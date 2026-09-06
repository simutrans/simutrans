/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

/** @file api_ai_test.cc
 *
 * TEST SUPPORT ONLY - not part of the public Script API.
 *
 * Deliberately absent from documentation/DoxyfileSQAPI.in and exported to scenarios
 * only, following the same pattern as api_schedule_route_test.cc.
 *
 * A scripted AI player can otherwise only be given its script by the GUI: the sole
 * caller of ai_scripted_t::init() is ai_selector_t::item_action(). That leaves the
 * Script AI lifecycle without automated coverage. This module supplies the missing
 * caller and nothing else. It drives the same public init() the dialog drives, so
 * the tests exercise the production path rather than a copy of it.
 *
 * The network policy is the dialog's own: gui/player_frame.cc offers the AI selector
 * only when (!env_t::networkmode || env_t::server), and attach_impl() applies exactly
 * that condition.
 */

#include "api.h"

#include "../api_function.h"

#include "../../dataobj/environment.h"
#include "../../player/ai_scripted.h"
#include "../../player/simplay.h"
#include "../../simconst.h"
#include "../../utils/cbuffer.h"
#include "../../world/simworld.h"

using namespace script_api;


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
 *
 * @param server whether this game acts as a server. Taken from the caller because
 *               env_t::server is a read-only reference to the network port, which a
 *               test cannot set; env_t::networkmode is read directly.
 * @returns NULL on success, else a message saying why not
 */
static const char* aitest_attach_impl(uint8 nr, const char* name, bool server)
{
	// same policy as the AI selector in gui/player_frame.cc
	if (env_t::networkmode  &&  !server) {
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
	// the argument shape ai_selector_t establishes: base directory with a trailing
	// separator, plus the name of the folder holding ai.nut
	cbuffer_t base;
	base.printf("%s/ai/", env_t::base_dir);

	return ai->init((const char*)base, name);
}


static SQInteger aitest_attach(HSQUIRRELVM vm)
{
	const uint8 nr = param<uint8>::get(vm, 2);
	const char* name = param<const char*>::get(vm, 3);

	return param<const char*>::push(vm, aitest_attach_impl(nr, name, env_t::server != 0));
}


/**
 * Attaches under a stated network state, to test the policy above.
 * env_t::networkmode is really set, so the guard reads the same global it reads in a
 * network game, and is restored before returning. Nothing can run in between: the
 * whole exchange happens inside this one call, and the refusing path touches no
 * player at all.
 */
static SQInteger aitest_attach_as(HSQUIRRELVM vm)
{
	const bool networkmode = param<bool>::get(vm, 2);
	const bool server      = param<bool>::get(vm, 3);
	const uint8 nr         = param<uint8>::get(vm, 4);
	const char* name       = param<const char*>::get(vm, 5);

	const bool saved_networkmode = env_t::networkmode;
	env_t::networkmode = networkmode;

	const char* err = aitest_attach_impl(nr, name, server);

	env_t::networkmode = saved_networkmode;

	return param<const char*>::push(vm, err);
}


/// @returns whether the slot holds a scripted AI player that has a script attached
static SQInteger aitest_has_script(HSQUIRRELVM vm)
{
	ai_scripted_t* ai = aitest_get_ai(param<uint8>::get(vm, 2));
	bool res = ai != NULL  &&  ai->has_script();

	return param<bool>::push(vm, res);
}


void export_ai_test(HSQUIRRELVM vm)
{
	register_function(vm, aitest_attach,     "aitest_attach",     3, ".is");
	register_function(vm, aitest_attach_as,  "aitest_attach_as",  5, ".bbis");
	register_function(vm, aitest_has_script, "aitest_has_script", 2, ".i");
}
