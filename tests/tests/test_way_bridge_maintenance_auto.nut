//
// This file is part of the Simutrans project under the Artistic License.
// (see LICENSE.txt)
//


//
// The obstacle is a taxiway: is_allowed_step() refuses any tile carrying an air_wt way
// before it looks at slopes, so an ordinary road_desc cannot cross one on flat ground, while a
// bridge over a taxiway is legal - both halves are already established by
// test_way_bridge_build_above_runway.
// BEWARE: a runway cannot be bridged!
//


function BMA_BUILD_BARRIER(pl)
{
	local channel = way_desc_x.get_available_ways(wt_air, st_flat)[0]
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(8, 0, 0), coord3d(8, 15, 0), channel, true), null)
}


function BMA_REMOVE_BARRIER(pl)
{
	command_x(tool_remove_way).work(pl, coord3d(8, 0, 0), coord3d(8, 15, 0), "" + wt_air)
	ASSERT_FALSE(tile_x(8, 8, 0).has_way(wt_air))
}


function BMA_CLEAR_ROW(pl)
{
	command_x(tool_remove_way).work(pl, coord3d(6, 8, 0), coord3d(10, 8, 0), "" + wt_road)
	for (local x = 6; x <= 10; x++) {
		ASSERT_FALSE(tile_x(x, 8, 0).has_way(wt_road))
	}
}


//
// An automatic drag that spans the barrier, then removes everything, must leave the books
// where it found them.
//
function test_way_bridge_maintenance_auto()
{
	local pl   = player_x(0)
	local bridge_desc = bridge_desc_x.get_available_bridges(wt_road)[0]

	// slowest available road_desc: any bridge of this pak can carry it
	local road_desc = null
	foreach (w in way_desc_x.get_available_ways(wt_road, st_flat)) {
		if (road_desc == null  ||  w.get_topspeed() < road_desc.get_topspeed()) {
			road_desc = w 
		}
	}

	local before = pl.get_current_maintenance()

	BMA_BUILD_BARRIER(pl)
	local with_barrier = pl.get_current_maintenance()

	ASSERT_EQUAL(command_x(tool_build_way).work(pl, coord3d(6, 8, 0), coord3d(10, 8, 0), road_desc.get_name() + ",a"), null)

	// a bridge really was inserted: no road_desc on the blocked column, a bridge on each side
	ASSERT_FALSE(tile_x(8, 8, 0).has_way(wt_road))
	ASSERT_TRUE(tile_x(8 - 1, 8, 0).find_object(mo_bridge) != null)
	ASSERT_TRUE(tile_x(8 + 1, 8, 0).find_object(mo_bridge) != null)

	// build a bridge with given desc
	ASSERT_EQUAL(command_x(tool_build_way).work(pl, coord3d(6, 8, 0), coord3d(10, 8, 0), road_desc.get_name() + ",,0," + bridge_desc.get_name()), null)

	// a bridge really was inserted: no road_desc on the blocked column, a bridge on each side
	ASSERT_FALSE(tile_x(8, 8, 0).has_way(wt_road))
	ASSERT_TRUE(tile_x(8 - 1, 8, 0).find_object(mo_bridge) != null)
	ASSERT_TRUE(tile_x(8 + 1, 8, 0).find_object(mo_bridge) != null)

	BMA_CLEAR_ROW(pl)
	ASSERT_EQUAL(pl.get_current_maintenance(), with_barrier)

	BMA_REMOVE_BARRIER(pl)
	ASSERT_EQUAL(pl.get_current_maintenance(), before)
	RESET_ALL_PLAYER_FUNDS()
}


//
// A drag with the mode off builds nothing and charges nothing.
//
function test_way_bridge_maintenance_auto_off()
{
	local pl   = player_x(0)
	local road_desc = way_desc_x.get_available_ways(wt_road, st_flat)[0]

	BMA_BUILD_BARRIER(pl)
	local before = pl.get_current_maintenance()

	ASSERT_EQUAL(command_x(tool_build_way).work(pl, coord3d(6, 8, 0), coord3d(10, 8, 0), road_desc.get_name()), "")

	ASSERT_FALSE(tile_x(8, 8, 0).has_way(wt_road))
	ASSERT_TRUE(tile_x(8 - 1, 8, 0).find_object(mo_bridge) == null)

	BMA_CLEAR_ROW(pl)
	ASSERT_EQUAL(pl.get_current_maintenance(), before)

	BMA_REMOVE_BARRIER(pl)
	RESET_ALL_PLAYER_FUNDS()
}
