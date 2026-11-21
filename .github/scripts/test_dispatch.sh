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
gh() { echo "gh $*" >>"$CALLS"; }
out=$(close_finished_concepts "$CONCEPTS_FIX" "$ARCS_FIX")
check "close pass: closes only #10 with reason completed" "gh issue close 10 -R $REPO --reason completed" "$(cat "$CALLS")"
check "close pass: log line" "  closing concept #10: all arcs closed" "$out"
: >"$CALLS"
DRY_RUN=true
out=$(close_finished_concepts "$CONCEPTS_FIX" "$ARCS_FIX")
check "dry run: nothing closed" "" "$(cat "$CALLS")"
check "dry run: would-close line logged" $'  closing concept #10: all arcs closed\n    (dry) gh issue close 10 -R '"$REPO"' --reason completed' "$out"
DRY_RUN=false
rm -f "$CALLS"

exit $fails
