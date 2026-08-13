/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#include "api.h"

/** @file api_pathfinding.cc exports heap structure and construction helpers. */

#include "api_obj_desc_base.h"
#include "api_simple.h"
#include "../api_class.h"
#include "../api_function.h"
#include "../../builder/brueckenbauer.h"
#include "../../builder/tunnelbauer.h"
#include "../../builder/wegbauer.h"
#include "../../dataobj/settings.h"
#include "../../descriptor/bridge_desc.h"
#include "../../descriptor/way_desc.h"
#include "../../tpl/binary_heap_tpl.h"
#include "../../world/simworld.h"

using namespace script_api;


struct heap_node_t {
	sint32 weight;
	sint32 value;

	heap_node_t(sint32 w, sint32 v) : weight(w), value(v) {}
	// dereferencing to be used in binary_heap_tpl
	inline sint32 operator * () const { return weight; }
};

typedef binary_heap_tpl<heap_node_t> simple_heap_t;

namespace script_api{
	declare_specialized_param(heap_node_t, "t|x|y", "simple_heap_x::node_x");
	declare_specialized_param(simple_heap_t*, "t|x|y", "simple_heap_x");
};

SQInteger heap_constructor(HSQUIRRELVM vm)
{
	simple_heap_t* heap = new simple_heap_t();
	attach_instance(vm, 1, heap);
	return SQ_OK;
}

void* script_api::param<simple_heap_t*>::tag()
{
	return (void*)&heap_constructor;
}

simple_heap_t* script_api::param<simple_heap_t*>::get(HSQUIRRELVM vm, SQInteger index)
{
	simple_heap_t *heap = get_attached_instance<simple_heap_t>(vm, index, param<simple_heap_t*>::tag());
	return heap;
}

SQInteger param<heap_node_t>::push(HSQUIRRELVM vm, heap_node_t const& v)
{
	sq_newtable(vm);
	create_slot<sint32>(vm, "weight", v.weight);
	create_slot<sint32>(vm, "value", v.value);
	return 1;
}

void simple_heap_insert(simple_heap_t *heap, sint32 weight, sint32 value)
{
	heap->insert( heap_node_t(weight, value) );
}

SQInteger simple_heap_pop(HSQUIRRELVM vm) // instance
{
	simple_heap_t *heap = param<simple_heap_t*>::get(vm, 1);
	if (heap) {
		if (!heap->empty()) {
			return param<heap_node_t>::push(vm, heap->pop());
		}
		else {
			return sq_raise_error(vm, "Called pop() on empty heap");
		}
	}
	else {
		return sq_raise_error(vm, "Not a heap instance"); // should not happen
	}
}


SQInteger way_builder_constructor(HSQUIRRELVM vm) // instance, player
{
	// get player parameter
	player_t *player = get_my_player(vm);
	if (player == NULL) {
		player = param<player_t*>::get(vm, 2);
	}
	if (player == NULL) {
		return SQ_ERROR;
	}
	way_builder_t* bob = new way_builder_t(player);

	bob->set_keep_existing_faster_ways(true);
	bob->set_keep_city_roads(true);

	attach_instance(vm, 1, bob);
	return SQ_OK;
}

void way_builder_set_build_types(way_builder_t *bob, const way_desc_t *way)
{
	if (way) {
		way_builder_t::bautyp_t bautyp = (way_builder_t::bautyp_t)way->get_waytype();
		if (way->is_tram()) {
			bautyp = way_builder_t::schiene_tram;
		}
		// type_elevated and type_runway share the same value, so air stays flat
		if (way->get_styp() == type_elevated && way->get_waytype() != air_wt) {
			bautyp |= way_builder_t::elevated_flag;
		}
		bob->init_builder( bautyp, way, NULL /*tunnel*/, NULL /*bridge*/);
	}
}

bool way_builder_is_allowed_step(way_builder_t *bob, grund_t *from, grund_t *to)
{
	if (from == NULL || to == NULL) {
		return false;
	}
	sint32 costs = 0;
	return bob->is_allowed_step(from, to, &costs);
}


SQInteger way_builder_get_step_cost(HSQUIRRELVM vm) // instance, from, to
{
	way_builder_t *bob = param<way_builder_t*>::get(vm, 1);
	if (bob == NULL) {
		return sq_raise_error(vm, "Not a way_planner_x instance"); // should not happen
	}
	grund_t *from = param<grund_t*>::get(vm, 2);
	grund_t *to   = param<grund_t*>::get(vm, 3);

	sint32 costs = 0;
	if (from == NULL || to == NULL || !bob->is_allowed_step(from, to, &costs)) {
		sq_pushnull(vm);
		return 1;
	}
	return param<sint32>::push(vm, costs);
}


/**
 * Highest length a script may ask for: bridge_builder_t::find_end_pos counts the
 * tested lengths in an uint8, so 255 would never terminate.
 */
static const uint32 MAX_SCRIPT_BRIDGE_LEN = 254;

koord3d bridge_builder_find_end_pos(player_t *player, koord3d pos, my_ribi_t mribi, const bridge_desc_t *bridge, uint32 min_length, sint32 max_length, bool allow_flat_ends)
{
	sint8 height;
	ribi_t::ribi ribi(mribi);

	if (player == NULL  ||  bridge == NULL) {
		return koord3d::invalid;
	}
	// a script must not search further than the player could build
	uint32 limit = min( welt->get_settings().way_max_bridge_len, MAX_SCRIPT_BRIDGE_LEN );
	if (bridge->get_max_length() > 0) {
		// a bridge of max_length spans a distance of max_length+1, see bridge_builder_t::can_span_bridge
		limit = min( limit, (uint32)bridge->get_max_length() + 1 );
	}
	// max_length <= 0 means: as far as this bridge and the settings allow
	const uint32 length = max_length <= 0 ? limit : min( (uint32)max_length, limit );

	if (min_length > length) {
		return koord3d::invalid;
	}
	if (bridge_builder_t::find_end_pos(player, pos, ribi, height, bridge, min_length, length, allow_flat_ends) != NULL) {
		return koord3d::invalid;
	}
	return pos;
}


typedef koord3d (*bfe_type)(player_t*, koord3d, my_ribi_t, const bridge_desc_t*, uint32, sint32, bool);

SQInteger bridge_planner_find_end(HSQUIRRELVM vm)
{
	/* possible calling conventions:
	 *
	 * find_end(pl, pos, dir, bridge, min_length)                            - top == 6
	 * find_end(pl, pos, dir, bridge, min_length, max_length)                - top == 7
	 * find_end(pl, pos, dir, bridge, min_length, max_length, flat_ends)     - top == 8
	 */
	if (sq_gettop(vm) == 6) {
		// keep the length the old binding used
		sq_pushinteger(vm, 10);
	}
	if (sq_gettop(vm) == 7) {
		sq_pushbool(vm, false);
	}
	return embed_call_t<bfe_type>::call_function(vm, bridge_builder_find_end_pos, false);
}


koord3d tunnel_builder_find_end_pos(player_t *player, koord3d pos, my_ribi_t mribi, const tunnel_desc_t *tunnel)
{
	ribi_t::ribi ribi(mribi);

	if (player == NULL  ||  tunnel == NULL) {
		return koord3d::invalid;
	}
	// koord(ribi) turns anything but a single direction into a diagonal, a
	// different cardinal, or zero, and a zero vector never leaves the start tile
	if (!ribi_t::is_single(ribi)) {
		return koord3d::invalid;
	}
	return tunnel_builder_t::find_end_pos(player, pos, koord(ribi), tunnel);
}


void export_pathfinding(HSQUIRRELVM vm)
{
	/**
	 * Exports a binary heap structure with
	 * with simple nodes.
	 */
	create_class(vm, "simple_heap_x", 0);
	/**
	 * Constructor
	 */
	register_function(vm, heap_constructor, "constructor", 1, "x");
	sq_settypetag(vm, -1, param<simple_heap_t*>::tag());

	/// Clears the heap.
	register_method(vm, &simple_heap_t::clear, "clear");
	/// @returns number of nodes in heap
	register_method(vm, &simple_heap_t::get_count, "len");
	/// @returns true when heap is empty
	register_method(vm, &simple_heap_t::empty, "is_empty");
	/**
	 * Inserts a node into the heap.
	 * @param weight heap is sorted with respect to weight
	 * @param value the data to be stored
	 */
	register_method(vm, simple_heap_insert, "insert", true);
	/**
	 * Pops the top node of the heap.
	 * Raises error if heap is empty.
	 * @returns top node
	 */
	register_function(vm, simple_heap_pop, "pop", 1, "x");
#ifdef SQAPI_DOC
		/**
		 * Helper node class.
		 */
		class node_x {
			int weight; ///< heap is sorted with respect to weight
			int value;  ///< the data to be stored
		}
#endif
	end_class(vm);

	/**
	 * Class with helper methods for way planning.
	 */
	create_class(vm, "way_planner_x", 0);
	/**
	 * Constructor
	 * @param pl player that wants to plan, for ai scripts is set to ai player_x::self
	 * @typemask way_planner_x(player_x)
	 */
	register_function(vm, way_builder_constructor, "constructor", 2, "xx");
	sq_settypetag(vm, -1, param<way_builder_t*>::tag());

	/**
	 * Sets way descriptor, which is needed for @ref is_allowed_step.
	 * @param way descriptor of way to be planned.
	 */
	register_method(vm, way_builder_set_build_types, "set_build_types", true);
	/**
	 * Checks if player can build way from @p from to @p to.
	 * @param from from here
	 * @param to to here, @p from and @p to must be adjacent.
	 */
	register_method(vm, way_builder_is_allowed_step, "is_allowed_step", true);
	/**
	 * Costs of the step from @p from to @p to, as used by the route search of the way builder.
	 * These are the weights derived from the way_count_* settings, not an amount of money.
	 * @param from from here
	 * @param to to here, @p from and @p to must be adjacent.
	 * @returns costs of the step, or null if @ref is_allowed_step refuses it
	 * @typemask integer(tile_x,tile_x)
	 */
	register_function(vm, way_builder_get_step_cost, "get_step_cost", 3, "x t|x|y t|x|y");

	log_squirrel_type("way_planner_x", "get_step_cost", "integer(tile_x, tile_x)");

	end_class(vm);

	/**
	 * Class with helper methods for bridge planning.
	 */
	create_class(vm, "bridge_planner_x", 0);
	/**
	 * Find suitable end tile for bridge starting at @p pos going into direction @p dir.
	 *
	 * The search never goes further than the player could build: it is limited by the
	 * maximum length of @p bridge and by the @c way_max_bridge_len setting.
	 *
	 * @param pl who wants to build a bridge
	 * @param pos start tile for bridge
	 * @param dir direction
	 * @param bridge bridge descriptor
	 * @param min_length bridge should have this minimal length
	 * @param max_length (optional parameter) bridge should not be longer than this, zero or negative means as long as allowed. Defaults to 10.
	 * @param flat_ends (optional parameter) if true then an end on flat ground is accepted too, not only an end at a slope. Defaults to false.
	 * @returns coordinate of end tile or an invalid coordinate
	 * @typemask coord3d(player_x,coord3d,dir,bridge_desc_x,integer,integer,bool)
	 */
	STATIC register_function(vm, bridge_planner_find_end, "find_end", -6 /* at least 6 parameters */,
	                         func_signature_t<bfe_type>::get_typemask(false).c_str(), true /* static */);

	log_squirrel_type(func_signature_t<bfe_type>::get_squirrel_class(false), "find_end", func_signature_t<bfe_type>::get_squirrel_type(false, 0));

	end_class(vm);

	/**
	 * Class with helper methods for tunnel planning.
	 */
	create_class(vm, "tunnel_planner_x", 0);
	/**
	 * Find the far portal of a tunnel starting at @p pos and going into direction @p dir.
	 *
	 * The search runs until it finds a place for the second portal or until it leaves the
	 * map, just as it does for the tunnel tool of a player. Nothing is built, and the start
	 * tile is not validated: if it cannot carry a portal, the answer is just the next tile.
	 *
	 * @param pl who wants to build a tunnel
	 * @param pos start tile of the tunnel, the tile that would carry the first portal
	 * @param dir direction, must be a single direction
	 * @param tunnel tunnel descriptor
	 * @returns coordinate of the far portal or an invalid coordinate
	 */
	STATIC register_method(vm, tunnel_builder_find_end_pos, "find_end", false, true);

	end_class(vm);
}


void* script_api::param<way_builder_t*>::tag()
{
	return (void*)&way_builder_constructor;
}

way_builder_t* script_api::param<way_builder_t*>::get(HSQUIRRELVM vm, SQInteger index)
{
	way_builder_t *bob = get_attached_instance<way_builder_t>(vm, index, param<way_builder_t*>::tag());
	return bob;
}

