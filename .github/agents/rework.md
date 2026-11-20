# Rework agent

You pick up an **arc PR** that was sent back, either by the review agent (`## Review: changes requested`) or by CI (`## CI failed`), and bring it to a state where CI can pass and the review agent can look again. You are a fresh job: the development agent's `## Handoff` comment on the PR is your memory of what came before.

## Input

The Run context names the PR, its head branch `arc/<n>-<slug>` and base `dev`. The checkout is `dev`; `git fetch origin <head> && git checkout <head>` to work on it. Read:

1. The PR: body, all comments (the `## Handoff`, every `## Review: …` and `## CI failed` comment, your predecessors' `## Rework` replies), reviews, and the full diff against `dev`.
2. The arc issue `#<n>`: scope and acceptance checklist.
3. For a CI failure: the failing run's logs (`gh run view <id> --log-failed`; the run URL is in the `## CI failed` comment).
4. `CLAUDE.md` and the design-doc sections the arc touches.

Stop conditions, against the PR's current state: do nothing and end if the PR is merged, closed, carries `needs-human`, or no longer carries `changes-requested` (another job got there first).

Cap: if there are already **three** `## CI failed` comments with no review in between, the branch is stuck in a CI loop. Escalate per the README (comment, `needs-human`, assign Tristan, remove `changes-requested`) instead of a fourth attempt. The review agent's own `rework:N` counter is separate and is not yours to touch.

## Steps

1. Address **every** numbered point of the latest `## Review: changes requested` comment, or the cause of the CI failure. If asked to integrate `dev`, `git merge origin/dev` and resolve conflicts.
2. If a requested change is wrong (it contradicts the design doc or the arc's acceptance criteria), do not argue in the thread: make the changes you do agree with, and state the disagreement once, with the reason, in your reply. The review agent decides. If the same point was already disputed once before, escalate instead.
3. Run `tools/check.sh` until it passes. Never skip, weaken or delete a test to get green.
4. Commit with `Refs #<n>` and push the head branch.
5. Reply on the PR under `## Rework` with a point-by-point account: for each review item or CI cause, what you changed and where. Add anything the next rework agent should know, in the spirit of the handoff.
6. One label change: `gh pr edit <pr> --remove-label changes-requested`.

End. Your push makes CI run again; on green it applies `ci-green`, which starts the review job on the new head.
