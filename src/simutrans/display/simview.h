/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#ifndef DISPLAY_SIMVIEW_H
#define DISPLAY_SIMVIEW_H


#include "simgraph.h"


class karte_t;
class koord3d;
class viewport_t;
template<class T> class vector_tpl;


/**
 * Height of the way surface at one corner of the route a schedule editor shows, in half
 * height levels: the centre of the tile route[step], or the middle of the edge that tile
 * shares with route[step+1].
 *
 * The route holds ground positions - route_t stores grund_t::get_pos() - whose z is the
 * base height of a tile, that is its lowest corner. The way on that ground can be higher:
 * it climbs across a tile that is a slope, and on the head of a bridge that starts on
 * already sloped ground the way is flat but the whole tile content is lifted a level or
 * two. grund_t::get_vmove() answers both of those together for one edge of a tile, so
 * none of that geometry is repeated here.
 *
 * It is not part of the drawing code, which a headless build does not compile at all, so
 * that the automated tests can check it.
 */
sint32 schedule_route_way_height2(const karte_t *welt, const vector_tpl<koord3d> &route, uint32 step, bool is_edge);


/**
 * Whether the route a schedule editor shows bends where it crosses the edge between
 * route[step] and route[step+1].
 *
 * A way keeps one grade across a tile and changes it on the edge to the next one, so a
 * straight line from one tile centre to the next leaves the way surface on that edge by
 * a quarter of the change of grade there, and needs a corner of its own to follow it.
 * Where the grade does not change the edge lies on that line already and stays implicit,
 * which is what keeps ground without a slope exactly as it was drawn before.
 *
 * Height is all that can part the two: the tiles are neighbours, so the middle of the
 * line between their centres is the middle of the edge they share.
 *
 * Outside the drawing code for the same reason as schedule_route_way_height2().
 */
bool schedule_route_edge_is_corner(const karte_t *welt, const vector_tpl<koord3d> &route, uint32 step);


/**
 * World view class, it contains the routines that handle world display to the pixel buffer.
 * @brief View for the simulated world.
 */
class main_view_t
{
private:
	/// The simulated world this view is associated to.
	karte_t *welt;
	/// We cache the camera here, it's the camera what we are supposed to render, not the whole world.
	viewport_t *viewport;

	/// Cached value from last display run to determine if the background was visible, we'll save redraws if it was not.
	bool outside_visible;

public:
	main_view_t(karte_t *welt);

	/**
	 * Draws the visible world on screen.
	 * @param dirty If set to true, will mark the whole screen as dirty.
	 * @see display_flush_buffer() for the consequences of setting screen areas dirty.
	 */
	void display(bool dirty);

	/**
	 * @brief Clears the prepared area of the view.
	 *
	 * Sets the prepared area of this view to no area. The entire view will have
	 * to be reprepared on next display call. Intended when the entire world has
	 * changed, eg switching underground mode or layer.
	 */
	void clear_prepared() const;

	/**
	 * Draws the simulated world in the specified rectangular area of the pixel buffer. This is a internal function of the class.
	 * <br>
	 * See lt and wt as the absolute limit a pixel this routine can draw, a clipping rectangle. y_min and y_max are the coordinates this routine starts,
	 * locating and drawing objects. This mechanic is due to the fact objects are drawn in relation of their top-left pixel, and that coordinate might be outside
	 * the clipping rectangle. Think of water tiles on the top of screen of high buildings that fall over the bottom of screen, but so high that their top has to
	 * remain visible.
	 * 
	 * @param lt Top-left pixel coordinate of the rectangle. In pixels.
	 * @param wh Width and height f the rectangle. In pixels.
	 * @param y_min Minimum height of the screen (top pixel row) to start processing objects to draw.
	 * @param y_max Maximum height of the screen (bottom pixel row) to start processing objects to draw.
	 * @param force_dirty If set to true, will mark the whole rectangle as dirty.
	 * @param threaded If set to true, indicates there are more threads drawing on screen, and this routine will use mutexes when needed.
	 */
#ifdef MULTI_THREAD
	void display_region( koord lt, koord wh, sint16 y_min, const sint16 y_max, bool force_dirty, bool threaded, const sint8 clip_num );
#else
	void display_region( koord lt, koord wh, sint16 y_min, const sint16 y_max, bool force_dirty );
#endif

private:
	/**
	 * Draws background in the specified rectangular screen coordinates.
	 * @param xp X screen coordinate of the left-top corner.
	 * @param yp Y screen coordinate y of the left-top corner.
	 * @param w Width of the rectangle to draw.
	 * @param h Height of the rectangle to draw.
	 * @param dirty Mark the specified area as dirty.
	 */
	void display_background( scr_coord_val xp, scr_coord_val yp, scr_coord_val w, scr_coord_val h, bool dirty );
};

#endif
