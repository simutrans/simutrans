/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#ifndef SIMSOUND_H
#define SIMSOUND_H

#include <string>
#include "simtypes.h"
#include "utils/plainstring.h"

/// sound can be selectively muted (but volume is not touched)
void sound_set_mute(bool new_flag);
bool sound_get_mute();

/// @param volume in range 0..255
void sound_set_global_volume(int volume);

/// @returns volume in range 0..255
int sound_get_global_volume();

/// Sets volume for a specific type of sound.
/// @param volume in range 0..255
/// @param t
void sound_set_specific_volume( int volume, sound_type_t t );

/// @param t
/// @returns volume in range 0..255
int sound_get_specific_volume( sound_type_t t );

/**
 * Play a sound.
 *
 * @param idx    Index of the sound
 * @param volume in range 0..255
 * @param t
 */
void sound_play(uint16 idx, uint8 volume, sound_type_t t );


/// shuffle enable/disable for midis
bool sound_get_shuffle_midi();
void sound_set_shuffle_midi( bool shuffle );

/// @param volume in range 0..255
void sound_set_midi_volume(int volume);

/// @returns volume in range 0..255
int sound_get_midi_volume();

struct midi_info_t {
	std::string title;
	std::string composer;
	std::string arranger;
};

/// gets midi title
struct midi_info_t sound_get_midi_info(int index);


/**
 * gets curent midi number
 */
int get_current_midi();

// when muted, midi is not used
void midi_set_mute(bool on);
bool midi_get_mute();

/* MIDI routines */
extern int midi_init(const char *path);

/// Loads the songs of env_t::music_folder, or the first music.tab of pakset,
/// user and program directory if that is empty or has no music.
/// @return false if no song was found at all
extern bool midi_load_list();

/// Stops the music and loads the list again after env_t::music_folder changed.
/// @return false if there is no music routine to reload
extern bool midi_reload();

/// @return whether the current songs came from env_t::music_folder
extern bool midi_from_music_folder();

/// @return whether @p folder has a music.tab or a file the music routine can play
extern bool midi_folder_has_music(const char *folder);

extern void midi_play(const int no);
extern void check_midi();


/**
 * shuts down midi playing
 */
extern void close_midi();

extern void midi_next_track();
extern void midi_last_track();
extern void midi_stop();

#endif
