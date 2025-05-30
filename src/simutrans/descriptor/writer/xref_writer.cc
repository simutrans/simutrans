/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#include <string.h>
#include "../text_desc.h"
#include "obj_node.h"
#include "xref_writer.h"


void xref_writer_t::write_obj(FILE* outfp, obj_node_t& parent, obj_type type, const char* text, bool fatal)
{
	if (!text) {
		text = "";
	}
	int len = strlen(text);

	obj_node_t node(
		this,
			sizeof(char)     + // Fatal-Flag
			sizeof(obj_type) + // type of dest node
			len + 1, // 0-terminated name of dest node
		&parent
	);

	char c = fatal ? 1 : 0;

	node.write_uint32(outfp, (uint32)type);
	node.write_uint8 (outfp, c);
	node.write_bytes(outfp,  len + 1, text);
	node.check_and_write_header(outfp);
}


bool xref_writer_t::dump_node(FILE* infp, const obj_node_info_t& node)
{
	if (!obj_writer_t::dump_node(infp, node)) {
		return false;
	}

	if(  node.size<5  ) {
		return false;
	}

	char* buf = new char[node.size+1];
	buf[node.size] = 0;

	if (fread(buf, node.size, 1, infp) != 1) {
		delete[] buf;
		return false;
	}

	printf(" -> %4.4s-node (%s) '%s'", buf, buf[4] ? "required" : "optional", buf+5 );
	delete[] buf;
	return true;
}
