# Development process

How work moves from an idea to `main` in Silent Water, and which agent does what. This is the spec the pipeline is built from: the role prompts in `.github/agents/`, the workflows in `.github/workflows/`, the shared actions in `.github/actions/` and the dispatcher in `.github/scripts/` all implement what is written here. When they disagree with this document, this document wins and the implementation is a bug.

The pipeline runs entirely as **GitHub Actions**. Each Claude role is a workflow job that runs [`anthropics/claude-code-action`](https://github.com/anthropics/claude-code-action) on Tristan's Claude subscription; the dispatcher is plain shell. Nothing about the pipeline lives outside this repository except secrets and two GitHub Apps that give the agents their identities.

Tracked by [#62](https://github.com/tsebens/silent_water/issues/62); the migration to Actions is [#93](https://github.com/tsebens/silent_water/issues/93).

## Principles

- **The repo is the source of truth.** Roles, labels, the state machine, the dispatcher and every trigger live in version control and change through pull requests into `dev`. A change to the pipeline deploys when it merges to `dev`.
- **Issues are the queue.** Work waits as an issue in a known state, never as a pending run. A missed event costs minutes, not work: the dispatcher's cron reconciles from the labels.
- **Labels are the only state agents touch.** Workflows fire on a label being *added*. The board is a projection of the labels, written by the dispatcher alone, so agents never need board access and the board can never disagree with the labels for long.
- **Instructions come from the branch the workflow ran from, never from the PR under review.** PR-triggered roles use `pull_request_target`, which runs the base branch's workflow and checks out the base branch; the PR head is fetched as content. A PR cannot rewrite the instructions of the agent reviewing it.
- **Two identities.** The pipeline App authors work; the reviewer App reviews it. Different actors, so a review approval is a real GitHub approval and `dev` can require one.
- **One human gate per stage, and it is not Tristan.** Agents check each other. Tristan sees the pipeline when it stalls (`needs-human`) and when `dev` merges to `main`.
- **Bounded loops.** Every retry loop has a counter and an exit to a human.

## Branches

| Branch | Purpose | Who writes |
| --- | --- | --- |
| `dev` | **Default branch.** Integration; every arc lands here; the pipeline deploys from here | Review agent, by squash-merging arc PRs; Tristan, by merging other PRs |
| `main` | Release branch: playable, promoted by Tristan | Tristan, by merging `dev` |
| `arc/<issue>-<slug>` | One arc's work, branched from `dev` | The development agent, then rework agents |

Rules:

- `dev` is the repository's default branch so that issue-triggered and scheduled workflows run from it and pull requests default to it. `main` is the release branch by convention and branch rules, not by the default flag.
- Arc branches are created from the head of `dev`, never from `main`.
- Before opening a PR, the development agent merges `dev` into the arc branch and re-runs the checks. If `dev` moves again before the PR merges, the review agent requests changes and a rework agent integrates it; the review agent never resolves conflicts.
- Arc PRs target `dev` and are **squash-merged**, so `dev` reads as one commit per arc and `dev → main` is a readable diff. The reviewer deletes the merged branch.
- Branch protection: `dev` requires green CI and one approval (the reviewer App supplies it for arc PRs); `main` accepts only PRs from `dev`, merged by Tristan.

## Roles

Seven roles. Six are Claude jobs; the dispatcher is deterministic code.

| Role | Runs as | Fired by | Input | Output |
| --- | --- | --- | --- | --- |
| **Head developer** | Interactive Claude session with Tristan | Conversation | Ideas | A `concept` issue |
| **Organization agent** | `role-organization.yml`, pipeline App | `concept` or `plan-rejected` added to an issue | The concept | A proposed breakdown as a comment; `plan-proposed` |
| **Plan-review agent** | `role-plan-review.yml`, pipeline App | `plan-proposed` added | The proposal | Arc issues (`ready` or `blocked`) and `plan-approved`, or objections and `plan-rejected` |
| **Dispatcher** | `dispatch.yml`, PAT, no Claude | Any label change or close on issues and PRs; cron `*/15` | Labels | Unblocks arcs, claims up to the worker cap, starts development runs, projects labels onto the board |
| **Development agent** | `role-development.yml`, pipeline App | `gh workflow run` from the dispatcher | A `claimed` arc | An arc branch, a PR into `dev` with a `## Handoff` comment; `in-review` |
| **Review agent** | `role-review.yml`, **reviewer App** | `ci-green` added to a PR into `dev` | The PR | Approval and (for arcs) squash-merge, or a changes-requested review with a rework counter |
| **Rework agent** | `role-rework.yml`, pipeline App | `changes-requested` added to an arc PR | The PR, its handoff and the review or CI failure | A pushed fix and a `## Rework` reply; `changes-requested` cleared |

### Head developer

Talks with Tristan about a feature, fix or adjustment until the idea is solid. Writes one `concept` issue per idea: the problem, the intended player experience, constraints, what is explicitly out of scope, and any design-doc sections it touches. Does not break the work down and does not write code. If the conversation settles an open design question, records it as a `Decision:` issue and in the design doc, as CLAUDE.md requires. Applying the `concept` label is what starts the organization job, so the head developer applies it when the concept is ready for breakdown (create the issue first, label it when the text is final).

### Organization agent

Reads the concept, the design doc, the open milestones and the open arcs. Decides whether the concept is one arc or several. For each proposed arc it writes a title in the milestone scheme (`M<n>.<k> · <name>`, under an existing milestone; if none fits it proposes one and escalates), a scope, headless acceptance criteria, `Touches:` (its blast radius) and `Blocked by:` (dependencies, including chaining any two arcs whose `Touches:` overlap). Posts the breakdown as a comment and applies `plan-proposed` (removing `plan-rejected` on a retry). Creates no issues.

### Plan-review agent

Checks the proposal against the concept and the design doc: fidelity, design consistency, size (one development job each), verifiability, dependencies, naming. On approval it creates the arcs as sub-issues of their milestones with `arc` and `blocked`, then adds `ready` as a separate final label change to those with no open blockers, and applies `plan-approved`. On rejection it comments objections and swaps `plan-proposed` for `plan-rejected`, which starts another organization job. A second rejection escalates to `needs-human` instead.

### Dispatcher

`.github/workflows/dispatch.yml` running `.github/scripts/dispatch.sh` (unit-tested by `test_dispatch.sh` in CI; dry-runnable from the Actions tab). Each run:

1. Exits if the repository variable `PIPELINE_PAUSED` is `true`.
2. **Mirrors the board.** Arcs whose board Status is Ready but which lack the `ready` label get it, so Tristan can promote work from the board UI.
3. **Unblocks.** For each `blocked` arc, if every issue in its `Blocked by:` line and in GitHub's native blocked-by dependencies is closed, swap `blocked` for `ready`.
4. **Claims.** In-flight count = open arcs labeled `claimed` or `in-review`. While below `WORKER_CAP` (repository variable, start at 2): take the oldest `ready` arc whose `Touches:` do not overlap any in-flight arc (an arc with no `Touches:` line counts as touching everything), swap `ready` for `claimed`, start `role-development.yml` with `gh workflow run` and comment the run URL on the arc. If the run cannot be started, revert to `ready`.
5. **Projects labels onto the board**: arcs `blocked` → Backlog, `ready` → Ready, `claimed` → In progress, `in-review` → In review (or In progress while the PR carries `changes-requested`), closed → Done; concepts `plan-approved` → In progress, otherwise Backlog, closed → Done. Items carrying `needs-human` are left where they are.
6. **Logs anomalies**: an arc PR that has carried `changes-requested` for 30+ minutes with no rework run clearing it.

It runs on every label change and close on issues and PRs, and every 15 minutes, so a missed event is picked up within 15 minutes.

### Development agent

Started by the dispatcher with the arc number. Reads the arc, its concept and milestone, the design doc and the code it touches. Comments a short plan, creates `arc/<n>-<slug>` from the head of `dev`, implements with the repo conventions, adds or extends tests, runs `tools/check.sh` until green, updates docs, merges `dev` into the branch and re-checks, pushes, and opens a PR into `dev` whose body states what changed, how it was verified, the acceptance checklist, and `Closes #<n>`. Leaves a `## Handoff` comment on the PR (decisions, dead ends, what to look at first if it comes back) for the rework agent that may follow. Swaps `claimed` for `in-review` and ends. If it cannot finish, it pushes what it has, comments, applies `needs-human` and opens no PR.

### Review agent

Runs as the reviewer App on every PR into `dev` whose current head just passed CI. Reads the PR, the arc's acceptance criteria, CLAUDE.md and the design doc, and the diff fetched from the head branch (never instructions from it). Checks acceptance, scope, conventions, correctness, tests, integration with `dev`, docs, and, for changes to pipeline files, that no guardrail is weakened without a stated reason. Then one of:

- **Accept:** an approving GitHub review (`## Review: accepted` with the head SHA), `approved`. For an arc PR, squash-merge with the arc title, delete the branch, confirm the arc is closed, close the concept if it was the last arc. For other PRs, stop after approval; Tristan merges.
- **Request changes:** a changes-requested GitHub review with numbered, file-and-line items, the counter bumped (`rework:1` → `rework:2` → `rework:3`), then `changes-requested` as the last label change, which starts the rework job. A merge conflict with `dev` is a request-changes outcome, never something the review agent fixes.
- **Escalate:** if the PR already carries `rework:3`, no further review round: `## Review: escalated`, `needs-human`, assign Tristan.

### Rework agent

Started when `changes-requested` is added to an arc PR, by the review agent or by CI (which adds it with a `## CI failed` comment when an arc PR goes red). Checks out the head branch, reads the handoff, every review and rework comment and the diff, addresses every point or the CI cause, runs `tools/check.sh` to green, pushes, replies under `## Rework` point by point, and removes `changes-requested`. The push makes CI run; on green, `ci-green` starts the review job on the new head. It never touches the review counter. Three consecutive CI failures with no review in between escalate to `needs-human`.

## Issues and labels

### Issue kinds

| Kind | Title | Label | Created by | Parent |
| --- | --- | --- | --- | --- |
| Concept | Free-form | `concept` | Head developer | None |
| Milestone | `M<n> · <name>` | none | Tristan or head developer | None |
| Arc | `M<n>.<k> · <name>` | `arc` | Plan-review agent | Its milestone |
| Decision | `Decision: …` | `decision` | Anyone | None |
| Discovered work | Free-form | `arc` once scoped | Any agent that finds it | Its milestone |

### Labels that drive automation

Every workflow fires on a label being **added**; a label already present fires nothing. Applying a label is starting a job.

| Label | On | Meaning | Added by (starts) | Removed by |
| --- | --- | --- | --- | --- |
| `concept` | issue | A concept issue, ready for breakdown | Head developer (starts organization) | never |
| `plan-proposed` | concept | Breakdown awaits plan review | Organization agent (starts plan review) | Plan-review agent |
| `plan-rejected` | concept | Breakdown sent back; counts toward the plan cap | Plan-review agent (starts organization) | Organization agent |
| `plan-approved` | concept | Arcs created; concept closes with its last arc | Plan-review agent | never |
| `arc` | issue | A unit of work | Plan-review agent | never |
| `blocked` | arc | Waits on `Blocked by:` issues | Plan-review agent | Dispatcher |
| `ready` | arc | Eligible for claiming | Plan-review agent, dispatcher, Tristan (starts dispatcher) | Dispatcher |
| `claimed` | arc | A development run has it | Dispatcher | Development agent |
| `in-review` | arc | Has an open PR | Development agent | Review agent (merge closes the arc) |
| `ci-green` | PR | CI passed on the current head | CI workflow, with the PAT (starts review) | CI workflow, on the next push |
| `changes-requested` | PR | Rework needed | Review agent, or CI on a red arc PR (starts rework) | Rework agent; review agent on a later accept |
| `rework:1` `rework:2` `rework:3` | PR | Review rounds so far | Review agent | never (replaced) |
| `approved` | PR | Review passed | Review agent | never |
| `needs-human` | any | Pipeline stopped here; Tristan decides | Any agent, with Tristan assigned | Tristan |

`plan-needed` was used by the retired scheduled-task pipeline and is unused now; it may be deleted.

### Board projection

The dispatcher is the only writer of board Status. Agents never update the board; Tristan may, and the dispatcher mirrors a manual move to Ready back onto the `ready` label.

| Board Status | Concept | Arc |
| --- | --- | --- |
| Backlog | Awaiting breakdown or plan review | `blocked` |
| Ready | Not used | `ready` |
| In progress | `plan-approved`, arcs in flight | `claimed`, or `in-review` with `changes-requested` on the PR |
| In review | Not used | `in-review`, PR awaiting CI or review |
| Done | Closed | Closed |

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
blocked ──(blockers closed)──► ready ──(dispatcher, cap)──► claimed ──(development job)──► in-review
                                                                                            │
                                               ┌────────────────────────────────────────────┤
                                               ▼                                            ▼
                                   CI green → ci-green → review agent        CI red → changes-requested → rework agent
                                               │                                            │
                     ┌─────────────────────────┼─────────────────────┐                      │
                     ▼                         ▼                     ▼                      │
              approved, merged         changes-requested        rework:3 already            │
              arc closed, Done         rework:n+1               → needs-human               │
                                               │                                            │
                                               ▼                                            ▼
                                        rework agent → push → CI ───────────────────────────┘
```

## Triggers

| Workflow | Event | Condition (`if:`) | Identity | Godot |
| --- | --- | --- | --- | --- |
| `role-organization.yml` | `issues.labeled` | label is `concept` or `plan-rejected`; issue lacks `needs-human`, `plan-proposed`, `plan-approved` | pipeline App | no |
| `role-plan-review.yml` | `issues.labeled` | label is `plan-proposed`; lacks `needs-human`, `plan-approved` | pipeline App | no |
| `dispatch.yml` | `issues` labeled/unlabeled/closed/reopened; `pull_request` labeled/unlabeled/closed; cron `*/15`; manual (dry run) | — | PAT | no |
| `role-development.yml` | `workflow_dispatch` (input `arc`) | — | pipeline App | yes |
| `role-review.yml` | `pull_request_target.labeled` | label is `ci-green`; base `dev`; same-repo head; not draft; lacks `needs-human` | reviewer App | yes |
| `role-rework.yml` | `pull_request_target.labeled` | label is `changes-requested`; base `dev`; head `arc/*`; same-repo head; lacks `needs-human` | pipeline App | yes |
| `ci.yml` | `push` to `dev`/`main`; `pull_request` | — | PAT for labels | yes |

Every role job also requires `vars.PIPELINE_PAUSED != 'true'`, has a `concurrency` group per issue or PR (so two runs for one item never interleave), and a `timeout-minutes`.

Notes:

- **Workflow source.** Workflows for `issues`, `schedule` and `workflow_dispatch` run from the default branch (`dev`). `pull_request_target` runs the base branch's workflow (also `dev`) and checks out the base branch; the role fetches the PR head as content. `pull_request` (CI only) runs the PR's own merge commit, which is fine for CI because it carries no instructions.
- **Token choice.** Events made with the workflow's own `GITHUB_TOKEN` do not start other workflows. Every label an agent applies goes through its App token, and CI applies `ci-green` and `changes-requested` with the PAT, so the chain continues. Labels applied by Tristan start workflows as usual.
- **Bots.** `claude-code-action` rejects events whose actor is a bot unless allowed; `run-role` sets `allowed_bots: "*"`, because every actor in this chain is one of our Apps or `github-actions[bot]`, and a bot can only produce these events with write access to the repository. The exact-label `if:` conditions and the stop conditions in each role are the loop-breakers.
- **Fork PRs** never run role jobs (`same-repo head` condition) and `allow_fork_prs` is off.
- `run-role` passes `--permission-mode acceptEdits` and an explicit `--allowedTools` list, so the agent has exactly the tools its workflow names.

## Worker pool

There is no native "at most N runs" setting in Actions (`concurrency` groups hold one pending run and cancel the rest), so the pool is the dispatcher's claim step. `WORKER_CAP` is a repository variable, start at **2**. Raising it buys throughput and merge conflicts in equal measure; the `Touches:` overlap check and the organization agent's dependency chains are what make a higher cap safe. The dispatcher's own `concurrency` group is deliberate: any run reconciles everything from the labels, so one pending run is enough.

## Guardrails

- `PIPELINE_PAUSED=true` (repository variable) stops every role job and the dispatcher at the `if:`. Running jobs finish; nothing new starts.
- Every role job has `--max-turns` and `timeout-minutes`; a stuck agent dies, it does not spin.
- Loop caps: 2 plan rejections, 3 review rounds, 3 consecutive CI failures. Each exits to `needs-human`, which assigns Tristan.
- Agents never create labels; the label set is fixed here and created once in setup.
- `needs-human` is terminal for automation. Tristan clears it by hand and re-applies the label that should fire next.
- Discovered work during an arc becomes a new issue, labeled `arc` and `blocked`, under the right milestone. It is never a TODO in code or scope creep in the current PR.
- Role prompts, workflows and this document change only through PRs into `dev`, like code. The review agent reads pipeline changes against the spec on `dev` and flags weakened guardrails.
- Branch protection on `dev`: PRs only, CI required, one approval required. On `main`: PRs from `dev` only, merged by Tristan.

## One-time setup (Tristan)

1. **Default branch.** Settings → General → Default branch → `dev`.
2. **Two GitHub Apps** (Settings → Developer settings → GitHub Apps → New), owned by you, installed on `tsebens/silent_water` only. No webhook. Repository permissions for both: Contents read & write, Issues read & write, Pull requests read & write, Metadata read.
   - `silent-water-pipeline`: identity of the organization, plan-review, development and rework agents.
   - `silent-water-reviewer`: identity of the review agent. Must be a different App so its approvals count.
   For each: note the App ID and generate a private key.
3. **Secrets** (Settings → Secrets and variables → Actions):
   - `CLAUDE_CODE_OAUTH_TOKEN`: run `claude setup-token` locally and paste the result. Runs bill to your subscription.
   - `PIPELINE_APP_ID`, `PIPELINE_APP_PRIVATE_KEY`, `REVIEWER_APP_ID`, `REVIEWER_APP_PRIVATE_KEY`.
   - `GH_MCP_PAT`: the PAT the dispatcher and CI use (issues read/write, pull requests read/write, user projects read/write; classic `repo` + `project` also works). Same value as the cloud environment's `GITHUB_MCP_PAT`.
   - Delete `FIRE_URL_DEV` and `FIRE_TOKEN_DEV`; the fire API is no longer used.
4. **Variables:** `WORKER_CAP=2`, `PIPELINE_PAUSED=false`.
5. **Labels** from the table above (all exist already). `plan-needed` may be deleted.
6. **Branch protection.** `dev`: require a PR, require the `check` status, require 1 approval, dismiss stale approvals on push. `main`: require a PR; restrict who can push to you.
7. **Retire the scheduled tasks** in the Claude Code web UI: disable or delete the four tasks and their triggers. The Claude GitHub App install can stay (it does no harm) but nothing depends on it now.
8. **Dry run.** Actions → Dispatch → Run workflow on `dev` with `dry_run` checked; expect the four steps to complete with no errors against the real board.
9. **Shakedown.** One deliberately tiny concept through the chain. Watch the Actions tab: organization → plan review → dispatch → development → CI → review → merge.

## Open items

- The `allowed_bots: "*"` setting is the broadest guardrail in the chain. If the repo ever grants write access to a third-party bot, replace it with the exact list `silent-water-pipeline[bot],silent-water-reviewer[bot],github-actions[bot]`.
- Whether `Blocked by:` body lines or GitHub's native issue dependencies are the primary source for the dispatcher. It reads both and treats the union as blocking.
- `plan-needed` label: unused; delete when convenient.
