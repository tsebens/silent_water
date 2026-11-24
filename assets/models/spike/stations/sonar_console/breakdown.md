# Sonar console: breakdown

Level 1 of the loop, written before any building: what the brief asks for, what the catalogue already has, and what
has to be made. This is the one-screen artefact the human approves. Brief: [`brief.yaml`](brief.yaml).

**Final goal:** the sonar console. **This level's goal:** the same (the top of the loop).

## Functions → parts

| Function (brief) | Part | Catalogue match | Decision |
| --- | --- | --- | --- |
| Hydrophone bearing | trackball | `hydrophone_wheel` does the function but is the handwheel the concept replaces | **New scene** `trackball` (2x2 base). **New behaviour** `Trackball`, a development arc |
| Active sonar | guarded toggle with lamp | `ai_toggle_switch` fits; it predates the shared base | **Variant** → `guarded_toggle`, rebuilt on the 1x2 base. Behaviour `SwitchLever` exists |
| Chart zoom and rotate | four map keys | nothing | **New scene** `map_keypad`, which recurses: needs `push_button` (**new scene**) and **new behaviour** `PushButton`, a development arc |
| Bearing chart | screen, about 55 cm wide | `flat_chart` (square only) | **Reuse**, at 36 cm square in a 58 cm opening. The aspect gap is discovered work for the chart, not for this asset |
| Sonar dials | BEARING, SIGNAL, BRG RATE, NOISE | `gauge`, `noise_gauge` | **Reuse**, radii set per instance |
| Headset | headset on a hook | `headset` | **Reuse**; the hook is a local solid |
| Operator seat | seat facing the console | nothing (the game's is two primitive boxes) | **New scene** `operator_seat`, furniture; `SonarSeat` binds on the station |
| Control mounting | standard plates | nothing | **New solid set** `control_base` (1x1, 1x2, 2x2), shared by every control |

## Local solids (not scenes)

Console body (side-profile extrusion with knee space), bezel and screen glass, dark strip inset, orange front-edge
frames, kick plate, headset hook. They don't move, aren't reused and aren't tunable content.

## Recursion order

`control_base` → `push_button` → `guarded_toggle`, `trackball` → `map_keypad` → `operator_seat` → `sonar_console`.
Each is one build script in `tools/cad_spike/components/` and passes its own geometric checks before it writes anything.

## Development arcs this breakdown files

- `Trackball` behaviour (drag sideways trains the bearing; extends `HydrophoneWheel` so `SonarStation.wheel` takes it).
- `PushButton` behaviour (momentary).
- In the spike both were written in the same session, in their own commit, to stand in for those arcs.

## Decisions surfaced for the human

- The concept's trackball replaces the game's handwheel for training the hydrophone. The concept doc lists "trackball
  or joystick" as open. The spike takes the trackball; confirm or overrule.
