//
// This file is part of the Simutrans project under the Artistic License.
// (see LICENSE.txt)
//


function create_simple_schedule(waytype, stop_positions)
{
	return schedule_x(waytype, stop_positions.map(@(pos) schedule_entry_x(pos, 0, 0)))
}

//
// Tests for transporting passengers, mail and goods
//

function test_transport_generate_pax_invalid_pos()
{
	ASSERT_EQUAL(world.generate_goods(coord(-1, -1), coord(-1, -1), good_desc_x.passenger, 42), 0)
	ASSERT_EQUAL(world.generate_goods(coord( 0,  0), coord(-1, -1), good_desc_x.passenger, 42), 0)
	ASSERT_EQUAL(world.generate_goods(coord(-1, -1), coord( 0,  0), good_desc_x.passenger, 42), 0)
}


function test_transport_generate_pax_walked()
{
	ASSERT_EQUAL(command_x(tool_build_way).work(player_x(0), coord3d(4, 2, 0), coord3d(4, 3, 0), "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(player_x(0), coord3d(4, 2, 0), "BusStop"), null)

	{
		ASSERT_EQUAL(world.generate_goods(coord(3, 2), coord(5, 2), good_desc_x.passenger, 42), 2) // 2 == walked

		ASSERT_EQUAL(halt_x.get_halt(coord3d(4, 2, 0), player_x(0)).get_walked()[0], 42)
	}

	// clean up
	ASSERT_EQUAL(command_x(tool_remover).work(player_x(0), coord3d(4, 2, 0)), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(player_x(0), coord3d(4, 2, 0), coord3d(4, 3, 0), "" + wt_road), null)
	RESET_ALL_PLAYER_FUNDS()
}


function test_transport_generate_pax_no_route()
{
	ASSERT_EQUAL(command_x(tool_build_way).work(player_x(0), coord3d(4, 2, 0), coord3d(4, 7, 0), "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(player_x(0), coord3d(4, 2, 0), "BusStop"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(player_x(0), coord3d(4, 7, 0), "BusStop"), null)

	{
		local from_halt = halt_x.get_halt(coord3d(4, 2, 0), player_x(0))
		ASSERT_EQUAL(world.generate_goods(coord(3, 2), coord(3, 7), good_desc_x.passenger, 42), 0)
		ASSERT_EQUAL(from_halt.get_noroute()[0], 42)
		ASSERT_EQUAL(from_halt.get_route_too_long()[0], 0)
	}

	// clean up
	ASSERT_EQUAL(command_x(tool_remover).work(player_x(0), coord3d(4, 2, 0)), null)
	ASSERT_EQUAL(command_x(tool_remover).work(player_x(0), coord3d(4, 7, 0)), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(player_x(0), coord3d(4, 2, 0), coord3d(4, 7, 0), "" + wt_road), null)
	RESET_ALL_PLAYER_FUNDS()
}


function test_transport_pax_rejects_excessive_schedule_detour()
{
	local pl = player_x(0)
	local a = coord3d(4, 2, 0)
	local b = coord3d(4, 7, 0)
	local c = coord3d(4, 10, 0)
	local d = coord3d(4, 14, 0)
	local depot_pos = coord3d(4, 15, 0)

	ASSERT_EQUAL(command_x(tool_build_way).work(pl, a, d, "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_way).work(pl, d, depot_pos, "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, a, "BusStop"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, b, "BusStop"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, d, "BusStop"), null)
	ASSERT_EQUAL(command_x.build_depot(pl, depot_pos, building_desc_x("CarDepot")), null)

	local depot = depot_x(depot_pos.x, depot_pos.y, depot_pos.z)
	depot.append_vehicle(pl, convoy_x(0), vehicle_desc_x("Buessig"))
	local cnv = depot.get_convoy_list()[0]
	cnv.change_schedule(pl, create_simple_schedule(wt_road, [a, d, c, b]))
	depot.start_all_convoys(pl)

	while (!halt_x.is_rerouting_finished()) {
		sleep()
	}

	// The scheduled trip A-D-C-B is 19 tiles while A-B is only 5 tiles.
	local from_halt = halt_x.get_halt(a, pl)
	ASSERT_EQUAL(world.generate_goods(coord(3, 2), coord(3, 7), good_desc_x.passenger, 30), 4) // 4 == route too long
	ASSERT_EQUAL(from_halt.get_route_too_long()[0], 30)
	ASSERT_EQUAL(from_halt.get_noroute()[0], 0)
	ASSERT_EQUAL(from_halt.get_unhappy()[0], 0)
	ASSERT_EQUAL(from_halt.get_waiting()[0], 0)

	cnv.destroy(pl)
	sleep()
	sleep()
	ASSERT_EQUAL(command_x(tool_remover).work(pl, a), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, b), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, d), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, depot_pos), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(pl, a, d, "" + wt_road), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(pl, d, depot_pos, "" + wt_road), null)
	RESET_ALL_PLAYER_FUNDS()
}


function test_transport_pax_accepts_detour_at_exact_limit()
{
	local pl = player_x(0)
	local a = coord3d(4, 2, 0)
	local b = coord3d(4, 10, 0)
	local branch_start = coord3d(4, 4, 0)
	local waypoint = coord3d(10, 4, 0)
	local depot_pos = coord3d(4, 11, 0)

	// A-waypoint-B is exactly 20 tiles, while A-B is 8 tiles: 2.5x.
	ASSERT_EQUAL(command_x(tool_build_way).work(pl, a, depot_pos, "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_way).work(pl, branch_start, waypoint, "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, a, "BusStop"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, b, "BusStop"), null)
	ASSERT_EQUAL(command_x.build_depot(pl, depot_pos, building_desc_x("CarDepot")), null)

	local depot = depot_x(depot_pos.x, depot_pos.y, depot_pos.z)
	depot.append_vehicle(pl, convoy_x(0), vehicle_desc_x("Buessig"))
	local cnv = depot.get_convoy_list()[0]
	cnv.change_schedule(pl, create_simple_schedule(wt_road, [a, waypoint, b]))
	depot.start_all_convoys(pl)

	while (!halt_x.is_rerouting_finished()) {
		sleep()
	}

	local from_halt = halt_x.get_halt(a, pl)
	ASSERT_EQUAL(world.generate_goods(coord(3, 2), coord(3, 10), good_desc_x.passenger, 30), 1)
	ASSERT_EQUAL(from_halt.get_waiting()[0], 30)
	ASSERT_EQUAL(from_halt.get_route_too_long()[0], 0)

	cnv.destroy(pl)
	sleep()
	sleep()
	ASSERT_EQUAL(command_x(tool_remover).work(pl, a), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, b), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, depot_pos), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(pl, branch_start, waypoint, "" + wt_road), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(pl, a, depot_pos, "" + wt_road), null)
	RESET_ALL_PLAYER_FUNDS()
}


function test_transport_pax_rejects_excessive_transfer_detour()
{
	local pl = player_x(0)
	local a = coord3d(4, 2, 0)
	local b = coord3d(4, 7, 0)
	local d = coord3d(4, 14, 0)
	local depot_pos = coord3d(4, 15, 0)

	ASSERT_EQUAL(command_x(tool_build_way).work(pl, a, d, "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_way).work(pl, d, depot_pos, "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, a, "BusStop"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, b, "BusStop"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, d, "BusStop"), null)
	ASSERT_EQUAL(command_x.build_depot(pl, depot_pos, building_desc_x("CarDepot")), null)

	local depot = depot_x(depot_pos.x, depot_pos.y, depot_pos.z)
	depot.append_vehicle(pl, convoy_x(0), vehicle_desc_x("Buessig"))
	local first_cnv = depot.get_convoy_list()[0]
	first_cnv.change_schedule(pl, create_simple_schedule(wt_road, [a, d]))

	depot.append_vehicle(pl, convoy_x(0), vehicle_desc_x("Buessig"))
	local second_cnv = depot.get_convoy_list()[1]
	second_cnv.change_schedule(pl, create_simple_schedule(wt_road, [d, b]))
	depot.start_all_convoys(pl)

	while (!halt_x.is_rerouting_finished()) {
		sleep()
	}

	// Each leg is direct, but A-D-B totals 19 tiles versus 5 tiles directly.
	local from_halt = halt_x.get_halt(a, pl)
	ASSERT_EQUAL(world.generate_goods(coord(3, 2), coord(3, 7), good_desc_x.passenger, 30), 4) // 4 == route too long
	ASSERT_EQUAL(from_halt.get_route_too_long()[0], 30)
	ASSERT_EQUAL(from_halt.get_noroute()[0], 0)
	ASSERT_EQUAL(from_halt.get_unhappy()[0], 0)
	ASSERT_EQUAL(from_halt.get_waiting()[0], 0)

	first_cnv.destroy(pl)
	second_cnv.destroy(pl)
	sleep()
	sleep()
	ASSERT_EQUAL(command_x(tool_remover).work(pl, a), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, b), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, d), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, depot_pos), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(pl, a, d, "" + wt_road), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(pl, d, depot_pos, "" + wt_road), null)
	RESET_ALL_PLAYER_FUNDS()
}


function test_transport_reroute_removes_existing_excessive_transfer_detour()
{
	local pl = player_x(0)
	local a = coord3d(4, 2, 0)
	local b = coord3d(4, 7, 0)
	local d = coord3d(4, 14, 0)
	local depot_pos = coord3d(4, 15, 0)

	ASSERT_EQUAL(command_x(tool_build_way).work(pl, a, depot_pos, "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, a, "BusStop"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, b, "BusStop"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, d, "BusStop"), null)
	ASSERT_EQUAL(command_x.build_depot(pl, depot_pos, building_desc_x("CarDepot")), null)

	local depot = depot_x(depot_pos.x, depot_pos.y, depot_pos.z)
	local schedules = [
		[a, b],
		[a, d],
		[d, b]
	]
	local convoys = []
	foreach (index, entries in schedules) {
		depot.append_vehicle(pl, convoy_x(0), vehicle_desc_x("Buessig"))
		local cnv = depot.get_convoy_list()[index]
		cnv.change_schedule(pl, create_simple_schedule(wt_road, entries))
		convoys.append(cnv)
	}

	while (!halt_x.is_rerouting_finished()) {
		sleep()
	}

	// The direct service initially makes the waiting packet valid.
	local from_halt = halt_x.get_halt(a, pl)
	ASSERT_EQUAL(world.generate_goods(coord(3, 2), coord(3, 7), good_desc_x.passenger, 30), 1)
	ASSERT_EQUAL(from_halt.get_waiting()[0], 30)

	// Once it is removed, only A-D-B remains: 19 tiles versus 5 direct.
	// Existing waiting packets must be checked by the same detour-aware search
	// as newly generated packets, and removed without booking new demand stats.
	convoys[0].destroy(pl)
	while (!halt_x.is_rerouting_finished()) {
		sleep()
	}
	ASSERT_EQUAL(from_halt.get_waiting()[0], 0)
	ASSERT_EQUAL(from_halt.get_route_too_long()[0], 0)

	convoys[1].destroy(pl)
	convoys[2].destroy(pl)
	sleep()
	sleep()
	ASSERT_EQUAL(command_x(tool_remover).work(pl, a), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, b), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, d), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, depot_pos), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(pl, a, depot_pos, "" + wt_road), null)
	RESET_ALL_PLAYER_FUNDS()
}


function test_transport_pax_rejects_locally_excessive_transfer_leg()
{
	local pl = player_x(0)
	local a = coord3d(4, 2, 0)
	local b = coord3d(4, 8, 0)
	local c = coord3d(4, 13, 0)
	local e = coord3d(4, 9, 0)
	local f = coord3d(4, 12, 0)
	local d = coord3d(8, 9, 0)
	local depot_pos = coord3d(9, 9, 0)

	ASSERT_EQUAL(command_x(tool_build_way).work(pl, a, c, "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_way).work(pl, e, d, "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_way).work(pl, d, f, "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_way).work(pl, d, depot_pos, "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, a, "BusStop"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, b, "BusStop"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, c, "BusStop"), null)
	ASSERT_EQUAL(command_x.build_depot(pl, depot_pos, building_desc_x("CarDepot")), null)

	local depot = depot_x(depot_pos.x, depot_pos.y, depot_pos.z)
	depot.append_vehicle(pl, convoy_x(0), vehicle_desc_x("Buessig"))
	local first_cnv = depot.get_convoy_list()[0]
	first_cnv.change_schedule(pl, create_simple_schedule(wt_road, [a, b]))

	depot.append_vehicle(pl, convoy_x(0), vehicle_desc_x("Buessig"))
	local second_cnv = depot.get_convoy_list()[1]
	second_cnv.change_schedule(pl, create_simple_schedule(wt_road, [b, d, c]))
	depot.start_all_convoys(pl)

	while (!halt_x.is_rerouting_finished()) {
		sleep()
	}

	// Globally A-B-D-C is 19 tiles versus 11 direct (valid at 2.5x), but
	// the transfer leg B-D-C is 13 tiles versus only 5 direct (locally 2.6x).
	local from_halt = halt_x.get_halt(a, pl)
	ASSERT_EQUAL(world.generate_goods(coord(3, 2), coord(3, 13), good_desc_x.passenger, 30), 4)
	ASSERT_EQUAL(from_halt.get_route_too_long()[0], 30)
	ASSERT_EQUAL(from_halt.get_noroute()[0], 0)
	ASSERT_EQUAL(from_halt.get_waiting()[0], 0)

	first_cnv.destroy(pl)
	second_cnv.destroy(pl)
	sleep()
	sleep()
	ASSERT_EQUAL(command_x(tool_remover).work(pl, a), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, b), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, c), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, depot_pos), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(pl, a, c, "" + wt_road), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(pl, e, d, "" + wt_road), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(pl, d, depot_pos, "" + wt_road), null)
	RESET_ALL_PLAYER_FUNDS()
}


function test_transport_pax_uses_valid_alternative_to_invalid_transfer_leg()
{
	local pl = player_x(0)
	local a = coord3d(2, 2, 0)
	local b = coord3d(7, 2, 0)
	local e = coord3d(1, 7, 0)
	local c = coord3d(2, 12, 0)
	local d = coord3d(7, 12, 0)
	local top_left = coord3d(1, 2, 0)
	local top_right = coord3d(15, 2, 0)
	local waypoint = coord3d(15, 7, 0)
	local bottom_left = coord3d(1, 12, 0)
	local bottom_right = coord3d(15, 12, 0)
	local depot_pos = coord3d(15, 13, 0)

	ASSERT_EQUAL(command_x(tool_build_way).work(pl, top_left, top_right, "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_way).work(pl, top_right, depot_pos, "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_way).work(pl, bottom_left, bottom_right, "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_way).work(pl, top_left, bottom_left, "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, a, "BusStop"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, b, "BusStop"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, e, "BusStop"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, c, "BusStop"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, d, "BusStop"), null)
	ASSERT_EQUAL(command_x.build_depot(pl, depot_pos, building_desc_x("CarDepot")), null)

	local depot = depot_x(depot_pos.x, depot_pos.y, depot_pos.z)
	local schedules = [
		[a, b],
		[b, waypoint, d],
		[a, e, c],
		[c, d]
	]
	local convoys = []
	foreach (index, entries in schedules) {
		depot.append_vehicle(pl, convoy_x(0), vehicle_desc_x("Buessig"))
		local cnv = depot.get_convoy_list()[index]
		cnv.change_schedule(pl, create_simple_schedule(wt_road, entries))
		convoys.append(cnv)
	}
	depot.start_all_convoys(pl)

	while (!halt_x.is_rerouting_finished()) {
		sleep()
	}

	// A-B has the lower ordinary routing weight, but B-waypoint-D is
	// locally invalid (26/10 = 2.6x).  The heavier A-E-C, C-D alternative
	// is valid and must still be selected.
	local from_halt = halt_x.get_halt(a, pl)
	local via_b = halt_x.get_halt(b, pl)
	local via_c = halt_x.get_halt(c, pl)
	ASSERT_EQUAL(world.generate_goods(coord(3, 2), coord(8, 12), good_desc_x.passenger, 30), 1)
	ASSERT_EQUAL(from_halt.get_freight_to_halt(good_desc_x.passenger, via_b), 0)
	ASSERT_EQUAL(from_halt.get_freight_to_halt(good_desc_x.passenger, via_c), 30)
	ASSERT_EQUAL(from_halt.get_route_too_long()[0], 0)

	foreach (cnv in convoys) {
		cnv.destroy(pl)
	}
	sleep()
	sleep()
	ASSERT_EQUAL(command_x(tool_remover).work(pl, a), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, b), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, e), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, c), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, d), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, depot_pos), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(pl, top_left, top_right, "" + wt_road), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(pl, top_right, depot_pos, "" + wt_road), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(pl, bottom_left, bottom_right, "" + wt_road), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(pl, top_left, bottom_left, "" + wt_road), null)
	RESET_ALL_PLAYER_FUNDS()
}


function test_transport_pax_uses_short_service_and_skips_long_convoy()
{
	local pl = player_x(0)
	local a = coord3d(4, 2, 0)
	local b = coord3d(4, 7, 0)
	local waypoint = coord3d(4, 10, 0)
	local d = coord3d(4, 14, 0)
	local depot_pos = coord3d(4, 15, 0)

	ASSERT_EQUAL(command_x(tool_build_way).work(pl, a, depot_pos, "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, a, "BusStop"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, b, "BusStop"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, d, "BusStop"), null)
	ASSERT_EQUAL(command_x.build_depot(pl, depot_pos, building_desc_x("CarDepot")), null)

	local depot = depot_x(depot_pos.x, depot_pos.y, depot_pos.z)
	depot.append_vehicle(pl, convoy_x(0), vehicle_desc_x("Buessig"))
	local long_cnv = depot.get_convoy_list()[0]
	long_cnv.change_schedule(pl, create_simple_schedule(wt_road, [a, d, waypoint, b]))
	depot.start_all_convoys(pl)

	// Keep the direct convoy in the depot: its schedule makes A-B routable,
	// while only the long convoy can physically reach A during the first check.
	depot.append_vehicle(pl, convoy_x(0), vehicle_desc_x("Buessig"))
	local short_cnv = depot.get_convoy_list()[0]
	short_cnv.change_schedule(pl, create_simple_schedule(wt_road, [a, b]))

	while (!halt_x.is_rerouting_finished()) {
		sleep()
	}

	local from_halt = halt_x.get_halt(a, pl)
	local to_halt = halt_x.get_halt(b, pl)
	ASSERT_EQUAL(world.generate_goods(coord(3, 2), coord(3, 7), good_desc_x.passenger, 30), 1)
	ASSERT_EQUAL(from_halt.get_waiting()[0], 30)

	local wait_steps = 0
	while (from_halt.get_convoys()[0] == 0 && wait_steps < 500) {
		sleep()
		wait_steps++
	}
	ASSERT_TRUE(from_halt.get_convoys()[0] > 0)
	while (long_cnv.is_loading() && wait_steps < 600) {
		sleep()
		wait_steps++
	}
	// The local destination_halts filter prevents the A-D-waypoint-B convoy
	// from taking passengers whose route was found through the direct service.
	ASSERT_EQUAL(from_halt.get_waiting()[0], 30)

	depot.start_all_convoys(pl)
	wait_steps = 0
	while (from_halt.get_waiting()[0] > 0 && wait_steps < 500) {
		sleep()
		wait_steps++
	}
	ASSERT_EQUAL(from_halt.get_waiting()[0], 0)
	wait_steps = 0
	while (to_halt.get_arrived()[0] < 30 && wait_steps < 500) {
		sleep()
		wait_steps++
	}
	ASSERT_EQUAL(to_halt.get_arrived()[0], 30)

	long_cnv.destroy(pl)
	short_cnv.destroy(pl)
	sleep()
	sleep()
	ASSERT_EQUAL(command_x(tool_remover).work(pl, a), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, b), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, d), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, depot_pos), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(pl, a, depot_pos, "" + wt_road), null)
	RESET_ALL_PLAYER_FUNDS()
}


function test_transport_freight_rejects_excessive_schedule_detour()
{
	local pl = player_x(0)
	local main_a = coord3d(4, 2, 0)
	local main_b = coord3d(4, 7, 0)
	local main_d = coord3d(4, 14, 0)
	local a = coord3d(5, 2, 0)
	local b = coord3d(5, 7, 0)
	local waypoint = coord3d(4, 10, 0)
	local d = coord3d(5, 14, 0)
	local depot_pos = coord3d(4, 15, 0)

	ASSERT_EQUAL(command_x(tool_build_way).work(pl, main_a, depot_pos, "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_way).work(pl, main_a, a, "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_way).work(pl, main_b, b, "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_way).work(pl, main_d, d, "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, a, "CarStop"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, b, "CarStop"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, d, "CarStop"), null)
	ASSERT_EQUAL(command_x.build_depot(pl, depot_pos, building_desc_x("CarDepot")), null)

	local depot = depot_x(depot_pos.x, depot_pos.y, depot_pos.z)
	depot.append_vehicle(pl, convoy_x(0), vehicle_desc_x("Kohletransporter"))
	local cnv = depot.get_convoy_list()[0]
	cnv.change_schedule(pl, create_simple_schedule(wt_road, [a, d, waypoint, b]))
	depot.start_all_convoys(pl)

	while (!halt_x.is_rerouting_finished()) {
		sleep()
	}

	local from_halt = halt_x.get_halt(a, pl)
	ASSERT_EQUAL(world.generate_goods(coord(6, 2), coord(6, 7), good_desc_x("Kohle"), 18), 4)
	ASSERT_EQUAL(from_halt.get_waiting()[0], 0)
	// Route-too-long satisfaction is deliberately passenger-only.
	ASSERT_EQUAL(from_halt.get_route_too_long()[0], 0)
	ASSERT_EQUAL(from_halt.get_noroute()[0], 0)

	cnv.destroy(pl)
	sleep()
	sleep()
	ASSERT_EQUAL(command_x(tool_remover).work(pl, a), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, b), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, d), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, depot_pos), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(pl, main_a, a, "" + wt_road), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(pl, main_b, b, "" + wt_road), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(pl, main_d, d, "" + wt_road), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(pl, main_a, depot_pos, "" + wt_road), null)
	RESET_ALL_PLAYER_FUNDS()
}


function test_transport_pax_valid_route()
{
	local pl = player_x(0)

	ASSERT_EQUAL(command_x(tool_build_way).work(pl, coord3d(4, 2, 0), coord3d(4, 8, 0), "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, coord3d(4, 2, 0), "BusStop"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, coord3d(4, 7, 0), "BusStop"), null)
	ASSERT_EQUAL(command_x.build_depot(pl, coord3d(4, 8, 0), building_desc_x("CarDepot")), null)

	local depot     = depot_x(4, 8, 0)
	local from_halt = halt_x.get_halt(coord3d(4, 7, 0), pl)
	local to_halt   = halt_x.get_halt(coord3d(4, 2, 0), pl)

	// create vehicle ...
	depot.append_vehicle(pl, convoy_x(0), vehicle_desc_x("Buessig"))
	local cnv = depot.get_convoy_list()[0]
	// ... with simple 2-entry schedule ...
	cnv.change_schedule(pl, create_simple_schedule(wt_road, [ coord3d(4, 7, 0), coord3d(4, 2, 0) ]))
	// and start the convoy
	depot.start_all_convoys(pl)

	// make sure that the graph linking and all halts is updated
	while(!halt_x.is_rerouting_finished()) {
		sleep()
	}

	{
		ASSERT_EQUAL(world.generate_goods(coord(3, 7), coord(3, 2), good_desc_x.passenger, 30), 1) // 1 == OK

		ASSERT_EQUAL(from_halt.waiting[0], 30)
		ASSERT_EQUAL(from_halt.get_freight_to_halt(good_desc_x.passenger, to_halt), 30)
		ASSERT_EQUAL(from_halt.get_freight_to_dest(good_desc_x.passenger, coord3d(3, 2, 0)), 30)
		ASSERT_EQUAL(from_halt.get_freight_to_dest(good_desc_x.passenger, coord3d(4, 2, 0)), 0)
		ASSERT_EQUAL(from_halt.happy[0], 30)
		ASSERT_EQUAL(from_halt.unhappy[0], 0)
		ASSERT_EQUAL(from_halt.noroute[0], 0)
		ASSERT_EQUAL(from_halt.walked[0], 0)
		ASSERT_EQUAL(from_halt.departed[0], 0)
		ASSERT_EQUAL(from_halt.arrived[0], 0)
		ASSERT_EQUAL(from_halt.convoys[0], 0)
	}

	while (from_halt.convoys[0] == 0) {
		sleep()
	}

	// Loading is not instant, so we need to make sure loading has finished
	while (from_halt.waiting[0] > 0) {
		sleep()
	}

	{
		ASSERT_EQUAL(from_halt.convoys[0], 1)
		ASSERT_EQUAL(from_halt.waiting[0], 0)
		ASSERT_EQUAL(from_halt.get_freight_to_halt(good_desc_x.passenger, to_halt), 0)
		ASSERT_EQUAL(from_halt.get_freight_to_dest(good_desc_x.passenger, coord3d(3, 2, 0)), 0)
		ASSERT_EQUAL(from_halt.get_freight_to_dest(good_desc_x.passenger, coord3d(4, 2, 0)), 0)
		ASSERT_EQUAL(from_halt.happy[0], 30)
		ASSERT_EQUAL(from_halt.unhappy[0], 0)
		ASSERT_EQUAL(from_halt.noroute[0], 0)
		ASSERT_EQUAL(from_halt.walked[0], 0)
		ASSERT_EQUAL(from_halt.departed[0], 30)
		ASSERT_EQUAL(from_halt.arrived[0], 0)
	}

	while (to_halt.convoys[0] == 0) {
		sleep()
	}

	// make sure unloading has finished
	while (to_halt.arrived[0] < 30) {
		sleep()
	}

	{
		ASSERT_EQUAL(to_halt.waiting[0], 0)
		ASSERT_EQUAL(to_halt.happy[0], 0)
		ASSERT_EQUAL(to_halt.unhappy[0], 0)
		ASSERT_EQUAL(to_halt.noroute[0], 0)
		ASSERT_EQUAL(to_halt.walked[0], 0)
		ASSERT_EQUAL(to_halt.departed[0], 0)
		ASSERT_EQUAL(to_halt.arrived[0], 30)
	}

	// clean up
	cnv.destroy(pl)
	sleep()
	sleep() // make sure the convoy is destroyed
	ASSERT_EQUAL(command_x(tool_remover).work(player_x(0), coord3d(4, 2, 0)), null)
	ASSERT_EQUAL(command_x(tool_remover).work(player_x(0), coord3d(4, 7, 0)), null)
	ASSERT_EQUAL(command_x(tool_remover).work(player_x(0), coord3d(4, 8, 0)), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(player_x(0), coord3d(4, 2, 0), coord3d(4, 8, 0), "" + wt_road), null)
	RESET_ALL_PLAYER_FUNDS()
}


function test_transport_mail_valid_route()
{
	local pl = player_x(0)

	ASSERT_EQUAL(command_x(tool_build_way).work(pl, coord3d(4, 2, 0), coord3d(4, 8, 0), "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, coord3d(4, 2, 0), "PostStop"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, coord3d(4, 7, 0), "PostStop"), null)
	ASSERT_EQUAL(command_x.build_depot(pl, coord3d(4, 8, 0), building_desc_x("CarDepot")), null)

	local depot = depot_x(4, 8, 0)
	local from_halt = halt_x.get_halt(coord3d(4, 7, 0), pl)
	local to_halt   = halt_x.get_halt(coord3d(4, 2, 0), pl)

	// create vehicle ...
	depot.append_vehicle(pl, convoy_x(0), vehicle_desc_x("Posttransporter"))
	local cnv = depot.get_convoy_list()[0]
	// ... with simple 2-entry schedule ...
	cnv.change_schedule(pl, create_simple_schedule(wt_road, [ coord3d(4, 7, 0), coord3d(4, 2, 0) ]))
	// and start the convoy
	depot.start_all_convoys(pl)

	// make sure that the graph linking and all halts is updated
	while(!halt_x.is_rerouting_finished()) {
		sleep()
	}

	{
		ASSERT_EQUAL(world.generate_goods(coord(3, 7), coord(3, 2), good_desc_x.mail, 30), 1) // 1 == OK
	}

	sleep()
	sleep()

	{
		ASSERT_EQUAL(from_halt.waiting[0], 30)
		ASSERT_EQUAL(from_halt.get_freight_to_halt(good_desc_x.mail, to_halt), 30)
		ASSERT_EQUAL(from_halt.get_freight_to_dest(good_desc_x.mail, coord3d(3, 2, 0)), 30)
		ASSERT_EQUAL(from_halt.get_freight_to_dest(good_desc_x.mail, coord3d(4, 2, 0)), 0)
		ASSERT_EQUAL(from_halt.happy[0], 0)
		ASSERT_EQUAL(from_halt.unhappy[0], 0)
		ASSERT_EQUAL(from_halt.noroute[0], 0)
		ASSERT_EQUAL(from_halt.walked[0], 0)
		ASSERT_EQUAL(from_halt.departed[0], 0)
		ASSERT_EQUAL(from_halt.arrived[0], 0)
		ASSERT_EQUAL(from_halt.convoys[0], 0)
	}

	while (from_halt.convoys[0] == 0) {
		sleep()
	}

	// Loading is not instant, so we need to make sure loading has finished
	while (from_halt.waiting[0] > 0) {
		sleep()
	}

	{
		ASSERT_EQUAL(from_halt.convoys[0], 1)
		ASSERT_EQUAL(from_halt.waiting[0], 0)
		ASSERT_EQUAL(from_halt.get_freight_to_halt(good_desc_x.mail, to_halt), 0)
		ASSERT_EQUAL(from_halt.get_freight_to_dest(good_desc_x.mail, coord3d(3, 2, 0)), 0)
		ASSERT_EQUAL(from_halt.get_freight_to_dest(good_desc_x.mail, coord3d(4, 2, 0)), 0)
		ASSERT_EQUAL(from_halt.happy[0], 0)
		ASSERT_EQUAL(from_halt.unhappy[0], 0)
		ASSERT_EQUAL(from_halt.noroute[0], 0)
		ASSERT_EQUAL(from_halt.walked[0], 0)
		ASSERT_EQUAL(from_halt.departed[0], 30)
		ASSERT_EQUAL(from_halt.arrived[0], 0)
	}

	while (to_halt.convoys[0] == 0) {
		sleep()
	}

	// make sure unloading has finished
	while (to_halt.arrived[0] < 30) {
		sleep()
	}

	{
		ASSERT_EQUAL(to_halt.waiting[0], 0)
		ASSERT_EQUAL(to_halt.happy[0], 0)
		ASSERT_EQUAL(to_halt.unhappy[0], 0)
		ASSERT_EQUAL(to_halt.noroute[0], 0)
		ASSERT_EQUAL(to_halt.walked[0], 0)
		ASSERT_EQUAL(to_halt.departed[0], 0)
		ASSERT_EQUAL(to_halt.arrived[0], 30)
	}

	// clean up
	cnv.destroy(pl)
	sleep()
	sleep() // make sure the convoy is destroyed
	ASSERT_EQUAL(command_x(tool_remover).work(player_x(0), coord3d(4, 2, 0)), null)
	ASSERT_EQUAL(command_x(tool_remover).work(player_x(0), coord3d(4, 7, 0)), null)
	ASSERT_EQUAL(command_x(tool_remover).work(player_x(0), coord3d(4, 8, 0)), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(player_x(0), coord3d(4, 2, 0), coord3d(4, 8, 0), "" + wt_road), null)
	RESET_ALL_PLAYER_FUNDS()
}


function test_transport_freight_valid_route()
{
	local pl = player_x(0)

	ASSERT_EQUAL(command_x(tool_build_way).work(pl, coord3d(4, 2, 0), coord3d(4, 8, 0), "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_way).work(pl, coord3d(4, 7, 0), coord3d(5, 7, 0), "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, coord3d(4, 2, 0), "CarStop"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, coord3d(5, 7, 0), "CarStop"), null)
	ASSERT_EQUAL(command_x.build_depot(pl, coord3d(4, 8, 0), building_desc_x("CarDepot")), null)

	local depot = depot_x(4, 8, 0)
	local from_halt = halt_x.get_halt(coord3d(5, 7, 0), pl)
	local to_halt   = halt_x.get_halt(coord3d(4, 2, 0), pl)

	// create vehicle ...
	depot.append_vehicle(pl, convoy_x(0), vehicle_desc_x("Kohletransporter"))
	local cnv = depot.get_convoy_list()[0]
	// ... with simple 2-entry schedule ...
	cnv.change_schedule(pl, create_simple_schedule(wt_road, [ coord3d(5, 7, 0), coord3d(4, 2, 0) ]))
	// and start the convoy
	depot.start_all_convoys(pl)

	// make sure that the graph linking and all halts is updated
	while(!halt_x.is_rerouting_finished()) {
		sleep()
	}

	{
		ASSERT_EQUAL(world.generate_goods(coord(3, 7), coord(3, 2), good_desc_x("Kohle"), 18), 1) // 1 == OK
	}

	sleep()
	sleep()

	{
		ASSERT_EQUAL(from_halt.waiting[0], 18)
		ASSERT_EQUAL(from_halt.get_freight_to_halt(good_desc_x("Kohle"), to_halt), 18)
		ASSERT_EQUAL(from_halt.get_freight_to_dest(good_desc_x("Kohle"), coord3d(3, 2, 0)), 18)
		ASSERT_EQUAL(from_halt.get_freight_to_dest(good_desc_x("Kohle"), coord3d(4, 2, 0)), 0)
		ASSERT_EQUAL(from_halt.happy[0], 0)
		ASSERT_EQUAL(from_halt.unhappy[0], 0)
		ASSERT_EQUAL(from_halt.noroute[0], 0)
		ASSERT_EQUAL(from_halt.walked[0], 0)
		ASSERT_EQUAL(from_halt.departed[0], 0)
		ASSERT_EQUAL(from_halt.arrived[0], 0)
		ASSERT_EQUAL(from_halt.convoys[0], 0)
	}

	while (from_halt.convoys[0] == 0) {
		sleep()
	}

	// Loading is not instant, so we need to make sure loading has finished
	while (from_halt.waiting[0] > 0) {
		sleep()
	}

	{
		ASSERT_EQUAL(from_halt.convoys[0], 1)
		ASSERT_EQUAL(from_halt.waiting[0], 0)
		ASSERT_EQUAL(from_halt.get_freight_to_halt(good_desc_x("Kohle"), to_halt), 0)
		ASSERT_EQUAL(from_halt.get_freight_to_dest(good_desc_x("Kohle"), coord3d(3, 2, 0)), 0)
		ASSERT_EQUAL(from_halt.get_freight_to_dest(good_desc_x("Kohle"), coord3d(4, 2, 0)), 0)
		ASSERT_EQUAL(from_halt.happy[0], 0)
		ASSERT_EQUAL(from_halt.unhappy[0], 0)
		ASSERT_EQUAL(from_halt.noroute[0], 0)
		ASSERT_EQUAL(from_halt.walked[0], 0)
		ASSERT_EQUAL(from_halt.departed[0], 18)
		ASSERT_EQUAL(from_halt.arrived[0], 0)
	}

	while (to_halt.convoys[0] == 0) {
		sleep()
	}

	// make sure unloading has finished
	while (to_halt.arrived[0] < 18) {
		sleep()
	}

	{
		ASSERT_EQUAL(to_halt.waiting[0], 0)
		ASSERT_EQUAL(to_halt.happy[0], 0)
		ASSERT_EQUAL(to_halt.unhappy[0], 0)
		ASSERT_EQUAL(to_halt.noroute[0], 0)
		ASSERT_EQUAL(to_halt.walked[0], 0)
		ASSERT_EQUAL(to_halt.departed[0], 0)
		ASSERT_EQUAL(to_halt.arrived[0], 18)
	}

	// clean up
	cnv.destroy(pl)
	sleep()
	sleep() // make sure the convoy is destroyed
	ASSERT_EQUAL(command_x(tool_remover).work(player_x(0), coord3d(4, 2, 0)), null)
	ASSERT_EQUAL(command_x(tool_remover).work(player_x(0), coord3d(5, 7, 0)), null)
	ASSERT_EQUAL(command_x(tool_remover).work(player_x(0), coord3d(4, 8, 0)), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(player_x(0), coord3d(4, 2, 0), coord3d(4, 8, 0), "" + wt_road), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(player_x(0), coord3d(5, 7, 0), coord3d(4, 7, 0), "" + wt_road), null)
	RESET_ALL_PLAYER_FUNDS()
}
