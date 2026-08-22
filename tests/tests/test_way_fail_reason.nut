//
// This file is part of the Simutrans project under the Artistic License.
// (see LICENSE.txt)
//


//
// Tests for the reason a way build is refused.
//
// tool_build_way_t hands back whatever way_builder_t recorded in warn_fail, so
// these pin the reason text itself, not just the refusal. The last test is the
// control that matters: a refusal the builder cannot explain must stay empty,
// never pick up a neighbouring reason and never gain an invented one.
//


function test_way_fail_reason_building()
{
	local pl = player_x(0)
	local road = way_desc_x.get_available_ways(wt_road, st_flat)[0]
	local rail = way_desc_x.get_available_ways(wt_rail, st_flat)[0]
	local road_depot = get_depot_by_wt(wt_road)
	local remover = command_x(tool_remove_way)

	ASSERT_TRUE(road != null)
	ASSERT_TRUE(rail != null)
	ASSERT_TRUE(road_depot != null)

	// a road depot needs a flat dead-end road tile to stand on
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(4, 1, 0), coord3d(4, 2, 0), road, true), null)
	ASSERT_EQUAL(command_x.build_depot(pl, coord3d(4, 2, 0), road_depot), null)

	// rail straight through the depot tile: check_building() refuses to enter a
	// depot of another waytype, and that refusal has a reason attached
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(2, 2, 0), coord3d(6, 2, 0), rail, true),
		"A building blocks the construction")

	// clean up
	ASSERT_EQUAL(command_x(tool_remover).work(pl, coord3d(4, 2, 0)), null)
	ASSERT_EQUAL(remover.work(pl, tile_x(4, 1, 0), tile_x(4, 2, 0), "" + wt_road), null)

	RESET_ALL_PLAYER_FUNDS()
}


function test_way_fail_reason_crossing()
{
	local pl = player_x(0)
	local road = way_desc_x.get_available_ways(wt_road, st_flat)[0]
	local rail = way_desc_x.get_available_ways(wt_rail, st_flat)[0]
	local remover = command_x(tool_remove_way)

	ASSERT_TRUE(road != null)
	ASSERT_TRUE(rail != null)

	ASSERT_EQUAL(command_x.build_way(pl, coord3d(4, 1, 0), coord3d(4, 3, 0), road, true), null)

	// cross at (4,1), the dead end of that road: a crossing needs a through way
	// on both sides, so this is refused - with a reason.
	// The expected text is the *translated* one: wegbauer.cc translates this
	// reason where it records it, unlike every other tool error, which is
	// handed back as a key and translated when it is shown.
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(2, 1, 0), coord3d(6, 1, 0), rail, true),
		"No suitable crossing! (max speed too fast?)")

	// clean up
	ASSERT_EQUAL(remover.work(pl, tile_x(4, 1, 0), tile_x(4, 3, 0), "" + wt_road), null)

	RESET_ALL_PLAYER_FUNDS()
}


function test_way_fail_reason_ground()
{
	local pl = player_x(0)
	local road = way_desc_x.get_available_ways(wt_road, st_flat)[0]
	local setclimate = command_x(tool_set_climate)

	ASSERT_TRUE(road != null)

	ASSERT_EQUAL(setclimate.work(pl, coord3d(4, 4, 0), coord3d(4, 4, 0), "" + cl_water), null)

	// a road cannot enter water
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(2, 4, 0), coord3d(6, 4, 0), road, true),
		"No suitable ground!")

	// clean up
	ASSERT_EQUAL(setclimate.work(pl, coord3d(4, 4, 0), coord3d(4, 4, 0), "" + cl_mediterran), null)

	RESET_ALL_PLAYER_FUNDS()
}


function test_way_fail_reason_slope()
{
	local pl = player_x(0)
	local road = way_desc_x.get_available_ways(wt_road, st_flat)[0]

	ASSERT_TRUE(road != null)

	// a slope across the direction of travel: the way cannot follow it and
	// there is no terraforming to fall back on
	ASSERT_EQUAL(command_x.set_slope(pl, coord3d(4, 4, 0), slope.east), null)

	ASSERT_EQUAL(command_x.build_way(pl, coord3d(4, 2, 0), coord3d(4, 6, 0), road, true),
		"Slope is too steep")

	// clean up
	ASSERT_EQUAL(command_x.set_slope(pl, coord3d(4, 4, 0), slope.flat), null)

	RESET_ALL_PLAYER_FUNDS()
}


function test_way_fail_reason_still_silent()
{
	local pl = player_x(0)
	local road = way_desc_x.get_available_ways(wt_road, st_flat)[0]
	local powerline = way_desc_x.get_available_ways(wt_power, st_flat)[0]
	local remover = command_x(tool_remove_way)

	ASSERT_TRUE(road != null)
	ASSERT_TRUE(powerline != null)

	ASSERT_EQUAL(command_x.build_way(pl, coord3d(4, 2, 0), coord3d(4, 6, 0), road, true), null)

	// negative control. A powerline may only cross a way at a right angle and
	// only where that way runs straight; here it is asked to run *along* the
	// road, and that refusal deliberately carries no reason, because the
	// condition it fails is an accumulation of several unrelated ones and any
	// single message would be a guess.
	//
	// The empty string is the whole point: if this ever comes back with a
	// message, either a reason was added without thinking about what it means
	// or a reason from an unrelated tile leaked into this one.
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(4, 3, 0), coord3d(4, 5, 0), powerline, true), "")

	// clean up
	ASSERT_EQUAL(remover.work(pl, tile_x(4, 2, 0), tile_x(4, 6, 0), "" + wt_road), null)

	RESET_ALL_PLAYER_FUNDS()
}
