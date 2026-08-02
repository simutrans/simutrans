//
// This file is part of the Simutrans project under the Artistic License.
// (see LICENSE.txt)
//

// An elevated way must not be built over a building that needs more clearance
// than the deck leaves. pak64 assets: Theatre = 2x2 drawn two levels tall,
// Tennis_Court = 2x2 drawn flat.

function test_way_elevated_over_building()
{
	local public_pl = player_x(1)

	local elevated = way_desc_x.get_available_ways(wt_monorail, st_elevated)[0]
	ASSERT_TRUE(elevated != null)

	ASSERT_EQUAL(command_x(tool_add_city).work(public_pl, coord3d(8, 8, 0), "0"), null)

	// (A) control: over empty ground the same two-tile span is allowed
	ASSERT_EQUAL(command_x.build_way(public_pl, coord3d(3, 4, 0), coord3d(4, 4, 0), elevated, true), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(public_pl, coord3d(3, 4, 1), coord3d(4, 4, 1), "" + wt_monorail), null)

	// (B) Theatre draws two levels although no tile carries a second image row,
	//     so the old has_upper_storey() test let a way through it
	ASSERT_EQUAL(command_x(tool_build_house).work(public_pl, coord3d(3, 4, 0), "1#Theatre"), null)
	ASSERT_EQUAL(command_x.build_way(public_pl, coord3d(3, 4, 0), coord3d(4, 4, 0), elevated, true), "")
	ASSERT_TRUE(square_x(3, 4).get_tile_at_height(1) == null)
	ASSERT_TRUE(square_x(4, 4).get_tile_at_height(1) == null)
	ASSERT_EQUAL(command_x(tool_remover).work(public_pl, coord3d(3, 4, 0)), null) // removes the whole 2x2

	// (C) a building that does fit below the deck stays allowed
	ASSERT_EQUAL(command_x(tool_build_house).work(public_pl, coord3d(3, 4, 0), "1#Tennis_Court"), null)
	ASSERT_EQUAL(command_x.build_way(public_pl, coord3d(3, 4, 0), coord3d(4, 4, 0), elevated, true), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(public_pl, coord3d(3, 4, 1), coord3d(4, 4, 1), "" + wt_monorail), null)
	ASSERT_EQUAL(command_x(tool_remover).work(public_pl, coord3d(3, 4, 0)), null)

	ASSERT_EQUAL(command_x(tool_remover).work(public_pl, coord3d(8, 8, 0)), null) // remove city
	ASSERT_EQUAL(command_x(tool_remove_way).work(public_pl, coord3d(7, 9, 0), coord3d(9, 9, 0), "" + wt_road), null)

	RESET_ALL_PLAYER_FUNDS()
}


function test_way_elevated_over_building_footprint()
{
	local public_pl = player_x(1)

	local elevated = way_desc_x.get_available_ways(wt_monorail, st_elevated)[0]
	ASSERT_TRUE(elevated != null)

	ASSERT_EQUAL(command_x(tool_add_city).work(public_pl, coord3d(8, 8, 0), "0"), null)

	// the far row of the 2x2 Theatre carries no anchor, and the height belongs to
	// the building and not to the tile, so crossing it must be refused as well
	ASSERT_EQUAL(command_x(tool_build_house).work(public_pl, coord3d(3, 4, 0), "1#Theatre"), null)
	ASSERT_EQUAL(command_x.build_way(public_pl, coord3d(3, 5, 0), coord3d(4, 5, 0), elevated, true), "")
	ASSERT_TRUE(square_x(3, 5).get_tile_at_height(1) == null)
	ASSERT_TRUE(square_x(4, 5).get_tile_at_height(1) == null)

	// control: the same span one tile further, off the building, is allowed
	ASSERT_EQUAL(command_x.build_way(public_pl, coord3d(3, 6, 0), coord3d(4, 6, 0), elevated, true), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(public_pl, coord3d(3, 6, 1), coord3d(4, 6, 1), "" + wt_monorail), null)

	ASSERT_EQUAL(command_x(tool_remover).work(public_pl, coord3d(3, 4, 0)), null)
	ASSERT_EQUAL(command_x(tool_remover).work(public_pl, coord3d(8, 8, 0)), null)
	ASSERT_EQUAL(command_x(tool_remove_way).work(public_pl, coord3d(7, 9, 0), coord3d(9, 9, 0), "" + wt_road), null)

	RESET_ALL_PLAYER_FUNDS()
}
