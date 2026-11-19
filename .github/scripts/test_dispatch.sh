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

exit $fails
