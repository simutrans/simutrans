/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#include "simloadingscreen.h"

#include "sys/simsys.h"
#include "descriptor/image.h"
#include "descriptor/skin_desc.h"
#include "simskin.h"
#include "display/simgraph.h"
#include "simevent.h"
#include "dataobj/environment.h"
#include "simticker.h"
#include "gui/simwin.h"
#include "gui/gui_theme.h"
#include "tpl/slist_tpl.h"


loadingscreen_t::loadingscreen_t( const char *w, uint32 max_p, bool logo, bool continueflag )
{
	what = w;
	info = NULL;
	progress = 0;
	max_progress = max_p;
	last_bar_len = -1;
	show_logo = logo;

	if(  !gfx->is_display_init()  ||  continueflag  ) {
		return;
	}

	// darkens the current screen
	const scr_size screen = gfx->get_screen_size();
	gfx->tint_rect(0, 0, screen.w, screen.h, gfx->palette_lookup(COL_BLACK), 50 );
	gfx->mark_screen_dirty();

	display_logo();
}


// show the logo if requested and there
void loadingscreen_t::display_logo()
{
	if(  show_logo  &&  skinverwaltung_t::biglogosymbol  ) {
		const scr_size screen = gfx->get_screen_size();
		const image_t *image0 = skinverwaltung_t::biglogosymbol->get_image(0);
		const int w = image0->w;
		const int h = image0->h + image0->y;
		int x = screen.w/2-w;
		int y = screen.h/4-w;
		if(y<0) {
			y = 1;
		}

		gfx->draw_color_img(skinverwaltung_t::biglogosymbol->get_image_id(0), x,   y,   0, false, true CLIP_NUM_DEFAULT);
		gfx->draw_color_img(skinverwaltung_t::biglogosymbol->get_image_id(1), x+w, y,   0, false, true CLIP_NUM_DEFAULT);
		gfx->draw_color_img(skinverwaltung_t::biglogosymbol->get_image_id(2), x,   y+h, 0, false, true CLIP_NUM_DEFAULT);
		gfx->draw_color_img(skinverwaltung_t::biglogosymbol->get_image_id(3), x+w, y+h, 0, false, true CLIP_NUM_DEFAULT);
	}
}


// show everything but the logo
void loadingscreen_t::display()
{
	const scr_size screen = gfx->get_screen_size();
	const int half_width    = screen.w / 2;
	const int quarter_width = screen.w / 4;
	const int half_height   = screen.h / 2;

	scr_coord_val const bar_height = max(LINESPACE + 10, 20);
	scr_coord_val const bar_y = half_height - bar_height / 2 + 1;
	scr_coord_val const bar_text_y = half_height - LINESPACE / 2 + 1;

	const int bar_len = max_progress>0 ? (int) ( ((double)progress*(double)half_width)/(double)max_progress ) : 0;

	if(  bar_len != last_bar_len  ) {
		last_bar_len = bar_len;

		dr_prepare_flush();

		if(  info  ) {
			gfx->draw_text( half_width, bar_y - LINESPACE - 2, info, ALIGN_CENTER_H, gfx->palette_lookup(COL_WHITE), true );
		}

		// outline
		gfx->draw_box3d(quarter_width-2, bar_y,     half_width+4, bar_height,     gfx->palette_lookup(COL_GREY6), gfx->palette_lookup(COL_GREY4), true);
		gfx->draw_box3d(quarter_width-1, bar_y + 1, half_width+2, bar_height - 2, gfx->palette_lookup(COL_GREY4), gfx->palette_lookup(COL_GREY6), true);

		// inner
		gfx->draw_rect( quarter_width, bar_y + 2, half_width, bar_height - 4, SYSCOL_LOADINGBAR_INNER, true);

		// progress
		gfx->draw_rect( quarter_width, bar_y + 4, bar_len,  bar_height - 8, SYSCOL_LOADINGBAR_PROGRESS, true );

		if(  what  ) {
			gfx->draw_text( half_width, bar_text_y, what, ALIGN_CENTER_H, SYSCOL_TEXT_HIGHLIGHT, false );
		}

		dr_flush();
	}
}


void loadingscreen_t::set_progress( uint32 progress )
{
	if (!gfx->is_display_init()  &&  (progress != this->progress  ||  progress == 0)  ) {
		return;
	}

	// first: handle events
	event_t *ev = new event_t;

	display_poll_event(ev);
	if(  ev->ev_class == EVENT_SYSTEM  ) {
		if(  ev->ev_code == SYSTEM_RESIZE  ) {
			// main window resized
			gfx->on_window_resized( ev->new_window_size );
			gfx->draw_rect( 0, 0, ev->mouse_pos.x, ev->mouse_pos.y, gfx->palette_lookup(COL_BLACK), true );
			display_logo();
			// queue the event anyway, so the viewport is correctly updated on world resume (screen will be resized again).
			queued_events.append(ev);
		}
		else if(  ev->ev_code == SYSTEM_QUIT  ) {
			// since the world is suspended (or may not even exists) when the loading screen is active
			// we can quit the quick way
			env_t::quit_simutrans = true;
			delete ev;
		}
		else {
			delete ev;
		}
	}
	else if(  IS_KEYBOARD(ev)  ) {
		queued_events.append(ev);
	}
	else { // neither a keyboard or system event -> not of interest
		delete ev;
	}

	this->progress = progress;
	display();

	if (progress > max_progress) {
		dbg->error("loadingscreen_t::set_progress", "too much progress: actual = %d max = %d", progress, max_progress);
	}
}


loadingscreen_t::~loadingscreen_t()
{
	if (gfx->is_display_init()) {
		win_redraw_world();
		gfx->mark_screen_dirty();
		ticker::set_redraw_all(true);
	}

	while(  !queued_events.empty()  ) {
		queue_event( queued_events.remove_first() );
	}
}
