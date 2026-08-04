//
// This file is part of the Simutrans project under the Artistic License.
// (see LICENSE.txt)
//


//
// The same maintenance balance, reached through the way tool's automatic bridge mode.
//
// way_builder_t::build() lays the ordinary way over the whole route first and only then
// calls build_tunnel_and_bridges(), so the two tiles that become bridge heads always carry
// a way that is already booked. The automatic path therefore meets the adoption case on
// every single drag, where a player has to build the road first to meet it at all.
//
// The mode is a local preference that no scenario script can set. What is driven here is
// the "<way>,<0|1>" option suffix of tool_build_way_t, which init() has always parsed.
//
// The obstacle is a taxiway: is_allowed_step() refuses any tile carrying an air_wt way
// before it looks at slopes, so an ordinary road cannot cross one on flat ground, while a
// bridge over a taxiway is legal - both halves are already established by
// test_way_bridge_build_above_runway.
//

const BMA_BARRIER_X = 8
const BMA_ROW       = 8
const BMA_WEST      = 6
const BMA_EAST      = 10


function BMA_BUILD_BARRIER(pl)
{
	local taxiway = way_desc_x.get_available_ways(wt_air, st_flat)[0]
	ASSERT_TRUE(taxiway != null)
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(BMA_BARRIER_X, 0, 0), coord3d(BMA_BARRIER_X, 15, 0), taxiway, true), null)
}


function BMA_REMOVE_BARRIER(pl)
{
	command_x(tool_remove_way).work(pl, coord3d(BMA_BARRIER_X, 0, 0), coord3d(BMA_BARRIER_X, 15, 0), "" + wt_air)
	ASSERT_FALSE(tile_x(BMA_BARRIER_X, BMA_ROW, 0).has_way(wt_air))
}


function BMA_CLEAR_ROW(pl)
{
	command_x(tool_remove_way).work(pl, coord3d(BMA_WEST, BMA_ROW, 0), coord3d(BMA_EAST, BMA_ROW, 0), "" + wt_road)
	for (local x = BMA_WEST; x <= BMA_EAST; x++) {
		ASSERT_FALSE(tile_x(x, BMA_ROW, 0).has_way(wt_road))
	}
}


//
// An automatic drag that spans the barrier, then removes everything, must leave the books
// where it found them.
//
function test_way_bridge_maintenance_auto()
{
	local pl   = player_x(0)
	local road = BM_ROAD()

	local before = pl.get_current_maintenance()

	BMA_BUILD_BARRIER(pl)
	local with_barrier = pl.get_current_maintenance()

	ASSERT_EQUAL(command_x(tool_build_way).work(pl, coord3d(BMA_WEST, BMA_ROW, 0), coord3d(BMA_EAST, BMA_ROW, 0), road.get_name() + ",1"), null)

	// a bridge really was inserted: no road on the blocked column, a bridge on each side
	ASSERT_FALSE(tile_x(BMA_BARRIER_X, BMA_ROW, 0).has_way(wt_road))
	ASSERT_TRUE(tile_x(BMA_BARRIER_X - 1, BMA_ROW, 0).find_object(mo_bridge) != null)
	ASSERT_TRUE(tile_x(BMA_BARRIER_X + 1, BMA_ROW, 0).find_object(mo_bridge) != null)

	BMA_CLEAR_ROW(pl)
	ASSERT_EQUAL(pl.get_current_maintenance(), with_barrier)

	BMA_REMOVE_BARRIER(pl)
	ASSERT_EQUAL(pl.get_current_maintenance(), before)
	RESET_ALL_PLAYER_FUNDS()
}


//
// The automatic structure and the hand-built one over the same geometry must cost the same
// while they stand, and both must come back to the same zero. If they ever diverge again,
// one of the two paths has stopped booking what the other books.
//
function test_way_bridge_maintenance_auto_equals_manual()
{
	local pl     = player_x(0)
	local road   = BM_ROAD()
	local bridge = BM_BRIDGE(wt_road, road)

	BMA_BUILD_BARRIER(pl)
	local with_barrier = pl.get_current_maintenance()

	// automatic
	ASSERT_EQUAL(command_x(tool_build_way).work(pl, coord3d(BMA_WEST, BMA_ROW, 0), coord3d(BMA_EAST, BMA_ROW, 0), road.get_name() + ",1"), null)
	local automatic = pl.get_current_maintenance()
	BMA_CLEAR_ROW(pl)
	ASSERT_EQUAL(pl.get_current_maintenance(), with_barrier)

	// the same thing by hand: the two approaches, then the span
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(BMA_WEST, BMA_ROW, 0), coord3d(BMA_BARRIER_X - 1, BMA_ROW, 0), road, true), null)
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(BMA_BARRIER_X + 1, BMA_ROW, 0), coord3d(BMA_EAST, BMA_ROW, 0), road, true), null)
	ASSERT_EQUAL(command_x.build_bridge(pl, coord3d(BMA_BARRIER_X - 1, BMA_ROW, 0), coord3d(BMA_BARRIER_X + 1, BMA_ROW, 0), bridge), null)
	local manual = pl.get_current_maintenance()

	ASSERT_EQUAL(automatic, manual)

	BMA_CLEAR_ROW(pl)
	ASSERT_EQUAL(pl.get_current_maintenance(), with_barrier)

	BMA_REMOVE_BARRIER(pl)
	RESET_ALL_PLAYER_FUNDS()
}


//
// A drag with the mode off builds nothing and charges nothing.
//
function test_way_bridge_maintenance_auto_off()
{
	local pl   = player_x(0)
	local road = BM_ROAD()

	BMA_BUILD_BARRIER(pl)
	local before = pl.get_current_maintenance()

	command_x(tool_build_way).work(pl, coord3d(BMA_WEST, BMA_ROW, 0), coord3d(BMA_EAST, BMA_ROW, 0), road.get_name() + ",0")

	ASSERT_FALSE(tile_x(BMA_BARRIER_X, BMA_ROW, 0).has_way(wt_road))
	ASSERT_TRUE(tile_x(BMA_BARRIER_X - 1, BMA_ROW, 0).find_object(mo_bridge) == null)

	BMA_CLEAR_ROW(pl)
	ASSERT_EQUAL(pl.get_current_maintenance(), before)

	BMA_REMOVE_BARRIER(pl)
	RESET_ALL_PLAYER_FUNDS()
}
