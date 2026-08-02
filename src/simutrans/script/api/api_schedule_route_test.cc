/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

/** @file api_schedule_route_test.cc
 *
 * TEST SUPPORT ONLY - not part of the schedule route overlay itself.
 *
 * Drives the real schedule editor component (gui_schedule_t) and reads the real
 * display only route channel of the world, so that the automated tests exercise
 * the production code path instead of a copy of it.
 */

#include "api.h"

#include "../api_class.h"
#include "../api_function.h"

#include "../../dataobj/schedule.h"
#include "../../ground/grund.h"
#include "../../gui/components/gui_schedule.h"
#include "../../obj/simobj.h"
#include "../../player/simplay.h"
#include "../../simconvoi.h"
#include "../../simline.h"
#include "../../world/simworld.h"

using namespace script_api;


#define SROUTE_SLOTS (3)

/// one open schedule editor per slot, so that two windows can be tested against each other
static gui_schedule_t *sroute_gui[SROUTE_SLOTS] = { NULL, NULL, NULL };
static player_t       *sroute_player_of[SROUTE_SLOTS] = { NULL, NULL, NULL };
static convoihandle_t  sroute_cnv_of[SROUTE_SLOTS];
static linehandle_t    sroute_lin_of[SROUTE_SLOTS];


static gui_schedule_t *sroute_slot(HSQUIRRELVM vm, SQInteger index)
{
	const uint8 slot = param<uint8>::get(vm, index);
	return slot < SROUTE_SLOTS ? sroute_gui[slot] : NULL;
}


static void sroute_fill(uint8 slot, schedule_t *sched, player_t *pl, convoihandle_t cnv, linehandle_t lin)
{
	delete sroute_gui[slot];
	sroute_gui[slot] = new gui_schedule_t();
	sroute_player_of[slot] = pl;
	sroute_cnv_of[slot] = cnv;
	sroute_lin_of[slot] = lin;
	sroute_gui[slot]->init( sched, pl, cnv, lin, true );
}


static SQInteger sroute_open(HSQUIRRELVM vm) // slot, schedule_x, player_nr
{
	const uint8 slot = param<uint8>::get(vm, 2);
	schedule_t *sched = param<schedule_t*>::get(vm, 3);
	player_t *pl = welt->get_player( param<uint8>::get(vm, 4) );
	if(  slot >= SROUTE_SLOTS  ||  sched == NULL  ||  pl == NULL  ) {
		return sq_raise_error(vm, "sroute_open: bad slot, schedule or player");
	}
	sroute_fill( slot, sched, pl, convoihandle_t(), linehandle_t() );
	return 0;
}


static SQInteger sroute_open_line(HSQUIRRELVM vm) // slot, line_x
{
	const uint8 slot = param<uint8>::get(vm, 2);
	linehandle_t lin = param<linehandle_t>::get(vm, 3);
	if(  slot >= SROUTE_SLOTS  ||  !lin.is_bound()  ) {
		return sq_raise_error(vm, "sroute_open_line: bad slot or line");
	}
	sroute_fill( slot, lin->get_schedule(), lin->get_owner(), convoihandle_t(), lin );
	return 0;
}


static SQInteger sroute_open_convoy(HSQUIRRELVM vm) // slot, convoy_x
{
	const uint8 slot = param<uint8>::get(vm, 2);
	convoihandle_t cnv = param<convoihandle_t>::get(vm, 3);
	if(  slot >= SROUTE_SLOTS  ||  !cnv.is_bound()  ||  cnv->get_schedule() == NULL  ) {
		return sq_raise_error(vm, "sroute_open_convoy: bad slot or convoy");
	}
	sroute_fill( slot, cnv->get_schedule(), cnv->get_owner(), cnv, linehandle_t() );
	return 0;
}


static SQInteger sroute_mark(HSQUIRRELVM vm) // slot, bool
{
	gui_schedule_t *gui = sroute_slot(vm, 2);
	if(  gui == NULL  ) {
		return sq_raise_error(vm, "sroute_mark: empty slot");
	}
	gui->highlight_schedule( param<bool>::get(vm, 3) );
	return 0;
}


static SQInteger sroute_reinit(HSQUIRRELVM vm) // slot, schedule_x
{
	// the editor is re-initialised with a changed schedule, as line_management_gui
	// does when the schedule of the shown line changed. The component - and with it
	// the overlay id - stays the same, only its content changes.
	const uint8 slot = param<uint8>::get(vm, 2);
	schedule_t *sched = param<schedule_t*>::get(vm, 3);
	if(  slot >= SROUTE_SLOTS  ||  sroute_gui[slot] == NULL  ||  sched == NULL  ) {
		return sq_raise_error(vm, "sroute_reinit: empty slot or bad schedule");
	}
	sroute_gui[slot]->init( sched, sroute_player_of[slot], sroute_cnv_of[slot], sroute_lin_of[slot], true );
	return 0;
}


static SQInteger sroute_close(HSQUIRRELVM vm) // slot
{
	const uint8 slot = param<uint8>::get(vm, 2);
	if(  slot >= SROUTE_SLOTS  ) {
		return sq_raise_error(vm, "sroute_close: bad slot");
	}
	delete sroute_gui[slot];
	sroute_gui[slot] = NULL;
	return 0;
}


static SQInteger sroute_step(HSQUIRRELVM)
{
	// what karte_t::interactive() does once per loop
	welt->step_schedule_route();
	return 0;
}


static SQInteger sroute_rotate(HSQUIRRELVM)
{
	// rotating rewrites every coordinate; the overlay must not survive it
	welt->rotate90();
	return 0;
}


static SQInteger sroute_len(HSQUIRRELVM vm)
{
	return param<uint32>::push( vm, welt->get_schedule_route().get_count() );
}


static SQInteger sroute_gaps(HSQUIRRELVM vm)
{
	uint32 gaps = 0;
	for(  koord3d const& pos : welt->get_schedule_route()  ) {
		gaps += (pos == koord3d::invalid);
	}
	return param<uint32>::push( vm, gaps );
}


static SQInteger sroute_tile(HSQUIRRELVM vm) // index -> coord3d, null for a gap
{
	const uint32 index = param<uint32>::get(vm, 2);
	const vector_tpl<koord3d> &route = welt->get_schedule_route();
	if(  index >= route.get_count()  ||  route[index] == koord3d::invalid  ) {
		sq_pushnull(vm);
		return 1;
	}
	return param<koord3d>::push( vm, route[index] );
}


static SQInteger sroute_has(HSQUIRRELVM vm) // coord3d -> bool
{
	const koord3d pos = param<koord3d>::get(vm, 2);
	return param<bool>::push( vm, welt->get_schedule_route().is_contained(pos) );
}


static SQInteger sroute_owner(HSQUIRRELVM vm)
{
	return param<uint32>::push( vm, welt->get_schedule_route_owner() );
}


static SQInteger sroute_player(HSQUIRRELVM vm)
{
	return param<uint32>::push( vm, welt->get_schedule_route_player_nr() );
}


static SQInteger sroute_stop_marked(HSQUIRRELVM vm) // coord3d -> bool
{
	const koord3d pos = param<koord3d>::get(vm, 2);
	bool marked = false;
	if(  grund_t *gr = welt->lookup(pos)  ) {
		marked = gr->get_flag( grund_t::marked );
		for(  uint i = 0;  !marked  &&  i < gr->obj_count();  i++  ) {
			marked = gr->obj_bei(i)->get_flag( obj_t::highlight );
		}
	}
	return param<bool>::push( vm, marked );
}


static SQInteger sroute_convoy_fingerprint(HSQUIRRELVM vm) // convoy_x -> string
{
	convoihandle_t cnv = param<convoihandle_t>::get(vm, 2);
	if(  !cnv.is_bound()  ) {
		return sq_raise_error(vm, "sroute_convoy_fingerprint: no convoy");
	}
	cbuffer_t buf;
	buf.printf( "%s|%d|%u|%d|%d",
		cnv->get_pos().get_str(), (int)cnv->get_state(), cnv->get_route()->get_count(),
		(int)cnv->get_akt_speed(), (int)cnv->get_schedule()->get_current_stop() );
	return param<const char*>::push( vm, (const char*)buf );
}


void export_schedule_route_test(HSQUIRRELVM vm)
{
	register_function(vm, sroute_open,        "sroute_open",        4, ".ixi");
	register_function(vm, sroute_open_line,   "sroute_open_line",   3, ".ix");
	register_function(vm, sroute_open_convoy, "sroute_open_convoy", 3, ".ix");
	register_function(vm, sroute_mark,        "sroute_mark",        3, ".ib");
	register_function(vm, sroute_reinit,      "sroute_reinit",      3, ".ix");
	register_function(vm, sroute_close,       "sroute_close",       2, ".i");
	register_function(vm, sroute_step,        "sroute_step",        1, ".");
	register_function(vm, sroute_rotate,      "sroute_rotate",      1, ".");
	register_function(vm, sroute_len,         "sroute_len",         1, ".");
	register_function(vm, sroute_gaps,        "sroute_gaps",        1, ".");
	register_function(vm, sroute_tile,        "sroute_tile",        2, ".i");
	register_function(vm, sroute_has,         "sroute_has",         2, ".x");
	register_function(vm, sroute_owner,       "sroute_owner",       1, ".");
	register_function(vm, sroute_player,      "sroute_player",      1, ".");
	register_function(vm, sroute_stop_marked, "sroute_stop_marked", 2, ".x");
	register_function(vm, sroute_convoy_fingerprint, "sroute_convoy_fingerprint", 2, ".x");
}
