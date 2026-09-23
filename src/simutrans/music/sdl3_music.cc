/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

/// Music for the SDL3 backend through SDL3_mixer: any format its decoders know.

/*
 * The SDL3 backend opens one audio stream, in sdl3_sound.cc. Music does not
 * open another: SDL3_mixer runs here as a mixer without a device
 * (MIX_CreateMixer) in the stream's own format, and the stream's callback asks
 * it for each chunk through sdl3_audio_set_music(), adding it to the effects.
 *
 * The names are MIDI's for historical reasons only. A song that cannot be
 * played is reported once and skipped from then on, so one bad entry in
 * music.tab does not silence the list; if no song can be played the playlist
 * stays idle instead of trying again every poll.
 */

#include <SDL3/SDL.h>
#include <SDL3_mixer/SDL_mixer.h>

#include <string>

#include "music.h"
#include "../sound/sdl3_audio.h"
#include "../dataobj/environment.h"
#include "../simdebug.h"
#include "../utils/plainstring.h"


// SDL3_mixer 3.2 reads these two load properties, but they are not in its
// public header: the path MIX_LoadAudio() itself passes, and where the
// FluidSynth decoder takes its SoundFont from.
#define LOAD_PATH_STRING       "SDL_mixer.audio.load.path"
#define FLUIDSYNTH_SOUNDFONT   "SDL_mixer.decoder.fluidsynth.soundfont_path"


static int         midi_number = -1;
static plainstring midi_filenames[MAX_MIDI];

// songs that could not be loaded or started are skipped from then on
static bool midi_failed[MAX_MIDI];
static int  midi_failed_count = 0;

static MIX_Mixer *mixer = NULL;
static MIX_Track *track = NULL;
static float      music_gain = 1.0f;


/// Audio thread, stream locked: adds the music to one chunk of effects.
static void mix_music(Uint8 *buffer, int len)
{
	Uint8 music[4096];

	while(  len > 0  ) {
		const int n = SDL_min(len, (int)sizeof(music));
		// fills all n bytes, silence after the end of a song; the return value
		// counts only real music, so silence is not mixed at all
		const int got = MIX_Generate(mixer, music, n);
		if(  got > 0  ) {
			// SDL_MixAudio saturates instead of wrapping around
			SDL_MixAudio(buffer, music, sdl3_audio_format()->format, (Uint32)got, 1.0f);
		}
		buffer += n;
		len    -= n;
	}
}


/// The SoundFont a MIDI song needs, found where fluidsynth.cc looks first.
static std::string find_soundfont()
{
	const std::string &name = env_t::soundfont_filename;
	if(  name.empty()  ||  name == "Error"  ) {
		return "";
	}
	if(  SDL_GetPathInfo(name.c_str(), NULL)  ) {
		return name;
	}
	const std::string in_music = std::string(env_t::base_dir) + "music/" + name;
	if(  SDL_GetPathInfo(in_music.c_str(), NULL)  ) {
		return in_music;
	}
	return "";
}


static void song_failed(int key, const char *why)
{
	dbg->warning("dr_play_midi(SDL3)", "Unable to play music %d (%s): %s", key, midi_filenames[key].c_str(), why);
	midi_failed[key] = true;
	if(  ++midi_failed_count > midi_number  ) {
		dbg->warning("dr_play_midi(SDL3)", "No music file could be played, music stays silent");
	}
}


void dr_set_midi_volume(int vol)
{
	// Simutrans volume 0..255 to SDL3_mixer's linear gain, 255 being unity
	music_gain = vol / 255.0f;
	if(  track  ) {
		MIX_SetTrackGain(track, music_gain);
	}
}


int dr_load_midi(const char *filename)
{
	if(  midi_number < MAX_MIDI - 1  ) {
		const int i = midi_number + 1;
		// only remembered here: whether SDL3_mixer can play it is found out
		// when it is played, as with the Windows MIDI routine
		midi_filenames[i] = filename;
		midi_failed[i] = false;
		midi_number = i;
	}
	return midi_number;
}


void dr_play_midi(int key)
{
	if(  !track  ||  key < 0  ||  key > midi_number  ||  midi_failed[key]  ) {
		return;
	}
	MIX_StopTrack(track, 0);

	SDL_IOStream *io = SDL_IOFromFile(midi_filenames[key], "rb");
	if(  !io  ) {
		song_failed(key, SDL_GetError());
		return;
	}

	// what MIX_LoadAudio() sets, plus the SoundFont for a MIDI song
	const SDL_PropertiesID props = SDL_CreateProperties();
	SDL_SetPointerProperty(props, MIX_PROP_AUDIO_LOAD_PREFERRED_MIXER_POINTER, mixer);
	SDL_SetStringProperty(props, LOAD_PATH_STRING, midi_filenames[key]);
	SDL_SetPointerProperty(props, MIX_PROP_AUDIO_LOAD_IOSTREAM_POINTER, io);
	SDL_SetBooleanProperty(props, MIX_PROP_AUDIO_LOAD_PREDECODE_BOOLEAN, false);
	SDL_SetBooleanProperty(props, MIX_PROP_AUDIO_LOAD_CLOSEIO_BOOLEAN, true);
	const std::string soundfont = find_soundfont();
	if(  !soundfont.empty()  ) {
		SDL_SetStringProperty(props, FLUIDSYNTH_SOUNDFONT, soundfont.c_str());
	}
	MIX_Audio *audio = MIX_LoadAudioWithProperties(props);
	SDL_DestroyProperties(props);

	if(  !audio  ) {
		song_failed(key, SDL_GetError());
		return;
	}

	// the track keeps its own reference to the audio, and drops it when it is
	// given the next one: nothing else has to be released per song
	const bool ok = MIX_SetTrackAudio(track, audio)  &&  MIX_PlayTrack(track, 0);
	MIX_DestroyAudio(audio);
	if(  !ok  ) {
		song_failed(key, SDL_GetError());
		MIX_SetTrackAudio(track, NULL);
	}
}


void dr_stop_midi()
{
	if(  track  ) {
		MIX_StopTrack(track, 0);
		MIX_SetTrackAudio(track, NULL);
	}
}


sint32 dr_midi_pos()
{
	if(  track  &&  MIX_TrackPlaying(track)  ) {
		return 0;
	}
	// nothing is playing: move on to the next song, unless none can be played
	return midi_failed_count > midi_number ? 0 : -1;
}


/// Releases SDL3_mixer. dr_os_close() runs this before SDL_Quit(), because the
/// mixer and track own audio streams that are only safe to destroy while SDL
/// runs; close_midi() comes later and finds nothing left to do.
static void close_mixer()
{
	// once this returns the audio thread will not touch the mixer again
	sdl3_audio_set_music(NULL);

	if(  track  ) {
		MIX_DestroyTrack(track);
		track = NULL;
	}
	if(  mixer  ) {
		MIX_DestroyMixer(mixer);
		mixer = NULL;
		MIX_Quit();
	}
}


void dr_destroy_midi()
{
	sdl3_audio_set_close(NULL);
	close_mixer();
	midi_number = -1;
	midi_failed_count = 0;
}


bool dr_init_midi()
{
	if(  mixer  ) {
		return true;
	}
	// the stream effects use; opened here as well if effects are off (-nosound)
	if(  !sdl3_audio_open()  ) {
		return false;
	}
	if(  !MIX_Init()  ) {
		dbg->warning("dr_init_midi(SDL3)", "SDL3_mixer could not be initialised: %s", SDL_GetError());
		return false;
	}
	// no device of its own: the same format as the stream, mixed on request
	mixer = MIX_CreateMixer(sdl3_audio_format());
	if(  mixer  ) {
		track = MIX_CreateTrack(mixer);
	}
	if(  !track  ) {
		dbg->warning("dr_init_midi(SDL3)", "SDL3_mixer mixer could not be created: %s", SDL_GetError());
		if(  mixer  ) {
			MIX_DestroyMixer(mixer);
			mixer = NULL;
		}
		MIX_Quit();
		return false;
	}
	MIX_SetTrackGain(track, music_gain);

	std::string decoders;
	for(  int i = 0;  i < MIX_GetNumAudioDecoders();  i++  ) {
		decoders += (i ? " " : "");
		decoders += MIX_GetAudioDecoder(i);
	}
	dbg->message("dr_init_midi(SDL3)", "SDL3_mixer %d.%d.%d, decoders: %s", SDL_VERSIONNUM_MAJOR(MIX_Version()), SDL_VERSIONNUM_MINOR(MIX_Version()), SDL_VERSIONNUM_MICRO(MIX_Version()), decoders.c_str());

	sdl3_audio_set_music(mix_music);
	sdl3_audio_set_close(close_mixer);
	return true;
}
