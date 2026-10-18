/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#include <stdio.h>
#include <stdlib.h>
#include <windows.h>
#include <mmsystem.h>

#include "../macros.h"
#include "../utils/plainstring.h"
#include "../utils/simstring.h"
#include "music.h"
#include "../simsound.h"
#include "../simdebug.h"

/*
 * class to play other sampled data (REQUIRES WIN8 or later)
 * because of COM callback mandatory
 * MCI crashes on WIndow11 on many MP3 so we divide the playback
 */

#include <mfapi.h>
#include <mfmediaengine.h>

#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mf.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "ole32.lib")

// A minimal notify handler required by the Media Engine
class AudioEngineNotify : public IMFMediaEngineNotify {
	long m_cRef = 1;
public:
	STDMETHODIMP QueryInterface(REFIID riid, void** ppvObject)
	{
		if (!ppvObject) {
			return E_POINTER;
		}
		if (riid == IID_IUnknown || riid == __uuidof(IMFMediaEngineNotify)) {
			*ppvObject = static_cast<IMFMediaEngineNotify*>(this);
			AddRef();
			return S_OK;
		}
		*ppvObject = nullptr;
		return E_NOINTERFACE;
	}
	STDMETHODIMP_(ULONG) AddRef() {	return InterlockedIncrement(&m_cRef); }

	STDMETHODIMP_(ULONG) Release() {
		long cRef = InterlockedDecrement(&m_cRef);
		if (cRef == 0) delete this;
		return cRef;
	}

	STDMETHODIMP EventNotify(DWORD eventCode, DWORD_PTR param1, DWORD param2) { return S_OK; }
};

// teh actual playback class
class WindowsAudioPlayer {
private:
	IMFMediaEngine* m_pEngine = nullptr;
	AudioEngineNotify* m_pNotify = nullptr;
	IMFAttributes* m_pAttributes = nullptr;

public:
	WindowsAudioPlayer()
	{
		// Initialize COM and Media Foundation
		CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
		MFStartup(MF_VERSION);

		// Set up the Media Engine
		IMFMediaEngineClassFactory* pFactory = nullptr;
		m_pNotify = new AudioEngineNotify();

		if (SUCCEEDED(MFCreateAttributes(&m_pAttributes, 1))) {
			m_pAttributes->SetUnknown(MF_MEDIA_ENGINE_CALLBACK, m_pNotify);
			if (SUCCEEDED(CoCreateInstance(CLSID_MFMediaEngineClassFactory, nullptr,
				CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&pFactory)))) {
				// Create an audio-only instance
				pFactory->CreateInstance(MF_MEDIA_ENGINE_AUDIOONLY, m_pAttributes, &m_pEngine);
				pFactory->Release();
			}
		}
	}

	~WindowsAudioPlayer()
	{
		if (m_pEngine) m_pEngine->Release();
		if (m_pAttributes) m_pAttributes->Release();
		if (m_pNotify) m_pNotify->Release();
		MFShutdown();
		CoUninitialize();
	}

	// FUNCTION 1: Play file by its path
	bool PlayFile(const char *filePath)
	{
		if (!m_pEngine) return false;

		static WCHAR wFilename[MAX_PATH];
		MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, filePath, -1, wFilename, lengthof(wFilename));
		HRESULT hr = m_pEngine->SetSource(wFilename);
		if (SUCCEEDED(hr)) {
			hr = m_pEngine->Play();
			return SUCCEEDED(hr);
		}
		return false;
	}

	sint32 GetPosition()
	{
		if (!m_pEngine) {
			return 0;
		}
		if (m_pEngine->IsEnded()) {
			return -1; // not playing
		}
		return 1000 * m_pEngine->GetCurrentTime(); // Returns time in milliseconds
	}

	// volume (0.0 = Silent, 1.0 = Max Volume)
	void SetVolume(double volume)
	{
		if (!m_pEngine) return;
		if (volume < 0.0) volume = 0.0;
		if (volume > 1.0) volume = 1.0;
		m_pEngine->SetVolume(volume);
	}

	void StopPlaying()
	{
		// pause ...
		if (!m_pEngine) return;
		HRESULT hr = m_pEngine->Pause();
		if (SUCCEEDED(hr)) {
			// and rewind for next time (not needed actually here)
			hr = m_pEngine->SetCurrentTime(0.0);
		}
	}
};


WindowsAudioPlayer* AP = NULL;


/************** native win32 midi playing routines using ancient MCI interface ************************/

static int         midi_number = -1;
static plainstring midi_filenames[MAX_MIDI];

// whether the SimuMIDI alias is open; MCI cannot tell a finished song from one that never opened
static bool midi_open = false;
// songs MCI could not open or play are skipped from then on instead of retried
static bool midi_failed[MAX_MIDI];
static int  midi_failed_count = 0;


static int OldMIDIVol[2] = {-1, -1};

bool last_playing_midi = true;

#define __MIDI_VOL_SIMU    1  // 0-255
#define __MIDI_VOL_WIN32   2  // 0-65535


void __win32_set_midi_volume(int type, int left, int right);


/**
 * sets midi playback volume
 */
void dr_set_midi_volume(int vol)
{
	__win32_set_midi_volume(__MIDI_VOL_SIMU, vol, vol);
	if (AP) {
		AP->SetVolume(vol / 255.0);
	}
}


/**
 * Loads a MIDI file
 */

int dr_load_midi(const char *filename)
{
	if(midi_number < MAX_MIDI-1) {
		const int i = midi_number + 1;

		if (i >= 0 && i < MAX_MIDI) {

			// MCI doesn't like relative paths
			// but we get absolute ones anyway
			// already absolute path
			midi_filenames[i] = filename;

			// need to make dos path separators
			for (char* j = const_cast<char *>(midi_filenames[i].c_str()); *j != '\0'; ++j) {
				if (*j == '/') {
					*j = '\\';
				}
			}

			midi_failed[i] = false;
			midi_number = i;
		}
	}
	return midi_number;
}


/**
 * Plays a MIDI file
 * Key: The index of the MIDI file to be played
 */
void dr_play_midi(int key)
{
	char retstr[200];

	if (midi_number >= 0) {

		if (key >= 0 && key <= midi_number) {

			if (midi_failed[key]) {
				return; // already reported
			}

			if (last_playing_midi) {
				// stop last open one (just to be sure)
				mciSendStringA("stop SimuMIDI", retstr, 200, NULL);
				mciSendStringA("close SimuMIDI", retstr, 200, NULL);
				last_playing_midi = false;
			}

			// find out if midi
			const char* f = midi_filenames[key].c_str();
			if (const char* r = strrchr(f, '.')) {
				if (STRNICMP(r+1, "MID", 3) != 0) {
					if (!AP->PlayFile(midi_filenames[key])) {
						midi_failed[key] = true;
					}
					return;
				}
			}
			else {
				if (!AP->PlayFile(midi_filenames[key])) {
					midi_failed[key] = true;
				}
				return;
			}

			char command[MAX_PATH + 100];
			sprintf(command, "open \"%s\" type sequencer alias SimuMIDI", midi_filenames[key].c_str());
			dbg->debug("dr_play_midi(w32)", "MCI string: %s",command);

			// the name is UTF-8 and of any length: hand it to MCI as a wide string
			MCIERROR err = MCIERR_INVALID_FILE;
			WCHAR wCmd[MAX_PATH + 100];
			const size_t wlen = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, command, -1, NULL, 0);
			if (wlen > 0  &&  wlen < lengthof(wCmd)) {
				MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, command, -1, wCmd, wlen);
				err = mciSendStringW(wCmd, NULL, 0, NULL);
			}
			if (err == 0) {
				err = mciSendStringA("play SimuMIDI", NULL, 0, NULL);
				if (err != 0) {
					mciSendStringA("close SimuMIDI", NULL, 0, NULL);
				}
			}
			if (err == 0) {
				midi_open = true;
				last_playing_midi = true;
			}
			else {
				mciGetErrorStringA(err, retstr, sizeof(retstr));
				dbg->warning("dr_play_midi(w32)", "Unable to play MIDI %d (%s): %s", key, midi_filenames[key].c_str(), retstr);
				midi_failed[key] = true;
				if (++midi_failed_count > midi_number) {
					dbg->warning("dr_play_midi(w32)", "No MIDI file could be played, music stays silent");
				}
			}
		}
		else {
			dbg->warning("dr_play_midi(w32)", "Unable to play MIDI %d", key);
		}
	}
}



/**
 * Stops playing MIDI file
 */
void dr_stop_midi()
{
	if (AP) {
		AP->StopPlaying();
	}

	//   stop_midi();
	char retstr[200];

	mciSendStringA("stop SimuMIDI", retstr, 200, NULL);
	mciSendStringA("close SimuMIDI", retstr, 200, NULL);
	midi_open = false;
}


/**
 * Returns the midi_pos variable
 */
sint32 dr_midi_pos()
{
	if (!last_playing_midi) {
		if (AP) {
			return AP->GetPosition();
		}
		return 0;
	}


	char retstr[200];
	long length;

	if (!midi_open) {
		// nothing is playing: move on to the next song, unless none of them can be played
		return midi_failed_count > midi_number ? 0 : -1;
	}

	mciSendStringA("set SimuMIDI time format milliseconds", retstr, 200, NULL);
	mciSendStringA("status SimuMIDI length", retstr, 200, NULL);
	length = atol(retstr);

	if (mciSendStringA("status SimuMIDI position", retstr, 200, NULL) == 0) {
		const long pos = atol(retstr);
		if (pos == length) {
			mciSendStringA("stop SimuMIDI", retstr, 200, NULL);  // We must stop ourselves
			mciSendStringA("close SimuMIDI", retstr, 200, NULL);
			midi_open = false;
			return (-1);
		}
		else {
			return pos;
		}
	}
	return 0;
}


void dr_clear_midi()
{
	dr_stop_midi();
	midi_number = -1;
	midi_failed_count = 0;
}


const char *dr_get_midi_extensions()
{
	// MCI is asked for a sequencer, so MIDI only
	return ".mid .midi ";
}


/**
 * Midi shutdown/cleanup
 */
void dr_destroy_midi()
{
	dr_stop_midi();
	__win32_set_midi_volume(__MIDI_VOL_WIN32, OldMIDIVol[0], OldMIDIVol[1]);
	midi_number = -1;
	midi_failed_count = 0;
	if (AP) {
		delete AP;
		AP = NULL;
	}
}


/**
 * MIDI initialisation routines
 */
bool dr_init_midi()
{
	if (!AP) {
		AP = new WindowsAudioPlayer();
	}
 #ifdef MIXER_VOLUME
	UINT nMIDIDevices;
	MIXERLINECONTROLS mlc;
	MIXERCONTROL MixControl;
	MIXERCONTROLDETAILS MixControlDetails;
	MIXERCONTROLDETAILS_UNSIGNED MixControlDetailsUnsigned[2];
	MIXERLINE MixerLine;
	HMIXER hMixer;
	MIXERCAPS DevCaps;

	// Reset MIDI volume

	nMIDIDevices = midiOutGetNumDevs();

	if (nMIDIDevices == 0)
		return;

	mixerOpen(&hMixer, 0, 0, 0, MIXER_OBJECTF_MIDIOUT);
	mixerGetDevCaps((UINT) hMixer, &DevCaps, sizeof(DevCaps));
	mixerClose(hMixer);

	MixerLine.cbStruct = sizeof(MixerLine);
	MixerLine.Target.dwType = MIXERLINE_TARGETTYPE_MIDIOUT;
	MixerLine.Target.wMid = DevCaps.wMid;
	MixerLine.Target.wPid = DevCaps.wPid;
	MixerLine.Target.vDriverVersion = DevCaps.vDriverVersion;
	strcpy(MixerLine.Target.szPname, DevCaps.szPname);

	mixerGetLineInfo(0, &MixerLine, MIXER_GETLINEINFOF_TARGETTYPE | MIXER_OBJECTF_MIDIOUT);

	mlc.cbStruct = sizeof(mlc);
	mlc.dwLineID = MixerLine.dwLineID;
	mlc.dwControlType = MIXERCONTROL_CONTROLTYPE_VOLUME;
	mlc.cControls = 1;
	mlc.cbmxctrl = sizeof(MixControl);
	mlc.pamxctrl = &MixControl;

	MixControl.cbStruct = sizeof(MixControl);
	MixControl.dwControlType = MIXERCONTROL_CONTROLTYPE_VOLUME;

	mixerGetLineControls(0, &mlc, MIXER_OBJECTF_MIDIOUT | MIXER_GETLINECONTROLSF_ONEBYTYPE);

	MixControlDetails.cbStruct = sizeof(MixControlDetails);
	MixControlDetails.dwControlID = MixControl.dwControlID;
	MixControlDetails.cChannels = MixerLine.cChannels;
	MixControlDetails.hwndOwner = NULL;
	MixControlDetails.cMultipleItems = 0;
	MixControlDetails.cbDetails = sizeof(MixControlDetailsUnsigned[0])*2;
	MixControlDetails.paDetails = &MixControlDetailsUnsigned[0];

	mixerGetControlDetails(0, &MixControlDetails, MIXER_OBJECTF_MIDIOUT | MIXER_GETCONTROLDETAILSF_VALUE);

	OldMIDIVol[0] = MixControlDetailsUnsigned[0].dwValue;  // Save the old volume
	OldMIDIVol[1] = MixControlDetailsUnsigned[0].dwValue;

	sound_set_midi_volume_var(OldMIDIVol[0] >> 8); // Set the MIDI volume

	mixerSetControlDetails(0, &MixControlDetails, MIXER_OBJECTF_MIDIOUT | MIXER_SETCONTROLDETAILSF_VALUE);
#else
	if( midiOutGetNumDevs()== 0 ) {
		return false;
	}
	DWORD old_volume;
	midiOutGetVolume( 0, &old_volume );
	OldMIDIVol[0] = old_volume>>24;
	OldMIDIVol[1] = (old_volume&0x0000FF00)>>8;
#endif
	// assuming if we got here, all is set up to work properly
	return true;
}


#ifdef MIXER_VOLUME
// Sets the MIDI volume - internal routine
void __win32_set_midi_volume(int type, int left, int right)
{
	UINT nMIDIDevices;
	MIXERLINECONTROLS mlc;
	MIXERCONTROL MixControl;
	MIXERCONTROLDETAILS MixControlDetails;
	MIXERCONTROLDETAILS_UNSIGNED MixControlDetailsUnsigned[2];
	MIXERLINE MixerLine;
	HMIXER hMixer;
	MIXERCAPS DevCaps;

	nMIDIDevices = midiOutGetNumDevs();
	if (nMIDIDevices == 0) {
		return;
	}

	mixerOpen(&hMixer, 0, 0, 0, MIXER_OBJECTF_MIDIOUT);
	mixerGetDevCaps((UINT) hMixer, &DevCaps, sizeof(DevCaps));
	mixerClose(hMixer);

	MixerLine.cbStruct = sizeof(MixerLine);
	MixerLine.Target.dwType = MIXERLINE_TARGETTYPE_MIDIOUT;
	MixerLine.Target.wMid = DevCaps.wMid;
	MixerLine.Target.wPid = DevCaps.wPid;
	MixerLine.Target.vDriverVersion = DevCaps.vDriverVersion;
	strcpy(MixerLine.Target.szPname, DevCaps.szPname);

	mixerGetLineInfo(0, &MixerLine, MIXER_GETLINEINFOF_TARGETTYPE | MIXER_OBJECTF_MIDIOUT);

	mlc.cbStruct = sizeof(mlc);
	mlc.dwLineID = MixerLine.dwLineID;
	mlc.dwControlType = MIXERCONTROL_CONTROLTYPE_VOLUME;
	mlc.cControls = 1;
	mlc.cbmxctrl = sizeof(MixControl);
	mlc.pamxctrl = &MixControl;

	MixControl.cbStruct = sizeof(MixControl);
	MixControl.dwControlType = MIXERCONTROL_CONTROLTYPE_VOLUME;

	mixerGetLineControls(0, &mlc, MIXER_OBJECTF_MIDIOUT | MIXER_GETLINECONTROLSF_ONEBYTYPE);

	MixControlDetails.cbStruct = sizeof(MixControlDetails);
	MixControlDetails.dwControlID = MixControl.dwControlID;
	MixControlDetails.cChannels = MixerLine.cChannels;
	MixControlDetails.hwndOwner = NULL;
	MixControlDetails.cMultipleItems = 0;
	MixControlDetails.cbDetails = sizeof(MixControlDetailsUnsigned[0])*2;
	MixControlDetails.paDetails = &MixControlDetailsUnsigned[0];

	mixerGetControlDetails(0, &MixControlDetails, MIXER_OBJECTF_MIDIOUT | MIXER_GETCONTROLDETAILSF_VALUE);

	if (type == __MIDI_VOL_SIMU)
	{
		MixControlDetailsUnsigned[0].dwValue = (left << 8);
		MixControlDetailsUnsigned[1].dwValue = (right << 8);
	}
	else
	{
		MixControlDetailsUnsigned[0].dwValue = left;
		MixControlDetailsUnsigned[1].dwValue = right;
	}

	mixerSetControlDetails(0, &MixControlDetails, MIXER_OBJECTF_MIDIOUT | MIXER_SETCONTROLDETAILSF_VALUE);

	// Phew, I'm glad that's over! What a horrible API...
}
#else
// Sets the MIDI volume - internal routine
void __win32_set_midi_volume(int , int left, int right)
{
	// short version
	long vol = (left<<24)|(right<<8);

	if( midiOutGetNumDevs()== 0 ) {
		return;
	}
	midiOutSetVolume( 0, vol );
}
#endif
