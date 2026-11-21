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
## seeded from the site seed; only the droplet pass draws from it. When
## [param timings] is given, it receives each pass that ran as name -> ms.
static func erode(heights: PackedFloat32Array, nx: int, nz: int, cell: float, mask: PackedFloat32Array, params: ErosionParams, rng: RandomNumberGenerator, timings: Dictionary = {}) -> PackedFloat32Array:
	var h: PackedFloat32Array = heights.duplicate()
	var t0: int = Time.get_ticks_usec()
	if params.droplet_enabled:
		h = droplet_pass(h, nx, nz, cell, mask, params.protect_threshold, rng, params.droplet_count, params.droplet_lifetime, params.droplet_capacity, params.droplet_erode_rate, params.droplet_deposit_rate, params.droplet_evaporation)
		t0 = _lap(timings, "droplet", t0)
	if params.thermal_enabled:
		h = thermal_pass(h, nx, nz, cell, mask, params.protect_threshold, params.talus_angle, params.thermal_iterations, params.thermal_rate)
		t0 = _lap(timings, "thermal", t0)
	if params.deposition_enabled:
		h = deposition_pass(h, nx, nz, cell, mask, params.protect_threshold, params.settle_slope, params.settle_strength, params.deposition_iterations)
		_lap(timings, "deposition", t0)
	return h


static func _lap(timings: Dictionary, pass_name: String, since_usec: int) -> int:
	var now: int = Time.get_ticks_usec()
	timings[pass_name] = (now - since_usec) / 1000.0
	return now


static func make_rng(spec_seed: int, params: ErosionParams) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([spec_seed, params.seed])
	return rng


static func _is_protected(mask: PackedFloat32Array, k: int, protect: float) -> bool:
	return mask.size() > k and mask[k] > protect


## Hydraulic droplet erosion. Each droplet starts on a random unprotected cell
## and steps to its steepest lower unprotected 8-neighbour (so flow bends around
## protected cells). It carries sediment: it picks up material in proportion to
## its speed, water and the local slope, deposits when over capacity, and
## evaporates a little each step. A droplet that finds no way down, or reaches the
## end of its lifetime, drops all remaining sediment where it stands, so total
## height is conserved. Protected cells are never visited, hence never changed.
static func droplet_pass(heights: PackedFloat32Array, nx: int, nz: int, cell: float, mask: PackedFloat32Array, protect: float, rng: RandomNumberGenerator, count: int, lifetime: int, capacity_k: float, erode_rate: float, deposit_rate: float, evaporation: float) -> PackedFloat32Array:
	var h: PackedFloat32Array = heights.duplicate()
	if nx < 2 or nz < 2:
		return h
	for _d: int in range(count):
		var i: int = rng.randi_range(0, nx - 1)
		var j: int = rng.randi_range(0, nz - 1)
		if _is_protected(mask, j * nx + i, protect):
			continue
		var water: float = 1.0
		var speed: float = 1.0
		var sediment: float = 0.0
		for _s: int in range(lifetime):
			var k: int = j * nx + i
			var best: int = -1
			var best_slope: float = 0.0
			var bi: int = i
			var bj: int = j
			for dj: int in range(-1, 2):
				for di: int in range(-1, 2):
					if di == 0 and dj == 0:
						continue
					var ni: int = i + di
					var nj: int = j + dj
					if ni < 0 or nj < 0 or ni >= nx or nj >= nz:
						continue
					var n: int = nj * nx + ni
					if _is_protected(mask, n, protect):
						continue
					var slope: float = (h[k] - h[n]) / (cell * (1.414214 if di != 0 and dj != 0 else 1.0))
					if slope > best_slope:
						best_slope = slope
						best = n
						bi = ni
						bj = nj
			if best < 0:
				break
			var capacity: float = best_slope * speed * water * capacity_k
			if sediment > capacity:
				var dep: float = (sediment - capacity) * deposit_rate
				h[k] += dep
				sediment -= dep
			else:
				# Never dig below the downhill neighbour, so pits are not carved.
				var take: float = minf((capacity - sediment) * erode_rate, (h[k] - h[best]) * 0.5)
				h[k] -= take
				sediment += take
			speed = sqrt(maxf(speed * speed + best_slope * cell, 0.0))
			water *= 1.0 - evaporation
			i = bi
			j = bj
		h[j * nx + i] += sediment
	return h


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
