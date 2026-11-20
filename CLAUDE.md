# Silent Water

First-person co-op submarine stealth game for a crew of four (three viable). The design source of truth is `Silent Water — Design Doc.md`. Read it before any design or gameplay work.

## Work tracking policy (mandatory)

All work is tracked on the GitHub Project board **"silent_water"** (user project #1, owner `tsebens`). This applies to agents and to Tristan alike. Be diligent:

- **Every unit of work has an issue** in `tsebens/silent_water` and is on the board, before work starts.
- **Milestones are parent issues** titled `M<n> · <name>`. Units of work are **sub-issues** titled `M<n>.<k> · <name>`. Break a milestone into sub-issues when it moves to Ready.
- **Status column:** Backlog → Ready → In progress → In review → Done.
  - Move an item to **In progress** when you start it, and **In review** when its PR is open.
  - Move it to **Done** when it is merged or the decision is recorded, then close the issue.
  - A parent milestone is Done when all its sub-issues are.
- **Open design decisions** get an issue titled `Decision: …`. Record the outcome in the issue and in the design doc.
- **Discovered work** (bugs, follow-ups, scope found mid-task) gets a new issue on the board, never a silent TODO.
- Reference the issue in commits and PRs (e.g. `Refs #12`, `Closes #12`).

### Board access

The `github-projects` MCP server in `.mcp.json` provides `projects_list`, `projects_get` and `projects_write`. It authenticates with the `GITHUB_MCP_PAT` environment variable. Status options are Backlog, Ready, In progress, In review and Done. Use the `{"name": "Status", "value": "<option>"}` form for `updated_field`.

Create issues and sub-issues with the regular GitHub MCP tools (`issue_write` with `parent_issue_number`).

The same server carries the `labels` toolset (`list_label`, `get_label`, `label_write`) for creating and editing repository labels. The pipeline's label set is defined in `docs/process.md`; pipeline agents apply labels but never create them.

Pipeline agents (the `role-*.yml` workflows) never touch the board: the dispatcher projects their labels onto it. Interactive sessions and Tristan update the board directly as described above.

### Branches

`dev` is the default branch and the integration branch; all work branches off it and returns to it by PR. `main` is the release branch, promoted from `dev` by Tristan. See `docs/process.md`.

## Roles

Agents with a specific role follow their role doc in addition to this file:

- **Graphic designer and 3D asset modeler:** [`docs/roles/graphic_designer.md`](docs/roles/graphic_designer.md)

## Tech

- **Engine:** Godot 4.7.2. The cloud environment's setup script installs it as `godot` on `PATH`. Run headless with `godot --headless`.
- **Language:** typed GDScript everywhere, with type hints on every variable, parameter and return.
- **Networking:** listen server, host-authoritative. ENet locally now, GodotSteam later. Create the peer in exactly one function.
- **Sub frame:** the interior is a still scene. The hull and world move outside. Sync player positions in sub-local space.

## Conventions

- Small, single-purpose scenes; signals over hard references between systems.
- Autoloads only for true globals: networking, noise and audio routing.
- No HUD unless the design calls for an in-world screen.
- Content (creatures, equipment, objectives, sites) is Godot Resources so it can be tuned without code.
- Sum noise as intensity (pressure squared), never as decibels.
