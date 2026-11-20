# Development process

How work moves from an idea to `main` in Silent Water, and which agent does what. This is the spec the pipeline is built from: the role prompts in `.github/agents/`, the workflows in `.github/workflows/`, and the scheduled tasks on Tristan's Claude account all implement what is written here. When they disagree with this document, this document wins and the implementation is a bug.

Tracked by [#62](https://github.com/tsebens/silent_water/issues/62).

> **Migration in progress** ([#93](https://github.com/tsebens/silent_water/issues/93)). The pipeline is moving from Claude scheduled tasks to GitHub Actions jobs that run the Claude Code CLI directly (`.github/actions/claude-role`), one role at a time, in reverse order. The scheduled tasks are disabled. Status:
>
> | Role | Mechanism now |
> | --- | --- |
> | Review | **Actions**: `role-review.yml` on `pull_request_target.labeled` = `ci-green`, runs from the base branch, merges accepted PRs ([#95](https://github.com/tsebens/silent_water/issues/95)) |
> | Development (build and rework) | **Actions**: `role-development.yml`. Build via `workflow_dispatch(arc)` from the dispatcher (or by hand); rework on `pull_request_target.labeled` = `changes-requested` on `arc/*` PRs, by the reviewer or by CI ([#101](https://github.com/tsebens/silent_water/issues/101)) |
> | Organization, plan review | Not yet migrated; described below as scheduled tasks, currently off |
> | Dispatcher | **Actions**, rebuilt ([#107](https://github.com/tsebens/silent_water/issues/107)): label-change and close events plus a 30-minute cron; worker cap, `Touches:` overlap, unblocking, board projection. The only thing that starts builds |
> | CI | Actions; applies `ci-green` with the PAT so the event starts the review job |
>
> Identity: roles act with the `GH_MCP_PAT` token (as Tristan) for now; a GitHub App token can replace it later as a secret swap. Configuration is files in this repo plus the secrets `CLAUDE_CODE_OAUTH_TOKEN` and `GH_MCP_PAT`. The sections below are rewritten role by role as each one migrates; until then, this note wins where they disagree.

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
| `arc/<issue>-<slug>` | One arc's work, branched from `dev` | One development agent, which stays with the branch until its PR merges |

Rules:

- Arc branches are created from the head of `dev`, never from `main`.
- Before opening a PR, the development agent merges `dev` into the arc branch and re-runs the checks. If `dev` moves again before the PR merges, the review agent requests changes and the development agent integrates it; the review agent never resolves conflicts.
- Arc PRs target `dev` and are **squash-merged**, so `dev` reads as one commit per arc and `dev → main` is a readable diff.
- Branch protection: `dev` and `main` accept changes only through PRs with green CI. `main` is Tristan's alone.

## Roles

Six roles. Five are Claude sessions; the dispatcher is deterministic code.

| Role | Runs as | Input | Output |
| --- | --- | --- | --- |
| **Head developer** | Interactive cloud session with Tristan | Conversation | A `concept` issue, labeled `plan-needed` when its breakdown is wanted |
| **Organization agent** | Scheduled task | A concept carrying `plan-needed` | A proposed breakdown into arcs, posted as a comment; `plan-needed` cleared, `plan-proposed` applied |
| **Plan-review agent** | Scheduled task | A `plan-proposed` concept | Either the arc issues (created under milestones) and `plan-approved`, or objections, `plan-rejected`, then `plan-needed` |
| **Dispatcher** | GitHub Action (no Claude) | Labels, PR merges, a 15-minute cron | Marks arcs `ready`, claims them up to the worker cap, fires development agents |
| **Development agent** | Scheduled task, then subscribed to its PR | A `claimed` arc | An arc branch and a PR into `dev`; stays with the PR through CI and review until it merges |
| **Review agent** | Scheduled task | A PR carrying `ci-green` (green and awaiting review) | `ci-green` cleared, then squash-merge and Done, or `changes-requested` with a rework counter |

### Head developer

Talks with Tristan about a feature, fix or adjustment until the idea is solid. Writes one `concept` issue per idea: the problem, the intended player experience, constraints, what is explicitly out of scope, and any design-doc sections it touches. Does not break the work down and does not write code. If the conversation settles an open design question, records it as a `Decision:` issue and in the design doc, as CLAUDE.md requires.

When the concept is ready for breakdown, applies `plan-needed`. It goes on **last, in its own API call**, after `concept` and any other label the concept gets: one labeled event, one organization-agent run. `concept` itself is only the permanent marker of a concept issue and fires nothing.

### Organization agent

Reads the concept, the design doc, the open milestones and the open arcs. Decides whether the concept is one arc or several. For each proposed arc it writes:

- a title in the milestone scheme, `M<n>.<k> · <name>`, under an existing milestone where one fits; if nothing fits, it proposes a new `M<n> · <name>` milestone and stops with `needs-human` instead of inventing one
- a scope statement and acceptance criteria that a development agent can verify headless
- `Touches:` the systems or folders the arc will change (its blast radius)
- `Blocked by:` other arcs it depends on, including arcs from the same concept and outstanding arcs already on the board. Two arcs with overlapping `Touches:` are chained even when logically independent, so only one of them is in flight at a time

Posts the breakdown as a comment on the concept issue, then in one step removes `plan-needed` (and `plan-rejected` if present) and applies `plan-proposed`. Creates no issues itself. If the concept already carries `plan-proposed` when the agent starts, the firing was late or a duplicate: it does nothing and ends.

### Plan-review agent

A second pair of eyes before one misread concept fans out into several wasted development runs. Checks the proposal against the concept and the design doc: is anything missing, is anything out of scope, are the dependencies right, is each arc small enough to finish in one session, are the acceptance criteria testable. On approval it creates the arc issues as sub-issues of their milestones with the `arc` label, copies `Touches:` and `Blocked by:` into each body, adds them to the board in Backlog, labels unblocked arcs `ready` and the rest `blocked`, and applies `plan-approved` to the concept. On rejection it comments its objections, removes `plan-proposed`, applies `plan-rejected`, and then applies `plan-needed` **last, in its own API call**; that final label is what fires the organization agent again. Two rejections on one concept escalate to `needs-human` instead, and the escalation does not apply `plan-needed`.

### Dispatcher

`.github/workflows/dispatch.yml` running `.github/scripts/dispatch.sh` (unit-tested by `test_dispatch.sh` in CI; dry-runnable from the Actions tab). Deterministic shell against the GitHub API, no Claude. It runs on every label change and close on issues and PRs (the primary clock: a merge or a new `ready` is handled within seconds) and on a 30-minute cron (recovery from a lost event). Each run:

1. Exits immediately if the repository variable `PIPELINE_PAUSED` is `true`.
2. **Mirrors the board.** Arcs whose board Status is Ready but which lack the `ready` label get it, so Tristan can promote work from the board UI.
3. **Unblocks.** For each `blocked` arc, if every issue in its `Blocked by:` line and in GitHub's native blocked-by dependencies is closed, swap `blocked` for `ready`.
4. **Claims.** In-flight count = open arcs labeled `claimed` or `in-review` (a PR awaiting review or rework still occupies its slice of `dev`). While in-flight is below `WORKER_CAP` (repository variable, start at 2): take the oldest `ready` arc whose `Touches:` do not overlap any in-flight arc (prefix-directory match; an arc with no `Touches:` line counts as touching everything), swap `ready` for `claimed`, start `role-development.yml` with `gh workflow run`, and comment the run URL on the arc. If the run cannot be started, revert to `ready`.
5. **Projects labels onto the board**: arcs `blocked` → Backlog, `ready` → Ready, `claimed` → In progress, `in-review` → In review (or In progress while the PR carries `changes-requested`), closed → Done; concepts `plan-approved` → In progress, otherwise Backlog, closed → Done. Closed arcs also lose any stale state label. Items carrying `needs-human` are left where they are.
6. **Logs anomalies**: an arc PR that has carried `changes-requested` for 30+ minutes with no rework run clearing it.

The dispatcher is the only thing that starts builds: `ready` is a queue marker, not a trigger.

### Development agent

Fired with an arc number. Reads the arc, its milestone, the design doc and the code it touches. Writes a short plan as a comment on the arc, moves the arc to In progress on the board, creates `arc/<n>-<slug>` from the head of `dev`, and implements with the repo conventions (typed GDScript, small scenes, signals, Resources for content). Runs `tools/check.sh` until green. Adds or extends tests under `tests/unit/` for behaviour it changed. Merges `dev` into the branch and re-runs the checks. Opens a PR into `dev` whose body states what changed, how it was verified, and `Closes #<n>`. Swaps `claimed` for `in-review` and moves the arc to In review.

It then **subscribes to the PR** (`subscribe_pr_activity`) and ends its turn instead of exiting. The session idles with its full context (plan, code, reasoning) and is woken by each PR event:

- **CI failed:** fix it, re-run `tools/check.sh`, push. The review agent never sees a red PR.
- **Changes requested** (the review agent applied `changes-requested`): move the arc to In progress, address every point (including merging `dev` if asked), re-run the checks, push, reply to the review with what was done, remove `changes-requested`, move the arc back to In review. CI runs on the push and, when green, the review agent fires again.
- **`needs-human` applied** (the review agent hit the rework cap): do nothing further; unsubscribe and exit.
- **Merged or closed:** confirm the arc is Done and closed, unsubscribe, exit.

The development agent never touches the rework counter; only the review agent does. If it cannot finish the arc in the first place (larger than it looked, or a dependency is missing), it comments why, applies `needs-human` and exits without a PR.

Only one session may hold a PR's event stream, so no other role subscribes to arc PRs, and the web UI's auto-fix toggle stays off for them.

### Review agent

Fires only on a PR that CI has already passed (see the trigger table). Reviews for correctness against the arc's acceptance criteria, adherence to CLAUDE.md and the design doc, test coverage, and whether the branch is up to date with `dev`.

Its trigger filter matches on labels the PR carries, so every label the review agent applies would fire it again on the same head while `ci-green` is still present (observed on #81: the `changes-requested` and `rework:1` applications each started a fresh review session). Two layers make that harmless. First, **the review agent removes `ci-green` as its first label change on every verdict path**, before `approved`, `changes-requested`, `rework:n` or `needs-human`; `ci-green` means "green and awaiting review", mirroring `plan-needed`, and `ci.yml` re-adds it on the next green run. Second, **stop conditions**: if the PR carries `changes-requested` or `approved`, a verdict for this head already exists; if it is merged or closed, there is nothing to review. In each case the agent does nothing and ends. A session fired by a leftover label event therefore never re-reviews a head, never bumps the rework counter twice for one round, and never escalates on its own echo.

Then one of:

- **Accept:** removes `ci-green`, comments a short review, applies `approved`, squash-merges into `dev` with the arc title as the commit subject, deletes the branch, moves the arc to Done and confirms it is closed. If that was the concept's last open arc, it closes the concept as Done too. Nothing fires after a merge except the dispatcher.
- **Request changes:** removes `ci-green`, comments the specific, actionable changes, increments the rework counter (`rework:1` → `rework:2` → `rework:3`), applies `changes-requested`, and moves the arc to In progress. A merge conflict with `dev`, or stale CI, is a request-changes outcome, never something the review agent fixes.
- **Escalate:** if the PR already carries `rework:3`, it does not request changes again. It removes `ci-green`, applies `needs-human`, assigns Tristan, summarises why the PR keeps failing, and sends a push notification.

Commits and PRs in this pipeline carry Tristan's GitHub identity (that is how cloud sessions push), so the review agent cannot use GitHub's formal approve; the `approved` label and the review comment are the record. The review agent does not subscribe to the PR; its session ends when its verdict is posted.

Rework is done by the development agent that opened the PR, woken through its subscription (see above). There is no separate rework role; see Open items for the deferred fallback.

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
| `concept` | issue | Marks a concept issue; fires nothing | Head developer | never |
| `plan-needed` | concept | Breakdown wanted now; fires the organization agent | Head developer, plan-review agent (on rejection); always last, in its own call | Organization agent |
| `plan-proposed` | concept | Breakdown awaits plan review | Organization agent | Plan-review agent |
| `plan-approved` | concept | Arcs created; concept is done when they are | Plan-review agent | never |
| `plan-rejected` | concept | Breakdown sent back; counts toward the plan cap | Plan-review agent (before `plan-needed`) | Organization agent |
| `arc` | issue | A unit of work | Plan-review agent | never |
| `blocked` | arc | Waits on `Blocked by:` issues | Plan-review agent | Dispatcher |
| `ready` | arc | Eligible for claiming | Plan-review agent, dispatcher, Tristan | Dispatcher |
| `claimed` | arc | A development agent has it | Dispatcher | Development agent |
| `in-review` | arc | Has an open PR | Development agent | Review agent (on merge) |
| `ci-green` | PR | CI passed on the current head and the review is pending; fires the review agent | CI workflow | Review agent (first label change of any verdict); CI workflow (on next push) |
| `changes-requested` | PR | Rework needed | Review agent | Development agent |
| `rework:1` `rework:2` `rework:3` | PR | Rounds of rework so far | Review agent | never (replaced) |
| `approved` | PR | Review passed; merged | Review agent | never |
| `needs-human` | any | Pipeline stopped here; Tristan decides | Any agent | Tristan |

### Board status mirror

| Board Status | Concept | Arc |
| --- | --- | --- |
| Backlog | Awaiting breakdown or plan review | `blocked` |
| Ready | Not used | `ready` |
| In progress | `plan-approved`, arcs in flight | `claimed`, or PR has `changes-requested` |
| In review | Not used | `in-review` and PR awaiting CI or review |
| Done | All arcs Done (the review agent closes it with the last arc) | Merged and closed |

## State machine

### Concept

```
created(concept) ─► plan-needed ─► organization agent ─► plan-proposed ─► plan-review agent
                     (applied last,   (clears plan-needed)                       │
                      on its own)                                                │
                                              ┌──────────────────────────────────┤
                                              ▼                                  ▼
                                   plan-rejected (×1), then plan-needed    plan-approved → arcs exist
                                              │
                                              ▼
                                   organization agent ─► plan-proposed ─► plan-review agent
                                   (clears plan-needed,                          │
                                    plan-rejected)                               │
                                              ┌──────────────────────────────────┤
                                              ▼                                  ▼
                                   plan-rejected (×2) → needs-human        plan-approved
                                   (no plan-needed; nothing fires)
```

### Arc

```
blocked ──(blockers closed)──► ready ──(dispatcher, cap)──► claimed ──(dev agent)──► in-review
                                                                                      │
                                              ┌───────────────────────────────────────┤
                                              ▼                                       ▼
                                      PR ci-green → review agent              CI red → wait for push
                                              │
                                   (clears ci-green first)
                        ┌─────────────────────┼─────────────────────────┐
                        ▼                     ▼                         ▼
                   approved, merged     changes-requested          rework:3 already
                   arc Done, closed     rework:n+1                 → needs-human
                                              │
                                              ▼
                                        dev session wakes → push → CI → ci-green → review agent
```

## Triggers

Each Claude role is a scheduled task on Tristan's Claude account, configured in the Claude Code web UI, running in the `silent_water` cloud environment (which installs Godot). The task's stored prompt is a stub of the form:

> You are the *&lt;role&gt;* in the Silent Water pipeline. Read `.github/agents/<role>.md` in the repository and follow it exactly. Your input is in the trigger context or fire payload or, for pull request events, the checked-out branch.

Everything else is in the repo: the exact stub text and the conventions shared by all roles are in [`.github/agents/README.md`](../.github/agents/README.md).

| Role | Event | Filter | How fired | Input the session gets |
| --- | --- | --- | --- | --- |
| Organization | `issues.labeled` | label = `plan-needed` | Native trigger | Issue number, from `<github-trigger-context>` |
| Plan review | `issues.labeled` | label = `plan-proposed` | Native trigger | Issue number, from `<github-trigger-context>` |
| Dispatcher | `issues` labeled/closed, `pull_request` closed, cron `*/15` | — | GitHub Action | Event |
| Development | Dispatcher claim | — | Dispatcher calls the fire API with `{"text": "arc #n"}`; the session then subscribes to its own PR and is woken by PR events, not re-fired | Arc number, from `<routine-fire-payload>`; then PR events |
| Review | `pull_request.labeled` | label = `ci-green`, base = `dev` | Native trigger | Checkout at PR head; PR found from branch |

Notes:

- Native pull-request triggers support filters on Author, Title, Body, Base branch, Head branch, Labels, Is draft and Is merged, and the session checks out the PR head. Every PR hop uses them.
- Native issue triggers are confirmed (first end-to-end run, #74, recorded on #68). A label filter fires, and the session receives a `<github-trigger-context>` block with the event type, the repository, and the issue number and URL. It does **not** say which label was added. The filter matches on the labels **present** on the issue at the time of the event, not on the label just added, so a filter on a permanent label such as `concept` fires again on every later label change. That is why the organization hop filters on the transient `plan-needed`, and why `plan-needed` is always applied last, in its own call. The role reads the issue's current labels from GitHub to learn its state.
- `fire.yml` (an Action that POSTs to a task's fire endpoint with the issue number as `text`) is not needed for the organization or plan-review hops. Whether to keep it as a general fallback is [#65](https://github.com/tsebens/silent_water/issues/65), Tristan's call.
- CI gating: `ci.yml` removes `ci-green` at the start of every PR run and adds it on success. The label event, not the push, is what fires the review agent, so the review agent never looks at a red or pending PR.
- **Filter labels re-fire their role until cleared.** A label filter matches on the labels present on the issue or PR, not on the label just added, so any label change on an item that still carries a role's filter label fires that role again, including the role's own label changes. Every filter label is therefore transient and cleared by the role it fires: `plan-needed` by the organization agent when it posts the proposal, `ci-green` by the review agent as the first label change of its verdict. Each role also has stop conditions for the state its own verdict leaves behind (`plan-proposed`; `changes-requested`, `approved`, merged or closed), so a duplicate firing that slips through finds nothing to do. #81 is the observed instance for the review hop; see [#83](https://github.com/tsebens/silent_water/issues/83).
- PR subscriptions deliver review, comment, CI and merge events for one PR into the session that subscribed, waking it from idle with its context intact. This is how rework reaches the development agent without a fired session, so `changes-requested` has no trigger row.
- Native GitHub triggers do not queue. Events over the hourly caps are dropped, and a run blocked by the concurrent-session ceiling does not start. The labels hold the state and the dispatcher's cron retries, so nothing is lost; it is at most late.
- Events caused by a workflow's `GITHUB_TOKEN` do not start other **Actions** workflows (which is why `fire.yml` and `dispatch.yml` use the `GH_MCP_PAT` secret where they must chain), but they do reach the Claude GitHub App's webhooks, which is what the `ci-green` row relies on. Setup step 7 confirms this.

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
2. Create the labels in the table above: `concept`, `plan-needed`, `plan-proposed`, `plan-approved`, `plan-rejected`, `arc`, `blocked`, `ready`, `claimed`, `in-review`, `ci-green`, `changes-requested`, `rework:1`, `rework:2`, `rework:3`, `approved`, `needs-human`. The table is the single list; agents never create labels.
3. Add repository variables `WORKER_CAP=2`, `PIPELINE_PAUSED=false`, and the secret `GH_MCP_PAT` (same value as the cloud environment's `GITHUB_MCP_PAT` used by `.mcp.json`; Actions reserves the `GITHUB_*` prefix for secrets. Needs issues read/write, pull requests read and user-projects read/write, or classic `repo` + `project`).
4. Install the Claude GitHub App on `tsebens/silent_water` (required for native triggers).
5. Create four scheduled tasks (organization, plan-review, development, review) in the Claude Code web UI, each with the stub prompt above, the `silent_water` environment, and the trigger from the table. The development task is API-only (no schedule, no GitHub trigger).
6. Copy the development task's fire URL and token into repository secrets `FIRE_URL_DEV` and `FIRE_TOKEN_DEV`. The organization and plan-review tasks use native issue triggers and need no fire secrets.
7. **Verify** the remaining PR-side questions with a throwaway arc: does `ci.yml` adding `ci-green` with `GITHUB_TOKEN` fire the review task? Does a development session that subscribed to its PR still wake after hours idle, and does a review posted under the same GitHub identity wake it? Record the answers in [#62](https://github.com/tsebens/silent_water/issues/62). The issue-side question (do native `issues.labeled` triggers fire, and what does the session see) is answered; see the trigger-table notes.
8. Run one deliberately tiny concept (a docs fix) end to end before trusting the pipeline with gameplay work.

## Open items

- **Answered:** native issue-trigger filters fire, the session receives the issue number in `<github-trigger-context>`, and the filter matches on labels present on the issue rather than the label just added (observed on #74, recorded on #68). The organization hop therefore fires on the transient `plan-needed`; see [#77](https://github.com/tsebens/silent_water/issues/77).
- **Deferred: a fallback rework agent.** If a subscribed development session fails to wake (container reclaimed, subscription lost, session died) a PR could sit with `changes-requested` indefinitely. The fix would be a dispatcher check for `changes-requested` PRs with no push for 30+ minutes that fires a rework task to take over. Not built until it is observed to be a problem; until then such a PR surfaces in the dispatcher's run log and Tristan re-fires or resumes the session by hand.
- Decide whether `Blocked by:` lines in the body or GitHub's native issue dependencies are the source for the dispatcher. Body lines are simpler to read from shell; native dependencies show on the board. The dispatcher can read both and treat the union as blocking.
- The fire API is marked experimental. The curl lives in exactly one place, `.github/scripts/fire.sh`, so a header change is a one-line fix.
