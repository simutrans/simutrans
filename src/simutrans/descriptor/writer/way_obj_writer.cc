/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#include <string>
#include "../../dataobj/tabfile.h"
#include "obj_node.h"
#include "obj_pak_exception.h"
#include "../way_obj_desc.h"
#include "text_writer.h"
#include "imagelist_writer.h"
#include "skin_writer.h"
#include "get_waytype.h"
#include "way_obj_writer.h"

using std::string;

/**
 * Write a way object (lamps, overheadwires)
 */
void way_obj_writer_t::write_obj(FILE* outfp, obj_node_t& parent, tabfileobj_t& obj)
{
	static const char* const ribi_codes[26] = {
		"-", "n",  "e",  "ne",  "s",  "ns",  "se",  "nse",
		"w", "nw", "ew", "new", "sw", "nsw", "sew", "nsew",
		"nse1", "new1", "nsw1", "sew1", "nsew1", // different crossings: northwest/southeast is oneway
		"nse2", "new2", "nsw2", "sew2", "nsew2",
	};
	int ribi, slope;

	const sint64 price       = obj.get_int64("cost",        100);
	const sint64 maintenance = obj.get_int64("maintenance", 100);
	const sint32 topspeed    = obj.get_int  ("topspeed",    999);

	uint16 intro  = obj.get_int("intro_year", DEFAULT_INTRO_YEAR) * 12;
	intro +=        obj.get_int("intro_month", 1) - 1;

	uint16 retire  = obj.get_int("retire_year", DEFAULT_RETIRE_YEAR) * 12;
	retire +=        obj.get_int("retire_month", 1) - 1;

	uint8 wtyp     =  get_waytype(obj.get("waytype"));
	uint8 own_wtyp =  get_waytype(obj.get("own_waytype"));

	obj_node_t node(this, 28, &parent);

	node.write_version(outfp, 2);
	node.write_sint64(outfp, price);
	node.write_sint64(outfp, maintenance);
	node.write_sint32(outfp, topspeed);
	node.write_uint16(outfp, intro);
	node.write_uint16(outfp, retire);
	node.write_uint8 (outfp, wtyp);
	node.write_uint8 (outfp, own_wtyp);

	write_name_and_copyright(outfp, node, obj);

	slist_tpl<string> front_list;
	slist_tpl<string> back_list;

	for (ribi = 0; ribi < lengthof(ribi_codes); ribi++) {
		char buf[40];
		sprintf(buf, "frontimage[%s]", ribi_codes[ribi]);
		string str = obj.get(buf);
		front_list.append(str);
		sprintf(buf, "backimage[%s]", ribi_codes[ribi]);
		string str2 = obj.get(buf);
		back_list.append(str2);
	}
	imagelist_writer_t::instance()->write_obj(outfp, node, front_list);
	imagelist_writer_t::instance()->write_obj(outfp, node, back_list);

	front_list.clear();
	back_list.clear();

	for(  slope = 3;  slope <= 12;  slope += 3  ) {
		char buf[40];
		sprintf( buf, "frontimageup[%d]", slope );
		string str = obj.get(buf);
		front_list.append(str);
		sprintf( buf, "backimageup[%d]", slope );
		string str2 = obj.get(buf);
		back_list.append(str2);
	}
	for(  slope = 3;  slope <= 12;  slope += 3  ) {
		char buf[40];
		sprintf( buf, "frontimageup2[%d]", slope );
		string str = obj.get(buf);
		if(  !str.empty()  ) {
			front_list.append(str);
		}
		sprintf( buf, "backimageup2[%d]", slope );
		string str2 = obj.get(buf);
		if(  !str2.empty()  ) {
			back_list.append(str2);
		}
	}
	imagelist_writer_t::instance()->write_obj(outfp, node, front_list);
	imagelist_writer_t::instance()->write_obj(outfp, node, back_list);

	front_list.clear();
	back_list.clear();

	for (ribi = 3; ribi <= 12; ribi += 3) {
		char buf[40];
		sprintf(buf, "frontdiagonal[%s]", ribi_codes[ribi]);
		string str = obj.get(buf);
		front_list.append(str);
		sprintf(buf, "backdiagonal[%s]", ribi_codes[ribi]);
		string str2 = obj.get(buf);
		back_list.append(str2);
	}
	imagelist_writer_t::instance()->write_obj(outfp, node, front_list);
	imagelist_writer_t::instance()->write_obj(outfp, node, back_list);

	slist_tpl<string> cursorkeys;
	cursorkeys.append(string(obj.get("cursor")));
	cursorkeys.append(string(obj.get("icon")));
	cursorskin_writer_t::instance()->write_obj(outfp, node, obj, cursorkeys);

	node.check_and_write_header(outfp);
}
