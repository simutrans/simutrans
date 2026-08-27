/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

/*
 * SDL3 platform backend.
 *
 * This implements the dr_* contract of simsys.h on top of SDL3, with the
 * existing software renderer unchanged: simgraph16 still draws into a CPU
 * framebuffer in PIXVAL format and this file only presents it. There is no
 * SDL_GPU here and no renderer change.
 *
 * simsys_s2.cc (SDL2) and this file are never compiled together - the build
 * selects exactly one platform file - so the dr_* symbols cannot collide and
 * SDL2 and SDL3 cannot end up in the same binary.
 *
 * The one deliberate divergence from simsys_s2 is who owns the framebuffer:
 *
 *   simsys_s2  simgraph16 draws straight into the pixels of an SDL_Surface,
 *              so SDL's pitch is also the engine's pitch.
 *   simsys_s3  the framebuffer is a plain contiguous allocation of ours whose
 *              pitch in pixels is exactly the width handed to simgraph16. The
 *              streaming texture may use any pitch it likes; presentation
 *              copies into it.
 *
 * That divergence is not a preference: SDL_CreateRGBSurface does not exist in
 * SDL3, so the surface had to go anyway.
 *
 * Not implemented here, and deliberately so - see the SDL3 integration plan:
 *   - IME candidate lists (SDL_EVENT_TEXT_EDITING_CANDIDATES has no SDL2
 *     counterpart, and Simutrans has nothing to display one with)
 *
 * Audio is not here either, but it is not missing: sound is in
 * sound/sdl3_sound.cc, and music comes from the same per-platform routine the
 * sdl2 backend uses. simsys_s2.cc leaves both out for the same reason.
 */

#include <SDL3/SDL.h>

#ifdef _WIN32
#include <windows.h>
#endif

#include <assert.h>
#include <stdlib.h>
#include <string.h>

#include "simsys.h"

#include "../macros.h"
#include "../simversion.h"
#include "../simevent.h"
#include "../simintr.h"
#include "../simdebug.h"
#include "../display/simgraph.h"
#include "../dataobj/environment.h"
#include "../dataobj/loadsave.h"
#include "../gui/simwin.h"
#include "../gui/components/gui_component.h"
#include "../gui/components/gui_textinput.h"
#include "../music/music.h"
#include "../utils/unicode.h"
#include "../world/simworld.h"


static Uint8 hourglass_cursor[] = {
	0x3F, 0xFE, //   *************
	0x30, 0x06, //   **         **
	0x3F, 0xFE, //   *************
	0x10, 0x04, //    *         *
	0x10, 0x04, //    *         *
	0x12, 0xA4, //    *  * * *  *
	0x11, 0x44, //    *  * * *  *
	0x18, 0x8C, //    **   *   **
	0x0C, 0x18, //     **     **
	0x06, 0xB0, //      ** * **
	0x03, 0x60, //       ** **
	0x03, 0x60, //       **H**
	0x06, 0x30, //      ** * **
	0x0C, 0x98, //     **     **
	0x18, 0x0C, //    **   *   **
	0x10, 0x84, //    *    *    *
	0x11, 0x44, //    *   * *   *
	0x12, 0xA4, //    *  * * *  *
	0x15, 0x54, //    * * * * * *
	0x3F, 0xFE, //   *************
	0x30, 0x06, //   **         **
	0x3F, 0xFE  //   *************
};

static Uint8 hourglass_cursor_mask[] = {
	0x3F, 0xFE, //   *************
	0x3F, 0xFE, //   *************
	0x3F, 0xFE, //   *************
	0x1F, 0xFC, //    ***********
	0x1F, 0xFC, //    ***********
	0x1F, 0xFC, //    ***********
	0x1F, 0xFC, //    ***********
	0x1F, 0xFC, //    ***********
	0x0F, 0xF8, //     *********
	0x07, 0xF0, //      *******
	0x03, 0xE0, //       *****
	0x03, 0xE0, //       **H**
	0x07, 0xF0, //      *******
	0x0F, 0xF8, //     *********
	0x1F, 0xFC, //    ***********
	0x1F, 0xFC, //    ***********
	0x1F, 0xFC, //    ***********
	0x1F, 0xFC, //    ***********
	0x1F, 0xFC, //    ***********
	0x3F, 0xFE, //   *************
	0x3F, 0xFE, //   *************
	0x3F, 0xFE  //   *************
};

static Uint8 blank_cursor[] = {
	0x0,
	0x0,
};


static SDL_Window   *window    = NULL;
static SDL_Renderer *renderer  = NULL;
static SDL_Texture  *screen_tx = NULL;

/* The framebuffer is ours: contiguous, and its pitch in pixels is fb_pitch. */
static PIXVAL *framebuffer = NULL;
static int     fb_pitch    = 0; // in pixels
static int     fb_height   = 0;
static size_t  fb_bytes    = 0;

static int    sync_blit       = 0;
static int    use_dirty_tiles = 1;
static sint16 fullscreen      = WINDOWED;

static SDL_Cursor *arrow     = NULL;
static SDL_Cursor *hourglass = NULL;
static SDL_Cursor *blank     = NULL;

static bool has_soft_keyboard = false;

// Number of fractional bits for screen scaling
#define SCALE_SHIFT_X 5
#define SCALE_SHIFT_Y 5

#define SCALE_NEUTRAL_X (1 << SCALE_SHIFT_X)
#define SCALE_NEUTRAL_Y (1 << SCALE_SHIFT_Y)

// Multiplier when converting from texture to screen coords, fixed point format
static sint32 x_scale = SCALE_NEUTRAL_X;
static sint32 y_scale = SCALE_NEUTRAL_Y;

// When using -autodpi, attempt to scale things on screen to this DPI value
#define TARGET_DPI (96)

// make sure we have at least so much pixel in y-direction
#define MIN_SCALE_HEIGHT (640)

// screen -> texture coords
#define SCREEN_TO_TEX_X(x) (((x) * SCALE_NEUTRAL_X) / x_scale)
#define SCREEN_TO_TEX_Y(y) (((y) * SCALE_NEUTRAL_Y) / y_scale)

// texture -> screen coords
#define TEX_TO_SCREEN_X(x) (((x) * x_scale) / SCALE_NEUTRAL_X)
#define TEX_TO_SCREEN_Y(y) (((y) * y_scale) / SCALE_NEUTRAL_Y)


/* --------------------------------------------------------------- scaling */

bool dr_set_screen_scale(sint16 scale_percent)
{
	const sint32 old_x_scale = x_scale;
	const sint32 old_y_scale = y_scale;

	if(  scale_percent == -1  ) {
		/* SDL2->SDL3: SDL_GetDisplayDPI() is gone. SDL3 reports a unitless
		 * content scale instead, where 1.0 means 96 dpi by definition. The
		 * arithmetic below therefore reproduces the SDL2 result rather than
		 * introducing a different scaling policy. */
		const SDL_DisplayID    disp  = SDL_GetPrimaryDisplay();
		const SDL_DisplayMode *mode  = SDL_GetCurrentDisplayMode( disp );
		const float            scale = SDL_GetDisplayContentScale( disp );

		if(  mode  &&  scale > 0.0f  &&  mode->h > 1.5 * MIN_SCALE_HEIGHT  ) {
			x_scale = (sint32)(scale * SCALE_NEUTRAL_X + 0.5f);
			y_scale = (sint32)(scale * SCALE_NEUTRAL_Y + 0.5f);
			DBG_MESSAGE("dr_set_screen_scale(SDL3)", "content scale %.2f -> x=%i, y=%i", scale, x_scale, y_scale);
		}

		// ensure minimum height
		if(  mode  ) {
			const sint32 current_y = SCREEN_TO_TEX_Y( mode->h );
			if(  current_y < MIN_SCALE_HEIGHT  ) {
				DBG_MESSAGE("dr_set_screen_scale(SDL3)", "virtual height=%d < %d", current_y, MIN_SCALE_HEIGHT);
				x_scale = (x_scale * current_y) / MIN_SCALE_HEIGHT;
				y_scale = (y_scale * current_y) / MIN_SCALE_HEIGHT;
			}
		}
	}
	else if(  scale_percent == 0  ) {
		x_scale = SCALE_NEUTRAL_X;
		y_scale = SCALE_NEUTRAL_Y;
	}
	else {
		x_scale = (scale_percent * SCALE_NEUTRAL_X) / 100;
		y_scale = (scale_percent * SCALE_NEUTRAL_Y) / 100;
	}

	if(  window  &&  (x_scale != old_x_scale  ||  y_scale != old_y_scale)  ) {
		// force window resize
		int w, h;
		SDL_GetWindowSize( window, &w, &h );

		/* SDL2->SDL3: SDL_WINDOWEVENT with a sub-event field became one event
		 * type per window action, so the synthetic resize is pushed directly.
		 * SDL_PushEvent returns true when the event was queued. */
		SDL_Event ev;
		SDL_zero( ev );
		ev.type            = SDL_EVENT_WINDOW_RESIZED;
		ev.window.windowID = SDL_GetWindowID( window );
		ev.window.data1    = w;
		ev.window.data2    = h;

		return SDL_PushEvent( &ev );
	}

	return true;
}


sint16 dr_get_screen_scale()
{
	return (sint16)((x_scale * 100) / SCALE_NEUTRAL_X);
}


/* --------------------------------------------------- application lifecycle */

/**
 * Save the settings without any user interface, for the case where the
 * operating system is about to suspend or kill the process.
 */
static void save_settings_silently()
{
	dr_chdir( env_t::user_dir );

	loadsave_t settings_file;
	if(  settings_file.wr_open( "settings.xml", loadsave_t::xml, 0, "settings only/", SAVEGAME_VER_NR ) == loadsave_t::FILE_STATUS_OK  ) {
		env_t::rdwr( &settings_file );
		env_t::default_settings.rdwr( &settings_file );
		settings_file.close();
	}
}


/* SDL2->SDL3: an SDL_EventFilter now returns bool, and the application lifecycle
 * events must be handled from a watch rather than from the poll loop. That is not
 * a style preference: SDL_SendAppEvent hands SDL_EVENT_TERMINATING, LOW_MEMORY and
 * the four background/foreground events straight to the event watchers and never
 * queues them, so SDL_PollEvent cannot return one. Under SDL2 the same events were
 * pushed onto the queue like any other, which is why simsys_s2 can handle the
 * foreground case in its event loop and this file cannot.
 *
 * A watch cannot drop events, which is fine here: nothing else consumes these.
 *
 * On Windows, Linux and macOS these events do not occur. The handlers exist so that
 * the contract of simsys_s2.cc is preserved rather than silently dropped. */
static bool SDLCALL app_lifecycle_watch(void * /*userdata*/, SDL_Event *event)
{
	switch(  event->type  ) {
		case SDL_EVENT_DID_ENTER_BACKGROUND:
			intr_disable();
			save_settings_silently();
			dr_stop_midi();
			break;

		/* Coming back. The partner of the above: that one stops the interrupt,
		 * and without this one nothing ever starts it again - the game would
		 * return to the screen frozen. simsys_s2 handles this from its poll loop
		 * instead, and copying that placement would have produced dead code:
		 * SDL2 pushes application events onto the queue like any other, but
		 * SDL_SendAppEvent in SDL3 hands the six lifecycle events to the event
		 * watchers and deliberately never queues them, so SDL_PollEvent can
		 * never return one.
		 *
		 * The watch runs on the thread that pumps events, which is this game's
		 * main thread - Android_PumpEvents dispatches the resume - so the text
		 * input call below is on the thread that owns it.
		 *
		 * dr_stop_textinput() first, as simsys_s2 does: the soft keyboard does
		 * not survive the trip to the background, and a stale one would leave
		 * the game accepting text nobody can see being typed. */
		case SDL_EVENT_DID_ENTER_FOREGROUND:
			dr_stop_textinput();
			intr_enable();
			break;

		case SDL_EVENT_TERMINATING:
			// Quitting immediately: save the game and the settings with no
			// visual feedback, then leave the rest of the cleanup to the OS.
			intr_disable();
			DBG_DEBUG("app_lifecycle_watch(SDL3)", "env_t::reload_and_save_on_quit=%d", env_t::reload_and_save_on_quit);
			world()->stop( true );
			save_settings_silently();
			dr_stop_midi();
			dr_os_close();
			exit( 0 );
			break;

		default:
			break;
	}

	return true;
}


/* ------------------------------------------------------------------- init */

bool dr_os_init(const int *parameter)
{
	/* SDL2 always sent SDL_TEXTEDITING. SDL3 only sends SDL_EVENT_TEXT_EDITING
	 * if the application declares that it draws the composition itself: the
	 * default for SDL_HINT_IME_IMPLEMENTED_UI is "none", and then the OS draws
	 * the preedit and no editing event ever arrives. Simutrans does draw it -
	 * gui_textinput_t underlines the composition and highlights the target
	 * clause - so without this line the whole IME path below is dead code.
	 *
	 * Deliberately NOT "candidates": Simutrans has nothing to draw a candidate
	 * list with, so the OS has to keep drawing that one, which is also what it
	 * does under SDL2. The hint must be set before SDL_Init. */
	SDL_SetHint( SDL_HINT_IME_IMPLEMENTED_UI, "composition" );

	/* Touch must not also arrive as mouse input: the finger handling below
	 * produces the clicks itself, and with both a tap would act twice. This is
	 * simsys_s2's SDL_HINT_TOUCH_MOUSE_EVENTS, set before SDL_Init so no
	 * subsystem can latch the default first. */
	SDL_SetHint( SDL_HINT_TOUCH_MOUSE_EVENTS, "0" );

	// SDL2->SDL3: SDL_Init returns true on success, where SDL2 returned 0.
	if(  !SDL_Init( SDL_INIT_VIDEO )  ) {
		dbg->error( "dr_os_init(SDL3)", "Could not initialize SDL: %s", SDL_GetError() );
		return false;
	}

	/* Which screen orientations the game may be rotated to, on the two
	 * platforms that have a say in it - Android and iOS. Simutrans allows all
	 * four, and this is simsys_s2's string unchanged: it is a statement about
	 * the game, not about SDL, so it does not become a different set under a
	 * different backend.
	 *
	 * Placed here, after SDL_Init and before the window exists, because that
	 * is where simsys_s2 sets it and because SDL3 reads it at exactly the same
	 * moment SDL2 did: Android_CreateWindow passes SDL_GetHint(
	 * SDL_HINT_ORIENTATIONS ) straight to Android_JNI_SetOrientation, and
	 * SDL_uikitwindow.m reads it when the window is made. The hint
	 * documentation says "before SDL is initialized", which is stricter than
	 * the code needs; following the documentation instead of the code would
	 * have moved the call for no reason and diverged from simsys_s2. */
	SDL_SetHint( SDL_HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight Portrait PortraitUpsideDown" );

	dbg->message( "dr_os_init(SDL3)", "SDL %d.%d.%d, video driver: %s",
		SDL_MAJOR_VERSION, SDL_MINOR_VERSION, SDL_MICRO_VERSION, SDL_GetCurrentVideoDriver() );

	/* SDL2->SDL3: SDL_EventState() became SDL_SetEventEnabled(). SDL3 has no
	 * dollar gestures to switch off, and no multigesture either - see the
	 * touch section further down. */
	SDL_SetEventEnabled( SDL_EVENT_FINGER_DOWN,     true );
	SDL_SetEventEnabled( SDL_EVENT_FINGER_UP,       true );
	SDL_SetEventEnabled( SDL_EVENT_FINGER_MOTION,   true );
	SDL_SetEventEnabled( SDL_EVENT_FINGER_CANCELED, true );
	SDL_SetEventEnabled( SDL_EVENT_CLIPBOARD_UPDATE, false );
	SDL_SetEventEnabled( SDL_EVENT_DROP_FILE,     false );

	SDL_AddEventWatch( app_lifecycle_watch, NULL );

	has_soft_keyboard = SDL_HasScreenKeyboardSupport();
	if(  has_soft_keyboard  &&  !env_t::hide_keyboard  ) {
		env_t::hide_keyboard = true;
	}

	sync_blit       = parameter[0]; // hijack SDL1 -async flag for vsync
	use_dirty_tiles = !parameter[1]; // hijack SDL1 -use_hw flag to force full screen updates

	// prepare for next event
	sys_event.type = SIM_NOEVENT;
	sys_event.code = 0;

	return true;
}


resolution dr_query_screen_resolution()
{
	resolution res;

	/* SDL2->SDL3: displays are addressed by SDL_DisplayID rather than by index,
	 * and the mode is returned as a const pointer instead of being copied into
	 * a caller-provided struct. */
	const SDL_DisplayMode *mode = SDL_GetCurrentDisplayMode( SDL_GetPrimaryDisplay() );
	if(  !mode  ) {
		dbg->warning( "dr_query_screen_resolution(SDL3)", "no display mode: %s", SDL_GetError() );
		res.w = 1024;
		res.h = 768;
		return res;
	}

	DBG_MESSAGE("dr_query_screen_resolution(SDL3)", "screen resolution width=%d, height=%d", mode->w, mode->h);
	res.w = SCREEN_TO_TEX_X( mode->w );
	res.h = SCREEN_TO_TEX_Y( mode->h );
	return res;
}


/* ------------------------------------------------ framebuffer and texture */

static void internal_free_framebuffer()
{
	free( framebuffer );
	framebuffer = NULL;
	fb_pitch    = 0;
	fb_height   = 0;
	fb_bytes    = 0;
}


static bool internal_create_framebuffer(int pitch_pixels, int height)
{
	internal_free_framebuffer();

	const size_t bytes = (size_t)pitch_pixels * (size_t)height * sizeof(PIXVAL);
	framebuffer = (PIXVAL *)calloc( 1, bytes );
	if(  !framebuffer  ) {
		dbg->error( "internal_create_framebuffer(SDL3)", "cannot allocate %zu bytes", bytes );
		return false;
	}

	fb_pitch  = pitch_pixels;
	fb_height = height;
	fb_bytes  = bytes;
	return true;
}


static void internal_destroy_texture()
{
	if(  screen_tx  ) {
		SDL_DestroyTexture( screen_tx );
		screen_tx = NULL;
	}
}


static bool internal_create_surfaces(int tex_width, int tex_height)
{
	// The pixel format needs to match the graphics code within simgraph16.cc.
	// Note that alpha is handled by simgraph16, not by SDL.
	const SDL_PixelFormat pixel_format = SDL_PIXELFORMAT_RGB565;

	if(  !renderer  ) {
		/* SDL2->SDL3: SDL_CreateRenderer takes a driver name instead of an
		 * index and a flag set. The ACCELERATED/SOFTWARE flags no longer exist;
		 * SDL3 picks the best available driver itself and falls back on its
		 * own, so the explicit fallback of simsys_s2 has no counterpart. */
		renderer = SDL_CreateRenderer( window, NULL );
		if(  !renderer  ) {
			dbg->error( "internal_create_surfaces(SDL3)", "No suitable SDL3 renderer found: %s", SDL_GetError() );
			return false;
		}

		// SDL2->SDL3: vsync is a separate call rather than a creation flag.
		SDL_SetRenderVSync( renderer, sync_blit ? 1 : SDL_RENDERER_VSYNC_DISABLED );

		DBG_DEBUG("internal_create_surfaces(SDL3)", "Using renderer: %s, format: %s",
			SDL_GetRendererName( renderer ), SDL_GetPixelFormatName( pixel_format ));
	}

	internal_destroy_texture();
	screen_tx = SDL_CreateTexture( renderer, pixel_format, SDL_TEXTUREACCESS_STREAMING, tex_width, tex_height );
	if(  !screen_tx  ) {
		dbg->error( "internal_create_surfaces(SDL3)", "Couldn't create texture: %s", SDL_GetError() );
		return false;
	}

	/* SDL2->SDL3: SDL_HINT_RENDER_SCALE_QUALITY was replaced by a per-texture
	 * scale mode. Non-integer window scaling gets linear filtering, integer
	 * scaling stays nearest so the pixels are not smeared. */
	const bool integer_scaling = (x_scale & (SCALE_NEUTRAL_X - 1)) == 0  &&  (y_scale & (SCALE_NEUTRAL_Y - 1)) == 0;
	SDL_SetTextureScaleMode( screen_tx, integer_scaling ? SDL_SCALEMODE_NEAREST : SDL_SCALEMODE_LINEAR );

	/* The format has to be exactly COLOUR_DEPTH bits with no alpha, or the
	 * PIXVALs written by simgraph16 mean something else on screen. Checked
	 * rather than assumed.
	 *
	 * SDL2->SDL3: SDL_PixelFormatEnumToMasks was replaced by
	 * SDL_GetPixelFormatDetails, which returns a pointer OWNED BY SDL. Unlike
	 * SDL_AllocFormat it must not be freed. */
	const SDL_PixelFormatDetails *details = SDL_GetPixelFormatDetails( pixel_format );
	if(  !details  ) {
		dbg->error( "internal_create_surfaces(SDL3)", "Pixel format error: %s", SDL_GetError() );
		return false;
	}
	if(  details->bits_per_pixel != COLOUR_DEPTH  ||  details->Amask != 0  ) {
		dbg->error( "internal_create_surfaces(SDL3)", "Pixel format error. Bpp got %d, needed %d. Amask got %u, needed 0.",
			details->bits_per_pixel, COLOUR_DEPTH, details->Amask );
		return false;
	}

	return true;
}


// open the window
int dr_os_open(const scr_size window_size, sint16 fs)
{
	// scale up
	const resolution res   = dr_query_screen_resolution();
	const int        tex_w = clamp( res.w, 1, SCREEN_TO_TEX_X(window_size.w) );
	const int        tex_h = clamp( res.h, 1, SCREEN_TO_TEX_Y(window_size.h) );

	DBG_MESSAGE("dr_os_open(SDL3)", "Screen requested %i,%i, available max %i,%i", tex_w, tex_h, res.w, res.h);

	fullscreen = fs ? BORDERLESS : WINDOWED;

	// some cards need those alignments
	// especially 64bit want a border of 8bytes
	const int tex_pitch = max( (tex_w + 15) & 0x7FF0, 16 );

	/* SDL2->SDL3: SDL_CreateWindow lost its position arguments, the flags are
	 * 64 bit, and SDL_WINDOW_ALLOW_HIGHDPI is gone because high-DPI handling is
	 * the default. SDL_WINDOW_FULLSCREEN without an explicit fullscreen mode is
	 * the borderless desktop fullscreen that Simutrans expects. */
	SDL_WindowFlags flags = SDL_WINDOW_RESIZABLE;
	if(  fullscreen  ) {
		flags |= SDL_WINDOW_FULLSCREEN;
	}

	window = SDL_CreateWindow( SIM_TITLE, window_size.w, window_size.h, flags );
	if(  window == NULL  ) {
		dbg->error( "dr_os_open(SDL3)", "Could not open the window: %s", SDL_GetError() );
		return 0;
	}

	if(  !internal_create_surfaces( tex_pitch, tex_h )  ||  !internal_create_framebuffer( tex_pitch, tex_h )  ) {
		// Every failure path releases what it has already built, in the reverse
		// order of construction.
		internal_free_framebuffer();
		internal_destroy_texture();
		if(  renderer  ) {
			SDL_DestroyRenderer( renderer );
			renderer = NULL;
		}
		SDL_DestroyWindow( window );
		window = NULL;
		return 0;
	}

	DBG_MESSAGE("dr_os_open(SDL3)", "SDL realized screen size width=%d, height=%d (internal w=%d, h=%d)",
		window_size.w, window_size.h, tex_pitch, tex_h);

	// SDL2->SDL3: the default cursor is owned by SDL and must not be destroyed.
	arrow     = SDL_GetDefaultCursor();
	hourglass = SDL_CreateCursor( hourglass_cursor, hourglass_cursor_mask, 16, 22, 8, 11 );
	blank     = SDL_CreateCursor( blank_cursor, blank_cursor, 8, 2, 0, 0 );

	if(  !env_t::hide_keyboard  ) {
		// SDL2->SDL3: text input is started per window rather than globally.
		SDL_StartTextInput( window );
	}

	gfx->set_screen_actual_width( tex_w );
	gfx->set_screen_height( tex_h );
	return tex_pitch;
}


// shut down SDL
void dr_os_close()
{
	/* The destruction order matters and it is this one:
	 *   1 stop text input  - it is attached to the window, so it goes first
	 *   2 destroy texture  - a texture belongs to a renderer
	 *   3 destroy renderer - a renderer belongs to a window
	 *   4 free framebuffer - ours; nothing inside SDL points at it
	 *   5 destroy cursors  - independent of the window, but before SDL_Quit
	 *   6 destroy window   - now nothing refers to it
	 *   7 SDL_Quit         - last, or the calls above have no subsystem left
	 */
	if(  window  ) {
		SDL_StopTextInput( window );
	}

	internal_destroy_texture();

	if(  renderer  ) {
		SDL_DestroyRenderer( renderer );
		renderer = NULL;
	}

	internal_free_framebuffer();

	if(  blank  ) {
		SDL_DestroyCursor( blank );
		blank = NULL;
	}
	if(  hourglass  ) {
		SDL_DestroyCursor( hourglass );
		hourglass = NULL;
	}
	arrow = NULL; // owned by SDL, never created here

	if(  window  ) {
		SDL_DestroyWindow( window );
		window = NULL;
	}

	SDL_Quit();
}


unsigned short *dr_textur_init()
{
	// Never NULL in normal operation: dr_os_open() fails outright when the
	// allocation fails, rather than handing back a pointer nobody checks.
	return (unsigned short *)framebuffer;
}


// resizes screen
int dr_textur_resize(unsigned short **const textur, int tex_w, int const tex_h)
{
	// enforce multiple of 16 pixels, or there are likely mismatches
	const int tex_pitch = max( (tex_w + 15) & 0x7FF0, 16 );

	if(  tex_pitch != fb_pitch  ||  tex_h != fb_height  ) {
		if(  !internal_create_surfaces( tex_pitch, tex_h )  ||  !internal_create_framebuffer( tex_pitch, tex_h )  ) {
			dbg->error( "dr_textur_resize(SDL3)", "could not resize to %dx%d", tex_pitch, tex_h );
		}
		else {
			DBG_MESSAGE("dr_textur_resize(SDL3)", "SDL realized screen size width=%d, height=%d (internal w=%d, h=%d)",
				tex_w, tex_h, tex_pitch, tex_h);
		}
	}

	// The caller must pick up the new pointer: the old one is freed above.
	*textur = dr_textur_init();

	gfx->set_screen_actual_width( tex_w );
	return tex_pitch;
}


/**
 * Transform a 24 bit RGB color into the system format.
 * @return converted color value
 */
PIXVAL get_system_color(rgb888_t col)
{
	/* SDL2->SDL3: SDL_AllocFormat/SDL_FreeFormat became
	 * SDL_GetPixelFormatDetails, whose result belongs to SDL and must not be
	 * freed, and SDL_MapRGB gained a palette argument. */
	const SDL_PixelFormatDetails *details = SDL_GetPixelFormatDetails( SDL_PIXELFORMAT_RGB565 );
	if(  !details  ) {
		return 0;
	}

	const unsigned int ret = SDL_MapRGB( details, NULL, col.r, col.g, col.b );
	assert( (ret & 0xFFFF0000u) == 0 );
	return (PIXVAL)ret;
}


/* ----------------------------------------------------------- presentation */

void dr_prepare_flush()
{
	return;
}


void dr_flush()
{
	gfx->flush_framebuffer();

	if(  !screen_tx  ||  !framebuffer  ) {
		return;
	}

	if(  !use_dirty_tiles  ) {
		SDL_UpdateTexture( screen_tx, NULL, framebuffer, fb_pitch * (int)sizeof(PIXVAL) );
	}

	/* SDL2->SDL3: SDL_RenderCopy became SDL_RenderTexture and its rectangles
	 * are floats. The source rectangle is the LOGICAL screen and not the padded
	 * pitch, so the alignment padding never reaches the window. */
	const scr_size screen = gfx->get_screen_size();
	const SDL_FRect src   = { 0.0f, 0.0f, (float)min( (int)screen.w, fb_pitch ), (float)min( (int)screen.h, fb_height ) };

	SDL_RenderTexture( renderer, screen_tx, &src, NULL );
	SDL_RenderPresent( renderer );
}


void dr_textur(int xp, int yp, int w, int h)
{
	if(  !use_dirty_tiles  ||  !screen_tx  ||  !framebuffer  ) {
		return;
	}

	SDL_Rect r;
	r.x = xp;
	r.y = yp;
	r.w = xp + w > fb_pitch  ? fb_pitch  - xp : w;
	r.h = yp + h > fb_height ? fb_height - yp : h;

	if(  r.w <= 0  ||  r.h <= 0  ) {
		return;
	}

	const int pitch_bytes = fb_pitch * (int)sizeof(PIXVAL);
	SDL_UpdateTexture( screen_tx, &r,
		(const Uint8 *)framebuffer + (size_t)yp * pitch_bytes + (size_t)xp * sizeof(PIXVAL),
		pitch_bytes );
}


/* ------------------------------------------------------ touch and gestures */

/* SDL3 removed the gesture recogniser, and with it SDL_MULTIGESTURE - the one
 * event simsys_s2 pinch-zooms and three-finger-scrolls with. There is nothing
 * to call in its place: SDL_EVENT_PINCH_* does not exist in SDL 3.2.0, it
 * reports a scale ratio rather than a distance delta, and it carries neither a
 * position nor a finger count, so it could restore neither the sensitivity nor
 * the three finger scroll. What SDL3 does still deliver, since 3.2.0, are the
 * raw finger events, so the information Simutrans consumes is rebuilt here.
 *
 * The value to rebuild is mgesture.dDist, and it is not what the name suggests.
 * SDL2's recogniser (src/events/SDL_gesture.c) emits one gesture per FINGER
 * MOTION, and dDist is the change of THAT finger's distance to the centroid of
 * all fingers currently down - not the change of the distance between two
 * fingers. With two fingers the centroid is the midpoint, so each event carries
 * half of its step, and the running sum simsys_s2 keeps therefore telescopes to
 * half the change of the finger separation. The halving is not incidental:
 * dropping it would double the zoom sensitivity against the same DELTA_PINCH.
 *
 * The centroid is folded in and out exactly as SDL2 did. For a balanced down
 * and up sequence that is the true centroid of the fingers, so this inherits no
 * drift from the incremental form.
 *
 * Coordinates are normalized 0..1 in both SDL versions, and the arithmetic below
 * stays in that space, as SDL2's did - moving it to pixels would make the
 * threshold depend on the window aspect ratio. */

// threshold for zooming in/out with multitouch, as in simsys_s2
#define DELTA_PINCH (0.033)

/* Enough for every hand on the glass. A device that reports more simply has the
 * extra fingers ignored, which is safer than growing a table from a number the
 * driver chooses. */
#define MAX_FINGERS (16)

static bool in_finger_handling = false;

static struct {
	SDL_FingerID id[MAX_FINGERS];
	int          count;
	float        cx, cy; // centroid of the fingers down, normalized
} fingers;


/* SDL2->SDL3: SDL_FingerID is 64 bit now and is a device supplied handle, not
 * an index - it is never used to index anything here. */
static int finger_index(SDL_FingerID id)
{
	for(  int i = 0;  i < fingers.count;  i++  ) {
		if(  fingers.id[i] == id  ) {
			return i;
		}
	}
	return -1;
}


static void finger_down(SDL_FingerID id, float x, float y)
{
	// counting one finger twice would corrupt the centroid, and every distance
	// taken from it, for the rest of the gesture
	if(  fingers.count >= MAX_FINGERS  ||  finger_index( id ) >= 0  ) {
		return;
	}
	fingers.id[fingers.count] = id;
	fingers.count++;
	fingers.cx = (fingers.cx * (fingers.count - 1) + x) / fingers.count;
	fingers.cy = (fingers.cy * (fingers.count - 1) + y) / fingers.count;
}


static void finger_lifted(SDL_FingerID id, float x, float y)
{
	const int i = finger_index( id );
	if(  i < 0  ) {
		return;
	}
	fingers.count--;
	for(  int j = i;  j < fingers.count;  j++  ) {
		fingers.id[j] = fingers.id[j + 1];
	}
	if(  fingers.count > 0  ) {
		fingers.cx = (fingers.cx * (fingers.count + 1) - x) / fingers.count;
		fingers.cy = (fingers.cy * (fingers.count + 1) - y) / fingers.count;
	}
	else {
		// nothing is touching the screen: leave no residue for the next gesture
		fingers.cx = 0.0f;
		fingers.cy = 0.0f;
	}
}


/* Advances the centroid and returns what SDL2 would have put in dDist for this
 * motion. Zero below two fingers, because SDL2 emitted no gesture there. */
static double finger_moved(const SDL_TouchFingerEvent &tf)
{
	if(  finger_index( tf.fingerID ) < 0  ) {
		// a finger that never went down - SDL2 held no state for it either, and
		// this also keeps the divisor below away from zero
		return 0.0;
	}
	const float last_cx = fingers.cx;
	const float last_cy = fingers.cy;
	fingers.cx += tf.dx / fingers.count;
	fingers.cy += tf.dy / fingers.count;

	if(  fingers.count < 2  ) {
		return 0.0;
	}
	const float lvx   = (tf.x - tf.dx) - last_cx;
	const float lvy   = (tf.y - tf.dy) - last_cy;
	const float ldist = (float)SDL_sqrt( lvx * lvx + lvy * lvy );
	const float vx    = tf.x - fingers.cx;
	const float vy    = tf.y - fingers.cy;
	const float dist  = (float)SDL_sqrt( vx * vx + vy * vy );

	/* SDL2's guard, kept for the same reason: a finger sitting exactly on the
	 * centroid has no direction to grow along, and the step would be noise
	 * rather than a pinch. It also keeps a zero length vector out of the sum. */
	return ldist == 0.0f ? 0.0 : (double)(dist - ldist);
}


/* ----------------------------------------------------------------- cursor */

// move cursor to the specified location
bool move_pointer(int x, int y)
{
	/* While a finger is down the finger is the pointer: warping would fight
	 * it, and the caller has to know the cursor did not move. simsys_s2
	 * returns false here for the same reason. */
	if(  in_finger_handling  ) {
		return false;
	}
	// SDL2->SDL3: the warp coordinates are floats.
	SDL_WarpMouseInWindow( window, (float)TEX_TO_SCREEN_X(x), (float)TEX_TO_SCREEN_Y(y) );
	return true;
}


// set the mouse cursor (pointer/load)
void set_pointer(int loading)
{
	SDL_SetCursor( loading ? hourglass : arrow );
}


void show_pointer(int yesno)
{
	SDL_SetCursor( (yesno != 0) ? arrow : blank );
}


void ex_ord_update_mx_my()
{
	SDL_PumpEvents();
}


/* ----------------------------------------------------------------- events */

static inline unsigned int ModifierKeys()
{
	const SDL_Keymod mod = SDL_GetModState();

	return
		  ((mod & SDL_KMOD_SHIFT) ? SIM_KEYMOD_SHIFT : SIM_KEYMOD_NONE)
		| ((mod & SDL_KMOD_CTRL)  ? SIM_KEYMOD_CTRL  : SIM_KEYMOD_NONE)
#ifdef __APPLE__
		// Treat the Command key as a control key.
		| ((mod & SDL_KMOD_GUI)   ? SIM_KEYMOD_CTRL  : SIM_KEYMOD_NONE)
#endif
		;
}


static uint16 conv_mouse_buttons(SDL_MouseButtonFlags state)
{
	return
		(state & SDL_BUTTON_LMASK ? MOUSE_LEFTBUTTON  : 0) |
		(state & SDL_BUTTON_MMASK ? MOUSE_MIDBUTTON   : 0) |
		(state & SDL_BUTTON_RMASK ? MOUSE_RIGHTBUTTON : 0);
}


static void internal_GetEvents()
{
	static char textinput[256];

	/* Both of these exist in simsys_s2 for the same reasons and carry the same
	 * meaning here.
	 *
	 * composition_is_underway: while an IME is composing, key presses belong to
	 * the IME and must not reach the game. Without it a Bopomofo or Pinyin
	 * session drives Simutrans tools with every keystroke.
	 *
	 * ignore_previous_number: a numpad digit produces a key event AND a text
	 * input event, so the digit would be entered twice. */
	static bool composition_is_underway = false;
	static bool ignore_previous_number  = false;

	/* Touch state, all of it simsys_s2's and carrying the same meaning.
	 *
	 * previous_multifinger_touch: 0, or the number of fingers the current
	 * multi finger gesture is being read as - 2 pinches, 3 scrolls.
	 * FirstFingerId: the finger that owns the single finger drag; any other
	 * finger only ever turns the drag into a multi finger gesture.
	 * dLastDist: the running pinch sum, and below two fingers it doubles as
	 * the has-this-finger-moved-yet flag, exactly as in simsys_s2. */
	static int          previous_multifinger_touch = 0;
	static SDL_FingerID FirstFingerId = 0;
	static double       dLastDist = 0.0;

	/* A tap owes the game a press and a release, but only one sys_event fits
	 * in a poll, so the release waits here for the next one. */
	static bool   has_queued_finger_release = false;
	static sint32 last_mx = 0, last_my = 0;

	if(  has_queued_finger_release  ) {
		has_queued_finger_release = false;
		sys_event.type    = SIM_MOUSE_BUTTONS;
		sys_event.code    = SIM_MOUSE_LEFTUP;
		sys_event.mb      = 0;
		sys_event.mx      = last_mx;
		sys_event.my      = last_my;
		sys_event.key_mod = ModifierKeys();
		return;
	}

	SDL_Event event;
	// SDL2->SDL3: SDL_PollEvent returns bool instead of int. Zero still means
	// "no event", so the test itself is unchanged in meaning.
	if(  !SDL_PollEvent( &event )  ) {
		return;
	}

	DBG_DEBUG("SDL_EVENT", "0x%X", event.type);

	switch(  event.type  ) {

		case SDL_EVENT_QUIT:
		case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
			sys_event.type = SIM_SYSTEM;
			sys_event.code = SYSTEM_QUIT;
			break;


		/* SDL2->SDL3: SDL_WINDOWEVENT with a sub-event field became one event
		 * type per window action. SDL_WINDOWEVENT_SIZE_CHANGED, which is what
		 * simsys_s2 listens for, no longer exists as a separate event: in SDL3
		 * SDL_EVENT_WINDOW_RESIZED covers both a user resize and a resize
		 * caused by an API call, which is exactly what SIZE_CHANGED meant.
		 *
		 * SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED is deliberately not handled. It
		 * has no SDL2 counterpart, so reacting to it would be new behaviour
		 * rather than parity. */
		case SDL_EVENT_WINDOW_RESIZED:
			sys_event.type              = SIM_SYSTEM;
			sys_event.code              = SYSTEM_RESIZE;
			sys_event.new_window_size_w = max( 1, SCREEN_TO_TEX_X( event.window.data1 ) );
			sys_event.new_window_size_h = max( 1, SCREEN_TO_TEX_Y( event.window.data2 ) );
			break;

		case SDL_EVENT_MOUSE_BUTTON_DOWN:
			// a real button press is not part of a pinch, so the sum restarts
			dLastDist = 0.0;
			/* Belt and braces, as in simsys_s2: the hint set at startup already
			 * stops SDL turning a finger into a mouse, and a synthetic press must
			 * not act as a click when the finger handling makes its own. */
			if(  event.button.which == SDL_TOUCH_MOUSEID  ) {
				break;
			}
			sys_event.type = SIM_MOUSE_BUTTONS;
			switch(  event.button.button  ) {
				case SDL_BUTTON_LEFT:   sys_event.code = SIM_MOUSE_LEFTBUTTON;  break;
				case SDL_BUTTON_MIDDLE: sys_event.code = SIM_MOUSE_MIDBUTTON;   break;
				case SDL_BUTTON_RIGHT:  sys_event.code = SIM_MOUSE_RIGHTBUTTON; break;
				case SDL_BUTTON_X1:     sys_event.code = SIM_MOUSE_WHEELUP;     break;
				case SDL_BUTTON_X2:     sys_event.code = SIM_MOUSE_WHEELDOWN;   break;
				// Any further button carries no meaning for Simutrans, but the
				// event still refreshes the button state below, as in simsys_s2.
				default:                sys_event.code = 0;                     break;
			}
			// SDL2->SDL3: the event coordinates are floats.
			sys_event.mx      = SCREEN_TO_TEX_X( (int)event.button.x );
			sys_event.my      = SCREEN_TO_TEX_Y( (int)event.button.y );
			sys_event.mb      = conv_mouse_buttons( SDL_GetMouseState( NULL, NULL ) );
			sys_event.key_mod = ModifierKeys();
			break;

		case SDL_EVENT_MOUSE_BUTTON_UP:
			/* Only genuine mouse releases: during or straight after a gesture the
			 * release belongs to the fingers, which send their own. */
			if(  previous_multifinger_touch  ||  in_finger_handling  ) {
				break;
			}
			sys_event.type = SIM_MOUSE_BUTTONS;
			switch(  event.button.button  ) {
				case SDL_BUTTON_LEFT:   sys_event.code = SIM_MOUSE_LEFTUP;  break;
				case SDL_BUTTON_MIDDLE: sys_event.code = SIM_MOUSE_MIDUP;   break;
				case SDL_BUTTON_RIGHT:  sys_event.code = SIM_MOUSE_RIGHTUP; break;
				default:                sys_event.code = 0;                break;
			}
			sys_event.mx      = SCREEN_TO_TEX_X( (int)event.button.x );
			sys_event.my      = SCREEN_TO_TEX_Y( (int)event.button.y );
			sys_event.mb      = conv_mouse_buttons( SDL_GetMouseState( NULL, NULL ) );
			sys_event.key_mod = ModifierKeys();
			break;

		case SDL_EVENT_MOUSE_WHEEL: {
			/* SDL2->SDL3: the wheel delta is a float. Simutrans wants a
			 * direction rather than an amount, so the sign is what is used and
			 * a fractional wheel produces one step per event.
			 *
			 * An event with no vertical component is not a scroll and must not
			 * become one: without this test it would read as WHEELDOWN. */
			if(  event.wheel.y == 0.0f  ) {
				sys_event.type = SIM_IGNORE_EVENT;
				break;
			}

			// The system may report the wheel reversed, in which case SDL sets
			// the direction to FLIPPED rather than changing the sign.
			const bool is_up = (event.wheel.y > 0.0f) ^ (event.wheel.direction == SDL_MOUSEWHEEL_FLIPPED);

			sys_event.type    = SIM_MOUSE_BUTTONS;
			sys_event.code    = is_up ? SIM_MOUSE_WHEELUP : SIM_MOUSE_WHEELDOWN;
			sys_event.key_mod = ModifierKeys();
			break;
		}

		case SDL_EVENT_MOUSE_MOTION:
			// a finger is driving the pointer, so the mouse must not fight it
			if(  in_finger_handling  ) {
				break;
			}
			sys_event.type    = SIM_MOUSE_MOVE;
			sys_event.code    = SIM_MOUSE_MOVED;
			sys_event.mx      = SCREEN_TO_TEX_X( (int)event.motion.x );
			sys_event.my      = SCREEN_TO_TEX_Y( (int)event.motion.y );
			sys_event.mb      = conv_mouse_buttons( event.motion.state );
			sys_event.key_mod = ModifierKeys();
			break;

		case SDL_EVENT_FINGER_DOWN:
			/* Nothing is reported yet: the press comes from the first motion, or
			 * from the finger up if the finger never moved, so the coordinate is
			 * the one the player finished on. simsys_s2 does the same. */
			finger_down( event.tfinger.fingerID, event.tfinger.x, event.tfinger.y );
			if(  !in_finger_handling  ) {
				dLastDist = 0.0;
				FirstFingerId = event.tfinger.fingerID;
				in_finger_handling = true;
				previous_multifinger_touch = 0;
			}
			else if(  FirstFingerId != event.tfinger.fingerID  ) {
				// a second finger: this is a gesture, not a drag
				previous_multifinger_touch = 2;
			}
			break;

		case SDL_EVENT_FINGER_MOTION: {
			/* Every motion feeds the reconstruction, including the ones thrown
			 * away right after. Under SDL2 the recogniser ran inside
			 * SDL_PumpEvents, so the multigesture events already existed when
			 * simsys_s2 swallowed the flood of finger motions, and their dDist
			 * still reached the sum. Coalescing before accumulating would change
			 * the zoom sensitivity by whatever share of the motions happens to be
			 * dropped - which varies with the frame rate. */
			double dist = finger_moved( event.tfinger );

			// swallow the millions of finger motion events
			SDL_Event next;
			while(  SDL_PeepEvents( &next, 1, SDL_GETEVENT, SDL_EVENT_FINGER_MOTION, SDL_EVENT_FINGER_MOTION ) == 1  ) {
				dist += finger_moved( next.tfinger );
				event = next;
			}
			dLastDist += dist;
			in_finger_handling = true;

			const scr_size screen_size = gfx->get_screen_size();

			if(  fingers.count == 2  ) {
				// any multitouch is interpreted as pinch zoom
				if(  dLastDist < -DELTA_PINCH  ) {
					sys_event.type    = SIM_MOUSE_BUTTONS;
					sys_event.code    = SIM_MOUSE_WHEELDOWN;
					sys_event.key_mod = ModifierKeys();
					dLastDist = 0;
				}
				else if(  dLastDist > DELTA_PINCH  ) {
					sys_event.type    = SIM_MOUSE_BUTTONS;
					sys_event.code    = SIM_MOUSE_WHEELUP;
					sys_event.key_mod = ModifierKeys();
					dLastDist = 0;
				}
				previous_multifinger_touch = 2;
			}
			else if(  fingers.count == 3  &&  framebuffer  ) {
				/* Any three finger touch scrolls the map, from the centroid that
				 * SDL2 reported in mgesture.x/y.
				 *
				 * simsys_s2 scales that by the surface size and then applies
				 * SCREEN_TO_TEX on top, although the surface is already texture
				 * sized, so at a screen scale other than 100% the position ends up
				 * scaled twice. Reproduced rather than corrected: it is the
				 * behaviour Simutrans has today, and the two agree exactly at the
				 * default scale. */
				const sint32 mx = (sint32)SCREEN_TO_TEX_X( fingers.cx * screen_size.w );
				const sint32 my = (sint32)SCREEN_TO_TEX_Y( fingers.cy * screen_size.h );
				if(  previous_multifinger_touch != 3  ) {
					// just started scrolling
					set_click_xy( mx, my );
				}
				sys_event.type    = SIM_MOUSE_MOVE;
				sys_event.code    = SIM_MOUSE_MOVED;
				sys_event.mb      = MOUSE_RIGHTBUTTON;
				sys_event.key_mod = ModifierKeys();
				sys_event.mx      = mx;
				sys_event.my      = my;
				previous_multifinger_touch = 3;
			}
			else if(  framebuffer  &&  previous_multifinger_touch == 0  &&  FirstFingerId == event.tfinger.fingerID  ) {
				// one finger drags, which the game reads as the left button
				if(  dLastDist == 0.0  ) {
					// no press was sent yet, so this motion carries it
					dLastDist = 1e-99;
					sys_event.type = SIM_MOUSE_BUTTONS;
					sys_event.code = SIM_MOUSE_LEFTBUTTON;
					previous_multifinger_touch = 0;
				}
				else {
					sys_event.type = SIM_MOUSE_MOVE;
					sys_event.code = SIM_MOUSE_MOVED;
				}
				sys_event.mx      = (sint32)(event.tfinger.x * screen_size.w);
				sys_event.my      = (sint32)(event.tfinger.y * screen_size.h);
				sys_event.mb      = MOUSE_LEFTBUTTON;
				sys_event.key_mod = ModifierKeys();
			}
			break;
		}

		/* SDL_EVENT_FINGER_CANCELED has no SDL2 counterpart: the system took the
		 * gesture away - a system edge swipe, the app sent to the background -
		 * and that finger will never be lifted. It ends the gesture the way an up
		 * does, but must not leave a click behind, because the player completed
		 * none. Ignoring it would strand in_finger_handling at true and freeze
		 * the pointer for the rest of the session. */
		case SDL_EVENT_FINGER_UP:
		case SDL_EVENT_FINGER_CANCELED: {
			const bool cancelled = (event.type == SDL_EVENT_FINGER_CANCELED);
			finger_lifted( event.tfinger.fingerID, event.tfinger.x, event.tfinger.y );

			if(  framebuffer  &&  in_finger_handling  ) {
				/* The gesture ends when the finger that owns it goes, or when the
				 * last finger does. simsys_s2 asks SDL for the live count here; the
				 * table above already knows it, and asking SDL3 would mean
				 * SDL_GetTouchFingers, which allocates an array to be freed. */
				if(  FirstFingerId == event.tfinger.fingerID  ||  fingers.count == 0  ) {
					const scr_size screen_size = gfx->get_screen_size();

					if(  !previous_multifinger_touch  &&  !cancelled  ) {
						if(  dLastDist == 0.0  ) {
							// a tap: the finger never moved, so press and release now
							dLastDist = 1e-99;
							sys_event.type    = SIM_MOUSE_BUTTONS;
							sys_event.code    = SIM_MOUSE_LEFTBUTTON;
							sys_event.mb      = MOUSE_LEFTBUTTON;
							sys_event.key_mod = ModifierKeys();
							last_mx = sys_event.mx = (sint32)(event.tfinger.x * screen_size.w);
							last_my = sys_event.my = (sint32)(event.tfinger.y * screen_size.h);

							// not moved yet, so set the click origin or the click lands
							// wherever the pointer happened to be left
							set_click_xy( sys_event.mx, sys_event.my );

							has_queued_finger_release = true;
						}
						else {
							// end of a drag
							sys_event.type    = SIM_MOUSE_BUTTONS;
							sys_event.code    = SIM_MOUSE_LEFTUP;
							sys_event.mb      = 0;
							sys_event.mx      = (sint32)((event.tfinger.x + event.tfinger.dx) * screen_size.w);
							sys_event.my      = (sint32)((event.tfinger.y + event.tfinger.dy) * screen_size.h);
							sys_event.key_mod = ModifierKeys();
						}
					}
					previous_multifinger_touch = 0;
					in_finger_handling = false;
					FirstFingerId = 0;
				}
			}
			break;
		}

		case SDL_EVENT_KEY_DOWN: {
			/* While a composition is under way the keys belong to the IME, so
			 * they are swallowed here - but only while the focused field really
			 * holds a pending string, or cursor keys and return would stop
			 * working after any composition has ever happened. Both conditions
			 * are simsys_s2's, unchanged. */
			if(  composition_is_underway  ) {
				if(  gui_component_t *c = win_get_focus()  ) {
					if(  gui_textinput_t *tinp = dynamic_cast<gui_textinput_t *>( c )  ) {
						if(  tinp->get_composition()[0]  ) {
							// pending string, handled by the IME
							break;
						}
					}
				}
			}

			bool np = false; // was it a numpad key?
			unsigned long code;
#ifdef _WIN32
			// SDL does not set the numlock state correctly on startup. Revert
			// to the win32 function as a workaround, as simsys_s2 does.
			const bool key_numlock = ((GetKeyState( VK_NUMLOCK ) & 1) != 0);
#else
			const bool key_numlock = (SDL_GetModState() & SDL_KMOD_NUM) != 0;
#endif
			const bool numlock = key_numlock  ||  (env_t::numpad_always_moves_map  &&  !win_is_textinput());

			sys_event.key_mod = ModifierKeys();

			// SDL2->SDL3: event.key.keysym.sym became event.key.key.
			const SDL_Keycode sym = event.key.key;

			switch(  sym  ) {
				case SDLK_BACKSPACE:  code = SIM_KEYCODE_BACKSPACE;  break;
				case SDLK_TAB:        code = SIM_KEYCODE_TAB;        break;
				case SDLK_RETURN:     code = SIM_KEYCODE_ENTER;      break;
				case SDLK_ESCAPE:     code = SIM_KEYCODE_ESCAPE;     break;
				case SDLK_DELETE:     code = SIM_KEYCODE_DELETE;     break;
				case SDLK_DOWN:       code = SIM_KEYCODE_DOWN;       break;
				case SDLK_END:        code = SIM_KEYCODE_END;        break;
				case SDLK_HOME:       code = SIM_KEYCODE_HOME;       break;
				case SDLK_F1:         code = SIM_KEYCODE_F1;         break;
				case SDLK_F2:         code = SIM_KEYCODE_F2;         break;
				case SDLK_F3:         code = SIM_KEYCODE_F3;         break;
				case SDLK_F4:         code = SIM_KEYCODE_F4;         break;
				case SDLK_F5:         code = SIM_KEYCODE_F5;         break;
				case SDLK_F6:         code = SIM_KEYCODE_F6;         break;
				case SDLK_F7:         code = SIM_KEYCODE_F7;         break;
				case SDLK_F8:         code = SIM_KEYCODE_F8;         break;
				case SDLK_F9:         code = SIM_KEYCODE_F9;         break;
				case SDLK_F10:        code = SIM_KEYCODE_F10;        break;
				case SDLK_F11:        code = SIM_KEYCODE_F11;        break;
				case SDLK_F12:        code = SIM_KEYCODE_F12;        break;
				case SDLK_F13:        code = SIM_KEYCODE_F13;        break;
				case SDLK_F14:        code = SIM_KEYCODE_F14;        break;
				case SDLK_F15:        code = SIM_KEYCODE_F15;        break;
				case SDLK_KP_0:       np = true; code = (numlock ? '0' : (unsigned long)SIM_KEYCODE_NUMPAD_BASE); break;
				case SDLK_KP_1:       np = true; code = (numlock ? '1' : (unsigned long)SIM_KEYCODE_DOWNLEFT);    break;
				case SDLK_KP_2:       np = true; code = (numlock ? '2' : (unsigned long)SIM_KEYCODE_DOWN);        break;
				case SDLK_KP_3:       np = true; code = (numlock ? '3' : (unsigned long)SIM_KEYCODE_DOWNRIGHT);   break;
				case SDLK_KP_4:       np = true; code = (numlock ? '4' : (unsigned long)SIM_KEYCODE_LEFT);        break;
				case SDLK_KP_5:       np = true; code = (numlock ? '5' : (unsigned long)SIM_KEYCODE_CENTER);      break;
				case SDLK_KP_6:       np = true; code = (numlock ? '6' : (unsigned long)SIM_KEYCODE_RIGHT);       break;
				case SDLK_KP_7:       np = true; code = (numlock ? '7' : (unsigned long)SIM_KEYCODE_UPLEFT);      break;
				case SDLK_KP_8:       np = true; code = (numlock ? '8' : (unsigned long)SIM_KEYCODE_UP);          break;
				case SDLK_KP_9:       np = true; code = (numlock ? '9' : (unsigned long)SIM_KEYCODE_UPRIGHT);     break;
				case SDLK_KP_ENTER:   code = SIM_KEYCODE_ENTER;      break;
				case SDLK_LEFT:       code = SIM_KEYCODE_LEFT;       break;
				case SDLK_PAGEDOWN:   code = '<';                    break;
				case SDLK_PAGEUP:     code = '>';                    break;
				case SDLK_RIGHT:      code = SIM_KEYCODE_RIGHT;      break;
				case SDLK_UP:         code = SIM_KEYCODE_UP;         break;
				case SDLK_PAUSE:      code = SIM_KEYCODE_PAUSE;      break;
				case SDLK_SCROLLLOCK: code = SIM_KEYCODE_SCROLLLOCK; break;
				default:
					/* Ordinary characters arrive through text input, so only
					 * CTRL-letter has to be synthesised here. SDLK_A is the
					 * lowercase 'a' keycode in SDL3, exactly as SDLK_a was in
					 * SDL2, so the range test is unchanged. */
					if(  (sys_event.key_mod & SIM_KEYMOD_CTRL)  &&  SDLK_A <= sym  &&  sym <= SDLK_Z  ) {
						code = sym & 31;
					}
					else {
						code = 0;
					}
					break;
			}

			ignore_previous_number = (np  &&  key_numlock);
			sys_event.type = SIM_KEYBOARD;
			sys_event.code = code;
			break;
		}

		case SDL_EVENT_KEY_UP:
			// A released key carries no code, but the event still has to be
			// reported, exactly as simsys_s2 does: an EVENT_NONE here would end
			// the event drain loop of simwin one iteration early.
			sys_event.type = SIM_KEYBOARD;
			sys_event.code = 0;
			break;

		case SDL_EVENT_TEXT_INPUT: {
			/* SDL2->SDL3: the text is a const char* owned by SDL rather than a
			 * fixed array inside the event, and SDL_TEXTINPUTEVENT_TEXT_SIZE no
			 * longer exists, so the copy below is bounded explicitly. */
			const utf8 *const in = (const utf8 *)event.text.text;
			if(  !in  ||  !in[0]  ) {
				sys_event.type = SIM_IGNORE_EVENT;
				break;
			}

			size_t      in_pos = 0;
			const utf32 uc     = utf8_decoder_t::decode( in, in_pos );

			if(  in[in_pos] == 0  ) {
				// single character
				if(  ignore_previous_number  ) {
					// the key event already delivered this digit
					ignore_previous_number = false;
					break;
				}
				sys_event.type = SIM_KEYBOARD;
				sys_event.code = (unsigned long)uc;
			}
			else {
				// string
				// Not min(): it takes ints, so both size_t operands would be
				// truncated. MSVC warns about exactly that (C4267).
				const size_t room = lengthof( textinput ) - 1;
				const size_t len  = strlen( (const char *)in );
				const size_t n    = len < room ? len : room;
				memcpy( textinput, in, n );
				textinput[n] = 0;
				sys_event.type = SIM_STRING;
				sys_event.ptr  = (void *)textinput;
			}

			sys_event.key_mod = ModifierKeys();
			// committed text ends any composition that led to it
			composition_is_underway = false;
			break;
		}

		case SDL_EVENT_TEXT_EDITING: {
			/* The preedit string of an IME. It is not a Simutrans event: the
			 * focused text field is told directly, exactly as simsys_s2 does,
			 * and sys_event is deliberately left alone so this poll yields
			 * EVENT_NONE - which is also what simsys_s2 produces here.
			 *
			 * SDL2->SDL3: event.edit.text was a fixed char[32] inside the event
			 * and is now a const char* owned by SDL with no length limit, so the
			 * copy has to be bounded. */
			const char *const in = event.edit.text;

			size_t len = 0;
			if(  in  ) {
				const size_t room = lengthof( textinput ) - 1;
				len = strlen( in );
				if(  len > room  ) {
					/* Never cut a UTF-8 sequence in half: back up to the last
					 * boundary at or before the limit. */
					len = room;
					while(  len > 0  &&  (((const unsigned char *)in)[len] & 0xC0) == 0x80  ) {
						len--;
					}
				}
				memcpy( textinput, in, len );
			}
			textinput[len] = 0;

			/* SDL reports the highlighted part of the preedit in CHARACTERS,
			 * gui_textinput_t wants BYTES. simsys_s2 walks the string to convert;
			 * the walk is over our bounded copy rather than SDL's string, so a
			 * truncated preedit can never produce an offset past its own end.
			 *
			 * SDL2->SDL3: start and length are documented as "-1 if not set",
			 * which SDL2 never produced. Not set means no highlighted target,
			 * which is what a zero length says. */
			const int edit_start  = event.edit.start  < 0 ? 0 : event.edit.start;
			const int edit_length = event.edit.length < 0 ? 0 : event.edit.length;

			size_t start = 0;
			int    i     = 0;
			for(  ; i < edit_start  &&  textinput[start];  ++i  ) {
				start = utf8_get_next_char( textinput, start );
			}
			size_t end = start;
			for(  ; i < edit_start + edit_length  &&  textinput[end];  ++i  ) {
				end = utf8_get_next_char( textinput, end );
			}

			if(  gui_component_t *c = win_get_focus()  ) {
				if(  gui_textinput_t *tinp = dynamic_cast<gui_textinput_t *>( c )  ) {
					tinp->set_composition_status( textinput, (int)start, (int)(end - start) );
				}
			}

			/* An empty preedit means the composition is over, committed or
			 * cancelled. simsys_s2 writes false for that case and then true
			 * unconditionally two lines later, so its false never survives;
			 * one assignment says the same thing without the dead store.
			 * Observably identical either way, because the swallow above also
			 * requires the field to still hold a pending string. */
			composition_is_underway = (textinput[0] != 0);
			break;
		}

		default:
			sys_event.type = SIM_IGNORE_EVENT;
			sys_event.code = 0;
			break;
	}
}


void GetEvents()
{
	internal_GetEvents();
}


/* ------------------------------------------------------------- text input */

void dr_start_textinput()
{
	if(  env_t::hide_keyboard  &&  window  ) {
		// SDL2->SDL3: text input is started per window.
		SDL_StartTextInput( window );
		DBG_MESSAGE("dr_start_textinput(SDL3)", "");
	}
}


void dr_stop_textinput()
{
	if(  window  ) {
		if(  env_t::hide_keyboard  ) {
			SDL_StopTextInput( window );
			DBG_MESSAGE("dr_stop_textinput(SDL3)", "");
		}
		else {
			SDL_SetEventEnabled( SDL_EVENT_TEXT_INPUT, true );
		}
	}
}


void dr_notify_input_pos(scr_coord pos)
{
	/* SDL2->SDL3: SDL_SetTextInputRect became SDL_SetTextInputArea, which is
	 * per window and takes the cursor offset within the area as well. */
	const SDL_Rect rect = { TEX_TO_SCREEN_X(pos.x), TEX_TO_SCREEN_Y(pos.y + LINESPACE), 1, 1 };
	if(  window  ) {
		SDL_SetTextInputArea( window, &rect, 0 );
	}
}


/* ----------------------------------------------------------------- locale */

const char *dr_get_locale()
{
	/* SDL2->SDL3: SDL_GetPreferredLocales returns an owned array plus a count.
	 * The array is a single allocation, so one SDL_free releases all of it. */
	static char LanguageCode[5] = "";

	int          count   = 0;
	SDL_Locale **locales = SDL_GetPreferredLocales( &count );
	if(  !locales  ) {
		return NULL;
	}

	const char *result = NULL;
	if(  count > 0  &&  locales[0]->language  ) {
		strncpy( LanguageCode, locales[0]->language, 2 );
		LanguageCode[2] = 0;
		DBG_MESSAGE("dr_get_locale(SDL3)", "%2s", LanguageCode);
		result = LanguageCode;
	}

	SDL_free( locales );
	return result;
}


/* ------------------------------------------------------------- fullscreen */

bool dr_has_fullscreen()
{
	/* SDL3 can do real exclusive fullscreen, but the contract Simutrans relies
	 * on is the borderless one that simsys_s2 provides. Reporting false keeps
	 * the observable behaviour identical instead of changing it here. */
	return false;
}


sint16 dr_get_fullscreen()
{
	return fullscreen ? BORDERLESS : WINDOWED;
}


sint16 dr_toggle_borderless()
{
	/* SDL2->SDL3: SDL_SetWindowFullscreen takes a bool. Without an explicit
	 * fullscreen mode set on the window, true means borderless desktop
	 * fullscreen, which is what SDL_WINDOW_FULLSCREEN_DESKTOP meant in SDL2. */
	if(  fullscreen  ) {
		SDL_SetWindowFullscreen( window, false );
		SDL_SetWindowPosition( window, 10, 10 );
		fullscreen = WINDOWED;
	}
	else {
		SDL_SetWindowPosition( window, 0, 0 );
		SDL_SetWindowFullscreen( window, true );
		fullscreen = BORDERLESS;
	}
	return fullscreen;
}


sint16 dr_suspend_fullscreen()
{
	const sint16 was_fullscreen = fullscreen;

	if(  fullscreen  ) {
		SDL_SetWindowFullscreen( window, false );
		fullscreen = WINDOWED;
	}
	SDL_MinimizeWindow( window );

	return was_fullscreen;
}


void dr_restore_fullscreen(sint16 was_fullscreen)
{
	SDL_RestoreWindow( window );
	if(  was_fullscreen  ) {
		SDL_SetWindowFullscreen( window, true );
		fullscreen = BORDERLESS;
	}
}


/* ----------------------------------------------------------------- timers */

uint32 dr_time()
{
	// SDL2->SDL3: SDL_GetTicks returns 64 bits. The truncation to 32 bits is
	// deliberate: it reproduces exactly what SDL2 returned.
	return (uint32)SDL_GetTicks();
}


void dr_sleep(uint32 msec)
{
	SDL_Delay( msec );
}


/* ------------------------------------------------------------------ entry */

/* Unlike SDL2, SDL3 does not redefine main: SDL_main.h is deliberately not
 * included by SDL.h, and this file does not include it. So there is no macro to
 * undefine here, and the entry points below are the real ones.
 *
 * Android is the exception, and it is not optional there. The process is started
 * from Java, so the entry point is outside this binary: SDLActivity looks up a
 * symbol called SDL_main in the shared library and refuses to start without it -
 * "Couldn't find function SDL_main", then the activity closes again. SDL2 got
 * this by accident, because its SDL.h drags in SDL_main.h, which renames main;
 * SDL3 asks to be told. Restricted to Android on purpose: on Windows SDL3's
 * SDL_main.h would rename main as well and take over the WinMain arrangement
 * below, which is working and is not this cut's business. */
#ifdef __ANDROID__
#include <SDL3/SDL_main.h>
#endif

#ifdef _MSC_VER
// Needed for MS Visual C++ with /SUBSYSTEM:CONSOLE to work.
// If /SUBSYSTEM:WINDOWS this function is compiled but unreachable.
int main()
{
	return WinMain( NULL, NULL, NULL, NULL );
}
#endif


#ifdef _WIN32
int CALLBACK WinMain(HINSTANCE, HINSTANCE, LPSTR, int)
#else
int main(int argc, char **argv)
#endif
{
#ifdef _WIN32
	int    const argc = __argc;
	char** const argv = __argv;
#endif
	return sysmain( argc, argv );
}
