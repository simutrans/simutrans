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

/**
 * Window displaying information about all schedules and lines.
 */
class way_builder_frame_t : public gui_frame_t, public action_listener_t
{
private:
	gui_aligned_container_t cont;
	gui_waytype_tab_panel_t tabs;
	gui_image_t	   way_i, bridge_i, tunnel_i;
	gui_combobox_t ways_c, bridges_c, tunnels_c;
	button_t bt_straight_way, bt_replace_way;

	gui_label_t costs;

	// reads current selection
	void read_selection();

	// (re-)initialize the current tab using the static saved structure
	void init_tab();

	void call_building_tool(bool init = false);

public:
	way_builder_frame_t(waytype_t wt);

//	~way_builder_frame_t();

	void draw(scr_coord pos, scr_size size) OVERRIDE;

	const char* get_help_filename() const OVERRIDE { return "way_builder.txt"; }

	bool action_triggered(gui_action_creator_t*, value_t) OVERRIDE;

	bool infowin_event(const event_t *) OVERRIDE;

	// following: rdwr stuff
	void rdwr(loadsave_t* file) OVERRIDE;
	uint32 get_rdwr_id() OVERRIDE { return magic_way_builder; }
};

#endif
