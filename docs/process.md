# Development process

How work moves from an idea to `main` in Silent Water, and which agent does what. This is the spec the pipeline is built from: the role prompts in `.github/agents/`, the workflows in `.github/workflows/`, and the scheduled tasks on Tristan's Claude account all implement what is written here. When they disagree with this document, this document wins and the implementation is a bug.

Tracked by [#62](https://github.com/tsebens/silent_water/issues/62).

## Principles

- **The repo is the source of truth.** Role definitions, labels, the state machine and the dispatcher live in version control and change through pull requests. Anything stored elsewhere (scheduled-task prompts, tokens) is a thin pointer back here.
- **Issues are the queue.** Work waits as an issue in a known state, never as a pending run. A dropped event costs minutes, not work.
- **Labels drive automation; the board is for people.** GitHub fires events for label changes, not for board status changes on a user-owned project. Every agent updates both, and the dispatcher reconciles them.
- **One human gate per stage, and it is not Tristan.** Agents check each other. Tristan sees the pipeline when it stalls (`needs-human`) and when `dev` merges to `main`.
- **Bounded loops.** Every retry loop has a counter and an exit to a human.

## Branches

| Branch | Purpose | Who writes |
| --- | --- | --- |
| `main` | Playable, reviewed by Tristan | Tristan, by merging `dev` |
| `dev` | Integration branch; every arc lands here | Review agent, by squash-merging arc PRs |
| `arc/<issue>-<slug>` | One arc's work, branched from `dev` | One development agent (and its rework agents) |

Rules:

- Arc branches are created from the head of `dev`, never from `main`.
- Before opening a PR, the development agent merges `dev` into the arc branch and re-runs the checks. If `dev` moves again before the PR merges, that is a rework round (see below); the review agent never resolves conflicts.
- Arc PRs target `dev` and are **squash-merged**, so `dev` reads as one commit per arc and `dev → main` is a readable diff.
- Branch protection: `dev` and `main` accept changes only through PRs with green CI. `main` is Tristan's alone.

## Roles

Seven roles. Six are Claude sessions; the dispatcher is deterministic code.

| Role | Runs as | Input | Output |
| --- | --- | --- | --- |
| **Head developer** | Interactive cloud session with Tristan | Conversation | A `concept` issue |
| **Organization agent** | Scheduled task | A `concept` issue | A proposed breakdown into arcs, posted as a comment; `plan-proposed` |
| **Plan-review agent** | Scheduled task | A `plan-proposed` concept | Either the arc issues (created under milestones) and `plan-approved`, or objections and `plan-rejected` |
| **Dispatcher** | GitHub Action (no Claude) | Labels, PR merges, a 15-minute cron | Marks arcs `ready`, claims them up to the worker cap, fires development agents |
| **Development agent** | Scheduled task | A `claimed` arc | An arc branch, a PR into `dev`, the arc In review |
| **Review agent** | Scheduled task | A PR with green CI | Squash-merge and Done, or `changes-requested` with a rework counter |
| **Rework agent** | Scheduled task (same prompt as development, in rework mode) | A `changes-requested` PR | An updated PR, or `needs-human` after the third round |

### Head developer

Talks with Tristan about a feature, fix or adjustment until the idea is solid. Writes one `concept` issue per idea: the problem, the intended player experience, constraints, what is explicitly out of scope, and any design-doc sections it touches. Does not break the work down and does not write code. If the conversation settles an open design question, records it as a `Decision:` issue and in the design doc, as CLAUDE.md requires.

### Organization agent

Reads the concept, the design doc, the open milestones and the open arcs. Decides whether the concept is one arc or several. For each proposed arc it writes:

- a title in the milestone scheme, `M<n>.<k> · <name>`, under an existing milestone where one fits; if nothing fits, it proposes a new `M<n> · <name>` milestone and stops with `needs-human` instead of inventing one
- a scope statement and acceptance criteria that a development agent can verify headless
- `Touches:` the systems or folders the arc will change (its blast radius)
- `Blocked by:` other arcs it depends on, including arcs from the same concept and outstanding arcs already on the board. Two arcs with overlapping `Touches:` are chained even when logically independent, so only one of them is in flight at a time

Posts the breakdown as a comment on the concept issue and applies `plan-proposed`. Creates no issues itself.

### Plan-review agent

A second pair of eyes before one misread concept fans out into several wasted development runs. Checks the proposal against the concept and the design doc: is anything missing, is anything out of scope, are the dependencies right, is each arc small enough to finish in one session, are the acceptance criteria testable. On approval it creates the arc issues as sub-issues of their milestones with the `arc` label, copies `Touches:` and `Blocked by:` into each body, adds them to the board in Backlog, labels unblocked arcs `ready` and the rest `blocked`, and applies `plan-approved` to the concept. On rejection it comments its objections and applies `plan-rejected`, which re-fires the organization agent. Two rejections on one concept escalate to `needs-human`.

### Dispatcher

A workflow in `.github/workflows/dispatch.yml`, running on `issues` (labeled, closed), `pull_request` (closed) and a 15-minute cron. It is plain shell against the GitHub API, which keeps it cheap, fast and predictable. Each run:

1. Exits immediately if the repository variable `PIPELINE_PAUSED` is `true`.
2. **Mirrors the board.** Arcs whose board Status is Ready but which lack the `ready` label get it (so Tristan can promote work from the board UI). Arcs that are Done on the board but still open are flagged in the run log.
3. **Unblocks.** For each `blocked` arc, if every issue in its `Blocked by:` list is closed, swap `blocked` for `ready`.
4. **Claims.** In-flight count = open arcs labeled `claimed` or `in-review`. While in-flight is below `WORKER_CAP` (repository variable, start at 2): take the oldest `ready` arc whose `Touches:` do not overlap any in-flight arc, swap `ready` for `claimed`, and fire the development task with `{"text": "arc #<n>"}`. Comment the returned session URL on the issue.

Because the cron re-runs this from the labels alone, a dropped webhook or a session that never started is picked up within 15 minutes.

### Development agent

Fired with an arc number. Reads the arc, its milestone, the design doc and the code it touches. Writes a short plan as a comment on the arc, moves the arc to In progress on the board, creates `arc/<n>-<slug>` from the head of `dev`, and implements with the repo conventions (typed GDScript, small scenes, signals, Resources for content). Runs `tools/check.sh` until green. Adds or extends tests under `tests/unit/` for behaviour it changed. Merges `dev` into the branch and re-runs the checks. Opens a PR into `dev` whose body states what changed, how it was verified, and `Closes #<n>`. Swaps `claimed` for `in-review`, moves the arc to In review, and exits. If it cannot finish (the arc is larger than it looked, or a dependency is missing), it comments why, applies `needs-human` and exits without a PR.

### Review agent

Fires only on a PR that CI has already passed (see the trigger table). Reviews for correctness against the arc's acceptance criteria, adherence to CLAUDE.md and the design doc, test coverage, and whether the branch is up to date with `dev`. Then one of:

- **Accept:** comments a short review, applies `approved`, squash-merges into `dev` with the arc title as the commit subject, deletes the branch, moves the arc to Done and confirms it is closed. Nothing fires after a merge except the dispatcher.
- **Request changes:** comments the specific, actionable changes, increments the rework counter (`rework:1` → `rework:2` → `rework:3`), applies `changes-requested`, and moves the arc to In progress. A merge conflict with `dev`, or stale CI, is a request-changes outcome, never something the review agent fixes.
- **Escalate:** if the PR already carries `rework:3`, it does not request changes again. It applies `needs-human`, assigns Tristan, summarises why the PR keeps failing, and sends a push notification.

Commits and PRs in this pipeline carry Tristan's GitHub identity (that is how cloud sessions push), so the review agent cannot use GitHub's formal approve; the `approved` label and the review comment are the record.

### Rework agent

Fires on `changes-requested`. The session starts at the PR head. It reads the review, moves the arc to In progress, addresses every point (including merging `dev` if asked), re-runs `tools/check.sh`, pushes, replies to the review comment with what it did, removes `changes-requested`, and moves the arc back to In review. CI runs on the push and, when green, the review agent fires again. The rework agent never bumps the counter; only the review agent does.

## Issues and labels

### Issue kinds

| Kind | Title | Label | Created by | Parent |
| --- | --- | --- | --- | --- |
| Concept | Free-form | `concept` | Head developer | None |
| Milestone | `M<n> · <name>` | none | Tristan or head developer (via `needs-human`) | None |
| Arc | `M<n>.<k> · <name>` | `arc` | Plan-review agent | Its milestone |
| Decision | `Decision: …` | `decision` | Anyone | None |
| Discovered work | Free-form | `arc` once scoped | Any agent that finds it | Its milestone |

### Labels that drive automation

| Label | On | Meaning | Set by | Cleared by |
| --- | --- | --- | --- | --- |
| `concept` | issue | Input to the organization agent | Head developer | never |
| `plan-proposed` | concept | Breakdown awaits plan review | Organization agent | Plan-review agent |
| `plan-approved` | concept | Arcs created; concept is done when they are | Plan-review agent | never |
| `plan-rejected` | concept | Breakdown sent back; counts toward the plan cap | Plan-review agent | Organization agent |
| `arc` | issue | A unit of work | Plan-review agent | never |
| `blocked` | arc | Waits on `Blocked by:` issues | Plan-review agent | Dispatcher |
| `ready` | arc | Eligible for claiming | Plan-review agent, dispatcher, Tristan | Dispatcher |
| `claimed` | arc | A development agent has it | Dispatcher | Development agent |
| `in-review` | arc | Has an open PR | Development agent | Review agent (on merge) |
| `ci-green` | PR | CI passed on the current head | CI workflow | CI workflow (on next push) |
| `changes-requested` | PR | Rework needed | Review agent | Rework agent |
| `rework:1` `rework:2` `rework:3` | PR | Rounds of rework so far | Review agent | never (replaced) |
| `approved` | PR | Review passed; merged | Review agent | never |
| `needs-human` | any | Pipeline stopped here; Tristan decides | Any agent | Tristan |

### Board status mirror

| Board Status | Concept | Arc |
| --- | --- | --- |
| Backlog | Awaiting breakdown or plan review | `blocked` |
| Ready | Not used | `ready` |
| In progress | Not used | `claimed`, or PR has `changes-requested` |
| In review | Not used | `in-review` and PR awaiting CI or review |
| Done | `plan-approved` and all arcs Done | Merged and closed |

## State machine

### Concept

```
created(concept) ─► organization agent ─► plan-proposed ─► plan-review agent
                                                              │
                              ┌───────────────────────────────┤
                              ▼                               ▼
                       plan-rejected (×1)                plan-approved → arcs exist
                              │
                              ▼
                       organization agent ─► plan-proposed ─► plan-review agent
                                                              │
                              ┌───────────────────────────────┤
                              ▼                               ▼
                       plan-rejected (×2) → needs-human  plan-approved
```

### Arc

```
blocked ──(blockers closed)──► ready ──(dispatcher, cap)──► claimed ──(dev agent)──► in-review
                                                                                      │
                                              ┌───────────────────────────────────────┤
                                              ▼                                       ▼
                                      PR ci-green → review agent              CI red → wait for push
                                              │
                        ┌─────────────────────┼─────────────────────────┐
                        ▼                     ▼                         ▼
                   approved, merged     changes-requested          rework:3 already
                   arc Done, closed     rework:n+1                 → needs-human
                                              │
                                              ▼
                                        rework agent → push → CI → ci-green → review agent
```

## Triggers

Each Claude role is a scheduled task on Tristan's Claude account, configured in the Claude Code web UI, running in the `silent_water` cloud environment (which installs Godot). The task's stored prompt is a stub of the form:

> You are the *&lt;role&gt;* in the Silent Water pipeline. Read `.github/agents/<role>.md` in the repository and follow it exactly. Your input is in the fire payload or, for pull request events, the checked-out branch.

Everything else is in the repo.

| Role | Event | Filter | How fired | Input the session gets |
| --- | --- | --- | --- | --- |
| Organization | `issues.labeled` | label = `concept` or `plan-rejected` | Native trigger if issue-label filters prove available; else `fire.yml` | Issue number (payload `text`) |
| Plan review | `issues.labeled` | label = `plan-proposed` | Same as above | Issue number |
| Dispatcher | `issues` labeled/closed, `pull_request` closed, cron `*/15` | — | GitHub Action | Event |
| Development | Dispatcher claim | — | Dispatcher calls the fire API with `{"text": "arc #n"}` | Arc number |
| Review | `pull_request.labeled` | label = `ci-green`, base = `dev` | Native trigger | Checkout at PR head; PR found from branch |
| Rework | `pull_request.labeled` | label = `changes-requested`, base = `dev` | Native trigger | Checkout at PR head |

Notes:

- Native pull-request triggers support filters on Author, Title, Body, Base branch, Head branch, Labels, Is draft and Is merged, and the session checks out the PR head. Every PR hop uses them.
- The docs list no filters for issue events and do not say what context an issue-triggered session receives. The web UI may offer more than the docs. **Setup step 7** tests one native issue trigger; if the fired session can see the issue number and the label filter holds, the organization and plan-review rows use native triggers. Otherwise `fire.yml` (an Action with `if: github.event.label.name == '…'` that POSTs to the task's fire endpoint with the issue number as `text`) stands in. Either way the role prompts are unchanged.
- CI gating: `ci.yml` removes `ci-green` at the start of every PR run and adds it on success. The label event, not the push, is what fires the review agent, so the review agent never looks at a red or pending PR.
- Native GitHub triggers do not queue. Events over the hourly caps are dropped, and a run blocked by the concurrent-session ceiling does not start. The labels hold the state and the dispatcher's cron retries, so nothing is lost; it is at most late.
- Events caused by a workflow's `GITHUB_TOKEN` do not start other **Actions** workflows (which is why `fire.yml` and `dispatch.yml` use the `GITHUB_MCP_PAT` secret where they must chain), but they do reach the Claude GitHub App's webhooks, which is what the `ci-green` row relies on. Setup step 7 confirms this too.

## Worker pool

There is no native "at most N runs" setting anywhere in the chain: Actions concurrency groups hold one pending run and cancel the rest; cloud sessions have an account-wide ceiling with no per-task cap. The pool is therefore the dispatcher's claim step. `WORKER_CAP` is a repository variable, start at **2**. Raising it buys throughput and merge conflicts in equal measure; the `Touches:` overlap check and the organization agent's dependency chains are what make a higher cap safe.

## Guardrails

- `PIPELINE_PAUSED=true` (repository variable) stops the dispatcher and `fire.yml`. Sessions already running finish; nothing new starts. Scheduled tasks can also be disabled individually in the Claude UI.
- Every role prompt states a turn budget and a wall-clock budget, and ends the session cleanly with a comment when either is hit.
- Loop caps: 2 plan rejections, 3 rework rounds. Both exit to `needs-human`, which assigns Tristan and sends a push notification.
- Agents never create labels; the label set is fixed here and created once in setup.
- `needs-human` is terminal for automation. Tristan clears it by hand (and usually re-labels `ready` or `plan-proposed` to resume).
- Discovered work during an arc becomes a new issue with `Touches:` and `Blocked by:` filled in, labeled `arc` and `blocked`, under the right milestone. It is never a TODO in code or a scope creep in the current PR.
- Role prompts and this document change only through PRs into `dev`, like code.

## One-time setup (Tristan)

1. Create `dev` from `main`. Protect `dev` and `main`: PRs only, CI required. Keep `main` default.
2. Create the labels in the table above.
3. Add repository variables `WORKER_CAP=2`, `PIPELINE_PAUSED=false`, and the secret `GITHUB_MCP_PAT` (already used by `.mcp.json`; needs `repo` and `project` scopes).
4. Install the Claude GitHub App on `tsebens/silent_water` (required for native triggers).
5. Create five scheduled tasks (organization, plan-review, development, review, rework) in the Claude Code web UI, each with the stub prompt above, the `silent_water` environment, and the trigger from the table. The development task is API-only (no schedule, no GitHub trigger).
6. Copy the development task's fire URL and token into repository secrets `FIRE_URL_DEV` and `FIRE_TOKEN_DEV`. If `fire.yml` is needed for issue events, do the same for the organization and plan-review tasks.
7. **Verify** with a throwaway `concept` issue: does a native `issues.labeled` trigger with a label filter fire, and can the session see which issue fired it? Does `ci.yml` adding `ci-green` with `GITHUB_TOKEN` fire the review task? Record the answers in [#62](https://github.com/tsebens/silent_water/issues/62) and switch the trigger table rows accordingly.
8. Run one deliberately tiny concept (a docs fix) end to end before trusting the pipeline with gameplay work.

## Open items

- Confirm native issue-trigger filters and payload (setup step 7); until then the organization and plan-review hops are specified with both options.
- Decide whether `Blocked by:` lines in the body or GitHub's native issue dependencies are the source for the dispatcher. Body lines are simpler to read from shell; native dependencies show on the board. The dispatcher can read both and treat the union as blocking.
- The fire API is marked experimental. Keep the curl in one composite action so a header change is a one-line fix.
