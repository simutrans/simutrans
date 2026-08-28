/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#include <string>
#include <vector>
#include "../../dataobj/tabfile.h"
#include "../roadsign_desc.h"
#include "obj_node.h"
#include "text_writer.h"
#include "imagelist_writer.h"
#include "roadsign_writer.h"
#include "get_waytype.h"
#include "skin_writer.h"


static const char* private_sign_directions[] = {"ns", "ew"};
static const char* traffic_light_directions[] = {"n", "s", "w", "e", "nw", "se", "sw", "ne"};
static const char* general_sign_directions[] = {"n", "s", "w", "e"};

// parse "<name>[direction][state]" syntax for the states [state_begin, state_end).
// When required is false, a completely absent first state means "this list is
// not given" and is fine; a partially given state is an error either way
void parse_images_2d(slist_tpl<std::string>& keys, tabfileobj_t& obj, roadsign_desc_t::types flags, const char* name, uint8 state_begin, uint8 state_end, bool required)
{
	const char** directions;
	uint8 dir_cnt; // how many directions are there?
	if(  flags&roadsign_desc_t::PRIVATE_ROAD  ) {
		directions = private_sign_directions;
		dir_cnt = lengthof(private_sign_directions);
	}
	else if(  *obj.get("image[ne][0]")  ) {
		// Assume this is a traffic light.
		directions = traffic_light_directions;
		dir_cnt = lengthof(traffic_light_directions);
	}
	else {
		// Normal road sign or railway signal
		directions = general_sign_directions;
		dir_cnt = lengthof(general_sign_directions);
	}

	for(  uint8 state=state_begin;  state<state_end;  state++  ) {
		for(  uint8 idx = 0;  idx < dir_cnt;  idx++  ) {
			char buf[64];
			sprintf(buf, "%s[%s][%i]", name, directions[idx], state);
			const char* img = obj.get(buf);
			if(  !*img  ){
				if(  !required  &&  state==state_begin  &&  idx==0  ) {
					// the whole list is simply not there
					return;
				}
				if(  state>state_begin+(dir_cnt==2)  &&  idx==0  ) {
					// Assume all further state numbers are invalid.
					return;
				}
				// image in the middle is missing => fatal error
				dbg->fatal("roadsign_writer", "%s is missing!", buf);
			}
			// append image number
			keys.append(img);
		}
	}
}


// parse "<name>[number]" syntax
void parse_images_numbered(slist_tpl<std::string>& keys, tabfileobj_t& obj, const char* name)
{
	for (int i = 0; i < 32; i++) {
		char buf[40];
		sprintf(buf, "%s[%i]", name, i);
		const char *str = obj.get(buf);
		// make sure, there are always 4, 8, 12, ... images (for all directions)
		if(  !*str  ) {
			if(  i % 4  ) {
				dbg->fatal("roadsign_writer", "%s count is %d but must be multiple of 4!", name, i);
			}
			break;
		}
		keys.append(str);
	}
}


// parse "<name>[number][variant]" syntax
void parse_images_numbered_variant(slist_tpl<std::string>& keys, tabfileobj_t& obj, const char* name, uint8 variant)
{
	for (int i = 0; i < 32; i++) {
		char buf[48];
		sprintf(buf, "%s[%i][%i]", name, i, variant);
		const char *str = obj.get(buf);
		// make sure, there are always 4, 8, 12, ... images (for all directions)
		if(  !*str  ) {
			if(  i % 4  ) {
				dbg->fatal("roadsign_writer", "%s[..][%i] count is %d but must be multiple of 4!", name, variant, i);
			}
			break;
		}
		keys.append(str);
	}
}


void roadsign_writer_t::write_obj(FILE* fp, obj_node_t& parent, tabfileobj_t& obj)
{
	const sint64           price       = obj.get_int64("cost",      500) * 100;
	const sint64           maintenance = obj.get_int64("maintenance", 0);
	const uint16           min_speed   = obj.get_int("min_speed",     0);
	const sint8            offset_left = obj.get_int("offset_left",  14);
	const uint8            wtyp        = get_waytype(obj.get("waytype"));
	roadsign_desc_t::types flags       = roadsign_desc_t::NONE;

	if(  obj.get_int("is_signal",0)   ) {
		flags = roadsign_desc_t::SIGN_SIGNAL;
		if(  obj.get_int("free_route",0)  ) {
			flags |= roadsign_desc_t::CHOOSE_SIGN;
		}
	}
	else if(  obj.get_int("is_presignal",0)   ) {
		flags = roadsign_desc_t::SIGN_PRE_SIGNAL;
	}
	else if(  obj.get_int("is_prioritysignal",0)   ) {
		flags = roadsign_desc_t::SIGN_PRIORITY_SIGNAL;
	}
	else if(  obj.get_int("is_longblocksignal",0)   ) {
		flags = roadsign_desc_t::SIGN_LONGBLOCK_SIGNAL;
	}
	else {
		// road or airsigns ...
		flags =
			(obj.get_int("single_way",         0) > 0 ? roadsign_desc_t::ONE_WAY               : roadsign_desc_t::NONE) |
			(obj.get_int("free_route",         0) > 0 ? roadsign_desc_t::CHOOSE_SIGN           : roadsign_desc_t::NONE) |
			(obj.get_int("is_private",         0) > 0 ? roadsign_desc_t::PRIVATE_ROAD          : roadsign_desc_t::NONE) |
			(obj.get_int("no_foreground",      0) > 0 ? roadsign_desc_t::ONLY_BACKIMAGE        : roadsign_desc_t::NONE) |
			(obj.get_int("end_of_choose",      0) > 0 ? roadsign_desc_t::END_OF_CHOOSE_AREA    : roadsign_desc_t::NONE);
	}
	// this causes unused entries to give a warning that they are ignored

	obj_node_t node(this, 28, &parent);

	node.write_version(fp, 6);
	node.write_uint16(fp, min_speed);
	node.write_sint64(fp, price);
	node.write_sint64(fp, maintenance);
	node.write_uint16(fp, flags);
	node.write_uint8 (fp, offset_left);
	node.write_uint8 (fp, wtyp);

	uint16 intro_date = obj.get_int("intro_year", DEFAULT_INTRO_YEAR) * 12;
	intro_date += obj.get_int("intro_month", 1) - 1;
	node.write_uint16(fp, intro_date);

	uint16 retire_date = obj.get_int("retire_year", DEFAULT_RETIRE_YEAR) * 12;
	retire_date += obj.get_int("retire_month", 1) - 1;
	node.write_uint16(fp, retire_date);

	write_name_and_copyright(fp, node, obj);

	// add the images
	slist_tpl<std::string> keys;

	// a signal uses the second index of image[..][..] for its states and a
	// traffic light for its phases; only a plain sign can use it for the
	// drive-on-left variant. The variant lists live in children of their own,
	// so the count of the main list keeps meaning what it always meant - which
	// is also what decides whether a sign is a traffic light
	const bool plain_sign = (flags & (roadsign_desc_t::SIGN_SIGNAL|roadsign_desc_t::SIGN_PRE_SIGNAL|roadsign_desc_t::SIGN_PRIORITY_SIGNAL|roadsign_desc_t::SIGN_LONGBLOCK_SIGNAL|roadsign_desc_t::PRIVATE_ROAD)) == 0
	                       &&  !*obj.get("image[ne][0]");

	if(  *obj.get("image[0]")  ) {
		// image[0] is defined.
		// assume that images are defined in image[number] syntax.
		parse_images_numbered(keys, obj, "image");
	}
	else {
		// image[0] is not defined.
		// assume that images are defined in image[direction][state] syntax.
		parse_images_2d(keys, obj, flags, "image", 0, plain_sign ? 1 : 8, true);
	}

	// the optional lists, ordered as roadsign_desc_t::optional_children names
	// them. The diagonal entries are places and not directions, two for each
	// direction, so the [direction][state] syntax cannot name them and they
	// are always numbered
	slist_tpl<std::string> optional[7];
	parse_images_numbered(optional[0], obj, "diagonal");                 // diagonal[n] ...
	if(  optional[0].empty()  ) {
		parse_images_numbered_variant(optional[0], obj, "diagonal", 0);  // ... or diagonal[n][0]
	}
	if(  *obj.get("frontimage[0]")  ) {
		parse_images_numbered(optional[1], obj, "frontimage");
	}
	else {
		parse_images_2d(optional[1], obj, flags, "frontimage", 0, 1, false);
	}
	parse_images_numbered_variant(optional[2], obj, "frontdiagonal", 0);
	if(  optional[2].empty()  ) {
		parse_images_numbered(optional[2], obj, "frontdiagonal");
	}
	if(  plain_sign  ) {
		parse_images_2d(optional[3], obj, flags, "image", 1, 2, false);
		parse_images_numbered_variant(optional[4], obj, "diagonal", 1);
		parse_images_2d(optional[5], obj, flags, "frontimage", 1, 2, false);
		parse_images_numbered_variant(optional[6], obj, "frontdiagonal", 1);
	}

	// any other length would silently shift the images instead of failing here
	static const char* const optional_names[7] = { "diagonal", "frontimage", "frontdiagonal", "image[..][1]", "diagonal[..][1]", "frontimage[..][1]", "frontdiagonal[..][1]" };
	for(  int j=0;  j<7;  j++  ) {
		const uint32 want = (j&1) == 0 ? 2*keys.get_count() : keys.get_count();
		if(  !optional[j].empty()  &&  optional[j].get_count() != want  ) {
			dbg->fatal("roadsign_writer", "%i %s images given, but the sign needs %i!", optional[j].get_count(), optional_names[j], want);
		}
	}

	imagelist_writer_t::instance()->write_obj(fp, node, keys);

	// probably add some icons, if defined
	slist_tpl<std::string> cursorkeys;

	const char *c = obj.get("cursor"), *i=obj.get("icon");
	cursorkeys.append(c);
	cursorkeys.append(i);

	int last_list = -1;
	for(  int j=0;  j<7;  j++  ) {
		if(  !optional[j].empty()  ) {
			last_list = j;
		}
	}
	if (*c || *i || last_list>=0) {
		// when optional lists follow, this node has to be written even if it is
		// empty: the lists are found by their position, and would take this one
		// otherwise
		cursorskin_writer_t::instance()->write_obj(fp, node, obj, cursorkeys);
	}

	// the optional lists, up to the last one this sign uses; the gaps in
	// between are written as empty lists so that a position never changes its
	// meaning. Last children, so that older versions of Simutrans ignore them
	for(  int j=0;  j<=last_list;  j++  ) {
		imagelist_writer_t::instance()->write_obj(fp, node, optional[j]);
	}

	node.check_and_write_header(fp);
}
