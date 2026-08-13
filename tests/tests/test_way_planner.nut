//
// This file is part of the Simutrans project under the Artistic License.
// (see LICENSE.txt)
//


//
// Tests for way_planner_x
//


// way_count_* settings of the test map, which come from the savegame, not from simuconf.tab
const WAY_COUNT_STRAIGHT =  1
const WAY_COUNT_NO_WAY   =  3
const WAY_COUNT_SLOPE    = 10


function make_road_planner()
{
	local road = way_desc_x.get_available_ways(wt_road, st_flat)[0]
	ASSERT_TRUE(road != null)

	local planner = way_planner_x(player_x(0))
	planner.set_build_types(road)
	return planner
}


function test_way_planner_step_cost_ground()
{
	local pl = player_x(0)
	local road = way_desc_x.get_available_ways(wt_road, st_flat)[0]
	local planner = make_road_planner()
	local remover = command_x(tool_remove_way)

	local virgin = planner.get_step_cost(tile_x(2, 2, 0), tile_x(3, 2, 0))
	ASSERT_EQUAL(virgin, WAY_COUNT_NO_WAY)

	// same step, but now the target tile has a road on it
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(3, 1, 0), coord3d(3, 4, 0), road, true), null)

	local on_way = planner.get_step_cost(tile_x(2, 2, 0), tile_x(3, 2, 0))
	ASSERT_EQUAL(on_way, WAY_COUNT_STRAIGHT)

	// existing ways must be cheaper than untouched ground
	ASSERT_TRUE(on_way < virgin)

	// clean up
	ASSERT_EQUAL(remover.work(pl, tile_x(3, 1, 0), tile_x(3, 4, 0), "" + wt_road), null)

	RESET_ALL_PLAYER_FUNDS()
}


function test_way_planner_step_cost_slope()
{
	local pl = player_x(0)
	local planner = make_road_planner()

	// a slope along the direction of travel: the step stays allowed, only dearer
	ASSERT_EQUAL(command_x.set_slope(pl, coord3d(4, 4, 0), slope.south), null)

	local flat_step  = planner.get_step_cost(tile_x(4, 2, 0), tile_x(4, 3, 0))
	local slope_step = planner.get_step_cost(tile_x(4, 3, 0), tile_x(4, 4, 0))

	// both steps are onto bare ground, so only the way_slope term differs
	ASSERT_EQUAL(flat_step, WAY_COUNT_NO_WAY)
	ASSERT_EQUAL(slope_step, WAY_COUNT_NO_WAY + WAY_COUNT_SLOPE)

	// approaching the same slope from the other side costs the same
	ASSERT_EQUAL(planner.get_step_cost(tile_x(4, 5, 0), tile_x(4, 4, 0)), slope_step)

	// across the slope the way cannot follow it
	ASSERT_FALSE(planner.is_allowed_step(tile_x(3, 4, 0), tile_x(4, 4, 0)))
	ASSERT_EQUAL(planner.get_step_cost(tile_x(3, 4, 0), tile_x(4, 4, 0)), null)

	// clean up
	ASSERT_EQUAL(command_x.set_slope(pl, coord3d(4, 4, 0), slope.flat), null)

	RESET_ALL_PLAYER_FUNDS()
}


function test_way_planner_step_cost_refused()
{
	local pl = player_x(0)
	local planner = make_road_planner()
	local setclimate = command_x(tool_set_climate)

	ASSERT_EQUAL(setclimate.work(pl, coord3d(4, 4, 0), coord3d(4, 4, 0), "" + cl_water), null)
	ASSERT_TRUE(tile_x(4, 4, 0).is_water())

	// a road cannot enter water
	ASSERT_FALSE(planner.is_allowed_step(tile_x(4, 3, 0), tile_x(4, 4, 0)))
	ASSERT_EQUAL(planner.get_step_cost(tile_x(4, 3, 0), tile_x(4, 4, 0)), null)

	// control: the step before it is still priced
	ASSERT_TRUE(planner.is_allowed_step(tile_x(4, 2, 0), tile_x(4, 3, 0)))
	ASSERT_EQUAL(planner.get_step_cost(tile_x(4, 2, 0), tile_x(4, 3, 0)), WAY_COUNT_NO_WAY)

	// clean up
	ASSERT_EQUAL(setclimate.work(pl, coord3d(4, 4, 0), coord3d(4, 4, 0), "" + cl_mediterran), null)

	RESET_ALL_PLAYER_FUNDS()
}


function test_way_planner_step_cost_invalid()
{
	local planner = make_road_planner()

	// off the map: no ground, so no step to price
	ASSERT_FALSE(planner.is_allowed_step(tile_x(2, 2, 0), tile_x(40, 40, 0)))
	ASSERT_EQUAL(planner.get_step_cost(tile_x(2, 2, 0), tile_x(40, 40, 0)), null)
	ASSERT_EQUAL(planner.get_step_cost(tile_x(40, 40, 0), tile_x(2, 2, 0)), null)

	// a height with no ground falls back to the map ground, for both methods
	ASSERT_TRUE(planner.is_allowed_step(tile_x(2, 2, 5), tile_x(3, 2, 0)))
	ASSERT_EQUAL(planner.get_step_cost(tile_x(2, 2, 5), tile_x(3, 2, 0)), WAY_COUNT_NO_WAY)

	// from and to the very same tile
	ASSERT_TRUE(planner.is_allowed_step(tile_x(2, 2, 0), tile_x(2, 2, 0)))
	ASSERT_EQUAL(planner.get_step_cost(tile_x(2, 2, 0), tile_x(2, 2, 0)), WAY_COUNT_NO_WAY)

	// is_allowed_step does not enforce adjacency, and neither does get_step_cost
	ASSERT_TRUE(planner.is_allowed_step(tile_x(2, 2, 0), tile_x(7, 7, 0)))
	ASSERT_EQUAL(planner.get_step_cost(tile_x(2, 2, 0), tile_x(7, 7, 0)), WAY_COUNT_NO_WAY)

	RESET_ALL_PLAYER_FUNDS()
}


function test_way_planner_step_cost_matches_is_allowed_step()
{
	local pl = player_x(0)
	local road = way_desc_x.get_available_ways(wt_road, st_flat)[0]
	local planner = make_road_planner()
	local remover = command_x(tool_remove_way)
	local setclimate = command_x(tool_set_climate)

	// a corner of the map with a way, water and a slope in it
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(3, 1, 0), coord3d(3, 4, 0), road, true), null)
	ASSERT_EQUAL(setclimate.work(pl, coord3d(6, 6, 0), coord3d(6, 6, 0), "" + cl_water), null)
	ASSERT_EQUAL(command_x.set_slope(pl, coord3d(5, 2, 0), slope.south), null)

	// a cost must appear exactly when the step is allowed, it is the same call
	local checked = 0
	local priced  = 0

	for (local x = 1; x < 8; ++x) {
		for (local y = 1; y < 8; ++y) {
			local from = tile_x(x, y, 0)

			foreach (to in [tile_x(x + 1, y, 0), tile_x(x, y + 1, 0), tile_x(x, y, 0), tile_x(1, 7, 0)]) {
				local allowed = planner.is_allowed_step(from, to)
				local cost    = planner.get_step_cost(from, to)

				ASSERT_EQUAL(cost != null, allowed)
				if (allowed) {
					ASSERT_TRUE(cost >= 0)
					++priced
				}
				++checked
			}
		}
	}

	// both outcomes have to occur, otherwise the sweep proves nothing
	ASSERT_TRUE(priced > 0)
	ASSERT_TRUE(priced < checked)

	// clean up
	ASSERT_EQUAL(command_x.set_slope(pl, coord3d(5, 2, 0), slope.flat), null)
	ASSERT_EQUAL(setclimate.work(pl, coord3d(6, 6, 0), coord3d(6, 6, 0), "" + cl_mediterran), null)
	ASSERT_EQUAL(remover.work(pl, tile_x(3, 1, 0), tile_x(3, 4, 0), "" + wt_road), null)

	RESET_ALL_PLAYER_FUNDS()
}


function test_way_planner_unconfigured()
{
	// An unconfigured planner has no way to build, and must reject every step.
	local planner = way_planner_x(player_x(0))

	ASSERT_FALSE(planner.is_allowed_step(tile_x(2, 2, 0), tile_x(3, 2, 0)))
	ASSERT_EQUAL(planner.get_step_cost(tile_x(2, 2, 0), tile_x(3, 2, 0)), null)
}


function test_way_planner_tram_shares_road()
{
	local pl   = player_x(0)
	local road = way_desc_x.get_available_ways(wt_road, st_flat)[0]
	local tram = way_desc_x.get_available_ways(wt_rail, st_tram)[0]
	local rail = way_desc_x.get_available_ways(wt_rail, st_flat)[0]
	ASSERT_TRUE(tram != null)

	ASSERT_EQUAL(command_x.build_way(pl, coord3d(3, 1, 0), coord3d(3, 4, 0), road, true), null)

	local tram_planner = way_planner_x(pl)
	tram_planner.set_build_types(tram)
	local rail_planner = way_planner_x(pl)
	rail_planner.set_build_types(rail)

	// a tram runs along the road it shares, a normal track has to cross it
	ASSERT_EQUAL(tram_planner.get_step_cost(tile_x(3, 2, 0), tile_x(3, 3, 0)), WAY_COUNT_NO_WAY + WAY_COUNT_STRAIGHT)
	ASSERT_FALSE(rail_planner.is_allowed_step(tile_x(3, 2, 0), tile_x(3, 3, 0)))

	local remover = command_x(tool_remove_way)
	ASSERT_EQUAL(remover.work(pl, tile_x(3, 1, 0), tile_x(3, 4, 0), "" + wt_road), null)

	RESET_ALL_PLAYER_FUNDS()
}


function test_way_planner_elevated_passes_over_road()
{
	local pl       = player_x(0)
	local road     = way_desc_x.get_available_ways(wt_road, st_flat)[0]
	local elevated = way_desc_x.get_available_ways(wt_monorail, st_elevated)[0]
	local flat     = way_desc_x.get_available_ways(wt_monorail, st_flat)[0]
	ASSERT_TRUE(elevated != null)

	ASSERT_EQUAL(command_x.build_way(pl, coord3d(3, 1, 0), coord3d(3, 4, 0), road, true), null)

	local high = way_planner_x(pl)
	high.set_build_types(elevated)
	local low = way_planner_x(pl)
	low.set_build_types(flat)

	// the elevated way passes above the road, the flat way of the same type cannot
	ASSERT_EQUAL(high.get_step_cost(tile_x(2, 2, 0), tile_x(3, 2, 0)), WAY_COUNT_NO_WAY)
	ASSERT_FALSE(low.is_allowed_step(tile_x(2, 2, 0), tile_x(3, 2, 0)))

	local remover = command_x(tool_remove_way)
	ASSERT_EQUAL(remover.work(pl, tile_x(3, 1, 0), tile_x(3, 4, 0), "" + wt_road), null)

	RESET_ALL_PLAYER_FUNDS()
}


function test_way_planner_runway_is_not_elevated()
{
	local pl    = player_x(0)
	local taxi  = way_desc_x.get_available_ways(wt_air, st_flat)[0]
	local rway  = way_desc_x.get_available_ways(wt_air, st_runway)[0]
	ASSERT_TRUE(rway != null)

	// st_runway and st_elevated are the same value, so a runway must stay a flat air way
	ASSERT_EQUAL(command_x.build_way(pl, coord3d(6, 1, 0), coord3d(6, 4, 0), taxi, true), null)

	local planner = way_planner_x(pl)
	planner.set_build_types(rway)
	ASSERT_TRUE(planner.is_allowed_step(tile_x(6, 2, 0), tile_x(6, 3, 0)))

	local remover = command_x(tool_remove_way)
	ASSERT_EQUAL(remover.work(pl, tile_x(6, 1, 0), tile_x(6, 4, 0), "" + wt_air), null)

	RESET_ALL_PLAYER_FUNDS()
}
