# The apex and passive sonar

## The apex (`src/creature/`)

A huge, blind hunter (`ApexMonster`, ~30 m) that lives under the world root. The host runs its brain and steering; clients get its pose and state through a `MultiplayerSynchronizer` and smooth toward them.

### Hearing

Each physics tick the host computes the sub's noise as heard at the monster (`Acoustics.heard_at`: spreading loss and terrain occlusion) and compares it with the background at the monster (`Acoustics.ambient_at`). The difference, plus the monster's `hearing_gain_db` (+30 dB, it's a sound hunter), is the SNR:

| What the crew does | Distance where it's a conclusive signal (≥ 6 dB SNR, open water) |
| --- | --- |
| Whisper (~58 dB) | ~25 m |
| Walking or normal speech (~75 dB) | ~300 m |
| Engine full ahead (80 dB) | ~650 m |
| Blowing ballast (90 dB) | ~3 km |

A rock in the way costs 15 dB.

### Ladder and decay (`SuspicionModel`, tuning in `SuspicionTuning`)

| State | Suspicion | Behaviour |
| --- | --- | --- |
| Unaware | < 15 | Slow wandering; a distant moan every 40–80 s |
| Patrol | < 15, after arousal | Faster roaming near where it last heard something; moans every 25–45 s |
| Curious | 15–40 | Drifts toward the noise and stops short; grunts every 9–15 s |
| Hunting | 40–75 | Circles the last-heard area; pulse trains every 5–8 s |
| Committed | ≥ 75 and within 150 m | Roars and charges the **last-heard position** at 13 m/s |
| Contact | jaws within 9 m of the sub | Sub lost |

- Suspicion rises at 0.8 per second per dB of SNR. The last-heard position gets more accurate as the signal gets louder.
- **Tiered decay:** after the last conclusive signal there's a 2 s grace period. Then aroused states (Hunting, Committed) fall back about **29 s** after the last signal. **Patrol** lingers about **90 s** after that. A charge is abandoned once suspicion drops below 60.
- A committed charge goes where it *heard* the sub. A crew that goes silent and moves can make it miss. A near miss (body within 28 m at speed) jolts the crew and has a 60% chance of springing a leak.

### Felt before heard (`ThreatCues`)

- **Within 220 m:** a sub-bass rumble on the Felt bus, rising with proximity and speed.
- **Within 70 m:** the view shakes, lights flicker, and the hull creaks.
- **Through the hull:** calls and swimming are audible to everyone, heavily muffled (−35 dB, low-passed).

## Passive sonar (`src/sonar/`)

Minimal, and expected to change a lot.

- **Headset** (`Wearable`): click to put on, click to take off. Walking more than 2.2 m away pulls it off. One operator at a time, and only the operator hears the hydrophone. Their headphones duck the room by 14 dB.
- **Hydrophone trackball** (`Trackball`, a `HydrophoneWheel`; the sonar desk is the generated `sonar_console` station, placed at the program's sonar desk by `StationPlacement`: just aft of the dome on the starboard wall, its seat on the aisle side, the operator facing the hull and not the dome): rolling it sideways swings the bearing 0.25° per pixel (a handwheel turn is 120°). Bearings are relative to the bow, clockwise. The **bearing dial** shows where it's trained.
- **Beam** (`SonarStation.beam_gain_db`): ((1 + cos Δ)/2)^8. On bearing is 0 dB, 30° off is about −2.4 dB, 60° off about −10 dB, and abeam about −24 dB.
- **What's on the hydrophone** (`OutsideAudio`): the apex's swimming (louder with speed) and calls, ambient vents, the ocean background, and the sub's own noise. The sub's own noise masks distant contacts, so a noisy sub is also a deaf one.
- **Signal strength gauge** (`SIGNAL`, readout `signal`): the received level on the current hydrophone bearing, in dB. The host sums every outside source as intensity after `OutsideAudio.level_at_sub` plus `SonarStation.beam_gain_db` (the same model as the directional audio), so it rises with louder, nearer and on-beam sources. It is signal strength, not range. Range is `signal_min_db`..`signal_max_db` on `SonarStation`.
- **Bearing rate gauge** (`BRG RATE`, readout `bearing_rate`): deg/min of the contact received most strongly on the current bearing. Zero is at the top; **right is clockwise** (bearing increasing, contact drawing to starboard) and left is counter-clockwise. The needle rests at 0 while that contact's received level is below `rate_threshold_db`. Full scale is `rate_range_deg_min`. The rate is measured on the **bow-relative** bearing (what the operator reads off the wheel), so turning the sub shifts it too. Contact selection uses only received level through the beam; no range is computed or shown. The maths is in `SonarReadouts`; the host computes both values and replicates them at `readout_hz`.
- **Bearing display** (`ScreenMount/Chart` on the console, a `FlatChart`): a flat, non-interactive, heading-up 2D chart drawn by a `SubViewport` and shown as the texture of a quad in the console's bezel, facing the seat. The sub is at the centre facing up (starboard right); it draws range rings, the shared chart's pins, the objective and the fading marks in the holographic colour style, with no terrain. While someone is on sonar it shows a yellow cone on the hydrophone bearing; its width is `HoloMap.SONAR_CONE_HALF_ANGLE_DEG`, the same constant as the pilot map. The BEARING, SIGNAL, BRG RATE dials and the NOISE repeater sit on the bezel's lower border (`Gauges`).
- **Marks** (`M`, `SonarSeat.mark_contact`): still add a `CONTACT` chart pin, and also a transient mark in `MapModel.marks`, host-owned and replicated like pins (`_rpc_add_mark` → host → `_rpc_set_marks`; ages travel, not timestamps). Intensity is `MapModel.mark_intensity(age, fade)`: 1 when new, 0 at `mark_fade_s` (default 60 s), then pruned. The display draws each as a fading blob (`HoloMap.show_marks`, `mark_blob_size`), so repeated marks leave a trail brightest at the newest.
- Full scale on the hydrophone is 95 dB at the sub. Everything is a constant in `OutsideAudio` or `SonarStation`.

## Losing the sub (`DiveDirector`)

On contact: a roar and crunch, then the lights die. After 6 s the host resets the sub, leaks, monster, noise and crew positions, and the dive starts over. M5 adds objectives and surfacing.
