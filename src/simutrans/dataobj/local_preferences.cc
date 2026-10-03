/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vector>
#ifdef _WIN32
#include <io.h>
#include <process.h>
#else
#include <unistd.h>
#endif

#include "local_preferences.h"
#include "environment.h"
#include "../simdebug.h"
#include "../sys/simsys.h"


#define PREFERENCES_FILE "preferences.tab"
#define HEADER "# Written by Simutrans: preferences of this user. Settings of your own belong into simuconf.tab."

// the file is tiny; anything bigger is not ours (and is kept as .bad instead of being read)
static const long MAX_FILE_SIZE = 1024*1024;
static const size_t MAX_KEY_LENGTH = 64;


namespace {

struct line_t
{
	std::string text;  ///< the whole line as read or to be written
	std::string key;   ///< empty if the line is no key=value pair
	std::string value;
	bool valid;        ///< a pair whose value can be used
};

std::vector<line_t> lines;
bool changed = false;
bool keep_old_file = false; ///< the file could not be read: keep it as .bad before writing a new one


/// whether @p s is well formed UTF-8 (no overlong forms, no surrogates, nothing above U+10FFFF)
bool is_utf8(const std::string &s)
{
	const unsigned char *p = (const unsigned char *)s.c_str(), *end = p + s.length();
	while(  p < end  ) {
		const unsigned char c = *p++;
		int more;
		unsigned long cp;
		if(  c < 0x80  ) { continue; }
		else if(  c >= 0xC2  &&  c <= 0xDF  ) { more = 1; cp = c & 0x1F; }
		else if(  c >= 0xE0  &&  c <= 0xEF  ) { more = 2; cp = c & 0x0F; }
		else if(  c >= 0xF0  &&  c <= 0xF4  ) { more = 3; cp = c & 0x07; }
		else { return false; }
		if(  end - p < more  ) {
			return false;
		}
		for(  int i = 0;  i < more;  i++  ) {
			if(  (p[i] & 0xC0) != 0x80  ) {
				return false;
			}
			cp = (cp << 6) | (p[i] & 0x3F);
		}
		p += more;
		if(  (more == 2  &&  (cp < 0x800  ||  (cp >= 0xD800  &&  cp <= 0xDFFF)))  ||  (more == 3  &&  (cp < 0x10000  ||  cp > 0x10FFFF))  ) {
			return false;
		}
	}
	return true;
}


std::string trim(const std::string &s)
{
	const size_t b = s.find_first_not_of(" \t");
	if(  b == std::string::npos  ) {
		return "";
	}
	return s.substr(b, s.find_last_not_of(" \t") - b + 1);
}


bool is_key(const std::string &k)
{
	if(  k.empty()  ||  k.length() > MAX_KEY_LENGTH  ) {
		return false;
	}
	for(  char c : k  ) {
		if(  !((c >= 'a'  &&  c <= 'z')  ||  (c >= '0'  &&  c <= '9')  ||  c == '_')  ) {
			return false;
		}
	}
	return true;
}


line_t *find(const char *key)
{
	for(  line_t &l : lines  ) {
		if(  l.valid  &&  l.key == key  ) {
			return &l;
		}
	}
	return NULL;
}


std::string file_name()
{
	return std::string(env_t::user_dir) + PREFERENCES_FILE;
}

}


bool local_preferences_t::read_file(const std::string &filename)
{
	lines.clear();
	changed = false;
	keep_old_file = false;

	FILE *f = dr_fopen(filename.c_str(), "rb");
	for(  int i = 0;  !f  &&  errno != ENOENT  &&  i < 10;  i++  ) {
		// another Simutrans may be replacing it just now
		dr_sleep(10);
		f = dr_fopen(filename.c_str(), "rb");
	}
	if(  !f  ) {
		// none yet
		return false;
	}
	fseek(f, 0, SEEK_END);
	const long size = ftell(f);
	fseek(f, 0, SEEK_SET);
	if(  size < 0  ||  size > MAX_FILE_SIZE  ) {
		fclose(f);
		dbg->warning("local_preferences_t::read_file()", "'%s' is too big (%ld bytes) and is not used", filename.c_str(), size);
		keep_old_file = true;
		return false;
	}
	std::string content(size, '\0');
	const size_t got = size ? fread(&content[0], 1, size, f) : 0;
	fclose(f);
	content.resize(got);
	if(  content.compare(0, 3, "\xEF\xBB\xBF") == 0  ) {
		content.erase(0, 3);
	}

	std::vector<std::string> duplicates;
	size_t start = 0;
	int line_number = 0;
	while(  start < content.length()  ) {
		size_t end = content.find('\n', start);
		if(  end == std::string::npos  ) {
			end = content.length();
		}
		line_t l;
		l.text = content.substr(start, end - start);
		if(  !l.text.empty()  &&  l.text.back() == '\r'  ) {
			l.text.pop_back();
		}
		l.valid = false;
		start = end + 1;
		line_number++;

		if(  l.text.empty()  ||  l.text[0] == '#'  ) {
			if(  l.text != HEADER  ) {
				lines.push_back(l);
			}
			continue;
		}
		const size_t eq = l.text.find('=');
		std::string key = eq == std::string::npos ? "" : trim(l.text.substr(0, eq));
		for(  char &c : key  ) {
			if(  c >= 'A'  &&  c <= 'Z'  ) {
				c += 'a' - 'A';
			}
		}
		if(  !is_key(key)  ) {
			dbg->warning("local_preferences_t::read_file()", "Line %d of '%s' is not understood and is ignored", line_number, filename.c_str());
		}
		else {
			l.key = key;
			l.value = trim(l.text.substr(eq + 1));
			if(  !is_utf8(l.value)  ) {
				dbg->warning("local_preferences_t::read_file()", "The value of '%s' in '%s' is not UTF-8 and is ignored", key.c_str(), filename.c_str());
			}
			else if(  find(key.c_str())  ) {
				duplicates.push_back(key);
			}
			else {
				l.valid = true;
			}
		}
		// kept as it is, so a line this version does not understand is not lost when the file is written again
		lines.push_back(l);
	}
	for(  const std::string &key : duplicates  ) {
		dbg->warning("local_preferences_t::read_file()", "'%s' appears more than once in '%s', the first value is used", key.c_str(), filename.c_str());
	}
	return true;
}


bool local_preferences_t::write_file(const std::string &filename)
{
	std::string content = HEADER "\n";
	for(  const line_t &l : lines  ) {
		content += l.text;
		content += '\n';
	}

	// never truncate the only copy: write a new file and replace the old one by renaming;
	// the name is per process, so two Simutrans writing at once never rename each other's half written file
#ifdef _WIN32
	const std::string temp = filename + ".tmp" + std::to_string(_getpid());
#else
	const std::string temp = filename + ".tmp" + std::to_string(getpid());
#endif
	FILE *f = dr_fopen(temp.c_str(), "wb");
	if(  !f  ) {
		dbg->warning("local_preferences_t::write_file()", "Cannot write '%s'", temp.c_str());
		return false;
	}
	bool ok = fwrite(content.c_str(), 1, content.length(), f) == content.length()  &&  fflush(f) == 0;
#ifdef _WIN32
	ok = ok  &&  _commit(_fileno(f)) == 0;
#else
	ok = ok  &&  fsync(fileno(f)) == 0;
#endif
	ok = (fclose(f) == 0)  &&  ok;
	if(  !ok  ) {
		dbg->warning("local_preferences_t::write_file()", "Cannot write '%s'", temp.c_str());
		dr_remove(temp.c_str());
		return false;
	}
	if(  keep_old_file  ) {
		const std::string bad = filename + ".bad";
		dr_rename(filename.c_str(), bad.c_str());
		keep_old_file = false;
	}
	bool renamed = false;
	for(  int i = 0;  !renamed  &&  i < 10;  i++  ) {
		if(  i  ) {
			// a virus scanner or another Simutrans may hold the file for a moment
			dr_sleep(10);
		}
#ifdef _WIN32
		renamed = dr_rename(temp.c_str(), filename.c_str()) == 0;
#else
		// rename() replaces the old file atomically (dr_rename() would remove it first)
		renamed = rename(temp.c_str(), filename.c_str()) == 0;
#endif
	}
	if(  !renamed  ) {
		dbg->warning("local_preferences_t::write_file()", "Cannot replace '%s'", filename.c_str());
		dr_remove(temp.c_str());
		return false;
	}
	return true;
}


void local_preferences_t::load()
{
	read_file(file_name());
}


bool local_preferences_t::save()
{
	if(  !changed  ) {
		return true;
	}
	if(  write_file(file_name())  ) {
		changed = false;
		return true;
	}
	return false;
}


bool local_preferences_t::has(const char *key)
{
	return find(key) != NULL;
}


std::string local_preferences_t::get(const char *key, const char *def)
{
	const line_t *l = find(key);
	return l ? l->value : def;
}


int local_preferences_t::get_int(const char *key, int def, int min_value, int max_value)
{
	const line_t *l = find(key);
	if(  !l  ) {
		return def;
	}
	char *end;
	const long v = strtol(l->value.c_str(), &end, 10);
	if(  l->value.empty()  ||  *end != 0  ||  v < min_value  ||  v > max_value  ) {
		dbg->warning("local_preferences_t::get_int()", "'%s' is not a number between %d and %d, using %d", key, min_value, max_value, def);
		return def;
	}
	return (int)v;
}


bool local_preferences_t::set(const char *key, const std::string &value)
{
	// a line break would end the line, surrounding blanks would be trimmed when reading
	if(  !is_key(key)  ||  value.find_first_of("\r\n") != std::string::npos  ||  value != trim(value)  ||  !is_utf8(value)  ||  value.length() > MAX_FILE_SIZE / 2  ) {
		dbg->warning("local_preferences_t::set()", "'%s' cannot be stored", key);
		return false;
	}
	const line_t *old = find(key);
	int count = 0;
	for(  const line_t &l : lines  ) {
		count += l.key == key;
	}
	if(  old  &&  count == 1  &&  old->value == value  ) {
		// nothing to write
		return true;
	}
	const std::string text = std::string(key) + "=" + value;
	bool done = false;
	for(  size_t i = 0;  i < lines.size();  ) {
		if(  lines[i].key == key  ) {
			if(  done  ) {
				// a duplicate or a value that could not be read: the new value replaces them
				lines.erase(lines.begin() + i);
				continue;
			}
			lines[i].text = text;
			lines[i].value = value;
			lines[i].valid = true;
			done = true;
		}
		i++;
	}
	if(  !done  ) {
		line_t l;
		l.text = text;
		l.key = key;
		l.value = value;
		l.valid = true;
		lines.push_back(l);
	}
	changed = true;
	return true;
}


void local_preferences_t::unset(const char *key)
{
	for(  size_t i = 0;  i < lines.size();  ) {
		if(  lines[i].key == key  ) {
			lines.erase(lines.begin() + i);
			changed = true;
			continue;
		}
		i++;
	}
}
