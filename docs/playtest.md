# Playtest guide

The prototype asks one question: **is it tense and fun to coordinate a sub when talking is dangerous?**

## Setup

1. **Crew:** 3–4 players (4 is the target). One hosts.
2. **Voice:** talk over an external voice app (Discord or similar). The game measures each player's mic separately for noise. Use push-to-talk off or voice activity in the voice app, so the game hears what the crew hears. Use **headphones**, so the game's sounds don't leak into your mic.
3. **Build:** everyone needs the same commit and Godot 4.7.2 (standard, not .NET).
4. **Network:** the prototype has no Steam lobby yet. The host's port **24550/UDP** must be reachable: same LAN, a VPN such as Tailscale or ZeroTier, or a port forward.

Host:

```bash
godot --path . -- --host --name Tristan
```

Each crew member:

```bash
godot --path . -- --join <host-address> --name <your-name>
```

You can also launch with no arguments and use the dev connect menu.

To try it alone with several windows on one machine:

```bash
tools/launch.sh 4
```

## The dive

The **orders** are on the board on the aft bulkhead:

1. Scan Raindrop sensor array **S-7** on **shelf 2** (east wall, ~140 m). It has a red beacon and an acoustic **pinger** the sonar operator can find.
2. **Surface** for recovery.

You start floating at the surface with empty tanks. Flood to go down. The canyon has a close first shelf (~60 m), the array's shelf (~140 m), and the floor (~230 m), where there is a loud vent. Something big lives down there. It's blind and hunts by sound.

A dive ends when you surface after the scan (success) or when it reaches you (loss). Either way, the dive resets after a few seconds.

## Stations

| Station | Where | What you do |
| --- | --- | --- |
| **Pilot** | Bow | **Cabin lights** lever on the starboard wall dims the cabin, so you can see out. Click the seat to sit. **A/D** rudder, **W/S** dive planes (W noses down). The planes only work with water moving over them. Gauges: depth, heading, pitch. You can't work other stations while seated, so call your orders out. |
| **Engineering** | Aft, starboard | The **engine order telegraph**: drag up for ahead, down for astern. It snaps to the nearest order. The engine takes a few seconds to respond. |
| **Ballast** | Midships, port | **FLOOD** valve (quiet) makes the sub heavier. **BLOW** valve (very loud, uses limited HP air) makes it lighter. Turn the handwheels by circling the mouse. Gauges: tank, HP air. |
| **Sonar** | Midships, starboard | Click the **headset** to put it on (it comes off if you walk away). Circle the mouse on the **hydrophone wheel** to turn the listening bearing; the dial shows where you're listening. Only you hear the hydrophone, and you must say what you hear out loud. |
| **Bilge** | Aft, port | **Pump** switch: removes leak water, but it's loud. |
| **Scanner** | Forward, port | **Scanner** switch: within ~30 m of the array, nearly stopped, it fills the SCAN gauge in ~25 s. It's **loud** the whole time it's on. |

**Leaks** hiss and spray. Find them by ear, then click and hold **steady** for 2 s to patch. A shaky patch doesn't last.

**Noise gauges** (one at every station): the red needle is the sub, the blue needle is the ocean. Red under blue means you're hidden.

## Controls

| Input | Action |
| --- | --- |
| Mouse | Look. The dot at screen centre lights up over anything usable and says what it is and how to use it. |
| Click (hold) on a control | Grab it; move the mouse to work it. The view holds still while the button is down. Ease it for quiet, slam it for a clank. |
| Click | Sit or stand (pilot seat), put on or take off (sonar headset) |
| WASD | Walk, or fly the sub when seated |
| Shift | Sneak (quieter footsteps) |
| Esc | Release the mouse and let go of everything |

## What makes noise

Roughly loudest first:

- blowing ballast
- slamming controls
- hull strikes
- shouting
- the scanner
- the engine at speed
- the bilge pump
- normal talking and walking
- a leak
- flooding
- sneaking

Whispering and a still sub hide under the ocean. Vents mask you if you're close to them. They also deafen the sonar.

## The monster's tells

Every step up the ladder can be heard or felt:

| What you notice | What it means |
| --- | --- |
| Long, distant **moans** now and then | Unaware |
| **Moans more often**, moving around more | Patrolling: it heard something a while ago |
| **Grunts** | Curious: it's drifting toward a noise |
| Rhythmic **pulse trains** | Hunting: it's searching where it last heard you |
| A **roar** | Committed: it's charging where it last heard you. Go silent and move. |
| Low **rumble** you feel, then **shaking, flickering lights, creaking** | It's close |

Arousal fades about 30 seconds after you go quiet. Patrolling lasts a minute or two after that.

## Debug keys (playtests only)

| Key | What it does |
| --- | --- |
| F1 | Developer overlay: console (engine output and game events, including the host's on clients), 3D minimap (sub green, apex red, array yellow), and live sub, noise, apex and dive stats. Launch with `-- --dev-overlay` to start with it on. |
| F4 | Switch the apex off or on for everyone (the host decides). While it's off, it's gone: no body, no sound, no hearing, no contact. Start the host with `-- --no-apex` to dive without it from the start. |
| F3 | Simulate normal speech on your mic |
| Shift+F3 | Simulate a shout |

## During and after

- **Don't coach the crew** about talking quietly. Watch whether they start on their own.
- The host's game writes a **session log** (its path is printed at the start; it lives under the Godot user data folder, `logs/session_*.txt`). For each change in the monster's state, the log records how loudly it heard the sub and the **loudest things aboard at that moment**. Use it to answer "what gave us away?"

### Success criteria

1. Crews start whispering, calling out tersely and going silent without being told.
2. Players can tell where the monster is on the ladder from sound alone.
3. After a loss, the crew can say what gave them away. Check their answer against the log.

### Report

File a **Playtest feedback** issue (template in `.github/ISSUE_TEMPLATE`) and attach the session log. Put tuning numbers you'd change in the issue: most live in `SuspicionTuning`, `docs/noise.md` and `docs/apex_and_sonar.md`.
