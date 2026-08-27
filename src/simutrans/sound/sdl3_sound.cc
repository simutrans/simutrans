/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

/// sdl-sound for SDL3, without SDL_mixer

/*
 * This is the SDL3 counterpart of sdl2_sound.cc and deliberately keeps the
 * same shape: four software mixing channels, at most 64 samples, every sample
 * converted once on load to a single output format, and one callback that
 * mixes the active channels. Only the SDL calls differ.
 *
 * Where SDL3 changed the meaning of something rather than only its name, the
 * difference is spelled out at the call:
 *
 *   - the device is opened through an SDL_AudioStream, because SDL3 has no
 *     SDL_AUDIO_ALLOW_ANY_CHANGE: the stream converts our fixed format to
 *     whatever the device wants, instead of us converting to the device;
 *   - the callback is handed a stream to push into, not a buffer to fill;
 *   - SDL_MixAudio takes the mixing volume as a float, and passing SDL2's
 *     integer straight through would be a gain of up to 128;
 *   - SDL_InitSubSystem and SDL_LoadWAV report failure as false, so SDL2's
 *     "== -1" and "== NULL" tests would not be checking anything here.
 */

#include <SDL3/SDL.h>

#include "sound.h"
#include "../simdebug.h"

#include <cstring>


/// flag if sound module should be used
/// -1: error during initialization
///  0: not initialized
///  1: successfully initialized
static int use_sound = 0;

/// defines the number of channels available
#define NUM_AUDIO_CHANNELS 4

/// Used to indicate that a channel is empty
#define NO_SAMPLE (0xFF)

/// The scale the mixing volume is expressed in. SDL2 exports this as
/// SDL_MIX_MAXVOLUME; SDL3 no longer does, but still mixes at exactly this
/// scale internally, so it has to be spelled out rather than dropped.
#define MIX_MAXVOLUME 128

/// How much is mixed at a time. SDL2 asked the device for a buffer of 1024
/// frames and mixed one such buffer per callback; SDL3 asks for however much
/// the device happens to need at that moment, which is not a fixed number.
/// Keeping the chunk fixed keeps the mixing identical to SDL2 instead of
/// making it depend on the device's timing.
#define MIX_FRAMES_PER_CHUNK 1024


/// this structure contains the data for one sample
struct sample
{
	// the buffer containing the data for the sample, the format
	// must always be identical to the one of the system output
	// format
	Uint8 *audio_data;

	Uint32 audio_len; // number of samples in the audio data
};


/// this list contains all the samples
static sample samples[64];

/// all samples are stored chronologically there
static int samplenumber = 0;


/// this structure contains the information about one channel
struct channel
{
	Uint32 sample_pos; ///< the current position inside this sample
	Uint8 sample;      ///< which sample is played, or NO_SAMPLE if there is none
	Uint8 volume;      ///< the volume this channel should be played
};


/// this array contains all the information of the currently played samples
static channel channels[NUM_AUDIO_CHANNELS];


/// the format of the output audio channel in use
/// all loaded waves need to be converted to this format
///
/// SDL2 let the device override this and mixed in whatever came back. SDL3
/// removed that negotiation: this is the application side of the stream and
/// SDL converts it to the device format, so it is fixed and known.
static const SDL_AudioSpec output_audio_format = { SDL_AUDIO_S16, 1, 22050 };

static SDL_AudioStream *audio_stream = NULL;


void SDLCALL sdl_sound_callback(void *, SDL_AudioStream *stream, int additional_amount, int)
{
	// One chunk is exactly what one SDL2 callback used to be handed, so both
	// backends cut a sample at the same point.
	Uint8 buffer[MIX_FRAMES_PER_CHUNK * sizeof(Sint16)];
	const int len = (int)sizeof(buffer);

	while(  additional_amount > 0  ) {
		memset(buffer, 0, len); // nothing is guaranteed about a fresh chunk either.

		// add all the sample that need to be played
		for(  int c = 0;  c < NUM_AUDIO_CHANNELS;  c++  ) {
			if (channels[c].sample == NO_SAMPLE) {
				// only do something if the channel is used
				continue;
			}

			sample *smp = &samples[channels[c].sample];

			// add sample
			if (len + channels[c].sample_pos >= smp->audio_len ) {
				channels[c].sample = NO_SAMPLE;
			}
			else {
				// SDL_MixAudioFormat became SDL_MixAudio, and the volume
				// became a float in 0.0 .. 1.0. SDL3 turns it straight back
				// into round(volume * 128) and then applies the same integer
				// scaling SDL2 does, so dividing by MIX_MAXVOLUME here is not
				// an approximation: it reproduces SDL2 sample for sample.
				SDL_MixAudio(buffer, smp->audio_data + channels[c].sample_pos, output_audio_format.format, len, channels[c].volume / (float)MIX_MAXVOLUME);
				channels[c].sample_pos += len;
			}
		}

		// The SDL3 callback does not fill a buffer, it feeds the stream.
		if(  !SDL_PutAudioStreamData(stream, buffer, len)  ) {
			// Retrying cannot help and would spin the audio thread.
			break;
		}

		additional_amount -= len;
	}
}


bool dr_init_sound()
{
	// avoid init twice
	if (use_sound != 0) {
		return use_sound > 0;
	}

	// initialize SDL sound subsystem
	if(  !SDL_InitSubSystem(SDL_INIT_AUDIO)  ) {
		dbg->error("dr_init_sound(SDL3)", "Could not initialize sound system: %s. Muting.", SDL_GetError());
		use_sound = -1;
		return false;
	}

	// open an audio channel
	//
	// SDL_OpenAudioDevice returns a device that still has to be bound to a
	// stream by hand; SDL_OpenAudioDeviceStream does the open, the create and
	// the bind at once and ties the device's lifetime to the stream. Like
	// SDL2's device, it comes up paused.
	audio_stream = SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &output_audio_format, sdl_sound_callback, NULL);

	if(  !audio_stream  ) {
		dbg->error("dr_init_sound(SDL3)", "Could not open required audio channel: %s. Muting.", SDL_GetError());
		SDL_QuitSubSystem(SDL_INIT_AUDIO);
		use_sound = -1;
		return false;
	}

	// finished initializing
	for (int i = 0; i < NUM_AUDIO_CHANNELS; i++) {
		channels[i].sample = NO_SAMPLE;
	}

	// start playing sounds
	SDL_ResumeAudioStreamDevice(audio_stream);

	use_sound = 1;
	return true;
}


/**
 * loads a sample
 * @return a handle for that sample or -1 on failure
 */
int dr_load_sample(const char *filename)
{
	if(use_sound<=0  ||  samplenumber>=64) {
		return -1;
	}

	SDL_AudioSpec wav_spec;
	Uint8 *wav_data;
	Uint32 wav_length;
	sample smp;

	// load the sample
	// SDL3 reports failure with false, and the buffer is released with
	// SDL_free: SDL_FreeWAV is gone.
	if(  !SDL_LoadWAV(filename, &wav_spec, &wav_data, &wav_length)  ) {
		dbg->warning("dr_load_sample", "Could not load wav: %s", SDL_GetError());
		return -1;
	}

	/* convert the loaded wav to the internally used sound format */
	//
	// SDL_BuildAudioCVT + SDL_ConvertAudio wanted a caller allocated buffer
	// big enough for the worst case growth and converted it in place. SDL3
	// does the whole conversion in one call and returns a buffer of exactly
	// the right size, so len_mult and len_cvt have no equivalent here.
	Uint8 *cvt_data   = NULL;
	int    cvt_length = 0;

	if(  !SDL_ConvertAudioSamples(&wav_spec, wav_data, (int)wav_length, &output_audio_format, &cvt_data, &cvt_length)  ) {
		dbg->error("dr_load_sample", "Could not convert wav to output format: %s", SDL_GetError());
		SDL_free(wav_data);
		return -1;
	}

	SDL_free(wav_data);

	// save the data
	// The converted buffer is kept for the lifetime of the process, exactly
	// as in SDL2: samples are loaded once and never released.
	smp.audio_data = cvt_data;
	smp.audio_len = (Uint32)cvt_length;
	samples[samplenumber] = smp;

	dbg->message("dr_load_sample", "Loaded '%s' to sample %i.", filename, samplenumber);
	return samplenumber++;
}


/*
 * plays a sample
 *
 * @param sample_number the key for the sample to be played
 * @param volume
  */
void dr_play_sample(int sample_number, int volume)
{
	if (use_sound <= 0 || sample_number == -1) {
		return;
	}

	// find an empty channel, and play
	for (int c = 0; c < NUM_AUDIO_CHANNELS; c++) {
		if (channels[c].sample == NO_SAMPLE) {
			channels[c].sample = sample_number;
			channels[c].sample_pos = 0;
			// unchanged from SDL2: 0..255 in, 0..MIX_MAXVOLUME out. The
			// conversion to SDL3's float happens at the mixing call, so this
			// stays the integer both backends agree on.
			channels[c].volume = volume * MIX_MAXVOLUME >> 8;
			break;
		}
	}
}
