//
// This file is part of the Simutrans project under the Artistic License.
// (see LICENSE.txt)
//


//
// Tests for the scripted AI player lifecycle.
//
// A scripted AI is otherwise reachable only through the GUI: the sole caller of
// ai_scripted_t::init() is ai_selector_t::item_action(). These tests drive that same
// public init() through the test support in api_ai_test.cc, so they exercise the
// production path and not a copy of it.
//
// The load-bearing oracle is the fixture ai in tests/ai/stlab_probe, whose start()
// calls aitest_note(). It is owned by the tests, needs no gameplay tool and does not
// depend on what any shipped ai happens to do. A cheap smoke test keeps real
// coverage of the shipped sqai as well.
//

// a scripted ai player may live in slots 2 .. MAX-1; the suite itself uses 0, 1 and 2
const AI_SLOT_FIRST = 2
const AI_SLOT_LAST  = 7

const AI_FIXTURE = "stlab_probe"
const AI_MISSING = "no_such_ai_for_tests"

const AI_NAME_BEFORE_INIT = "The unknown AI player"

const AI_ERR_LOAD   = "Loading ai script failed"
const AI_ERR_POLICY = "Scripted AI can only be attached on the server"


// Picks a free player slot instead of assuming one. Never touches an occupied slot.
function find_free_ai_slot()
{
	for (local i = AI_SLOT_FIRST; i <= AI_SLOT_LAST; i++) {
		if (!player_x(i).is_valid()) {
			return i
		}
	}
	return -1
}


function make_scripted_ai()
{
	local slot = find_free_ai_slot()
	ASSERT_TRUE(slot >= AI_SLOT_FIRST)
	ASSERT_FALSE(player_x(slot).is_valid())

	ASSERT_TRUE(world.create_player(slot, 4)) // 4 == player_t::AI_SCRIPTED
	ASSERT_TRUE(player_x(slot).is_valid())
	ASSERT_FALSE(aitest_has_script(slot))
	ASSERT_EQUAL(player_x(slot).get_name(), AI_NAME_BEFORE_INIT)

	aitest_reset_notes()
	return slot
}


function drop_scripted_ai(slot)
{
	ASSERT_TRUE(world.remove_player(player_x(slot)))
	ASSERT_FALSE(player_x(slot).is_valid())
}


// The load-bearing oracle: a fixture ai loads and its start() runs.
function test_ai_scripted_fixture_start_dispatched()
{
	local slot = make_scripted_ai()

	ASSERT_EQUAL(aitest_note_count(), 0)
	ASSERT_EQUAL(aitest_attach_fixture(slot, AI_FIXTURE), null)
	ASSERT_TRUE(aitest_has_script(slot))

	// start(pl) ran inside the ai vm and reported through the test support
	ASSERT_EQUAL(aitest_note_count(), 1)
	ASSERT_EQUAL(aitest_get_note(), "start:" + slot)

	drop_scripted_ai(slot)
}


// Cheap end-to-end smoke test that the real shipped ai still loads and runs.
function test_ai_scripted_shipped_sqai_smoke()
{
	local slot = make_scripted_ai()

	ASSERT_EQUAL(aitest_attach(slot, "sqai"), null)
	ASSERT_TRUE(aitest_has_script(slot))
	// sqai renames its own player from inside start(); the engine never sets this
	ASSERT_TRUE(player_x(slot).get_name() != AI_NAME_BEFORE_INIT)

	drop_scripted_ai(slot)
}


// Negative control: attachment fails for the intended reason and nothing runs.
function test_ai_scripted_attach_missing_ai_fails()
{
	local slot = make_scripted_ai()

	// The engine logs a script error for this, which the runner would
	// otherwise read as a test having broken without saying so. Announce it,
	// so that this one line is excused and an unexpected one still fails.
	EXPECT_SCRIPT_ERROR(AI_MISSING)
	ASSERT_EQUAL(aitest_attach(slot, AI_MISSING), AI_ERR_LOAD)
	ASSERT_FALSE(aitest_has_script(slot))
	ASSERT_EQUAL(aitest_note_count(), 0)
	ASSERT_EQUAL(player_x(slot).get_name(), AI_NAME_BEFORE_INIT)

	drop_scripted_ai(slot)
}


function test_ai_scripted_attach_empty_name_fails()
{
	local slot = make_scripted_ai()

	ASSERT_EQUAL(aitest_attach(slot, ""), "No AI name given")
	ASSERT_FALSE(aitest_has_script(slot))
	ASSERT_EQUAL(aitest_note_count(), 0)

	drop_scripted_ai(slot)
}


// The test support mirrors the GUI policy (!networkmode || server) and reads the
// same two globals the dialog reads.
function test_ai_scripted_attach_network_policy()
{
	local slot = make_scripted_ai()

	// network client: refused before anything is loaded
	ASSERT_EQUAL(aitest_attach_fixture_as(true, false, slot, AI_FIXTURE), AI_ERR_POLICY)
	ASSERT_FALSE(aitest_has_script(slot))
	ASSERT_EQUAL(aitest_note_count(), 0)

	// local game: allowed
	ASSERT_EQUAL(aitest_attach_fixture_as(false, false, slot, AI_FIXTURE), null)
	ASSERT_TRUE(aitest_has_script(slot))

	drop_scripted_ai(slot)
}


// Real server state: env_t::server is a reference onto the network server port, and
// the test support sets that port rather than passing a substitute flag.
function test_ai_scripted_attach_server_succeeds()
{
	local slot = make_scripted_ai()

	ASSERT_EQUAL(aitest_attach_fixture_as(true, true, slot, AI_FIXTURE), null)
	ASSERT_TRUE(aitest_has_script(slot))

	// the vm really ran under server state, and did not suspend on a tool call
	ASSERT_EQUAL(aitest_note_count(), 1)
	ASSERT_EQUAL(aitest_get_note(), "start:" + slot)

	drop_scripted_ai(slot)
}


// The globals the policy reads are restored on every path out of the test support.
function test_ai_scripted_network_state_restored()
{
	local before = aitest_net_state()
	ASSERT_EQUAL(before, "0,0")

	local slot = make_scripted_ai()

	// success path
	ASSERT_EQUAL(aitest_attach_fixture_as(true, true, slot, AI_FIXTURE), null)
	ASSERT_EQUAL(aitest_net_state(), before)

	// policy refusal path, on a slot that already has a script
	ASSERT_EQUAL(aitest_attach_fixture_as(true, false, slot, AI_FIXTURE), AI_ERR_POLICY)
	ASSERT_EQUAL(aitest_net_state(), before)

	drop_scripted_ai(slot)

	// ordinary failure path, deep inside the attach
	slot = make_scripted_ai()
	EXPECT_SCRIPT_ERROR(AI_MISSING)
	ASSERT_EQUAL(aitest_attach_fixture_as(true, true, slot, AI_MISSING), AI_ERR_LOAD)
	ASSERT_EQUAL(aitest_net_state(), before)
	drop_scripted_ai(slot)

	// and a plain local attach still behaves as if nothing had ever been changed
	slot = make_scripted_ai()
	ASSERT_EQUAL(aitest_attach_fixture(slot, AI_FIXTURE), null)
	ASSERT_TRUE(aitest_has_script(slot))
	drop_scripted_ai(slot)
}


// Slot allocation must step over an occupied slot instead of colliding with it.
function test_ai_scripted_slot_allocation_skips_occupied()
{
	local first = find_free_ai_slot()
	ASSERT_TRUE(first >= AI_SLOT_FIRST)

	// occupy it with an ordinary player, as another test would
	ASSERT_TRUE(world.create_player(first, 1))
	ASSERT_TRUE(player_x(first).is_valid())

	// the allocator must now choose a different, genuinely free slot
	local second = find_free_ai_slot()
	ASSERT_TRUE(second >= AI_SLOT_FIRST)
	ASSERT_TRUE(second != first)
	ASSERT_FALSE(player_x(second).is_valid())

	// and the seam works on it without disturbing the occupied one
	ASSERT_TRUE(world.create_player(second, 4))
	aitest_reset_notes()
	ASSERT_EQUAL(aitest_attach_fixture(second, AI_FIXTURE), null)
	ASSERT_EQUAL(aitest_get_note(), "start:" + second)
	ASSERT_TRUE(player_x(first).is_valid())

	drop_scripted_ai(second)
	ASSERT_TRUE(world.remove_player(player_x(first)))
	ASSERT_FALSE(player_x(first).is_valid())
}
