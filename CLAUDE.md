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

## Roles

Agents with a specific role follow their role doc in addition to this file:

- **Graphic designer and 3D asset modeler:** [`docs/roles/graphic_designer.md`](docs/roles/graphic_designer.md)

## Tech

- **Engine:** Godot 4.7.2. The cloud environment's setup script installs it as `godot` on `PATH`. Run headless with `godot --headless`.
- **Language:** typed GDScript everywhere, with type hints on every variable, parameter and return. The one exception is tooling under `tools/` (the asset pipeline backend in `tools/asset_pipeline/`, run with `uv`), which may be Python; game code and the Godot editor plugin stay GDScript (#220).
- **Asset pipeline:** `uv run asset <command>` in `tools/asset_pipeline/` (tests: `uv run pytest`). Keys live in the git-ignored `tools/asset_pipeline/.env` (template: `.example.env` beside it); scratch meshes and rejected variants in the git-ignored `.asset_work/`.
- **Blender (asset cleanup):** 4.5 LTS, native or in Docker (`ASSET_BLENDER_RUNNER=native|docker|auto`; `uv run asset blender-image build` makes the image). Version pin in `tools/asset_pipeline/versions.yaml`.
- **Networking:** listen server, host-authoritative. ENet locally now, GodotSteam later. Create the peer in exactly one function.
- **Sub frame:** the interior is a still scene. The hull and world move outside. Sync player positions in sub-local space.

## Conventions

- Small, single-purpose scenes; signals over hard references between systems.
- Autoloads only for true globals: networking, noise and audio routing.
- No HUD unless the design calls for an in-world screen.
- Content (creatures, equipment, objectives, sites) is Godot Resources so it can be tuned without code.
- Sum noise as intensity (pressure squared), never as decibels.
