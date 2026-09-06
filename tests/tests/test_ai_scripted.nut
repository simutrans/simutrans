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
// The oracle is deliberately stronger than "a player exists". sqai renames its own
// player from inside its start(pl) callback (ai/sqai/ai.nut), through the public
// script api. Neither name the engine assigns can survive that, so a name that is
// neither of them proves the script was loaded and its callback dispatched.
//
// Slot 3 is used because the rest of the suite only ever touches slots 0, 1 and 2,
// which keeps these tests independent of the order the suite runs in.
//

const AI_SLOT = 3

// the name ai_scripted_t's constructor gives the player
const AI_NAME_BEFORE_INIT = "The unknown AI player"
// the name ai_scripted_t::init() gives it, "player <nr-1>"
const AI_NAME_AFTER_INIT = "player 2"

// a directory that must not exist under simutrans/ai/
const AI_MISSING = "no_such_ai_for_tests"

// the error ai_scripted_t::init() returns when the script file cannot be loaded
const AI_ERR_LOAD = "Loading ai script failed"
// the error the test support returns when the GUI network policy forbids attaching
const AI_ERR_POLICY = "Scripted AI can only be attached on the server"


function make_scripted_ai_slot()
{
	ASSERT_FALSE(player_x(AI_SLOT).is_valid())
	ASSERT_TRUE(world.create_player(AI_SLOT, 4)) // 4 == player_t::AI_SCRIPTED
	ASSERT_TRUE(player_x(AI_SLOT).is_valid())
	ASSERT_FALSE(aitest_has_script(AI_SLOT))
	ASSERT_EQUAL(player_x(AI_SLOT).get_name(), AI_NAME_BEFORE_INIT)
}


function drop_scripted_ai_slot()
{
	ASSERT_TRUE(world.remove_player(player_x(AI_SLOT)))
	ASSERT_FALSE(player_x(AI_SLOT).is_valid())
}


// A real shipped AI attaches and its start() callback runs.
function test_ai_scripted_attach_starts_shipped_ai()
{
	make_scripted_ai_slot()

	ASSERT_EQUAL(aitest_attach(AI_SLOT, "sqai"), null)
	ASSERT_TRUE(aitest_has_script(AI_SLOT))

	// sqai's start(pl) renamed the player. Only the script can have done this.
	local name = player_x(AI_SLOT).get_name()
	ASSERT_TRUE(name != AI_NAME_BEFORE_INIT)
	ASSERT_TRUE(name != AI_NAME_AFTER_INIT)

	drop_scripted_ai_slot()
}


// Negative control. Attachment must fail for the intended reason, leave no script
// behind, and leave the player name untouched - the same observable the positive
// test relies on, so a seam that silently attached would fail here.
function test_ai_scripted_attach_missing_ai_fails()
{
	make_scripted_ai_slot()

	ASSERT_EQUAL(aitest_attach(AI_SLOT, AI_MISSING), AI_ERR_LOAD)
	ASSERT_FALSE(aitest_has_script(AI_SLOT))
	ASSERT_EQUAL(player_x(AI_SLOT).get_name(), AI_NAME_BEFORE_INIT)

	drop_scripted_ai_slot()
}


// An empty name is refused before anything is loaded.
function test_ai_scripted_attach_empty_name_fails()
{
	make_scripted_ai_slot()

	ASSERT_EQUAL(aitest_attach(AI_SLOT, ""), "No AI name given")
	ASSERT_FALSE(aitest_has_script(AI_SLOT))
	ASSERT_EQUAL(player_x(AI_SLOT).get_name(), AI_NAME_BEFORE_INIT)

	drop_scripted_ai_slot()
}


// The test support mirrors the GUI policy (!networkmode || server): the AI selector
// is offered on a local game and on the server, never on a network client.
function test_ai_scripted_attach_network_policy()
{
	make_scripted_ai_slot()

	// network client: refused by the policy, before anything is loaded
	ASSERT_EQUAL(aitest_attach_as(true, false, AI_SLOT, "sqai"), AI_ERR_POLICY)
	ASSERT_FALSE(aitest_has_script(AI_SLOT))
	ASSERT_EQUAL(player_x(AI_SLOT).get_name(), AI_NAME_BEFORE_INIT)

	// server: the policy lets the call through, so the refusal comes from the
	// loader instead. A missing AI is used on purpose - a real attachment here
	// would run the AI's first tool call under networkmode and suspend its vm.
	ASSERT_EQUAL(aitest_attach_as(true, true, AI_SLOT, AI_MISSING), AI_ERR_LOAD)
	ASSERT_FALSE(aitest_has_script(AI_SLOT))

	// local game: allowed, and it really attaches
	ASSERT_EQUAL(aitest_attach_as(false, false, AI_SLOT, "sqai"), null)
	ASSERT_TRUE(aitest_has_script(AI_SLOT))

	drop_scripted_ai_slot()
}
