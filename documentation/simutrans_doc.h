/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

 /** @file simutrans_doc.h Just contains pages of exciting documentation */


/**
 * @mainpage Simutrans Code Documentation
 *
 *
 * License
 * =======
 *
 * Simutrans is licensed under the Artistic License version 1.0. The Artistic License 1.0 is an OSI-approved license which allows for use, distribution, modification, and distribution of modified versions, under the terms of the Artistic License 1.0. For the complete license text see LICENSE.txt.
 *
 * Simutrans paksets (which are necessary to run the game) have their own license, but no one is included alongside this code.
 *
 *
 *
 *
 * @section s_squirrel squirrel Scripting language
 * ------------------
 *
 * The scripts have to be written in squirrel. The manual can be found at <a href="http://squirrel-lang.org/">Squirrel main page</a>.
 * As squirrels like to crack nuts, understandably the script files get the extension '.nut'.
 *
 *
 * For more information see <a href="https://doc.simutrans-germany.com/Simutrans-Squirrel-API/index.html">Simutrans-Squirrel-API Documentation</a>.
 *
 */


/**
  * @defgroup squirrel-toolkit-api Squirrel toolkit interface
  *
  * The following methods create macro scripted tools.
  *
  *
  *
  */


/**
 * @page nls_ime_input Native language IME text input
 *
 * Simutrans is translated into many languages, but a translation alone does not make a language
 * usable. Languages such as Japanese and Chinese are typed through an Input Method Editor (IME):
 * the player types a phonetic or structural key sequence, and the IME turns it into the intended
 * characters. This page describes how the text input component handles IME composition, what
 * changed with SVN r12182, what was verified for that change, and which limitations remain open.
 *
 *
 * @section nls_ime_composition What an IME composition is
 *
 * While the player is still typing, the IME shows a provisional string - usually underlined -
 * called the <em>composition</em> or <em>pre-edit</em>. That string is not part of the field's
 * content yet: the player can extend it, convert it, pick among candidate readings, or cancel it.
 * Only on confirmation is the result <em>committed</em> and appended to the field's actual text;
 * cancelling leaves the committed text untouched.
 *
 * The composition is therefore temporary, visible state that the application itself must draw
 * inside the text field at the caret - the IME only supplies the string. In Simutrans both display
 * backends feed the same text component: the Windows GDI backend forwards WM_IME_COMPOSITION
 * events, the SDL2 backend forwards SDL_TEXTEDITING events, and gui_textinput_t draws committed
 * text and composition in one pass. The committed text is stored as UTF-8, separately from the
 * composition state.
 *
 *
 * @section nls_ime_r12182 The defect fixed in r12182
 *
 * When a text field contained no committed text, an active IME composition was not drawn at all.
 * The data path was always correct - every composition event and every committed character
 * arrived, nothing was lost or corrupted - but the drawing pass of
 * gui_textinput_t::display_with_cursor() was guarded by the presence of the display text pointer,
 * which is NULL when the field holds neither committed text nor a placeholder. An empty field
 * therefore skipped the entire pass, composition included. In practice: clear a name field, start
 * typing Japanese or Chinese, and nothing is visible until the composition is committed.
 *
 * From r12182 the pass runs with an empty display string when a composition is active (and the
 * caret pixel offset is no longer derived from a NULL buffer), so the pre-edit is drawn in an
 * empty field exactly as in a non-empty one. The committed text buffer is never modified by the
 * change; it affects drawing only.
 *
 * A typical Japanese input sequence, before and after:
 * @verbatim
   typed:  n i h o n        pre-edit:  にほん     committed:  日本

   before r12182:  empty field -> pre-edit invisible, committed text appears only at the end
   from   r12182:  empty field -> pre-edit visible from the first keystroke
   @endverbatim
 *
 *
 * @section nls_ime_verified What was verified for r12182
 *
 * Verified on Windows with both display backends (GDI and SDL2), each measured separately, using
 * real native IMEs:
 *
 * - Japanese (Microsoft IME), Simplified Chinese (Microsoft Pinyin) and Traditional Chinese
 *   (Microsoft Bopomofo) compositions are visible in empty fields.
 * - A composition commits exactly once and cancelling restores the field unchanged.
 * - Committed UTF-8 bytes are identical before and after the change.
 * - Latin and Unicode editing behaviour is unchanged; deleting a multi-byte character removes
 *   exactly that character.
 * - An overlong composition is clipped at the field border.
 * - The full automated test suite passes on both backends, before and after the change.
 *
 * Korean was validated separately, after this page was first written: native Hangul composition
 * (Microsoft Korean IME) is visible in empty and non-empty fields on both backends, Backspace
 * during composition steps through the syllable jamo by jamo exactly as in a native Windows edit
 * control, committed UTF-8 is byte-exact, and clipboard transfer and savegame persistence of
 * Hangul text were verified. One property of the Microsoft Korean IME is worth knowing when
 * testing: it has no cancel gesture - Escape commits the pending syllable and is then forwarded
 * to the application (closing the topmost window, for example), which matches the behaviour of
 * native Windows edit controls and is not a Simutrans defect.
 *
 *
 * @section nls_ime_open Known limitations still open
 *
 * r12182 fixes one visibility defect; it does not complete native-language input support. Known
 * independent findings, by behaviour: the SDL2 backend does not show the IME's candidate list
 * window; with GDI an in-progress composition can be lost on focus change and a stale pre-edit
 * can occasionally linger; the candidate window is not always positioned at the caret; the IME
 * can stay active over the map where it interferes with keyboard shortcuts; and the default font
 * configuration does not guarantee CJK glyphs. None of these is addressed by r12182.
 *
 * Reports from native speakers are welcome in the Simutrans forum. A useful report names the
 * language and IME, the operating system and (if known) the backend, the exact text entered, the
 * expected and the actual result, and whether the problem concerns input, display, editing,
 * saving/loading or translation wording.
 */


/**
 * @page sdl3_backend SDL3 display backend
 *
 * Simutrans can be built against SDL3 instead of SDL2. The SDL3 backend is a platform layer only:
 * it creates the window, translates events and presents the finished frame, while the existing
 * software renderer draws that frame exactly as it does for every other backend. Nothing about how
 * the game looks is changed by choosing it.
 *
 * The backend ships as a <em>beta</em>. SDL2 remains the default and is not affected by any of
 * this. This page describes what the SDL3 backend covers, how to build and select it, how its
 * behaviour differs from SDL2 where SDL3 itself changed, and what has not been verified.
 *
 *
 * @section sdl3_availability Backend availability
 *
 * Simutrans offers four backends, and SDL3 is one selectable choice among them:
 *
 * - <b>sdl2</b> - the default, unchanged.
 * - <b>sdl3</b> - this backend, beta.
 * - <b>gdi</b> - the Windows GDI backend, unchanged.
 * - <b>none</b> (called <b>posix</b> in the GNU Makefile) - the headless server build, unchanged.
 *
 * SDL3 does not replace SDL2 and does not deprecate it. Choosing SDL3 is opt-in: the build system
 * lists it after the other backends, and the default backend is the first entry of that list, so
 * the SDL3 backend can only be reached by asking for it by name. A machine without SDL3 installed
 * simply does not offer the backend.
 *
 * The running program identifies the backend in the message it writes at startup, which is
 * therefore present in every simu.log attached to a bug report:
 *
 * @verbatim
   Message: dr_os_init(SDL3):  SDL 3.4.14 (BETA backend), video driver: windows
   @endverbatim
 *
 *
 * @section sdl3_building Building with SDL3
 *
 * SDL 3.2.0 or later is required. One behaviour depends on a slightly newer SDL: discrete mouse
 * wheel notches use SDL_MouseWheelEvent::integer_y, which exists from SDL 3.2.12, and an older
 * SDL3 falls back to the sign of the high-resolution value.
 *
 * The backend is selected at <em>compile time</em>. There is no runtime switch and no
 * configuration file entry: a binary is built for one backend.
 *
 * CMake:
 * @verbatim
   cmake -B build -DSIMUTRANS_BACKEND=sdl3
   cmake --build build
   @endverbatim
 *
 * GNU Makefile, through config.default:
 * @verbatim
   BACKEND = sdl3
   @endverbatim
 *
 * Visual Studio: build the <em>Simutrans-SDL3</em> project in Simutrans.sln.
 *
 * SDL3 is discovered with find_package(SDL3 CONFIG) under MSVC and with pkg-config elsewhere; the
 * GNU Makefile uses pkg-config sdl3, falling back to plain -lSDL3, and to the SDL3 framework on
 * macOS. Unlike SDL2 there is no SDL3main to link and no -Dmain=SDL_main: SDL3 only redefines main
 * when SDL_main.h is included, and the backend does not include it except on Android.
 *
 * Asking for a backend that is not available is an error rather than a silent substitution. An
 * unknown or misspelled value - SDL3 with capitals, sdl33, or an empty string - stops the CMake
 * configuration with a message naming the value received and the values accepted. Asking for sdl3
 * on a machine without SDL3 stops with a message naming the package to install.
 *
 *
 * @section sdl3_input Input and events
 *
 * The SDL3 backend translates SDL3 events into the same internal events the other backends
 * produce, so the rest of the program cannot tell which backend delivered them. Where SDL3 changed
 * an interface, the backend restores the established behaviour rather than adopting the new one.
 *
 * <b>Keyboard and text.</b> Key events, modifiers and committed text behave as with SDL2. Text
 * arrives as UTF-8.
 *
 * <b>Composition and IME.</b> SDL_EVENT_TEXT_EDITING is forwarded to the text component rather
 * than being received and discarded, and the composition state is tracked, so an input method's
 * pre-edit string is visible while it is being typed. The guard that swallows a keystroke during
 * composition requires both an active composition flag and a non-empty composition string, so an
 * empty pre-edit cannot consume a keystroke.
 *
 * <b>Mouse.</b> Buttons, motion and dragging behave as with SDL2.
 *
 * <b>Mouse wheel.</b> SDL3 changed what wheel.y means while keeping the name: in SDL2 it carried
 * whole notches and the high-resolution amount was separate, whereas in SDL3 it carries the
 * high-resolution amount and the notches moved to integer_y. The backend reads integer_y and emits
 * one zoom step per event regardless of the notch count, which is what the SDL2 backend does. A
 * precision touchpad therefore zooms at the same rate as a mouse wheel rather than several times
 * faster.
 *
 * <b>Touch and gestures.</b> SDL3 removed the gesture recogniser that SDL2 provided, so the pinch
 * gesture is reconstructed from the raw finger events by tracking the fingers and the distance
 * between them. SDL_EVENT_FINGER_CANCELED, which has no SDL2 counterpart, ends a gesture without
 * leaving a stray click behind.
 *
 *
 * @section sdl3_density High-DPI and pixel density
 *
 * Two coordinate systems matter on a high-density display. <em>Window coordinates</em> are the
 * sizes and positions the desktop works in; <em>pixels</em> are the physical dots in the back
 * buffer. On a display scaled to 200 % a window 1280 units wide holds 2560 pixels. Mixing the two
 * silently is the usual source of a picture at the wrong size, and the SDL3 backend converts
 * explicitly wherever the two meet.
 *
 * High pixel density is requested rather than assumed. SDL3 renamed the flag that asks for it from
 * SDL_WINDOW_ALLOW_HIGHDPI to SDL_WINDOW_HIGH_PIXEL_DENSITY and kept it opt-in; without it a dense
 * panel hands the game a small logical size and the system stretches the result back up.
 *
 * SDL3 reports no dpi figure at all, only a unitless content scale, and what that scale is
 * measured against differs by platform: the desktop platforms define 1.0 against 96 dpi while
 * Android derives it from the display density, which is defined against 160. Both bases are
 * applied where they belong.
 *
 * An automatic scale - the scale Simutrans chooses for itself - follows the display while the game
 * runs. When the display scale changes, or the window is moved to a display with a different
 * scale, the automatic scale is recomputed from the window's own display rather than from whichever
 * display the system calls primary, and the minimum-height limit that bounds it is compared in
 * pixels rather than in window coordinates. A scale the player set explicitly is never recomputed:
 * a chosen percentage survives a display change.
 *
 *
 * @section sdl3_window Window, fullscreen and displays
 *
 * SDL3 split the single SDL2 size-changed event into two: one carrying the window size in window
 * coordinates and one carrying the size of the back buffer in pixels. Both are handled, and where
 * they coincide the resulting resize is de-duplicated so that one resize produces one internal
 * resize event. Closing the last window produces both a close request and a quit in SDL3, as it
 * does in SDL2, and both are handled without producing two quits.
 *
 * Entering fullscreen keeps the window on the display that already holds it, and leaving
 * fullscreen restores the position the player chose. Display arrival, removal, movement,
 * reorientation and scale changes are written to the log with the display's identifier, name,
 * bounds and content scale, so a report that begins "it broke when I connected the second screen"
 * can be acted on.
 *
 *
 * @section sdl3_sound Sound
 *
 * Sound effects are played through SDL3. The application-side format is fixed at 22050 Hz mono
 * 16-bit, the same format the SDL2 backend asks for, and SDL3 converts to whatever the device
 * wants. Music is not an SDL responsibility for either backend and keeps the per-platform routine
 * it already had, so FluidSynth is available for SDL3 on the same terms as for SDL2 and GDI.
 *
 *
 * @section sdl3_clipboard Clipboard
 *
 * Copying and pasting text is available. Which implementation is compiled depends on the platform
 * and the build system: builds that are not for Windows use the SDL3 clipboard, while a Windows
 * build configured with CMake uses the Win32 clipboard for every backend. A Windows build produced
 * from the GNU Makefile with BACKEND=sdl3 uses the SDL3 clipboard instead.
 *
 *
 * @section sdl3_platforms Platform notes
 *
 * <b>Windows.</b> Buildable with MSVC through the Simutrans-SDL3 project and with MinGW through the
 * GNU Makefile. The GDI backend is unaffected and remains available.
 *
 * <b>Linux and other POSIX systems.</b> Buildable with CMake or the GNU Makefile against a system
 * SDL3 found through pkg-config.
 *
 * <b>Android.</b> Supported. SDL3 requires the application to provide its entry point explicitly,
 * so SDL_main.h is included on Android only; the six application lifecycle events are delivered to
 * the event watchers; and SDL comes from the Android project's own SDL3 subdirectory rather than
 * from pkg-config. The automatic scale is capped so that the drawn area is at most 1280 pixels
 * across, because most Android devices are not fast enough for more.
 *
 * <b>macOS.</b> A build path exists - the GNU Makefile locates the SDL3 framework, and CMake finds
 * SDL3 through pkg-config - but the SDL3 backend has not been built or run on macOS as part of this
 * work, and no claim is made about it.
 *
 *
 * @section sdl3_architecture Notes for developers
 *
 * The backend is a platform layer, not a renderer. simgraph16 draws into a CPU framebuffer exactly
 * as it does for the SDL2 backend, and the backend's job is to create the window, translate events
 * into sys_event codes, convert between window coordinates and pixels, and present the framebuffer.
 * The boundary is the same one the other backends sit behind, so a change confined to the backend
 * cannot affect what is drawn.
 *
 * Three files implement it:
 *
 * - src/simutrans/sys/simsys_s3.cc - window, events, coordinates, density, fullscreen, scaling.
 * - src/simutrans/sys/clipboard_s3.cc - clipboard.
 * - src/simutrans/sound/sdl3_sound.cc - sound effects.
 *
 * None of them is compiled by the SDL2, GDI or headless builds, which is why a change to the SDL3
 * backend cannot alter another backend's binary.
 *
 * When working on the backend, the useful comparison is against src/simutrans/sys/simsys_s2.cc
 * rather than against the SDL3 documentation: several of the differences that matter are places
 * where SDL3 renamed or re-specified something and the established Simutrans behaviour has to be
 * preserved on top of it.
 *
 * Official SDL documentation is at <a href="https://wiki.libsdl.org/SDL3/">wiki.libsdl.org</a>.
 *
 *
 * @section sdl3_verification Testing and validation
 *
 * The SDL3 backend is developed and tested alongside the existing SDL2, GDI and headless paths,
 * and each behaviour described above was compared against the SDL2 backend rather than assumed.
 *
 * Input parity was measured with real input rather than synthetic events: keystrokes through the
 * Windows input queue produced the same codes in the same order on both backends, covering ASCII
 * and two- and three-byte UTF-8 including CJK; touch injected through the Windows input stack
 * produced the same pinch behaviour on both. Sound was compared against the SDL2 backend through
 * SDL's disk driver. Android sizing was measured on an emulator against an SDL2 build until the
 * drawn content had an identical bounding box in both axes. Display and scaling behaviour was
 * measured on a compositor driving outputs of different sizes and scales, with the game running
 * across the changes.
 *
 *
 * @section sdl3_limitations Known limitations
 *
 * - The backend is a beta. SDL2 remains the default and the recommended choice for players who do
 *   not specifically want SDL3.
 * - Multi-monitor behaviour has been validated on virtual compositor outputs only. It has not been
 *   tested on physical multi-monitor hardware.
 * - macOS has a build path but has not been built or run as part of this work.
 * - Display arrival, removal and reconfiguration are logged but not otherwise acted on.
 * - Discrete wheel notches require SDL 3.2.12 or later; on an older SDL3 the backend falls back to
 *   the sign of the high-resolution wheel value.
 * - The limitations of native-language input described in @ref nls_ime_input are independent of the
 *   backend and are not changed by it.
 */
