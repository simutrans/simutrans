/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#include <stdio.h>

#include "simwin.h"
#include "../simskin.h"

#include "../tool/simmenu.h"
#include "../player/simplay.h"
#include "../world/simworld.h"

#include "../builder/brueckenbauer.h"
#include "../builder/tunnelbauer.h"
#include "../builder/wegbauer.h"

#include "../dataobj/translator.h"
#include "../dataobj/environment.h"
#include "../dataobj/scenario.h"

#include "../obj/way/kanal.h"
#include "../obj/way/maglev.h"
#include "../obj/way/monorail.h"
#include "../obj/way/narrowgauge.h"
#include "../obj/way/runway.h"
#include "../obj/way/schiene.h"
#include "../obj/way/strasse.h"
#include "../obj/bruecke.h"
#include "../descriptor/tunnel_desc.h"

#include "../utils/unicode.h"
#include "../tool/simmenu.h"
#include "../tool/simtool.h"

#include "way_builder_frame.h"

#include "components/gui_scrolled_list.h"

class way_selection_t {
public:
	waytype_t wt;
	const way_desc_t* way;
	const bridge_desc_t* bridge;
	const tunnel_desc_t* tunnel;
	bool straight;
	bool keep;
	bool terraform;
	way_selection_t() :
		wt(invalid_wt),
		way(0),
		bridge(0),
		tunnel(0),
		straight(false),
		keep(false)
	{
	}
};

// all waytype (rail, road, tram, monorail, maglev, narrogauge, 
static way_selection_t selected_way[MAX_PLAYER_COUNT][MAX_WAYTYPE_TABS];

/// selected tab per player
static uint8 selected_tab[MAX_PLAYER_COUNT] = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };

static uint8 active_player_nr = 255;
static uint8 active_tab = -1;

static vector_tpl<char *>way_strings;
static vector_tpl<const way_desc_t*>way_descs;
static vector_tpl<char *>bridge_strings;
static vector_tpl<const bridge_desc_t*>bridge_descs;
static vector_tpl<char *>tunnel_strings;
static vector_tpl<const tunnel_desc_t*>tunnel_descs;

static bool pending_tool_update = false;

static image_id empty_selection;

const char* generate_description(const char* name, uint32 speed, sint64 price, sint64 maintenance, bool elevated, sint64 span)
{
	static char toolstr[1024];
	int n = sprintf(toolstr, "%s, %d km/h, ", translator::translate(name), speed);
	money_to_string(toolstr + n, (double)price / 100.0);
	n += strlen(toolstr + n);
	if (maintenance) {
		toolstr[n] = '+';
		money_to_string(toolstr + n + 1, (double)(world()->scale_with_month_length(maintenance)) / 100.0);
		//strcat(toolstr, translator::translate("/month"));
	}
	if (span) {
		n += strlen(toolstr + n);
		n += sprintf(toolstr+n, ", l<%d", span);
	}
	if (elevated) {
		strcat(toolstr+n, translator::translate(" (elevated)"));
	}
	return toolstr;
}



scr_size gui_image_combobox_t::get_min_size() const
{
	return env_t::iconsize;
}

void gui_image_combobox_t::draw(scr_coord offset)
{
	gui_combobox_t::draw(offset);
	img.draw(offset+get_pos());

	// to be fixed: streching
//	gfx->fit_img_to_width(back_img, env_t::iconsize.w);
//	gfx->draw_color_img(back_img, draw_pos.x, draw_pos.y, welt->get_active_player_nr(), false, true CLIP_NUM_DEFAULT);
}

void gui_image_combobox_t::set_size(scr_size size)
{
	gui_combobox_t::set_size(size);

	textinp.set_size(env_t::iconsize);

	bt_prev.set_pos(scr_coord(0,0));
	bt_next.set_pos(scr_coord(0,0));
	img.set_pos(scr_coord(0, 0));
}


gui_image_combobox_t::gui_image_combobox_t(gui_scrolled_list_t::item_compare_func cmp) :
	gui_combobox_t(cmp)
{
	textinp.set_visible(false);
	bt_prev.set_visible(false);
	bt_next.set_visible(false);
	empty_selection = skinverwaltung_t::menu_icon ? skinverwaltung_t::menu_icon->get_image_id(0) : skinverwaltung_t::bauigelsymbol->get_image_id(0);

	img.set_image(empty_selection, true);
	img.set_size(env_t::iconsize);
}

/*********************** end of helper class **********************/

void way_builder_frame_t::read_selection()
{
	// maybe save old ones
	if (active_player_nr < 0) {
		return;
	}
	way_selection_t& cur = selected_way[active_player_nr][selected_tab[active_player_nr]];
	cur.wt = tabs.get_tab_waytype(selected_tab[active_player_nr]);
	cur.way = ways_c.get_selection() >= 0 ? way_descs[ways_c.get_selection()] : NULL;
	cur.bridge = bridges_c.get_selection() > 0 ? bridge_descs[bridges_c.get_selection()-1] : NULL;
	cur.tunnel = tunnels_c.get_selection() > 0 ? tunnel_descs[tunnels_c.get_selection()-1] : NULL;

	cur.terraform = bt_terraform.pressed;
	cur.straight = bt_straight_way.pressed;
	cur.keep = bt_replace_way.pressed;
	ways_c.set_image(empty_selection);
	bridges_c.set_image(empty_selection);
	tunnels_c.set_image(empty_selection);

	if (!welt->get_scenario()->is_tool_allowed(welt->get_active_player(), TOOL_BUILD_WAY | GENERAL_TOOL, cur.wt, 0)) {
		ways_c.set_image(empty_selection);
		cur.way = NULL;
		costs.set_text("Forbidden by scenario");
		costs.set_color(SYSCOL_TEXT_STRONG);
	}
	else {
		if (cur.way) {
			ways_c.set_image(cur.way->get_builder()->get_icon(welt->get_player(active_player_nr)));
		}
		if (cur.bridge) {
			bridges_c.set_image(cur.bridge->get_builder()->get_icon(welt->get_player(active_player_nr)));
		}
		if (cur.tunnel) {
			tunnels_c.set_image(cur.tunnel->get_builder()->get_icon(welt->get_player(active_player_nr)));
		}
		if (cur.way) {
			pending_tool_update = true;
			costs.set_text(NULL);
			costs.set_color(SYSCOL_TEXT);
		}
		else {
			costs.set_text("Please select a way to build!");
			costs.set_color(SYSCOL_TEXT_STRONG);
		}
	}
	resize(scr_coord(0, 0));
}


void way_builder_frame_t::init_tab()
{
	// activate new
	active_player_nr = world()->get_active_player_nr();
	selected_tab[active_player_nr] = tabs.get_active_tab_index();

	for (char* str : way_strings) {
		free(str);
	}
	way_strings.clear();
	way_descs.clear();
	ways_c.clear_elements();
	for (char * str : bridge_strings) {
		free(str);
	}
	bridge_strings.clear();
	bridge_descs.clear();
	bridges_c.clear_elements();
	for (char* str : tunnel_strings) {
		free(str);
	}
	tunnel_strings.clear();
	tunnel_descs.clear();
	tunnels_c.clear_elements();

	// add new ones
	way_selection_t& sel = selected_way[active_player_nr][selected_tab[active_player_nr]];
	if (sel.wt == 0) {
		// TOTO: init with default way
	}
	sel.wt = tabs.get_active_tab_waytype();
	ways_c.set_selection(-1);

	bridges_c.new_component<gui_scrolled_list_t::const_text_scrollitem_t>("Don't build bridges", SYSCOL_TEXT);
	bridges_c.set_selection(0);
	bridges_c.set_image(empty_selection);

	tunnels_c.new_component<gui_scrolled_list_t::const_text_scrollitem_t>("Don't build tunnels", SYSCOL_TEXT);
	tunnels_c.set_selection(0);
	tunnels_c.set_image(empty_selection);

	// ways
	ways_c.set_force_selection(true);
	const vector_tpl<const way_desc_t*>& wl = way_builder_t::get_way_list(sel.wt, type_flat);
	for (const way_desc_t* w : wl) {
		if (active_player_nr == PLAYER_PUBLIC_NR || w->get_builder()->get_icon(welt->get_active_player()) != IMG_EMPTY) {
			// allowed way!
			way_descs.append(w);
			way_strings.append(strdup(generate_description(w->get_name(), w->get_topspeed(), w->get_price(), w->get_maintenance(), false, 0)));
			ways_c.new_component<gui_scrolled_list_t::const_text_scrollitem_t>(way_strings.back(), SYSCOL_TEXT);
			if (w == sel.way) {
				ways_c.set_selection(ways_c.count_elements() - 1);
			}
		}
	}
	if (sel.wt != tram_wt) {
		const vector_tpl<const way_desc_t*>& wl = way_builder_t::get_way_list(sel.wt, type_elevated);
		for (const way_desc_t* w : wl) {
			if (active_player_nr == PLAYER_PUBLIC_NR || w->get_builder()->get_icon(welt->get_active_player()) != IMG_EMPTY) {
				way_descs.append(w);
				way_strings.append(strdup(generate_description(w->get_name(), w->get_topspeed(), w->get_price(), w->get_maintenance(), true, 0)));
				ways_c.new_component<gui_scrolled_list_t::const_text_scrollitem_t>(way_strings.back(), SYSCOL_TEXT);
				if (w == sel.way) {
					ways_c.set_selection(ways_c.count_elements() - 1);
				}
			}
		}
	}
	if (sel.way) {
		ways_c.set_image(sel.way->get_builder()->get_icon(welt->get_active_player()));
	}
	else {
		ways_c.set_image(empty_selection);
	}

	for (auto br : bridge_builder_t::get_available_bridges(sel.wt)) {
		bridge_descs.append(br);
		bridge_strings.append(strdup(generate_description(br->get_name(), br->get_topspeed(), br->get_price(), br->get_maintenance(), false, br->get_max_length())));
		bridges_c.new_component<gui_scrolled_list_t::const_text_scrollitem_t>(bridge_strings.back(), SYSCOL_TEXT);
		if (br == sel.bridge) {
			bridges_c.set_selection(bridges_c.count_elements() - 1);
		}
	}
	if (sel.bridge) {
		bridges_c.set_image(sel.bridge->get_builder()->get_icon(welt->get_active_player()));
	}

	for (auto tu : tunnel_builder_t::get_available_tunnels(sel.wt)) {
		tunnel_descs.append(tu);
		tunnel_strings.append(strdup(generate_description(tu->get_name(), tu->get_topspeed(), tu->get_price(), tu->get_maintenance(), false, 0)));
		tunnels_c.new_component<gui_scrolled_list_t::const_text_scrollitem_t>(tunnel_strings.back(), SYSCOL_TEXT);
		if (tu == sel.tunnel) {
			tunnels_c.set_selection(tunnels_c.count_elements() - 1);
		}
	}
	if (sel.tunnel) {
		tunnels_c.set_image(sel.tunnel->get_builder()->get_icon(welt->get_active_player()));
	}

	bt_terraform.pressed = sel.terraform;
	bt_straight_way.pressed = sel.straight;
	bt_replace_way.pressed = sel.keep;
}



void way_builder_frame_t::call_building_tool(bool init)
{
	way_selection_t& current = selected_way[active_player_nr][selected_tab[active_player_nr]];
	static tool_build_way_t *tool = 0;
	static cbuffer_t toolstr;
	pending_tool_update = false;
	if (init) {
		// forse init tool
		toolstr.clear();
	}
	if (!tool) {
		tool = new tool_build_way_t();
	}
	if (current.way) {
		tool->set_icon(current.way->get_cursor()->get_image_id(1));
		tool->cursor = current.way->get_cursor()->get_image_id(0);

		cbuffer_t old_str(toolstr);
		toolstr.clear();
		toolstr.printf("%s,%s%s%s,0,%s,%s", current.way->get_name(), current.keep ? "k" : "", current.straight ? "s" : "", current.terraform ? "t" : "", current.bridge ? current.bridge->get_name() : "", current.tunnel ? current.tunnel->get_name() : "");
		if (welt->get_tool(active_player_nr) != tool || strcmp(old_str, toolstr)) {
			// set tool to current tool
			tool->set_default_param(toolstr);
			welt->set_tool(tool, welt->get_player(active_player_nr));
		}
	}
	else {
		// reset to query tool
		welt->set_tool(tool_t::general_tool[TOOL_QUERY], welt->get_player(active_player_nr));
	}
}



way_builder_frame_t::way_builder_frame_t(waytype_t initial_wt) :
	gui_frame_t(translator::translate("Way builder"), world()->get_active_player()),
	cont(4, 0),
	tabs(false)
{
	bool first_call = active_player_nr == 255;
	if (skinverwaltung_t::menu_icon) {
		gfx->fit_img_to_width(skinverwaltung_t::menu_icon->get_image_id(0), env_t::iconsize.w);
	}
	set_table_layout(1, 0);

	// tab panel
	tabs.init_tabs(&cont);
	tabs.add_listener(this);
	add_component(&tabs);

	for (int i = 0; i < tabs.get_count(); i++) {
		if (tabs.get_tab_waytype(i) == initial_wt) {
			tabs.set_active_tab_index(i);
			break;
		}
	}
	init_tab();
	pending_tool_update = true;

	// comboboxes for building types
	cont.add_component(&ways_c);
	ways_c.add_listener(this);
	cont.add_component(&bridges_c);
	bridges_c.add_listener(this);
	cont.add_component(&tunnels_c);
	tunnels_c.add_listener(this);
	cont.new_component<gui_fill_t>();

	bt_terraform.init(button_t::square_automatic, "automatic terraforming");
	cont.add_component(&bt_terraform, 4);
	bt_terraform.add_listener(this);

	bt_straight_way.init(button_t::square_automatic, "straight route");
	cont.add_component(&bt_straight_way, 4);
	bt_straight_way.add_listener(this);

	bt_replace_way.init(button_t::square_automatic, "replace existing ways");
	cont.add_component(&bt_replace_way, 4);
	bt_replace_way.add_listener(this);

	cont.add_component(&costs, 3);

	reset_min_windowsize();

	if (first_call) {
		resize(get_min_windowsize() - get_windowsize());
		set_resizemode(no_resize);
	}
}


bool way_builder_frame_t::infowin_event(const event_t* ev)
{
	if (ev->ev_class == INFOWIN && ev->ev_code == WIN_CLOSE) {
		// reset to query tool
		welt->set_tool(tool_t::general_tool[TOOL_QUERY], welt->get_player(active_player_nr));
	}
	else if (ev->ev_class == INFOWIN && ev->ev_code == WIN_TOP) {
		call_building_tool();
	}
	else if (selected_way[active_player_nr][selected_tab[active_player_nr]].way  &&  pending_tool_update) {
		// check each draw if we are still active ...
		call_building_tool();
		set_resizemode(horizontal_resize);
	}
	return gui_frame_t::infowin_event(ev);
}


bool way_builder_frame_t::action_triggered(gui_action_creator_t* comp, value_t v)
{
	if (comp == &tabs) {
		read_selection();
		init_tab();
	}
	else {
		read_selection();
	}
	call_building_tool();
	return true;
}


void way_builder_frame_t::draw(scr_coord pos, scr_size size)
{
	if (welt->get_active_player_nr() != active_player_nr) {
		read_selection();
		init_tab();
		read_selection();
		this->set_owner(welt->get_active_player());
	}
	if (!pending_tool_update  &&  win_get_top() == this  &&  welt->get_tool(active_player_nr) == tool_t::general_tool[TOOL_QUERY]) {
		pending_tool_update = true;
	}
	gui_frame_t::draw(pos, size);
}


void way_builder_frame_t::rdwr(loadsave_t* file)
{
	scr_size size;
	if (file->is_saving()) {
		size = get_windowsize();
	}
	size.rdwr(file);
	tabs.rdwr(file);
	file->rdwr_byte(active_player_nr);

	for (int i = 0; i < MAX_PLAYER_COUNT; i++) {
		file->rdwr_byte(selected_tab[i]);
		for (int j = 0; j < tabs.get_count(); j++) {
			if (file->is_saving()) {
				const char* ws = selected_way[i][j].way ? selected_way[i][j].way->get_name() : "";
				file->rdwr_str(ws);
				const char* bs = selected_way[i][j].bridge ? selected_way[i][j].bridge->get_name() : "";
				file->rdwr_str(bs);
				const char* ts = selected_way[i][j].tunnel ? selected_way[i][j].tunnel->get_name() : "";
				file->rdwr_str(ts);
			}
			else {
				plainstring ws;
				file->rdwr_str(ws);
				selected_way[i][j].way = way_builder_t::get_desc(ws);
				file->rdwr_str(ws);
				selected_way[i][j].bridge = bridge_builder_t::get_desc(ws);
				file->rdwr_str(ws);
				selected_way[i][j].tunnel = tunnel_builder_t::get_desc(ws);
			}
			file->rdwr_bool(selected_way[i][j].straight);
			file->rdwr_bool(selected_way[i][j].keep);
		}
	}


	// open dialogue
	if (file->is_loading()) {
		active_player_nr = -1;
		active_tab = -1;
		init_tab();
		set_windowsize(size);
	}
}


