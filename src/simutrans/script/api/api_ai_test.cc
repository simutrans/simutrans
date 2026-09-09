/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

/** @file api_ai_test.cc
 *
 * TEST SUPPORT ONLY - not part of the public Script API.
 *
 * Deliberately absent from documentation/DoxyfileSQAPI.in, following the same
 * pattern as api_schedule_route_test.cc.
 *
 * A scripted AI player can otherwise only be given its script by the GUI: the sole
 * caller of ai_scripted_t::init() is ai_selector_t::item_action(). That leaves the
 * Script AI lifecycle without automated coverage. This module supplies the missing
 * caller and nothing else. It drives the same public init() the dialog drives, so
 * the tests exercise the production path rather than a copy of it.
 *
 * The network policy is the dialog's own: gui/player_frame.cc offers the AI selector
 * only when (!env_t::networkmode || env_t::server), and attach_impl() applies exactly
 * that condition to those globals rather than to a copy of their values.
 *
 * Everything is exported to scenarios only, with one exception: aitest_note() is also
 * reachable from an ai vm, because the object under test *is* an ai vm and has to be
 * able to report that its callback ran. It only records a string.
 */

#include "api.h"

#include "../api_function.h"

#include "../../dataobj/environment.h"
#include "../../dataobj/scenario.h"
#include "../../player/ai_scripted.h"
#include "../../player/simplay.h"
#include "../../simconst.h"
#include "../../utils/cbuffer.h"
#include "../../utils/plainstring.h"
#include "../../world/simworld.h"

/// env_t::server is a read-only reference onto this
extern uint16 network_server_port;

using namespace script_api;


/// the port a test claims when it asks to be seen as a server
#define AITEST_SERVER_PORT (13353)


/**
 * Saves the two globals the attach policy reads and puts them back on every path out
 * of the call - success, refusal, early return. Squirrel code never has to restore
 * c++ state, and no world step can run while they are changed, because the whole
 * exchange happens inside one native call.
 */
class aitest_net_state_t
{
	bool   saved_networkmode;
	uint16 saved_server_port;

public:
	aitest_net_state_t() :
		saved_networkmode(env_t::networkmode),
		saved_server_port(network_server_port)
	{ }

	void set(bool networkmode, bool server)
	{
		env_t::networkmode  = networkmode;
		network_server_port = server ? AITEST_SERVER_PORT : 0;
	}

	~aitest_net_state_t()
	{
		env_t::networkmode  = saved_networkmode;
		network_server_port = saved_server_port;
	}
};


/// last string a fixture ai reported, and how many were reported
static plainstring aitest_note_text;
static uint32      aitest_note_calls = 0;


/**
 * Resolves a player slot to a scripted AI player.
 * @returns the player, or NULL if the slot is empty or holds another player type
 */
static ai_scripted_t* aitest_get_ai(uint8 nr)
{
	if (nr >= MAX_PLAYER_COUNT) {
		return NULL;
	}
	return dynamic_cast<ai_scripted_t*>(welt->get_player(nr));
}


/**
 * Attaches a script to an existing scripted AI player, as ai_selector_t::item_action
 * does. The caller creates the player first, which the scenario api can already do.
 * @param base directory holding the ai folder, with a trailing separator
 * @returns NULL on success, else a message saying why not
 */
static const char* aitest_attach_impl(uint8 nr, const char* name, const char* base)
{
	// same policy as the AI selector in gui/player_frame.cc, on the same globals
	if (env_t::networkmode  &&  !env_t::server) {
		return "Scripted AI can only be attached on the server";
	}
	if (name == NULL  ||  *name == 0) {
		return "No AI name given";
	}
	ai_scripted_t* ai = aitest_get_ai(nr);
	if (ai == NULL) {
		return "Not a scripted AI player";
	}
	if (ai->has_script()) {
		return "AI already has a script";
	}
	return ai->init(base, name);
}


/// the shipped ai folder, the one ai_selector_t offers
static plainstring aitest_shipped_base()
{
	cbuffer_t buf;
	buf.printf("%s/ai/", env_t::base_dir);
	return plainstring((const char*)buf);
}


/// the ai folder inside the automated-tests scenario, holding test fixtures only
///
/// The path comes from the running scenario, not from env_t::pak_dir. A scenario
/// is looked for in the addon directory first and only then in the pakset, and
/// the automated tests run from the addon directory: the workflow links tests/
/// to addons/<pak>/scenario/automated-tests. Rebuilding the path from the pakset
/// instead sent every fixture lookup to a directory that does not exist.
static plainstring aitest_fixture_base()
{
	scenario_t* scen = welt->get_scenario();
	if (scen == NULL) {
		return plainstring("");
	}

	cbuffer_t buf;
	buf.printf("%sai/", scen->get_scenario_path());
	return plainstring((const char*)buf);
}


static SQInteger aitest_attach(HSQUIRRELVM vm)
{
	const uint8 nr = param<uint8>::get(vm, 2);
	const char* name = param<const char*>::get(vm, 3);

	return param<const char*>::push(vm, aitest_attach_impl(nr, name, aitest_shipped_base()));
}


/// attaches a fixture ai shipped with the automated tests, not with the game
static SQInteger aitest_attach_fixture(HSQUIRRELVM vm)
{
	const uint8 nr = param<uint8>::get(vm, 2);
	const char* name = param<const char*>::get(vm, 3);

	return param<const char*>::push(vm, aitest_attach_impl(nr, name, aitest_fixture_base()));
}


/**
 * Attaches under a stated network state. The real globals are set, so the guard reads
 * exactly what it reads in a network game, and aitest_net_state_t puts them back.
 */
static SQInteger aitest_attach_as(HSQUIRRELVM vm)
{
	const bool networkmode = param<bool>::get(vm, 2);
	const bool server      = param<bool>::get(vm, 3);
	const uint8 nr         = param<uint8>::get(vm, 4);
	const char* name       = param<const char*>::get(vm, 5);

	aitest_net_state_t net;
	net.set(networkmode, server);

	return param<const char*>::push(vm, aitest_attach_impl(nr, name, aitest_shipped_base()));
}


/// the same for a fixture ai, so a successful attach can be tested under server state
static SQInteger aitest_attach_fixture_as(HSQUIRRELVM vm)
{
	const bool networkmode = param<bool>::get(vm, 2);
	const bool server      = param<bool>::get(vm, 3);
	const uint8 nr         = param<uint8>::get(vm, 4);
	const char* name       = param<const char*>::get(vm, 5);

	aitest_net_state_t net;
	net.set(networkmode, server);

	return param<const char*>::push(vm, aitest_attach_impl(nr, name, aitest_fixture_base()));
}


/// @returns whether the slot holds a scripted AI player that has a script attached
static SQInteger aitest_has_script(HSQUIRRELVM vm)
{
	ai_scripted_t* ai = aitest_get_ai(param<uint8>::get(vm, 2));
	bool res = ai != NULL  &&  ai->has_script();

	return param<bool>::push(vm, res);
}


/// called by a fixture ai to report that its callback ran; reachable from an ai vm
static SQInteger aitest_note(HSQUIRRELVM vm)
{
	const char* text = param<const char*>::get(vm, 2);
	aitest_note_text = text ? text : "";
	aitest_note_calls++;

	return 0;
}


static SQInteger aitest_get_note(HSQUIRRELVM vm)
{
	const char* text = aitest_note_text ? (const char*)aitest_note_text : "";

	return param<const char*>::push(vm, text);
}


static SQInteger aitest_note_count(HSQUIRRELVM vm)
{
	return param<uint32>::push(vm, aitest_note_calls);
}


static SQInteger aitest_reset_notes(HSQUIRRELVM vm)
{
	aitest_note_text = "";
	aitest_note_calls = 0;
	bool res = true;

	return param<bool>::push(vm, res);
}


/// "<networkmode>,<server>" as the policy sees them, so a test can prove restoration
static SQInteger aitest_net_state(HSQUIRRELVM vm)
{
	cbuffer_t buf;
	buf.printf("%d,%d", env_t::networkmode ? 1 : 0, env_t::server ? 1 : 0);

	return param<const char*>::push(vm, (const char*)buf);
}


void export_ai_test(HSQUIRRELVM vm, bool scenario)
{
	// a fixture ai has to be able to report from inside its own vm
	register_function(vm, aitest_note, "aitest_note", 2, ".s");

	if (!scenario) {
		return;
	}
	register_function(vm, aitest_attach,            "aitest_attach",            3, ".is");
	register_function(vm, aitest_attach_fixture,    "aitest_attach_fixture",    3, ".is");
	register_function(vm, aitest_attach_as,         "aitest_attach_as",         5, ".bbis");
	register_function(vm, aitest_attach_fixture_as, "aitest_attach_fixture_as", 5, ".bbis");
	register_function(vm, aitest_has_script,        "aitest_has_script",        2, ".i");
	register_function(vm, aitest_get_note,          "aitest_get_note",          1, ".");
	register_function(vm, aitest_note_count,        "aitest_note_count",        1, ".");
	register_function(vm, aitest_reset_notes,       "aitest_reset_notes",       1, ".");
	register_function(vm, aitest_net_state,         "aitest_net_state",         1, ".");
}
