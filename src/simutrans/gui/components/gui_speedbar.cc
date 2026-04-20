/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#include <string.h>

#include "gui_speedbar.h"
#include "../gui_theme.h"
#include "../../display/simgraph.h"
#include "../../simcolor.h"
#include "../../simtypes.h"


void gui_speedbar_t::set_base(sint32 base)
{
	this->base = base!=0 ? base : 1;
}


void gui_speedbar_t::add_color_value(const sint32 *value, PIXVAL color)
{
	info_t  next =  { color, value, -1 };
	values.insert(next);
}


scr_size gui_speedbar_t::get_min_size() const
{
	return D_INDICATOR_SIZE;
}

scr_size gui_speedbar_t::get_max_size() const
{
	return scr_size(scr_size::inf.w, D_INDICATOR_HEIGHT);
}

void gui_speedbar_t::draw(scr_coord offset)
{
	offset += pos;

	if(vertical) {
		sint32 from = size.h;
		for(info_t const& i : values) {
			sint32 const to = size.h - min(*i.value, base) * size.h / base;
			if(to < from) {
				gfx->draw_rect_clipped(offset.x, offset.y + to, size.w, from - to, i.color, true CLIP_NUM_DEFAULT);
				from = to - 1;
			}
		}
		if(from > 0) {
			gfx->draw_rect_clipped( offset.x, offset.y, size.w, from, gfx->palette_lookup(MN_GREY0), true CLIP_NUM_DEFAULT);
		}
	}
	else {
		sint32 from = 0;
		for(info_t const& i : values) {
			sint32 const to = min(*i.value, base) * size.w / base;
			if(to > from) {
				gfx->draw_rect_clipped(offset.x + from, offset.y, to - from, size.h, i.color, true CLIP_NUM_DEFAULT);
				from = to + 1;
			}
		}
		if(from < size.w) {
			gfx->draw_rect_clipped(offset.x + from, offset.y, size.w - from, size.h, gfx->palette_lookup(MN_GREY0), true CLIP_NUM_DEFAULT);
		}
	}
}

void gui_speedbar_fixed_length_t::draw(scr_coord offset)
{
	offset += pos;

	sint32 from = 0;
	for (info_t const& i : values) {
		sint32 const to = min(*i.value, base) * fixed_width / base;
		if (to > from) {
			gfx->draw_rect_clipped(offset.x + from, offset.y, to - from, size.h, i.color, true CLIP_NUM_DEFAULT);
			from = to + 1;
		}
		if (from > size.w) {
			// reached size already
			break;
		}
	}
	if (from < size.w) {
		gfx->draw_rect_clipped(offset.x + from, offset.y, size.w - from, size.h, gfx->palette_lookup(MN_GREY0), true CLIP_NUM_DEFAULT);
	}
}

void gui_routebar_t::set_base(sint32 base)
{
	this->base = base != 0 ? base : 1;
}

void gui_routebar_t::set_reservation(const sint32 *value, PIXVAL color)
{
	reserve_value = value;
	reserved_color= color;
}

void gui_routebar_t::init(const sint32 *value, uint8 state)
{
	this->value = value;
	this->state = state;
}

void gui_routebar_t::set_state(uint8 state)
{
	this->state = state;
}


void gui_routebar_t::draw(scr_coord offset)
{
	uint8  h = size.h % 2 ? size.h : size.h-1;
	if (h < 5) { h = 5; set_size( scr_size(size.w, h) ); }
	const uint16 w = size.w - h/2;

	offset += pos;
	gfx->draw_rect_clipped(offset.x, offset.y+h/2-1, w, 3, gfx->palette_lookup(MN_GREY1), true CLIP_NUM_DEFAULT);

	PIXVAL col;
	for (uint8 i = 0; i<5; i++) {
		col = i % 2 ? COL_GREY4-1 : MN_GREY0;
		gfx->draw_vline_clipped(offset.x + h/2 + w*i/4, offset.y+i%2, h-(i%2)*2, gfx->palette_lookup(col), true CLIP_NUM_DEFAULT);
	}
	sint32 const to = min(*value, base) * w / base;
	if (reserve_value  &&  *reserve_value) {
		sint32 const reserved_to = min(*reserve_value, base) * w / base;
		gfx->draw_rect_clipped(offset.x + h / 2, offset.y + h / 2 - 1, reserved_to, 3, reserved_color, true CLIP_NUM_DEFAULT);
	}
	gfx->draw_rect_clipped(offset.x+h/2, offset.y+h/2-1, to, 3, gfx->palette_lookup(43), true CLIP_NUM_DEFAULT);

	switch (state)
	{
		case 1:
			gfx->draw_rect_clipped(offset.x + to + 1, offset.y + 1, h - 2, h - 2, gfx->palette_lookup(COL_YELLOW), true CLIP_NUM_DEFAULT);
			break;
		case 2:
			gfx->draw_rect_clipped(offset.x + to + 1, offset.y + 1, h - 2, h - 2, gfx->palette_lookup(COL_ORANGE), true CLIP_NUM_DEFAULT);
			break;
		case 3:
			gfx->draw_rect_clipped(offset.x + to + 1, offset.y + 1, h - 2, h - 2, gfx->palette_lookup(COL_RED), true CLIP_NUM_DEFAULT);
			break;
		case 0:
		default:
			gfx->draw_rect_clipped( offset.x+h/2, offset.y + 1, to-2, h - 2, gfx->palette_lookup( COL_GREEN ), true CLIP_NUM_DEFAULT);
			gfx->draw_right_triangle(offset.x + to, offset.y, h, gfx->palette_lookup(COL_MAGENTA), true);
			break;
	}
}

scr_size gui_routebar_t::get_min_size() const
{
	return scr_size(D_INDICATOR_WIDTH, height);
}

scr_size gui_routebar_t::get_max_size() const
{
	return scr_size(scr_size::inf.w, height);
}
