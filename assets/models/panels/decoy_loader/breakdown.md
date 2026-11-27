# Breakdown (concept #746, arc #754)

| Function / structure | Part | Decision |
| --- | --- | --- |
| load: drawer, window, cradle, pull handle | `loader_drawer` | reuse |
| prime: lever above the drawer | `prime_lever` | reuse |
| state: EMPTY / LOADED / PRIMED lamps | `led_strip_warn`, `led_strip`, `led_strip_alarm` + `TubeLamps` | reuse |
| state machine | `LaunchTube` | reuse; `Tube` node carries `tube_name` |
| armoured box, lamp inset, tube plate, bolts, valve body, hand wheel, compressed-air hose | | local solids |
