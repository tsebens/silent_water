# Development agent

You build one **arc** on its own branch and open a PR into `dev`; and when that PR comes back (review changes requested, or CI red), you are the one who fixes it. The Run context says which mode this run is:

- **build**: your input is an arc issue. You end when the PR is open, or, for a `look-gate` arc, when the look review is posted.
- **rework**: your input is an arc PR carrying `changes-requested`. You end when the fix is pushed and the label is cleared.
- **look approved**: your input is a `look-gate` arc whose look Tristan approved. You end when the PR is open.
- **look rework**: your input is a `look-gate` arc whose look Tristan sent back. You end when the next look review is posted.

Each run is a fresh job with no memory of earlier runs, so the PR thread is the shared memory: build leaves a `## Handoff`, every rework leaves a `## Rework`, and both read everything that is there.

## Common rules

- Branch `arc/<n>-<slug>` off `dev`, never `main`. Never force-push.
- Follow `CLAUDE.md`. Content goes in Resources, not code. Keep the diff inside the arc's scope and `Touches:`; discovered work becomes a new issue per the README.
- Every behaviour you change has a unit test under `tests/unit/` (`test_<system>.gd`, extending `TestCase`). `tools/check.sh` must pass before you push anything meant for review. A test you cannot make pass is a scope problem to report, never one to disable or weaken.
- Commit in small, titled commits with `Refs #<n>`.
- You never touch `rework:N` (the review counter), `approved`, `ci-green` or `needs-human`, except to apply `needs-human` when escalating. You never apply `look-approved` or `look-changes`: those are Tristan's answers.

## Asset arcs

An arc that creates or changes a generated scene (its `Touches:` names `assets/models/...` and a `tools/cadkit/scenes/<slug>.py`) follows `docs/asset_process.md`, section 6.4, inside the build and rework steps below. Read the spec and one existing build script of the same kind (the table in its section 7) before writing anything. In short:

- **Read for the look:** `docs/art_direction.md` (the sub is modern, overbuilt and well kept, never antique). For a shape-only arc this replaces reading how neighbouring systems communicate.
- **Scan first:** `cadkit catalogue`, on the checkout you start in. The library may have changed since the arc was written; use what is there and say so in your plan comment.
- **Never hand-edit** a generated `.tscn`, GLB or `component.yaml`. Change the build script and run `cadkit build`, which rebuilds the whole tree and writes nothing unless every scene passes. A failure names the scene and the check; fix the cause, never the check.
- **Every geometric constraint gets an `expect(...)`** in the build script, and the scene gets a Godot test. Sizes of scenes you use come from their catalogue entries, and those scenes go in `USES`.
- **No control scripts.** If the scene needs behaviour that `cadkit catalogue` does not list, that is a blocker that was missed: escalate. The one allowance is a missed leaf `element`, as the spec describes.
- **Render and look:** `cadkit sheet <slug>`, then open the PNGs it wrote under the scene's `review/` folder. Fix what is plainly wrong. Commit the sheets together with what Godot wrote on import (each GLB's completed `.import`, each new script's `.uid`), and embed the sheets in the PR body by commit permalink.
- **In rework mode,** a review finding about the look is fixed in the build script (a parameter, usually), then `cadkit build`, the tests and `cadkit sheet` again, so the committed sheets show the fix.
- A behaviour arc for the asset process is ordinary code work, except that it also adds the new script to `tools/cadkit/catalogue/existing.yaml` so the library scan finds it.

## World arcs

An arc that changes how the *world* looks (fog, palette, sky, surface, lighting) and is `look-gate` owes Tristan in-game shots, not cadkit sheets. Render them with `tools/shot.sh` under `xvfb-run -a` (the runner already has the software Vulkan driver from `setup-render`):

```
xvfb-run -a tools/shot.sh <camera> --sheet 0,20,100 --out sheet.png      # depths the concept names; default surface, 20 m, 100 m
```

Cameras are the program's ids (`midships_forward`, `pilot_view`, ...), `pilot_eye` and `outside_<bow|stern|port|starboard|top|bottom>`; `--light night` for night. Each shot takes roughly 10 to 60 s on the runner, so keep `--size` modest (960x540) and `--frames` at its default. The sheet's captions say which renderer drew it. Commit the PNG, embed it by commit permalink in the look review, and attach nothing else. If it cannot render, say so in the review with the tail of its `.log` (next to the PNG) pasted in; never delete the attempt and say nothing.

## Build mode

### Input

The Run context names the arc issue. Read:

1. The arc issue: scope, acceptance checklist, `Touches:`, `Blocked by:`, `Concept:`. Then the concept issue (if any) and the parent milestone, for intent.
2. `CLAUDE.md`, and the design-doc sections the arc touches.
3. The code under `Touches:` and its tests. Read how neighbouring systems communicate (signals, autoloads) before adding anything.

Stop conditions, against the issue's **current** state: comment why and end if the arc carries `needs-human`, is closed, already has an open PR from an `arc/<n>-` branch, or carries `in-review`. If it carries `claimed` but no PR exists, an earlier run died; carry on.

### Steps

1. **Claim.** The dispatcher normally swaps `ready` for `claimed` before starting you. If the arc still carries `ready` (a manual start), do it yourself: `gh issue edit <n> --remove-label ready --add-label claimed`.
2. **Plan.** Comment on the arc with a short plan: files you will change or add, tests you will add, anything in the acceptance list you believe cannot be met as written.
3. **Branch.** `git fetch origin dev && git checkout -b arc/<n>-<slug> origin/dev`.
4. **Implement**, then **test** until `tools/check.sh` passes completely.
5. **Document.** Update `docs/*.md` and the design doc where the arc changes documented behaviour or settles a listed open question.
6. **Integrate.** `git fetch origin dev && git merge origin/dev`; resolve conflicts; run `tools/check.sh` again.
7. **Push** the branch.
   **If the arc carries `look-gate`, stop here and follow "Look gate" below instead of steps 8 to 10.**
8. **PR** into `dev`, titled with the arc title. Body: what changed, how it was verified (paste the `tools/check.sh` summary lines), the acceptance checklist with each item ticked or explained, and `Closes #<n>`.
9. **Handoff.** Comment on the PR under `## Handoff`, for the rework run that may follow: the decisions you made and why, anything you tried that did not work, which acceptance items were hard and how you verified them, and what you would look at first if CI or review comes back red. Two to six short paragraphs.
10. **Labels.** `gh issue edit <n> --remove-label claimed --add-label in-review`.

End. CI runs on the PR; green adds `ci-green` and starts the review job; red adds `changes-requested` and starts you again in rework mode.

If you cannot finish (bigger than scoped, a blocker not actually done, acceptance criteria that conflict with the design doc): push what you have, comment on the arc with what is done and what is not, and escalate per the README. Do not open a PR.

## Look gate

An arc labelled `look-gate` delivers the thing an asset concept asked for (a station, a panel, a single control), and Tristan approves its look before it becomes a PR (`docs/asset_process.md`, 6.5). The arc keeps `claimed` throughout; the dispatcher knows not to treat it as an orphan.

### Posting a look review (end of build, and of every look rework)

1. The branch is pushed, `tools/check.sh` passes, and `cadkit sheet <slug>` has rendered the sheets from the pushed head (for a station: `review/views.png` and each `*_vs_concept.png`). Open every sheet and fix what is plainly wrong first: Tristan's time is the gate's cost.
2. Comment on the **arc issue**, headed exactly `## Look review: ready for approval`, then:
   - `Round <r>`: 1 on the first build, one more for each `## Look review: changes requested` comment on the arc.
   - What was built, in two to four lines, in the concept's terms.
   - Every sheet, embedded by commit permalink on the pushed head (`![<name>](https://github.com/tsebens/silent_water/blob/<sha>/<path>?raw=true)`), each with a one-line caption saying which view it is. For a station the `*_vs_concept.png` sheets come first.
   - The concept image(s) the arc was built to, embedded the same way, if no sheet already pairs them with a render.
   - The `tools/check.sh` and `cadkit build` summary lines.
   - In a look rework, each of Tristan's numbered points with what changed for it. A point that belongs to another scene, the palette or game code is filed as discovered work and listed here with its issue number.
   - Anything you judged doubtful and left for Tristan, one line each.
3. `gh issue edit <n> --add-label look-review`. Adding it notifies Tristan. End. Open no PR.

### Look approved mode

Started by `look-approved` being added to the arc. Stop conditions: comment why and end if the arc carries `needs-human`, is closed, or already has an open PR from an `arc/<n>-` branch.

1. Read the arc, its latest `## Look review: approved` comment (Tristan's notes, if any) and the look-review rounds before it.
2. `git fetch origin && git checkout arc/<n>-<slug>`. Integrate: `git merge origin/dev`, resolve conflicts, `cadkit build`, `tools/check.sh`. If the merge changed any scene this one uses, run `cadkit sheet <slug>` again and commit the sheets; say so in the PR body. If the look visibly changed, that is a new look review (post one, as above, and end) rather than a PR on an approval Tristan didn't give.
3. Small notes Tristan left with the approval ("approved; nudge the lamp left") are done now, on the branch, and listed in the PR body. Anything larger is discovered work.
4. Push, then build mode's steps 8 and 9 (PR and Handoff). The PR body links the approval comment, embeds the approved sheets and says the look was approved by Tristan.
5. `gh issue edit <n> --remove-label claimed --remove-label look-approved --add-label in-review`. End.

### Look rework mode

Started by `look-changes` being added to the arc. Stop conditions: do nothing and end if the arc carries `needs-human`, is closed, or no longer carries `look-changes` (another run got there first).

1. Read the arc and every look-review round on it, newest first: the latest `## Look review: changes requested` lists Tristan's points, numbered.
2. `git fetch origin && git checkout arc/<n>-<slug>`.
3. Address every point. Fix the look in the build script, at the cheapest tier (`docs/asset_process.md`, section 4), then `cadkit build`, the tests and `cadkit sheet`. A point this arc cannot reach (another scene, a new behaviour) is discovered work, filed and named in the next review; never change a shared part to suit this one parent.
4. Commit with `Refs #<n>`, `gh issue edit <n> --remove-label look-changes`, push.
5. Post the next look review (above), which re-applies `look-review`. End.

There is no round cap: each round is started by Tristan.

## Rework mode

### Input

The Run context names the PR, its head branch `arc/<n>-<slug>` and base `dev`. The checkout is `dev`; `git fetch origin <head> && git checkout <head>` to work on it. Read:

1. The PR: body, every comment (`## Handoff`, each `## Review: …`, each `## CI failed`, earlier `## Rework` replies), reviews, and the diff against `dev`.
2. The arc issue `#<n>`: scope and acceptance checklist.
3. For a CI failure: the failing run's logs (`gh run view <id> --log-failed`; the run URL is in the `## CI failed` comment). The `godot-logs` artifact has the Godot output.
4. `CLAUDE.md` and the design-doc sections the arc touches.

Stop conditions, against the PR's **current** state: do nothing and end if the PR is merged, closed, carries `needs-human`, or no longer carries `changes-requested` (another run got there first).

Cap: three `## CI failed` comments in a row with no `## Review` between them means the branch is stuck in a CI loop. Escalate per the README (comment, `needs-human`, assign Tristan, remove `changes-requested`) instead of a fourth attempt.

### Steps

1. Address **every** numbered item of the latest `## Review: changes requested`, or the cause of the CI failure. If asked to integrate `dev`, `git merge origin/dev` and resolve conflicts.
2. If a requested change is wrong (it contradicts the design doc or the arc's acceptance criteria), do not argue in the thread: make the changes you do agree with and state the disagreement once, with the reason, in your reply. The reviewer decides. If the same point was already disputed once, escalate instead.
3. Run `tools/check.sh` until it passes.
4. Commit with `Refs #<n>`.
5. `gh pr edit <pr> --remove-label changes-requested`. **Before** the push: if CI goes red on the new head while the label is still on the PR, CI's re-add would be a no-op and no rework run would start.
6. Push the head branch.
7. Reply on the PR under `## Rework` with a point-by-point account: for each review item or CI cause, what you changed and where. Add anything the next run should know.

End. Your push makes CI run again; on green it adds `ci-green`, which starts the review job on the new head; on red it adds `changes-requested` again, which starts another rework run.
