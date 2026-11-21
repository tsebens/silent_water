extends TestCase
## SiteSpec: the canyon preset reproduces the pre-spec generator, and the
## generator is deterministic from spec + seed.

## height_at on x in -100..100 step 25 (9 columns), z in -450..50 step 25
## (21 rows), row-major, captured from the generator before it read a spec.
const GOLDEN: Array[float] = [-17.816825,-17.436085,-70.615283,-124.384143,-124.383835,-123.056597,-37.793359,-16.982447,-18.535010,-15.605463,-14.999319,-115.100358,-231.467504,-230.269945,-230.954180,-72.998640,-16.600764,-17.259464,-17.001991,-17.063295,-91.216574,-229.737351,-229.834143,-230.083319,-80.617008,-15.406758,-17.341693,-16.273747,-16.188578,-78.116204,-232.555208,-231.597714,-229.711984,-84.494203,-16.144879,-17.349380,-18.399744,-17.688649,-57.482007,-230.481548,-228.907246,-231.927681,-85.803761,-17.045209,-17.651630,-16.216948,-15.520521,-53.669372,-228.650811,-229.447674,-139.877496,-86.349770,-14.163216,-17.558940,-17.161639,-16.837216,-81.384630,-228.311985,-231.001230,-140.659420,-74.918507,-15.776326,-17.284355,-16.231792,-14.271673,-100.245624,-229.579712,-227.993467,-139.618714,-83.918949,-16.046550,-15.738881,-18.811824,-15.883593,-110.483447,-227.739274,-231.012706,-139.969333,-128.538083,-18.193205,-17.253037,-15.766907,-16.588013,-104.999986,-231.136413,-230.488897,-141.350358,-111.595946,-14.784721,-16.422609,-16.640327,-16.451611,-88.494646,-230.703850,-230.370457,-145.484241,-118.182384,-15.364693,-17.695474,-17.543027,-15.737000,-102.981045,-229.911309,-228.644310,-228.278621,-111.631737,-17.102274,-18.404817,-15.119586,-15.111114,-59.104733,-62.655976,-230.631489,-231.718850,-106.740860,-13.114092,-14.457261,-18.759320,-17.768079,-60.891696,-64.704920,-228.663451,-227.395003,-108.173518,-17.130483,-17.814437,-16.663977,-15.300420,-60.729328,-58.447427,-229.915651,-230.837177,-115.277337,-15.544143,-17.612552,-16.781891,-15.286897,-59.694907,-75.652174,-231.949659,-229.454344,-107.328652,-16.441298,-18.433349,-18.408459,-14.184360,-59.684394,-73.714084,-229.001010,-227.698324,-108.760094,-15.473799,-15.931267,-16.920432,-17.994260,-55.536587,-229.098171,-229.485765,-229.506929,-81.818977,-17.771203,-17.581767,-17.215475,-17.937565,-77.945714,-231.908846,-229.650862,-228.433382,-81.586450,-15.329295,-17.724735,-17.009774,-14.708134,-111.046409,-230.478835,-229.679108,-229.738986,-64.562747,-16.397893,-18.454018,-17.763045,-15.215323,-65.567369,-123.865822,-123.671449,-122.657238,-37.990957,-16.786276,-16.231230]


func test_preset_loads() -> void:
	var spec: SiteSpec = load(CanyonSite.PRESET) as SiteSpec
	expect(spec != null, "canyon.tres loads as a SiteSpec")
	expect_eq(spec.seed, 4417)
	expect_eq(spec.shelves.size(), 2)


func test_preset_mirrors_site_constants() -> void:
	var spec: SiteSpec = load(CanyonSite.PRESET) as SiteSpec
	expect_eq(spec.rim_y, CanyonSite.RIM_Y)
	expect_eq(spec.floor_y, CanyonSite.FLOOR_Y)
	expect_eq(spec.north_z, CanyonSite.NORTH_Z)
	expect_eq(spec.south_z, CanyonSite.SOUTH_Z)
	expect_eq(spec.shelves[0].footprint, CanyonSite.SHELF1)
	expect_eq(spec.shelves[0].top_y, CanyonSite.SHELF1_TOP)
	expect_eq(spec.shelves[1].footprint, CanyonSite.SHELF2)
	expect_eq(spec.shelves[1].top_y, CanyonSite.SHELF2_TOP)


func test_heights_match_pre_spec_generator() -> void:
	var site: CanyonSite = CanyonSite.new()
	var k: int = 0
	var worst: float = 0.0
	var z: float = -450.0
	while z <= 50.0:
		var x: float = -100.0
		while x <= 100.0:
			worst = maxf(worst, absf(site.height_at(x, z) - GOLDEN[k]))
			k += 1
			x += 25.0
		z += 25.0
	expect_eq(k, GOLDEN.size())
	# Golden values are printed to 1e-6 m.
	expect(worst < 0.001, "worst deviation %f m" % worst)
	site.free()


func test_same_spec_same_heights() -> void:
	var spec: SiteSpec = load(CanyonSite.PRESET) as SiteSpec
	var a: CanyonSite = CanyonSite.new()
	var b: CanyonSite = CanyonSite.new()
	a.spec = spec
	b.spec = spec
	for p: Vector2 in [Vector2(3, -77), Vector2(-50, -300), Vector2(45, -10), Vector2(-90, -400)]:
		expect_eq(a.height_at(p.x, p.y), b.height_at(p.x, p.y))
	a.free()
	b.free()


func test_seed_changes_ground() -> void:
	var a: CanyonSite = CanyonSite.new()
	var b: CanyonSite = CanyonSite.new()
	var other: SiteSpec = (load(CanyonSite.PRESET) as SiteSpec).duplicate() as SiteSpec
	other.seed = 99
	b.spec = other
	expect(absf(a.height_at(-45, -100) - b.height_at(-45, -100)) > 0.01, "a different seed gives different ground")
	a.free()
	b.free()


func test_centreline_shifts_canyon() -> void:
	var spec: SiteSpec = (load(CanyonSite.PRESET) as SiteSpec).duplicate() as SiteSpec
	spec.centreline = PackedVector2Array([Vector2(20, 60), Vector2(20, -460)])
	var a: CanyonSite = CanyonSite.new()
	var b: CanyonSite = CanyonSite.new()
	b.spec = spec
	expect_near(spec.centre_x(-100.0), 20.0, 0.001)
	expect(absf(a.height_at(-45, -250) - b.height_at(-45, -250)) > 5.0, "moving the centreline moves the wall")
	a.free()
	b.free()
