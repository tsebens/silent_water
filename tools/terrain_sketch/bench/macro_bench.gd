extends SceneTree
## Spike: cost of the macro terrain stage in GDScript (#952). 171 x 276 cells at 10 m (about 47,000), the
## same sizes as the numpy prototype. Each part mirrors tools/terrain_sketch closely enough to time it.

const NX: int = 171
const NZ: int = 276
const CELL: float = 10.0
var n: int = NX * NZ


func _noise(seed: int, wavelength: float, octaves: int, ridged: bool = false) -> FastNoiseLite:
	var f: FastNoiseLite = FastNoiseLite.new()
	f.seed = seed
	f.noise_type = FastNoiseLite.TYPE_PERLIN
	f.frequency = 1.0 / wavelength
	f.fractal_octaves = octaves
	f.fractal_type = FastNoiseLite.FRACTAL_RIDGED if ridged else FastNoiseLite.FRACTAL_FBM
	return f


## Distance from every cell to a polyline, culled to cells within reach of each segment.
func _polyline_dist(pts: PackedVector2Array, reach: float, out: PackedFloat32Array) -> void:
	for k: int in range(n):
		out[k] = INF
	for s: int in range(pts.size() - 1):
		var a: Vector2 = pts[s]
		var b: Vector2 = pts[s + 1]
		var lo: Vector2 = Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(reach, reach)
		var hi: Vector2 = Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(reach, reach)
		var i0: int = maxi(int((lo.x + NX * CELL / 2.0) / CELL), 0)
		var i1: int = mini(int((hi.x + NX * CELL / 2.0) / CELL) + 1, NX - 1)
		var j0: int = maxi(int((lo.y + NZ * CELL / 2.0) / CELL), 0)
		var j1: int = mini(int((hi.y + NZ * CELL / 2.0) / CELL) + 1, NZ - 1)
		var ab: Vector2 = b - a
		var ll: float = ab.length_squared()
		for j: int in range(j0, j1 + 1):
			var z: float = -NZ * CELL / 2.0 + j * CELL
			for i: int in range(i0, i1 + 1):
				var p: Vector2 = Vector2(-NX * CELL / 2.0 + i * CELL, z)
				var u: float = clampf((p - a).dot(ab) / ll, 0.0, 1.0)
				var d: float = p.distance_to(a + ab * u)
				var k: int = j * NX + i
				if d < out[k]:
					out[k] = d


## D8 receivers and slopes, then accumulation in high-to-low order. The order comes from a native sort of
## int64 keys (height in millimetres, shifted, plus the cell index), which avoids a custom comparator.
func _flow_route(h: PackedFloat32Array, recv: PackedInt32Array, slope: PackedFloat32Array, acc: PackedFloat32Array) -> PackedInt64Array:
	var offs: Array[Vector3] = [Vector3(-1, -1, 1.4142), Vector3(0, -1, 1), Vector3(1, -1, 1.4142), Vector3(-1, 0, 1),
		Vector3(1, 0, 1), Vector3(-1, 1, 1.4142), Vector3(0, 1, 1), Vector3(1, 1, 1.4142)]
	var keys: PackedInt64Array = PackedInt64Array()
	keys.resize(n)
	for j: int in range(NZ):
		for i: int in range(NX):
			var k: int = j * NX + i
			var best: float = 0.0
			var r: int = k
			for o: Vector3 in offs:
				var ii: int = i + int(o.x)
				var jj: int = j + int(o.y)
				if ii < 0 or jj < 0 or ii >= NX or jj >= NZ:
					continue
				var nb: int = jj * NX + ii
				var s: float = (h[k] - h[nb]) / (CELL * o.z)
				if s > best:
					best = s
					r = nb
			recv[k] = r
			slope[k] = best
			acc[k] = 1.0
			keys[k] = (int((h[k] + 2000.0) * 1000.0) << 20) | k
	keys.sort()
	for q: int in range(n - 1, -1, -1):
		var k: int = keys[q] & 0xFFFFF
		if recv[k] != k:
			acc[recv[k]] += acc[k]
	return keys


func _sediment_pass(h: PackedFloat32Array, recv: PackedInt32Array, slope: PackedFloat32Array, acc: PackedFloat32Array, keys: PackedInt64Array) -> void:
	var qs: PackedFloat32Array = PackedFloat32Array()
	qs.resize(n)
	var dh: PackedFloat32Array = PackedFloat32Array()
	dh.resize(n)
	var steep: float = tan(deg_to_rad(22.0))
	for q: int in range(n - 1, -1, -1):
		var k: int = keys[q] & 0xFFFFF
		var rk: int = recv[k]
		var load: float = qs[k]
		if rk == k:
			dh[k] += load
			continue
		var cap: float = 0.25 * sqrt(acc[k]) * slope[k]
		if load > cap and slope[k] > steep:
			qs[rk] += load
			continue
		if load > cap:
			var dep: float = (load - cap) * 0.35
			dh[k] += dep
			load -= dep
		else:
			var e: float = minf(minf((cap - load) * 0.25, 4.0), maxf(h[k] - h[rk] - 0.05, 0.0) * 0.5)
			dh[k] -= e
			load += e
		qs[rk] += load
	for k: int in range(n):
		h[k] += dh[k]


func _thermal(h: PackedFloat32Array, talus_deg: float, passes: int) -> void:
	var t: float = tan(deg_to_rad(talus_deg))
	for _p: int in range(passes):
		var delta: PackedFloat32Array = PackedFloat32Array()
		delta.resize(n)
		for j: int in range(NZ - 1):
			for i: int in range(1, NX - 1):
				var k: int = j * NX + i
				for o: Vector3i in [Vector3i(1, 0, 10), Vector3i(0, 1, 10), Vector3i(1, 1, 14), Vector3i(-1, 1, 14)]:
					var nb: int = k + o.x + o.y * NX
					var d: float = h[k] - h[nb]
					var ex: float = absf(d) - t * CELL * o.z * 0.1
					if ex > 0.0:
						var m: float = ex * 0.06 * signf(d)
						delta[k] -= m
						delta[nb] += m
		for k: int in range(n):
			h[k] += delta[k]


## Priority-flood fill (Barnes et al.): the spill surface of every closed basin, with a binary heap.
func _priority_flood(h: PackedFloat32Array) -> PackedFloat32Array:
	var filled: PackedFloat32Array = h.duplicate()
	var done: PackedByteArray = PackedByteArray()
	done.resize(n)
	var heap_h: PackedFloat32Array = PackedFloat32Array()
	var heap_k: PackedInt32Array = PackedInt32Array()
	var push: Callable = func(hh: float, kk: int) -> void:
		heap_h.append(hh); heap_k.append(kk)
		var c: int = heap_h.size() - 1
		while c > 0:
			var p: int = (c - 1) >> 1
			if heap_h[p] <= heap_h[c]:
				break
			var th: float = heap_h[p]; heap_h[p] = heap_h[c]; heap_h[c] = th
			var tk: int = heap_k[p]; heap_k[p] = heap_k[c]; heap_k[c] = tk
			c = p
	for j: int in range(NZ):
		for i: int in range(NX):
			if i == 0 or j == 0 or i == NX - 1 or j == NZ - 1:
				var k: int = j * NX + i
				done[k] = 1
				push.call(filled[k], k)
	while heap_h.size() > 0:
		var top_h: float = heap_h[0]
		var top_k: int = heap_k[0]
		var last: int = heap_h.size() - 1
		heap_h[0] = heap_h[last]; heap_k[0] = heap_k[last]
		heap_h.resize(last); heap_k.resize(last)
		var c: int = 0
		while true:
			var l: int = 2 * c + 1
			if l >= last:
				break
			var m: int = l
			if l + 1 < last and heap_h[l + 1] < heap_h[l]:
				m = l + 1
			if heap_h[c] <= heap_h[m]:
				break
			var th: float = heap_h[m]; heap_h[m] = heap_h[c]; heap_h[c] = th
			var tk: int = heap_k[m]; heap_k[m] = heap_k[c]; heap_k[c] = tk
			c = m
		var i0: int = top_k % NX
		var j0: int = top_k / NX
		for dj: int in range(-1, 2):
			for di: int in range(-1, 2):
				var ii: int = i0 + di
				var jj: int = j0 + dj
				if ii < 0 or jj < 0 or ii >= NX or jj >= NZ:
					continue
				var nb: int = jj * NX + ii
				if done[nb]:
					continue
				done[nb] = 1
				filled[nb] = maxf(filled[nb], top_h)
				push.call(filled[nb], nb)
	return filled


## Separable running max (or min) over a square window: the gate's footprint relief test, per station size.
func _window(h: PackedFloat32Array, r: int, use_max: bool) -> PackedFloat32Array:
	var tmp: PackedFloat32Array = PackedFloat32Array()
	tmp.resize(n)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	for j: int in range(NZ):
		for i: int in range(NX):
			var v: float = -INF if use_max else INF
			for d: int in range(-r, r + 1):
				var ii: int = clampi(i + d, 0, NX - 1)
				v = maxf(v, h[j * NX + ii]) if use_max else minf(v, h[j * NX + ii])
			tmp[j * NX + i] = v
	for j: int in range(NZ):
		for i: int in range(NX):
			var v: float = -INF if use_max else INF
			for d: int in range(-r, r + 1):
				var jj: int = clampi(j + d, 0, NZ - 1)
				v = maxf(v, tmp[jj * NX + i]) if use_max else minf(v, tmp[jj * NX + i])
			out[j * NX + i] = v
	return out


func _init() -> void:
	var t: Dictionary = {}
	var h: PackedFloat32Array = PackedFloat32Array()
	h.resize(n)
	# 1. Base field: warp, base noise, step-width noise, two rim noises, swales, roughness (7 fields).
	var t0: int = Time.get_ticks_usec()
	var fields: Array[FastNoiseLite] = [_noise(1, 1500.0, 3), _noise(2, 1400.0, 4), _noise(3, 700.0, 3), _noise(4, 500.0, 3),
		_noise(5, 500.0, 3), _noise(6, 450.0, 4), _noise(8, 220.0, 3, true)]
	for j: int in range(NZ):
		for i: int in range(NX):
			var x: float = -NX * CELL / 2.0 + i * CELL
			var z: float = -NZ * CELL / 2.0 + j * CELL
			var wx: float = x + fields[0].get_noise_2d(x, z) * 300.0
			var wz: float = z + fields[0].get_noise_2d(x + 1000.0, z - 1000.0) * 300.0
			var u: float = fields[1].get_noise_2d(wx, wz) * 0.5 + 0.5
			var w: float = 0.015 + 0.09 * pow(fields[2].get_noise_2d(x, z) * 0.5 + 0.5, 1.5)
			var s0: float = 0.4 + fields[3].get_noise_2d(x, z) * 0.05
			var s1: float = 0.7 + fields[4].get_noise_2d(x, z) * 0.05
			var tt: float = 0.15 + 0.35 * smoothstep(s0 - w, s0 + w, u) + 0.3 * smoothstep(s1 - w, s1 + w, u)
			tt += fields[5].get_noise_2d(wx, wz) * (0.025 + 0.03 * tt) + (fields[6].get_noise_2d(wx, wz) - 0.35) * 0.03 * tt * tt
			h[j * NX + i] = -650.0 + tt * 590.0
	t["base field"] = Time.get_ticks_usec() - t0

	# 2. Landforms: distance to 8 curves of 48 segments each (2 scarps, 2 chasms, 4 tributaries), reach 400 m,
	# plus warp and profile noise per cell for each.
	t0 = Time.get_ticks_usec()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var dist: PackedFloat32Array = PackedFloat32Array()
	dist.resize(n)
	var wob: FastNoiseLite = _noise(11, 260.0, 3)
	for c: int in range(8):
		var pts: PackedVector2Array = PackedVector2Array()
		var p: Vector2 = Vector2(rng.randf_range(-600, 600), rng.randf_range(-1100, 1100))
		var hd: float = rng.randf() * TAU
		for s: int in range(49):
			pts.append(p)
			hd += rng.randfn(0.0, 0.05)
			p += Vector2(cos(hd), sin(hd)) * 48.0
		_polyline_dist(pts, 400.0, dist)
		for k: int in range(n):
			if dist[k] < 400.0:
				var x: float = float(k % NX) * CELL
				var z: float = float(k / NX) * CELL
				var r: float = (dist[k] + wob.get_noise_2d(x, z) * 55.0) / 150.0
				h[k] -= 200.0 * (1.0 - smoothstep(0.35, 1.0, r)) * 0.01
	t["landforms (8 curves)"] = Time.get_ticks_usec() - t0

	# 3. Erosion: 6 incision passes and 10 sediment passes, each with a full flow routing; thermal 6 passes.
	var recv: PackedInt32Array = PackedInt32Array(); recv.resize(n)
	var slope: PackedFloat32Array = PackedFloat32Array(); slope.resize(n)
	var acc: PackedFloat32Array = PackedFloat32Array(); acc.resize(n)
	t0 = Time.get_ticks_usec()
	var keys: PackedInt64Array = _flow_route(h, recv, slope, acc)
	t["one flow routing"] = Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	for _it: int in range(6):
		keys = _flow_route(h, recv, slope, acc)
		for k: int in range(n):
			if recv[k] != k:
				h[k] = maxf(h[k] - minf(0.018 * sqrt(acc[k]) * slope[k], 6.0), h[recv[k]] + 0.05)
	t["incision (6 passes)"] = Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	_thermal(h, 38.0, 4)
	t["thermal (4 passes)"] = Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	for _it: int in range(10):
		keys = _flow_route(h, recv, slope, acc)
		_sediment_pass(h, recv, slope, acc, keys)
	t["sediment routing (10 passes)"] = Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	var filled: PackedFloat32Array = _priority_flood(h)
	t["priority flood"] = Time.get_ticks_usec() - t0

	# 4. Gate: relief over a footprint for 4 distinct station sizes (max and min windows).
	t0 = Time.get_ticks_usec()
	for r: int in [1, 2, 3, 6]:
		var hi: PackedFloat32Array = _window(h, r, true)
		var lo: PackedFloat32Array = _window(h, r, false)
	t["gate windows (4 sizes)"] = Time.get_ticks_usec() - t0

	var total: float = 0.0
	print("macro stage, %d x %d cells (%d):" % [NX, NZ, n])
	for key: String in t:
		if key == "one flow routing":
			print("  %-30s %7.0f ms   (included below)" % [key, t[key] / 1000.0])
			continue
		total += t[key]
		print("  %-30s %7.0f ms" % [key, t[key] / 1000.0])
	print("  %-30s %7.0f ms   (fans, ponds, mudflat filters not included)" % ["TOTAL", total / 1000.0])
	print("  filled max raise %.1f m" % (Array(filled).max() - Array(h).max()))
	quit()
