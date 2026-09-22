/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#ifndef GUI_WAY_BUILDER_H
#define GUI_WAY_BUILDER_H


#include "gui_frame.h"
#include "components/gui_aligned_container.h"
#include "components/gui_image.h"
#include "components/gui_combobox.h"
#include "components/gui_label.h"
#include "components/gui_textinput.h"
#include "components/gui_waytype_tab_panel.h"


class gui_image_combobox_t : public gui_combobox_t
{
private:
	gui_image_t img;

public:
	gui_image_combobox_t(gui_scrolled_list_t::item_compare_func cmp = 0);

	//	bool infowin_event(event_t const*) OVERRIDE;

	//	bool action_triggered(gui_action_creator_t*, value_t) OVERRIDE;

	void draw(scr_coord offset) OVERRIDE;

	void set_image(const image_id i) {
		img.set_image(i, true);
	}

	void set_size(scr_size size) OVERRIDE;

	scr_size get_min_size() const OVERRIDE;

	// only has one size ...
	scr_size get_size() const OVERRIDE { return get_min_size(); }
	scr_size get_max_size() const OVERRIDE { return get_min_size(); }

	// save selection
//	void rdwr(loadsave_t* file) OVERWRITE;
};


/**
 * Window displaying information about all schedules and lines.
 */
class way_builder_frame_t : public gui_frame_t, public action_listener_t
{
public:
	gui_label_t costs;

private:
	gui_aligned_container_t cont;
	gui_waytype_tab_panel_t tabs;
	gui_image_combobox_t ways_c, bridges_c, tunnels_c;
	button_t bt_terraform, bt_straight_way, bt_replace_way;


	// reads current selection
	void read_selection();

	// (re-)initialize the current tab using the static saved structure
	void init_tab();

	void call_building_tool(bool init = false);

public:
	way_builder_frame_t(waytype_t wt);

	void draw(scr_coord pos, scr_size size) OVERRIDE;

	const char* get_help_filename() const OVERRIDE { return "way_builder.txt"; }

	bool action_triggered(gui_action_creator_t*, value_t) OVERRIDE;

	bool infowin_event(const event_t *) OVERRIDE;

	// following: rdwr stuff
	void rdwr(loadsave_t* file) OVERRIDE;
	uint32 get_rdwr_id() OVERRIDE { return magic_way_builder; }
};

#endif
