# Breakdown (concept #424)

The life_support wall unit is a generated station built in two assembly arcs on top of three leaf scenes and one
behaviour arc.

| Arc | Title |
| --- | --- |
| #438 | M12.25 · Scrubber canister behaviours (`ScrubberCanister`, `CanisterSlot`, `CanisterRing`) |
| #439 | M12.26 · `linear_gauge` kit scene (`LinearGauge`) |
| #440 | M12.27 · `scrubber_canister` scene |
| #441 | M12.28 · life_support station: shell, plinth and cradles |
| #442 | M12.29 · life_support station: upper panel and checks (look gate) |

| Function | Part | Decision |
| --- | --- | --- |
| scrubber_cradle_a/b | open cradle in the alcove, `CanisterSlot` + `scrubber_canister` | station-local cradle solids, catalogue canister |
| saturation_gauge_a/b | `linear_gauge` on the housing beside each pocket | reuse (new kit scene, #439) |
| canister_storage | six holes in the upper panel, `CanisterSlot` + `scrubber_canister` each, tops showing | station-local bores, catalogue canister |
| o2_gauge | `gauge` | reuse |
| co2_rate_gauge | `gauge` with `readout_b` | reuse |
| scrubber_fans | `guarded_toggle` + `indicator_lamp` | reuse |
| noise_repeater | `noise_gauge` | reuse |

Placement in the sub and the life support system itself are out of scope.

Look review round 1 reshaped the unit (carriages at standing eye level, arcade-cabinet profile, dials on a sloped upper
panel, 24-sided storage bores, a 24,000 triangle budget for this asset, fan toggle on by default); the arrangement is
recorded in `brief.yaml`.

Look review round 3: the saturation bars stand on the carriage face beside each pocket (not inside it); the pockets are
about 20% larger than the canister each way, with chamfered corners; the dials stand off the plate by their own
10 mm back depth; each alarm lamp is directly under its gauge; the fan toggle and its run lamp are in the upper-right
corner of the storage shelf.
