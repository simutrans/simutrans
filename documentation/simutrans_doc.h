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
