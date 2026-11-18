# Silent Water

First-person co-op submarine stealth game. See [the design doc](Silent%20Water%20—%20Design%20Doc.md) for the game, and the [project board](https://github.com/users/tsebens/projects/1) for current work.

## Development

Requires **Godot 4.7.2** (standard build, not .NET). Scripts are typed GDScript.

Run a local crew of N players (1 host + N−1 clients, windows tiled):

```bash
tools/launch.sh 4
```

Run the headless checks (import, unit tests, two-process network smoke test):

```bash
tools/check.sh
```

Set `GODOT=/path/to/godot` if the binary isn't on `PATH` as `godot`.

Launch arguments go after `--`: `--host`, `--join [address]`, `--port <n>`, `--name <s>`. With no arguments the game opens a dev connect menu.

### Layout

| Path | Contents |
| --- | --- |
| `src/` | Game code and scenes, one folder per system |
| `tests/unit/` | Unit tests (`test_*.gd`, extend `TestCase`) |
| `tests/` | Test runner and network smoke test |
| `tools/` | Launch and check scripts |
| `docs/` | Architecture notes |
