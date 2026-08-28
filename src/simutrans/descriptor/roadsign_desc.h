/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#ifndef DESCRIPTOR_ROADSIGN_DESC_H
#define DESCRIPTOR_ROADSIGN_DESC_H


#include "obj_base_desc.h"
#include "image_list.h"
#include "skin_desc.h"
#include "../dataobj/ribi.h"
#include "../simtypes.h"
#include "../network/checksum.h"


/**
 * Road signs
 *
 * Child nodes:
 *  0   Name
 *  1   Copyright
 *  2   Image list
 *  3   Cursor and icon
 *  4   Diagonal image list (optional, see optional_children below)
 *  5   Front image list (optional)
 *  6   Front diagonal image list (optional)
 *  7   Drive-on-left image list (optional)
 *  8   Drive-on-left diagonal image list (optional)
 *  9   Drive-on-left front image list (optional)
 * 10   Drive-on-left front diagonal image list (optional)
 */
class roadsign_desc_t : public obj_desc_transport_infrastructure_t {
	friend class roadsign_reader_t;

private:
	uint16 flags;

	sint8 offset_left; // default 14

	uint16 min_speed; // 0 = no min speed

	// set from the number of children when loading, so it is not part of the
	// node data and does not change the checksum of signs already published
	uint8 children = 4;

public:
	enum types {
		NONE                  = 0,
		ONE_WAY               = 1U << 0,
		CHOOSE_SIGN           = 1U << 1,
		PRIVATE_ROAD          = 1U << 2,
		SIGN_SIGNAL           = 1U << 3,
		SIGN_PRE_SIGNAL       = 1U << 4,
		ONLY_BACKIMAGE        = 1U << 5,
		SIGN_LONGBLOCK_SIGNAL = 1U << 6,
		END_OF_CHOOSE_AREA    = 1U << 7,
		SIGN_PRIORITY_SIGNAL  = 1U << 8
	};

	image_id get_image_id(ribi_t::dir dir) const
	{
		image_t const* const image = get_child<image_list_t>(2)->get_image(dir);
		return image != NULL ? image->get_id() : IMG_EMPTY;
	}

	// asks for the straight image, whatever the way below looks like
	static const uint16 NO_DIAGONAL = 0xFFFF;

	/*
	 * The optional image lists behind the cursor child, found by their
	 * position. makeobj writes them up to the last one the sign uses and
	 * fills the skipped positions with empty lists, so a position never
	 * changes its meaning. Missing or empty simply means: fall back.
	 *
	 * The left lists repeat the exact layout of their right counterparts;
	 * the diagonal lists hold two entries per normal one, because a
	 * direction needs a different image in each of the two bends it can
	 * appear in, and the bend of the way picks between them.
	 */
	enum optional_children {
		CHILD_DIAGONAL            =  4,
		CHILD_FRONT               =  5,
		CHILD_FRONT_DIAGONAL      =  6,
		CHILD_LEFT                =  7,
		CHILD_LEFT_DIAGONAL       =  8,
		CHILD_LEFT_FRONT          =  9,
		CHILD_LEFT_FRONT_DIAGONAL = 10
	};

private:
	// one image of one optional list, or IMG_EMPTY when the list or the image is missing
	image_id optional_image(uint8 child, uint16 index) const
	{
		if(  index == NO_DIAGONAL  ||  children <= child  ) {
			return IMG_EMPTY;
		}
		image_t const* const image = get_child<image_list_t>(child)->get_image(index);
		return image != NULL ? image->get_id() : IMG_EMPTY;
	}

public:
	// most specific image first; every miss falls back one step, so an
	// incomplete pak loses the specialisation and never the sign itself
	image_id get_image_id(uint16 index, uint16 diagonal, bool left) const
	{
		if(  left  ) {
			image_id img = optional_image( CHILD_LEFT_DIAGONAL, diagonal );
			if(  img == IMG_EMPTY  ) {
				img = optional_image( CHILD_LEFT, index );
			}
			if(  img != IMG_EMPTY  ) {
				return img;
			}
		}
		const image_id img = optional_image( CHILD_DIAGONAL, diagonal );
		// falling back keeps the sign visible, and keeps its front/back order
		// and its offsets exactly as they are without diagonals
		return img != IMG_EMPTY ? img : get_image_id( (ribi_t::dir)index );
	}

	// the separate front list: when a pak provides it, image[] is the back
	// image and frontimage[] the front one, instead of the position heuristics
	image_id get_front_image_id(uint16 index, uint16 diagonal, bool left) const
	{
		if(  left  ) {
			image_id img = optional_image( CHILD_LEFT_FRONT_DIAGONAL, diagonal );
			if(  img == IMG_EMPTY  ) {
				img = optional_image( CHILD_LEFT_FRONT, index );
			}
			if(  img != IMG_EMPTY  ) {
				return img;
			}
		}
		const image_id img = optional_image( CHILD_FRONT_DIAGONAL, diagonal );
		return img != IMG_EMPTY ? img : optional_image( CHILD_FRONT, index );
	}

	bool has_diagonal_image() const { return children > CHILD_DIAGONAL; }
	bool has_left_images()    const { return children > CHILD_LEFT; }
	bool has_front_images(bool left) const { return children > (left ? CHILD_LEFT_FRONT : CHILD_FRONT); }

	// only the normal list: this count decides whether a sign is a traffic light
	// and whether it has electrified images, so the diagonals must stay out of it
	uint16 get_count() const { return get_child<image_list_t>(2)->get_count(); }

	skin_desc_t const* get_cursor() const { return get_child<skin_desc_t>(3); }

	uint16 get_min_speed() const { return min_speed; }

	bool is_single_way() const { return (flags & ONE_WAY) != 0; }

	bool is_private_way() const { return (flags & PRIVATE_ROAD) != 0; }

	bool is_choose_sign() const { return (flags & CHOOSE_SIGN) != 0; }

	//  return true for signal
	bool is_simple_signal() const { return (flags & (
		SIGN_SIGNAL |
		SIGN_PRE_SIGNAL |
		SIGN_PRIORITY_SIGNAL |
		SIGN_LONGBLOCK_SIGNAL |
		CHOOSE_SIGN)) == SIGN_SIGNAL; }

	//  return true for presignal
	bool is_pre_signal() const { return (flags & SIGN_PRE_SIGNAL) != 0; }

	//  return true for priority signal
	bool is_priority_signal() const { return (flags & SIGN_PRIORITY_SIGNAL) != 0; }

	//  return true for single track section signal
	bool is_longblock_signal() const { return (flags & SIGN_LONGBLOCK_SIGNAL) != 0; }

	bool is_end_choose_signal() const { return (flags & END_OF_CHOOSE_AREA) != 0; }

	bool is_signal_type() const
	{
		return (flags&(
				SIGN_SIGNAL |
				SIGN_PRE_SIGNAL |
				SIGN_PRIORITY_SIGNAL |
				SIGN_LONGBLOCK_SIGNAL)
			) != 0;
	}

	//  return true for a traffic light
	bool is_traffic_light() const { return !is_signal_type()  &&  get_count() > 4; }

	uint16 get_flags() const { return flags; }

	sint8 get_offset_left() const { return offset_left; }

	void calc_checksum(checksum_t *chk) const
	{
		obj_desc_transport_infrastructure_t::calc_checksum(chk);
		chk->input(flags);
		chk->input(min_speed);
	}
};

ENUM_BITSET(roadsign_desc_t::types)

#endif
