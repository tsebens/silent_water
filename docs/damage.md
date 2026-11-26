# Damage notes

## Leak and pump rates (M9.16)

`LeakSystem` exports both rates; tune them in the scene.

| Export | Default | Meaning |
|---|---|---|
| `leak_flow` | 0.04 t/s | inflow through the one open leak |
| `pump_flow` | 0.06 t/s | outflow with the bilge pump on |

The pump sits strictly between 1× and 2× the leak: `leak_flow < pump_flow < 2 × leak_flow`. One working pump beats one leak but would not beat two. Only one leak can be open at a time in the prototype (`open_index`); the two-leak case is verified arithmetically in tests (inflow of `2 × leak_flow`).

## Threshold

`SubPhysicsModel.max_surfaceable_bilge_t()` = `displacement_t − dry_mass_t − payload_t` = 150 − 139.64 − 0.36 = **10.0 t**. With the ballast tank fully blown, a hull holding more bilge water than this cannot rise above the waterline.

## Time to flood

One unattended leak, no pump: 10.0 t ÷ 0.04 t/s = **250 s** (inside the 3–5 minute design window). Leak inflow is not depth-scaled; #132 scales only the spontaneous opening rate.

## Hand pump (M12.70)

`HandPump` (`src/interact/hand_pump.gd`) is a lever that works the bilge by hand and needs no power. Holding it is the 0.6 s down stroke, releasing springs it back in 0.4 s, and a 0.5 s refill beat follows (1.5 s per cycle). A full stroke bails 0.0525 t through `LeakSystem.manual_bail`, so steady work removes about 0.035 t/s. It makes no noise, and the electric pump's path is unchanged. The host runs the cycle and streams the lever value.
