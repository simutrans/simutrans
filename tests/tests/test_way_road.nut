//
// This file is part of the Simutrans project under the Artistic License.
// (see LICENSE.txt)
//


//
// Tests for way building / removal
//


function test_way_road_build_single_tile()
{
	local pl = player_x(0)
	local road_desc = way_desc_x.get_available_ways(wt_road, st_flat)[0]
	local default_cash = pl.get_current_cash()

	ASSERT_TRUE(road_desc != null)

	{
		ASSERT_EQUAL(command_x.build_way(pl, coord3d(4, 2, 0), coord3d(4, 2, 0), road_desc, true), "")
		ASSERT_EQUAL(pl.get_current_cash(), default_cash)

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........"
			])
	}

	{
		ASSERT_EQUAL(command_x.build_way(pl, coord3d(4, 2, 0), coord3d(4, 2, 0), road_desc, false), "")
		ASSERT_EQUAL(pl.get_current_cash(), default_cash)

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........"
			])
	}

	RESET_ALL_PLAYER_FUNDS()
}


function test_way_road_build_straight()
{
	local default_cash = 200000 * 100
	local current_cash = default_cash

	local pl   = player_x(0)
	local desc = way_desc_x.get_available_ways(wt_road, st_flat)[0]
	ASSERT_TRUE(desc != null)

	//prerequisites
	ASSERT_EQUAL(pl.get_current_maintenance(), 0)

	local tool_result = command_x.build_way(pl, coord3d(2, 1, 0), coord3d(2, 6, 0), desc, true)
	ASSERT_EQUAL(tool_result, null)
	ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
		[
			"........",
			"..4.....",
			"..5.....",
			"..5.....",
			"..5.....",
			"..5.....",
			"..1.....",
			"........"
		])

	ASSERT_TRUE(pl.get_current_net_wealth() < current_cash)
	ASSERT_TRUE(pl.get_current_maintenance() > 0)
	ASSERT_TRUE(pl.get_current_cash() < default_cash / 100)
	current_cash = pl.get_current_net_wealth()
	local maintenance_per_tile = pl.get_current_maintenance() / 6

	tool_result = command_x.build_way(pl, coord3d(2, 2, 0), coord3d(6, 2, 0), desc, true)
	ASSERT_EQUAL(tool_result, null)
	ASSERT_TRUE(pl.get_current_net_wealth() < current_cash)
	ASSERT_EQUAL(pl.get_current_maintenance(), maintenance_per_tile * (6 + 4))
	ASSERT_TRUE(pl.get_current_cash() < default_cash / 100)

	ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
		[
			"........",
			"..4.....",
			"..7AAA8.",
			"..5.....",
			"..5.....",
			"..5.....",
			"..1.....",
			"........"
		])

	tool_result = command_x.build_way(pl, coord3d(16, 5, 0), coord3d(5, 5, 0), desc, true)
	ASSERT_EQUAL(tool_result, "")
	ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
		[
			"........",
			"..4.....",
			"..7AAA8.",
			"..5.....",
			"..5.....",
			"..5.....",
			"..1.....",
			"........"
		])

	tool_result = command_x.build_way(pl, coord3d(1, 1, 1), coord3d(1, 5, 1), desc, true)
	ASSERT_EQUAL(tool_result, "")
	ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
		[
			"........",
			"..4.....",
			"..7AAA8.",
			"..5.....",
			"..5.....",
			"..5.....",
			"..1.....",
			"........"
		])

	tool_result = command_x.build_way(pl, coord3d(1, 1, -1), coord3d(1, 5, -1), desc, true)
	ASSERT_EQUAL(tool_result, "")
	ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
		[
			"........",
			"..4.....",
			"..7AAA8.",
			"..5.....",
			"..5.....",
			"..5.....",
			"..1.....",
			"........"
		])

	// clean up

	local remover = command_x(tool_remove_way)
	tool_result = remover.work(pl, tile_x(2, 2, 0), tile_x(6, 2, 0), "" + wt_road)
	ASSERT_EQUAL(tool_result, null)
	ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
		[
			"........",
			"..4.....",
			"..5.....",
			"..5.....",
			"..5.....",
			"..5.....",
			"..1.....",
			"........"
		])

	tool_result = remover.work(pl, tile_x(2, 3, 0), tile_x(2, 4, 0), "" + wt_road)
	ASSERT_EQUAL(tool_result, null)
	ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
		[
			"........",
			"..4.....",
			"..5.....",
			"..1.....",
			"..4.....",
			"..5.....",
			"..1.....",
			"........"
		])

	tool_result = remover.work(pl, tile_x(2, 1, 0), tile_x(2, 2, 0), "" + wt_road)
	ASSERT_EQUAL(tool_result, null)
	ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
		[
			"........",
			"........",
			"..4.....",
			"..1.....",
			"..4.....",
			"..5.....",
			"..1.....",
			"........"
		])

	tool_result = remover.work(pl, tile_x(2, 2, 0), tile_x(2, 6, 0), "" + wt_road)
	ASSERT_EQUAL(tool_result, "Ways not connected")
	ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
		[
			"........",
			"........",
			"..4.....",
			"..1.....",
			"..4.....",
			"..5.....",
			"..1.....",
			"........"
		])

	tool_result = remover.work(pl, tile_x(2, 2, 0), tile_x(2, 3, 0), "" + wt_road)
	ASSERT_EQUAL(tool_result, null)
	tool_result = remover.work(pl, tile_x(2, 4, 0), tile_x(2, 6, 0), "" + wt_road)
	ASSERT_EQUAL(tool_result, null)
	ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
		[
			"........",
			"........",
			"........",
			"........",
			"........",
			"........",
			"........",
			"........"
		])

	RESET_ALL_PLAYER_FUNDS()
}


function test_way_road_build_bend()
{
	local pl   = player_x(0)
	local desc = way_desc_x.get_available_ways(wt_road, st_flat)[0]
	local remover = command_x(tool_remove_way)

	ASSERT_TRUE(desc != null)

	{
		local tool_result = command_x.build_way(pl, coord3d(0, 1, 0), coord3d(1, 0, 0), desc, true)
		ASSERT_EQUAL(tool_result, null)
		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				".4......",
				"29......",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........"
			])

		remover.work(pl, tile_x(0, 1, 0), coord3d(1, 0, 0), "" + wt_road)
		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........"
			])
	}

	{

		command_x.grid_raise(pl, coord3d(2, 2, 0))

		local err = command_x.build_way(pl, coord3d(0, 1, 0), coord3d(1, 0, 0), desc, true)
		ASSERT_EQUAL(err, null)
		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"68......",
				"1.......",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........"
			])

		remover.work(pl, tile_x(0, 1, 0), coord3d(1, 0, 0), "" + wt_road)
		command_x.grid_lower(pl, coord3d(2, 2, 0))
		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........"
			])
	}

	RESET_ALL_PLAYER_FUNDS()
}


function test_way_road_build_parallel()
{
	local pl   = player_x(0)
	local desc = way_desc_x.get_available_ways(wt_road, st_flat)[0]
	local rail_desc = way_desc_x.get_available_ways(wt_rail, st_flat)[0]
	local remover = command_x(tool_remove_way)

	{
		for (local i = 1; i < 16; ++i) {
			ASSERT_EQUAL(command_x.build_way(pl, coord3d(0, i, 0), coord3d(i, i, 0), desc, true), null)
		}

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"................",
				"28..............",
				"2A8.............",
				"2AA8............",
				"2AAA8...........",
				"2AAAA8..........",
				"2AAAAA8.........",
				"2AAAAAA8........",
				"2AAAAAAA8.......",
				"2AAAAAAAA8......",
				"2AAAAAAAAA8.....",
				"2AAAAAAAAAA8....",
				"2AAAAAAAAAAA8...",
				"2AAAAAAAAAAAA8..",
				"2AAAAAAAAAAAAA8.",
				"2AAAAAAAAAAAAAA8"
			])

		for (local i = 1; i < 16; ++i) {
			ASSERT_EQUAL(remover.work(pl, coord3d(0, i, 0), coord3d(i, i, 0), "" + wt_road), null)
		}
	}

	{
		for (local i = 1; i < 16; ++i) {
			ASSERT_EQUAL(command_x.build_way(pl, coord3d(0, i, 0), coord3d(i, i, 0), desc, false), null)
		}

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"................",
				"28..............",
				"2A8.............",
				"2AA8............",
				"2AAA8...........",
				"2AAAA8..........",
				"2AAAAA8.........",
				"2AAAAAA8........",
				"2AAAAAAA8.......",
				"2AAAAAAAA8......",
				"2AAAAAAAAA8.....",
				"2AAAAAAAAAA8....",
				"2AAAAAAAAAAA8...",
				"2AAAAAAAAAAAA8..",
				"2AAAAAAAAAAAAA8.",
				"2AAAAAAAAAAAAAA8"
			])

		for (local i = 1; i < 16; ++i) {
			ASSERT_EQUAL(remover.work(pl, coord3d(0, i, 0), coord3d(i, i, 0), "" + wt_road), null)
		}
	}

	{
		for (local i = 0; i < 16; ++i) {
			ASSERT_EQUAL(command_x.build_way(pl, coord3d(0, i, 0), coord3d(15, i, 0), desc, false), null)
		}

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"2AAAAAAAAAAAAAA8",
				"2AAAAAAAAAAAAAA8",
				"2AAAAAAAAAAAAAA8",
				"2AAAAAAAAAAAAAA8",
				"2AAAAAAAAAAAAAA8",
				"2AAAAAAAAAAAAAA8",
				"2AAAAAAAAAAAAAA8",
				"2AAAAAAAAAAAAAA8",
				"2AAAAAAAAAAAAAA8",
				"2AAAAAAAAAAAAAA8",
				"2AAAAAAAAAAAAAA8",
				"2AAAAAAAAAAAAAA8",
				"2AAAAAAAAAAAAAA8",
				"2AAAAAAAAAAAAAA8",
				"2AAAAAAAAAAAAAA8",
				"2AAAAAAAAAAAAAA8"
			])

		for (local i = 0; i < 16; ++i) {
			ASSERT_EQUAL(remover.work(pl, coord3d(0, i, 0), coord3d(15, i, 0), "" + wt_road), null)
		}
	}

	RESET_ALL_PLAYER_FUNDS()
}


function test_way_road_build_below_powerline()
{
	local pl = player_x(0)
	local public_pl = player_x(1)
	local remover = command_x(tool_remove_way)
	local powerline = way_desc_x.get_available_ways(wt_power, st_flat)[0]
	local road = way_desc_x.get_available_ways(wt_road, st_flat)[0]


	ASSERT_EQUAL(pl.get_current_maintenance(), 0)

	ASSERT_EQUAL(command_x.build_way(pl, coord3d(1, 1, 0), coord3d(3, 1, 0), powerline, true), null)
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(3, 1, 0), coord3d(3, 3, 0), powerline, true), null)
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(3, 3, 0), coord3d(1, 3, 0), powerline, true), null)
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(1, 3, 0), coord3d(1, 1, 0), powerline, true), null)

	ASSERT_WAY_PATTERN(wt_power, coord3d(0, 0, 0),
		[
			"........",
			".6AC....",
			".5.5....",
			".3A9....",
			"........",
			"........",
			"........",
			"........"
		])

	// build way along powerline above, should fail
	{
		local old_maintenance = pl.get_current_maintenance()

		ASSERT_EQUAL(command_x.build_way(pl, coord3d(1, 1, 0), coord3d(3, 1, 0), road, true), "")
		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........"
			])

		ASSERT_EQUAL(pl.get_current_maintenance(), old_maintenance)
	}

	// build way ending below power line, should succeed
	{
		ASSERT_EQUAL(command_x.build_way(pl, coord3d(2, 2, 0), coord3d(2, 1, 0), road, true), null)
		ASSERT_EQUAL(command_x.build_way(pl, coord3d(2, 2, 0), coord3d(3, 2, 0), road, true), null)
		ASSERT_EQUAL(command_x.build_way(pl, coord3d(2, 2, 0), coord3d(2, 3, 0), road, true), null)
		ASSERT_EQUAL(command_x.build_way(pl, coord3d(2, 2, 0), coord3d(1, 2, 0), road, true), null)

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"..4.....",
				".2F8....",
				"..1.....",
				"........",
				"........",
				"........",
				"........"
			])
	}

	// remove ways
	ASSERT_EQUAL(remover.work(pl, coord3d(2, 1, 0), coord3d(2, 3, 0), "" + wt_road), null)
	ASSERT_EQUAL(remover.work(pl, coord3d(1, 2, 0), coord3d(3, 2, 0), "" + wt_road), null)

	ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
		[
			"........",
			"........",
			"........",
			"........",
			"........",
			"........",
			"........",
			"........"
		])

	// build way not ending under power line, should succeed
	{
		ASSERT_EQUAL(command_x.build_way(pl, coord3d(2, 2, 0), coord3d(2, 0, 0), road, true), null)
		ASSERT_EQUAL(command_x.build_way(pl, coord3d(2, 2, 0), coord3d(4, 2, 0), road, true), null)
		ASSERT_EQUAL(command_x.build_way(pl, coord3d(2, 2, 0), coord3d(2, 4, 0), road, true), null)
		ASSERT_EQUAL(command_x.build_way(pl, coord3d(2, 2, 0), coord3d(0, 2, 0), road, true), null)

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"..4.....",
				"..5.....",
				"2AFA8...",
				"..5.....",
				"..1.....",
				"........",
				"........",
				"........"
			])
	}

	// remove ways
	ASSERT_EQUAL(remover.work(pl, coord3d(2, 0, 0), coord3d(2, 4, 0), "" + wt_road), null)
	ASSERT_EQUAL(remover.work(pl, coord3d(0, 2, 0), coord3d(4, 2, 0), "" + wt_road), null)
	ASSERT_EQUAL(remover.work(pl, coord3d(1, 1, 0), coord3d(3, 3, 0), "" + wt_power), null)
	ASSERT_EQUAL(remover.work(pl, coord3d(1, 1, 0), coord3d(3, 3, 0), "" + wt_power), null)

	ASSERT_WAY_PATTERN(wt_power, coord3d(0, 0, 0),
		[
			"........",
			"........",
			"........",
			"........",
			"........",
			"........",
			"........",
			"........"
		])

	ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
		[
			"........",
			"........",
			"........",
			"........",
			"........",
			"........",
			"........",
			"........"
		])

	ASSERT_EQUAL(pl.get_current_maintenance(), 0)

	// build way under end of powerline, should fail
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(2, 1, 0), coord3d(2, 3, 0), powerline, true), null)
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(1, 2, 0), coord3d(3, 2, 0), powerline, true), null)

	{
		local old_maintenance = pl.get_current_maintenance()

		ASSERT_EQUAL(command_x.build_way(pl, coord3d(1, 1, 0), coord3d(3, 1, 0), road, true), "")
		ASSERT_EQUAL(command_x.build_way(pl, coord3d(3, 1, 0), coord3d(3, 3, 0), road, true), "")
		ASSERT_EQUAL(command_x.build_way(pl, coord3d(3, 3, 0), coord3d(1, 3, 0), road, true), "")
		ASSERT_EQUAL(command_x.build_way(pl, coord3d(1, 3, 0), coord3d(1, 1, 0), road, true), "")

		ASSERT_WAY_PATTERN(wt_power, coord3d(0, 0, 0),
			[
				"........",
				"..4.....",
				".2F8....",
				"..1.....",
				"........",
				"........",
				"........",
				"........"
			])

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........"
			])

	}

	ASSERT_EQUAL(remover.work(pl, coord3d(2, 1, 0), coord3d(2, 3, 0), "" + wt_power), null)
	ASSERT_EQUAL(remover.work(pl, coord3d(1, 2, 0), coord3d(3, 2, 0), "" + wt_power), null)
	ASSERT_EQUAL(pl.get_current_maintenance(), 0)

	// add diagonal power line
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(0, 0, 0), coord3d(7, 7, 0), powerline, true), null)

	{
		// build way across diagonal power line, should fail
		ASSERT_EQUAL(command_x.build_way(pl, coord3d(0, 7, 0), coord3d(7, 0, 0), road, true), "")

		ASSERT_WAY_PATTERN(wt_power, coord3d(0, 0, 0),
			[
				"2C......",
				".3C.....",
				"..3C....",
				"...3C...",
				"....3C..",
				".....3C.",
				"......3C",
				".......1"
			])

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........"
			])
	}

	// and remove power line
	ASSERT_EQUAL(remover.work(pl, coord3d(0, 0, 0), coord3d(7, 7, 0), "" + wt_power), null)

	// clean up
	ASSERT_EQUAL(pl.get_current_maintenance(), 0)
	RESET_ALL_PLAYER_FUNDS()
}


function test_way_road_build_crossing()
{
	local pl = player_x(0)
	local public_pl = player_x(1)
	local remover = command_x(tool_remove_way)
	local rail = way_desc_x("sand_track")
	local slow_road = way_desc_x("dirt_road")
	local fast_road = way_desc_x("asphalt_road")

	// road too fast, cannot build crossing
	{
		ASSERT_EQUAL(command_x.build_way(pl, coord3d(3, 1, 0), coord3d(3, 3, 0), rail, true), null)
		ASSERT_EQUAL(command_x.build_way(pl, coord3d(2, 2, 0), coord3d(4, 2, 0), fast_road, true), translate("No suitable crossing"))

		ASSERT_WAY_PATTERN(wt_rail, coord3d(0, 0, 0),
			[
				"........",
				"...4....",
				"...5....",
				"...1....",
				"........",
				"........",
				"........",
				"........"
			])

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........"
			])

		ASSERT_FALSE(way_x(3, 2, 0).is_crossing())
		ASSERT_FALSE(tile_x(3, 2, 0).has_two_ways())
	}

	// road slow enough for crossing -> works
	{
		ASSERT_EQUAL(command_x.build_way(pl, coord3d(2, 2, 0), coord3d(4, 2, 0), slow_road, true), null)

		ASSERT_WAY_PATTERN(wt_rail, coord3d(0, 0, 0),
			[
				"........",
				"...4....",
				"...5....",
				"...1....",
				"........",
				"........",
				"........",
				"........"
			])

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"........",
				"..2A8...",
				"........",
				"........",
				"........",
				"........",
				"........"
			])

		ASSERT_TRUE(way_x(3, 2, 0).is_crossing())
		ASSERT_EQUAL(way_x(3, 2, 0).get_max_speed(), slow_road.get_topspeed())
		ASSERT_TRUE(tile_x(3, 2, 0).has_two_ways())
		ASSERT_EQUAL(tile_x(3, 2, 0).get_way(wt_road).get_max_speed(), slow_road.get_topspeed())
		ASSERT_EQUAL(tile_x(3, 2, 0).get_way(wt_rail).get_max_speed(), rail.get_topspeed())
	}

	// clean up
	ASSERT_EQUAL(remover.work(pl, coord3d(3, 1, 0), coord3d(3, 3, 0), "" + wt_rail), null)
	ASSERT_EQUAL(remover.work(pl, coord3d(2, 2, 0), coord3d(4, 2, 0), "" + wt_road), null)
	RESET_ALL_PLAYER_FUNDS()
}


function test_way_road_upgrade_crossing()
{
	local pl = player_x(0)
	local public_pl = player_x(1)
	local remover = command_x(tool_remove_way)
	local rail = way_desc_x("sand_track")
	local slow_road = way_desc_x("dirt_road")
	local fast_road = way_desc_x("asphalt_road")

	ASSERT_EQUAL(command_x.build_way(pl, coord3d(3, 1, 0), coord3d(3, 3, 0), rail, true), null)
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(2, 2, 0), coord3d(4, 2, 0), slow_road, true), null)

	// hard-coded because there is no crossing_desc_x/crossing_x
	local crossing_road_speed = 80
	local crossing_rail_speed = 160

	// upgrade road past max crossing speed; works, but road crossing speed is limited
	{
		ASSERT_EQUAL(command_x.build_way(pl, coord3d(2, 2, 0), coord3d(4, 2, 0), fast_road, true), null)

		ASSERT_WAY_PATTERN(wt_rail, coord3d(0, 0, 0),
			[
				"........",
				"...4....",
				"...5....",
				"...1....",
				"........",
				"........",
				"........",
				"........"
			])

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"........",
				"..2A8...",
				"........",
				"........",
				"........",
				"........",
				"........"
			])

		ASSERT_TRUE(way_x(3, 2, 0).is_crossing())
		ASSERT_EQUAL(way_x(3, 2, 0).get_max_speed(), min(crossing_road_speed, fast_road.get_topspeed()))
		ASSERT_TRUE(tile_x(3, 2, 0).has_two_ways())
		ASSERT_EQUAL(tile_x(3, 2, 0).get_way(wt_road).get_max_speed(), min(crossing_road_speed, fast_road.get_topspeed()))
		ASSERT_EQUAL(tile_x(3, 2, 0).get_way(wt_rail).get_max_speed(), min(crossing_rail_speed, rail.get_topspeed()))
	}

	// clean up
	ASSERT_EQUAL(remover.work(pl, coord3d(3, 1, 0), coord3d(3, 3, 0), "" + wt_rail), null)
	ASSERT_EQUAL(remover.work(pl, coord3d(2, 2, 0), coord3d(4, 2, 0), "" + wt_road), null)

	// upgrade rail with crossing; the crossing is upgraded
	{
		local fast_rail = way_desc_x("wooden_sleeper_track")
		ASSERT_EQUAL(command_x.build_way(pl, coord3d(2, 2, 0), coord3d(4, 2, 0), slow_road, true), null)
		// The crossing whose speed limit for rail is 80kph is built here.
		ASSERT_EQUAL(command_x.build_way(pl, coord3d(3, 1, 0), coord3d(3, 3, 0), rail, true), null)
		// upgrade rail. The crossing should be upgraded to the one whose speed limit for rail is 160kph.
		ASSERT_EQUAL(command_x.build_way(pl, coord3d(3, 1, 0), coord3d(3, 3, 0), fast_rail, true), null)

		ASSERT_EQUAL(tile_x(3, 2, 0).get_way(wt_road).get_max_speed(), min(crossing_road_speed, slow_road.get_topspeed()))
		ASSERT_EQUAL(tile_x(3, 2, 0).get_way(wt_rail).get_max_speed(), min(crossing_rail_speed, fast_rail.get_topspeed()))
	}

	// clean up
	ASSERT_EQUAL(remover.work(pl, coord3d(3, 1, 0), coord3d(3, 3, 0), "" + wt_rail), null)
	ASSERT_EQUAL(remover.work(pl, coord3d(2, 2, 0), coord3d(4, 2, 0), "" + wt_road), null)
	RESET_ALL_PLAYER_FUNDS()
}


function test_way_road_upgrade_downgrade()
{
	local pl = player_x(0)
	local public_pl = player_x(1)
	local remover = command_x(tool_remove_way)
	local start_pos = coord3d(4, 3, 0)
	local end_pos = coord3d(4, 5, 0)

	local all_ways = way_desc_x.get_available_ways(wt_road, st_flat)
	all_ways.sort(@(a, b) a.get_topspeed() <=> b.get_topspeed())

	ASSERT_TRUE(all_ways.len() >= 2)
	local slow_road = all_ways[0]
	local fast_road = all_ways[1]
	ASSERT_TRUE(slow_road.get_name() != fast_road.get_name())
	ASSERT_TRUE(slow_road.get_topspeed() < fast_road.get_topspeed())

	// build road
	ASSERT_EQUAL(command_x.build_way(pl, start_pos, end_pos, slow_road, true), null)

	// upgrade road
	{
		ASSERT_EQUAL(command_x.build_way(pl, start_pos, end_pos, fast_road, true), null)

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"........",
				"........",
				"....4...",
				"....5...",
				"....1...",
				"........",
				"........"
			])
	}

	// Replace road with same road, should incur no cost
	{
		local old_cash = pl.get_current_cash()
		ASSERT_EQUAL(command_x.build_way(pl, start_pos, end_pos, fast_road, true), null)
		ASSERT_EQUAL(pl.get_current_cash(), old_cash)

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"........",
				"........",
				"....4...",
				"....5...",
				"....1...",
				"........",
				"........"
			])
	}

	// downgrade road without ctrl; should fail
	// note that we cannot use command_x.buid_way for this, because there is no way to enable
	// ctrl-pressed behaviour (the way is replaced in any case)
	{
		local old_maintenance = pl.get_current_maintenance()
		local old_cash = pl.get_current_cash()

		local tool = command_x(tool_build_way)
		ASSERT_EQUAL(tool.work(pl, start_pos, end_pos, slow_road.get_name()), null)

		ASSERT_EQUAL(tile_x(4, 4, 0).find_object(mo_way).get_desc().get_name(), fast_road.get_name())
		ASSERT_EQUAL(pl.get_current_cash(), old_cash)
		ASSERT_EQUAL(pl.get_current_maintenance(), old_maintenance)

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"........",
				"........",
				"....4...",
				"....5...",
				"....1...",
				"........",
				"........"
			])
	}

	// downgrade road with ctrl
	{
		local tool = command_x(tool_build_way)
		tool.set_flags(2) // ctrl
		ASSERT_EQUAL(tool.work(pl, start_pos, end_pos, slow_road.get_name()), null)

		ASSERT_EQUAL(tile_x(4, 4, 0).find_object(mo_way).get_desc().get_name(), slow_road.get_name())

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"........",
				"........",
				"....4...",
				"....5...",
				"....1...",
				"........",
				"........"
			])
	}

	ASSERT_EQUAL(remover.work(pl, start_pos, end_pos, "" + wt_road), null)

	// clean up
	ASSERT_EQUAL(pl.get_current_maintenance(), 0)
	RESET_ALL_PLAYER_FUNDS()
}


function test_way_road_upgrade_downgrade_across_bridge()
{
	local pl = player_x(0)
	local public_pl = player_x(1)
	local remover = command_x(tool_remove_way)
	local start_pos = coord3d(3, 6, 0)
	local end_pos = coord3d(3, 2, 0)
	local bridge = bridge_desc_x.get_available_bridges(wt_road)[0]
	local all_ways = way_desc_x.get_available_ways(wt_road, st_flat)
	all_ways.sort(@(a, b) a.get_topspeed() <=> b.get_topspeed())

	ASSERT_TRUE(all_ways.len() >= 2)
	local slow_road = all_ways[0]
	local fast_road = all_ways[1]
	ASSERT_TRUE(slow_road.get_name() != fast_road.get_name())
	ASSERT_TRUE(slow_road.get_topspeed() < fast_road.get_topspeed())

	// build bridge
	ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(3, 6, 0)), null)
	ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(4, 6, 0)), null)
	ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(3, 3, 0)), null)
	ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(4, 3, 0)), null)
	ASSERT_EQUAL(command_x.build_bridge_at(pl, coord3d(3, 5, 0), bridge), null)

	// upgrade road
	{
		ASSERT_TRUE(tile_x(3, 6, 0).find_object(mo_way) != null)
		ASSERT_TRUE(tile_x(3, 2, 0).find_object(mo_way) != null)

		ASSERT_EQUAL(command_x.build_way(pl, start_pos, end_pos, fast_road, true), null)
		ASSERT_EQUAL(tile_x(3, 6, 0).find_object(mo_way).get_desc().get_name(), fast_road.get_name())
		ASSERT_EQUAL(tile_x(3, 2, 0).find_object(mo_way).get_desc().get_name(), fast_road.get_name())

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"........",
				"...4....",
				"...5....",
				"........",
				"...5....",
				"...1....",
				"........"
			])
	}

	// Replace road with same road, should incur no cost
	{
		local old_cash = pl.get_current_cash()
		ASSERT_EQUAL(command_x.build_way(pl, start_pos, end_pos, fast_road, true), null)
		ASSERT_EQUAL(pl.get_current_cash(), old_cash)

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"........",
				"...4....",
				"...5....",
				"........",
				"...5....",
				"...1....",
				"........"
			])
	}

	// downgrade road without ctrl; should fail
	// note that we cannot use command_x.buid_way for this, because there is no way to enable
	// ctrl-pressed behaviour (the way is replaced in any case)
	{
		local old_maintenance = pl.get_current_maintenance()
		local old_cash = pl.get_current_cash()

		local tool = command_x(tool_build_way)
		ASSERT_EQUAL(tool.work(pl, start_pos, end_pos, slow_road.get_name()), null)

		ASSERT_EQUAL(tile_x(3, 6, 0).find_object(mo_way).get_desc().get_name(), fast_road.get_name())
		ASSERT_EQUAL(tile_x(3, 2, 0).find_object(mo_way).get_desc().get_name(), fast_road.get_name())
		ASSERT_EQUAL(pl.get_current_cash(), old_cash)
		ASSERT_EQUAL(pl.get_current_maintenance(), old_maintenance)

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"........",
				"...4....",
				"...5....",
				"........",
				"...5....",
				"...1....",
				"........"
			])
	}

	// downgrade road with ctrl
	{
		local tool = command_x(tool_build_way)
		tool.set_flags(2) // ctrl
		ASSERT_EQUAL(tool.work(pl, start_pos, end_pos, slow_road.get_name()), null)

		ASSERT_EQUAL(tile_x(3, 6, 0).find_object(mo_way).get_desc().get_name(), slow_road.get_name())
		ASSERT_EQUAL(tile_x(3, 2, 0).find_object(mo_way).get_desc().get_name(), slow_road.get_name())

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"........",
				"...4....",
				"...5....",
				"........",
				"...5....",
				"...1....",
				"........"
			])
	}

	// remove bridge
	ASSERT_EQUAL(remover.work(pl, start_pos, end_pos, "" + wt_road), null)
	ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(3, 6, 0)), null)
	ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(4, 6, 0)), null)
	ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(3, 3, 0)), null)
	ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(4, 3, 0)), null)

	// clean up
	ASSERT_EQUAL(pl.get_current_maintenance(), 0)
	RESET_ALL_PLAYER_FUNDS()
}


function test_way_road_cityroad_build()
{
	local public_pl = player_x(1)
	local start_pos = coord3d(3, 2, 0)
	local end_pos = coord3d(3, 6, 0)

	// build single tile -> should fail
	{
		ASSERT_EQUAL(command_x(tool_build_cityroad).work(public_pl, start_pos, start_pos, "city_road"), "")

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
		[
			"........",
			"........",
			"........",
			"........",
			"........",
			"........",
			"........",
			"........"
		])
	}

	// build city road
	{
		ASSERT_EQUAL(command_x(tool_build_cityroad).work(public_pl, start_pos, end_pos, "city_road"), null)

		for (local y = start_pos.y; y < end_pos.y; ++y) {
			local r = way_x(start_pos.x, y, start_pos.z)
			ASSERT_TRUE(r != null)
			ASSERT_TRUE(r.is_valid())
			ASSERT_TRUE(r.has_sidewalk())
			ASSERT_EQUAL(r.desc.name, "city_road")
		}

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"........",
				"...4....",
				"...5....",
				"...5....",
				"...5....",
				"...1....",
				"........"
			])
	}

	// clean up
	ASSERT_EQUAL(command_x(tool_remove_way).work(public_pl, start_pos, end_pos, "" + wt_road), null)
	RESET_ALL_PLAYER_FUNDS()
}


function test_way_road_cityroad_upgrade_with_cityroad()
{
	local public_pl = player_x(1)
	local start_pos = coord3d(3, 2, 0)
	local end_pos = coord3d(3, 6, 0)

	ASSERT_EQUAL(command_x(tool_build_cityroad).work(public_pl, start_pos, end_pos, "city_road"), null)

	// upgrade cityroad
	{
		ASSERT_EQUAL(command_x(tool_build_cityroad).work(public_pl, start_pos, end_pos, "cobblestone_road"), null)

		for (local y = start_pos.y; y < end_pos.y; ++y) {
			local r = way_x(start_pos.x, y, start_pos.z)
			ASSERT_TRUE(r != null)
			ASSERT_TRUE(r.is_valid())
			ASSERT_TRUE(r.has_sidewalk())
			ASSERT_EQUAL(r.desc.name, "city_road") // FIXME Should this not be cobblestone_road?
		}

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"........",
				"...4....",
				"...5....",
				"...5....",
				"...5....",
				"...1....",
				"........"
			])
	}

	// clean up
	ASSERT_EQUAL(command_x(tool_remove_way).work(public_pl, start_pos, end_pos, "" + wt_road), null)
	RESET_ALL_PLAYER_FUNDS()
}


function test_way_road_cityroad_downgrade_with_cityroad()
{
	local public_pl = player_x(1)
	local start_pos = coord3d(3, 2, 0)
	local end_pos = coord3d(3, 6, 0)

	ASSERT_EQUAL(command_x(tool_build_cityroad).work(public_pl, start_pos, end_pos, "cobblestone_road"), null)

	// downgrade cityroad
	{
		local builder = command_x(tool_build_cityroad)
		builder.set_flags(2)
		ASSERT_EQUAL(builder.work(public_pl, start_pos, end_pos, "city_road"), null)

		for (local y = start_pos.y; y < end_pos.y; ++y) {
			local r = way_x(start_pos.x, y, start_pos.y)
			ASSERT_TRUE(r != null)
			ASSERT_TRUE(r.is_valid())
			ASSERT_TRUE(r.has_sidewalk())
			ASSERT_EQUAL(r.desc.name, "city_road")
		}

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"........",
				"...4....",
				"...5....",
				"...5....",
				"...5....",
				"...1....",
				"........"
			])
	}

	// clean up
	ASSERT_EQUAL(command_x(tool_remove_way).work(public_pl, start_pos, end_pos, "" + wt_road), null)
	RESET_ALL_PLAYER_FUNDS()
}


function test_way_road_cityroad_replace_by_normal_road()
{
	local public_pl = player_x(1)
	local start_pos = coord3d(3, 2, 0)
	local end_pos = coord3d(3, 6, 0)

	ASSERT_EQUAL(command_x(tool_build_cityroad).work(public_pl, start_pos, end_pos, "city_road"), null)

	// replace cityroad by normal road
	{
		ASSERT_EQUAL(command_x.build_way(public_pl start_pos, end_pos, way_desc_x("cobblestone_road"), true), null)

		for (local y = start_pos.y; y < end_pos.y; ++y) {
			local r = way_x(start_pos.x, y, start_pos.z)
			ASSERT_TRUE(r != null)
			ASSERT_TRUE(r.is_valid())
			ASSERT_FALSE(r.has_sidewalk())
			ASSERT_EQUAL(r.desc.name, "cobblestone_road")
		}

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"........",
				"...4....",
				"...5....",
				"...5....",
				"...5....",
				"...1....",
				"........"
			])
	}

	// clean up
	ASSERT_EQUAL(command_x(tool_remove_way).work(public_pl, start_pos, end_pos, "" + wt_road), null)
	RESET_ALL_PLAYER_FUNDS()
}


function test_way_road_cityroad_replace_keep_existing()
{
	local public_pl = player_x(1)
	local start_pos = coord3d(3, 2, 0)
	local end_pos = coord3d(3, 6, 0)

	ASSERT_EQUAL(command_x(tool_build_cityroad).work(public_pl, start_pos, end_pos, "city_road"), null)

	// replace cityroad by normal road
	{
		local builder = command_x(tool_build_way)
		builder.set_flags(1) // enable shift -> keep city roads

		ASSERT_EQUAL(builder.work(public_pl, start_pos, end_pos, "cobblestone_road"), null)

		for (local y = start_pos.y; y < end_pos.y; ++y) {
			local r = way_x(start_pos.x, y, start_pos.z)
			ASSERT_TRUE(r != null)
			ASSERT_TRUE(r.is_valid())
			ASSERT_TRUE(r.has_sidewalk())
			ASSERT_EQUAL(r.desc.name, "city_road")
		}

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"........",
				"...4....",
				"...5....",
				"...5....",
				"...5....",
				"...1....",
				"........"
			])
	}

	// clean up
	ASSERT_EQUAL(command_x(tool_remove_way).work(public_pl, start_pos, end_pos, "" + wt_road), null)
	RESET_ALL_PLAYER_FUNDS()
}


function test_way_road_has_double_slopes()
{
	local roads = way_desc_x.get_available_ways(wt_road, st_flat)

	foreach (r in roads) {
		ASSERT_TRUE(r.has_double_slopes())
	}
}


function test_way_road_make_public()
{
	local pl = player_x(0)
	local public_pl = player_x(1)
	local wayremover = command_x(tool_remove_way)
	local road_desc  = way_desc_x.get_available_ways(wt_road, st_flat)[0]
	local makepublic = command_x(tool_make_stop_public)

	ASSERT_EQUAL(command_x.build_way(pl, coord3d(4, 2, 0), coord3d(4, 4, 0), road_desc, true), null)

	// invalid coord
	{
		local old_cash = pl.get_current_cash()
		local old_maint = pl.get_current_maintenance()

		ASSERT_EQUAL(makepublic.work(pl, coord3d(-1, -1, -1)), "No suitable ground!")

		ASSERT_EQUAL(pl.get_current_cash(), old_cash)
		ASSERT_EQUAL(pl.get_current_maintenance(), old_maint)
	}

	// nothing to make public
	{
		local old_cash = pl.get_current_cash()
		local old_maint = pl.get_current_maintenance()

		ASSERT_EQUAL(makepublic.work(pl, coord3d(3, 4, 0)), null)

		ASSERT_EQUAL(pl.get_current_cash(), old_cash)
		ASSERT_EQUAL(pl.get_current_maintenance(), old_maint)
	}

	// make road public
	{
		local old_pl_cash = pl.get_current_cash()
		local old_pl_maint = pl.get_current_maintenance()
		local old_public_cash = public_pl.get_current_cash()
		local old_public_maint = public_pl.get_current_maintenance()

		ASSERT_EQUAL(makepublic.work(pl, coord3d(4, 2, 0)), null)

		ASSERT_TRUE(way_x(4, 2, 0).get_owner() != null)
		ASSERT_EQUAL(way_x(4, 2, 0).get_owner().get_name(), public_pl.get_name())

		ASSERT_EQUAL(pl.get_current_cash()*100, old_pl_cash*100 - 60 * road_desc.get_maintenance()) // 60 == cst_make_public_months
		ASSERT_EQUAL(pl.get_current_maintenance(), old_pl_maint - road_desc.get_maintenance())

		ASSERT_EQUAL(public_pl.get_current_maintenance(), old_public_maint + road_desc.get_maintenance())
		ASSERT_EQUAL(public_pl.get_current_cash(), old_public_cash)
	}

	ASSERT_EQUAL(wayremover.work(public_pl, coord3d(4, 2, 0), coord3d(4, 4, 0), "" + wt_road), null)
	RESET_ALL_PLAYER_FUNDS()
}


function test_way_road_build_terraform_defaults_to_off()
{
	local pl        = player_x(0)
	local road_desc = way_desc_x.get_available_ways(wt_road, st_flat)[0]
	local remover   = command_x(tool_remove_way)
	local pattern   = [
		"........",
		"........",
		"...4....",
		"...5....",
		"...5....",
		"...5....",
		"...1....",
		"........"
	]

	// the omitted parameter has to build exactly what an explicit false builds
	local cash = pl.get_current_cash()
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(3, 2, 0), coord3d(3, 6, 0), road_desc, true), null)
	local price = cash - pl.get_current_cash()
	ASSERT_TRUE(price > 0)
	ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0), pattern)
	ASSERT_EQUAL(remover.work(pl, coord3d(3, 2, 0), coord3d(3, 6, 0), "" + wt_road), null)

	cash = pl.get_current_cash()
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(3, 2, 0), coord3d(3, 6, 0), road_desc, true, false), null)
	ASSERT_EQUAL(cash - pl.get_current_cash(), price)
	ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0), pattern)
	ASSERT_EQUAL(remover.work(pl, coord3d(3, 2, 0), coord3d(3, 6, 0), "" + wt_road), null)

	// the same for build_road, which keeps city roads
	cash = pl.get_current_cash()
	ASSERT_EQUAL(command_x.build_road(pl, coord3d(3, 2, 0), coord3d(3, 6, 0), road_desc, true, true), null)
	ASSERT_EQUAL(cash - pl.get_current_cash(), price)
	ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0), pattern)
	ASSERT_EQUAL(remover.work(pl, coord3d(3, 2, 0), coord3d(3, 6, 0), "" + wt_road), null)

	cash = pl.get_current_cash()
	ASSERT_EQUAL(command_x.build_road(pl, coord3d(3, 2, 0), coord3d(3, 6, 0), road_desc, true, true, false), null)
	ASSERT_EQUAL(cash - pl.get_current_cash(), price)
	ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0), pattern)
	ASSERT_EQUAL(remover.work(pl, coord3d(3, 2, 0), coord3d(3, 6, 0), "" + wt_road), null)

	ASSERT_EQUAL(pl.get_current_maintenance(), 0)
	RESET_ALL_PLAYER_FUNDS()
}


function test_way_road_build_terraform_across_slope()
{
	local pl        = player_x(0)
	local road_desc = way_desc_x.get_available_ways(wt_road, st_flat)[0]
	local remover   = command_x(tool_remove_way)

	// a slope across the way: no road can follow it
	ASSERT_EQUAL(command_x.set_slope(pl, coord3d(4, 4, 0), slope.south), null)

	local cash = pl.get_current_cash()
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(3, 4, 0), coord3d(5, 4, 0), road_desc, true), "")
	ASSERT_EQUAL(pl.get_current_cash(), cash)
	ASSERT_EQUAL(tile_x(4, 4, 0).get_slope(), slope.south)

	// the same command may change the slope now
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(3, 4, 0), coord3d(5, 4, 0), road_desc, true, true), null)
	ASSERT_TRUE(pl.get_current_cash() < cash)
	ASSERT_EQUAL(tile_x(4, 4, 0).get_slope(), slope.flat)

	ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
		[
			"........",
			"........",
			"........",
			"........",
			"...2A8..",
			"........",
			"........",
			"........"
		])

	// nothing was bridged and nothing was tunneled
	ASSERT_FALSE(tile_x(4, 4, 0).is_bridge())
	ASSERT_FALSE(tile_x(4, 4, 0).is_tunnel())
	ASSERT_TRUE(square_x(4, 4).get_tile_at_height(1) == null)

	// clean up
	ASSERT_EQUAL(remover.work(pl, coord3d(3, 4, 0), coord3d(5, 4, 0), "" + wt_road), null)
	ASSERT_EQUAL(pl.get_current_maintenance(), 0)
	RESET_ALL_PLAYER_FUNDS()
}


function test_way_road_build_road_terraform_across_slope()
{
	local pl        = player_x(0)
	local road_desc = way_desc_x.get_available_ways(wt_road, st_flat)[0]
	local remover   = command_x(tool_remove_way)

	// the same crossing turned by 90 degrees, and through build_road this time
	ASSERT_EQUAL(command_x.set_slope(pl, coord3d(4, 4, 0), slope.east), null)

	ASSERT_EQUAL(command_x.build_road(pl, coord3d(4, 3, 0), coord3d(4, 5, 0), road_desc, true, false), "")
	ASSERT_EQUAL(tile_x(4, 4, 0).get_slope(), slope.east)

	ASSERT_EQUAL(command_x.build_road(pl, coord3d(4, 3, 0), coord3d(4, 5, 0), road_desc, true, false, true), null)
	ASSERT_EQUAL(tile_x(4, 4, 0).get_slope(), slope.flat)

	ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
		[
			"........",
			"........",
			"........",
			"....4...",
			"....5...",
			"....1...",
			"........",
			"........"
		])

	ASSERT_FALSE(tile_x(4, 4, 0).is_bridge())
	ASSERT_TRUE(square_x(4, 4).get_tile_at_height(1) == null)

	// clean up
	ASSERT_EQUAL(remover.work(pl, coord3d(4, 3, 0), coord3d(4, 5, 0), "" + wt_road), null)
	ASSERT_EQUAL(pl.get_current_maintenance(), 0)
	RESET_ALL_PLAYER_FUNDS()
}


function test_way_road_build_terraform_single_step()
{
	local pl        = player_x(0)
	local road_desc = way_desc_x.get_available_ways(wt_road, st_flat)[0]
	local remover   = command_x(tool_remove_way)
	local planner   = way_planner_x(pl)
	planner.set_build_types(road_desc)

	ASSERT_EQUAL(command_x.set_slope(pl, coord3d(9, 9, 0), slope.south), null)

	// this is how the bundled ai scripts build: one step of the planned route at a time
	ASSERT_FALSE(planner.is_allowed_step(tile_x(8, 9, 0), tile_x(9, 9, 0)))
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(8, 9, 0), coord3d(9, 9, 0), road_desc, true, true), null)

	// only the corner in the way is taken down, the rest of the slope stays
	ASSERT_EQUAL(tile_x(9, 9, 0).get_slope(), slope.northeast)

	// exactly the two tiles of the step, no detour
	ASSERT_WAY_PATTERN(wt_road, coord3d(7, 8, 0),
		[
			"0000",
			"0280",
			"0000",
			"0000"
		])

	ASSERT_FALSE(tile_x(9, 9, 0).is_bridge())
	ASSERT_TRUE(square_x(9, 9).get_tile_at_height(1) == null)

	// clean up
	ASSERT_EQUAL(remover.work(pl, coord3d(8, 9, 0), coord3d(9, 9, 0), "" + wt_road), null)
	ASSERT_EQUAL(command_x.set_slope(pl, coord3d(9, 9, 0), slope.flat), null)
	ASSERT_EQUAL(pl.get_current_maintenance(), 0)
	RESET_ALL_PLAYER_FUNDS()
}


function test_way_road_build_terraform_is_no_bypass()
{
	local pl        = player_x(0)
	local road_desc = way_desc_x.get_available_ways(wt_road, st_flat)[0]

	// a whole tile one level up: both tiles are flat, so the engine refuses to terraform
	ASSERT_EQUAL(command_x.set_slope(pl, coord3d(4, 4, 0), slope.all_up_slope), null)

	local cash = pl.get_current_cash()
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(4, 2, 0), coord3d(4, 4, 1), road_desc, true), "")
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(4, 2, 0), coord3d(4, 4, 1), road_desc, true, true), "")
	ASSERT_EQUAL(pl.get_current_cash(), cash)
	ASSERT_TRUE(square_x(4, 4).get_tile_at_height(0) == null)
	ASSERT_EQUAL(tile_x(4, 4, 1).get_slope(), slope.flat)

	// clean up
	ASSERT_EQUAL(command_x.set_slope(pl, coord3d(4, 4, 1), slope.all_down_slope), null)
	ASSERT_EQUAL(pl.get_current_maintenance(), 0)
	RESET_ALL_PLAYER_FUNDS()
}


function test_way_road_build_terraform_forbidden_by_scenario()
{
	local pl        = player_x(0)
	local road_desc = way_desc_x.get_available_ways(wt_road, st_flat)[0]
	local remover   = command_x(tool_remove_way)

	ASSERT_EQUAL(command_x.set_slope(pl, coord3d(4, 4, 0), slope.south), null)

	// the way is still built by the tool, so the scenario still sees the way name
	rules.forbid_way_tool_rect(0, tool_build_way, wt_road, road_desc.get_name(), coord(3, 3), coord(5, 5), "Foo Bar")
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(3, 4, 0), coord3d(5, 4, 0), road_desc, true, true), "")
	ASSERT_EQUAL(tile_x(4, 4, 0).get_slope(), slope.south)
	rules.clear()

	ASSERT_EQUAL(command_x.build_way(pl, coord3d(3, 4, 0), coord3d(5, 4, 0), road_desc, true, true), null)
	ASSERT_EQUAL(tile_x(4, 4, 0).get_slope(), slope.flat)

	// clean up
	ASSERT_EQUAL(remover.work(pl, coord3d(3, 4, 0), coord3d(5, 4, 0), "" + wt_road), null)
	ASSERT_EQUAL(pl.get_current_maintenance(), 0)
	RESET_ALL_PLAYER_FUNDS()
}


function test_way_road_build_terraform_builds_no_bridge()
{
	local pl        = player_x(0)
	local road_desc = way_desc_x.get_available_ways(wt_road, st_flat)[0]
	local taxiway   = way_desc_x.get_available_ways(wt_air, st_flat)[0]
	local remover   = command_x(tool_remove_way)

	// is_allowed_step refuses every tile carrying an air way, so this column can only be
	// passed on a bridge, and it spans the whole map: there is nothing to go around
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(8, 0, 0), coord3d(8, 15, 0), taxiway, true), null)

	// the automatic mode picks a bridge for exactly this drag
	ASSERT_EQUAL(command_x(tool_build_way).work(pl, coord3d(6, 8, 0), coord3d(10, 8, 0), road_desc.get_name() + ",1"), null)
	ASSERT_TRUE(tile_x(7, 8, 0).find_object(mo_bridge) != null)
	ASSERT_EQUAL(remover.work(pl, coord3d(6, 8, 0), coord3d(10, 8, 0), "" + wt_road), null)

	// terraforming gets no bridge and no tunnel to fall back on, so the same drag fails
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(6, 8, 0), coord3d(10, 8, 0), road_desc, false, true), "")
	ASSERT_TRUE(tile_x(7, 8, 0).find_object(mo_bridge) == null)
	ASSERT_FALSE(tile_x(7, 8, 0).has_way(wt_road))
	ASSERT_FALSE(tile_x(8, 8, 0).is_tunnel())

	// clean up
	ASSERT_EQUAL(remover.work(pl, coord3d(8, 0, 0), coord3d(8, 15, 0), "" + wt_air), null)
	ASSERT_EQUAL(pl.get_current_maintenance(), 0)
	RESET_ALL_PLAYER_FUNDS()
}


function test_way_road_build_terraform_not_kept_by_the_tool()
{
	local pl        = player_x(0)
	local road_desc = way_desc_x.get_available_ways(wt_road, st_flat)[0]
	local remover   = command_x(tool_remove_way)
	local builder   = command_x(tool_build_way)

	ASSERT_EQUAL(command_x.set_slope(pl, coord3d(4, 4, 0), slope.south), null)
	ASSERT_EQUAL(command_x.set_slope(pl, coord3d(9, 9, 0), slope.south), null)

	// terraforming once must not leave the tool terraforming for good: the option
	// belongs to the single command, and the same instance is used for both.
	// The ctrl flag makes the drag go straight, and the tool clears it per call.
	builder.set_flags(2)
	ASSERT_EQUAL(builder.work(pl, coord3d(3, 4, 0), coord3d(5, 4, 0), road_desc.get_name() + ",2"), null)
	ASSERT_EQUAL(tile_x(4, 4, 0).get_slope(), slope.flat)

	builder.set_flags(2)
	ASSERT_EQUAL(builder.work(pl, coord3d(8, 9, 0), coord3d(10, 9, 0), road_desc.get_name()), "")
	ASSERT_EQUAL(tile_x(9, 9, 0).get_slope(), slope.south)

	// clean up
	ASSERT_EQUAL(remover.work(pl, coord3d(3, 4, 0), coord3d(5, 4, 0), "" + wt_road), null)
	ASSERT_EQUAL(command_x.set_slope(pl, coord3d(9, 9, 0), slope.flat), null)
	ASSERT_EQUAL(pl.get_current_maintenance(), 0)
	RESET_ALL_PLAYER_FUNDS()
}
