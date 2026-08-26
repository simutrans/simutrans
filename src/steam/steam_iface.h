/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#ifndef STEAM_STEAM_IFACE_H
#define STEAM_STEAM_IFACE_H


#include "../simutrans/simtypes.h"


/*
 * The Steam entry points that do not expose the Steam SDK. Everything outside
 * src/steam/ includes this instead of steam.h, so that no core translation
 * unit ends up including proprietary headers.
 */

/// Install and uninstall Workshop items to match the current subscriptions.
void steam_install_workshop_items();

/// Publish the current game state as Rich Presence.
void steam_update_presence(const char *pakset, uint32 year, uint32 convoys);

/// Run pending Steam callbacks.
void steam_pump_events();

/// Unlock an achievement; the argument is a simachievements_enum value.
void steam_set_achievement(int ach_enum);

/// Shut the Steam API down.
void steam_shutdown();

#endif
