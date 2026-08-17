//
// This file is part of the Simutrans project under the Artistic License.
// (see LICENSE.txt)
//

//
// Tests for convoy problem state: convoy_x::has_no_route and convoy_x::is_stuck
//
// These test what the two predicates MEAN, not that they are registered.
// The distinctions they draw are the point of the API:
//
//   has_no_route()  is true only in the engine state NO_ROUTE
//   is_stuck()      is true only after the engine has escalated a blocked
//                   convoy to the two-month waiting states
//   is_waiting()    is a different question again, and is false for a convoy
//                   that has no route at all
//


// Kept local to this file so it does not depend on another test file having
// been included first.
function convoy_state_schedule(waytype, stop_positions)
{
	return schedule_x(waytype, stop_positions.map(@(pos) schedule_entry_x(pos, 0, 0)))
}


// Advance the simulation until cond(cnv) holds, or give up.
// A plain `while(!cond()) sleep()` is the idiom used elsewhere in these tests,
// but it hangs the whole suite if the condition never arrives. This fails
// instead, which is what a test should do.
function WAIT_UNTIL(cnv, cond)
{
	local steps = 0
	while (!cond(cnv)  &&  steps < 100) {
		sleep()
		steps++
	}
	return cond(cnv)
}


function CNV_HAS_NO_ROUTE(cnv)  { return cnv.has_no_route() }
function CNV_LEFT_DEPOT(cnv)    { return !cnv.is_in_depot() }


function test_convoy_state_in_depot()
{
	local pl = player_x(0)

	ASSERT_EQUAL(command_x(tool_build_way).work(pl, coord3d(2, 2, 0), coord3d(2, 5, 0), "cobblestone_road"), null)
	ASSERT_EQUAL(command_x.build_depot(pl, coord3d(2, 2, 0), building_desc_x("CarDepot")), null)

	local depot = depot_x(2, 2, 0)
	depot.append_vehicle(pl, convoy_x(0), vehicle_desc_x("Buessig"))
	local cnv = depot.get_convoy_list()[0]

	{
		// a convoy standing in its depot has nothing to report
		ASSERT_TRUE(cnv.is_in_depot())
		ASSERT_FALSE(cnv.has_no_route())
		ASSERT_FALSE(cnv.is_stuck())
		ASSERT_FALSE(cnv.is_waiting())
	}

	ASSERT_TRUE(cnv.destroy(pl))

	// clean up
	ASSERT_EQUAL(command_x(tool_remover).work(pl, coord3d(2, 2, 0)), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(pl, coord3d(2, 2, 0), coord3d(2, 5, 0), "" + wt_road), null)
	RESET_ALL_PLAYER_FUNDS()
}


function test_convoy_state_no_route()
{
	local pl = player_x(0)

	// one road the convoy can drive on ...
	ASSERT_EQUAL(command_x(tool_build_way).work(pl, coord3d(2, 2, 0), coord3d(2, 8, 0), "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, coord3d(2, 2, 0), "BusStop"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, coord3d(2, 7, 0), "BusStop"), null)
	ASSERT_EQUAL(command_x.build_depot(pl, coord3d(2, 8, 0), building_desc_x("CarDepot")), null)

	// ... and a second one it can never reach, because nothing connects them
	ASSERT_EQUAL(command_x(tool_build_way).work(pl, coord3d(10, 2, 0), coord3d(10, 8, 0), "cobblestone_road"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, coord3d(10, 2, 0), "BusStop"), null)
	ASSERT_EQUAL(command_x(tool_build_station).work(pl, coord3d(10, 7, 0), "BusStop"), null)

	local depot = depot_x(2, 8, 0)
	depot.append_vehicle(pl, convoy_x(0), vehicle_desc_x("Buessig"))
	local cnv = depot.get_convoy_list()[0]
	cnv.change_schedule(pl, convoy_state_schedule(wt_road, [ coord3d(2, 7, 0), coord3d(2, 2, 0) ]))
	depot.start_all_convoys(pl)

	ASSERT_TRUE(WAIT_UNTIL(cnv, CNV_LEFT_DEPOT))

	{
		// a convoy that is driving its schedule has no problem to report
		ASSERT_FALSE(cnv.has_no_route())
		ASSERT_FALSE(cnv.is_stuck())
	}

	// send it to the road it cannot reach: the next route calculation fails.
	// Note this cannot be done from the depot - depot_t::start_convoi refuses
	// to release a convoy whose route cannot be computed, so a convoy can only
	// enter NO_ROUTE after it has already left.
	cnv.change_schedule(pl, convoy_state_schedule(wt_road, [ coord3d(10, 7, 0), coord3d(10, 2, 0) ]))

	ASSERT_TRUE(WAIT_UNTIL(cnv, CNV_HAS_NO_ROUTE))

	{
		// having no route is a problem of its own, and is not being stuck:
		// the convoy is not waiting for anything, it has nowhere to go
		ASSERT_TRUE(cnv.has_no_route())
		ASSERT_FALSE(cnv.is_stuck())
		ASSERT_FALSE(cnv.is_waiting())
		ASSERT_FALSE(cnv.is_in_depot())
	}

	ASSERT_TRUE(cnv.destroy(pl))
	sleep()
	sleep() // make sure the convoy is really gone before the road is removed

	// clean up
	ASSERT_EQUAL(command_x(tool_remover).work(pl, coord3d(2, 8, 0)), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, coord3d(2, 7, 0)), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, coord3d(2, 2, 0)), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, coord3d(10, 7, 0)), null)
	ASSERT_EQUAL(command_x(tool_remover).work(pl, coord3d(10, 2, 0)), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(pl, coord3d(2, 2, 0), coord3d(2, 8, 0), "" + wt_road), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(pl, coord3d(10, 2, 0), coord3d(10, 8, 0), "" + wt_road), null)
	RESET_ALL_PLAYER_FUNDS()
}
