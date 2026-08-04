//
// This file is part of the Simutrans project under the Artistic License.
// (see LICENSE.txt)
//


//
// Maintenance bookkeeping when a bridge is built over a way that is already there.
//
// A way sitting on a bridge tile is meant to cost nothing - the bridge descriptor's own
// maintenance covers the structure. bridge_builder_t::remove() implements that by dropping
// the owner of the way on every bridge tile instead of refunding it, and the ways the
// bridge builder creates itself are booked to nobody, so the two halves match.
//
// A way that was ALREADY on the tile is booked to its owner, and the bridge adopts it. If
// that charge is not stopped when the bridge takes the tile, it is never given back: the
// removal has nothing to refund it from. The residue is one way's maintenance per bridge
// head, and it survives on a player who owns no object anywhere on the map.
//
// These measure the net, not a particular amount, so they hold for any pakset.
//

const BM_ROW  = 8   // the row everything is built along
const BM_W1   = 6   // plain road, west
const BM_W2   = 7   // west bridge head
const BM_E1   = 9   // east bridge head
const BM_E2   = 10  // plain road, east


function BM_ROAD()
{
	// slowest available road: any bridge of this pak can carry it
	local best = null
	foreach (w in way_desc_x.get_available_ways(wt_road, st_flat)) {
		if (best == null  ||  w.get_topspeed() < best.get_topspeed()) { best = w }
	}
	return best
}


function BM_BRIDGE(waytype, road)
{
	local best = null
	foreach (b in bridge_desc_x.get_available_bridges(waytype)) {
		if (b.get_topspeed() >= road.get_topspeed()  &&  (best == null  ||  b.get_topspeed() < best.get_topspeed())) {
			best = b
		}
	}
	return best
}


function BM_CLEAR(pl, waytype)
{
	command_x(tool_remove_way).work(pl, coord3d(BM_W1, BM_ROW, 0), coord3d(BM_E2, BM_ROW, 0), "" + waytype)
	for (local x = BM_W1; x <= BM_E2; x++) {
		ASSERT_FALSE(tile_x(x, BM_ROW, 0).has_way(waytype))
	}
}


// Lay the two approaches, leaving the middle tile free for the span. Built as two drags so
// nothing is placed on the tile the bridge will cross.
function BM_BUILD_APPROACHES(pl, way)
{
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(BM_W1, BM_ROW, 0), coord3d(BM_W2, BM_ROW, 0), way, true), null)
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(BM_E1, BM_ROW, 0), coord3d(BM_E2, BM_ROW, 0), way, true), null)
}


//
// The defect itself: a bridge whose two heads land on ways that were already built.
//
function test_way_bridge_maintenance_over_existing_way()
{
	local pl     = player_x(0)
	local road   = BM_ROAD()
	local bridge = BM_BRIDGE(wt_road, road)
	ASSERT_TRUE(road != null)
	ASSERT_TRUE(bridge != null)

	local before = pl.get_current_maintenance()

	BM_BUILD_APPROACHES(pl, road)
	ASSERT_EQUAL(command_x.build_bridge(pl, coord3d(BM_W2, BM_ROW, 0), coord3d(BM_E1, BM_ROW, 0), bridge), null)

	// it really is a bridge, on both heads - otherwise a net of zero would prove nothing
	ASSERT_TRUE(tile_x(BM_W2, BM_ROW, 0).find_object(mo_bridge) != null)
	ASSERT_TRUE(tile_x(BM_E1, BM_ROW, 0).find_object(mo_bridge) != null)

	BM_CLEAR(pl, wt_road)

	ASSERT_EQUAL(pl.get_current_maintenance(), before)
	RESET_ALL_PLAYER_FUNDS()
}


//
// The control: the same bridge with nothing underneath it beforehand. This path was always
// balanced, because the bridge builder makes those ways itself and books them to nobody.
// It is here so a future change cannot fix one half by breaking the other.
//
function test_way_bridge_maintenance_bare_ground()
{
	local pl     = player_x(0)
	local road   = BM_ROAD()
	local bridge = BM_BRIDGE(wt_road, road)

	local before = pl.get_current_maintenance()

	ASSERT_EQUAL(command_x.build_bridge(pl, coord3d(BM_W2, BM_ROW, 0), coord3d(BM_E1, BM_ROW, 0), bridge), null)
	ASSERT_TRUE(tile_x(BM_W2, BM_ROW, 0).find_object(mo_bridge) != null)

	BM_CLEAR(pl, wt_road)

	ASSERT_EQUAL(pl.get_current_maintenance(), before)
	RESET_ALL_PLAYER_FUNDS()
}


//
// While the bridge stands, the ways on its head tiles must cost nothing. This pins the
// rule rather than the net: building the bridge over the approaches has to GIVE BACK the
// maintenance of the two tiles it takes over, so the total is lower than road + bridges.
//
function test_way_bridge_maintenance_heads_are_free()
{
	local pl     = player_x(0)
	local road   = BM_ROAD()
	local bridge = BM_BRIDGE(wt_road, road)

	local before = pl.get_current_maintenance()

	BM_BUILD_APPROACHES(pl, road)
	local with_road = pl.get_current_maintenance()
	// four tiles of road were laid
	local per_tile = (with_road - before) / 4
	ASSERT_TRUE(per_tile > 0)

	ASSERT_EQUAL(command_x.build_bridge(pl, coord3d(BM_W2, BM_ROW, 0), coord3d(BM_E1, BM_ROW, 0), bridge), null)
	local with_bridge = pl.get_current_maintenance()

	// the two head tiles stopped costing, so the rise is the three bridge tiles minus them
	local rise = with_bridge - with_road
	ASSERT_EQUAL(rise, 3 * bridge.get_maintenance() - 2 * per_tile)

	BM_CLEAR(pl, wt_road)
	ASSERT_EQUAL(pl.get_current_maintenance(), before)
	RESET_ALL_PLAYER_FUNDS()
}


//
// Building and removing the same structure repeatedly must not accumulate anything. One
// pass hides a residue that is smaller than the reader's attention; three do not.
//
function test_way_bridge_maintenance_repeat()
{
	local pl     = player_x(0)
	local road   = BM_ROAD()
	local bridge = BM_BRIDGE(wt_road, road)

	local before = pl.get_current_maintenance()

	for (local i = 0; i < 3; i++) {
		BM_BUILD_APPROACHES(pl, road)
		ASSERT_EQUAL(command_x.build_bridge(pl, coord3d(BM_W2, BM_ROW, 0), coord3d(BM_E1, BM_ROW, 0), bridge), null)
		BM_CLEAR(pl, wt_road)
		ASSERT_EQUAL(pl.get_current_maintenance(), before)
	}

	RESET_ALL_PLAYER_FUNDS()
}


//
// A refused bridge must leave the books exactly as they were. The refusal used here is a
// span across an existing bridge head, which test_way_bridge_build_ground already
// establishes is rejected - and rejecting it is decided before anything is placed.
//
function test_way_bridge_maintenance_failed_build()
{
	local pl     = player_x(0)
	local road   = BM_ROAD()
	local bridge = BM_BRIDGE(wt_road, road)

	local start = pl.get_current_maintenance()

	BM_BUILD_APPROACHES(pl, road)
	ASSERT_EQUAL(command_x.build_bridge(pl, coord3d(BM_W2, BM_ROW, 0), coord3d(BM_E1, BM_ROW, 0), bridge), null)
	local before = pl.get_current_maintenance()

	// perpendicular span straight across the western head
	ASSERT_EQUAL(command_x.build_bridge(pl, coord3d(BM_W2, BM_ROW - 1, 0), coord3d(BM_W2, BM_ROW + 1, 0), bridge), "")
	ASSERT_FALSE(tile_x(BM_W2, BM_ROW - 1, 0).has_way(wt_road))

	ASSERT_EQUAL(pl.get_current_maintenance(), before)

	BM_CLEAR(pl, wt_road)
	ASSERT_EQUAL(pl.get_current_maintenance(), start)
	RESET_ALL_PLAYER_FUNDS()
}


//
// The charge and the refund have to belong to the same player. Player 1 is the public
// player and carries infrastructure of its own, so a second human player is created.
//
function test_way_bridge_maintenance_owner()
{
	world.create_player(2, 1)
	local pl     = player_x(2)
	local other  = player_x(0)
	ASSERT_TRUE(pl.is_valid())

	local road   = BM_ROAD()
	local bridge = BM_BRIDGE(wt_road, road)

	local before       = pl.get_current_maintenance()
	local other_before = other.get_current_maintenance()

	BM_BUILD_APPROACHES(pl, road)
	ASSERT_EQUAL(command_x.build_bridge(pl, coord3d(BM_W2, BM_ROW, 0), coord3d(BM_E1, BM_ROW, 0), bridge), null)

	// the builder pays, and nobody else moves
	ASSERT_TRUE(pl.get_current_maintenance() > before)
	ASSERT_EQUAL(other.get_current_maintenance(), other_before)

	BM_CLEAR(pl, wt_road)

	ASSERT_EQUAL(pl.get_current_maintenance(), before)
	ASSERT_EQUAL(other.get_current_maintenance(), other_before)
	RESET_ALL_PLAYER_FUNDS()
}


//
// Rail runs through the same bridge_builder_t code, so the same hole is reachable from it.
//
function test_way_bridge_maintenance_rail()
{
	local pl = player_x(0)

	local track = null
	foreach (w in way_desc_x.get_available_ways(wt_rail, st_flat)) {
		if (track == null  ||  w.get_topspeed() < track.get_topspeed()) { track = w }
	}
	local bridge = BM_BRIDGE(wt_rail, track)
	ASSERT_TRUE(track != null)
	ASSERT_TRUE(bridge != null)

	local before = pl.get_current_maintenance()

	BM_BUILD_APPROACHES(pl, track)
	ASSERT_EQUAL(command_x.build_bridge(pl, coord3d(BM_W2, BM_ROW, 0), coord3d(BM_E1, BM_ROW, 0), bridge), null)
	ASSERT_TRUE(tile_x(BM_W2, BM_ROW, 0).find_object(mo_bridge) != null)

	BM_CLEAR(pl, wt_rail)

	ASSERT_EQUAL(pl.get_current_maintenance(), before)
	RESET_ALL_PLAYER_FUNDS()
}
