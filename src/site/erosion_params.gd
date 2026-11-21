class_name ErosionParams
extends Resource
## Tunables for the grid erosion passes in [TerrainErosion]. With [member enabled]
## off, [CanyonSite.height_at] stays purely analytic.

@export var enabled: bool = false
## Grid spacing (m) the analytic generator is sampled at; smaller is finer and slower.
@export var cell_size: float = 2.0
## Extra seed mixed with the spec's seed; same spec + seed gives the same grid.
@export var seed: int = 0
## Cells with a constraint mask above this are never changed by any pass.
@export_range(0.0, 1.0) var protect_threshold: float = 0.05
@export_group("Droplets")
@export var droplet_enabled: bool = true
## Droplets simulated per bake, each starting at a random unprotected cell.
@export var droplet_count: int = 3000
## Maximum steps a droplet takes before it evaporates and drops its sediment.
@export var droplet_lifetime: int = 30
## Sediment capacity per unit of slope * speed * water.
@export var droplet_capacity: float = 4.0
@export_range(0.0, 1.0) var droplet_erode_rate: float = 0.3
@export_range(0.0, 1.0) var droplet_deposit_rate: float = 0.3
## Fraction of its water a droplet loses per step.
@export_range(0.0, 1.0) var droplet_evaporation: float = 0.05
@export_group("Thermal")
@export var thermal_enabled: bool = true
## Steepest stable slope (degrees); steeper material slumps downhill.
@export_range(1.0, 89.0) var talus_angle: float = 40.0
@export var thermal_iterations: int = 20
## Fraction of the excess height moved per neighbour per iteration (stable up to 0.25).
@export_range(0.0, 0.25) var thermal_rate: float = 0.1
@export_group("Deposition")
@export var deposition_enabled: bool = true
## Slope (degrees) at and above which a cell is left alone; flatter cells settle.
@export_range(1.0, 89.0) var settle_slope: float = 20.0
@export_range(0.0, 1.0) var settle_strength: float = 0.5
@export var deposition_iterations: int = 4
