/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#include "simsocial.h"

#ifdef STEAM_BUILT
#include "../steam/steam_iface.h"
#endif


void social_update_presence(const social_presence_t &presence)
{
#ifdef STEAM_BUILT
	steam_update_presence(presence.pakset, presence.year, presence.convoys);
#else
	(void)presence;
#endif
}


void social_pump_events()
{
#ifdef STEAM_BUILT
	steam_pump_events();
#endif
}


void social_shutdown()
{
#ifdef STEAM_BUILT
	steam_shutdown();
#endif
}
