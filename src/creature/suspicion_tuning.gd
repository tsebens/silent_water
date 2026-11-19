class_name SuspicionTuning
extends Resource
## Every number that shapes how the apex monster hears and escalates.
## Expect heavy iteration; keep tuning here, not in code.

@export_group("Hearing")
## Apex hearing advantage added to the sub's noise as heard at the monster
## (dB). It's a sound hunter; without this it would hear almost nothing.
@export var hearing_gain_db: float = 30.0
## SNR above the background (dB) that counts as a conclusive signal.
@export var conclusive_snr_db: float = 6.0
## Suspicion gained per second per dB of SNR above zero.
@export var gain_per_db: float = 0.8
## Error of the last-heard position: radius (m) at 0 dB SNR, shrinking with SNR.
@export var position_error_at_0db: float = 80.0
@export var position_error_per_db: float = 6.0
@export var position_error_min: float = 5.0

@export_group("Ladder")
@export var curious_at: float = 15.0
@export var hunting_at: float = 40.0
@export var committed_at: float = 75.0
## Drop this far below a threshold before stepping back down.
@export var hysteresis: float = 5.0
## Only charges when the last-heard position is this close (m).
@export var commit_range: float = 150.0
## A charge is abandoned when suspicion falls below this.
@export var abandon_charge_below: float = 60.0
@export var max_suspicion: float = 100.0

@export_group("Decay")
## Seconds after the last conclusive signal before suspicion starts to fall.
@export var grace_sec: float = 2.0
## Decay while aroused (Hunting and above): from full, arousal ends ~30 s
## after the last conclusive signal (grace + 65 points at this rate).
@export var aroused_decay_per_sec: float = 2.3
## Decay below arousal (Curious → Unaware): slower.
@export var calm_decay_per_sec: float = 0.6
## How long heightened patrol lingers after arousal (s).
@export var patrol_linger_sec: float = 90.0
