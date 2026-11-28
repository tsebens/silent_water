extends TestCase
## Flood zone model: loads the real research-station program, breaches spread through open doors only,
## closed watertight doors cut flooding, sea connection, and replication round-trip.


func _fz() -> FloodZones:
	var fz: FloodZones = FloodZones.load_program()
	expect(fz != null, "program loads")
	return fz


func test_loads_zones_from_real_program() -> void:
	var fz: FloodZones = _fz()
	for z: StringName in [&"main", &"maintenance", &"dock", &"power", &"refuge", &"lockout", &"life_support", &"dock_airlock", &"reactor", &"link_tunnel", &"power_tunnel"]:
		expect(fz.has_zone(z), "zone %s" % z)
	expect_eq(fz.zone_of_room(&"science_lab"), &"main", "lab in main")
	expect_eq(fz.zone_of_room(&"stair"), &"main", "stair in main")
	expect_eq(fz.zone_of_room(&"workshop"), &"maintenance", "workshop")
	expect_eq(fz.zone_of_room(&"dock_passage"), &"dock", "dock passage")
	expect_eq(fz.zone_of_room(&"reactor_hall"), &"reactor", "reactor hall")
	expect_eq(fz.zone_of_room(&"refuge"), &"refuge", "refuge")


func test_loads_doors_between_zones() -> void:
	var fz: FloodZones = _fz()
	expect(fz.door_keys().has("link_tunnel|main"), "main to link tunnel")
	expect(fz.door_keys().has("link_tunnel|maintenance"), "link tunnel to maintenance")
	expect(fz.door_kinds("link_tunnel|main").has("watertight"), "tunnel door is watertight")
	expect(fz.door_keys().has("lockout|sea"), "lockout hatch to sea")
	expect(not fz.is_door_open("lockout|sea"), "sea hatch starts closed")
	expect(fz.is_door_open("link_tunnel|main"), "watertight door starts open")


func test_everything_starts_dry() -> void:
	var fz: FloodZones = _fz()
	for z: Variant in fz.zone_ids():
		expect_eq(fz.zone_status(z), &"dry", "%s dry" % z)
		expect(not fz.connected_to_sea(z), "%s not connected" % z)


func test_breach_floods_zone_and_spreads_through_open_doors() -> void:
	var fz: FloodZones = _fz()
	fz.set_breach(&"main")
	expect(fz.is_flooded(&"main"), "breached zone floods")
	expect(fz.is_flooded(&"link_tunnel"), "spreads through open watertight door")
	expect(fz.is_flooded(&"maintenance"), "and on")
	expect(fz.is_flooded(&"dock"), "and on to the dock")
	expect(fz.is_flooded(&"power_tunnel"), "and the power tunnel")
	expect(fz.is_flooded(&"reactor"), "the reactor")
	expect_eq(fz.zone_status(&"main"), &"flooded", "status string")


func test_closed_watertight_door_stops_spread() -> void:
	var fz: FloodZones = _fz()
	expect(fz.set_between(&"main", &"link_tunnel", false), "door found")
	fz.set_breach(&"main")
	expect(fz.is_flooded(&"main"), "main floods")
	expect(not fz.is_flooded(&"link_tunnel"), "tunnel stays dry")
	expect(not fz.is_flooded(&"maintenance"), "maintenance stays dry")
	expect(not fz.connected_to_sea(&"maintenance"), "maintenance not connected")
	expect(fz.connected_to_sea(&"main"), "main connected")


func test_closing_after_breach_does_not_unflood_but_blocks_further() -> void:
	var fz: FloodZones = _fz()
	fz.set_between(&"maintenance", &"life_support", false)
	fz.set_breach(&"maintenance")
	expect(fz.is_flooded(&"maintenance"), "maintenance flooded")
	expect(not fz.is_flooded(&"life_support"), "closed door kept life support dry")


func test_connected_to_sea_by_open_path() -> void:
	var fz: FloodZones = _fz()
	fz.set_breach(&"lockout")
	expect(fz.connected_to_sea(&"lockout"), "breached zone connected")
	expect(fz.connected_to_sea(&"maintenance"), "open path to breach")
	expect(fz.connected_to_sea(&"main"), "far end too")
	fz.set_between(&"maintenance", &"link_tunnel", false)
	expect(not fz.connected_to_sea(&"main"), "closing cuts the path")
	fz.set_breach(&"lockout", false)
	expect(not fz.connected_to_sea(&"maintenance"), "repaired breach disconnects")


func test_open_sea_hatch_connects() -> void:
	var fz: FloodZones = _fz()
	fz.set_door_open("lockout|sea", true)
	expect(fz.connected_to_sea(&"lockout"), "open hatch to sea")
	expect(fz.is_flooded(&"lockout"), "lockout floods")
	fz.set_between(&"lockout", &"maintenance", true)
	expect(fz.is_flooded(&"maintenance"), "spread beyond the lockout")


func test_drain_stays_dry_only_when_disconnected() -> void:
	var fz: FloodZones = _fz()
	fz.set_between(&"main", &"link_tunnel", false)
	fz.set_between(&"main", &"refuge", false)
	fz.set_breach(&"main")
	fz.set_breach(&"main", false)
	fz.drain(&"main")
	expect(not fz.is_flooded(&"main"), "drained and sealed")
	fz.set_breach(&"main")
	fz.drain(&"main")
	expect(fz.is_flooded(&"main"), "refloods while breached")


func test_state_replicates() -> void:
	var host: FloodZones = _fz()
	host.set_between(&"main", &"link_tunnel", false)
	host.set_breach(&"main")
	var client: FloodZones = _fz()
	client.state = FloodZoneState.from_dict(host.state.to_dict())
	for z: Variant in host.zone_ids():
		expect_eq(client.is_flooded(z), host.is_flooded(z), "%s flooded matches" % z)
		expect_eq(client.is_breached(z), host.is_breached(z), "%s breach matches" % z)
		expect_eq(client.connected_to_sea(z), host.connected_to_sea(z), "%s sea matches" % z)
	expect(not client.is_door_open("link_tunnel|main"), "door state replicated")
