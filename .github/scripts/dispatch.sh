#!/usr/bin/env bash
# Pipeline dispatcher: deterministic shell, no Claude. Spec: docs/process.md, "Dispatcher".
#
# Each run:
#   0. exit if PIPELINE_PAUSED=true
#   1. mirror board Status=Ready onto the `ready` label (so Tristan can promote from the board)
#   2. unblock: `blocked` arcs whose blockers are all closed become `ready`
#   3. claim: while in-flight arcs < WORKER_CAP, claim the oldest `ready` arc whose
#      Touches: do not overlap an in-flight arc, and start a development run
#   4. project labels onto the board (agents touch labels only; this is the one writer of Status)
#   5. log anomalies (stale changes-requested PRs)
#
# Runs on label changes and closes (the primary clock) and a 30-minute cron (recovery).
#
# Env:  GH_TOKEN (PAT with repo + project scope), WORKER_CAP (default 2), PIPELINE_PAUSED,
#       PROJECT_NUMBER (default 1), STALE_MINUTES (default 30),
#       DEVELOPMENT_WORKFLOW (default role-development.yml),
#       DRY_RUN=true to log mutations instead of doing them.
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-tsebens/silent_water}"
OWNER="${REPO%%/*}"
PROJECT_NUMBER="${PROJECT_NUMBER:-1}"
WORKER_CAP="${WORKER_CAP:-2}"
STALE_MINUTES="${STALE_MINUTES:-30}"
DEVELOPMENT_WORKFLOW="${DEVELOPMENT_WORKFLOW:-role-development.yml}"
DRY_RUN="${DRY_RUN:-false}"

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

# Two path lists overlap if any pair is equal or one is a prefix directory of the other.
paths_overlap() { # "list a (newline sep)" "list b"
  local a b
  while IFS= read -r a; do
    [ -z "$a" ] && continue
    while IFS= read -r b; do
      [ -z "$b" ] && continue
      if [ "$a" = "$b" ] || [[ "$a" == "$b"/* ]] || [[ "$b" == "$a"/* ]]; then return 0; fi
    done <<<"$2"
  done <<<"$1"
  return 1
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
  log "    #$1 board -> $2"
  act gh api graphql -F project="$PROJECT_ID" -F item="$item" -F field="$STATUS_FIELD_ID" -F option="$option" -f query='
    mutation($project: ID!, $item: ID!, $field: ID!, $option: String!) {
      updateProjectV2ItemFieldValue(input: {projectId: $project, itemId: $item, fieldId: $field,
        value: {singleSelectOptionId: $option}}) { projectV2Item { id } }
    }' >/dev/null
}

# ---------------------------------------------------------------------------
# Run.
# ---------------------------------------------------------------------------

# Tests source this file with DISPATCH_LIB_ONLY=1 to get the functions without running.
if [ "${DISPATCH_LIB_ONLY:-}" = "1" ]; then return 0; fi

log "Dispatcher: repo=$REPO cap=$WORKER_CAP dry_run=$DRY_RUN"
load_arcs
load_board

log "1. Mirror board Ready -> label ready"
for n in $(board_numbers_with_status "Ready"); do
  arc_has "$n" arc || continue   # not an open arc (closed, or not labeled arc)
  if arc_has "$n" needs-human || arc_has "$n" claimed || arc_has "$n" in-review || arc_has "$n" ready; then continue; fi
  log "  #$n is Ready on the board; promoting"
  arc_has "$n" blocked && remove_label "$n" blocked
  add_label "$n" ready
done
load_arcs

log "2. Unblock"
for n in $(arcs_with blocked); do
  arc_has "$n" needs-human && continue
  open_blockers=""
  for b in $(blockers_of "$n"); do
    issue_is_closed "$b" || open_blockers="$open_blockers #$b"
  done
  if [ -z "$open_blockers" ]; then
    log "  #$n: all blockers closed"
    remove_label "$n" blocked
    add_label "$n" ready
    set_board_status "$n" "Ready"
  else
    log "  #$n: waiting on$open_blockers"
  fi
done
load_arcs

log "3. Claim"
in_flight=$( { arcs_with claimed; arcs_with in-review; } | sort -un)
in_flight_count=$(echo "$in_flight" | grep -c . || true)
in_flight_touches=""
for n in $in_flight; do
  t=$(touches_of "$n")
  if [ -z "$t" ]; then log "  #$n is in flight with no Touches: line; treating as touching everything"; t="."; fi
  in_flight_touches="$in_flight_touches"$'\n'"$t"
done
log "  in flight: $in_flight_count/$WORKER_CAP ($(echo "$in_flight" | tr '\n' ' '))"

DEFAULT_BRANCH=$(gh api "repos/$REPO" --jq .default_branch 2>/dev/null || echo dev)

# Start one development run for an arc. Prints the run URL (best effort) on success.
start_development() { # arc number
  gh workflow run "$DEVELOPMENT_WORKFLOW" -R "$REPO" --ref "$DEFAULT_BRANCH" -f "arc=$1" || return 1
  sleep 5
  gh run list -R "$REPO" --workflow "$DEVELOPMENT_WORKFLOW" --event workflow_dispatch --limit 1 \
    --json url --jq '.[0].url // empty' 2>/dev/null || true
}

for n in $(arcs_with ready); do
  [ "$in_flight_count" -lt "$WORKER_CAP" ] || break
  arc_has "$n" needs-human && continue
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

log "4. Project labels onto the board"
load_arcs
load_board
# Open PR labels, keyed by arc number (from the arc/<n>- branch prefix), for the in-review split.
PR_LABELS=$(gh api --paginate "repos/$REPO/pulls?state=open&base=dev&per_page=100" \
  --jq '[.[] | select(.head.ref | test("^arc/[0-9]+-")) | {arc: (.head.ref | capture("^arc/(?<n>[0-9]+)-").n | tonumber), labels: [.labels[].name]}]' \
  | jq -s 'add // []')
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

for n in $(echo "$ARCS" | jq -r '.[].number'); do
  arc_has "$n" needs-human && continue
  if arc_has "$n" in-review; then
    if pr_has "$n" changes-requested; then project "$n" "In progress"; else project "$n" "In review"; fi
  elif arc_has "$n" claimed; then project "$n" "In progress"
  elif arc_has "$n" ready;   then project "$n" "Ready"
  elif arc_has "$n" blocked; then project "$n" "Backlog"
  fi
done
CONCEPTS=$(gh api --paginate "repos/$REPO/issues?state=open&labels=concept&per_page=100" \
  --jq '[.[] | select(.pull_request == null) | {number, labels: [.labels[].name]}]' | jq -s 'add // []')
for n in $(echo "$CONCEPTS" | jq -r '.[].number'); do
  if echo "$CONCEPTS" | jq -e --argjson n "$n" '.[] | select(.number == $n) | .labels | index("plan-approved") != null' >/dev/null; then
    project "$n" "In progress"
  else
    project "$n" "Backlog"
  fi
done
# Recently closed arcs and concepts are Done, and a closed arc carries no state label.
since=$(date -u -d '3 days ago' +%Y-%m-%dT%H:%M:%SZ)
CLOSED=$(gh api --paginate "repos/$REPO/issues?state=closed&since=$since&per_page=100" \
  --jq '[.[] | select(.pull_request == null) | select([.labels[].name] | (index("arc") != null or index("concept") != null)) | {number, labels: [.labels[].name]}]' \
  | jq -s 'add // []')
for n in $(echo "$CLOSED" | jq -r '.[].number'); do
  project "$n" "Done"
  for l in ready claimed in-review blocked; do
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

log "Dispatcher done."
