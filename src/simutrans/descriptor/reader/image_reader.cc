/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#include <stdio.h>
#include <string.h>

#include "../../display/simgraph.h"
#include "../../simdebug.h"
#include "../../display/simimg.h"

#include "../image.h"
#include "image_reader.h"
#include "../obj_node_info.h"

#include <zlib.h>
#include "../../tpl/inthashtable_tpl.h"


obj_desc_t *image_reader_t::read_node(FILE *fp, obj_node_info_t &node)
{
	node_body_t p(fp, node.size, get_type_name());
	if (!p) return NULL;

	if(  node.nchildren != 0  ) {
		// an image node is a leaf: makeobj only ever counts children on the parent.
		// A file that claims otherwise would send pakset_manager_t::read_nodes() into
		// "delete data" on an obj_desc_t*, which does not dispatch to
		// image_t::operator delete, so a pool node would reach ::operator delete.
		dbg->warning( "image_reader_t::read_node()", "Ignoring image node that declares %i children", node.nchildren );
		return NULL;
	}

	p.seek(6);
	// always zero in old version, since length was always less than 65535
	// because a node could not hold more data
	uint8 version = decode_uint8(p);
	p.seek(0);

	image_t* desc = new image_t();

	desc->imageid = IMG_EMPTY;
#if COLOUR_DEPTH == 0
	// the pixels are never read here, but the node still has to say whether it
	// carries an image at all: that is what decides registration below
	uint32 img_len = 0;
#endif
	if(version==0) {
		desc->x = decode_uint8(p);
		desc->w = decode_uint8(p);
		desc->y = decode_uint8(p);
		desc->h = decode_uint8(p);
#if COLOUR_DEPTH == 0
		img_len = decode_uint32(p); // len
		goto adjust_image;
#else
		desc->alloc(decode_uint32(p)); // len
		p += 2; // dummys
		desc->zoomable = decode_uint8(p) != 0;
		uint16* dest = desc->data;
		p.seek(12);

		if (desc->h > 0) {
			for (uint i = 0; i < desc->len; i++) {
				uint16 data = decode_uint16(p);
				if(data>=0x8000u  &&  data<=0x800Fu) {
					// player color offset changed
					data ++;
				}
				*dest++ = data;
			}
		}
#endif
	}
	else if(version<=2) {
		desc->x = decode_sint16(p);
		desc->y = decode_sint16(p);
		desc->w = decode_uint8(p);
		desc->h = decode_uint8(p);
#if COLOUR_DEPTH == 0
		p++; // skip version information
		img_len = decode_uint16(p); // len
		goto adjust_image;
#else
		p++; // skip version information
		desc->alloc(decode_uint16(p)); // len
		desc->zoomable = decode_uint8(p) != 0;
		p.read_uint16_block(desc->data, desc->len);
#endif
	}
	else if(version==3) {
		desc->x = decode_sint16(p);
		desc->y = decode_sint16(p);
		desc->w = decode_sint16(p);
		p++; // skip version information
		desc->h = decode_sint16(p);
#if COLOUR_DEPTH == 0
		img_len = (node.size-10)/2; // len
		goto adjust_image;
#else
		desc->alloc((node.size-10)/2); // len
		desc->zoomable = decode_uint8(p) != 0;
		p.read_uint16_block(desc->data, desc->len);
#endif
	}
	else {
		dbg->fatal( "image_reader_t::read_node()", "Cannot handle too new node version %i", version );
	}

#if COLOUR_DEPTH == 0
adjust_image:
	// drop the pixels but keep x/y/w/h: descriptors derive data from them
	// (building_desc_t::calc_height_clearance), and that must not depend on the backend
	if(  img_len != 0  ) {
		// an image that has data must stay observable as "there is an image here":
		// way_builder_t::register_desc(), weg_search() and has_upper_storey() all test
		// the id, and simgraph0 answers with a valid one for exactly this purpose
		desc->imageid = gfx->register_image(desc);
	}
#else
	if (!image_has_valid_data(desc)) {
		delete desc;
		return NULL;
	}

	// check for left corner
	if(COLOUR_DEPTH != 0  &&  version<2  &&  desc->h>0) {
		// find left border
		uint16 left = 255;
		uint16 *dest = desc->data;
		uint16 *end  = desc->data + desc->len;

		for( uint8 y=0;  y<desc->h;  y++  ) {
			if (dest >= end) {
				delete desc;
				return NULL;
			}
			left = min(left, *dest);

			// skip rest of the line
			do {
				dest++;

				if (dest >= end) {
					delete desc;
					return NULL;
				}

				dest += *dest + 1;

				if (dest >= end) {
					delete desc;
					return NULL;
				}
			} while (*dest != 0);

			dest++; // skip trailing zero
		}

		if(left<desc->x) {
			dbg->warning( "image_reader_t::read_node()","left(%i)<x(%i) (may be intended)", left, desc->x );
		}

		/// No need to check for valid dest pointer here, the code has the same structure as above
		dest = desc->data;
		for( uint8 y=0;  y<desc->h;  y++  ) {
			*dest -= left;
			// skip rest of the line
			do {
				dest++;
				dest += *dest + 1;
			} while (*dest != 0);
			dest++; // skip trailing zero
		}
	}

	if (desc->len != 0) {
		// get the adler hash (since we have zlib on board anyway ... )
		bool do_register_image = true;
		uint32 adler = adler32(0L, NULL, 0 );
		// remember len is sizeof(uint16)!
		adler = adler32(adler, (const Bytef *)(desc->data), desc->len*2 );
		static inthashtable_tpl<uint32, image_t *> images_adlers;
		image_t *same = images_adlers.get(adler);
		if (same) {
			// same checksum => if same then skip!
			image_t const& a = *desc;
			image_t const& b = *same;
			do_register_image =
				a.x        != b.x        ||
				a.y        != b.y        ||
				a.w        != b.w        ||
				a.h        != b.h        ||
				a.zoomable != b.zoomable ||
				a.len      != b.len      ||
				memcmp(a.data, b.data, sizeof(*a.data) * a.len) != 0;
		}
		// unique image here
		if(  do_register_image  ) {
			if(!same) {
				images_adlers.put(adler,desc); // still with imageid == IMG_EMPTY!
			}
			// register image adds this image to the internal array maintained by simgraph??.cc
			desc->imageid = gfx->register_image(desc);
		}
		else {
			// no need to load doubles ...
			delete desc;
			desc = same;
		}
	}
#endif

	return desc;
}


#define TRANSPARENT_RUN (0x8000u)

bool image_reader_t::image_has_valid_data(image_t *image_in) const
{
#if COLOUR_DEPTH != 0
	PIXVAL *src = image_in->data;
	PIXVAL *end = image_in->data + image_in->len;

	for( int y = 0;  y < image_in->h;  ++y  ) {
		// decode line
		uint16 runlen = *src++;
		do {
			if (src >= end) {
				return false;
			}

			runlen = *src++ & ~TRANSPARENT_RUN;
			src += runlen;

			if (src >= end) {
				return false;
			}

			runlen = *src++;
		} while(  runlen!=0  ); // end of row: runlen == 0
	}

	return src == end;
#else
	return true;
#endif
}
