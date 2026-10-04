/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#ifndef GUI_MUSIC_FOLDER_FRAME_H
#define GUI_MUSIC_FOLDER_FRAME_H


#include "savegame_frame.h"

#include <string>


/**
 * Chooses where the music is played from: the default music.tab, or a folder
 * in a music directory. Every such folder with a music.tab or with files the
 * music routine can play is a soundtrack of its own.
 */
class music_folder_frame_t : public savegame_frame_t
{
private:
	/// restored on cancel
	std::string old_music_folder;

	button_t default_button;

	/// plays from @p folder, or the default music if it is empty
	void select_folder(const char *folder);

protected:
	bool item_action(const char *fullpath) OVERRIDE;
	bool ok_action(const char *fullpath) OVERRIDE;
	bool cancel_action(const char *fullpath) OVERRIDE;

	const char *get_info(const char *fullpath) OVERRIDE;
	bool check_file(const char *fullpath, const char *suffix) OVERRIDE;

	void fill_list() OVERRIDE;

public:
	music_folder_frame_t();

	void draw(scr_coord pos, scr_size size) OVERRIDE;

	bool action_triggered(gui_action_creator_t *component, value_t v) OVERRIDE;
};

#endif
