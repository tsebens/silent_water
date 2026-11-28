class_name FloodTuning
extends Resource
## Every number that shapes recovering a flooded facility: how fast the bilge pumps work and what the
## replacement air costs. Tune here, not in code.

## Water level removed per second by a running pump (a flooded zone is level 1.0).
@export var pump_rate: float = 0.02
## Units of gas pushed in from the station's stores for each 1.0 of water level pumped out.
@export var gas_per_level: float = 40.0
## Gas the station's store holds when full.
@export var gas_store_capacity: float = 400.0
## Scale of the pump-start noise and of the stall noise relative to their sound types.
@export var start_noise_scale: float = 1.0
@export var stall_noise_scale: float = 0.8
