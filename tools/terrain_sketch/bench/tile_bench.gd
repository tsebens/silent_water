extends SceneTree
## Spike: cost of one terrain detail tile in GDScript (#952, #976). 64 x 64 cells at 2 m plus a 4-cell margin.
## Compares noise sampled per cell against noise filled in batches by the engine, then times the per-cell
## combine, an 8-neighbour slump, and the mesh and collision build.

const N: int = 64
const MARGIN: int = 4
const CELL: float = 2.0
const LAYERS: Array = [
	# [wavelength m, fractal type, octaves, amplitude m]
	[70.0, FastNoiseLite.FRACTAL_FBM, 5, 2.5],      # rugosity
	[55.0, FastNoiseLite.FRACTAL_RIDGED, 4, 7.0],   # crags
	[18.0, FastNoiseLite.FRACTAL_RIDGED, 2, 1.8],   # blocks
	[60.0, FastNoiseLite.FRACTAL_FBM, 2, 1.5],      # strata offset
	[400.0, FastNoiseLite.FRACTAL_FBM, 2, 4.5],     # strata thickness
	[90.0, FastNoiseLite.FRACTAL_FBM, 3, 4.0],      # ripple phase
	[9.0, FastNoiseLite.FRACTAL_FBM, 2, 1.6],       # scree
]

var _noises: Array[FastNoiseLite] = []


func _make(i: int) -> FastNoiseLite:
	var l: Array = LAYERS[i]
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed = 4417 + i
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.frequency = 1.0 / float(l[0])
	n.fractal_type = l[1]
	n.fractal_octaves = l[2]
	if i < 2:
		n.domain_warp_enabled = true
		n.domain_warp_amplitude = 18.0
		n.domain_warp_frequency = 1.0 / 120.0
	return n


func _init() -> void:
	for i: int in range(LAYERS.size()):
		_noises.append(_make(i))
	var w: int = N + 2 * MARGIN
	var cells: int = w * w
	var reps: int = 5
	var t_sample: float = 0.0
	var t_batch: float = 0.0
	var t_combine: float = 0.0
	var t_slump: float = 0.0
	var t_mesh: float = 0.0
	var t_shape: float = 0.0
	for r: int in range(reps):
		var ox: float = 300.0 + r * 128.0
		var oz: float = -500.0
		# A base surface like an upsampled macro tile: a slope with a bump.
		var base: PackedFloat32Array = PackedFloat32Array()
		base.resize(cells)
		for j: int in range(w):
			for i: int in range(w):
				base[j * w + i] = -300.0 + i * 0.6 + 20.0 * sin(j * 0.05)

		# 1. Per-sample noise: every layer, every cell, from GDScript.
		var t0: int = Time.get_ticks_usec()
		var per: Array[PackedFloat32Array] = []
		for n: FastNoiseLite in _noises:
			var a: PackedFloat32Array = PackedFloat32Array()
			a.resize(cells)
			for j: int in range(w):
				for i: int in range(w):
					a[j * w + i] = n.get_noise_2d(ox + i * CELL, oz + j * CELL)
			per.append(a)
		t_sample += Time.get_ticks_usec() - t0

		# 2. Batched noise: the engine fills a whole layer; GDScript only decodes bytes.
		t0 = Time.get_ticks_usec()
		var bat: Array[PackedFloat32Array] = []
		for n: FastNoiseLite in _noises:
			var f: float = n.frequency
			n.frequency = f * CELL                      # one pixel per cell
			n.offset = Vector3(ox / CELL, oz / CELL, 0.0)
			var img: Image = n.get_image(w, w, false, false, false)
			n.frequency = f
			var bytes: PackedByteArray = img.get_data()
			var a: PackedFloat32Array = PackedFloat32Array()
			a.resize(cells)
			for k: int in range(cells):
				a[k] = bytes[k] / 127.5 - 1.0
			bat.append(a)
		t_batch += Time.get_ticks_usec() - t0

		# 3. Combine: slope, rock weight, crags, strata, rugosity, scree, ripples.
		t0 = Time.get_ticks_usec()
		var h: PackedFloat32Array = base.duplicate()
		for j: int in range(1, w - 1):
			for i: int in range(1, w - 1):
				var k: int = j * w + i
				var gx: float = (base[k + 1] - base[k - 1]) / (2.0 * CELL)
				var gz: float = (base[k + w] - base[k - w]) / (2.0 * CELL)
				var s: float = rad_to_deg(atan(sqrt(gx * gx + gz * gz)))
				var rock: float = smoothstep(24.0, 38.0, s)
				var v: float = h[k] + bat[1][k] * 7.0 * rock + bat[2][k] * 1.8 * rock
				var thick: float = 10.0 * (1.0 + 0.45 * bat[4][k])
				var q: float = v / thick
				var band: float = floorf(q)
				var strata: float = (band + smoothstep(0.25, 0.75, q - band)) * thick + bat[3][k] * 1.5
				v = lerpf(v, strata, 0.5 * rock * smoothstep(28.0, 45.0, s))
				v += bat[0][k] * 2.5 * (0.45 + 0.55 * rock)
				var phase: float = (i * CELL) / 22.0 * TAU + bat[5][k] * 4.0
				v += (absf(sin(phase * 0.5)) - 0.6) * 1.6 * (1.0 - rock)
				h[k] = v
		t_combine += Time.get_ticks_usec() - t0

		# 4. Slump: three 8-neighbour passes.
		t0 = Time.get_ticks_usec()
		var tan_t: float = tan(deg_to_rad(42.0))
		for it: int in range(3):
			var delta: PackedFloat32Array = PackedFloat32Array()
			delta.resize(cells)
			for j: int in range(w - 1):
				for i: int in range(1, w - 1):
					var k: int = j * w + i
					for o: Vector3i in [Vector3i(1, 0, 10), Vector3i(0, 1, 10), Vector3i(1, 1, 14), Vector3i(-1, 1, 14)]:
						var nb: int = k + o.x + o.y * w
						var d: float = h[k] - h[nb]
						var ex: float = absf(d) - tan_t * CELL * o.z * 0.1
						if ex > 0.0:
							var m: float = ex * 0.1 * signf(d)
							delta[k] -= m
							delta[nb] += m
			for k: int in range(cells):
				h[k] += delta[k]
		t_slump += Time.get_ticks_usec() - t0

		# 5. Mesh: the inner 64 x 64 cells (65 x 65 vertices), with normals and vertex colours.
		t0 = Time.get_ticks_usec()
		var vn: int = N + 1
		var verts: PackedVector3Array = PackedVector3Array()
		var norms: PackedVector3Array = PackedVector3Array()
		var cols: PackedColorArray = PackedColorArray()
		verts.resize(vn * vn); norms.resize(vn * vn); cols.resize(vn * vn)
		for j: int in range(vn):
			for i: int in range(vn):
				var k: int = (j + MARGIN) * w + (i + MARGIN)
				var nrm: Vector3 = Vector3(h[k - 1] - h[k + 1], 2.0 * CELL, h[k - w] - h[k + w]).normalized()
				var vi: int = j * vn + i
				verts[vi] = Vector3(ox + i * CELL, h[k], oz + j * CELL)
				norms[vi] = nrm
				cols[vi] = Color(0.6, 0.55, 0.45).lerp(Color(0.4, 0.4, 0.42), smoothstep(0.82, 0.55, nrm.y))
		var idx: PackedInt32Array = PackedInt32Array()
		idx.resize(N * N * 6)
		var p: int = 0
		for j: int in range(N):
			for i: int in range(N):
				var a: int = j * vn + i
				idx[p] = a; idx[p + 1] = a + 1; idx[p + 2] = a + vn
				idx[p + 3] = a + 1; idx[p + 4] = a + vn + 1; idx[p + 5] = a + vn
				p += 6
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts; arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_COLOR] = cols; arrays[Mesh.ARRAY_INDEX] = idx
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		t_mesh += Time.get_ticks_usec() - t0

		# 6. Collision shape for the tile.
		t0 = Time.get_ticks_usec()
		var shape: HeightMapShape3D = HeightMapShape3D.new()
		shape.map_width = vn
		shape.map_depth = vn
		var data: PackedFloat32Array = PackedFloat32Array()
		data.resize(vn * vn)
		for j: int in range(vn):
			for i: int in range(vn):
				data[j * vn + i] = h[(j + MARGIN) * w + (i + MARGIN)] / CELL
		shape.map_data = data
		t_shape += Time.get_ticks_usec() - t0

	var ms: Callable = func(us: float) -> float: return us / reps / 1000.0
	var total_batched: float = ms.call(t_batch + t_combine + t_slump + t_mesh + t_shape)
	print("tile %d x %d cells (+%d margin), mean of %d tiles, ms:" % [N, N, MARGIN, reps])
	print("  noise per-sample  %7.1f   (%d layers x %d cells)" % [ms.call(t_sample), LAYERS.size(), cells])
	print("  noise batched     %7.1f" % ms.call(t_batch))
	print("  combine           %7.1f" % ms.call(t_combine))
	print("  slump (3 passes)  %7.1f" % ms.call(t_slump))
	print("  mesh build        %7.1f" % ms.call(t_mesh))
	print("  collision shape   %7.1f" % ms.call(t_shape))
	print("  TOTAL batched     %7.1f   -> whole map (286 tiles) on one thread %.1f s" % [total_batched, total_batched * 286.0 / 1000.0])
	print("  TOTAL per-sample  %7.1f" % (total_batched - ms.call(t_batch) + ms.call(t_sample)))
	print("  worker threads available: %d" % OS.get_processor_count())
	quit()
