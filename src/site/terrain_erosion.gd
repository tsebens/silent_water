class_name TerrainErosion
extends RefCounted
## Pure grid erosion passes over a row-major height grid (index j * nx + i).
## Every pass takes a protection mask and returns a new array; cells whose mask
## exceeds [param protect] are never changed. Nothing here reads a scene.


## Sample [param height_fn] (Callable(x, z) -> float) onto a grid.
static func sample_grid(height_fn: Callable, origin: Vector2, cell: float, nx: int, nz: int) -> PackedFloat32Array:
	var h: PackedFloat32Array = PackedFloat32Array()
	h.resize(nx * nz)
	for j: int in range(nz):
		for i: int in range(nx):
			h[j * nx + i] = height_fn.call(origin.x + i * cell, origin.y + j * cell)
	return h


## Run the enabled passes in order and return the eroded grid. [param rng] is
## seeded from the site seed; the current passes are deterministic and do not
## draw from it, but later stochastic passes will.
static func erode(heights: PackedFloat32Array, nx: int, nz: int, cell: float, mask: PackedFloat32Array, params: ErosionParams, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var h: PackedFloat32Array = heights.duplicate()
	if params.thermal_enabled:
		h = thermal_pass(h, nx, nz, cell, mask, params.protect_threshold, params.talus_angle, params.thermal_iterations, params.thermal_rate)
	if params.deposition_enabled:
		h = deposition_pass(h, nx, nz, cell, mask, params.protect_threshold, params.settle_slope, params.settle_strength, params.deposition_iterations)
	return h


static func make_rng(spec_seed: int, params: ErosionParams) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([spec_seed, params.seed])
	return rng


static func _is_protected(mask: PackedFloat32Array, k: int, protect: float) -> bool:
	return mask.size() > k and mask[k] > protect


## Thermal erosion: wherever the drop between 4-neighbours exceeds the talus
## slope, move a fraction of the excess downhill. Mass is conserved; a pair
## with a protected cell on either end does not exchange.
static func thermal_pass(heights: PackedFloat32Array, nx: int, nz: int, cell: float, mask: PackedFloat32Array, protect: float, talus_deg: float, iterations: int, rate: float) -> PackedFloat32Array:
	var h: PackedFloat32Array = heights.duplicate()
	var max_drop: float = tan(deg_to_rad(talus_deg)) * cell
	for _it: int in range(iterations):
		var delta: PackedFloat32Array = PackedFloat32Array()
		delta.resize(h.size())
		for j: int in range(nz):
			for i: int in range(nx):
				var k: int = j * nx + i
				if _is_protected(mask, k, protect):
					continue
				# Visit each pair once: east and south neighbours.
				for n: int in [k + 1 if i + 1 < nx else -1, k + nx if j + 1 < nz else -1]:
					if n < 0 or _is_protected(mask, n, protect):
						continue
					var d: float = h[k] - h[n]
					var excess: float = absf(d) - max_drop
					if excess <= 0.0:
						continue
					var moved: float = excess * rate * signf(d)
					delta[k] -= moved
					delta[n] += moved
		for k: int in range(h.size()):
			h[k] += delta[k]
	return h


## Deposition settle: sediment fills hollows and shaves bumps on flat ground by
## relaxing each cell toward its neighbours' mean, weighted by how flat it is.
## Cells at or above [param settle_slope_deg] get weight 0 and do not change.
static func deposition_pass(heights: PackedFloat32Array, nx: int, nz: int, cell: float, mask: PackedFloat32Array, protect: float, settle_slope_deg: float, strength: float, iterations: int) -> PackedFloat32Array:
	var h: PackedFloat32Array = heights.duplicate()
	var max_slope: float = tan(deg_to_rad(settle_slope_deg))
	for _it: int in range(iterations):
		var next: PackedFloat32Array = h.duplicate()
		for j: int in range(nz):
			for i: int in range(nx):
				var k: int = j * nx + i
				if _is_protected(mask, k, protect):
					continue
				var l: float = h[j * nx + maxi(i - 1, 0)]
				var r: float = h[j * nx + mini(i + 1, nx - 1)]
				var d: float = h[maxi(j - 1, 0) * nx + i]
				var u: float = h[mini(j + 1, nz - 1) * nx + i]
				var slope: float = Vector2(r - l, u - d).length() / (2.0 * cell)
				var w: float = clampf(1.0 - slope / max_slope, 0.0, 1.0) * strength
				if w > 0.0:
					next[k] = lerpf(h[k], (l + r + d + u) * 0.25, w)
		h = next
	return h


## Bilinear height at world (x, z) on a grid; clamped to the grid's edge.
static func sample_bilinear(heights: PackedFloat32Array, nx: int, nz: int, origin: Vector2, cell: float, x: float, z: float) -> float:
	var fx: float = clampf((x - origin.x) / cell, 0.0, float(nx - 1))
	var fz: float = clampf((z - origin.y) / cell, 0.0, float(nz - 1))
	var i: int = mini(int(fx), nx - 2)
	var j: int = mini(int(fz), nz - 2)
	var tx: float = fx - i
	var tz: float = fz - j
	var a: float = lerpf(heights[j * nx + i], heights[j * nx + i + 1], tx)
	var b: float = lerpf(heights[(j + 1) * nx + i], heights[(j + 1) * nx + i + 1], tx)
	return lerpf(a, b, tz)
