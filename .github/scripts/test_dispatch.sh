#!/usr/bin/env bash
# Unit tests for the pure parts of dispatch.sh (parsing and overlap). No network.
# Usage: .github/scripts/test_dispatch.sh
set -uo pipefail
cd "$(dirname "$0")"

gh() { echo "gh must not be called by these tests: gh $*" >&2; return 1; }
export -f gh
# shellcheck source=dispatch.sh
DISPATCH_LIB_ONLY=1 PIPELINE_PAUSED=false source ./dispatch.sh
set +e  # dispatch.sh sets -e; the tests below check non-zero returns deliberately

fails=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1"; echo "      expected: $(printf %q "$2")"; echo "      actual:   $(printf %q "$3")"; fails=1; fi
}

ARCS=$(cat <<'EOF'
[
  {"number": 1, "created_at": "2026-01-01T00:00:00Z", "labels": ["arc","ready"],
   "body": "Scope: x\nTouches: src/noise, `src/sub/`, tests/unit\nBlocked by: none\n"},
  {"number": 2, "created_at": "2026-01-02T00:00:00Z", "labels": ["arc","blocked"],
   "body": "**Touches:** src/noise/sources\n**Blocked by:** #1, #7 and Arc 3\n"},
  {"number": 3, "created_at": "2026-01-03T00:00:00Z", "labels": ["arc","claimed"],
   "body": "No touches line here.\n"},
  {"number": 4, "created_at": "2025-12-31T00:00:00Z", "labels": ["arc","ready"],
   "body": "Touches: docs\n"}
]
EOF
)

check "touches: comma list, backticks, trailing slash" $'src/noise\nsrc/sub\ntests/unit' "$(touches_of 1)"
check "touches: bold markdown" "src/noise/sources" "$(touches_of 2)"
check "touches: missing line is empty" "" "$(touches_of 3)"
check "arcs_with sorts oldest first" $'4\n1' "$(arcs_with ready)"
arc_has 1 ready; check "arc_has present" 0 $?
arc_has 1 blocked; check "arc_has absent" 1 $?

paths_overlap $'src/noise' $'src/noise/sources'; check "overlap: parent vs child" 0 $?
paths_overlap $'src/noise/sources' $'src/noise'; check "overlap: child vs parent" 0 $?
paths_overlap $'src/noise' $'src/noisemaker'; check "overlap: shared prefix is not a directory" 1 $?
paths_overlap $'src/noise\nsrc/sub' $'docs\nsrc/sub/pilot'; check "overlap: any pair" 0 $?
paths_overlap $'docs' $'src/noise'; check "overlap: disjoint" 1 $?
paths_overlap "" $'src/noise'; check "overlap: empty list" 1 $?
paths_overlap $'tests/unit' $'tests/unit'; check "overlap: shared tests/unit twice" 1 $?
paths_overlap $'docs' $'docs'; check "overlap: shared docs twice" 1 $?
paths_overlap $'tests/unit/test_a.gd' $'tests/unit/test_a.gd'; check "overlap: same test file" 0 $?
paths_overlap $'tests/unit/test_a.gd' $'tests/unit/test_b.gd'; check "overlap: different test files" 1 $?
paths_overlap $'tests/unit' $'tests/unit/test_a.gd'; check "overlap: shared dir vs its file" 1 $?
paths_overlap $'docs/process.md' $'docs/process.md'; check "overlap: same docs file" 0 $?
paths_overlap $'src/sub' $'src/sub/foo.gd'; check "overlap: src parent vs file" 0 $?
paths_overlap $'src/sub' $'src/noise'; check "overlap: src siblings" 1 $?

# The look gate: an arc waiting on Tristan keeps its Touches: but holds no WORKER_CAP slot, and no look-gate arc
# between its build and its PR is ever an orphan.
SAVED_ARCS="$ARCS"
ARCS=$(cat <<'EOF2'
[
  {"number": 10, "created_at": "2026-01-01T00:00:00Z", "labels": ["arc","claimed"], "body": "Touches: src/a\n"},
  {"number": 11, "created_at": "2026-01-02T00:00:00Z", "labels": ["arc","claimed","look-gate","look-review"], "body": "Touches: src/b\n"},
  {"number": 12, "created_at": "2026-01-03T00:00:00Z", "labels": ["arc","claimed","look-gate","look-changes"], "body": "Touches: src/c\n"},
  {"number": 13, "created_at": "2026-01-04T00:00:00Z", "labels": ["arc","claimed","look-gate","look-approved"], "body": "Touches: src/d\n"},
  {"number": 14, "created_at": "2026-01-05T00:00:00Z", "labels": ["arc","claimed","look-gate"], "body": "Touches: src/e\n"}
]
EOF2
)
check "cap: look-review holds no slot; look-changes and look-approved runs do" $'10\n12\n13\n14' "$(counting_toward_cap $'10\n11\n12\n13\n14')"
in_look_phase 11; check "look phase: look-review" 0 $?
in_look_phase 12; check "look phase: look-changes" 0 $?
in_look_phase 13; check "look phase: look-approved" 0 $?
in_look_phase 14; check "look phase: a look-gate arc still building is not" 1 $?
in_look_phase 10; check "look phase: ordinary arc" 1 $?
ARCS="$SAVED_ARCS"

# blockers_of unions the body line with the native dependency API; stub the API call.
gh() { if [[ "$*" == *dependencies/blocked_by* ]]; then echo 9; echo 1; else return 1; fi; }
check "blockers: body numbers ∪ native, de-duplicated, sorted" $'1\n7\n9' "$(blockers_of 2)"
gh() { return 1; }
check "blockers: none and API failure" "" "$(blockers_of 1)"

check "concept_status: design is Backlog" "Backlog" "$(concept_status $'design')"
check "concept_status: design beats plan-approved" "Backlog" "$(concept_status $'concept\ndesign\nplan-approved')"
check "concept_status: plan-approved is In progress" "In progress" "$(concept_status $'concept\nplan-approved')"
check "concept_status: plain concept is Backlog" "Backlog" "$(concept_status $'concept')"

# closable_concepts: arcs in any state, linked by the "Concept: #n" line.
CONCEPTS_FIX='[{"number":10,"labels":["concept","plan-approved"]},{"number":11,"labels":["concept","plan-approved"]},
  {"number":12,"labels":["concept","plan-approved"]},{"number":13,"labels":["concept","plan-approved","needs-human"]},
  {"number":14,"labels":["concept"]}]'
ARCS_FIX='[{"number":20,"state":"closed","body":"Touches: x\nConcept: #10\n"},
  {"number":21,"state":"closed","body":"**Concept:** #10\n"},
  {"number":22,"state":"closed","body":"Concept: #11\n"},
  {"number":23,"state":"open","body":"Concept: #11\n"},
  {"number":24,"state":"closed","body":"Concept: #13\n"},
  {"number":25,"state":"closed","body":"Concept: #14\n"},
  {"number":26,"state":"closed","body":"Mentions #12 in Scope\nConcept: #99\n"}]'
check "closable: all arcs closed closes; open arc, no arcs, needs-human, unapproved stay" "10" "$(closable_concepts "$CONCEPTS_FIX" "$ARCS_FIX")"
check "closable: already-closed concepts are not in the open list (idempotent)" "" "$(closable_concepts '[]' "$ARCS_FIX")"

# The pass itself: closes with reason completed, logs the line; dry run logs without closing.
CALLS=$(mktemp)
gh() { if [[ "$*" == "api repos/$REPO/issues/10 --jq .state" ]]; then echo open; else echo "gh $*" >>"$CALLS"; fi; }
out=$(close_finished_concepts "$CONCEPTS_FIX" "$ARCS_FIX")
check "close pass: closes only #10 with reason completed" "gh issue close 10 -R $REPO --reason completed" "$(cat "$CALLS")"
check "close pass: log line" "  closing concept #10: all arcs closed" "$out"
: >"$CALLS"
DRY_RUN=true
out=$(close_finished_concepts "$CONCEPTS_FIX" "$ARCS_FIX")
check "dry run: nothing closed" "" "$(cat "$CALLS")"
check "dry run: would-close line logged" $'  closing concept #10: all arcs closed\n    (dry) gh issue close 10 -R '"$REPO"' --reason completed' "$out"
DRY_RUN=false

# Concept already closed since the snapshot: no close call, logged, returns 0.
: >"$CALLS"
gh() { if [[ "$*" == *"issues/10 --jq .state" ]]; then echo closed; else echo "gh $*" >>"$CALLS"; fi; }
out=$(close_finished_concepts "$CONCEPTS_FIX" "$ARCS_FIX"); rc=$?
check "already closed: no close call" "" "$(cat "$CALLS")"
check "already closed: logged" "  concept #10 already closed" "$out"
check "already closed: returns 0" 0 $rc

# The close call itself fails: logged and swallowed.
gh() { if [[ "$*" == *"issues/10 --jq .state" ]]; then echo open; else return 1; fi; }
out=$(close_finished_concepts "$CONCEPTS_FIX" "$ARCS_FIX"); rc=$?
check "close failure: logged" $'  closing concept #10: all arcs closed\n    closing concept #10 failed; continuing' "$out"
check "close failure: returns 0" 0 $rc
rm -f "$CALLS"

# closable_milestones: title `M<n> · …`, all sub-issues closed, past the quiet period. The sub-issue lookup is stubbed.
NOW=$(date -u -d 2026-01-10T00:00:00Z +%s)
MILESTONES_FIX='[{"number":50,"title":"M1 · done long ago","labels":[],"sub_issues_summary":{"total":3,"completed":3}},
  {"number":51,"title":"M2 · one still open","labels":[],"sub_issues_summary":{"total":3,"completed":2}},
  {"number":52,"title":"M3 · no sub-issues yet","labels":[],"sub_issues_summary":{"total":0,"completed":0}},
  {"number":53,"title":"M4 · finished an hour ago","labels":[],"sub_issues_summary":{"total":1,"completed":1}},
  {"number":54,"title":"M5 · needs a human","labels":["needs-human"],"sub_issues_summary":{"total":1,"completed":1}},
  {"number":55,"title":"M6.1 · an arc, not a milestone","labels":["arc"],"sub_issues_summary":{"total":1,"completed":1}},
  {"number":56,"title":"Concept: not a milestone","labels":["concept"],"sub_issues_summary":{"total":2,"completed":2}},
  {"number":57,"title":"M7 · summary missing","labels":[]}]'
gh() {
  case "$*" in
    *issues/50/sub_issues*) printf '2026-01-01T00:00:00Z\n2025-12-30T00:00:00Z\n' ;;
    *issues/53/sub_issues*) echo 2026-01-09T23:00:00Z ;;
    *) echo "gh must not be called here: gh $*" >&2; return 1 ;;
  esac
}
check "milestones: only finished, quiet, unlabelled parents close" "50" "$(closable_milestones "$MILESTONES_FIX" "$NOW" 2>/dev/null)"
check "milestones: a young finish is logged (stderr), not closed" "  milestone #53 finished 1h ago; closing after 24h" "$(closable_milestones "$MILESTONES_FIX" "$NOW" 2>&1 >/dev/null)"
MILESTONE_QUIET_HOURS=0
check "milestones: quiet period 0 closes the young one too" $'50\n53' "$(closable_milestones "$MILESTONES_FIX" "$NOW" 2>/dev/null)"
MILESTONE_QUIET_HOURS=24
is_milestone_title "M10 · Asset Studio"; check "milestone title: M<n> · name" 0 $?
is_milestone_title "M10.3 · Arc"; check "milestone title: arc is not one" 1 $?

# The pass: closes with reason completed; dry run logs; already closed and failures are logged and swallowed.
CALLS=$(mktemp)
gh() {
  case "$*" in
    *issues/50/sub_issues*) echo 2026-01-01T00:00:00Z ;;
    *issues/53/sub_issues*) echo 2026-01-09T23:00:00Z ;;
    *"issues/50 --jq .state") echo open ;;
    *) echo "gh $*" >>"$CALLS" ;;
  esac
}
out=$(close_finished_milestones "$MILESTONES_FIX" "$NOW" 2>/dev/null)
check "milestone pass: closes only #50 with reason completed" "gh issue close 50 -R $REPO --reason completed" "$(cat "$CALLS")"
check "milestone pass: log line" 1 "$(grep -c '^  closing milestone #50: all sub-issues closed$' <<<"$out")"
: >"$CALLS"
DRY_RUN=true
out=$(close_finished_milestones "$MILESTONES_FIX" "$NOW" 2>/dev/null)
check "milestone dry run: nothing closed" "" "$(cat "$CALLS")"
check "milestone dry run: would-close logged" 1 "$(grep -c "(dry) gh issue close 50 -R $REPO --reason completed" <<<"$out")"
DRY_RUN=false
: >"$CALLS"
gh() { case "$*" in *issues/50/sub_issues*) echo 2026-01-01T00:00:00Z ;; *sub_issues*) echo 2026-01-09T23:00:00Z ;; *"issues/50 --jq .state") echo closed ;; *) echo "gh $*" >>"$CALLS" ;; esac; }
out=$(close_finished_milestones "$MILESTONES_FIX" "$NOW" 2>/dev/null); rc=$?
check "milestone already closed: no close call" "" "$(cat "$CALLS")"
check "milestone already closed: logged" 1 "$(grep -c '^  milestone #50 already closed$' <<<"$out")"
check "milestone already closed: returns 0" 0 $rc
gh() { case "$*" in *issues/50/sub_issues*) echo 2026-01-01T00:00:00Z ;; *sub_issues*) echo 2026-01-09T23:00:00Z ;; *"issues/50 --jq .state") echo open ;; *) return 1 ;; esac; }
out=$(close_finished_milestones "$MILESTONES_FIX" "$NOW" 2>/dev/null); rc=$?
check "milestone close failure: logged" 1 "$(grep -c '^    closing milestone #50 failed; continuing$' <<<"$out")"
check "milestone close failure: returns 0" 0 $rc
# A sub-issue lookup that fails (or finds nothing closed) never closes.
gh() { case "$*" in *sub_issues*) return 1 ;; *) echo "gh $*" >>"$CALLS" ;; esac; }
: >"$CALLS"
check "milestones: failed sub-issue lookup closes nothing" "" "$(closable_milestones "$MILESTONES_FIX" "$NOW")"
rm -f "$CALLS"

# Stray ready: an arc with ready + claimed (or in-review) loses ready and is not claimed again.
ARCS='[{"number":30,"created_at":"2026-01-01T00:00:00Z","body":"","labels":["arc","ready","claimed"]},
  {"number":31,"created_at":"2026-01-01T00:00:00Z","body":"","labels":["arc","ready","in-review"]},
  {"number":32,"created_at":"2026-01-01T00:00:00Z","body":"","labels":["arc","ready"]}]'
CALLS=$(mktemp)
gh() { echo "gh $*" >>"$CALLS"; }
out=$(drop_stray_ready 30); rc=$?
check "stray ready: claimed arc returns 0 (not claimed again)" 0 $rc
check "stray ready: log line" $'  #30 already in flight; dropping stray ready\n    #30 -ready' "$out"
check "stray ready: only ready removed" "gh issue edit 30 -R $REPO --remove-label ready" "$(cat "$CALLS")"
: >"$CALLS"
drop_stray_ready 31 >/dev/null; check "stray ready: in-review arc dropped" 0 $?
drop_stray_ready 32 >/dev/null; check "stray ready: plain ready arc is left alone" 1 $?
check "stray ready: plain ready arc untouched" "gh issue edit 31 -R $REPO --remove-label ready" "$(cat "$CALLS")"
rm -f "$CALLS"

# Orphan recovery. gh is stubbed by endpoint; comment lookups return the already-jq-filtered "<created_at> <run id>".
ARCS='[{"number":40,"created_at":"2026-01-01T00:00:00Z","body":"","labels":["arc","claimed"]},
  {"number":41,"created_at":"2026-01-01T00:00:00Z","body":"","labels":["arc","claimed"]},
  {"number":42,"created_at":"2026-01-01T00:00:00Z","body":"","labels":["arc","claimed"]},
  {"number":43,"created_at":"2026-01-01T00:00:00Z","body":"","labels":["arc","claimed"]},
  {"number":44,"created_at":"2026-01-01T00:00:00Z","body":"","labels":["arc","claimed"]},
  {"number":45,"created_at":"2026-01-01T00:00:00Z","body":"","labels":["arc","claimed","needs-human"]}]'
OLD=2026-01-01T00:00:00Z
FUTURE=2099-01-01T00:00:00Z
CALLS=$(mktemp)
gh() {
  case "$*" in
    *"--jq .[].body"*) if [[ "$*" == *issues/44/comments* ]]; then echo "x $ORPHAN_MARKER"; fi ;;
    *issues/40/comments*) echo "$OLD 900" ;;    # cancelled run
    *issues/41/comments*) echo "$OLD 901" ;;    # in-progress run
    *issues/42/comments*) echo "$OLD 902" ;;    # open PR, dead run
    *issues/43/comments*) echo "$FUTURE 903" ;; # young claim
    *issues/44/comments*) echo "$OLD 904" ;;    # dead run, already reverted once
    *actions/runs/901*) echo in_progress ;;
    *actions/runs/90[0234]*) echo completed ;;
    *) echo "gh $*" >>"$CALLS" ;;
  esac
}
out=$(recover_orphans "42")
check "orphan: dead run is logged" 1 "$(grep -c '#40 is an orphan' <<<"$out")"
check "orphan: claimed removed" 1 "$(grep -c 'gh issue edit 40 -R '"$REPO"' --remove-label claimed' "$CALLS")"
check "orphan: ready added" 1 "$(grep -c 'gh issue edit 40 -R '"$REPO"' --add-label ready' "$CALLS")"
check "orphan: comment carries marker" 1 "$(grep -zc 'gh issue comment 40.*dispatcher:orphan-reverted' "$CALLS")"
check "orphan: live run left alone" 0 "$(grep -c 'issue [a-z]* 41 ' "$CALLS")"
check "orphan: open PR left alone" 0 "$(grep -c 'issue [a-z]* 42 ' "$CALLS")"
check "orphan: young claim left alone" 0 "$(grep -c 'issue [a-z]* 43 ' "$CALLS")"
check "orphan: second orphaning escalates" 1 "$(grep -c 'gh issue edit 44 -R '"$REPO"' --add-label needs-human --add-assignee tsebens' "$CALLS")"
check "orphan: second orphaning not reverted" 0 "$(grep -c 'edit 44 .*--add-label ready' "$CALLS")"
check "orphan: needs-human arc skipped" 0 "$(grep -c 'issue [a-z]* 45 ' "$CALLS")"
check "orphan: only existing labels used" 0 "$(grep -- '--add-label' "$CALLS" | grep -cvE -- '--add-label (ready|needs-human)')"
: >"$CALLS"
DRY_RUN=true
out=$(recover_orphans "42")
check "orphan dry run: nothing mutated" "" "$(cat "$CALLS")"
check "orphan dry run: plans revert and comment" 1 "$(grep -c '^    #40 comment: orphan notice' <<<"$out")"
check "orphan dry run: plans revert to ready" 1 "$(grep -c '^    #40 +ready' <<<"$out")"
DRY_RUN=false
rm -f "$CALLS"

# ---------------------------------------------------------------------------
# Never promote an arc with open blockers (#575; incident #564: #560 and #561 were promoted while blocked).
# A stateful stub: ISSUES maps number -> state; BODY_OF maps arc -> body; DEPS_OF maps arc -> native blockers.
# ---------------------------------------------------------------------------
CALLS=$(mktemp)
declare -A ISSUE_STATE BODY_OF DEPS_OF
FAIL_BODY="" FAIL_DEPS="" FAIL_ISSUE=""
gh() {
  case "$*" in
    api\ repos/*/issues/*/dependencies/blocked_by*)
      n=${2##*issues/}; n=${n%%/*}
      [ "$n" = "$FAIL_DEPS" ] && return 1
      [ -n "${DEPS_OF[$n]:-}" ] && tr ' ' '\n' <<<"${DEPS_OF[$n]}"; return 0 ;;
    api\ repos/*/issues/*)
      n=${2##*issues/}
      if [[ "$*" == *--jq\ .state* ]]; then
        [ "$n" = "$FAIL_ISSUE" ] && return 1
        echo "${ISSUE_STATE[$n]:-open}"
      else
        [ "$n" = "$FAIL_BODY" ] && return 1
        printf '%s\n' "${BODY_OF[$n]:-}"
      fi ;;
    *) echo "gh $*" >>"$CALLS" ;;
  esac
}
reset_incident() {
  : >"$CALLS"; FAIL_BODY="" FAIL_DEPS="" FAIL_ISSUE=""
  ISSUE_STATE=([557]=open [558]=open [560]=open [9]=closed); BODY_OF=(); DEPS_OF=()
  BODY_OF[560]=$'Touches: x\nBlocked by: #557\n'
  BODY_OF[561]=$'Blocked by: #558, #560\n'
  BODY_OF[570]=$'Blocked by: none\n'
  BODY_OF[571]=$'Blocked by: #9\n'
  PROJECT_ITEMS='[{"item_id":"I560","number":560,"state":"OPEN","status":"Ready"},{"item_id":"I570","number":570,"state":"OPEN","status":"Ready"}]'
  STATUS_OPTIONS='[{"id":"OPT_READY","name":"Ready"},{"id":"OPT_BACKLOG","name":"Backlog"}]'
  PROJECT_ID=P; STATUS_FIELD_ID=F
}
promoted() { grep -c -- "--add-label \(ready\|claimed\)" "$CALLS"; }

# 1. The incident: blocked arc, open blocker, board Status Ready -> neither ready nor claimed.
reset_incident
ARCS='[{"number":560,"created_at":"2026-11-26T04:13:13Z","labels":["arc","blocked"],"body":""}]'
PROJECT_ITEMS='[{"item_id":"I560","number":560,"state":"OPEN","status":"Ready"}]'
out=$(mirror_board_ready)
check "incident: open blocker + board Ready is not promoted" 0 "$(promoted)"
check "incident: blocked label kept" 0 "$(grep -c -- '--remove-label blocked' "$CALLS")"
check "incident: skip is logged" 1 "$(grep -c '#560 is Ready on the board but has open blockers (#557)' <<<"$out")"
# Same arc with no `blocked` label (automation put it in Ready): it gets `blocked`, never `ready`.
ARCS='[{"number":560,"created_at":"2026-11-26T04:13:13Z","labels":["arc"],"body":""}]'
: >"$CALLS"; mirror_board_ready >/dev/null
check "incident: unlabelled arc gets blocked, not ready" "gh issue edit 560 -R $REPO --add-label blocked" "$(cat "$CALLS")"

# 2. No open blockers + board Ready: still promoted.
reset_incident
ARCS='[{"number":570,"created_at":"2026-11-26T04:13:13Z","labels":["arc"],"body":""}]'
PROJECT_ITEMS='[{"item_id":"I570","number":570,"state":"OPEN","status":"Ready"}]'
mirror_board_ready >/dev/null
check "promote: no open blockers, board Ready -> ready" "gh issue edit 570 -R $REPO --add-label ready" "$(cat "$CALLS")"
reset_incident
ARCS='[{"number":571,"created_at":"2026-11-26T04:13:13Z","labels":["arc","blocked"],"body":""}]'
PROJECT_ITEMS='[{"item_id":"I571","number":571,"state":"OPEN","status":"Ready"}]'
mirror_board_ready >/dev/null
check "promote: closed blockers, blocked arc on board Ready -> blocked off, ready on" $'gh issue edit 571 -R '"$REPO"$' --remove-label blocked\ngh issue edit 571 -R '"$REPO"' --add-label ready' "$(cat "$CALLS")"

# 3. A failed or untrustworthy blocker read is an open blocker, in both steps.
for case in "body:560" "deps:560" "issue:557"; do
  reset_incident
  ARCS='[{"number":560,"created_at":"2026-11-26T04:13:13Z","labels":["arc","blocked"],"body":""}]'
  PROJECT_ITEMS='[{"item_id":"I560","number":560,"state":"OPEN","status":"Ready"}]'
  case "${case%%:*}" in
    body) FAIL_BODY=560 ;;
    deps) FAIL_DEPS=560; ISSUE_STATE[557]=closed ;;
    issue) FAIL_ISSUE=557 ;;
  esac
  mirror_board_ready >/dev/null; unblock_arcs >/dev/null
  check "failed read (${case%%:*}): neither step promotes" 0 "$(promoted)"
done
for pair in "empty body|" "no Blocked by line|Scope: only" "blank Blocked by line|Blocked by:" "blank bold line|**Blocked by:** "; do
  reset_incident; BODY_OF[560]="${pair#*|}"; ISSUE_STATE[557]=closed
  ARCS='[{"number":560,"created_at":"2026-11-26T04:13:13Z","labels":["arc","blocked"],"body":""}]'
  PROJECT_ITEMS='[{"item_id":"I560","number":560,"state":"OPEN","status":"Ready"}]'
  mirror_board_ready >/dev/null; unblock_arcs >/dev/null
  check "untrustworthy read (${pair%%|*}): neither step promotes" 0 "$(promoted)"
done
# The snapshot body in ARCS is never trusted: a stale empty snapshot with a fresh open blocker stays blocked.
reset_incident
ARCS='[{"number":560,"created_at":"2026-11-26T04:13:13Z","labels":["arc","blocked"],"body":"Blocked by: none"}]'
unblock_arcs >/dev/null
check "step 2 reads the body fresh, not from the snapshot" 0 "$(promoted)"

# 4. A blocked arc left by step 1 is promoted by the Unblock step once its blockers close.
reset_incident
ARCS='[{"number":560,"created_at":"2026-11-26T04:13:13Z","labels":["arc","blocked"],"body":""}]'
PROJECT_ITEMS='[{"item_id":"I560","number":560,"state":"OPEN","status":"Ready"}]'
mirror_board_ready >/dev/null; unblock_arcs >/dev/null
check "left blocked: still not promoted while open" 0 "$(promoted)"
ISSUE_STATE[557]=closed; : >"$CALLS"
out=$(unblock_arcs)
check "unblock: once blockers close, blocked -> ready and board Ready" \
  $'gh issue edit 560 -R '"$REPO"$' --remove-label blocked\ngh issue edit 560 -R '"$REPO"$' --add-label ready\ngh api graphql -f project=P -f item=I560 -f field=F -f option=OPT_READY -f query=\n    mutation($project: ID!, $item: ID!, $field: ID!, $option: String!) {\n      updateProjectV2ItemFieldValue(input: {projectId: $project, itemId: $item, fieldId: $field,\n        value: {singleSelectOptionId: $option}}) { projectV2Item { id } }\n    }' "$(cat "$CALLS")"
# Native dependencies count too.
reset_incident; DEPS_OF[560]="558"
ARCS='[{"number":560,"created_at":"2026-11-26T04:13:13Z","labels":["arc","blocked"],"body":""}]'
ISSUE_STATE[557]=closed; unblock_arcs >/dev/null
check "native open dependency blocks" 0 "$(promoted)"

# 5. A malformed `Blocked by:` line blocks: not promoted, not claimed, escalated to needs-human.
malformed_case() { # name body
  reset_incident; BODY_OF[580]="$2"
  ARCS='[{"number":580,"created_at":"2026-11-26T04:13:13Z","labels":["arc","blocked"],"body":""}]'
  PROJECT_ITEMS='[{"item_id":"I580","number":580,"state":"OPEN","status":"Ready"}]'
  unblock_arcs >/dev/null
  check "malformed ($1): not promoted by Unblock" 0 "$(promoted)"
  : >"$CALLS"; mirror_board_ready >/dev/null
  check "malformed ($1): not promoted by Ready mirror" 0 "$(promoted)"
  check "malformed ($1): needs-human added" 1 "$(grep -c -- '--add-label needs-human' "$CALLS")"
  check "malformed ($1): tsebens assigned" 1 "$(grep -c -- '--add-assignee tsebens' "$CALLS")"
}
malformed_case "bare hashes" $'Blocked by: #, #\n'
malformed_case "Arc N" $'Blocked by: #5, Arc 2\n'
malformed_case "stray words" $'Blocked by: #1, #7 and Arc 3\n'
reset_incident; BODY_OF[581]=$'Blocked by: #5, Arc 2\n'; ISSUE_STATE[5]=closed
check "open_blockers_of prints the malformed token" "?malformed-blocked-by-line" "$(open_blockers_of 581)"
# Claim step: a ready arc with a malformed line is neither claimed nor left unescalated.
reset_incident; BODY_OF[582]=$'Blocked by: #\n'
out=$(escalate_if_malformed 582 "$(open_blockers_of 582)"); rc=$?
check "escalate_if_malformed: returns 0 for a malformed line" 0 $rc
check "escalate_if_malformed: needs-human and assignee" 2 "$(grep -c 'needs-human\|add-assignee tsebens' "$CALLS")"
# The escalation comment suggests the concept's other arcs.
reset_incident; BODY_OF[590]=$'Blocked by: Arc 2\nConcept: #936\n'
ARCS='[{"number":590,"title":"A","labels":["arc"],"body":"Blocked by: Arc 2\nConcept: #936\n"},{"number":591,"title":"M1.2 · Sibling","labels":["arc"],"body":"Concept: #936\n"},{"number":592,"title":"Other","labels":["arc"],"body":"Concept: #9360\n"}]'
escalate_if_malformed 590 "$(open_blockers_of 590)" >/dev/null
check "escalation comment suggests sibling arcs only" "1:0:0" "$(grep -c -- '- #591 M1.2 · Sibling' "$CALLS"):$(grep -c -- '- #592' "$CALLS"):$(grep -c -- '- #590' "$CALLS")"
# Well-formed lines still promote.
for pair in "none|Blocked by: none" "closed|Blocked by: #5" "bold|**Blocked by:** #5, #9"; do
  reset_incident; ISSUE_STATE[5]=closed; BODY_OF[583]="${pair#*|}"
  ARCS='[{"number":583,"created_at":"2026-11-26T04:13:13Z","labels":["arc","blocked"],"body":""}]'
  unblock_arcs >/dev/null
  check "well-formed (${pair%%|*}): still promotes" 1 "$(grep -c -- '--add-label ready' "$CALLS")"
done

# ---------------------------------------------------------------------------
# #643: an open status is never written onto a closed issue; step 5 logs reopen and merged-close anomalies.
# ---------------------------------------------------------------------------
writes() { grep -c '^gh api graphql -f project' "$CALLS"; }
PR_LABELS='[]'
ALL_OPTIONS='[{"id":"OPT_INPROG","name":"In progress"},{"id":"OPT_REVIEW","name":"In review"},{"id":"OPT_DONE","name":"Done"}]'

# Closed item (snapshot) with a stale in-review label: no open-status write.
reset_incident
ARCS='[{"number":600,"created_at":"2026-11-26T04:13:13Z","labels":["arc","in-review"],"body":""}]'
PROJECT_ITEMS='[{"item_id":"I600","number":600,"state":"CLOSED","status":"Done"}]'
ISSUE_STATE[600]=closed; STATUS_OPTIONS="$ALL_OPTIONS"
out=$(project_arc_labels)
check "closed + stale in-review: no board write" 0 "$(writes)"
check "closed + stale in-review: skip logged" 1 "$(grep -c "#600 is closed" <<<"$out")"
# Even if Status somehow reads differently, the snapshot guard holds.
PROJECT_ITEMS='[{"item_id":"I600","number":600,"state":"CLOSED","status":"In progress"}]'
: >"$CALLS"; project_arc_labels >/dev/null
check "closed (snapshot) with another status: no board write" 0 "$(writes)"

# Snapshot says open, fresh REST read says closed: no write.
reset_incident
ARCS='[{"number":601,"created_at":"2026-11-26T04:13:13Z","labels":["arc","in-review"],"body":""}]'
PROJECT_ITEMS='[{"item_id":"I601","number":601,"state":"OPEN","status":"In progress"}]'
ISSUE_STATE[601]=closed; STATUS_OPTIONS="$ALL_OPTIONS"
out=$(project_arc_labels)
check "fresh read closed, snapshot open: no write" 0 "$(writes)"
check "fresh read closed: skip logged" 1 "$(grep -c "#601 is closed (fresh read)" <<<"$out")"
# A failed fresh read skips too; an open one writes.
reset_incident; FAIL_ISSUE=601; STATUS_OPTIONS="$ALL_OPTIONS"
ARCS='[{"number":601,"created_at":"2026-11-26T04:13:13Z","labels":["arc","in-review"],"body":""}]'
PROJECT_ITEMS='[{"item_id":"I601","number":601,"state":"OPEN","status":"In progress"}]'
project_arc_labels >/dev/null
check "fresh read fails: no write" 0 "$(writes)"
reset_incident; STATUS_OPTIONS="$ALL_OPTIONS"
ARCS='[{"number":601,"created_at":"2026-11-26T04:13:13Z","labels":["arc","in-review"],"body":""}]'
PROJECT_ITEMS='[{"item_id":"I601","number":601,"state":"OPEN","status":"In progress"}]'
project_arc_labels >/dev/null
check "fresh read open: write happens" 1 "$(writes)"
# Done is still written for a closed issue.
reset_incident; STATUS_OPTIONS="$ALL_OPTIONS"
PROJECT_ITEMS='[{"item_id":"I602","number":602,"state":"CLOSED","status":"In progress"}]'
ISSUE_STATE[602]=closed
set_board_status 602 Done >/dev/null
check "Done is written to a closed issue" 1 "$(writes)"

# Step 5 anomalies.
T_REOPEN='[{"event":"closed","created_at":"2026-11-26T10:00:00Z"},{"event":"reopened","created_at":"2026-11-26T10:00:30Z"}]'
T_SLOW='[{"event":"closed","created_at":"2026-11-26T10:00:00Z"},{"event":"reopened","created_at":"2026-11-26T11:00:00Z"}]'
T_MERGED='[{"event":"cross-referenced","created_at":"2026-11-26T10:00:00Z","merged_at":"2026-11-26T10:00:00Z","body":"Closes #650\n"}]'
T_MENTION='[{"event":"cross-referenced","created_at":"2026-11-26T10:00:00Z","merged_at":"2026-11-26T10:00:00Z","body":"Refs #650\n"},{"event":"cross-referenced","created_at":"2026-11-26T10:00:00Z","merged_at":null,"body":"Closes #650"}]'
check "anomaly: closed then reopened within a minute" "  anomaly: open arc #650 was closed then reopened within a minute" "$(log_arc_anomalies 650 "$T_REOPEN")"
check "anomaly: slow reopen is normal" "" "$(log_arc_anomalies 650 "$T_SLOW")"
check "anomaly: merged PR with Closes" "  anomaly: open arc #650 has a PR merged at 2026-11-26T10:00:00Z with Closes #650" "$(log_arc_anomalies 650 "$T_MERGED")"
check "anomaly: Refs or unmerged PR is not one" "" "$(log_arc_anomalies 650 "$T_MENTION")"
check "anomaly: Closes #65 does not match #650" "" "$(log_arc_anomalies 65 "$T_MERGED")"
rm -f "$CALLS"

exit $fails
