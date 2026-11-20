# Noise system

Noise is the core system. Everything the crew does feeds one number: how loud the sub is.

## Model

- Every source reports **linear intensity** (proportional to pressure squared) at 1 m. Intensities add; decibels and pascals don't.
- Scale: intensity 1.0 = **100 dB**. Conversions live in `NoiseLevel` (`to_db`, `from_db`, `attenuate`).
- The host (`Acoustics` autoload) sums every source into `sub_intensity` each physics tick. The sub is tiny next to what's listening, so it's one number for the whole sub.
- Ocean background is `OCEAN_BASE_DB` (62 dB) plus any `AmbientZone`s near the sub. When the sub is quieter than the background, it is **masked** (`Acoustics.is_masked()`).
- Clients receive both levels at 10 Hz for the gauges.

### Sources

| Source | Where | Level at 1 m |
| --- | --- | --- |
| Still sub, nobody moving | — | silent (masked) |
| Whisper (mic RMS ≈ 0.01) | `VoiceLoudness` | ~58 dB (under the ocean) |
| Ocean background | `Acoustics.OCEAN_BASE_DB` | 62 dB |
| Sneaking (1.1 m/s) | `Player.noise_intensity` | ~64 dB |
| Flooding ballast, vent fully open | `SubController.FLOOD_INTENSITY` | 70 dB |
| Open leak hissing | `LeakSystem.LEAK_INTENSITY` | 73 dB |
| Normal speech (RMS ≈ 0.07) | `VoiceLoudness` | ~75 dB |
| Walking (2.6 m/s) | `Player.FOOTSTEP_INTENSITY` | 75 dB |
| Side thrusters, full turn | `SubController.THRUSTER_INTENSITY` | 73 dB (∝ rudder input) |
| Bilge pump running | `LeakSystem.PUMP_INTENSITY` | 78 dB |
| Engine, full ahead | `SubController.ENGINE_FULL_INTENSITY` | 80 dB (∝ output²) |
| Shout (RMS ≈ 0.3) | `VoiceLoudness` | ~87 dB |
| Blowing ballast, valve fully open | `SubController.BLOW_INTENSITY` | 90 dB |
| Hull strike at 1 m/s | `SubController.STRIKE_INTENSITY` | 95 dB, decays over 1.5 s (∝ speed²) |
| Lever or valve slammed | `NoiseProfile` on each control | up to ~97 dB; easing it is near silent |

All of these are first-pass numbers to tune in playtests.

### How sources plug in

- A node in group `noise_sources` with `noise_intensity() -> float` is polled on the host. `Interactable`s, `Player`s, `SubController` and `LeakSystem` do this.
- Short events call `Acoustics.add_impulse(intensity, duration)` on the host.
- Footsteps are computed on the host from each player's **replicated** movement, so a client can't fake being quiet.

### Voice

Decision [#8](https://github.com/tsebens/silent_water/issues/8): each player's machine measures its own mic (`MicMeter`) and sends intensity to the host 10×/s. `VoiceLoudness.intensity_from_samples` takes raw mono samples, so it can move to the host unchanged once Steam Voice is in. There's no calibration yet; see [#17](https://github.com/tsebens/silent_water/issues/17).

Debug: hold **F3** to simulate normal speech, **Shift+F3** for a shout. `--fake-voice-db <dB>` reports a constant level.

The reports travel unreliable-ordered, and the host counts a peer's voice as silence once its last report is older than `Acoustics.VOICE_TIMEOUT` (0.5 s), so a voice stops adding noise promptly when a player goes quiet or drops. The three-instance autotest therefore holds its snapshot until every peer's report is fresh (`Autotest.report_due`, bounded by a short grace), rather than reading a timed-out zero as a failure ([#86](https://github.com/tsebens/silent_water/issues/86)).

## Hearing at a distance (for creatures)

`Acoustics.heard_at(world_point, sub_frame)` gives the sub's noise at a point:

- Spreading loss with exponent `NoiseLevel.SPREADING_EXPONENT` (1.5, between cylindrical and spherical): −30 dB at 100 m, −45 dB at 1 km.
- `OCCLUSION_LOSS_DB` (15 dB) extra when terrain blocks the straight line.

Creatures compare that against the background at their own position to decide whether they heard something.

## The mix tells the truth

`SubAudio` plays each source at `to_db(intensity) − 100` dBFS, so in-sub loudness tracks the same numbers the ocean hears. Sounds are synthesized placeholders (`ProceduralSounds`) until real audio exists.

## Gauges

The two-needle noise gauge (`src/noise/noise_gauge.tscn`) reads `sub_db` (red) and `ambient_db` (blue) from `Acoustics` on a 40–120 dB scale. Repeaters sit at the pilot, engineering, ballast and bilge stations.
