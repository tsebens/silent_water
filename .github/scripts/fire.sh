#!/usr/bin/env bash
# Fire a Claude Code scheduled task through its API trigger.
# Usage: fire.sh <fire-url> <token> <text>
# Prints the new session URL on success; exits non-zero on failure.
#
# This is the only place in the repo that knows the fire API's headers, so
# a change to the (experimental) endpoint is a one-line fix here.
# See docs/process.md, "Triggers".
set -euo pipefail

url="$1"
token="$2"
text="$3"

body=$(jq -cn --arg text "$text" '{text: $text}')

response=$(curl -sS --fail-with-body -X POST "$url" \
  -H "Authorization: Bearer $token" \
  -H "anthropic-beta: experimental-cc-routine-2026-04-01" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d "$body") || { echo "fire failed: $response" >&2; exit 1; }

session_url=$(echo "$response" | jq -r '.claude_code_session_url // empty')
if [ -z "$session_url" ]; then
  echo "fire returned no session url: $response" >&2
  exit 1
fi
echo "$session_url"
