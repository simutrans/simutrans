//
// This file is part of the Simutrans project under the Artistic License.
// (see LICENSE.txt)
//


//
// Tests for building and removal of tunnels
//


function test_way_tunnel_build_straight()
{
	local digger = command_x(tool_build_tunnel)
	local remover = command_x(tool_remover)
	local default_tunnel = tunnel_desc_x.get_available_tunnels(wt_road)[0]
	local pl = player_x(0)

	ASSERT_TRUE(default_tunnel != null)

	{
		ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(3, 2, 0)), null)
		ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(4, 2, 0)), null)

		digger.set_flags(2)
		ASSERT_EQUAL(digger.work(pl, tile_x(3, 1, 0), default_tunnel.get_name()), null)

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"...0....",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........"
			])

		ASSERT_EQUAL(digger.work(pl, tile_x(3, 2, 0), default_tunnel.get_name()), null)

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"...0....",
				"...0....",
				"........",
				"........",
				"........",
				"........",
				"........"
			])

		ASSERT_EQUAL(remover.work(pl, coord3d(3, 1, 0)), null)
		ASSERT_EQUAL(remover.work(pl, coord3d(3, 2, 0)), null)

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

		digger.set_flags(0)
	}

	{
		ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(3, 3, 0)), null)
		ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(4, 3, 0)), null)

		ASSERT_EQUAL(digger.work(pl, tile_x(3, 1, 0), default_tunnel.get_name()), null)

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
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

		{
			// test tunnel object
			local t = tile_x(3, 1, 0)
			local tunnel = t.find_object(mo_tunnel)

			ASSERT_TRUE(tunnel != null)

			ASSERT_EQUAL(tunnel.get_desc().get_name(), default_tunnel.get_name())
		}
	}

	{
		ASSERT_EQUAL(digger.work(pl, tile_x(2, 2, 0), default_tunnel.get_name()), null)

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"...4....",
				"..2D....",
				"...1....",
				"........",
				"........",
				"........",
				"........"
			])

		// building with ctrl
		digger.set_flags(2)
		ASSERT_EQUAL(digger.work(pl, tile_x(4, 2, 0), default_tunnel.get_name()), null)

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"...4....",
				"..2D0...",
				"...1....",
				"........",
				"........",
				"........",
				"........"
			])

		digger.set_flags(0)

		// remove the single tunnel entrance
		ASSERT_EQUAL(remover.work(pl, coord3d(4, 2, 0)), null)

		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"...4....",
				"..2D....",
				"...1....",
				"........",
				"........",
				"........",
				"........"
			])

		// remove tunnel network (more than 2 entrances)
		// should fail without ctrl
		local err = remover.work(pl, coord3d(3, 3, 0))
		ASSERT_EQUAL(err, "This tunnel branches. You can try Control+Click to remove.")
		ASSERT_WAY_PATTERN(wt_road, coord3d(0, 0, 0),
			[
				"........",
				"...4....",
				"..2D....",
				"...1....",
				"........",
				"........",
				"........",
				"........"
			])

		remover.set_flags(2) // activate ctrl
		ASSERT_EQUAL(remover.work(pl, coord3d(3, 3, 0)), null)

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

		remover.set_flags(0) // deactivate ctrl
	}

	// clean up
	ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(3, 2, 0)), null)
	ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(3, 3, 0)), null)
	ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(4, 2, 0)), null)
	ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(4, 3, 0)), null)

	RESET_ALL_PLAYER_FUNDS()
}


function test_way_tunnel_build_up_down()
{
	local digger = command_x(tool_build_tunnel)
	local setslope = command_x.set_slope
	local remover = command_x(tool_remover)
	local default_tunnel = tunnel_desc_x.get_available_tunnels(wt_rail)[0]
	local pl = player_x(0)

	ASSERT_TRUE(default_tunnel != null)

	ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(1, 1, 0)), null)
	ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(2, 1, 0)), null)
	ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(1, 2, 0)), null)
	ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(2, 2, 0)), null)
	ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(1, 3, 0)), null)
	ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(2, 3, 0)), null)

	digger.set_flags(2) // ctrl
	ASSERT_EQUAL(digger.work(pl, coord3d(1, 0, 0), default_tunnel.get_name()), null)
	ASSERT_EQUAL(digger.work(pl, coord3d(1, 0, 0), coord3d(1, 1, 0), default_tunnel.get_name()), null)


	// invalid param
	{
		ASSERT_EQUAL(setslope(pl, coord3d(1, 1, 0), 42), "Only up and down movement in the underground!")

		ASSERT_WAY_PATTERN(wt_rail, coord3d(0, 0, 0), // no change
			[
				".4......",
				".1......",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........"
			])
	}

	// Build up: Does not work: surface in the way
	{
		ASSERT_EQUAL(setslope(pl, coord3d(1, 1, 0), slope.all_up_slope), "Tile not empty.")
		ASSERT_WAY_PATTERN(wt_rail, coord3d(0, 0, 0), // no change
			[
				".4......",
				".1......",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........"
			])
	}

	// Build down
	{
		local old_maint = pl.get_current_maintenance()
		ASSERT_EQUAL(setslope(pl, coord3d(1, 1, 0), slope.all_down_slope), null)
		ASSERT_WAY_PATTERN(wt_rail, coord3d(0, 0, 0),
			[
				".4......",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........"
			])

		ASSERT_WAY_PATTERN(wt_rail, coord3d(0, 0, -1),
			[
				"........",
				".1......",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........"
			])

		ASSERT_EQUAL(pl.get_current_maintenance(), old_maint)
	}

	// try building duble slope down, rail does not support double slopes
	{
		local old_maint = pl.get_current_maintenance()
		ASSERT_EQUAL(setslope(pl, coord3d(1, 1, -1), slope.all_down_slope), "Tile not empty.")
		ASSERT_WAY_PATTERN(wt_rail, coord3d(0, 0, 0),
			[
				".4......",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........"
			])

		ASSERT_WAY_PATTERN(wt_rail, coord3d(0, 0, -1),
			[
				"........",
				".1......",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........"
			])

		ASSERT_EQUAL(pl.get_current_maintenance(), old_maint)
	}

	ASSERT_EQUAL(digger.work(pl, coord3d(1, 1, -1), coord3d(1, 2, -1), default_tunnel.get_name()), null)

	// Build up
	{
		local old_maint = pl.get_current_maintenance()

		ASSERT_EQUAL(setslope(pl, coord3d(1, 2, -1), slope.all_up_slope), null)

		ASSERT_WAY_PATTERN(wt_rail, coord3d(0, 0, 0),
			[
				".4......",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........"
			])

		ASSERT_WAY_PATTERN(wt_rail, coord3d(0, 0, -1),
			[
				"........",
				".5......",
				".1......",
				"........",
				"........",
				"........",
				"........",
				"........"
			])

		ASSERT_EQUAL(pl.get_current_maintenance(), old_maint)
	}

	// try building double slope up, rail does not support double slopes
	{
		ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(1, 2, 1)), null)
		ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(2, 2, 1)), null)
		ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(1, 3, 1)), null)
		ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(2, 3, 1)), null)

		local old_maint = pl.get_current_maintenance()
		ASSERT_EQUAL(setslope(pl, coord3d(1, 1, 0), slope.all_up_slope), "")
		ASSERT_WAY_PATTERN(wt_rail, coord3d(0, 0, 0),
			[
				".4......",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........",
				"........"
			])

		ASSERT_WAY_PATTERN(wt_rail, coord3d(0, 0, -1),
			[
				"........",
				".5......",
				".1......",
				"........",
				"........",
				"........",
				"........",
				"........"
			])

		ASSERT_EQUAL(pl.get_current_maintenance(), old_maint)

		ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(1, 2, 2)), null)
		ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(2, 2, 2)), null)
		ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(1, 3, 2)), null)
		ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(2, 3, 2)), null)
	}

	// clean up
	ASSERT_EQUAL(command_x(tool_remover).work(pl, coord3d(1, 0, 0)), null)
	ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(1, 1, 1)), null)
	ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(2, 1, 1)), null)
	ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(1, 2, 1)), null)
	ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(2, 2, 1)), null)
	ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(1, 3, 1)), null)
	ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(2, 3, 1)), null)

	RESET_ALL_PLAYER_FUNDS()
}


function test_way_tunnel_build_above_tunnel_slope()
{
	// Tests building on the tile above the top of a tunnel slope in pak64
	// Should be allowed but, as of r11373, isn't.
	// If way_height_clearance is >= 2, this test DOES NOT APPLY.
	// FIXME: ignore this test if way_height_clearance >= 2 ?
	local pl = player_x(0)
	local default_tunnel = tunnel_desc_x.get_available_tunnels(wt_road)[0]
	local digger = command_x(tool_build_tunnel)
	local remover = command_x(tool_remover)
	local setslope = command_x.set_slope

	// Prepare area
	ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(1, 1, 1)), null)
	ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(2, 1, 1)), null)
	ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(1, 2, 1)), null)
	ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(2, 2, 1)), null)
	ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(1, 3, 1)), null)
	ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(2, 3, 1)), null)

	{
		digger.set_flags(2)
		ASSERT_EQUAL(digger.work(pl, tile_x(1, 0, 0), default_tunnel.get_name()), null)
		ASSERT_EQUAL(digger.work(pl, tile_x(1, 3, 0), default_tunnel.get_name()), null)
		digger.set_flags(0)

		ASSERT_EQUAL(digger.work(pl, tile_x(1, 0, 0), tile_x(1, 1, 0), default_tunnel.get_name()), null)
		ASSERT_EQUAL(setslope(pl, coord3d(1, 1, 0), slope.all_down_slope), null)
		ASSERT_EQUAL(setslope(pl, coord3d(1, 1, -1), slope.all_down_slope), null)
		ASSERT_EQUAL(digger.work(pl, tile_x(1, 1, -2), tile_x(1, 2, -2), default_tunnel.get_name()), null)
		ASSERT_EQUAL(setslope(pl, coord3d(1, 2, -2), slope.all_up_slope), null)

		// Now for the real test: build at z=0 above simple slope from z=-2 to z=-1, should be allowed
		ASSERT_EQUAL(digger.work(pl, tile_x(1, 3, 0), tile_x(1, 2, 0), default_tunnel.get_name()), null)
		ASSERT_EQUAL(remover.work(pl, coord3d(1, 2, 0)), null)
	}

	// Clean up
	ASSERT_EQUAL(remover.work(pl, coord3d(1, 1, -2)), null)
	ASSERT_EQUAL(remover.work(pl, coord3d(1, 2, -2)), null)
	ASSERT_EQUAL(remover.work(pl, coord3d(1, 0,  0)), null)
	ASSERT_EQUAL(remover.work(pl, coord3d(1, 3,  0)), null)
	ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(1, 1, 1)), null)
	ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(2, 1, 1)), null)
	ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(1, 2, 1)), null)
	ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(2, 2, 1)), null)
	ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(1, 3, 1)), null)
	ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(2, 3, 1)), null)

	RESET_ALL_PLAYER_FUNDS()
}


function test_way_tunnel_build_across_tunnel_slope()
{
	local pl = player_x(0)
	local default_tunnel = tunnel_desc_x.get_available_tunnels(wt_road)[0]
	local digger = command_x(tool_build_tunnel)
	local remover = command_x(tool_remover)
	local setslope = command_x.set_slope

	// Prepare area
	ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(1, 1, 1)), null)
	ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(2, 1, 1)), null)
	ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(1, 2, 1)), null)
	ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(2, 2, 1)), null)
	ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(1, 3, 1)), null)
	ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(2, 3, 1)), null)

	{
		// build lone tunnel mouths
		digger.set_flags(2)
		ASSERT_EQUAL(digger.work(pl, tile_x(1, 0, 0), default_tunnel.get_name()), null)
		ASSERT_EQUAL(digger.work(pl, tile_x(1, 3, 0), default_tunnel.get_name()), null)
		digger.set_flags(0)

		// make double slope
		ASSERT_EQUAL(digger.work(pl, tile_x(1, 0, 0), tile_x(1, 1, 0), default_tunnel.get_name()), null)
		ASSERT_EQUAL(setslope(pl, coord3d(1, 1, 0), slope.all_down_slope), null)
		ASSERT_EQUAL(setslope(pl, coord3d(1, 1, -1), slope.all_down_slope), null)

		local net_wealth = pl.get_current_net_wealth()

		// try to tunnel across
		ASSERT_EQUAL(digger.work(pl, tile_x(1, 0, 0), tile_x(1, 3, 0), default_tunnel.get_name()), null)

		// nothing should be buid here
		ASSERT_EQUAL( net_wealth, pl.get_current_net_wealth() )

		// remove lone tunnel mouth
		ASSERT_EQUAL(remover.work(pl, coord3d(1, 3,  0)), null)

		// try to build across it - should fail and not build anything since the tunnel builder
		// only builds straight tunnels with no elevation changes
		// however, the player cannot call it like this since before the find_end_pos will return an invalid coordinate
		local err = digger.work(pl, tile_x(1, 3, 0), default_tunnel.get_name())
		ASSERT_EQUAL(err, "Tunnel must start on single way!")
	}
	// clean up
	ASSERT_EQUAL(remover.work(pl, coord3d(1, 1, -2)), null)
	ASSERT_EQUAL(remover.work(pl, coord3d(1, 0,  0)), null)

	ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(1, 1, 1)), null)
	ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(2, 1, 1)), null)
	ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(1, 2, 1)), null)
	ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(2, 2, 1)), null)
	ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(1, 3, 1)), null)
	ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(2, 3, 1)), null)

	RESET_ALL_PLAYER_FUNDS()
}


function test_way_tunnel_make_public()
{
	local pl = player_x(0)
	local public_pl = player_x(1)
	local tunnel_desc = tunnel_desc_x.get_available_tunnels(wt_road)[0]
	local makepublic  = command_x(tool_make_stop_public)

	ASSERT_EQUAL(command_x.grid_raise(public_pl, coord3d(4, 3, 0)), null)
	ASSERT_EQUAL(command_x.grid_raise(public_pl, coord3d(5, 3, 0)), null)
	ASSERT_EQUAL(command_x.grid_raise(public_pl, coord3d(4, 4, 0)), null)
	ASSERT_EQUAL(command_x.grid_raise(public_pl, coord3d(5, 4, 0)), null)

	ASSERT_EQUAL(command_x(tool_build_tunnel).work(pl, coord3d(4, 2, 0), tunnel_desc.get_name()), null)

	// make tunnel portal public
	{
		local old_pl_cash = pl.get_current_cash()
		local old_pl_maint = pl.get_current_maintenance()
		local old_public_cash = public_pl.get_current_cash()
		local old_public_maint = public_pl.get_current_maintenance()

		ASSERT_EQUAL(makepublic.work(pl, coord3d(4, 2, 0)), null)

		ASSERT_TRUE(way_x(4, 2, 0).get_owner() != null)
		ASSERT_EQUAL(way_x(4, 2, 0).get_owner().get_name(), public_pl.get_name())

		ASSERT_EQUAL(pl.get_current_cash()*100, old_pl_cash*100 - 60 * tunnel_desc.get_maintenance()) // 60 == cst_make_public_months
		ASSERT_EQUAL(pl.get_current_maintenance(), old_pl_maint - tunnel_desc.get_maintenance())

		ASSERT_EQUAL(public_pl.get_current_maintenance(), old_public_maint + tunnel_desc.get_maintenance())
		ASSERT_EQUAL(public_pl.get_current_cash(), old_public_cash)
	}

	// make tunnel inside public
	{
		local old_pl_cash = pl.get_current_cash()
		local old_pl_maint = pl.get_current_maintenance()
		local old_public_cash = public_pl.get_current_cash()
		local old_public_maint = public_pl.get_current_maintenance()

		ASSERT_EQUAL(makepublic.work(pl, coord3d(4, 3, 0)), null)

		ASSERT_TRUE(way_x(4, 3, 0).get_owner() != null)
		ASSERT_EQUAL(way_x(4, 3, 0).get_owner().get_name(), public_pl.get_name())

		ASSERT_EQUAL(pl.get_current_cash()*100, old_pl_cash*100 - 60 * tunnel_desc.get_maintenance()) // 60 == cst_make_public_months
		ASSERT_EQUAL(pl.get_current_maintenance(), old_pl_maint - tunnel_desc.get_maintenance())

		ASSERT_EQUAL(public_pl.get_current_maintenance(), old_public_maint + tunnel_desc.get_maintenance())
		ASSERT_EQUAL(public_pl.get_current_cash(), old_public_cash)
	}

	// clean up
	ASSERT_EQUAL(command_x(tool_remove_way).work(public_pl, coord3d(4, 2, 0), coord3d(4, 4, 0), "" + wt_road), null)

	ASSERT_EQUAL(command_x.grid_lower(public_pl, coord3d(4, 3, 1)), null)
	ASSERT_EQUAL(command_x.grid_lower(public_pl, coord3d(5, 3, 1)), null)
	ASSERT_EQUAL(command_x.grid_lower(public_pl, coord3d(4, 4, 1)), null)
	ASSERT_EQUAL(command_x.grid_lower(public_pl, coord3d(5, 4, 1)), null)
	RESET_ALL_PLAYER_FUNDS()
}


function test_way_tunnel_build_invalid_param_type()
{
	local digger = command_x(tool_build_tunnel)
	local default_tunnel = tunnel_desc_x.get_available_tunnels(wt_road)[0]
	local pl = player_x(0)

	ASSERT_TRUE(default_tunnel != null)

	// The fourth argument is the tool's default_param and has to be a string.
	// A descriptor passed there used to be swallowed by the string conversion,
	// leaving default_param NULL, and only surfaced further down as the
	// misleading "Error during initializing tool".
	{
		local error_caught = false
		try {
			digger.work(pl, coord3d(3, 1, 0), coord3d(3, 2, 0), default_tunnel)
		}
		catch (e) {
			error_caught = true
			ASSERT_EQUAL(e, "Tool parameter must be a string or null; descriptors have to be passed as <desc>.get_name()")
		}
		ASSERT_TRUE(error_caught)
	}

	// null is a valid parameter and must pass the check: it reaches the tool,
	// which then reports its own error because no tunnel is named. A string is
	// valid too and is exercised with a real descriptor name by
	// test_way_tunnel_build_up_down and test_way_tunnel_build_above_tunnel_slope.
	{
		local error_caught = false
		try {
			digger.work(pl, coord3d(3, 1, 0), coord3d(3, 2, 0), null)
		}
		catch (e) {
			error_caught = true
			ASSERT_EQUAL(e, "Error during initializing tool")
		}
		ASSERT_TRUE(error_caught)
	}

	// Nothing was built: the check happens before the tool is initialized,
	// and a tunnel would show up as maintenance here.
	RESET_ALL_PLAYER_FUNDS()
}


// helper for the tunnel planner tests: raises (or lowers again) a one tile wide
// ridge along column @p x from @p y0 to @p y1, which gives the tile at y0-1 the
// slope a tunnel mouth needs and something to dig through
function TUNNEL_RIDGE(pl, x, y0, y1, raise)
{
	for (local gx = x; gx <= x + 1; gx++) {
		for (local gy = y0; gy <= y1 + 1; gy++) {
			if (raise) {
				ASSERT_EQUAL(command_x.grid_raise(pl, coord3d(gx, gy, 0)), null)
			}
			else {
				ASSERT_EQUAL(command_x.grid_lower(pl, coord3d(gx, gy, 1)), null)
			}
		}
	}
}


function test_way_tunnel_planner_find_end()
{
	local pl = player_x(0)
	local tunnel_desc = tunnel_desc_x.get_available_tunnels(wt_road)[0]
	local start_pos = coord3d(3, 1, 0)
	local end_pos = coord3d(3, 6, 0)

	ASSERT_TRUE(tunnel_desc != null)

	TUNNEL_RIDGE(pl, 3, 2, 5, true)

	// the planner only answers the question, it neither builds nor pays
	local cash = pl.get_current_cash()
	ASSERT_EQUAL(tunnel_planner_x.find_end(pl, start_pos, dir.south, tunnel_desc).tostring(), end_pos.tostring())
	ASSERT_EQUAL(pl.get_current_cash(), cash)
	ASSERT_EQUAL(pl.get_current_maintenance(), 0)
	ASSERT_FALSE(square_x(3, 6).get_ground_tile().is_tunnel())

	// asking again gives the same answer
	ASSERT_EQUAL(tunnel_planner_x.find_end(pl, start_pos, dir.south, tunnel_desc).tostring(), end_pos.tostring())

	// and the tunnel tool puts the far portal exactly there
	ASSERT_EQUAL(command_x(tool_build_tunnel).work(pl, start_pos, tunnel_desc.get_name()), null)
	ASSERT_TRUE(square_x(3, 6).get_ground_tile().is_tunnel())
	for (local y = 0; y < 8; y++) {
		ASSERT_EQUAL(square_x(3, y).get_ground_tile().has_way(wt_road), y == 1  ||  y == 6)
	}

	// clean up
	ASSERT_EQUAL(command_x(tool_remover).work(pl, start_pos), null)
	for (local y = 0; y < 8; y++) {
		ASSERT_FALSE(square_x(3, y).get_ground_tile().has_way(wt_road))
	}
	TUNNEL_RIDGE(pl, 3, 2, 5, false)
	ASSERT_EQUAL(pl.get_current_maintenance(), 0)
	RESET_ALL_PLAYER_FUNDS()
}


function test_way_tunnel_planner_invalid_direction()
{
	local pl = player_x(0)
	local tunnel_desc = tunnel_desc_x.get_available_tunnels(wt_road)[0]
	local start_pos = coord3d(3, 1, 0)
	local invalid = coord3d(-1, -1, -1).tostring()

	TUNNEL_RIDGE(pl, 3, 2, 5, true)

	// control: the very same start tile does have an answer
	ASSERT_EQUAL(tunnel_planner_x.find_end(pl, start_pos, dir.south, tunnel_desc).tostring(), coord3d(3, 6, 0).tostring())

	// anything but a single direction converts to a step vector of length zero
	// or to a diagonal, neither of which the native search can walk
	ASSERT_EQUAL(tunnel_planner_x.find_end(pl, start_pos, dir.none,       tunnel_desc).tostring(), invalid)
	ASSERT_EQUAL(tunnel_planner_x.find_end(pl, start_pos, dir.northsouth, tunnel_desc).tostring(), invalid)
	ASSERT_EQUAL(tunnel_planner_x.find_end(pl, start_pos, dir.eastwest,   tunnel_desc).tostring(), invalid)
	ASSERT_EQUAL(tunnel_planner_x.find_end(pl, start_pos, dir.southeast,  tunnel_desc).tostring(), invalid)
	ASSERT_EQUAL(tunnel_planner_x.find_end(pl, start_pos, dir.all,        tunnel_desc).tostring(), invalid)

	ASSERT_EQUAL(pl.get_current_maintenance(), 0)

	TUNNEL_RIDGE(pl, 3, 2, 5, false)
	RESET_ALL_PLAYER_FUNDS()
}


function test_way_tunnel_planner_rotated_map()
{
	local pl = player_x(0)
	local tunnel_desc = tunnel_desc_x.get_available_tunnels(wt_road)[0]
	local start_pos = coord3d(3, 1, 0)
	local end_pos = coord3d(3, 6, 0)

	TUNNEL_RIDGE(pl, 3, 2, 5, true)

	ASSERT_EQUAL(tunnel_planner_x.find_end(pl, start_pos, dir.south, tunnel_desc).tostring(), end_pos.tostring())

	// script coordinates and directions are relative to the orientation the
	// script started with, so the very same question must keep pointing at the
	// same tile while the world underneath turns. sroute_rotate is the test-only
	// hook that rotates the world, it is not tied to the schedule route tests.
	sroute_rotate()
	ASSERT_EQUAL(tunnel_planner_x.find_end(pl, start_pos, dir.south, tunnel_desc).tostring(), end_pos.tostring())

	// back to the original orientation, so the rest of the suite is unaffected
	sroute_rotate()
	sroute_rotate()
	sroute_rotate()
	ASSERT_EQUAL(tunnel_planner_x.find_end(pl, start_pos, dir.south, tunnel_desc).tostring(), end_pos.tostring())

	TUNNEL_RIDGE(pl, 3, 2, 5, false)
	ASSERT_EQUAL(pl.get_current_maintenance(), 0)
	RESET_ALL_PLAYER_FUNDS()
}


function test_way_tunnel_planner_no_exit()
{
	local pl = player_x(0)
	local tunnel_desc = tunnel_desc_x.get_available_tunnels(wt_road)[0]
	local invalid = coord3d(-1, -1, -1).tostring()

	// a ridge that reaches the southern border of the map: the search runs out
	// of map before it finds a place for the second portal
	TUNNEL_RIDGE(pl, 9, 2, 15, true)

	ASSERT_EQUAL(tunnel_planner_x.find_end(pl, coord3d(9, 1, 0), dir.south, tunnel_desc).tostring(), invalid)
	ASSERT_EQUAL(pl.get_current_maintenance(), 0)

	TUNNEL_RIDGE(pl, 9, 2, 15, false)
	RESET_ALL_PLAYER_FUNDS()
}


function test_way_tunnel_planner_off_map()
{
	local pl = player_x(0)
	local tunnel_desc = tunnel_desc_x.get_available_tunnels(wt_road)[0]
	local invalid = coord3d(-1, -1, -1).tostring()

	// the first step already leaves the map
	ASSERT_EQUAL(tunnel_planner_x.find_end(pl, coord3d(3, 0, 0), dir.north, tunnel_desc).tostring(), invalid)
	ASSERT_EQUAL(tunnel_planner_x.find_end(pl, coord3d(0, 3, 0), dir.west,  tunnel_desc).tostring(), invalid)
	ASSERT_EQUAL(pl.get_current_maintenance(), 0)
	RESET_ALL_PLAYER_FUNDS()
}
