/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#ifndef SOUND_SDL3_AUDIO_H
#define SOUND_SDL3_AUDIO_H


#include <SDL3/SDL.h>


/*
 * Internal to the SDL3 backend. sdl3_sound.cc owns the one audio stream
 * Simutrans opens; the SDL3 music routine mixes into that same stream instead
 * of opening a second one.
 */

/// Mixes music into one chunk of the output, in the format returned by
/// sdl3_audio_format(). Called from the audio thread with the stream locked.
typedef void (*sdl3_audio_music_fn)(Uint8 *buffer, int len);

/// Opens the audio stream if it is not open yet. Safe to call more than once.
bool sdl3_audio_open();

/// The application-side format of the stream, identical for effects and music.
const SDL_AudioSpec *sdl3_audio_format();

/// Sets or removes (NULL) the music mixing routine. Returns only once the
/// audio thread can no longer be running the previous one.
void sdl3_audio_set_music(sdl3_audio_music_fn mix);

/// Closes whatever of the music depends on SDL. Registered by the music
/// routine; run by sdl3_audio_close().
typedef void (*sdl3_audio_close_fn)();
void sdl3_audio_set_close(sdl3_audio_close_fn close);

/// Called by dr_os_close() before SDL_Quit(): the music may still hold SDL
/// objects of its own, and must release them while SDL is running.
void sdl3_audio_close();

#endif
