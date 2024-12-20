/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#include <string.h>

#include "script_tool_frame.h"

#include "../script/script_tool_manager.h"
#include "../dataobj/environment.h"
#include "../dataobj/tabfile.h"
#include "../dataobj/translator.h"
#include "../simdebug.h"
#include "../world/simworld.h"
#include "../tool/simtool-scripted.h"
#include "../sys/simsys.h"
#include "../utils/cbuffer.h"
#include "../utils/simstring.h"

script_tool_frame_t::~script_tool_frame_t()
{
	clear_ptr_vector(infos);
}


script_tool_frame_t::script_tool_frame_t() : savegame_frame_t(NULL, true, NULL, false)
{
	static cbuffer_t pakset_script_tool;
	static cbuffer_t addons_script_tool;
	static cbuffer_t user_addons_script_tool;

	pakset_script_tool.clear();
	pakset_script_tool.printf("%stool%s", env_t::pak_dir.c_str(), PATH_SEPARATOR);

	addons_script_tool.clear();
	addons_script_tool.printf("%saddons%s%stool%s", env_t::install_dir, PATH_SEPARATOR, env_t::pak_name.c_str(), PATH_SEPARATOR);

	user_addons_script_tool.clear();
	user_addons_script_tool.printf("%saddons%s%stool%s", env_t::user_dir, PATH_SEPARATOR, env_t::pak_name.c_str(), PATH_SEPARATOR);

	if (env_t::default_settings.get_with_private_paks()) {
		this->add_path(addons_script_tool);
	}
	this->add_path(user_addons_script_tool);	// always add user addons
	this->add_path(pakset_script_tool);

	set_name(translator::translate("Load script tool"));
	set_focus(NULL);
}


/**
 * Action, started after button pressing.
 */
bool script_tool_frame_t::item_action(const char *fullpath)
{
	const scripted_tool_info_t* info = script_tool_manager_t::get_script_info(fullpath);
	bool is_one_click = info->is_one_click;
	delete info;

	tool_t* tool = script_tool_manager_t::load_tool(fullpath, tool_t::general_tool[is_one_click ? TOOL_EXEC_SCRIPT : TOOL_EXEC_TWO_CLICK_SCRIPT]);
	assert(tool);
	const char* p = strrchr(fullpath, *PATH_SEPARATOR);
	static plainstring last_default_param;
	last_default_param = p ? p + 1 : fullpath;
	tool->set_default_param(last_default_param);
	welt->set_tool(tool, welt->get_active_player());
	return true;
}


// calls tool manager to read description.tab
const char *script_tool_frame_t::get_info(const char *path)
{
	const scripted_tool_info_t* info = script_tool_manager_t::get_script_info(path);
	infos.append(info);

	return info->title.c_str();
}


bool script_tool_frame_t::check_file( const char *filename, const char * )
{
	return script_tool_manager_t::check_file(filename);
}
