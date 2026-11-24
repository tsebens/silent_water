# Development process

How work moves from an idea to `main` in Silent Water, and which agent does what. This is the spec the pipeline is built from: the role prompts in `.github/agents/`, the workflows in `.github/workflows/`, the shared actions in `.github/actions/` and the dispatcher in `.github/scripts/` all implement what is written here. When they disagree with this document, this document wins and the implementation is a bug.

The pipeline runs entirely as **GitHub Actions**. Each Claude role is a workflow job that runs the Claude Code CLI headless (`claude -p`) through the shared [`claude-role`](../.github/actions/claude-role/action.yml) action, on Tristan's Claude subscription; the dispatcher is plain shell. Everything about the pipeline is a file in this repository except two secrets and a few labels and variables.

Tracked by [#62](https://github.com/tsebens/silent_water/issues/62); the migration to Actions by [#93](https://github.com/tsebens/silent_water/issues/93).

## Principles

- **The repo is the source of truth.** Roles, labels, the state machine, the dispatcher and every trigger live in version control and change through pull requests into `dev`. A change to the pipeline deploys when it merges to `dev`.
- **Issues are the queue.** Work waits as an issue in a known state, never as a pending run. A missed event costs minutes, not work: the dispatcher's cron reconciles from the labels.
- **Labels are the only state agents touch.** Workflows fire on a label being *added*. The board is a projection of the labels, written by the dispatcher alone, so agents never need board access and the board can never disagree with the labels for long.
- **Instructions come from the branch the workflow ran from, never from the PR under review.** PR-triggered jobs use `pull_request_target`, which runs the base branch's workflow and checks out the base branch; the PR head is fetched as content. A PR cannot rewrite the instructions of the agent reviewing it, nor the script of the job that holds the PAT.
- **One human gate per stage, and it is not Tristan.** Agents check each other. Tristan sees the pipeline when it stalls (`needs-human`) and when `dev` merges to `main`.
- **Bounded loops.** Every retry loop has a counter and an exit to a human.

## Branches

| Branch | Purpose | Who writes |
| --- | --- | --- |
| `dev` | **Default branch.** Integration; every arc lands here; the pipeline deploys from here | Review agent, by squash-merging; Tristan |
| `main` | Release branch: playable, promoted by Tristan | Tristan, by merging `dev` |
| `arc/<issue>-<slug>` | One arc's work, branched from `dev` | The development agent (build, then rework) |

Rules:

- `dev` is the default branch so that issue-triggered and scheduled workflows run from it and pull requests default to it. `main` is the release branch by convention and branch rules.
- Arc branches are created from the head of `dev`, never from `main`. Never force-push.
- Before opening a PR, the development agent merges `dev` into the arc branch and re-runs the checks. If `dev` moves again before the PR merges, the review agent requests changes only when a trial merge conflicts or the PR's files intersect the files `dev` changed since the merge base (any intersection under `src/` or `tests/` counts); otherwise the stale base is a non-blocking note. When it does request changes, the development agent (rework mode) integrates it; the review agent never resolves conflicts.
- PRs into `dev` are **squash-merged** by the review agent, so `dev` reads as one commit per change and `dev → main` is a readable diff. The merged branch is deleted.
- Draft PRs are never touched by the pipeline. Open a draft when a PR is not ready to be reviewed and merged.

## Identity

All roles act with the `GH_MCP_PAT` token, i.e. as Tristan. Consequences: agent activity is not distinguishable from Tristan's in history; a formal GitHub approval is impossible (an author cannot approve their own PR), so the review verdict is a review comment plus the `approved` label; `needs-human` assigns Tristan to himself, so GitHub does not notify. A GitHub App token per role would fix all three and is a later secret swap in the workflows, not a redesign.

## Roles

Seven roles. Six are Claude jobs; the dispatcher is deterministic code.

| Role | Runs as | Started by | Input | Output |
| --- | --- | --- | --- | --- |
| **Head developer** | Interactive Claude session with Tristan | Conversation | Ideas | A `concept` issue (labelled `concept` when ready for breakdown) |
| **Organization agent** | `role-organization.yml` | `concept` or `plan-rejected` added to an issue | The concept | A `## Proposed breakdown` comment; `plan-proposed` |
| **Plan-review agent** | `role-plan-review.yml` | `plan-proposed` added | The proposal | Arc issues (`blocked`; the dispatcher promotes) and `plan-approved`; or objections and `plan-rejected` |
| **Dispatcher** | `dispatch.yml`, shell | Any label change or close on issues and PRs; cron `*/30` | Labels | Unblocks arcs, claims up to the worker cap, starts development builds, projects labels onto the board |
| **Development agent** | `role-development.yml` | Build: `gh workflow run` from the dispatcher. Rework: `changes-requested` added to an `arc/*` PR | A `claimed` arc, or a sent-back PR | A PR into `dev` with a `## Handoff` comment; or a pushed fix with a `## Rework` reply |
| **Review agent** | `role-review.yml` | `ci-green` added to a PR into `dev` | The PR | `## Review: accepted` + `approved` + squash-merge; or `## Review: changes requested` + `rework:N` + `changes-requested`; or escalation |
| **Audit agent** | `role-audit.yml` | Hourly cron, gated to every `PIPELINE_REVIEW_INTERVAL` minutes (default 360) and only when something happened; or by hand | The pipeline's own runs, transcripts and timelines since the last audit | A report comment on the standing "Pipeline health" issue; unlabelled `Concept:` proposals assigned to Tristan |

### Head developer

Talks with Tristan about a feature, fix or adjustment until the idea is solid. Writes one concept issue per idea: the problem, the intended player experience, constraints, what is explicitly out of scope, and any design-doc sections it touches. Does not break the work down and does not write code. If the conversation settles an open design question, records it as a `Decision:` issue and in the design doc, as CLAUDE.md requires. Applying the `concept` label starts the organization job, so the head developer creates the issue first and labels it when the text is final.

Thinking that is not final lives in GitHub issues, labelled `design`: a draft `Concept:` issue, or a `Design:` note issue (one per theme, thoughts accumulating as comments). `design` is inert: no workflow triggers on it and no role applies or removes it. To hand off, the head developer, with Tristan, removes `design` and adds `concept` (or, from a `Design:` note when it is ripe, writes `Concept:` issues, and a `Decision:` where the design doc changes).

### Organization agent

Reads the concept, the design doc, the open milestones and the open arcs. Decides whether the concept is one arc or several. For each proposed arc it writes a title as `M<n>.? · <name>` under an existing milestone (the `<k>` is left for plan review to assign; if no milestone fits it proposes one and escalates), a scope, headless acceptance criteria, `Touches:` (its blast radius) and `Blocked by:` (dependencies, including chaining any two arcs whose `Touches:` overlap). Posts the breakdown as a comment and applies `plan-proposed` (removing `plan-rejected` on a retry). Creates no issues. Two rejections on one concept escalate instead of a third proposal.

### Plan-review agent

Checks the proposal against the concept and the design doc: fidelity, design consistency, size (one development job each), verifiability, dependencies, naming (only that the milestone exists and is open; arc numbers are never a rejection reason). On approval it assigns each arc's `<k>` (next free under the milestone, open and closed sub-issues counted; plan review is serialised so this cannot race), creates the arcs as sub-issues of their milestones with `arc` and `blocked` and stops (the dispatcher's Unblock step promotes unblocked arcs to `ready`; the approval comment lists which are ready now), and applies `plan-approved`. On rejection it comments objections and swaps `plan-proposed` for `plan-rejected`, which starts another organization job. A second rejection escalates to `needs-human` instead.

### Dispatcher

`.github/workflows/dispatch.yml` running `.github/scripts/dispatch.sh` (unit-tested by `test_dispatch.sh` in CI; dry-runnable from the Actions tab). Deterministic shell against the GitHub API, no Claude. It runs on every label change and close on issues and PRs (the primary clock: a merge or a new `ready` is handled within seconds) and on a 30-minute cron (recovery from a lost event). PR events use `pull_request_target`, so the workflow and script always come from `dev`; the job holds the PAT and must never run a PR's own copy of itself. Each run:

1. Exits immediately if the repository variable `PIPELINE_PAUSED` is `true`.
2. **Mirrors the board.** Arcs whose board Status is Ready but which lack the `ready` label get it, so Tristan can promote work from the board UI.
3. **Unblocks.** For each `blocked` arc, if every issue in its `Blocked by:` line and in GitHub's native blocked-by dependencies is closed, swap `blocked` for `ready`. A blocker that cannot be looked up counts as still open.
4. **Recovers orphaned claims** (before claiming, so a revert frees its in-flight slot first and `WORKER_CAP` is never exceeded). A `claimed` arc is an orphan if it has no open `arc/<n>-*` PR, its claim comment (the dispatcher's own, which names the run) is older than `ORPHAN_GRACE_MINUTES` (default 15; unrelated to `STALE_MINUTES`) and that development run is no longer queued or in progress (with no run URL in the comment, any live development run counts). The dispatcher logs it, swaps `claimed` for `ready` and comments naming the dead run, with a hidden marker (`dispatcher:orphan-reverted`). If the marker is already in the arc's comments, it was orphaned before: the arc gets `needs-human` and `tsebens` assigned instead of a second revert. No label is created. A failed run lookup counts as alive.
5. **Claims.** First drops a stray `ready` from any arc already `claimed` or `in-review`. In-flight count = open arcs labeled `claimed` or `in-review` (a PR awaiting review or rework still occupies its slice of `dev`). While in-flight is below `WORKER_CAP` (repository variable, start at 2): take the oldest `ready` arc whose `Touches:` do not overlap any in-flight arc (prefix-directory match, except that `docs`, `tests`, `tests/unit` and the design doc are compared by exact path only, so `Touches:` names files there and folders under `src/`; an arc with no `Touches:` line counts as touching everything), swap `ready` for `claimed`, start `role-development.yml` with `gh workflow run`, and comment the run URL on the arc. If the run cannot be started, revert to `ready`.
6. **Closes finished concepts.** Any open `concept` issue carrying `plan-approved` (and not `needs-human`) whose arcs, found by their `Concept: #<n>` line, are all closed is closed as completed; a concept with no arcs is never closed. This backstops the review agent's Accept step 4.
   - **Closes finished milestones.** Any open milestone issue (title `M<n> · …`, not `needs-human`) with at least one sub-issue, all of them closed, is closed as completed once the last sub-issue has been closed for `MILESTONE_QUIET_HOURS` (default 24). The quiet period keeps a milestone that is still receiving arcs open between two of them. A closed milestone that gets new work is reopened by whoever files that work (the head developer, when the concept is written), since plan review only places arcs under open milestones.
7. **Projects labels onto the board**, first adding any arc, concept or `design` issue that is not yet a project item (plan review creates arcs without touching the board): arcs `blocked` → Backlog, `ready` → Ready, `claimed` → In progress, `in-review` → In review (or In progress while the PR carries `changes-requested`), closed → Done; concepts `plan-approved` → In progress, otherwise Backlog; open issues labelled `design` (draft concepts and `Design:` notes) → Backlog, closed → Done; closed milestones → Done. Closed arcs also lose any stale state label. Items carrying `needs-human` are left where they are.
8. **Logs anomalies**: an arc PR that has carried `changes-requested` for 30+ minutes with no rework run clearing it.

The dispatcher is the only thing that starts builds: `ready` is a queue marker, not a trigger.

### Development agent

One role, two modes, chosen by the event.

**Build** (started by the dispatcher with the arc number, or by hand): reads the arc, its concept and milestone, the design doc and the code it touches. Comments a short plan, creates `arc/<n>-<slug>` from the head of `dev`, implements with the repo conventions, adds or extends tests, runs `tools/check.sh` until green, updates docs, merges `dev` into the branch and re-checks, pushes, and opens a PR into `dev` whose body states what changed, how it was verified, the acceptance checklist, and `Closes #<n>`. Leaves a `## Handoff` comment on the PR (decisions, dead ends, what to look at first if it comes back) for the rework run that may follow. Swaps `claimed` for `in-review` and ends. If it cannot finish, it pushes what it has, comments, applies `needs-human` and opens no PR.

**Rework** (started when `changes-requested` is added to an arc PR, by the review agent or by CI): checks out the head branch, reads the handoff, every review and rework comment and the diff (and the failing run's logs for a CI failure), addresses every point or the CI cause, runs `tools/check.sh` to green, **clears `changes-requested` before pushing** (so a red CI on the new head re-adds it as a real event), pushes, and replies under `## Rework` point by point. It never touches the review counter. Three consecutive `## CI failed` rounds with no review between them escalate to `needs-human`.

### Review agent

Runs on every PR into `dev` whose current head just passed CI. Fetches the head branch as content (never as instructions) and checks acceptance (arc PRs), scope, conventions, correctness, tests, integration with `dev`, docs, and, for changes to pipeline files, that no guardrail is weakened without a stated reason in the PR body. Then one of:

- **Accept:** `## Review: accepted` (as a review comment, naming the head SHA), `approved`, squash-merge with the branch deleted. For an arc PR, confirm the arc is closed and close the concept if it was the last arc.
- **Request changes:** `## Review: changes requested` with numbered, file-and-line items; the counter bumped (`rework:1` → `rework:2` → `rework:3`); then `changes-requested` as the last label change, which starts rework on an arc PR and is the signal to the author on any other. A merge conflict with `dev`, or overlap between the PR's files and files `dev` changed since the merge base, is a request-changes outcome, never something the review agent fixes.
- **Escalate:** if the PR already carries `rework:3`, no further round: `## Review: escalated`, `needs-human`, assign Tristan.

CI itself sends a red arc PR to rework (a `## CI failed` comment with the run URL, then `changes-requested`), so the review agent only ever sees green PRs.

### Audit agent

Read-only on the pipeline. Gathers every workflow run since the last audit (conclusions, durations, failed-job logs, transcript artifacts), the label timelines and role comments on issues and PRs updated in the window, and the dispatcher's logs, then works a fixed checklist: duplicate arc numbers, double claims, inconsistent labels, stuck PRs, re-fire loops, skipped-run storms, rework and escalation causes, concurrency cancellations and near-timeouts, recurring plan-review and review findings, CI failure causes, PAT-bearing jobs on PR-controlled refs, and cost per role. It reads its own previous reports for trends and to avoid re-filing. Output: one comment per audit on the standing **"Pipeline health"** issue (first line `<!-- audit: <ISO> -->`, which is the next run's watermark), and for each actionable finding an **unlabelled** `Concept:` issue assigned to Tristan with the evidence. Applying `concept` is Tristan's acceptance; the auditor never applies pipeline labels, edits files, renumbers or closes anything, and uses `needs-human` only for a PAT-bearing job on PR code, a runaway, or budget burning with nothing merging.

The cron runs hourly as a floor; a shell gate enforces the real interval from `vars.PIPELINE_REVIEW_INTERVAL` (a schedule cannot read variables) and skips when no run, issue or PR has changed since the watermark.

## Issues and labels

### Issue kinds

| Kind | Title | Label | Created by | Parent |
| --- | --- | --- | --- | --- |
| Concept | Free-form, usually `Concept: …` | `concept` | Head developer | None |
| Milestone | `M<n> · <name>` | none | Tristan or head developer. Closed by the dispatcher once every sub-issue is closed (after a quiet period); reopened by whoever files new work under it | None |
| Arc | `M<n>.<k> · <name>` (`<k>` assigned by plan review at creation) | `arc` | Plan-review agent (or the head developer for a shakedown) | Its milestone |
| Design note | `Design: …` | `design` | Head developer | None |
| Decision | `Decision: …` | `decision` | Anyone | None |
| Discovered work | Free-form | `arc` once scoped | Any agent that finds it | Its milestone |

### Labels that drive automation

Every workflow fires on a label being **added**; a label already present fires nothing. Applying a label is starting a job.

| Label | On | Meaning | Added by (starts) | Removed by |
| --- | --- | --- | --- | --- |
| `design` | issue | Still being thought through; not ready for breakdown. Inert: fires nothing. Remove it and add `concept` to hand off | Head developer | Head developer |
| `concept` | issue | A concept issue, ready for breakdown | Head developer (starts organization) | never |
| `plan-proposed` | concept | Breakdown awaits plan review | Organization agent (starts plan review) | Plan-review agent |
| `plan-rejected` | concept | Breakdown sent back; counts toward the plan cap | Plan-review agent (starts organization) | Organization agent |
| `plan-approved` | concept | Arcs created; concept closes with its last arc | Plan-review agent | never |
| `arc` | issue | A unit of work | Plan-review agent | never |
| `blocked` | arc | Waits on `Blocked by:` issues | Plan-review agent | Dispatcher |
| `ready` | arc | Queued for the dispatcher | Dispatcher, Tristan | Dispatcher (claim; also drops a stray `ready` from a claimed/in-review arc) |
| `claimed` | arc | A development build has it | Dispatcher | Development agent |
| `in-review` | arc | Has an open PR | Development agent | Dispatcher, when the arc closes |
| `ci-green` | PR | CI passed on the current head | CI workflow, with the PAT (starts review) | CI workflow, on the next push |
| `changes-requested` | PR | Rework needed | Review agent, or CI on a red arc PR (starts rework on arc PRs) | Development agent (rework), before its push; review agent on a later accept |
| `rework:1` `rework:2` `rework:3` | PR | Review rounds so far | Review agent | never (replaced) |
| `approved` | PR | Review passed | Review agent | never |
| `needs-human` | any | Pipeline stopped here; Tristan decides | Any agent, with Tristan assigned | Tristan |

`plan-needed` belonged to the retired scheduled-task pipeline and is unused; it may be deleted.

### Board projection

The dispatcher is the only writer of board Status. Agents never update the board; Tristan may, and the dispatcher mirrors a manual move to Ready back onto the `ready` label.

**Ready holds arcs only.** It is the dispatcher's queue: an arc there is claimed and built. For anything else the column means nothing to automation, so an issue that is not an arc sitting in Ready only looks like stalled work. Work that needs a person (a playtest, files only Tristan has, a decision) stays in **Backlog** with that person assigned until it is done; a milestone's own card stays in Backlog or In progress and goes to Done when the dispatcher closes it.

| Board Status | Concept | Arc | Milestone, human task |
| --- | --- | --- | --- |
| Backlog | Awaiting breakdown or plan review; any open `design` issue (draft concept or `Design:` note) | `blocked` | Open; a human task carries its assignee |
| Ready | Not used | `ready` | Not used |
| In progress | `plan-approved`, arcs in flight | `claimed`, or `in-review` with `changes-requested` on the PR | A milestone with arcs in flight (set by hand) |
| In review | Not used | `in-review`, PR awaiting CI or review | Not used |
| Done | Closed | Closed | Closed |

## State machine

### Concept

```
concept added ─► organization agent ─► plan-proposed ─► plan-review agent
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
blocked ──(blockers closed)──► ready ──(dispatcher, cap)──► claimed ──(build)──► in-review
                                                                                    │
                                          ┌─────────────────────────────────────────┤
                                          ▼                                         ▼
                              CI green → ci-green → review agent       CI red → changes-requested → rework
                                          │                                         │
                ┌─────────────────────────┼─────────────────────┐                   │
                ▼                         ▼                     ▼                   │
         approved, merged         changes-requested        rework:3 already         │
         arc closed, Done         rework:n+1               → needs-human            │
                                          │                                         │
                                          ▼                                         ▼
                                       rework ──(clear label)──► push → CI ─────────┘
```

## Triggers

| Workflow | Event | Condition (`if:`) | Godot |
| --- | --- | --- | --- |
| `role-organization.yml` | `issues.labeled` | label is `concept` or `plan-rejected`; issue lacks `needs-human`, `plan-proposed`, `plan-approved` | no |
| `role-plan-review.yml` | `issues.labeled` | label is `plan-proposed`; lacks `needs-human`, `plan-approved` | no |
| `dispatch.yml` | `issues` labeled/unlabeled/closed/reopened; `pull_request_target` labeled/unlabeled/closed; cron `*/30`; manual (dry run) | — | no |
| `role-development.yml` | `workflow_dispatch(arc)` (build); `pull_request_target.labeled` (rework) | rework: label is `changes-requested`; base `dev`; head `arc/*`; same-repo head; lacks `needs-human` | yes |
| `role-review.yml` | `pull_request_target.labeled` | label is `ci-green`; base `dev`; same-repo head; not draft; lacks `needs-human` | yes |
| `role-audit.yml` | cron `17 * * * *`; manual (`force`) | gate: `PIPELINE_REVIEW_INTERVAL` minutes elapsed (default 360) and activity since the watermark | no |
| `ci.yml` | `push` to `dev`/`main`; `pull_request` | — | yes |

Every job also requires `vars.PIPELINE_PAUSED != 'true'`, has a `concurrency` group per issue or PR (plan review's is repository-wide, so arc numbering cannot race), and a `timeout-minutes`.

Notes:

- **Workflow source.** `issues`, `schedule` and `workflow_dispatch` workflows run from the default branch (`dev`). `pull_request_target` runs the base branch's workflow (also `dev`) and checks out the base branch; the role fetches the PR head as content. `pull_request` (CI only) runs the PR's own merge commit, which is fine for CI because it holds no secrets beyond the label step and no instructions.
- **Token choice.** Events made with a workflow's own `GITHUB_TOKEN` do not start other workflows. Every label an agent applies, and the `ci-green`/`changes-requested` labels CI applies, go through the PAT, so the chain continues.
- **`claude-role`** runs `claude -p` with `--permission-mode acceptEdits`, an explicit `--allowedTools` list, `--strict-mcp-config` (no project MCP servers), the role README + role file as appended system prompt, and the run context as the user message. It fails the job on an empty token or an error result, and uploads the full transcript as an artifact.
- **Fork PRs** never run role jobs (same-repo head condition); CI skips its label steps for them.

## Worker pool

There is no native "at most N runs" setting in Actions (`concurrency` groups hold one pending run and cancel the rest), so the pool is the dispatcher's claim step. `WORKER_CAP` is a repository variable, start at **2**. Raising it buys throughput and merge conflicts in equal measure; the `Touches:` overlap check and the organization agent's dependency chains are what make a higher cap safe.

## Guardrails

- `PIPELINE_PAUSED=true` (repository variable) stops every role job and the dispatcher at the `if:`. Running jobs finish; nothing new starts.
- Every job has a `timeout-minutes`; a stuck agent dies, it does not spin.
- Loop caps: 2 plan rejections, 3 review rounds, 3 consecutive CI failures. Each exits to `needs-human`, which assigns Tristan.
- Agents never create labels; the label set is fixed here.
- `needs-human` is terminal for automation. Tristan clears it by hand and re-applies the label that should fire next.
- Discovered work during an arc becomes a new issue, labeled `arc` and `blocked`, under the right milestone. It is never a TODO in code or scope creep in the current PR.
- Role prompts, workflows and this document change only through PRs into `dev`, like code. The review agent reads pipeline changes against the spec on `dev` and flags weakened guardrails; a PR touching pipeline files states its reason in the body.
- Jobs that hold the PAT (`dispatch.yml`, every role) run only code from `dev`: `pull_request_target`, never `pull_request`.

## Setup

Everything outside the files in this repository:

- **Secrets:** `CLAUDE_CODE_OAUTH_TOKEN` (output of `claude setup-token`; runs bill to that subscription) and `GH_MCP_PAT` (issues and pull requests read/write, user projects read/write, workflows; classic `repo` + `project` + `workflow` also works).
- **Variables:** `WORKER_CAP` (2), `PIPELINE_PAUSED` (`false`), `PIPELINE_REVIEW_INTERVAL` (minutes between audits; default 360 when unset).
- **Labels:** the table above.
- **Branches:** `dev` default; branch protection on `dev` (PRs only, CI required) and `main` (PRs from `dev`, merged by Tristan).

Portability to another repository: copy `.github/` and this document, create the labels, add the two secrets, set the variables, make the integration branch the default.

## Open items

- Identity: a GitHub App token per role (see Identity) when distinguishable history, real approvals or `needs-human` notifications are wanted.
- `plan-needed` label: unused; delete when convenient.
