/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#ifndef SIMSOCIAL_H
#define SIMSOCIAL_H


#include "simtypes.h"


/**
 * What the player is currently doing, in terms every external platform can
 * express. Presentation only: nothing here may influence the simulation.
 */
struct social_presence_t {
	const char *pakset;
	uint32 year;
	uint32 convoys;
};


/// Publish the current game state to whatever platform this build was compiled with.
void social_update_presence(const social_presence_t &presence);

/// Let the compiled-in platform run its pending callbacks.
void social_pump_events();

/// Shut the compiled-in platform down. Safe to call when none was started.
void social_shutdown();

#endif
