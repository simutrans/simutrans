/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

/** @file squirrel_32_en.h Squirrel 3.2 runtime update - English canonical documentation */

/**
 * @page squirrel32_en Squirrel 3.2 runtime update
 *
 * <b>English (canonical)</b> | @ref squirrel32_es "Español"
 *
 * @tableofcontents
 *
 * @section sq32_en_overview Overview
 *
 * Simutrans embeds the Squirrel language to run scripted scenarios and scripted AI
 * players. The embedded Squirrel runtime has been updated to upstream Squirrel v3.2.
 *
 * This is an update of the <em>language runtime</em>. It is not a redesign of the
 * Simutrans Script API. Scripts do not need to be rewritten for it.
 *
 * @section sq32_en_changed What changed
 *
 * - The vendored Squirrel sources were updated to upstream v3.2.
 * - Squirrel gained an inline syntax for binding an environment to a function, in
 *   addition to the existing @c bindenv method. See @ref sq32_en_bindenv.
 * - Tables gained a @c map method in the Squirrel standard library. See
 *   @ref sq32_en_tablemap.
 * - Upstream changed the string hash function. This changes the order in which the
 *   entries of a table are visited. See @ref sq32_en_order. For existing, unmodified
 *   scripts, this is the main behavioural change that may be observable.
 *
 * @section sq32_en_unchanged What did not change
 *
 * - The Simutrans Script API - the classes and methods documented in this reference -
 *   is unchanged. No function was added, removed or renamed by the runtime update, and
 *   no parameter list or default-argument behaviour changed.
 * - The scenario and AI entry points are unchanged.
 * - The savegame format is unchanged.
 * - The way scripts are loaded, suspended and resumed is unchanged.
 *
 * @section sq32_en_provenance Runtime provenance
 *
 * The Squirrel sources shipped with Simutrans are a vendored copy of the upstream
 * project at <a href="https://github.com/albertodemichelis/squirrel">albertodemichelis/squirrel</a>.
 *
 * <table>
 * <tr><th>Previous vendored basis<td><tt>23a0620658714b996d20da3d4dd1a0dcf9b0bd98</tt>
 *     <td>a snapshot of the 3.1.x development line, dated 2021-09-16
 * <tr><th>New basis<td><tt>f92bc298784ceea459b12e2de33bdff672bfeb83</tt>
 *     <td>upstream release tag <tt>v3.2</tt>, dated 2022-02-10
 * </table>
 *
 * The previous snapshot was taken from the development line after the 3.1 release, so
 * it was neither an exact upstream 3.1 release nor a 3.2 one. Describing the update
 * simply as "3.1 to 3.2" would therefore be inaccurate.
 *
 * @section sq32_en_compat Compatibility
 *
 * The two scripted AI players shipped with Simutrans, @c sqai and @c sqai_rail, were
 * run against the new runtime and remained compatible. In the tested campaign they
 * preserved their logical connection state, continued making valid progress and produced
 * no script or runtime errors. Some scheduling and route-search choices may differ
 * because of table iteration order, as described below. Loading a savegame written by
 * the previous runtime was also tested and works.
 *
 * This is a statement about the scripts and paths that were covered by that test
 * campaign. It is not a guarantee that every possible script is unaffected. A script
 * that depends on table iteration order may behave differently - see the next section.
 *
 * @section sq32_en_order Table iteration order
 *
 * @warning Do not rely on the iteration order of Squirrel tables unless it is
 * explicitly documented by the API.
 *
 * Squirrel 3.2 changes the hash function used for string keys. Tables are hash
 * containers, so this changes the order in which @c foreach visits their entries.
 *
 * The consequence for a script is indirect but real. If a script iterates a table to
 * pick the next thing to work on, the new order may change:
 *
 * - which entry is examined first,
 * - the order in which work is scheduled,
 * - which candidate wins when several are equally good,
 * - and therefore which of several equally valid results the script arrives at.
 *
 * This is not corruption and it is not randomness. For the same input the runtime
 * behaves the same way every time, the script keeps its complete logical state, and
 * execution stays valid. What changes is a tie-break that was never guaranteed in the
 * first place.
 *
 * If a script needs a defined order, it must impose one - for example by collecting the
 * keys into an array and sorting it - rather than relying on the order a table happens
 * to produce.
 *
 * Arrays are not affected: they are ordered containers and their order is part of their
 * contract.
 *
 * @section sq32_en_savegames Savegame compatibility
 *
 * Savegames written by the previous runtime load correctly under Squirrel 3.2. This was
 * tested with the scripted AI players shipped with Simutrans. The same old-runtime save
 * was loaded repeatedly to confirm reproducibility. A state loaded under 3.2 was also
 * saved again and reloaded successfully. The scripts resumed with their persistent state
 * complete.
 *
 * The reverse direction - loading a savegame written by Squirrel 3.2 into an older
 * Simutrans build - was not part of this work and is not claimed.
 *
 * When a script's persistent state is written out again, the entries of a saved table
 * may appear in a different order than before. The saved state itself is unaffected:
 * it is restored by name, not by position.
 *
 * @section sq32_en_bindenv bindenv
 *
 * Binding an environment to a function is a feature of the Squirrel language, not a
 * Simutrans class or API registration.
 *
 * The existing method is unchanged and continues to work:
 *
 * @code
 * local env = { factor = 2 }
 * local scale = function(x) { return x * factor }
 * local bound = scale.bindenv(env)   // 'this' inside scale is now env
 * bound(21)                          // 42
 * @endcode
 *
 * Squirrel 3.2 adds an inline form. The environment is written in square brackets
 * between the function name and the parameter list:
 *
 * @code
 * local env = { factor = 2 }
 * local scale = function [env] (x) { return x * factor }
 * scale(21)                          // 42
 * @endcode
 *
 * The same bracket form is accepted for named functions, for local functions and for
 * class and table members, including @c constructor.
 *
 * Both forms produce a closure whose environment is the given table, class or instance.
 * The inline form is a convenience; it does not give access to anything the method form
 * did not already allow. Existing scripts need no change.
 *
 * @section sq32_en_tablemap table.map
 *
 * Squirrel 3.2 adds a @c map method to tables in the standard library. Arrays already
 * had one.
 *
 * The callback is called once per entry and receives the key and the value, with
 * @c this bound to the table:
 *
 * @code
 * local prices = { coal = 10, oil = 25 }
 * local labels = prices.map(function(key, value) {
 *     return key + "=" + value
 * })
 * @endcode
 *
 * Two properties are worth knowing:
 *
 * - @c table.map returns an <b>array</b> of the callback results, not a table. This
 *   differs from @c table.filter, which returns a table.
 * - The results appear in table iteration order, so the order of the returned array is
 *   subject to @ref sq32_en_order. Sort it if the order matters.
 *
 * @section sq32_en_authors Notes for AI and scenario authors
 *
 * - No change is required to keep an existing script working.
 * - Review any place where a table is iterated to make a choice. If the first match
 *   wins, or the last one does, decide whether that was intentional and make it
 *   explicit.
 * - Do not compare two runs by their logs. Two runs of the same script under different
 *   Simutrans versions may make different, equally valid choices.
 * - Prefer arrays where order carries meaning.
 *
 * @section sq32_en_limits Known scope limits
 *
 * - The compatibility statement covers the scripted AI players shipped with Simutrans
 *   and the savegame directions listed above. Third-party scripts were not tested.
 * - Loading a Squirrel 3.2 savegame into an older build is not claimed to work.
 * - The inline @c bindenv form is a new language feature, and @c table.map is a new
 *   standard-library feature. Scripts that use them will not run on older Simutrans
 *   versions.
 *
 * @section sq32_en_further Further reference
 *
 * - @ref changelog - the Script API changelog
 * - @ref pitfalls - common scripting pitfalls
 * - @ref page_sqstdlib - the Squirrel standard library functions available in Simutrans
 */
