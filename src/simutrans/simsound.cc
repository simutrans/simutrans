/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include <sys/stat.h>
#include <algorithm>
#include <vector>
#include "macros.h"
#include "music/music.h"
#include "descriptor/sound_desc.h"
#include "sound/sound.h"
#include "simsound.h"
#include "sys/simsys.h"
#include "simio.h"
#include "simdebug.h"

#include "dataobj/environment.h"
#include "utils/plainstring.h"
#include "utils/searchfolder.h"
#include "utils/simrandom.h"
#include "utils/simstring.h"


static bool new_midi = false;

static struct midi_info_t midi_list[MAX_MIDI];

static int max_midi = -1; // number of MIDI files

static int current_midi = -1;  // init with error condition, reset during loading

static bool midi_ready = false; // the music routine is running and was given a list
static bool from_music_folder = false; // the list came from env_t::music_folder


void sound_set_global_volume(int volume)
{
	env_t::global_volume = volume;
}


void sound_set_specific_volume( int volume, sound_type_t t)
{
	env_t::specific_volume[t] = volume;
}


int sound_get_global_volume()
{
	return env_t::global_volume;
}


int sound_get_specific_volume( sound_type_t t )
{
	return env_t::specific_volume[t];
}


void sound_set_mute(bool f)
{
	env_t::global_mute_sound = f;
}


bool sound_get_mute()
{
	return (  env_t::global_mute_sound  );
}


void sound_play(uint16 const idx, uint8 const v, sound_type_t t)
{
	uint32 volume = v;
	if(  idx != (uint16)NO_SOUND  &&  !env_t::global_mute_sound  ) {
		dr_play_sample(idx, ( (volume  * env_t::global_volume * env_t::specific_volume[t] ) >> 16) );
	}
}


bool sound_get_shuffle_midi()
{
	return env_t::shuffle_midi;
}


void sound_set_shuffle_midi( bool shuffle )
{
	env_t::shuffle_midi = shuffle;
}


void sound_set_midi_volume(int volume)
{
	if(  !env_t::mute_midi  &&  max_midi > -1  ) {
		dr_set_midi_volume(volume);
	}
	env_t::midi_volume = volume;
}



int sound_get_midi_volume()
{
	return env_t::midi_volume;
}



/**
 * gets midi title
 */
struct midi_info_t sound_get_midi_info(int index)
{
	if (  index >= 0  &&  index <= max_midi  ) {
		return midi_list[index];
	}
	return { "Invalid MIDI Index!", "-", "-" };
}


/**
 * gets current midi number
 */
int get_current_midi()
{
	return current_midi;
}


static bool is_file(const std::string &path)
{
	struct stat st;
	return dr_stat(path.c_str(), &st) == 0  &&  (st.st_mode & S_IFREG);
}


static std::string with_separator(const std::string &folder)
{
	if(  !folder.empty()  &&  folder.back() != '/'  &&  folder.back() != '\\'  ) {
		return folder + "/";
	}
	return folder;
}


/// env_t::music_folder with a separator at the end; a relative one is taken from the user directory,
/// since the current directory changes while the game runs
static std::string music_folder_path()
{
	const std::string &folder = env_t::music_folder;
	const bool absolute = folder[0] == '/'  ||  folder[0] == '\\'  ||  (folder.length() > 1  &&  folder[1] == ':');
	return with_separator( absolute ? folder : env_t::user_dir + folder );
}


/**
 * Reads a music.tab: four lines per song, the path relative to @p directory,
 * title, composer and arranger.
 * With @p next_to_tab a song missing there is looked for by its file name in
 * @p directory too, so a music.tab copied along with its songs into a folder of
 * their own still works.
 * @return false if music.tab could not be opened
 */
static bool read_music_tab(const std::string &tab, const std::string &directory, bool next_to_tab)
{
	if(  FILE* const file = dr_fopen(tab.c_str(), "rb")  ) {
		while(!feof(file)) {
			char buf[256], title[256], composer[256], arranger[256];
			size_t len;

			read_line(buf,   sizeof(buf),   file);
			read_line(title, sizeof(title), file);
			read_line(composer, sizeof(composer), file);
			read_line(arranger, sizeof(arranger), file);
			if(  !feof(file)  ) {
				clear_invalid_ending_chars(buf);
				len = strlen(buf);
				if(  len > 1  ) {
					std::string full_path = directory + buf;
					if(  next_to_tab  &&  !is_file(full_path)  ) {
						// a music.tab copied from elsewhere: take the song next to it
						full_path = directory + str_get_filename(buf, true);
					}
					dbg->message("midi_init()", "  Reading MIDI file '%s' - %s", full_path.c_str(), title);
					max_midi = dr_load_midi(full_path.c_str());

					if(  max_midi >= 0  ) {
						midi_list[max_midi].title = (std::string) clear_invalid_ending_chars(title);
						midi_list[max_midi].composer = (std::string) clear_invalid_ending_chars(composer);
						midi_list[max_midi].arranger = (std::string) clear_invalid_ending_chars(arranger);
					}
				}
			}
		}

		fclose(file);
		return true;
	}
	return false;
}


/// whether the music routine can play this file, judged by its extension
static bool is_music_file(const char *name)
{
	const char *dot = strrchr(name, '.');
	if(  !dot  ) {
		return false;
	}
	std::string extension(dot);
	for(  char &c : extension  ) {
		c = (char)tolower((unsigned char)c);
	}
	extension += ' ';
	return strstr(dr_get_midi_extensions(), extension.c_str()) != NULL;
}


/**
 * Lists the songs of a folder without music.tab: every file the music routine
 * can play, in alphabetical order, without looking into subfolders.
 */
static void read_music_folder(const std::string &folder)
{
	searchfolder_t search;
	search.search(folder, "", searchfolder_t::SF_NONE);

	std::vector<std::string> names;
	for(  const char *name : search  ) {
		// a folder named like a song is not one
		if(  is_music_file(name)  &&  is_file(folder + name)  ) {
			names.push_back(name);
		}
	}
	std::sort(names.begin(), names.end(), [](const std::string &a, const std::string &b) {
		const int order = STRICMP(a.c_str(), b.c_str());
		return order != 0 ? order < 0 : a < b;
	});

	for(  const std::string &name : names  ) {
		if(  max_midi >= MAX_MIDI - 1  ) {
			dbg->warning("read_music_folder()", "Only the first %d songs of '%s' are played", MAX_MIDI, folder.c_str());
			break;
		}
		const std::string full_path = folder + name;
		dbg->message("read_music_folder()", "  Reading music file '%s'", full_path.c_str());
		max_midi = dr_load_midi(full_path.c_str());

		if(  max_midi >= 0  ) {
			midi_list[max_midi].title = str_get_filename(name.c_str(), false);
			midi_list[max_midi].composer = "-";
			midi_list[max_midi].arranger = "-";
		}
	}
}


/**
 * Load MIDI files
 */
int midi_init(const char *directory)
{
	// read a list of soundfiles
	const std::string full_path = std::string(directory) + "music" + PATH_SEPARATOR + "music.tab";

	if(  !read_music_tab(full_path, directory, false)  ) {
		dbg->warning("midi_init()","can't open file '%s' for reading.", full_path.c_str() );
	}

	if(  max_midi >= 0  ) {
		current_midi = 0;
	}
	// success?
	return (  max_midi >= 0  );
}


bool midi_load_list()
{
	midi_ready = true;
	from_music_folder = false;

	if(  !env_t::music_folder.empty()  ) {
		const std::string folder = music_folder_path();
		if(  !read_music_tab(folder + "music.tab", folder, true)  ) {
			read_music_folder(folder);
		}
		if(  max_midi >= 0  ) {
			current_midi = 0;
			from_music_folder = true;
			return true;
		}
		dbg->warning("midi_load_list()", "No music found in '%s', playing the default music instead", folder.c_str());
	}

	return  midi_init( env_t::pak_dir.c_str() )  ||  midi_init( env_t::user_dir )  ||  midi_init( env_t::base_dir );
}


bool midi_reload()
{
	if(  !midi_ready  ) {
		// no music routine: the choice is used from the next start on
		return false;
	}
	dr_clear_midi();
	max_midi = -1;
	current_midi = -1;
	new_midi = false;

	midi_load_list();
	if(  !midi_get_mute()  ) {
		midi_play( env_t::shuffle_midi ? -1 : 0 );
		dr_set_midi_volume( env_t::midi_volume );
	}
	return true;
}


bool midi_from_music_folder()
{
	return from_music_folder;
}


bool midi_folder_has_music(const char *folder)
{
	const std::string path = with_separator(folder);
	if(  is_file(path + "music.tab")  ) {
		return true;
	}
	searchfolder_t search;
	search.search(path, "", searchfolder_t::SF_NONE);
	for(  const char *name : search  ) {
		if(  is_music_file(name)  &&  is_file(path + name)  ) {
			return true;
		}
	}
	return false;
}


void midi_play(const int no)
{
	if(  no > max_midi  ) {
		dbg->warning("midi_play()", "MIDI index %d too high (total loaded: %d)", no, max_midi);
	}
	else if(  !midi_get_mute()  ) {
		current_midi = (no < 0) ? sim_async_rand( max_midi ) : no;
		dr_play_midi( current_midi );
	}
}


void midi_stop()
{
	if(  !midi_get_mute()  ) {
		dr_stop_midi();
	}
}



void midi_set_mute(bool on)
{
	on |= (  max_midi == -1  );
	if(  on  ) {
		if(  !env_t::mute_midi  ) {
			dr_stop_midi();
		}
		env_t::mute_midi = true;
	}
	else {
		if(  env_t::mute_midi  ) {
			env_t::mute_midi = false;
			midi_play(current_midi);
		}
		dr_set_midi_volume(env_t::midi_volume);
	}
}



bool midi_get_mute()
{
	return  (  env_t::mute_midi  ||  max_midi == -1  );
}



/*
 * Check if need to play new MIDI
 * Max Kielland:
 * Made it possible to get next song
 * even if we are muted.
 */
void check_midi()
{
	// Check for next sound
	if (new_midi || (!midi_get_mute() && dr_midi_pos() < 0)) {
		if(  env_t::shuffle_midi  &&  max_midi > 1  ) {

			// shuffle songs (must not use simrand()!)
			int new_song = sim_async_rand(max_midi);

			if(  new_song >= current_midi  ) {
				new_song ++;
			}
			current_midi = new_song;
		}
		else {
			current_midi++;
			if(  current_midi > max_midi  ) {
				current_midi = 0;
			}
		}

		// Are we in playing mode?
		if(  false == midi_get_mute()  ) {
			midi_play(current_midi);
			DBG_MESSAGE("check_midi()", "Playing MIDI %d", current_midi);
		}
	}

	new_midi = false;
}


/**
 * shuts down midi playing
 */
void close_midi()
{
	if(  max_midi > -1  ) {
		dr_destroy_midi();
	}
}


void midi_next_track()
{
	new_midi = true;
}


void midi_last_track()
{
	if (  current_midi == 0  ) {
		current_midi = max_midi - 1;
	}
	else {
		current_midi = current_midi - 2;
	}
	new_midi = true;
}
