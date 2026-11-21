# Asset pipeline backend

Python backend for Asset Studio (see #222, decisions in #220). Run from this directory with `uv run asset <command>`, or from the repo root with `uv run --project tools/asset_pipeline asset <command>`. Every command prints one JSON object (`{"ok": true, ...}` or `{"ok": false, "error": ...}`).

Implemented: `new <slug> --class <creature|prop|architecture|terrain> [--issue N]` and `lock <slug> <variant> [--decision approved|rejected] [--reviewer NAME] [--notes …]`. The remaining stages arrive in later arcs.

- Manifest: `assets/models/<slug>/asset.yaml` (committed): stage, lineage (prompt, provider, model, parent of every image or mesh), the locked variant and reviewer decision.
- Scratch: `.asset_work/<slug>/` (git-ignored): rejected variants and raw provider meshes.
- Providers: `providers.yaml` picks a provider per kind (`image`, `three_d`, `prompt_writer`); commands override with a flag. Only `mock` exists so far; it returns deterministic fixtures.
- Keys: environment variables, loaded from `tools/asset_pipeline/.env` (git-ignored). Never commit them.
- Tests: `uv run pytest`.
