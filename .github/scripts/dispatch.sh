#!/usr/bin/env bash
# Pipeline dispatcher: deterministic shell, no Claude. Spec: docs/process.md, "Dispatcher".
#
# Each run:
#   0. exit if PIPELINE_PAUSED=true
#   1. mirror board Status=Ready onto the `ready` label (so Tristan can promote from the board), unless the arc has open blockers
#   2. unblock: `blocked` arcs whose blockers are all closed become `ready`
#   2b. recover: a `claimed` arc whose build run died (no live run, no open arc PR, past the grace period) goes back to
#      `ready` once; orphaned again, it gets `needs-human`
#      An arc in its look gate (`look-review`, `look-approved`, `look-changes`) is never an orphan: it waits on
#      Tristan, or on a run that a label started, not the dispatcher's build
#   3. claim: drop a stray `ready` from arcs already claimed/in-review; while in-flight arcs < WORKER_CAP, claim the oldest `ready` arc whose
#      Touches: do not overlap an in-flight arc, and start a development run. An arc waiting on Tristan's look review
#      (`look-review`) does not count toward WORKER_CAP, but its Touches: still block overlapping arcs
#   3b. close approved concepts whose arcs are all closed (backstop for the review agent)
#   3c. close milestones (`M<n> · …`) whose sub-issues are all closed, once the last one has been closed for
#      MILESTONE_QUIET_HOURS (a milestone still receiving arcs is not closed between two of them)
#   4. project labels onto the board (agents touch labels only; this is the one writer of Status)
#   5. log anomalies (stale changes-requested PRs; open arcs closed-then-reopened or closed by a merged PR)
#   Board writes for any status but Done re-read the issue state fresh and skip a closed issue.
#
# Runs on label changes and closes (the primary clock) and a 30-minute cron (recovery).
#
# Env:  GH_TOKEN (PAT with repo + project scope), WORKER_CAP (default 2), PIPELINE_PAUSED,
#       PROJECT_NUMBER (default 1), STALE_MINUTES (default 30), ORPHAN_GRACE_MINUTES (default 15),
#       DEVELOPMENT_WORKFLOW (default role-development.yml), MILESTONE_QUIET_HOURS (default 24),
#       DRY_RUN=true to log mutations instead of doing them.
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-tsebens/silent_water}"
OWNER="${REPO%%/*}"
PROJECT_NUMBER="${PROJECT_NUMBER:-1}"
WORKER_CAP="${WORKER_CAP:-2}"
STALE_MINUTES="${STALE_MINUTES:-30}"
ORPHAN_GRACE_MINUTES="${ORPHAN_GRACE_MINUTES:-15}"
DEVELOPMENT_WORKFLOW="${DEVELOPMENT_WORKFLOW:-role-development.yml}"
MILESTONE_QUIET_HOURS="${MILESTONE_QUIET_HOURS:-24}"
DRY_RUN="${DRY_RUN:-false}"

# Shared-but-safe prefixes. Arcs routinely add a new test file or docs page, so naming the whole directory in
# Touches: would serialise arcs that only ever edit different files. A path in this list is compared by EXACT path
# only: `tests/unit` vs `tests/unit` does not overlap, `tests/unit/test_a.gd` vs `tests/unit/test_a.gd` does.
# Everything else, including all of src/, keeps the prefix-directory rule.
SHARED_PREFIXES=("docs" "tests" "tests/unit" "Silent Water — Design Doc.md")

if [ "${PIPELINE_PAUSED:-false}" = "true" ]; then
  echo "PIPELINE_PAUSED=true; nothing dispatched."
  exit 0
fi

log() { echo "$*"; }
act() { if [ "$DRY_RUN" = "true" ]; then log "    (dry) $*"; else "$@"; fi; }

# ---------------------------------------------------------------------------
# Issue helpers. ARCS is refreshed after every mutation that changes labels.
# ---------------------------------------------------------------------------

load_arcs() {
  ARCS=$(gh api --paginate "repos/$REPO/issues?state=open&labels=arc&per_page=100" \
    --jq '[.[] | select(.pull_request == null)
            | {number, title, created_at, body: (.body // ""), labels: [.labels[].name]}]' \
    | jq -s 'add // []')
}

arcs_with() { # label -> numbers, oldest first
  echo "$ARCS" | jq -r --arg l "$1" '[.[] | select(.labels | index($l))] | sort_by(.created_at) | .[].number'
}

arc_has() { # number label
  echo "$ARCS" | jq -e --argjson n "$1" --arg l "$2" '.[] | select(.number == $n) | .labels | index($l) != null' >/dev/null 2>&1
}

# The look gate (docs/asset_process.md, 6.5): a `look-gate` arc stops for Tristan before its PR.
LOOK_LABELS=("look-review" "look-approved" "look-changes")

in_look_phase() { # number -> 0 if the arc is between its build and its PR, in the look gate
  local l
  for l in "${LOOK_LABELS[@]}"; do arc_has "$1" "$l" && return 0; done
  return 1
}

# In-flight arcs that count toward WORKER_CAP: claimed or in-review, minus those waiting on Tristan's look review
# (no job is running for them). $1 = newline-separated in-flight numbers.
counting_toward_cap() {
  local n
  for n in $1; do arc_has "$n" look-review || echo "$n"; done
}

arc_body() { echo "$ARCS" | jq -r --argjson n "$1" '.[] | select(.number == $n) | .body'; }

add_label()    { log "    #$1 +$2"; act gh issue edit "$1" -R "$REPO" --add-label "$2" >/dev/null; }
remove_label() { log "    #$1 -$2"; act gh issue edit "$1" -R "$REPO" --remove-label "$2" >/dev/null; }
comment()      { act gh issue comment "$1" -R "$REPO" --body "$2" >/dev/null; }

issue_is_closed() { # number -> 0 if closed. A failed lookup (deleted, inaccessible) counts as still open.
  local state
  state=$(gh api "repos/$REPO/issues/$1" --jq .state 2>/dev/null) || { log "    #$1: lookup failed; treating as open"; return 1; }
  [ "$state" = "closed" ]
}

# "Touches: src/noise, src/sub/..." -> one normalised path per line.
touches_of() {
  arc_body "$1" | grep -i -m1 -E '^\**touches:?\**:?' | sed -E 's/^\**[Tt]ouches:?\**:?//' \
    | tr ',' '\n' | sed -E 's/`//g; s/^[[:space:]]+//; s/[[:space:]]+$//; s:/+$::' | grep -v '^$' || true
}

# Blockers = numbers on the "Blocked by:" line ∪ GitHub's native blocked-by dependencies.
blockers_of() {
  {
    arc_body "$1" | grep -i -m1 -E '^\**blocked by:?\**:?' | grep -oE '#[0-9]+' | tr -d '#' || true
    gh api "repos/$REPO/issues/$1/dependencies/blocked_by" --jq '.[].number' 2>/dev/null || true
  } | sort -un
}

# Open blockers of an arc, one token per line, read FRESH from the API (not the ARCS snapshot): "#<n>" for an open
# blocker, "?<why>" when the read cannot be trusted. Anything printed means "not promotable". A blocker read must
# never fail open: an arc created a moment ago can show an empty body or no dependencies (incident #564: #560 and
# #561 were promoted with open blockers), so the arc must carry an explicit, non-blank `Blocked by:` line ("none"
# is explicit) and the dependency read must succeed. Prints nothing only when every blocker is closed.
open_blockers_of() { # number
  local body line rest deps b
  body=$(gh api "repos/$REPO/issues/$1" --jq '.body // ""' 2>/dev/null) || { echo "?body-unreadable"; return 0; }
  line=$(grep -i -m1 -E '^\**blocked by:?\**:?' <<<"$body" || true)
  if [ -z "$line" ]; then echo "?no-blocked-by-line"; return 0; fi
  rest=$(sed -E 's/^\**[Bb]locked by:?\**:?//; s/[*[:space:]]+//g' <<<"$line")
  if [ -z "$rest" ]; then echo "?blank-blocked-by-line"; return 0; fi
  # Every entry must be `none` or `#<digits>`; a bare `#`, `Arc 3` or stray words make the line unreadable.
  for b in $(sed -E 's/^\**[Bb]locked by:?\**:?//; s/\*//g; s/,/ /g' <<<"$line"); do
    if ! grep -qiE '^(none|#[0-9]+)$' <<<"$b"; then echo "?malformed-blocked-by-line"; return 0; fi
  done
  deps=$(gh api "repos/$REPO/issues/$1/dependencies/blocked_by" --jq '.[].number' 2>/dev/null) || { echo "?dependencies-unreadable"; return 0; }
  for b in $( { grep -oE '#[0-9]+' <<<"$line" | tr -d '#' || true; echo "$deps"; } | grep -E '^[0-9]+$' | sort -un); do
    issue_is_closed "$b" || echo "#$b"
  done
}

# An arc never carries `ready` together with `claimed` or `in-review`: drop the stray `ready`.
# Returns 0 if it was dropped (the arc is in flight and must not be claimed again).
drop_stray_ready() { # number
  if arc_has "$1" claimed || arc_has "$1" in-review; then
    log "  #$1 already in flight; dropping stray ready"
    remove_label "$1" ready
    return 0
  fi
  return 1
}

# Two path lists overlap if any pair is equal or one is a prefix directory of the other, except for SHARED_PREFIXES.
paths_overlap() { # "list a (newline sep)" "list b"
  local a b
  while IFS= read -r a; do
    [ -z "$a" ] && continue
    while IFS= read -r b; do
      [ -z "$b" ] && continue
      if path_pair_overlaps "$a" "$b"; then return 0; fi
    done <<<"$2"
  done <<<"$1"
  return 1
}

path_pair_overlaps() { # a b
  local a="$1" b="$2" p
  if [ "$a" = "$b" ]; then
    for p in "${SHARED_PREFIXES[@]}"; do [ "$a" = "$p" ] && return 1; done
    return 0
  fi
  for p in "${SHARED_PREFIXES[@]}"; do
    # a shared prefix never claims its subtree; only identical file paths collide.
    if [ "$a" = "$p" ] || [ "$b" = "$p" ]; then return 1; fi
  done
  [[ "$a" == "$b"/* ]] || [[ "$b" == "$a"/* ]]
}

# ---------------------------------------------------------------------------
# Orphan recovery: a `claimed` arc whose development run died.
# ---------------------------------------------------------------------------

ORPHAN_MARKER="<!-- dispatcher:orphan-reverted -->"

# Latest "claimed and started a development run" comment on an arc -> "<created_at> <run id or ->", or nothing.
claim_info() { # number
  local row
  row=$(gh api --paginate "repos/$REPO/issues/$1/comments?per_page=100" \
    --jq '[.[] | select(.body | startswith("Dispatcher: claimed"))] | last // empty
          | "\(.created_at) \((.body | capture("actions/runs/(?<id>[0-9]+)").id) // "-")"' 2>/dev/null | tail -1) || return 0
  echo "$row"
}

# 0 if a development run for this arc is queued or in progress. Without a known run id, any live development run counts.
live_run_for() { # run-id-or-dash
  local status n
  if [ "$1" != "-" ]; then
    status=$(gh api "repos/$REPO/actions/runs/$1" --jq .status 2>/dev/null) || return 0  # lookup failed: assume alive
    case "$status" in queued|in_progress|waiting|pending|requested) return 0 ;; *) return 1 ;; esac
  fi
  n=$(gh api "repos/$REPO/actions/workflows/$DEVELOPMENT_WORKFLOW/runs?status=queued&per_page=1" --jq .total_count 2>/dev/null) || return 0
  [ "${n:-0}" -gt 0 ] && return 0
  n=$(gh api "repos/$REPO/actions/workflows/$DEVELOPMENT_WORKFLOW/runs?status=in_progress&per_page=1" --jq .total_count 2>/dev/null) || return 0
  [ "${n:-0}" -gt 0 ]
}

arc_reverted_before() { # number
  gh api --paginate "repos/$REPO/issues/$1/comments?per_page=100" --jq '.[].body' 2>/dev/null | grep -qF "$ORPHAN_MARKER"
}

# $1 = newline-separated arc numbers that have an open arc/<n>-* PR. Runs before Claim, so a revert frees its
# in-flight slot before the cap is computed and WORKER_CAP can never be exceeded by it.
recover_orphans() {
  local n info created run_id age grace=$((ORPHAN_GRACE_MINUTES * 60)) now
  now=$(date -u +%s)
  for n in $(arcs_with claimed); do
    arc_has "$n" needs-human && continue
    if in_look_phase "$n"; then log "  #$n claimed, in its look gate; not an orphan"; continue; fi
    if grep -qx "$n" <<<"$1"; then log "  #$n claimed, has an open PR; fine"; continue; fi
    info=$(claim_info "$n")
    if [ -z "$info" ]; then log "  #$n claimed with no dispatcher claim comment; cannot date it, leaving alone"; continue; fi
    created=${info%% *}; run_id=${info##* }
    age=$((now - $(date -u -d "$created" +%s)))
    if [ "$age" -lt "$grace" ]; then log "  #$n claimed ${age}s ago, inside the ${ORPHAN_GRACE_MINUTES}m grace period; fine"; continue; fi
    if live_run_for "$run_id"; then log "  #$n claimed, development run ${run_id} is live; fine"; continue; fi
    log "  #$n is an orphan: claimed since $created, run ${run_id} is not live and there is no open arc PR"
    if arc_reverted_before "$n"; then
      log "  #$n was already reverted once; escalating"
      log "    #$n comment: second orphaning notice"
      comment "$n" "Dispatcher: this arc was orphaned again (development run ${run_id} is dead, no open PR). It was already returned to \`ready\` once, so it needs a human."
      act gh issue edit "$n" -R "$REPO" --add-label needs-human --add-assignee tsebens >/dev/null
      log "    #$n +needs-human"
    else
      remove_label "$n" claimed
      add_label "$n" ready
      log "    #$n comment: orphan notice naming run ${run_id}"
      comment "$n" "Dispatcher: the development run for this arc (${run_id}) is dead and no PR exists; returning it to \`ready\` for another attempt. A second orphaning escalates to \`needs-human\`.
$ORPHAN_MARKER"
    fi
  done
}

# ---------------------------------------------------------------------------
# Board helpers (Projects v2 GraphQL).
# ---------------------------------------------------------------------------

load_board() {
  local after="null" page
  PROJECT_ITEMS="[]"
  while :; do
    page=$(gh api graphql -F owner="$OWNER" -F number="$PROJECT_NUMBER" -F after="$after" -f query='
      query($owner: String!, $number: Int!, $after: String) {
        user(login: $owner) { projectV2(number: $number) {
          id
          field(name: "Status") { ... on ProjectV2SingleSelectField { id options { id name } } }
          items(first: 100, after: $after) {
            pageInfo { hasNextPage endCursor }
            nodes {
              id
              status: fieldValueByName(name: "Status") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
              content { ... on Issue { number state repository { nameWithOwner } } }
            }
          }
        } }
      }')
    PROJECT_ID=$(echo "$page" | jq -r '.data.user.projectV2.id')
    STATUS_FIELD_ID=$(echo "$page" | jq -r '.data.user.projectV2.field.id')
    STATUS_OPTIONS=$(echo "$page" | jq -c '.data.user.projectV2.field.options')
    PROJECT_ITEMS=$(echo "$page" | jq -c --argjson acc "$PROJECT_ITEMS" --arg repo "$REPO" '
      $acc + [.data.user.projectV2.items.nodes[]
              | select(.content.repository.nameWithOwner == $repo)
              | {item_id: .id, number: .content.number, state: .content.state, status: (.status.name // "")}]')
    if [ "$(echo "$page" | jq -r '.data.user.projectV2.items.pageInfo.hasNextPage')" != "true" ]; then break; fi
    after=$(echo "$page" | jq -r '.data.user.projectV2.items.pageInfo.endCursor')
  done
}

board_numbers_with_status() { echo "$PROJECT_ITEMS" | jq -r --arg s "$1" '.[] | select(.status == $s) | .number'; }
board_state_of() { echo "$PROJECT_ITEMS" | jq -r --argjson n "$1" '.[] | select(.number == $n) | .state'; }

set_board_status() { # number status-name
  local item option
  item=$(echo "$PROJECT_ITEMS" | jq -r --argjson n "$1" '.[] | select(.number == $n) | .item_id')
  option=$(echo "$STATUS_OPTIONS" | jq -r --arg s "$2" '.[] | select(.name == $s) | .id')
  if [ -z "$item" ] || [ -z "$option" ]; then log "    #$1 not on board (or no option '$2'); status not set"; return; fi
  # An open status is never written onto a closed issue (a stale label or snapshot must not reopen a card). Two guards:
  # the board snapshot's content state, then a fresh REST read taken right before the mutation. A failed read skips.
  if [ "$2" != "Done" ]; then
    if [ "$(board_state_of "$1")" = "CLOSED" ]; then log "    #$1 is closed (board snapshot); not setting '$2'"; return; fi
    local fresh
    fresh=$(gh api "repos/$REPO/issues/$1" --jq .state 2>/dev/null) || { log "    #$1 state lookup failed; not setting '$2'"; return; }
    if [ "$fresh" = "closed" ]; then log "    #$1 is closed (fresh read); not setting '$2'"; return; fi
  fi
  log "    #$1 board -> $2"
  act gh api graphql -f project="$PROJECT_ID" -f item="$item" -f field="$STATUS_FIELD_ID" -f option="$option" -f query='
    mutation($project: ID!, $item: ID!, $field: ID!, $option: String!) {
      updateProjectV2ItemFieldValue(input: {projectId: $project, itemId: $item, fieldId: $field,
        value: {singleSelectOptionId: $option}}) { projectV2Item { id } }
    }' >/dev/null
}

# Concepts and Design: notes. `design` (still being thought through) is inert and always Backlog,
# even on a concept that somehow also carries plan-approved.
concept_status() { # newline-separated label names -> board status
  if grep -qx 'design' <<<"$1"; then echo "Backlog"
  elif grep -qx 'plan-approved' <<<"$1"; then echo "In progress"
  else echo "Backlog"; fi
}
# "Concept: #186" on an arc body's own line -> 186 (first number only), or nothing.
concept_of_body() { # body
  grep -i -m1 -E '^\**concept:?\**:?' <<<"$1" | grep -oE '#[0-9]+' | head -1 | tr -d '#' || true
}

# Open concepts to close: plan-approved, not needs-human, with at least one arc and every arc closed.
# $1 = JSON [{number, labels}] of open concepts, $2 = JSON [{number, state, body}] of arcs in any state.
closable_concepts() {
  local c n arc_states
  for n in $(echo "$1" | jq -r '.[] | select(.labels | index("plan-approved") and (index("needs-human") | not)) | .number'); do
    arc_states=""
    while IFS= read -r row; do
      [ -z "$row" ] && continue
      c=$(concept_of_body "$(jq -r '.body' <<<"$row")")
      [ "$c" = "$n" ] && arc_states="$arc_states $(jq -r '.state' <<<"$row")"
    done < <(echo "$2" | jq -c '.[]')
    [ -z "$arc_states" ] && continue
    case "$arc_states" in *open*|*OPEN*) continue ;; esac
    echo "$n"
  done
}

close_finished_concepts() { # same arguments as closable_concepts
  local n
  for n in $(closable_concepts "$1" "$2"); do
    # The snapshot may be stale: the reviewer can close a concept between it and here.
    if issue_is_closed "$n"; then log "  concept #$n already closed"; continue; fi
    log "  closing concept #$n: all arcs closed"
    act gh issue close "$n" -R "$REPO" --reason completed || log "    closing concept #$n failed; continuing"
  done
}

# Milestones are the `M<n> · …` parent issues (no label). One closes itself once all its sub-issues are closed.
is_milestone_title() { grep -qE '^M[0-9]+ · ' <<<"$1"; }

# When the milestone's last sub-issue was closed (ISO), or nothing if none is closed or the lookup fails.
milestone_last_closed() { # number
  gh api --paginate "repos/$REPO/issues/$1/sub_issues?per_page=100" --jq '.[] | .closed_at | select(. != null)' 2>/dev/null \
    | sort | tail -1
}

# Open milestones to close: not needs-human, at least one sub-issue, every sub-issue closed, and the last one
# closed at least MILESTONE_QUIET_HOURS ago. A milestone that is still receiving arcs is left open between them;
# one that gets new work after closing is reopened by whoever files the work.
# $1 = JSON [{number, title, labels, sub_issues_summary: {total, completed}}] of open issues, $2 = now (epoch s).
closable_milestones() {
  local n last age
  for n in $(echo "$1" | jq -r '.[] | select(.title | test("^M[0-9]+ · "))
      | select(.labels | index("needs-human") | not)
      | select((.sub_issues_summary.total // 0) > 0 and .sub_issues_summary.completed == .sub_issues_summary.total)
      | .number'); do
    last=$(milestone_last_closed "$n")
    [ -z "$last" ] && continue
    age=$(( $2 - $(date -u -d "$last" +%s) ))
    if [ "$age" -lt $((MILESTONE_QUIET_HOURS * 3600)) ]; then
      log "  milestone #$n finished $((age / 3600))h ago; closing after ${MILESTONE_QUIET_HOURS}h" >&2  # stdout is the number list
      continue
    fi
    echo "$n"
  done
}

close_finished_milestones() { # same arguments as closable_milestones
  local n
  for n in $(closable_milestones "$1" "$2"); do
    if issue_is_closed "$n"; then log "  milestone #$n already closed"; continue; fi
    log "  closing milestone #$n: all sub-issues closed"
    act gh issue close "$n" -R "$REPO" --reason completed || log "    closing milestone #$n failed; continuing"
  done
}

# ---------------------------------------------------------------------------
# Run.
# ---------------------------------------------------------------------------

# A malformed `Blocked by:` line cannot be trusted either way: escalate once (needs-human is terminal, so later
# passes skip the arc). $2 is the open_blockers_of output.
escalate_if_malformed() { # number open-blockers
  case "$2" in *'?malformed-blocked-by-line'*) ;; *) return 1 ;; esac
  log "  #$1 has a malformed Blocked by: line; escalating"
  add_label "$1" needs-human
  act gh issue edit "$1" -R "$REPO" --add-assignee tsebens >/dev/null
  return 0
}

# Step 1. A board Status of Ready puts an arc on the radar but never overrides open blockers, whoever set it.
mirror_board_ready() {
  local n open
  for n in $(board_numbers_with_status "Ready"); do
    arc_has "$n" arc || continue   # not an open arc (closed, or not labeled arc)
    if arc_has "$n" needs-human || arc_has "$n" claimed || arc_has "$n" in-review || arc_has "$n" ready; then continue; fi
    open=$(open_blockers_of "$n" | tr '\n' ' ')
    if escalate_if_malformed "$n" "$open"; then continue; fi
    if [ -n "$open" ]; then
      log "  #$n is Ready on the board but has open blockers (${open% }); not promoting, leaving it blocked"
      arc_has "$n" blocked || add_label "$n" blocked
      continue
    fi
    log "  #$n is Ready on the board; promoting"
    arc_has "$n" blocked && remove_label "$n" blocked
    add_label "$n" ready
  done
}

# Step 2. `blocked` arcs whose blockers are all closed (and readable) become ready.
unblock_arcs() {
  local n open
  for n in $(arcs_with blocked); do
    arc_has "$n" needs-human && continue
    open=$(open_blockers_of "$n" | tr '\n' ' ')
    if escalate_if_malformed "$n" "$open"; then continue; fi
    if [ -z "$open" ]; then
      log "  #$n: all blockers closed"
      remove_label "$n" blocked
      add_label "$n" ready
      set_board_status "$n" "Ready"
    else
      log "  #$n: waiting on ${open% }"
    fi
  done
}

pr_has() { echo "$PR_LABELS" | jq -e --argjson n "$1" --arg l "$2" '.[] | select(.arc == $n) | .labels | index($l) != null' >/dev/null 2>&1; }

# Add an issue to the board if it is not there yet (plan review creates arcs without touching
# the board; the board is the dispatcher's to keep). Appends the new item to PROJECT_ITEMS.
ensure_on_board() { # number
  if echo "$PROJECT_ITEMS" | jq -e --argjson n "$1" '.[] | select(.number == $n)' >/dev/null; then return 0; fi
  local content item
  content=$(gh api "repos/$REPO/issues/$1" --jq .node_id 2>/dev/null) || return 1
  log "    #$1 not on the board; adding"
  if [ "$DRY_RUN" = "true" ]; then return 1; fi
  item=$(gh api graphql -F project="$PROJECT_ID" -F content="$content" -f query='
    mutation($project: ID!, $content: ID!) {
      addProjectV2ItemById(input: {projectId: $project, contentId: $content}) { item { id } }
    }' --jq '.data.addProjectV2ItemById.item.id') || return 1
  PROJECT_ITEMS=$(echo "$PROJECT_ITEMS" | jq -c --arg id "$item" --argjson n "$1" '. + [{item_id: $id, number: $n, state: "OPEN", status: ""}]')
}

project() { # number wanted-status
  local current
  ensure_on_board "$1" || return 0
  current=$(echo "$PROJECT_ITEMS" | jq -r --argjson n "$1" '.[] | select(.number == $n) | .status')
  [ "$current" = "$2" ] && return 0
  set_board_status "$1" "$2"
}

project_arc_labels() {
  local n
  for n in $(echo "$ARCS" | jq -r '.[].number'); do
    arc_has "$n" needs-human && continue
    if arc_has "$n" in-review; then
      if pr_has "$n" changes-requested; then project "$n" "In progress"; else project "$n" "In review"; fi
    elif arc_has "$n" claimed && arc_has "$n" look-review; then project "$n" "In review"
    elif arc_has "$n" claimed; then project "$n" "In progress"
    elif arc_has "$n" ready;   then project "$n" "Ready"
    elif arc_has "$n" blocked; then project "$n" "Backlog"
    fi
  done
}

# Step 5 anomaly: an open arc whose timeline shows `closed` then `reopened` within a minute (something closed and
# reopened it, so a card may have flickered), or that has a merged PR saying `Closes #<n>` (it should be closed).
# $1 = arc number, $2 = normalised timeline JSON [{event, created_at, merged_at, body}] from arc_timeline.
log_arc_anomalies() {
  local n="$1" row
  row=$(jq -r '[.[] | select(.event == "closed" or .event == "reopened")] as $e
    | [range(1; $e | length) | select($e[.-1].event == "closed" and $e[.].event == "reopened"
        and (($e[.].created_at | fromdateiso8601) - ($e[.-1].created_at | fromdateiso8601)) <= 60)] | length' <<<"$2")
  if [ "${row:-0}" -gt 0 ]; then log "  anomaly: open arc #$n was closed then reopened within a minute"; fi
  row=$(jq -r --arg n "$n" '[.[] | select(.event == "cross-referenced" and .merged_at != null
      and ((.body // "") | test("(?i)\\b(close[sd]?|fix(e[sd])?|resolve[sd]?)[: ]+#" + $n + "\\b")))] | first | .merged_at // empty' <<<"$2")
  if [ -n "$row" ]; then log "  anomaly: open arc #$n has a PR merged at $row with Closes #$n"; fi
}

arc_timeline() { # number -> normalised timeline JSON, "[]" if the read fails
  gh api --paginate "repos/$REPO/issues/$1/timeline?per_page=100" \
    --jq '[.[] | select(.event == "closed" or .event == "reopened" or .event == "cross-referenced")
           | {event, created_at, merged_at: (.source.issue.pull_request.merged_at // null), body: (.source.issue.body // "")}]' \
    2>/dev/null | jq -s 'add // []' 2>/dev/null || echo "[]"
}

# Tests source this file with DISPATCH_LIB_ONLY=1 to get the functions without running.
if [ "${DISPATCH_LIB_ONLY:-}" = "1" ]; then return 0; fi

log "Dispatcher: repo=$REPO cap=$WORKER_CAP dry_run=$DRY_RUN"
load_arcs
load_board

log "1. Mirror board Ready -> label ready"
mirror_board_ready
load_arcs

log "2. Unblock"
unblock_arcs
load_arcs

log "2b. Recover orphaned claims"
OPEN_ARC_PRS=$(gh api --paginate "repos/$REPO/pulls?state=open&per_page=100" \
  --jq '.[] | select(.head.ref | test("^arc/[0-9]+-")) | .head.ref | capture("^arc/(?<n>[0-9]+)-").n' || true)
recover_orphans "$OPEN_ARC_PRS"
load_arcs

log "3. Claim"
in_flight=$( { arcs_with claimed; arcs_with in-review; } | sort -un)
in_flight_count=$(counting_toward_cap "$in_flight" | grep -c . || true)
in_flight_touches=""
for n in $in_flight; do
  t=$(touches_of "$n")
  if [ -z "$t" ]; then log "  #$n is in flight with no Touches: line; treating as touching everything"; t="."; fi
  in_flight_touches="$in_flight_touches"$'\n'"$t"
done
log "  in flight: $in_flight_count/$WORKER_CAP ($(echo "$in_flight" | tr '\n' ' '); look-review arcs hold Touches: but no slot)"

DEFAULT_BRANCH=$(gh api "repos/$REPO" --jq .default_branch 2>/dev/null || echo dev)

# Start one development run for an arc. Prints the run URL (best effort) on success.
start_development() { # arc number
  gh workflow run "$DEVELOPMENT_WORKFLOW" -R "$REPO" --ref "$DEFAULT_BRANCH" -f "arc=$1" || return 1
  sleep 5
  gh run list -R "$REPO" --workflow "$DEVELOPMENT_WORKFLOW" --event workflow_dispatch --limit 1 \
    --json url --jq '.[0].url // empty' 2>/dev/null || true
}

for n in $(arcs_with ready); do
  drop_stray_ready "$n" && continue
  [ "$in_flight_count" -lt "$WORKER_CAP" ] || continue
  arc_has "$n" needs-human && continue
  open=$(open_blockers_of "$n" | tr '\n' ' ')
  if escalate_if_malformed "$n" "$open"; then continue; fi
  if [ -n "$open" ]; then log "  #$n is ready but has open blockers (${open% }); not claiming"; continue; fi
  t=$(touches_of "$n")
  if [ -z "$t" ]; then log "  #$n has no Touches: line; treating as touching everything"; t="."; fi
  # "." means "touches everything": it blocks, and is blocked by, every other arc.
  if [ -n "$(echo "$in_flight_touches" | grep -v '^$')" ] && \
     { [ "$t" = "." ] || grep -qx '\.' <<<"$in_flight_touches" || paths_overlap "$t" "$in_flight_touches"; }; then
    log "  #$n overlaps an in-flight arc; skipping"
    continue
  fi
  log "  claiming #$n"
  remove_label "$n" ready
  add_label "$n" claimed
  if [ "$DRY_RUN" = "true" ]; then
    run_url="(dry run)"
  elif ! run_url=$(start_development "$n"); then
    log "  could not start a development run for #$n; reverting to ready"
    remove_label "$n" claimed
    add_label "$n" ready
    continue
  fi
  comment "$n" "Dispatcher: claimed and started a development run${run_url:+: $run_url}"
  in_flight_count=$((in_flight_count + 1))
  in_flight_touches="$in_flight_touches"$'\n'"$t"
done

log "3b. Close concepts whose arcs are all closed"
OPEN_CONCEPTS=$(gh api --paginate "repos/$REPO/issues?state=open&labels=concept&per_page=100" \
  --jq '[.[] | select(.pull_request == null) | {number, labels: [.labels[].name]}]' | jq -s 'add // []')
ALL_ARCS=$(gh api --paginate "repos/$REPO/issues?state=all&labels=arc&per_page=100" \
  --jq '[.[] | select(.pull_request == null) | {number, state, body: (.body // "")}]' | jq -s 'add // []')
close_finished_concepts "$OPEN_CONCEPTS" "$ALL_ARCS"

log "3c. Close milestones whose sub-issues are all closed"
OPEN_ISSUES=$(gh api --paginate "repos/$REPO/issues?state=open&per_page=100" \
  --jq '[.[] | select(.pull_request == null) | {number, title, labels: [.labels[].name], sub_issues_summary}]' | jq -s 'add // []')
close_finished_milestones "$OPEN_ISSUES" "$(date -u +%s)"

log "4. Project labels onto the board"
load_arcs
load_board
# Open PR labels, keyed by arc number (from the arc/<n>- branch prefix), for the in-review split.
PR_LABELS=$(gh api --paginate "repos/$REPO/pulls?state=open&base=dev&per_page=100" \
  --jq '[.[] | select(.head.ref | test("^arc/[0-9]+-")) | {arc: (.head.ref | capture("^arc/(?<n>[0-9]+)-").n | tonumber), labels: [.labels[].name]}]' \
  | jq -s 'add // []')

project_arc_labels
CONCEPTS=$({ for l in concept design; do
  gh api --paginate "repos/$REPO/issues?state=open&labels=$l&per_page=100" \
    --jq '[.[] | select(.pull_request == null) | {number, labels: [.labels[].name]}]'
  done; } | jq -s 'add // [] | unique_by(.number)')
for n in $(echo "$CONCEPTS" | jq -r '.[].number'); do
  project "$n" "$(concept_status "$(echo "$CONCEPTS" | jq -r --argjson n "$n" '.[] | select(.number == $n) | .labels[]')")"
done
# Recently closed arcs, concepts and milestones are Done, and a closed arc carries no state label.
since=$(date -u -d '3 days ago' +%Y-%m-%dT%H:%M:%SZ)
CLOSED=$(gh api --paginate "repos/$REPO/issues?state=closed&since=$since&per_page=100" \
  --jq '[.[] | select(.pull_request == null) | select(([.labels[].name] | (index("arc") != null or index("concept") != null)) or (.title | test("^M[0-9]+ · "))) | {number, labels: [.labels[].name]}]' \
  | jq -s 'add // []')
for n in $(echo "$CLOSED" | jq -r '.[].number'); do
  project "$n" "Done"
  for l in ready claimed in-review blocked look-review look-approved look-changes; do
    if echo "$CLOSED" | jq -e --argjson n "$n" --arg l "$l" '.[] | select(.number == $n) | .labels | index($l) != null' >/dev/null; then
      remove_label "$n" "$l"
    fi
  done
done

log "5. Anomalies (logged, not acted on)"
now=$(date -u +%s)
stale_before=$((now - STALE_MINUTES * 60))
for pr in $(gh api --paginate "repos/$REPO/pulls?state=open&base=dev&per_page=100" \
    --jq '.[] | select([.labels[].name] | index("changes-requested")) | .number'); do
  applied=$(gh api --paginate "repos/$REPO/issues/$pr/events?per_page=100" \
    --jq '[.[] | select(.event == "labeled" and .label.name == "changes-requested")] | last | .created_at // empty')
  [ -z "$applied" ] && continue
  if [ "$(date -u -d "$applied" +%s)" -lt "$stale_before" ]; then
    log "  PR #$pr has had changes-requested since $applied with no rework run clearing it; check the rework workflow's runs"
  fi
done

for n in $(echo "$ARCS" | jq -r '.[].number'); do
  log_arc_anomalies "$n" "$(arc_timeline "$n")"
done

log "Dispatcher done."
