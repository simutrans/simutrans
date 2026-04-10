/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#include "simgraph.h"

#include "simgraph0.h"
#include "simgraph16.h"


const simgraph_t *g_simgraph;

scr_coord_val default_font_ascent = 0;

// a font height of zero could cause division by zero errors, even though it should not be used in a server
scr_coord_val default_font_linespace = 1;


const simgraph_t *simgraph_select(simgraph_type_t preferred_type)
{
	switch (preferred_type) {
#if COLOUR_DEPTH == 0
		case SIMGRAPH_TYPE_NULL:     return &g_simgraph0;
#else
		case SIMGRAPH_TYPE_SOFTWARE: return &g_simgraph16;
#endif

		default: return NULL;
	}
}
