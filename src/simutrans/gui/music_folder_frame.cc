/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#include "music_folder_frame.h"
#include "simwin.h"
#include "messagebox.h"

#include "../simsound.h"
#include "../dataobj/environment.h"
#include "../dataobj/translator.h"
#include "../sys/simsys.h"


music_folder_frame_t::music_folder_frame_t() : savegame_frame_t(NULL, true, NULL, false)
{
	set_name( translator::translate("Select music") );
	fnlabel.set_text("Each soundtrack is a folder in the music directory.");
	top_frame.remove_component( &input );
	label_enabled = false;

	old_music_folder = env_t::music_folder;

	default_button.init( button_t::roundbox_state | button_t::flexible, "Default music" );
	default_button.add_listener( this );
	bottom_left_frame.add_component( &default_button );

	const std::string user_music = std::string(env_t::user_dir) + "music" + PATH_SEPARATOR;
	const std::string base_music = std::string(env_t::base_dir) + "music" + PATH_SEPARATOR;
	add_path( user_music.c_str() );
	if(  user_music != base_music  ) {
		add_path( base_music.c_str() );
	}
}


void music_folder_frame_t::select_folder(const char *folder)
{
	env_t::music_folder = folder;
	if(  midi_reload()  &&  !env_t::music_folder.empty()  &&  !midi_from_music_folder()  ) {
		// nothing in it could be loaded: the default music plays again
		env_t::music_folder.clear();
		create_win( new news_img("No music could be loaded from this folder."), w_time_delete, magic_none );
	}
}


bool music_folder_frame_t::item_action(const char *fullpath)
{
	select_folder( fullpath );
	// stay open to listen to another one
	return false;
}


bool music_folder_frame_t::ok_action(const char *)
{
	return true;
}


bool music_folder_frame_t::cancel_action(const char *)
{
	if(  env_t::music_folder != old_music_folder  ) {
		// exactly as before, even a folder that was not found at start (and is kept for the next one)
		env_t::music_folder = old_music_folder;
		midi_reload();
	}
	return true;
}


const char *music_folder_frame_t::get_info(const char *)
{
	return "";
}


bool music_folder_frame_t::check_file(const char *fullpath, const char *)
{
	return midi_folder_has_music( fullpath );
}


void music_folder_frame_t::fill_list()
{
	savegame_frame_t::fill_list();

	// show which one plays
	for(dir_entry_t const& i : entries) {
		if(  i.type == LI_HEADER  ) {
			continue;
		}
		i.button->set_typ( button_t::roundbox_state | button_t::flexible );
	}
	resize( scr_coord(0,0) );
}


void music_folder_frame_t::draw(scr_coord pos, scr_size size)
{
	for(dir_entry_t const& i : entries) {
		if(  i.type == LI_HEADER  ) {
			continue;
		}
		i.button->pressed = env_t::music_folder == i.info;
	}
	default_button.pressed = env_t::music_folder.empty();
	savegame_frame_t::draw( pos, size );
}


bool music_folder_frame_t::action_triggered(gui_action_creator_t *component, value_t v)
{
	if(  component == &default_button  ) {
		select_folder( "" );
		return true;
	}
	return savegame_frame_t::action_triggered( component, v );
}
