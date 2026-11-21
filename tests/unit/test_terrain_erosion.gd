extends TestCase
## TerrainErosion: thermal and deposition passes, constraint protection,
## determinism, bilinear sampling, and the analytic path when erosion is off.

const N: int = 17
const CELL: float = 2.0


func _empty_mask() -> PackedFloat32Array:
	return PackedFloat32Array()


func _spike() -> PackedFloat32Array:
	var h: PackedFloat32Array = PackedFloat32Array()
	h.resize(N * N)
	h[(N / 2) * N + N / 2] = 40.0
	return h


func _noisy(amp: float) -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var h: PackedFloat32Array = PackedFloat32Array()
	h.resize(N * N)
	for k: int in range(h.size()):
		h[k] = rng.randf_range(-amp, amp)
	return h


func _max_slope(h: PackedFloat32Array) -> float:
	var worst: float = 0.0
	for j: int in range(N):
		for i: int in range(N):
			if i + 1 < N:
				worst = maxf(worst, absf(h[j * N + i] - h[j * N + i + 1]) / CELL)
			if j + 1 < N:
				worst = maxf(worst, absf(h[j * N + i] - h[(j + 1) * N + i]) / CELL)
	return worst


func _variance(h: PackedFloat32Array) -> float:
	var mean: float = 0.0
	for v: float in h:
		mean += v
	mean /= h.size()
	var s: float = 0.0
	for v: float in h:
		s += (v - mean) * (v - mean)
	return s / h.size()


func test_thermal_reduces_slope_to_talus() -> void:
	var talus: float = 35.0
	var out: PackedFloat32Array = TerrainErosion.thermal_pass(_spike(), N, N, CELL, _empty_mask(), 0.05, talus, 400, 0.2)
	expect(_max_slope(out) <= tan(deg_to_rad(talus)) + 0.02, "max slope %f above talus" % _max_slope(out))
	var before: float = 0.0
	var after: float = 0.0
	for v: float in _spike():
		before += v
	for v: float in out:
		after += v
	expect_near(after, before, 0.01, "mass conserved")


func test_deposition_flattens_flats_and_spares_steep() -> void:
	# Flat noisy half, steep ramp half.
	var h: PackedFloat32Array = _noisy(0.3)
	for j: int in range(N):
		for i: int in range(N / 2, N):
			h[j * N + i] = (i - N / 2) * CELL * 3.0 + h[j * N + i] * 0.0
	var out: PackedFloat32Array = TerrainErosion.deposition_pass(h, N, N, CELL, _empty_mask(), 0.05, 20.0, 0.8, 4)
	var flat_before: PackedFloat32Array = PackedFloat32Array()
	var flat_after: PackedFloat32Array = PackedFloat32Array()
	for j: int in range(2, N - 2):
		for i: int in range(2, N / 2 - 2):
			flat_before.append(h[j * N + i])
			flat_after.append(out[j * N + i])
	expect(_variance(flat_after) < _variance(flat_before) * 0.5, "flat variance drops")
	for j: int in range(1, N - 1):
		for i: int in range(N / 2 + 2, N - 1):
			expect_eq(out[j * N + i], h[j * N + i], "steep cell unchanged")


func test_protected_cells_unchanged() -> void:
	var h: PackedFloat32Array = _noisy(6.0)
	var mask: PackedFloat32Array = PackedFloat32Array()
	mask.resize(N * N)
	for j: int in range(4, 10):
		for i: int in range(4, 10):
			mask[j * N + i] = 1.0
	var thermal: PackedFloat32Array = TerrainErosion.thermal_pass(h, N, N, CELL, mask, 0.05, 20.0, 30, 0.2)
	var dep: PackedFloat32Array = TerrainErosion.deposition_pass(h, N, N, CELL, mask, 0.05, 60.0, 0.8, 4)
	var changed: bool = false
	for k: int in range(h.size()):
		if mask[k] > 0.05:
			expect_eq(thermal[k], h[k], "thermal protected")
			expect_eq(dep[k], h[k], "deposition protected")
		elif thermal[k] != h[k]:
			changed = true
	expect(changed, "unprotected cells did change")


func test_same_seed_same_grid() -> void:
	var a: CanyonSite = _eroded_site()
	var b: CanyonSite = _eroded_site()
	expect(a.eroded_grid().size() > 0, "grid baked")
	expect(a.eroded_grid() == b.eroded_grid(), "identical grids")
	var r1: RandomNumberGenerator = TerrainErosion.make_rng(4417, a.erosion)
	var r2: RandomNumberGenerator = TerrainErosion.make_rng(4417, a.erosion)
	expect_eq(r1.randi(), r2.randi())


func _sum(h: PackedFloat32Array) -> float:
	var t: float = 0.0
	for v: float in h:
		t += v
	return t


func _droplets(h: PackedFloat32Array, mask: PackedFloat32Array, seed_value: int, count: int) -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return TerrainErosion.droplet_pass(h, N, N, CELL, mask, 0.05, rng, count, 30, 4.0, 0.3, 0.3, 0.05)


func _plane() -> PackedFloat32Array:
	var h: PackedFloat32Array = PackedFloat32Array()
	h.resize(N * N)
	for j: int in range(N):
		for i: int in range(N):
			h[j * N + i] = 40.0 - i * CELL * 0.8
	return h


func test_droplet_moves_downhill() -> void:
	var h: PackedFloat32Array = _plane()
	var out: PackedFloat32Array = _droplets(h, _empty_mask(), 3, 1)
	# One droplet lifts material from upslope and leaves it further downslope:
	# the centre of mass in x moves toward +x (downhill).
	var before: float = 0.0
	var after: float = 0.0
	for k: int in range(h.size()):
		before += (out[k] - h[k]) * (k % N)
		after += out[k] - h[k]
	expect_near(after, 0.0, 0.001, "net zero")
	expect(before > 0.0, "sediment ends downhill of where it was picked up")
	var changed: int = 0
	for k: int in range(h.size()):
		if out[k] != h[k]:
			changed += 1
	expect(changed > 1, "droplet altered the terrain")


func test_droplet_conserves_material() -> void:
	var h: PackedFloat32Array = _noisy(6.0)
	var out: PackedFloat32Array = _droplets(h, _empty_mask(), 11, 400)
	expect_near(_sum(out), _sum(h), 0.05, "total height conserved")
	expect(out != h, "terrain changed")


func test_droplet_protected_unchanged() -> void:
	var h: PackedFloat32Array = _noisy(6.0)
	var mask: PackedFloat32Array = PackedFloat32Array()
	mask.resize(N * N)
	for j: int in range(4, 10):
		for i: int in range(4, 10):
			mask[j * N + i] = 1.0
	var out: PackedFloat32Array = _droplets(h, mask, 5, 600)
	for k: int in range(h.size()):
		if mask[k] > 0.05:
			expect_eq(out[k], h[k], "protected cell untouched")
	expect_near(_sum(out), _sum(h), 0.05, "still conserved")


func test_droplet_deterministic() -> void:
	var h: PackedFloat32Array = _noisy(6.0)
	expect(_droplets(h, _empty_mask(), 9, 200) == _droplets(h, _empty_mask(), 9, 200), "same seed same grid")
	expect(_droplets(h, _empty_mask(), 9, 200) != _droplets(h, _empty_mask(), 10, 200), "different seed differs")


func test_bilinear_matches_nodes() -> void:
	var site: CanyonSite = _eroded_site()
	var g: PackedFloat32Array = site.eroded_grid()
	var cell: float = site.erosion.cell_size
	var nx: int = int((CanyonSite.GRID_MAX.x - CanyonSite.GRID_MIN.x) / cell) + 1
	for node: Vector2i in [Vector2i(0, 0), Vector2i(10, 20), Vector2i(40, 100), Vector2i(nx - 1, 5)]:
		var x: float = CanyonSite.GRID_MIN.x + node.x * cell
		var z: float = CanyonSite.GRID_MIN.y + node.y * cell
		expect_near(site.height_at(x, z), g[node.y * nx + node.x], 0.0001)
	# Midway between two nodes is their mean.
	var mid: float = site.height_at(CanyonSite.GRID_MIN.x + cell * 10.5, CanyonSite.GRID_MIN.y + cell * 20.0)
	expect_near(mid, (g[20 * nx + 10] + g[20 * nx + 11]) * 0.5, 0.0001)


func test_disabled_is_analytic() -> void:
	var plain: CanyonSite = CanyonSite.new()
	var off: CanyonSite = CanyonSite.new()
	off.erosion = ErosionParams.new()
	off.bake_erosion()
	expect(off.eroded_grid().is_empty(), "no grid when disabled")
	for p: Vector2 in [Vector2(0, -250), Vector2(-42, -100), Vector2(37.3, -281.7), Vector2(55, -400)]:
		expect_eq(off.height_at(p.x, p.y), plain.height_at(p.x, p.y))
		expect_eq(plain.height_at(p.x, p.y), plain.analytic_height_at(p.x, p.y))


func _eroded_site() -> CanyonSite:
	var site: CanyonSite = CanyonSite.new()
	var p: ErosionParams = ErosionParams.new()
	p.enabled = true
	p.cell_size = 4.0
	p.thermal_iterations = 5
	site.erosion = p
	site.bake_erosion()
	return site
