//
// This file is part of the Simutrans project under the Artistic License.
// (see LICENSE.txt)
//


//
// Tests for the route overlay of the schedule editor.
//
// The sroute_* functions drive the real gui_schedule_t component and read the
// real display only route channel of the world (api_schedule_route_test.cc),
// so these tests exercise the production code path.
//
// Terminology used below:
//   route      the ordered tiles the world stores for the shown schedule
//   gap        a koord3d::invalid entry, marking a leg that has no route
//   owner      the id of the editor component the route currently belongs to
//   stop mark  the existing red highlight of the schedule stops
//
// These are the only tests that build a real gui_schedule_t, whose entries read
// skinverwaltung_t::gadget unchecked. The themes in simutrans/themes are loaded
// even by a headless build; a tree without them dies here without a verdict.
//


function sroute_make_road(pl, from, to)
{
	local road = way_desc_x.get_available_ways(wt_road, st_flat)[0]
	ASSERT_TRUE(road != null)
	ASSERT_EQUAL(command_x.build_way(pl, from, to, road, true), null)
}


function sroute_remove_way(pl, from, to, wt = wt_road)
{
	ASSERT_EQUAL(command_x(tool_remove_way).work(pl, from, to, "" + wt), null)
}


// create_line does not hand back the line it made, so find the new one by name
function sroute_new_line(pl, wt)
{
	local before = {}
	foreach (l in pl.get_line_list()) {
		before[l.get_name()] <- true
	}

	pl.create_line(wt)

	local found = null
	foreach (l in pl.get_line_list()) {
		if (!(l.get_name() in before)) {
			found = l
		}
	}
	ASSERT_TRUE(found != null)
	return found
}


function sroute_schedule(wt, positions)
{
	local entries = []
	foreach (pos in positions) {
		entries.append(schedule_entry_x(pos, 0, 0))
	}
	return schedule_x(wt, entries)
}


// Takes every way of @p wt off one row of the map, at any height, and checks that it is
// really gone. A bridge needs a wider sweep than its own span: bridge_builder_t::build()
// extends the way one tile past a head that would otherwise be a dead end (see the
// "if start or end are single way" block at the end of brueckenbauer.cc), so two tiles
// nobody asked for are left behind, and RESET_ALL_PLAYER_FUNDS() then trips over them.
function SROUTE_CLEAR_ROW(pl, y, x0, x1, wt)
{
	command_x(tool_remove_way).work(pl, coord3d(x0, y, 0), coord3d(x1, y, 0), "" + wt)
	for (local x = x0; x <= x1; ++x) {
		for (local z = 0; z <= 2; ++z) {
			local tile = square_x(x, y).get_tile_at_height(z)
			if (tile != null  &&  tile.has_way(wt)) {
				command_x(tool_remover).work(pl, coord3d(x, y, z))
			}
		}
	}
	for (local x = x0; x <= x1; ++x) {
		for (local z = 0; z <= 2; ++z) {
			local tile = square_x(x, y).get_tile_at_height(z)
			ASSERT_TRUE(tile == null  ||  !tile.has_way(wt))
		}
	}
}


// every route tile must carry a way of that type: the geometry follows the
// infrastructure and is not a straight line between the stops
function ASSERT_ROUTE_ON_WAY(wt)
{
	for (local i = 0; i < sroute_len(); ++i) {
		local pos = sroute_tile(i)
		if (pos == null) {
			continue // gap
		}
		local tile = square_x(pos.x, pos.y).get_tile_at_height(pos.z)
		ASSERT_TRUE(tile != null)
		ASSERT_TRUE(tile.has_way(wt))
	}
}


//
// 1 + 2 + 15: opening shows stops and route, closing removes both,
//             and the geometry follows the way around a corner
//
function test_schedule_route_open_and_close()
{
	local pl = player_x(0)
	sroute_make_road(pl, coord3d(2, 2, 0), coord3d(2, 8, 0))
	sroute_make_road(pl, coord3d(2, 8, 0), coord3d(8, 8, 0))

	local sched = sroute_schedule(wt_road, [coord3d(2, 2, 0), coord3d(8, 8, 0)])

	sroute_open(0, sched, 0)
	sroute_mark(0, true)

	// nothing is installed before a safe step: the calculation never runs from the GUI
	ASSERT_EQUAL(sroute_len(), 0)
	ASSERT_TRUE(sroute_owner() != 0)

	sroute_step()

	ASSERT_TRUE(sroute_len() > 0)
	ASSERT_EQUAL(sroute_gaps(), 0)
	ASSERT_EQUAL(sroute_player(), 0)
	ASSERT_ROUTE_ON_WAY(wt_road)

	// the real path, not a straight line: both legs of the L are on it
	ASSERT_TRUE(sroute_has(coord3d(2, 5, 0)))
	ASSERT_TRUE(sroute_has(coord3d(2, 8, 0)))
	ASSERT_TRUE(sroute_has(coord3d(5, 8, 0)))

	// two independent channels: a tile can be on the route without being a stop
	ASSERT_TRUE(sroute_stop_marked(coord3d(2, 2, 0)))
	ASSERT_TRUE(sroute_stop_marked(coord3d(8, 8, 0)))
	ASSERT_FALSE(sroute_stop_marked(coord3d(2, 5, 0)))

	// closing the editor drops both
	sroute_close(0)
	ASSERT_EQUAL(sroute_len(), 0)
	ASSERT_EQUAL(sroute_owner(), 0)
	ASSERT_FALSE(sroute_stop_marked(coord3d(2, 2, 0)))

	sroute_remove_way(pl, coord3d(2, 2, 0), coord3d(2, 8, 0))
	sroute_remove_way(pl, coord3d(2, 8, 0), coord3d(8, 8, 0))
	ASSERT_FALSE(tile_x(5, 8, 0).has_way(wt_road))
	RESET_ALL_PLAYER_FUNDS()
}


//
// 3: changing the schedule invalidates the old route and produces a new one
//
function test_schedule_route_update_on_change()
{
	local pl = player_x(0)
	sroute_make_road(pl, coord3d(2, 2, 0), coord3d(2, 12, 0))

	local sched = sroute_schedule(wt_road, [coord3d(2, 2, 0), coord3d(2, 6, 0)])
	sroute_open(0, sched, 0)
	sroute_mark(0, true)
	sroute_step()

	local short_len = sroute_len()
	ASSERT_TRUE(short_len > 0)
	ASSERT_FALSE(sroute_has(coord3d(2, 10, 0)))

	// the schedule gained a stop; the editor is re-initialised with it, as
	// line_management_gui does when the schedule of the shown line changed
	local longer = sroute_schedule(wt_road, [coord3d(2, 2, 0), coord3d(2, 12, 0)])
	sroute_reinit(0, longer)
	sroute_mark(0, true)

	// the old route is dropped at once, the new one only after a safe step
	ASSERT_EQUAL(sroute_len(), 0)
	sroute_step()

	ASSERT_TRUE(sroute_len() > short_len)
	ASSERT_TRUE(sroute_has(coord3d(2, 10, 0)))
	ASSERT_ROUTE_ON_WAY(wt_road)

	sroute_close(0)
	sroute_remove_way(pl, coord3d(2, 2, 0), coord3d(2, 12, 0))
	RESET_ALL_PLAYER_FUNDS()
}


//
// 4: a second editor replaces the first one, and closing the first
//    does not remove the route of the second
//
function test_schedule_route_second_editor()
{
	local pl = player_x(0)
	sroute_make_road(pl, coord3d(2, 2, 0), coord3d(2, 12, 0))

	local short_sched = sroute_schedule(wt_road, [coord3d(2, 2, 0), coord3d(2, 4, 0)])
	local long_sched  = sroute_schedule(wt_road, [coord3d(2, 2, 0), coord3d(2, 12, 0)])

	sroute_open(0, short_sched, 0)
	sroute_mark(0, true)
	sroute_step()
	local first_owner = sroute_owner()
	local first_len = sroute_len()
	ASSERT_TRUE(first_len > 0)

	sroute_open(1, long_sched, 0)
	sroute_mark(1, true)
	sroute_step()
	local second_owner = sroute_owner()

	ASSERT_TRUE(second_owner != first_owner)
	ASSERT_TRUE(sroute_len() > first_len)
	ASSERT_TRUE(sroute_has(coord3d(2, 10, 0)))

	// closing the older window must not touch the newer route
	sroute_close(0)
	ASSERT_EQUAL(sroute_owner(), second_owner)
	ASSERT_TRUE(sroute_has(coord3d(2, 10, 0)))

	sroute_close(1)
	ASSERT_EQUAL(sroute_len(), 0)
	ASSERT_EQUAL(sroute_owner(), 0)

	sroute_remove_way(pl, coord3d(2, 2, 0), coord3d(2, 12, 0))
	RESET_ALL_PLAYER_FUNDS()
}


//
// 5: an outdated request may never overwrite a newer visualization
//
function test_schedule_route_outdated_request()
{
	local pl = player_x(0)
	sroute_make_road(pl, coord3d(2, 2, 0), coord3d(2, 12, 0))

	local a = sroute_schedule(wt_road, [coord3d(2, 2, 0), coord3d(2, 4, 0)])
	local b = sroute_schedule(wt_road, [coord3d(2, 2, 0), coord3d(2, 12, 0)])

	// a request that is never stepped, then the window closes
	sroute_open(0, a, 0)
	sroute_mark(0, true)
	sroute_close(0)
	sroute_step()
	ASSERT_EQUAL(sroute_len(), 0)
	ASSERT_EQUAL(sroute_owner(), 0)

	// an older window closes while a newer request is still pending
	sroute_open(0, a, 0)
	sroute_mark(0, true)
	sroute_open(1, b, 0)
	sroute_mark(1, true)
	local newer = sroute_owner()
	sroute_close(0)
	sroute_step()

	ASSERT_EQUAL(sroute_owner(), newer)
	ASSERT_TRUE(sroute_has(coord3d(2, 10, 0)))

	sroute_close(1)
	sroute_remove_way(pl, coord3d(2, 2, 0), coord3d(2, 12, 0))
	RESET_ALL_PLAYER_FUNDS()
}


//
// 14: a leg without a route leaves a gap and never draws a false connection
//
function test_schedule_route_broken_leg()
{
	local pl = player_x(0)
	sroute_make_road(pl, coord3d(2, 2, 0), coord3d(2, 5, 0))
	sroute_make_road(pl, coord3d(9, 2, 0), coord3d(9, 5, 0))

	// nothing at all can be routed: no geometry, and above all no false line
	local no_leg = sroute_schedule(wt_road, [coord3d(2, 2, 0), coord3d(9, 2, 0)])
	sroute_open(0, no_leg, 0)
	sroute_mark(0, true)
	sroute_step()
	ASSERT_EQUAL(sroute_len(), 0)
	ASSERT_FALSE(sroute_has(coord3d(5, 2, 0)))

	// but the stops are still marked: the two channels are independent
	ASSERT_TRUE(sroute_stop_marked(coord3d(2, 2, 0)))
	ASSERT_TRUE(sroute_stop_marked(coord3d(9, 2, 0)))
	sroute_close(0)

	// one leg routes and the next one does not: the good leg is kept and the
	// broken one becomes an explicit gap the display never draws across
	local one_leg = sroute_schedule(wt_road, [coord3d(2, 2, 0), coord3d(2, 5, 0), coord3d(9, 2, 0)])
	sroute_open(0, one_leg, 0)
	sroute_mark(0, true)
	sroute_step()

	ASSERT_EQUAL(sroute_gaps(), 1)
	ASSERT_TRUE(sroute_has(coord3d(2, 3, 0)))
	ASSERT_FALSE(sroute_has(coord3d(5, 2, 0)))
	ASSERT_EQUAL(sroute_tile(sroute_len() - 1), null) // the gap closes the list
	ASSERT_ROUTE_ON_WAY(wt_road)

	sroute_close(0)
	sroute_remove_way(pl, coord3d(2, 2, 0), coord3d(2, 5, 0))
	sroute_remove_way(pl, coord3d(9, 2, 0), coord3d(9, 5, 0))
	RESET_ALL_PLAYER_FUNDS()
}


//
// 11: rail
//
function test_schedule_route_rail()
{
	local pl = player_x(0)
	local rail = way_desc_x.get_available_ways(wt_rail, st_flat)[0]
	ASSERT_TRUE(rail != null)
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(3, 3, 0), coord3d(3, 11, 0), rail, true), null)

	local sched = sroute_schedule(wt_rail, [coord3d(3, 3, 0), coord3d(3, 11, 0)])
	sroute_open(0, sched, 0)
	sroute_mark(0, true)
	sroute_step()

	ASSERT_TRUE(sroute_len() > 0)
	ASSERT_EQUAL(sroute_gaps(), 0)
	ASSERT_TRUE(sroute_has(coord3d(3, 7, 0)))
	ASSERT_ROUTE_ON_WAY(wt_rail)

	sroute_close(0)
	sroute_remove_way(pl, coord3d(3, 3, 0), coord3d(3, 11, 0), wt_rail)
	RESET_ALL_PLAYER_FUNDS()
}


//
// 12: monorail. pak64 offers no maglev way at the start date of the test map,
//     so maglev cannot be covered here; it shares this code path.
//
function test_schedule_route_monorail()
{
	local pl = player_x(0)

	foreach (wt in [wt_monorail]) {
		local ways = way_desc_x.get_available_ways(wt, st_flat)
		ASSERT_TRUE(ways.len() > 0)
		local way = ways[0]

		ASSERT_EQUAL(command_x.build_way(pl, coord3d(6, 3, 0), coord3d(6, 9, 0), way, true), null)

		local sched = sroute_schedule(wt, [coord3d(6, 3, 0), coord3d(6, 9, 0)])
		sroute_open(0, sched, 0)
		sroute_mark(0, true)
		sroute_step()

		ASSERT_TRUE(sroute_len() > 0)
		ASSERT_EQUAL(sroute_gaps(), 0)
		ASSERT_TRUE(sroute_has(coord3d(6, 6, 0)))
		ASSERT_ROUTE_ON_WAY(wt)

		sroute_close(0)
		sroute_remove_way(pl, coord3d(6, 3, 0), coord3d(6, 9, 0), wt)
	}
	RESET_ALL_PLAYER_FUNDS()
}


//
// 13: ships
//
function test_schedule_route_water()
{
	local pl = player_x(0)
	local climate = command_x(tool_set_climate)

	ASSERT_EQUAL(climate.work(pl, coord3d(10, 2, 0), coord3d(12, 10, 0), "" + cl_water), null)

	local sched = sroute_schedule(wt_water, [coord3d(10, 2, 0), coord3d(12, 10, 0)])
	sroute_open(0, sched, 0)
	sroute_mark(0, true)
	sroute_step()

	ASSERT_TRUE(sroute_len() > 0)
	ASSERT_EQUAL(sroute_gaps(), 0)

	sroute_close(0)
	ASSERT_EQUAL(climate.work(pl, coord3d(10, 2, 0), coord3d(12, 10, 0), "" + cl_mediterran), null)
	RESET_ALL_PLAYER_FUNDS()
}


//
// 8: a line without convois still gets a real route, using a generic vehicle
//
function test_schedule_route_line_without_convoys()
{
	local pl = player_x(0)
	sroute_make_road(pl, coord3d(2, 2, 0), coord3d(2, 10, 0))

	local line = sroute_new_line(pl, wt_road)
	ASSERT_EQUAL(line.get_convoy_list().get_count(), 0)

	local sched = sroute_schedule(wt_road, [coord3d(2, 2, 0), coord3d(2, 10, 0)])
	ASSERT_TRUE(line.change_schedule(pl, sched))

	sroute_open_line(0, line)
	sroute_mark(0, true)
	sroute_step()

	ASSERT_TRUE(sroute_len() > 0)
	ASSERT_EQUAL(sroute_gaps(), 0)
	ASSERT_EQUAL(sroute_player(), 0)
	ASSERT_TRUE(sroute_has(coord3d(2, 6, 0)))
	ASSERT_ROUTE_ON_WAY(wt_road)

	sroute_close(0)
	line.destroy(pl)
	sroute_remove_way(pl, coord3d(2, 2, 0), coord3d(2, 10, 0))
	RESET_ALL_PLAYER_FUNDS()
}


//
// 6 + 7: a real convoi, and a line that has one. The calculation must not
//        touch the convoi.
//
function test_schedule_route_convoy_and_line()
{
	local pl = player_x(0)
	sroute_make_road(pl, coord3d(2, 2, 0), coord3d(2, 10, 0))
	ASSERT_EQUAL(command_x.build_depot(pl, coord3d(2, 2, 0), get_depot_by_wt(wt_road)), null)

	local the_depot = depot_x.get_depot_list(pl, wt_road)[0]
	local vehicle = vehicle_desc_x.get_available_vehicles(wt_road)[0]
	ASSERT_TRUE(vehicle != null)
	ASSERT_TRUE(the_depot.append_vehicle(pl, convoy_x(0), vehicle))
	local cnv = the_depot.get_convoy_list()[0]

	local sched = sroute_schedule(wt_road, [coord3d(2, 4, 0), coord3d(2, 10, 0)])
	ASSERT_TRUE(cnv.change_schedule(pl, sched))

	// 6: the convoi is not modified by the calculation
	local before = sroute_convoy_fingerprint(cnv)
	sroute_open_convoy(0, cnv)
	sroute_mark(0, true)
	sroute_step()

	ASSERT_TRUE(sroute_len() > 0)
	ASSERT_EQUAL(sroute_gaps(), 0)
	ASSERT_EQUAL(sroute_player(), 0)
	ASSERT_ROUTE_ON_WAY(wt_road)
	ASSERT_EQUAL(sroute_convoy_fingerprint(cnv), before)
	sroute_close(0)

	// 7: the same schedule through a line that has this convoi
	local line = sroute_new_line(pl, wt_road)
	ASSERT_TRUE(line.change_schedule(pl, sched))
	ASSERT_TRUE(cnv.set_line(pl, line))
	ASSERT_EQUAL(line.get_convoy_list().get_count(), 1)

	sroute_open_line(0, line)
	sroute_mark(0, true)
	sroute_step()

	ASSERT_TRUE(sroute_len() > 0)
	ASSERT_EQUAL(sroute_gaps(), 0)
	ASSERT_ROUTE_ON_WAY(wt_road)
	ASSERT_EQUAL(sroute_convoy_fingerprint(cnv), before)

	sroute_close(0)
	ASSERT_TRUE(cnv.destroy(pl))
	line.destroy(pl)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, coord3d(2, 2, 0)), null)
	sroute_remove_way(pl, coord3d(2, 2, 0), coord3d(2, 10, 0))
	RESET_ALL_PLAYER_FUNDS()
}


//
// 9: the owner decides the route - a private way blocks another player
//
function test_schedule_route_private_way()
{
	local pl = player_x(0)
	local public_pl = player_x(1)
	local sign = sign_desc_x.get_available_signs(wt_road).filter(@(idx, sign) sign.is_private_way())[0]
	ASSERT_TRUE(sign != null)

	sroute_make_road(public_pl, coord3d(2, 2, 0), coord3d(2, 10, 0))
	ASSERT_EQUAL(command_x.build_sign_at(pl, coord3d(2, 6, 0), sign), null)

	local sched = sroute_schedule(wt_road, [coord3d(2, 2, 0), coord3d(2, 10, 0)])

	// the owner of the private way gets through
	sroute_open(0, sched, 0)
	sroute_mark(0, true)
	sroute_step()
	ASSERT_TRUE(sroute_has(coord3d(2, 6, 0)))
	ASSERT_EQUAL(sroute_gaps(), 0)
	sroute_close(0)

	// another player does not
	sroute_open(0, sched, 1)
	sroute_mark(0, true)
	sroute_step()
	ASSERT_EQUAL(sroute_player(), 1)
	ASSERT_FALSE(sroute_has(coord3d(2, 6, 0)))
	ASSERT_EQUAL(sroute_len(), 0) // the only way through is closed for them
	sroute_close(0)

	ASSERT_EQUAL(command_x(tool_remover).work(pl, coord3d(2, 6, 0)), null)
	sroute_remove_way(public_pl, coord3d(2, 2, 0), coord3d(2, 10, 0))
	RESET_ALL_PLAYER_FUNDS()
}


//
// 16: rotating the map must not leave residual geometry
//
function test_schedule_route_rotate()
{
	local pl = player_x(0)
	sroute_make_road(pl, coord3d(2, 2, 0), coord3d(2, 10, 0))

	local sched = sroute_schedule(wt_road, [coord3d(2, 2, 0), coord3d(2, 10, 0)])
	sroute_open(0, sched, 0)
	sroute_mark(0, true)
	sroute_step()
	ASSERT_TRUE(sroute_len() > 0)

	sroute_rotate()
	ASSERT_EQUAL(sroute_len(), 0)
	ASSERT_EQUAL(sroute_owner(), 0)

	// back to the original orientation, so the rest of the suite is unaffected
	sroute_rotate()
	sroute_rotate()
	sroute_rotate()
	ASSERT_EQUAL(sroute_len(), 0)

	sroute_close(0)
	sroute_remove_way(pl, coord3d(2, 2, 0), coord3d(2, 10, 0))
	RESET_ALL_PLAYER_FUNDS()
}


//
// Catenary cases below share one map: a direct corridor at x=4 between (4,3) and
// (4,11), and a longer way round through x=8. Only the way round carries overhead
// line, junctions included, so the two corridors differ in exactly one property.
// The depot hangs off a spur at (2,3) and is never on any of the routes.
//
function sroute_build_catenary_loop(pl)
{
	local rail = way_desc_x.get_available_ways(wt_rail, st_flat)[0]
	ASSERT_TRUE(rail != null)
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(4, 3, 0), coord3d(4, 11, 0), rail, true), null)
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(4, 3, 0), coord3d(8, 3, 0), rail, true), null)
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(8, 3, 0), coord3d(8, 11, 0), rail, true), null)
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(8, 11, 0), coord3d(4, 11, 0), rail, true), null)
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(2, 3, 0), coord3d(4, 3, 0), rail, true), null)

	local ohl = wayobj_desc_x.get_available_wayobjs(wt_rail).filter(@(idx, w) w.is_overhead_line())[0]
	ASSERT_TRUE(ohl != null)
	ASSERT_EQUAL(command_x.build_wayobj(pl, coord3d(4, 3, 0), coord3d(8, 3, 0), ohl), null)
	ASSERT_EQUAL(command_x.build_wayobj(pl, coord3d(8, 3, 0), coord3d(8, 11, 0), ohl), null)
	ASSERT_EQUAL(command_x.build_wayobj(pl, coord3d(8, 11, 0), coord3d(4, 11, 0), ohl), null)

	// the point of the whole layout: the short way is the one without catenary
	ASSERT_TRUE(tile_x(8, 7, 0).find_object(mo_wayobj) != null)
	ASSERT_EQUAL(tile_x(4, 7, 0).find_object(mo_wayobj), null)

	ASSERT_EQUAL(command_x.build_depot(pl, coord3d(2, 3, 0), get_depot_by_wt(wt_rail)), null)
	return depot_x.get_depot_list(pl, wt_rail)[0]
}


function sroute_clear_catenary_loop(pl)
{
	local wrem = command_x(tool_remove_wayobj)
	ASSERT_EQUAL(wrem.work(pl, coord3d(4, 3, 0), coord3d(8, 3, 0), "" + wt_rail), null)
	ASSERT_EQUAL(wrem.work(pl, coord3d(8, 3, 0), coord3d(8, 11, 0), "" + wt_rail), null)
	ASSERT_EQUAL(wrem.work(pl, coord3d(8, 11, 0), coord3d(4, 11, 0), "" + wt_rail), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, coord3d(2, 3, 0)), null)
	sroute_remove_way(pl, coord3d(4, 3, 0), coord3d(4, 11, 0), wt_rail)
	sroute_remove_way(pl, coord3d(4, 3, 0), coord3d(8, 3, 0), wt_rail)
	sroute_remove_way(pl, coord3d(8, 3, 0), coord3d(8, 11, 0), wt_rail)
	sroute_remove_way(pl, coord3d(8, 11, 0), coord3d(4, 11, 0), wt_rail)
	sroute_remove_way(pl, coord3d(2, 3, 0), coord3d(4, 3, 0), wt_rail)
	RESET_ALL_PLAYER_FUNDS()
}


// stop at the first match instead of filtering the whole list: the pakset has 148 rail
// vehicles and filter() spends an opcode budget on all of them to hand back a list whose
// first entry is the only one used. The scripts run on a shared budget of 10000 opcodes,
// so a scan that costs 727 where 18 will do is what makes these tests fail as soon as
// anything is added ahead of them.
function sroute_electric_loco()
{
	foreach (v in vehicle_desc_x.get_available_vehicles(wt_rail)) {
		if (v.needs_electrification()  &&  v.can_be_first()) {
			return v
		}
	}
	ASSERT_TRUE(false)
}


function sroute_diesel_loco()
{
	foreach (v in vehicle_desc_x.get_available_vehicles(wt_rail)) {
		if (!v.needs_electrification()  &&  v.can_be_first()  &&  v.get_power() > 0) {
			return v
		}
	}
	ASSERT_TRUE(false)
}


//
// 18: an electric convoi is shown the route it could actually take, so it goes
//     the long way round rather than over the unelectrified short one
//
function test_schedule_route_electric_follows_catenary()
{
	local pl = player_x(0)
	local the_depot = sroute_build_catenary_loop(pl)

	ASSERT_TRUE(the_depot.append_vehicle(pl, convoy_x(0), sroute_electric_loco()))
	local cnv = the_depot.get_convoy_list()[0]
	ASSERT_TRUE(cnv.needs_electrification())

	local sched = sroute_schedule(wt_rail, [coord3d(4, 3, 0), coord3d(4, 11, 0)])
	ASSERT_TRUE(cnv.change_schedule(pl, sched))

	sroute_open_convoy(0, cnv)
	sroute_mark(0, true)
	sroute_step()

	ASSERT_TRUE(sroute_len() > 0)
	ASSERT_EQUAL(sroute_gaps(), 0)
	ASSERT_TRUE(sroute_has(coord3d(8, 7, 0)))
	ASSERT_FALSE(sroute_has(coord3d(4, 7, 0)))
	ASSERT_ROUTE_ON_WAY(wt_rail)

	sroute_close(0)
	ASSERT_TRUE(cnv.destroy(pl))
	sroute_clear_catenary_loop(pl)
}


//
// 19: the restriction comes from the convoi, not from the way: on the same map a
//     convoi that does not need catenary takes the short corridor
//
function test_schedule_route_diesel_ignores_catenary()
{
	local pl = player_x(0)
	local the_depot = sroute_build_catenary_loop(pl)

	ASSERT_TRUE(the_depot.append_vehicle(pl, convoy_x(0), sroute_diesel_loco()))
	local cnv = the_depot.get_convoy_list()[0]
	ASSERT_FALSE(cnv.needs_electrification())

	local sched = sroute_schedule(wt_rail, [coord3d(4, 3, 0), coord3d(4, 11, 0)])
	ASSERT_TRUE(cnv.change_schedule(pl, sched))

	sroute_open_convoy(0, cnv)
	sroute_mark(0, true)
	sroute_step()

	ASSERT_TRUE(sroute_len() > 0)
	ASSERT_EQUAL(sroute_gaps(), 0)
	ASSERT_TRUE(sroute_has(coord3d(4, 7, 0)))
	ASSERT_FALSE(sroute_has(coord3d(8, 7, 0)))
	ASSERT_ROUTE_ON_WAY(wt_rail)

	sroute_close(0)
	ASSERT_TRUE(cnv.destroy(pl))
	sroute_clear_catenary_loop(pl)
}


//
// 20: with the catenary gone there is no route at all for an electric convoi, and
//     an empty overlay is not the same as no overlay - the editor still owns it
//
function test_schedule_route_electric_without_catenary()
{
	local pl = player_x(0)
	local rail = way_desc_x.get_available_ways(wt_rail, st_flat)[0]
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(3, 3, 0), coord3d(3, 11, 0), rail, true), null)
	ASSERT_EQUAL(command_x.build_depot(pl, coord3d(3, 3, 0), get_depot_by_wt(wt_rail)), null)
	local the_depot = depot_x.get_depot_list(pl, wt_rail)[0]

	local sched = sroute_schedule(wt_rail, [coord3d(3, 5, 0), coord3d(3, 11, 0)])

	ASSERT_TRUE(the_depot.append_vehicle(pl, convoy_x(0), sroute_electric_loco()))
	local cnv = the_depot.get_convoy_list()[0]
	ASSERT_TRUE(cnv.change_schedule(pl, sched))
	sroute_open_convoy(0, cnv)
	sroute_mark(0, true)
	sroute_step()

	ASSERT_EQUAL(sroute_len(), 0)
	ASSERT_TRUE(sroute_owner() != 0)
	sroute_close(0)
	ASSERT_TRUE(cnv.destroy(pl))

	// the control: the very same schedule over the very same track does have a
	// route, so the empty one above is the electrification and nothing else
	ASSERT_TRUE(the_depot.append_vehicle(pl, convoy_x(0), sroute_diesel_loco()))
	local cnv2 = the_depot.get_convoy_list()[0]
	ASSERT_TRUE(cnv2.change_schedule(pl, sched))
	sroute_open_convoy(0, cnv2)
	sroute_mark(0, true)
	sroute_step()

	ASSERT_TRUE(sroute_len() > 0)
	ASSERT_EQUAL(sroute_gaps(), 0)
	sroute_close(0)
	ASSERT_TRUE(cnv2.destroy(pl))

	ASSERT_EQUAL(command_x(tool_remover).work(pl, coord3d(3, 3, 0)), null)
	sroute_remove_way(pl, coord3d(3, 3, 0), coord3d(3, 11, 0), wt_rail)
	RESET_ALL_PLAYER_FUNDS()
}


//
// 21: the restriction survives a schedule change - the editor is re-initialised
//     with the same convoi, so the new route avoids the same tiles as the old one
//
function test_schedule_route_electric_survives_schedule_change()
{
	local pl = player_x(0)
	local the_depot = sroute_build_catenary_loop(pl)

	ASSERT_TRUE(the_depot.append_vehicle(pl, convoy_x(0), sroute_electric_loco()))
	local cnv = the_depot.get_convoy_list()[0]

	local sched = sroute_schedule(wt_rail, [coord3d(4, 3, 0), coord3d(4, 11, 0)])
	ASSERT_TRUE(cnv.change_schedule(pl, sched))
	sroute_open_convoy(0, cnv)
	sroute_mark(0, true)
	sroute_step()
	ASSERT_TRUE(sroute_len() > 0)
	ASSERT_FALSE(sroute_has(coord3d(4, 7, 0)))

	// a stop is added in the middle of the electrified side
	local longer = sroute_schedule(wt_rail, [coord3d(4, 3, 0), coord3d(8, 7, 0), coord3d(4, 11, 0)])
	sroute_reinit(0, longer)
	sroute_mark(0, true)
	ASSERT_EQUAL(sroute_len(), 0)
	sroute_step()

	ASSERT_TRUE(sroute_len() > 0)
	ASSERT_EQUAL(sroute_gaps(), 0)
	ASSERT_TRUE(sroute_has(coord3d(8, 7, 0)))
	ASSERT_FALSE(sroute_has(coord3d(4, 7, 0)))
	ASSERT_ROUTE_ON_WAY(wt_rail)

	sroute_close(0)
	ASSERT_TRUE(cnv.destroy(pl))
	sroute_clear_catenary_loop(pl)
}


// a diagonal way, built one step at a time so that the shape is the test and not
// whatever the way builder would have picked; returns the tile it ends on
function sroute_make_staircase(pl, x0, y0, steps, build)
{
	local x = x0
	local y = y0
	for (local i = 0; i < steps; ++i) {
		local nx = (i % 2 == 0) ? x + 1 : x
		local ny = (i % 2 == 0) ? y : y + 1
		if (build) {
			sroute_make_road(pl, coord3d(x, y, 0), coord3d(nx, ny, 0))
		}
		else {
			sroute_remove_way(pl, coord3d(x, y, 0), coord3d(nx, ny, 0))
		}
		x = nx
		y = ny
	}
	return coord3d(x, y, 0)
}


//
// 22: a diagonal way is a staircase of orthogonal steps, never a diagonal move, and
//     the route over it is exactly that staircase. The display leans on this: it draws
//     such a run as one straight line, because joining the tile centres would zigzag
//     precisely where the way graphics are straight.
//
function test_schedule_route_diagonal_staircase()
{
	local pl = player_x(0)
	local last = sroute_make_staircase(pl, 2, 2, 20, true)
	ASSERT_EQUAL(last.x, 12)
	ASSERT_EQUAL(last.y, 12)

	local sched = sroute_schedule(wt_road, [coord3d(2, 2, 0), last])
	sroute_open(0, sched, 0)
	sroute_mark(0, true)
	sroute_step()

	// there and back again, sharing the two stops: 21 tiles plus the 20 of the return
	ASSERT_EQUAL(sroute_len(), 41)
	ASSERT_EQUAL(sroute_gaps(), 0)
	ASSERT_ROUTE_ON_WAY(wt_road)

	// one tile per step along one axis, and never twice the same way in a row
	local prev_dx = 0
	local prev_dy = 0
	for (local i = 1; i < sroute_len(); ++i) {
		local a = sroute_tile(i - 1)
		local b = sroute_tile(i)
		local dx = b.x - a.x
		local dy = b.y - a.y
		ASSERT_EQUAL((dx < 0 ? -dx : dx) + (dy < 0 ? -dy : dy), 1)
		if (i > 1) {
			ASSERT_FALSE(dx == prev_dx && dy == prev_dy)
		}
		prev_dx = dx
		prev_dy = dy
	}

	sroute_close(0)
	sroute_make_staircase(pl, 2, 2, 20, false)
	ASSERT_FALSE(tile_x(3, 3, 0).has_way(wt_road))
	RESET_ALL_PLAYER_FUNDS()
}


//
// 23-26: the overlay is drawn on the surface of the way, not on the base height of the
//        ground the route stores. sroute_way_height2() reports the height the display
//        lifts one corner of the route to, in half height levels; a tile whose way is
//        flat must report exactly twice its own z, and a tile whose way is higher - a
//        slope, or the head of a bridge - must report how much higher.
//
//        The expected values were measured against the height code a vehicle driving on
//        that way uses (vehicle_base_t::calc_height), not chosen to match the display.
//

// every corner of the route sits on the base height of its own ground
function ASSERT_OVERLAY_FLAT()
{
	for (local i = 0; i < sroute_len(); ++i) {
		local pos = sroute_tile(i)
		if (pos == null) {
			continue
		}
		ASSERT_EQUAL(sroute_way_height2(i, false), 2 * pos.z)
		local next = i+1 < sroute_len() ? sroute_tile(i+1) : null
		if (next != null) {
			ASSERT_EQUAL(sroute_way_height2(i, true), 2 * pos.z)
		}
	}
}


// half height levels the way at the centre of the tile at @p pos is above its ground
function OVERLAY_RISE_AT(pos)
{
	for (local i = 0; i < sroute_len(); ++i) {
		local p = sroute_tile(i)
		if (p != null && p.x == pos.x && p.y == pos.y && p.z == pos.z) {
			return sroute_way_height2(i, false) - 2 * p.z
		}
	}
	throw "tile " + pos.tostring() + " is not on the route"
}


//
// 23: flat ground and a flat diagonal are untouched: the overlay stays on the ground,
//     because on flat ground the way is the ground
//
function test_schedule_route_height_flat()
{
	local pl = player_x(0)
	sroute_make_road(pl, coord3d(2, 2, 0), coord3d(2, 8, 0))
	sroute_make_road(pl, coord3d(2, 8, 0), coord3d(8, 8, 0))

	local sched = sroute_schedule(wt_road, [coord3d(2, 2, 0), coord3d(8, 8, 0)])
	sroute_open(0, sched, 0)
	sroute_mark(0, true)
	sroute_step()
	ASSERT_TRUE(sroute_len() > 0)
	ASSERT_OVERLAY_FLAT()
	sroute_close(0)

	// and the same over a diagonal, where the corners are edge midpoints and not centres
	local last = sroute_make_staircase(pl, 3, 2, 8, true)
	local diag = sroute_schedule(wt_road, [coord3d(3, 2, 0), last])
	sroute_open(0, diag, 0)
	sroute_mark(0, true)
	sroute_step()
	ASSERT_TRUE(sroute_len() > 0)
	ASSERT_OVERLAY_FLAT()
	sroute_close(0)

	sroute_make_staircase(pl, 3, 2, 8, false)
	sroute_remove_way(pl, coord3d(2, 2, 0), coord3d(2, 8, 0))
	sroute_remove_way(pl, coord3d(2, 8, 0), coord3d(8, 8, 0))
	RESET_ALL_PLAYER_FUNDS()
}


//
// 24: a way that climbs a slope. The middle of the ramp is half a height level above its
//     ground, its low edge is on it and its high edge a whole level above it.
//
function test_schedule_route_height_slope()
{
	local pl = player_x(0)
	local rail = way_desc_x.get_available_ways(wt_rail, st_flat)[0]
	local setslope = command_x.set_slope

	// a plateau one level up, and the tile before it as the ramp onto it
	ASSERT_EQUAL(setslope(pl, coord3d(4, 10, 0), slope.all_up_slope), null)
	ASSERT_EQUAL(setslope(pl, coord3d(5, 10, 0), slope.all_up_slope), null)
	ASSERT_EQUAL(setslope(pl, coord3d(3, 10, 0), slope.west), null)
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(1, 10, 0), coord3d(5, 10, 1), rail, true), null)

	local sched = sroute_schedule(wt_rail, [coord3d(1, 10, 0), coord3d(5, 10, 1)])
	sroute_open(0, sched, 0)
	sroute_mark(0, true)
	sroute_step()
	ASSERT_TRUE(sroute_len() > 0)

	// the flat ground before and the plateau after are on their own ground
	ASSERT_EQUAL(OVERLAY_RISE_AT(coord3d(2, 10, 0)), 0)
	ASSERT_EQUAL(OVERLAY_RISE_AT(coord3d(4, 10, 1)), 0)
	// the ramp is half a level up in the middle of the tile
	ASSERT_EQUAL(OVERLAY_RISE_AT(coord3d(3, 10, 0)), 1)

	// and its two edges, low and high
	for (local i = 0; i < sroute_len(); ++i) {
		local p = sroute_tile(i)
		local n = i+1 < sroute_len() ? sroute_tile(i+1) : null
		if (p != null && n != null && p.x == 2 && p.y == 10) {
			ASSERT_EQUAL(sroute_way_height2(i, true), 2 * p.z)       // low edge of the ramp
		}
		if (p != null && n != null && p.x == 3 && p.y == 10 && n.x == 4) {
			ASSERT_EQUAL(sroute_way_height2(i, true), 2 * p.z + 2)   // high edge of the ramp
		}
	}

	sroute_close(0)
	SROUTE_CLEAR_ROW(pl, 10, 1, 5, wt_rail)
	ASSERT_EQUAL(setslope(pl, coord3d(5, 10, 1), slope.all_down_slope), null)
	ASSERT_EQUAL(setslope(pl, coord3d(4, 10, 1), slope.all_down_slope), null)
	ASSERT_EQUAL(setslope(pl, coord3d(3, 10, 0), slope.flat), null)
	RESET_ALL_PLAYER_FUNDS()
}


//
// 25: a bridge on flat ground. Its heads carry a sloped way and behave like a ramp; the
//     deck is flat and untouched.
//
function test_schedule_route_height_bridge_head_flat()
{
	local pl = player_x(0)
	local bd = bridge_desc_x.get_available_bridges(wt_rail)[0]
	ASSERT_TRUE(bd != null)
	ASSERT_EQUAL(command_x.build_bridge(pl, coord3d(2, 12, 0), coord3d(8, 12, 0), bd), null)

	local sched = sroute_schedule(wt_rail, [coord3d(2, 12, 0), coord3d(8, 12, 0)])
	sroute_open(0, sched, 0)
	sroute_mark(0, true)
	sroute_step()
	ASSERT_TRUE(sroute_len() > 0)

	ASSERT_EQUAL(OVERLAY_RISE_AT(coord3d(2, 12, 0)), 1) // head, way climbs the ramp
	ASSERT_EQUAL(OVERLAY_RISE_AT(coord3d(8, 12, 0)), 1) // head at the far end
	ASSERT_EQUAL(OVERLAY_RISE_AT(coord3d(5, 12, 1)), 0) // deck

	sroute_close(0)
	SROUTE_CLEAR_ROW(pl, 12, 1, 9, wt_rail)
	RESET_ALL_PLAYER_FUNDS()
}


//
// 26: a bridge whose heads stand on ground that was already sloped. There the way is flat
//     but the whole tile content is lifted, so the rise is constant over the tile - one
//     level on a single ramp and two on a double one. This is the case of the report.
//
function test_schedule_route_height_bridge_head_sloped()
{
	local pl = player_x(0)
	local bd = bridge_desc_x.get_available_bridges(wt_rail)[0]
	local setslope = command_x.set_slope

	ASSERT_EQUAL(setslope(pl, coord3d(2, 14, 0), slope.east), null)
	ASSERT_EQUAL(setslope(pl, coord3d(8, 14, 0), slope.west), null)
	ASSERT_EQUAL(command_x.build_bridge(pl, coord3d(2, 14, 0), coord3d(8, 14, 0), bd), null)

	local sched = sroute_schedule(wt_rail, [coord3d(2, 14, 0), coord3d(8, 14, 0)])
	sroute_open(0, sched, 0)
	sroute_mark(0, true)
	sroute_step()
	ASSERT_TRUE(sroute_len() > 0)

	ASSERT_EQUAL(OVERLAY_RISE_AT(coord3d(2, 14, 0)), 2) // head, lifted a whole level
	ASSERT_EQUAL(OVERLAY_RISE_AT(coord3d(8, 14, 0)), 2)
	ASSERT_EQUAL(OVERLAY_RISE_AT(coord3d(5, 14, 1)), 0) // deck

	// the lift is constant across such a head, both edges as well as the centre
	for (local i = 0; i < sroute_len(); ++i) {
		local p = sroute_tile(i)
		local n = i+1 < sroute_len() ? sroute_tile(i+1) : null
		if (p != null && n != null && p.x == 2 && p.y == 14) {
			ASSERT_EQUAL(sroute_way_height2(i, true), 2 * p.z + 2)
		}
	}

	sroute_close(0)
	SROUTE_CLEAR_ROW(pl, 14, 1, 9, wt_rail)
	ASSERT_EQUAL(setslope(pl, coord3d(2, 14, 0), slope.flat), null)
	ASSERT_EQUAL(setslope(pl, coord3d(8, 14, 0), slope.flat), null)
	RESET_ALL_PLAYER_FUNDS()
}


//
// 27-30: the overlay is a line between corners, and a way changes its grade on the edge
//        between two tiles. A straight line from one tile centre to the next therefore
//        misses the way on that edge by a quarter of the change of grade, unless the
//        line is given a corner there. sroute_edge_is_corner() reports whether the
//        display puts one on that edge.
//
//        The property being checked is not "there is a corner here": it is that the line
//        the display draws meets the way surface on every edge the route crosses, with
//        corners only where they are needed. Both halves matter - a display that put a
//        corner on every edge would pass the first half and fail the second, and would
//        also move lines on ground that has no slope at all.
//

// how far the drawn line is from the way surface where it crosses the edge between
// route[i] and route[i+1], in half height levels
function SROUTE_EDGE_MISS(i)
{
	if (sroute_edge_is_corner(i)) {
		return 0
	}
	return 2 * sroute_way_height2(i, true) - sroute_way_height2(i, false) - sroute_way_height2(i + 1, false)
}


// checks that on every edge of the route the drawn line is on the way, and answers how
// many corners that took
function SROUTE_ASSERT_ON_WAY_SURFACE()
{
	local corners = 0
	for (local i = 0; i + 1 < sroute_len(); ++i) {
		if (sroute_tile(i) == null || sroute_tile(i + 1) == null) {
			continue
		}
		ASSERT_EQUAL(SROUTE_EDGE_MISS(i), 0)
		if (sroute_edge_is_corner(i)) {
			corners++
		}
	}
	return corners
}


// whether the edge the route crosses when it leaves the tile at @p pos is a corner
function SROUTE_CORNER_LEAVING(pos)
{
	for (local i = 0; i + 1 < sroute_len(); ++i) {
		local p = sroute_tile(i)
		if (p != null && sroute_tile(i + 1) != null && p.x == pos.x && p.y == pos.y && p.z == pos.z) {
			return sroute_edge_is_corner(i)
		}
	}
	throw "tile " + pos.tostring() + " does not leave anywhere on this route"
}


//
// 27: ground without a slope needs no corner anywhere, on a straight way or a diagonal
//     one. This is the half of the rule that keeps the drawing of flat ground unchanged.
//
function test_schedule_route_corner_flat()
{
	local pl = player_x(0)
	sroute_make_road(pl, coord3d(2, 2, 0), coord3d(2, 8, 0))
	sroute_make_road(pl, coord3d(2, 8, 0), coord3d(8, 8, 0))

	local sched = sroute_schedule(wt_road, [coord3d(2, 2, 0), coord3d(8, 8, 0)])
	sroute_open(0, sched, 0)
	sroute_mark(0, true)
	sroute_step()
	ASSERT_TRUE(sroute_len() > 0)
	ASSERT_EQUAL(SROUTE_ASSERT_ON_WAY_SURFACE(), 0)
	sroute_close(0)

	local last = sroute_make_staircase(pl, 3, 2, 8, true)
	local diag = sroute_schedule(wt_road, [coord3d(3, 2, 0), last])
	sroute_open(0, diag, 0)
	sroute_mark(0, true)
	sroute_step()
	ASSERT_TRUE(sroute_len() > 0)
	ASSERT_EQUAL(SROUTE_ASSERT_ON_WAY_SURFACE(), 0)
	sroute_close(0)

	sroute_make_staircase(pl, 3, 2, 8, false)
	sroute_remove_way(pl, coord3d(2, 2, 0), coord3d(2, 8, 0))
	sroute_remove_way(pl, coord3d(2, 8, 0), coord3d(8, 8, 0))
	RESET_ALL_PLAYER_FUNDS()
}


//
// 28: a ramp. Its two edges are where the way changes grade, so both are corners, and
//     nothing else on the route is. The route runs out and back, so each of the two is
//     counted once per direction.
//
function test_schedule_route_corner_slope()
{
	local pl = player_x(0)
	local rail = way_desc_x.get_available_ways(wt_rail, st_flat)[0]
	local setslope = command_x.set_slope

	ASSERT_EQUAL(setslope(pl, coord3d(4, 10, 0), slope.all_up_slope), null)
	ASSERT_EQUAL(setslope(pl, coord3d(5, 10, 0), slope.all_up_slope), null)
	ASSERT_EQUAL(setslope(pl, coord3d(3, 10, 0), slope.west), null)
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(1, 10, 0), coord3d(5, 10, 1), rail, true), null)

	local sched = sroute_schedule(wt_rail, [coord3d(1, 10, 0), coord3d(5, 10, 1)])
	sroute_open(0, sched, 0)
	sroute_mark(0, true)
	sroute_step()
	ASSERT_TRUE(sroute_len() > 0)

	// four corners over the whole route: the foot and the top of the ramp, once each way
	ASSERT_EQUAL(SROUTE_ASSERT_ON_WAY_SURFACE(), 4)
	ASSERT_TRUE(SROUTE_CORNER_LEAVING(coord3d(2, 10, 0)))  // flat ground onto the ramp
	ASSERT_TRUE(SROUTE_CORNER_LEAVING(coord3d(3, 10, 0)))  // ramp onto the plateau
	ASSERT_FALSE(SROUTE_CORNER_LEAVING(coord3d(1, 10, 0))) // flat to flat
	ASSERT_FALSE(SROUTE_CORNER_LEAVING(coord3d(4, 10, 1))) // plateau to plateau

	sroute_close(0)
	SROUTE_CLEAR_ROW(pl, 10, 1, 5, wt_rail)
	ASSERT_EQUAL(setslope(pl, coord3d(5, 10, 1), slope.all_down_slope), null)
	ASSERT_EQUAL(setslope(pl, coord3d(4, 10, 1), slope.all_down_slope), null)
	ASSERT_EQUAL(setslope(pl, coord3d(3, 10, 0), slope.flat), null)
	RESET_ALL_PLAYER_FUNDS()
}


//
// 29: a bridge on flat ground. The way changes grade where each head meets the ground it
//     stands on and where it meets the deck; the deck itself is one flat run and takes no
//     corner at all, however long it is.
//
function test_schedule_route_corner_bridge_head()
{
	local pl = player_x(0)
	local bd = bridge_desc_x.get_available_bridges(wt_rail)[0]
	ASSERT_TRUE(bd != null)
	ASSERT_EQUAL(command_x.build_bridge(pl, coord3d(2, 12, 0), coord3d(8, 12, 0), bd), null)

	local sched = sroute_schedule(wt_rail, [coord3d(2, 12, 0), coord3d(8, 12, 0)])
	sroute_open(0, sched, 0)
	sroute_mark(0, true)
	sroute_step()
	ASSERT_TRUE(sroute_len() > 0)

	// the two heads, once per direction; the deck contributes none
	ASSERT_EQUAL(SROUTE_ASSERT_ON_WAY_SURFACE(), 4)
	ASSERT_TRUE(SROUTE_CORNER_LEAVING(coord3d(2, 12, 0)))  // head onto the deck
	ASSERT_FALSE(SROUTE_CORNER_LEAVING(coord3d(4, 12, 1))) // deck to deck
	ASSERT_FALSE(SROUTE_CORNER_LEAVING(coord3d(5, 12, 1)))

	sroute_close(0)
	SROUTE_CLEAR_ROW(pl, 12, 1, 9, wt_rail)
	RESET_ALL_PLAYER_FUNDS()
}


//
// 30: a leg that ends on the ramp itself. It leaves by the edge it came in through, so
//     the same edge is crossed twice and takes a corner both times, once on the way in
//     and once on the way out - with the tile centre between them, which is what keeps
//     the two from collapsing into one. The centre of that tile must still be half a
//     level up: sampling one edge twice would put it a whole level up instead.
//
function test_schedule_route_corner_terminus()
{
	local pl = player_x(0)
	local rail = way_desc_x.get_available_ways(wt_rail, st_flat)[0]
	local setslope = command_x.set_slope

	ASSERT_EQUAL(setslope(pl, coord3d(6, 6, 0), slope.all_up_slope), null)
	ASSERT_EQUAL(setslope(pl, coord3d(7, 6, 0), slope.all_up_slope), null)
	ASSERT_EQUAL(setslope(pl, coord3d(5, 6, 0), slope.west), null)
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(3, 6, 0), coord3d(5, 6, 0), rail, true), null)

	local sched = sroute_schedule(wt_rail, [coord3d(3, 6, 0), coord3d(5, 6, 0)])
	sroute_open(0, sched, 0)
	sroute_mark(0, true)
	sroute_step()
	ASSERT_TRUE(sroute_len() > 0)

	ASSERT_EQUAL(SROUTE_ASSERT_ON_WAY_SURFACE(), 2)
	ASSERT_TRUE(SROUTE_CORNER_LEAVING(coord3d(4, 6, 0)))  // flat ground onto the ramp
	ASSERT_TRUE(SROUTE_CORNER_LEAVING(coord3d(5, 6, 0)))  // and back off it by the same edge
	ASSERT_EQUAL(OVERLAY_RISE_AT(coord3d(5, 6, 0)), 1)    // still half a level, not a whole one

	sroute_close(0)
	SROUTE_CLEAR_ROW(pl, 6, 3, 5, wt_rail)
	ASSERT_EQUAL(setslope(pl, coord3d(5, 6, 0), slope.flat), null)
	ASSERT_EQUAL(setslope(pl, coord3d(7, 6, 1), slope.all_down_slope), null)
	ASSERT_EQUAL(setslope(pl, coord3d(6, 6, 1), slope.all_down_slope), null)
	RESET_ALL_PLAYER_FUNDS()
}
