/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#include <stdio.h>

#include "../world/simworld.h"
#include "simview.h"
#include "simgraph.h"
#include "viewport.h"

#include "../simticker.h"
#include "../simdebug.h"
#include "../obj/simobj.h"
#include "../simconst.h"
#include "../world/simplan.h"
#include "../tool/simmenu.h"
#include "../player/simplay.h"
#include "../descriptor/ground_desc.h"
#include "../ground/wasser.h"
#include "../dataobj/environment.h"
#include "../obj/zeiger.h"
#include "../utils/simrandom.h"

uint16 win_get_statusbar_height(); // simwin.h

main_view_t::main_view_t(karte_t *welt)
{
	this->welt = welt;
	outside_visible = true;
	viewport = welt->get_viewport();
	assert(welt  &&  viewport);
}

#if COLOUR_DEPTH != 0
static const sint8 hours2night[] =
{
	4,4,4,4,4,4,4,4,
	4,4,4,4,3,2,1,0,
	0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,1,
	2,3,4,4,4,4,4,4
};
#endif

#ifdef MULTI_THREAD
#include "../utils/simthread.h"

bool spawned_threads=false; // global job indicator array
static simthread_barrier_t display_barrier_start;
static simthread_barrier_t display_barrier_end;

// to start a thread
typedef struct{
	main_view_t *show_routine;
	koord   lt_cl, wh_cl; // pos/size of clipping rect for this thread
	koord   lt, wh;       // pos/size of region to display. set larger than clipping for correct display of trees at thread seams
	sint16  y_min;
	sint16  y_max;
	sint8   thread_num;
} display_region_param_t;

// now the parameters
static display_region_param_t ka[MAX_THREADS];

void *display_region_thread( void *ptr )
{
	display_region_param_t *view = reinterpret_cast<display_region_param_t *>(ptr);

	while(true) {
		simthread_barrier_wait( &display_barrier_start ); // wait for all to start
		gfx->clear_all_poly_clip( view->thread_num );
		gfx->set_clip_rect( view->lt_cl.x, view->lt_cl.y, view->wh_cl.x, view->wh_cl.y, view->thread_num, false);
		view->show_routine->display_region( view->lt, view->wh, view->y_min, view->y_max, false, true, view->thread_num );
		simthread_barrier_wait( &display_barrier_end ); // wait for all to finish
	}
}

/* The following mutex is only needed for smart cursor */
// mutex for changing settings on hiding buildings/trees
static pthread_mutex_t hide_mutex = PTHREAD_MUTEX_INITIALIZER;
static bool threads_req_pause = false;  // set true to pause all threads to display smartcursor region single threaded
static uint8 num_threads_paused = 0; // number of threads in the paused state
static pthread_cond_t hiding_cond = PTHREAD_COND_INITIALIZER;
static pthread_cond_t waiting_cond = PTHREAD_COND_INITIALIZER;

#if COLOUR_DEPTH != 0
static bool can_multithreading = true;
#endif
#endif


/**
 * @copydoc schedule_route_way_height2
 *
 * The way crosses a whole tile, so the middle of one is halfway between the heights of
 * the two edges the way crosses there. The route touches one edge only where a stretch
 * ends, and where it turns back on itself at the last stop of a leg and so leaves by the
 * edge it came in through; the opposite edge is the second one in both of those cases.
 */
sint32 schedule_route_way_height2(const karte_t *welt, const vector_tpl<koord3d> &route, uint32 step, bool is_edge)
{
	const koord3d &pos = route[step];
	const grund_t *gr = welt->lookup( pos );
	if(  gr == NULL  ) {
		// the ground went away under a route that has not been recalculated yet
		return 2*(sint32)pos.z;
	}
	if(  is_edge  ) {
		// both tiles answer the same height for the way on the edge they share, which is
		// what makes them neighbours on a route in the first place
		return 2*(sint32)gr->get_vmove( ribi_type( pos, route[step+1] ) );
	}
	// steps of a route are always neighbouring tiles, so each of these is a single
	// direction, as get_vmove() requires
	const bool has_prev = step > 0  &&  route[step-1] != koord3d::invalid;
	const bool has_next = step+1 < route.get_count()  &&  route[step+1] != koord3d::invalid;
	const ribi_t::ribi in  = has_prev ? ribi_type( pos, route[step-1] ) : (ribi_t::ribi)ribi_t::none;
	const ribi_t::ribi out = has_next ? ribi_type( pos, route[step+1] ) : (ribi_t::ribi)ribi_t::none;
	const ribi_t::ribi a = in ? in : ribi_t::backward( out );
	const ribi_t::ribi b = out  &&  out != a ? out : ribi_t::backward( a );
	return (sint32)gr->get_vmove( a ) + (sint32)gr->get_vmove( b );
}


/**
 * @copydoc schedule_route_edge_is_corner
 */
bool schedule_route_edge_is_corner(const karte_t *welt, const vector_tpl<koord3d> &route, uint32 step)
{
	// the middle of the line between the two centres against the way on the edge itself
	return 2*schedule_route_way_height2( welt, route, step, true ) !=
		schedule_route_way_height2( welt, route, step, false ) + schedule_route_way_height2( welt, route, step+1, false );
}


#if COLOUR_DEPTH != 0
/**
 * The area the tile loop of main_view_t::display() covers, in the rotated coordinates
 * it uses itself: u across, v down. A route runs anywhere on the map, while
 * get_screen_coord() returns sint16 and wraps a few hundred tiles away from the view,
 * so tiles are checked here, before they are projected.
 */
struct route_area_t {
	sint32 i_off, j_off;
	sint32 u_lim, v_lo, v_hi;

	/// which borders @p pos lies beyond, as a bit per border
	uint8 outcode(const koord3d &pos) const {
		const sint32 di = (sint32)pos.x - i_off;
		const sint32 dj = (sint32)pos.y - j_off;
		const sint32 u = di - dj;
		const sint32 v = di + dj;
		return (u < -u_lim ? 1 : 0) | (u > u_lim ? 2 : 0) | (v < v_lo ? 4 : 0) | (v > v_hi ? 8 : 0);
	}
};


/**
 * The offset get_screen_coord() needs to put a point of the route on the surface of the
 * way instead of on the ground below it.
 *
 * @param height2 height of the way there, in half height levels, from schedule_route_way_height2()
 */
static koord route_way_offset(const koord &centre, const koord3d &pos, sint32 height2)
{
	return koord( centre.x, centre.y - (sint16)((TILE_HEIGHT_STEP*(height2 - 2*(sint32)pos.z))/2) );
}


/**
 * A corner of the route shown by a schedule editor, held as a place on the route
 * rather than as a screen position: either the centre of the tile route[step], or the
 * midpoint of the tile edge the step from route[step] to route[step+1] crosses.
 *
 * It is projected only once the segment it belongs to is known to be drawn, because
 * get_screen_coord() works in sint16 (see viewport.cc) and wraps a few hundred tiles
 * away from the view: a tile that far never reaches it this way. The ground is looked
 * up there for the same reason.
 */
struct route_point_t {
	uint32 step;
	bool   is_edge;
	uint8  code;

	scr_coord project(const karte_t *welt, const viewport_t *viewport, const vector_tpl<koord3d> &route, const koord &centre) const {
		const sint32 height2 = schedule_route_way_height2( welt, route, step, is_edge );
		const scr_coord a = viewport->get_screen_coord( route[step], route_way_offset( centre, route[step], height2 ) );
		if(  !is_edge  ) {
			return a;
		}
		// scr_coord_val is 32 bit, so the two ends can be added before halving them
		const scr_coord b = viewport->get_screen_coord( route[step+1], route_way_offset( centre, route[step+1], height2 ) );
		return scr_coord( (a.x+b.x)/2, (a.y+b.y)/2 );
	}
};


/// @p n divided by @p d and rounded to nearest, for a positive @p d and either sign of @p n
static sint32 route_line_offset(sint32 n, sint32 d)
{
	return n >= 0 ? (2*n + d) / (2*d) : -((-2*n + d) / (2*d));
}


/**
 * One segment of the route shown by a schedule editor: a coloured core with a dark
 * line below it, so that it stays visible on any ground. Both grow when zooming in.
 *
 * The copies are shifted along the normal of the segment and not simply downwards.
 * A diagonal way runs straight down the screen, and shifting such a line in y only
 * makes it longer, never thicker: it stayed one pixel wide with no dark line beside
 * it at all, however far one zoomed in. The normal is scaled to its own length, so
 * that one step is one pixel of width in every direction and the line keeps the width
 * it always had; and it is turned to point down the screen, so that the dark line
 * keeps to the same side of the coloured one whatever the direction is, which is also
 * what makes the two directions of a leg land on each other.
 *
 * Nothing is drawn, and nothing is projected either, when both ends lie beyond the
 * same border of the drawn area, so that whatever enters, leaves or crosses the view
 * is still drawn whole.
 */
static void display_route_segment(const karte_t *welt, const viewport_t *viewport, const vector_tpl<koord3d> &route, const route_point_t &from, const route_point_t &to, const koord &centre, PIXVAL col, PIXVAL dark, sint16 core, sint16 edge)
{
	if(  (from.code & to.code) != 0  ) {
		return;
	}
	const scr_coord a = from.project( welt, viewport, route, centre );
	const scr_coord b = to.project( welt, viewport, route, centre );

	sint32 nx = -(sint32)(b.y - a.y);
	sint32 ny =  (sint32)(b.x - a.x);
	if(  ny < 0  ||  (ny == 0  &&  nx < 0)  ) {
		nx = -nx;
		ny = -ny;
	}
	const sint32 len = (sint32)sqrt_i64( (uint64)nx*nx + (uint64)ny*ny );
	// the coloured core sits on the line itself, so it does not drift off the way
	const sint16 first = -((core-1)/2);

	for(  sint16 i = core;  i < core+edge;  i++  ) {
		const sint32 k  = first + i;
		const sint32 ox = len ? route_line_offset( k*nx, len ) : 0;
		const sint32 oy = len ? route_line_offset( k*ny, len ) : k;
		gfx->draw_line( a.x+ox, a.y+oy, b.x+ox, b.y+oy, dark );
	}
	for(  sint16 i = 0;  i < core;  i++  ) {
		const sint32 k  = first + i;
		const sint32 ox = len ? route_line_offset( k*nx, len ) : 0;
		const sint32 oy = len ? route_line_offset( k*ny, len ) : k;
		gfx->draw_line( a.x+ox, a.y+oy, b.x+ox, b.y+oy, col );
	}
}


/**
 * Last step of the alternating pattern that starts at step @p a, or @p a itself when
 * the steps there do not alternate. Step k leads from route[k] to route[k+1], and
 * @p last is the final tile of the stretch under consideration.
 */
static uint32 diagonal_run_end(const vector_tpl<koord3d> &route, uint32 last, uint32 a)
{
	// below three steps a staircase cannot be told from a single bend
	if(  a+3 > last  ) {
		return a;
	}
	const koord d0 = (route[a+1] - route[a]).get_2d();
	const koord d1 = (route[a+2] - route[a+1]).get_2d();
	if(  d0 == d1  ||  d0 == -d1  ) {
		// carrying straight on, or turning back: neither one makes a diagonal
		return a;
	}
	uint32 b = a+1;
	while(  b+2 <= last  &&  (route[b+2] - route[b+1]).get_2d() == (((b+1-a) & 1) ? d1 : d0)  ) {
		b++;
	}
	return b;
}


/**
 * Longest diagonal run drawn as a single line.
 *
 * A run advances one tile per step along one of the two screen axes, so a long one ends
 * hundreds of tiles from the view, where get_screen_coord() wraps; and it cannot simply
 * be dropped, because it may well cross the view. All the edge midpoints of a run are
 * on the same straight line, so cutting it on them adds points without moving any, and
 * every piece is then short enough to be projected: a piece display_route_segment()
 * keeps has one end within the drawn area, hence both ends at most this many tiles
 * beyond it, that is 64*(IMG_SIZE/2) past its border at the very most. That leaves half
 * of the sint16 range to spare on the largest tiles and screens in use.
 */
static const uint32 ROUTE_DIAGONAL_MAX_STEPS = 64;


/**
 * Draws the tiles [first,last] of the route shown by a schedule editor, which are
 * known to be a stretch without a gap in it.
 *
 * A diagonal way is a staircase of orthogonal steps, so a line from tile centre to
 * tile centre zigzags exactly where the way graphics show a straight line. The centres
 * of such a staircase swing half a tile to either side of the line through the midpoints
 * of the shared tile edges, and those midpoints are collinear. A run of at least three
 * alternating steps is therefore entered and left on the midpoint of its first and of its
 * last step: both sit on that straight line, and both sit on the way of the straight part
 * before and after it, because a run can only begin where the step before it either
 * pointed the same way or turned a real corner. Straight runs and single bends keep the
 * tile centres they always had, and so do both ends of the stretch.
 *
 * A segment is left undrawn only when both of its ends lie beyond the same border of
 * @p area, so anything that enters, leaves or crosses the view is still drawn whole.
 * The midpoint of two tiles is beyond a border whenever both of them are, hence the
 * bitwise and of their two outcodes.
 */
static void display_route_stretch(const karte_t *welt, const viewport_t *viewport, const vector_tpl<koord3d> &route, uint32 first, uint32 last, const koord &centre, PIXVAL col, PIXVAL dark, sint16 core, sint16 edge, const route_area_t &area)
{
	route_point_t previous = { first, false, area.outcode( route[first] ) };
	uint32 t = first;
	while(  t < last  ) {
		const uint32 b = diagonal_run_end( route, last, t );
		if(  b >= t+2  ) {
			// a diagonal: cross it in one straight line, from edge midpoint to edge
			// midpoint, in pieces of at most ROUTE_DIAGONAL_MAX_STEPS steps each
			uint32 s = t;
			while(  true  ) {
				const route_point_t here = { s, true, (uint8)(area.outcode( route[s] ) & area.outcode( route[s+1] )) };
				display_route_segment( welt, viewport, route, previous, here, centre, col, dark, core, edge );
				previous = here;
				if(  s == b  ) {
					break;
				}
				s = ( b-s > ROUTE_DIAGONAL_MAX_STEPS ? s+ROUTE_DIAGONAL_MAX_STEPS : b );
			}
			// the tile the run ends on keeps its centre, so that the next corner is drawn there
			t = b+1;
		}
		else {
			// a way changes its grade on the edge between two tiles, so the line bends
			// there too. The corner is left out where the grade does not change, which
			// is every tile of level ground: those keep the corners they always had.
			const route_point_t corner = { t, true, (uint8)(area.outcode( route[t] ) & area.outcode( route[t+1] )) };
			if(  corner.code == 0  &&  schedule_route_edge_is_corner( welt, route, t )  ) {
				display_route_segment( welt, viewport, route, previous, corner, centre, col, dark, core, edge );
				previous = corner;
			}
			t++;
		}
		const route_point_t here = { t, false, area.outcode( route[t] ) };
		display_route_segment( welt, viewport, route, previous, here, centre, col, dark, core, edge );
		previous = here;
	}
}
#endif


void main_view_t::display(bool force_dirty)
{
	const uint32 rs = get_random_seed();

#if COLOUR_DEPTH != 0
	DBG_DEBUG4("main_view_t::display", "starting ...");
	gfx->set_image_procs(true);

	const scr_size screen = gfx->get_screen_size();
	const sint16 IMG_SIZE = gfx->get_tile_raster_width();

	const sint16 disp_height = screen.h - win_get_statusbar_height() - (!ticker::empty() ? TICKER_HEIGHT : 0);

	scr_rect clip_rr(0, env_t::iconsize.w, screen.w, disp_height - env_t::iconsize.h);
	switch (env_t::menupos) {
	case MENU_TOP:
		// rect default
		break;
	case MENU_BOTTOM:
		clip_rr.y = win_get_statusbar_height() + (!ticker::empty() ? TICKER_HEIGHT : 0);
		break;
	case MENU_LEFT:
		clip_rr = scr_rect(env_t::iconsize.w, 0, screen.w - env_t::iconsize.w, disp_height);
		break;
	case MENU_RIGHT:
		clip_rr = scr_rect(0, 0, screen.w - env_t::iconsize.w, disp_height);
		break;
	}

	gfx->set_clip_rect(clip_rr.x, clip_rr.y, clip_rr.w, clip_rr.h CLIP_NUM_DEFAULT, false);

	// redraw everything?
	force_dirty = force_dirty || welt->is_dirty();
	welt->unset_dirty();
	if(  force_dirty  ) {
		gfx->mark_screen_dirty();
		welt->set_background_dirty();
		force_dirty = false;
	}

	const int dpy_width  = screen.w / IMG_SIZE + 2;
	const int dpy_height = (screen.h*4)/IMG_SIZE;

	const int i_off = viewport->get_world_position().x + viewport->get_viewport_ij_offset().x;
	const int j_off = viewport->get_world_position().y + viewport->get_viewport_ij_offset().y;
	const int const_x_off = viewport->get_x_off();
	const int const_y_off = viewport->get_y_off();

	// change to night mode?
	// images will be recalculated only, when there has been a change, so we set always
	if(grund_t::underground_mode == grund_t::ugm_all) {
		gfx->set_daynight_level(0);
	}
	else if(!env_t::night_shift) {
		gfx->set_daynight_level(env_t::daynight_level);
	}
	else {
		// calculate also days if desired
		uint32 month = welt->get_last_month();
		const uint32 ticks_this_month = welt->get_ticks() % welt->ticks_per_world_month;
		uint32 hours2;
		if (env_t::show_month > env_t::DATE_FMT_MONTH) {
			static sint32 days_per_month[12]={31,28,31,30,31,30,31,31,30,31,30,31};
			hours2 = (((sint64)ticks_this_month*days_per_month[month]) >> (welt->ticks_per_world_month_shift-17));
			hours2 = ((hours2*3) / 8192) % 48;
		}
		else {
			hours2 = ( (ticks_this_month * 3) >> (welt->ticks_per_world_month_shift-4) )%48;
		}
		gfx->set_daynight_level(hours2night[hours2]+env_t::daynight_level);
	}

	// not very elegant, but works:
	// fill everything with black for Underground mode ...
	if( grund_t::underground_mode ) {
		gfx->draw_rect(clip_rr.x, clip_rr.y, clip_rr.w, clip_rr.h, gfx->palette_lookup(COL_BLACK), force_dirty);
	}
	else if( welt->is_background_dirty()  &&  outside_visible  ) {
		// we check if background will be visible, no need to clear screen if it's not.
		display_background(clip_rr.x, clip_rr.y, clip_rr.w, clip_rr.h, force_dirty);
		welt->unset_background_dirty();
		// reset
		outside_visible = false;
	}
	// to save calls to grund_t::get_disp_height
	// gr->get_disp_height() == min(gr->get_hoehe(), hmax_ground)
	const sint8 hmax_ground = (grund_t::underground_mode==grund_t::ugm_level) ? grund_t::underground_level : 127;

	// lower limit for y: display correctly water/outside graphics at upper border of screen
	int y_min = (-const_y_off + 4*tile_raster_scale_y( min(hmax_ground, welt->min_height)*TILE_HEIGHT_STEP, IMG_SIZE )
					+ 4*(clip_rr.y-IMG_SIZE)-IMG_SIZE/2-1) / IMG_SIZE;

	// prepare view
	rect_t const world_rect(koord(0, 0), welt->get_size());

	koord const estimated_min(((y_min+(-2-((y_min+dpy_width) & 1))) >> 1) + i_off,
		((y_min-(clip_rr.w - const_x_off) / (IMG_SIZE/2) - 1) >> 1) + j_off);

	sint16 const worst_case_mountain_extra = (welt->max_height - welt->min_height) / 2;
	koord const estimated_max((((dpy_height+4*4)+(screen.w - const_x_off) / (IMG_SIZE/2) - 1) >> 1) + i_off + worst_case_mountain_extra,
		(((dpy_height+4*4)-(-2-(((dpy_height+4*4)+dpy_width) & 1))) >> 1) + j_off + worst_case_mountain_extra);

	rect_t view_rect(estimated_min, estimated_max - estimated_min + koord(1, 1));
	view_rect.mask(world_rect);

	if (view_rect != viewport->prepared_rect) {
		welt->prepare_tiles(view_rect, viewport->prepared_rect);
		viewport->prepared_rect = view_rect;
	}

#ifdef MULTI_THREAD
	if(  can_multithreading  ) {
		if(  !spawned_threads  ) {
			// we can do the parallel display using posix threads ...
			pthread_t thread[MAX_THREADS];
			/* Initialize and set thread detached attribute */
			pthread_attr_t attr;
			pthread_attr_init( &attr );
			pthread_attr_setdetachstate( &attr, PTHREAD_CREATE_DETACHED );
			// init barrier
			simthread_barrier_init( &display_barrier_start, NULL, env_t::num_threads );
			simthread_barrier_init( &display_barrier_end, NULL, env_t::num_threads );

			for(  int t = 0;  t < env_t::num_threads - 1;  t++  ) {
				if(  pthread_create( &thread[t], &attr, display_region_thread, (void *)&ka[t] )  ) {
					can_multithreading = false;
					dbg->error( "main_view_t::display()", "cannot multi-thread, error at thread #%i", t+1 );
					return;
				}
			}
			spawned_threads = true;
			pthread_attr_destroy( &attr );
		}

		// set parameter for each thread
		const scr_coord_val wh_x = clip_rr.w / env_t::num_threads;
		scr_coord_val lt_x = clip_rr.x;
		for(  int t = 0;  t < env_t::num_threads - 1;  t++  ) {
			ka[t].show_routine = this;
			ka[t].lt_cl = koord( lt_x, clip_rr.y );
			ka[t].wh_cl = koord( wh_x, clip_rr.h );
			ka[t].lt = ka[t].lt_cl - koord( IMG_SIZE/2, 0 ); // process tiles IMG_SIZE/2 outside clipping range for correct tree display at thread seams
			ka[t].wh = ka[t].wh_cl + koord( IMG_SIZE, 0 );
			ka[t].y_min = y_min;
			ka[t].y_max = dpy_height + 4 * 4;
			ka[t].thread_num = t;
			lt_x += wh_x;
		}

		// init variables required to draw smart cursor
		threads_req_pause = false;
		num_threads_paused = 0;

		// and start drawing
		simthread_barrier_wait( &display_barrier_start );

		// the last we can run ourselves, setting clip_wh to the screen edge instead of wh_x (in case disp_width % num_threads != 0)
		gfx->clear_all_poly_clip( env_t::num_threads - 1 );
		gfx->set_clip_rect( lt_x, clip_rr.y, clip_rr.w, clip_rr.h, env_t::num_threads - 1, false);
		display_region( koord( lt_x - IMG_SIZE / 2, clip_rr.y ), koord( clip_rr.x + clip_rr.w + IMG_SIZE, clip_rr.h ), y_min, dpy_height + 4 * 4, false, true, env_t::num_threads - 1 );

		simthread_barrier_wait( &display_barrier_end );

		gfx->clear_all_poly_clip( CLIP_NUM_DEFAULT_VALUE );
		gfx->set_clip_rect(clip_rr.x, clip_rr.y, clip_rr.w, clip_rr.h CLIP_NUM_DEFAULT, false);
	}
	else {
		// slow serial way of display
		gfx->clear_all_poly_clip( CLIP_NUM_DEFAULT_VALUE );
		display_region( koord(clip_rr.x, clip_rr.y), koord(clip_rr.w, clip_rr.h), y_min, dpy_height + 4 * 4, false, false, 0 );
	}
#else
	gfx->clear_all_poly_clip();
	display_region(koord(clip_rr.x, clip_rr.y), koord(clip_rr.w, clip_rr.h), y_min, dpy_height + 4 * 4, false );
#endif

	// and finally overlays (station coverage and signs)
	bool plotted = false; // display overlays even on very large mountains
	for(sint16 y=y_min; y<dpy_height+4*4  ||  plotted; y++) {
		const sint16 ypos = y*(IMG_SIZE/4) + const_y_off;
		plotted = false;

		for( sint16 x = -2-((y+dpy_width) & 1); (x*(IMG_SIZE/2) + const_x_off)<clip_rr.x+clip_rr.w; x += 2 ) {

			const sint16 i = ((y + x) >> 1) + i_off;
			const sint16 j = ((y - x) >> 1) + j_off;
			const sint16 xpos = x * (IMG_SIZE / 2) + const_x_off;

			if(  xpos+IMG_SIZE>0  ) {
				const planquadrat_t *plan=welt->access(i,j);
				if(plan  &&  plan->get_kartenboden()) {
					const grund_t *gr = plan->get_kartenboden();
					sint16 yypos = ypos - tile_raster_scale_y( min(gr->get_hoehe(),hmax_ground)*TILE_HEIGHT_STEP, IMG_SIZE);
					if(  yypos-IMG_SIZE < clip_rr.get_bottom()  &&  yypos+IMG_SIZE>=clip_rr.y  ) {
						plan->display_overlay( xpos, yypos );
						plotted = true;
					}
				}
			}
		}
	}

	// route of the schedule shown by a schedule editor (display only, see karte_t)
	const vector_tpl<koord3d> &schedule_route = welt->get_schedule_route();
	if(  !schedule_route.empty()  ) {
		DBG_DEBUG4("main_view_t::display", "display schedule route");
		const player_t *pl = welt->get_player( welt->get_schedule_route_player_nr() );
		const PIXVAL col  = gfx->palette_lookup( pl ? pl->get_player_color1()+3 : COL_WHITE );
		const PIXVAL dark = gfx->palette_lookup( COL_BLACK );
		// centre of the top surface of a tile, in the internal 64 per tile units
		const koord centre( OBJECT_OFFSET_STEPS*2, OBJECT_OFFSET_STEPS*3 );
		// The line grows when zooming in, so that it does not get lost on a large tile,
		// and keeps a visible minimum when zooming out. Zooming in only reaches twice the
		// tile size, hence the half steps; even at its widest the line is a few pixels on
		// a tile of at least 128, so the way below it stays visible.
		const sint16 core = clamp( (2*IMG_SIZE)/gfx->get_base_tile_raster_width() - 1, 1, 3 );
		const sint16 edge = (core+1)/2;
		// the same area the tile loop above walked, with room to spare for the line width,
		// for tall ground and for a tile that only sticks into the view by a corner
		route_area_t area;
		area.i_off = i_off;
		area.j_off = j_off;
		area.u_lim = dpy_width + 16;
		area.v_lo  = -64;
		area.v_hi  = dpy_height + 4*4 + 64;

		// koord3d::invalid separates legs without a route: each stretch is drawn on its own
		const uint32 count = schedule_route.get_count();
		uint32 first = 0;
		while(  first < count  ) {
			if(  schedule_route[first] == koord3d::invalid  ) {
				first++;
				continue;
			}
			uint32 last = first;
			while(  last+1 < count  &&  schedule_route[last+1] != koord3d::invalid  ) {
				last++;
			}
			display_route_stretch( welt, viewport, schedule_route, first, last, centre, col, dark, core, edge, area );
			first = last+1;
		}
	}

	obj_t *zeiger = welt->get_zeiger();
	DBG_DEBUG4("main_view_t::display", "display pointer");
	if( zeiger  &&  zeiger->get_pos() != koord3d::invalid ) {
		bool dirty = zeiger->get_flag(obj_t::dirty);

		scr_coord background_pos = viewport->get_screen_coord(zeiger->get_pos());
		scr_coord pointer_pos = background_pos + viewport->scale_offset(koord(zeiger->get_xoff(),zeiger->get_yoff()));

		// mark the cursor position for all tools (except lower/raise)
		if(zeiger->get_yoff()==Z_PLAN) {
			grund_t *gr = welt->lookup( zeiger->get_pos() );
			if(gr && gr->is_visible()) {
				const FLAGGED_PIXVAL transparent = TRANSPARENT25_FLAG|OUTLINE_FLAG| env_t::cursor_overlay_color;
				if(  gr->get_image()==IMG_EMPTY  ) {
					if(  gr->hat_wege()  ) {
						gfx->draw_img_blend( gr->obj_bei(0)->get_image(), background_pos.x, background_pos.y, transparent, 0, dirty );
					}
					else {
						gfx->draw_img_blend( ground_desc_t::get_ground_tile(gr), background_pos.x, background_pos.y, transparent, 0, dirty );
					}
				}
				else if(  gr->get_typ()==grund_t::wasser  ) {
					gfx->draw_img_blend( ground_desc_t::sea->get_image(gr->get_image(),wasser_t::stage), background_pos.x, background_pos.y, transparent, 0, dirty );
				}
				else {
					gfx->draw_img_blend( gr->get_image(), background_pos.x, background_pos.y, transparent, 0, dirty );
				}
			}
		}
		zeiger->display( pointer_pos.x , pointer_pos.y  CLIP_NUM_DEFAULT);
		zeiger->clear_flag( obj_t::dirty );
	}

	if(welt) {
		// show players income/cost messages
		switch (env_t::show_money_message) {

			case 0:
				// show messages of all players
				for(int x=0; x<MAX_PLAYER_COUNT; x++) {
					if(  welt->get_player(x)  ) {
						welt->get_player(x)->display_messages();
					}
				}
				break;

			case 1:
				// show message of active player
				if (welt->get_active_player()) {
					welt->get_active_player()->display_messages();
				}
				break;

			default: // no messages
				break;
		}

	}

	assert( rs == get_random_seed() ); (void)rs;

#else
	(void)force_dirty;
	(void)rs;
#endif
}

void main_view_t::clear_prepared() const
{
	viewport->prepared_rect.discard_area();
}


#ifdef MULTI_THREAD
void main_view_t::display_region( koord lt, koord wh, sint16 y_min, sint16 y_max, bool /*force_dirty*/, bool threaded, const sint8 clip_num )
#else
void main_view_t::display_region( koord lt, koord wh, sint16 y_min, sint16 y_max, bool /*force_dirty*/ )
#endif
{
	const sint16 IMG_SIZE = gfx->get_tile_raster_width();

	const int i_off = viewport->get_world_position().x + viewport->get_viewport_ij_offset().x;
	const int j_off = viewport->get_world_position().y + viewport->get_viewport_ij_offset().y;
	const int const_x_off = viewport->get_x_off();
	const int const_y_off = viewport->get_y_off();

	const scr_size screen = gfx->get_screen_size();
	const int dpy_width = screen.w / IMG_SIZE + 2;

	// to save calls to grund_t::get_disp_height
	const sint8 hmax_ground = (grund_t::underground_mode == grund_t::ugm_level) ? grund_t::underground_level : 127;

	// prepare for selectively display
	const koord cursor_pos = welt->get_zeiger() ? welt->get_zeiger()->get_pos().get_2d() : koord(-1000, -1000);
	const bool needs_hiding = !env_t::hide_trees  ||  (env_t::hide_buildings != env_t::ALL_HIDDEN_BUILDING);

	for(  int y = y_min;  y < y_max;  y++  ) {
		const sint16 ypos = y * (IMG_SIZE / 4) + const_y_off;
		// plotted = we plotted something
		bool plotted = false;

		for(  sint16 x = -2 - ((y  +dpy_width) & 1);  (x * (IMG_SIZE / 2) + const_x_off) < (lt.x + wh.x);  x += 2  ) {
			const sint16 i = ((y + x) >> 1) + i_off;
			const sint16 j = ((y - x) >> 1) + j_off;
			const sint16 xpos = x * (IMG_SIZE / 2) + const_x_off;

			if(  xpos + IMG_SIZE > lt.x  ) {
				const koord pos(i, j);
				if(  grund_t* const kb = welt->lookup_kartenboden(pos)  ) {
					const sint16 yypos = ypos - tile_raster_scale_y( min( kb->get_hoehe(), hmax_ground ) * TILE_HEIGHT_STEP, IMG_SIZE );
					if(  yypos - IMG_SIZE < lt.y + wh.y  &&  yypos + IMG_SIZE > lt.y  ) {
#ifdef MULTI_THREAD
						bool force_show_grid = false;
						if(  env_t::hide_under_cursor  ) {
							const uint32 cursor_dist = shortest_distance( pos, cursor_pos );
							if(  cursor_dist <= env_t::cursor_hide_range + 2u  ) {  // +2 to allow for rapid diagonal movement
								kb->set_flag( grund_t::dirty );
								if(  cursor_dist <= env_t::cursor_hide_range  ) {
									force_show_grid = true;
								}
							}
						}
						kb->display_if_visible( xpos, yypos, IMG_SIZE, clip_num, force_show_grid );
#else
						if(  env_t::hide_under_cursor  ) {
							const bool saved_grid = grund_t::show_grid;
							const uint32 cursor_dist = shortest_distance( pos, cursor_pos );
							if(  cursor_dist <= env_t::cursor_hide_range + 2u  ) {
								kb->set_flag( grund_t::dirty );
								if(  cursor_dist <= env_t::cursor_hide_range  ) {
									grund_t::show_grid = true;
								}
							}
							kb->display_if_visible( xpos, yypos, IMG_SIZE );
							grund_t::show_grid = saved_grid;
						}
						else {
							kb->display_if_visible( xpos, yypos, IMG_SIZE );
						}
#endif
						plotted = true;

					}
					// not on screen? We still might need to plot the border ...
					else if(  env_t::draw_earth_border  &&  (pos.x-welt->get_size().x+1 == 0  ||  pos.y-welt->get_size().y+1 == 0)  ) {
						kb->display_border( xpos, yypos, IMG_SIZE  CLIP_NUM_PAR);
					}
				}
				else {
					// check if outside visible
					outside_visible = true;
					if(  env_t::draw_outside_tile  ) {
						const sint16 yypos = ypos - tile_raster_scale_y( welt->min_height * TILE_HEIGHT_STEP, IMG_SIZE );
						gfx->draw_normal( ground_desc_t::outside->get_image(0), xpos, yypos, 0, true, false  CLIP_NUM_PAR);
					}
				}
			}
		}
		// increase lower bound if nothing is visible
		if(  !plotted  ) {
			if (y == y_min) {
				y_min++;
			}
		}
		// increase upper bound if something is visible
		else {
			if (y == y_max-1) {
				y_max++;
			}
		}
	}

	// and then things (and other ground)
	// especially necessary for vehicles
	for(  int y = y_min;  y < y_max;  y++  ) {
		const sint16 ypos = y * (IMG_SIZE / 4) + const_y_off;

		for(  sint16 x = -2 - ((y + dpy_width) & 1);  (x * (IMG_SIZE / 2) + const_x_off) < (lt.x + wh.x);  x += 2  ) {
			const int i = ((y + x) >> 1) + i_off;
			const int j = ((y - x) >> 1) + j_off;
			const int xpos = x * (IMG_SIZE / 2) + const_x_off;

			if(  xpos + IMG_SIZE > lt.x  ) {
				const planquadrat_t *plan = welt->access(i,j);
				if(  plan  &&  plan->get_kartenboden()  ) {
					const grund_t *gr = plan->get_kartenboden();
					// minimum height: ground height for overground,
					// for the definition of underground_level see grund_t::set_underground_mode
					const sint8 hmin = min( gr->get_hoehe(), grund_t::underground_level );

					// maximum height: 127 for overground, underground level for sliced, ground height-1 for complete underground view
					const sint8 hmax = grund_t::underground_mode == grund_t::ugm_all ? gr->get_hoehe() - (!gr->ist_tunnel()) : grund_t::underground_level;

					/* long version
					switch(grund_t::underground_mode) {
						case ugm_all:
							hmin = -128;
							hmax = gr->get_hoehe()-(!gr->ist_tunnel());
							underground_level = -128;
							break;
						case ugm_level:
							hmin = min(gr->get_hoehe(), underground_level);
							hmax = underground_level;
							underground_level = level;
							break;
						case ugm_none:
							hmin = gr->get_hoehe();
							hmax = 127;
							underground_level = 127;
					} */
					sint16 yypos = ypos - tile_raster_scale_y( min( gr->get_hoehe(), hmax_ground ) * TILE_HEIGHT_STEP, IMG_SIZE );
					if(  yypos - IMG_SIZE * 3 < wh.y + lt.y  &&  yypos + IMG_SIZE > lt.y  ) {
						const koord pos(i,j);
						if(  env_t::hide_under_cursor  &&  needs_hiding  ) {
							// If the corresponding setting is on, then hide trees and buildings under mouse cursor
#ifdef MULTI_THREAD
							if(  threaded  ) {
								pthread_mutex_lock( &hide_mutex );
								if(  threads_req_pause  ) {
									// another thread is requesting we pause
									num_threads_paused++;
									pthread_cond_broadcast( &waiting_cond ); // signal the requesting thread that another thread has paused

									// wait until no longer requested to pause
									while(  threads_req_pause  ) {
										pthread_cond_wait( &hiding_cond, &hide_mutex );
									}

									num_threads_paused--;
								}
								if(  shortest_distance( pos, cursor_pos ) <= env_t::cursor_hide_range  ) {
									// wait until all threads are paused
									threads_req_pause = true;
									while(  num_threads_paused < env_t::num_threads - 1  ) {
										pthread_cond_wait( &waiting_cond, &hide_mutex );
									}

									// proceed with drawing in the hidden area singlethreaded
									const bool saved_hide_trees = env_t::hide_trees;
									const uint8 saved_hide_buildings = env_t::hide_buildings;
									env_t::hide_trees = true;
									env_t::hide_buildings = env_t::ALL_HIDDEN_BUILDING;

									plan->display_obj( xpos, yypos, IMG_SIZE, true, hmin, hmax, clip_num );

									env_t::hide_trees = saved_hide_trees;
									env_t::hide_buildings = saved_hide_buildings;

									// unpause all threads
									threads_req_pause = false;
									pthread_cond_broadcast( &hiding_cond );
									pthread_mutex_unlock( &hide_mutex );
								}
								else {
									// not in the hidden area, draw multithreaded
									pthread_mutex_unlock( &hide_mutex );
									plan->display_obj( xpos, yypos, IMG_SIZE, true, hmin, hmax, clip_num );
								}
							}
							else {
#endif
								if(  shortest_distance( pos, cursor_pos ) <= env_t::cursor_hide_range  ) {
									const bool saved_hide_trees = env_t::hide_trees;
									const uint8 saved_hide_buildings = env_t::hide_buildings;
									env_t::hide_trees = true;
									env_t::hide_buildings = env_t::ALL_HIDDEN_BUILDING;

									plan->display_obj( xpos, yypos, IMG_SIZE, true, hmin, hmax  CLIP_NUM_PAR);

									env_t::hide_trees = saved_hide_trees;
									env_t::hide_buildings = saved_hide_buildings;
								}
								else {
									plan->display_obj( xpos, yypos, IMG_SIZE, true, hmin, hmax  CLIP_NUM_PAR);
								}
#ifdef MULTI_THREAD
							}
#endif
						}
						else {
							// hiding turned off, draw multithreaded
							plan->display_obj( xpos, yypos, IMG_SIZE, true, hmin, hmax  CLIP_NUM_PAR);
						}
					}
				}
			}
		}
	}
#ifdef MULTI_THREAD
	// show thread as paused when finished
	if(  threaded  ) {
		pthread_mutex_lock( &hide_mutex );
		num_threads_paused++;
		pthread_cond_broadcast( &waiting_cond );
		pthread_mutex_unlock( &hide_mutex );
	}
#endif
}


void main_view_t::display_background( scr_coord_val xp, scr_coord_val yp, scr_coord_val w, scr_coord_val h, bool dirty )
{
	if(  !(env_t::draw_earth_border  &&  env_t::draw_outside_tile)  ) {
		gfx->draw_rect(xp, yp, w, h, env_t::background_color, dirty );
	}
}
