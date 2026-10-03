/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#ifndef DATAOBJ_LOCAL_PREFERENCES_H
#define DATAOBJ_LOCAL_PREFERENCES_H


#include <string>


/**
 * Preferences of this user on this machine that are never part of a game, a savegame or a network game, kept in
 * preferences.tab in the user directory. Unlike settings.xml it does not depend on the savegame version: a line is
 * "key=value" in UTF-8, keys this version does not know are kept when the file is written again, and a key that is
 * missing just means "no preference".
 *
 * The file is owned by Simutrans and rewritten as a whole (via a temporary file and a rename); settings meant to be
 * edited by hand belong into simuconf.tab, which Simutrans never writes.
 */
class local_preferences_t
{
public:
	/// reads the file in the user directory; a missing file is no error
	static void load();

	/// writes the file in the user directory if something changed since load(); false on failure (with a warning)
	static bool save();

	/// @return whether @p key has a value, even an empty one
	static bool has(const char *key);

	/// @return the value of @p key, or @p def if it has none
	static std::string get(const char *key, const char *def = "");

	/// @return the value of @p key as a number between @p min_value and @p max_value, or @p def
	static int get_int(const char *key, int def, int min_value, int max_value);

	/// sets @p key to @p value; false (with a warning) if the value cannot be stored, e.g. it holds a line break
	static bool set(const char *key, const std::string &value);

	/// forgets the value of @p key
	static void unset(const char *key);

	/// the parts of load() and save() for a given file, so they can also be used on other files
	static bool read_file(const std::string &filename);
	static bool write_file(const std::string &filename);
};

#endif
