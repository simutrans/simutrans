/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#ifndef DESCRIPTOR_IMAGE_H
#define DESCRIPTOR_IMAGE_H

#include "../tpl/freelist_tpl.h"

#include "../display/simgraph.h"
#include "../display/simimg.h"
#include "obj_desc.h"


// number of special colors
#define SPECIAL (31)

#define SPECIAL_TRANSPARENT (0x00E7FFFF)


#if COLOUR_DEPTH == 0

/**
 * Data of one image
 *
 * Child nodes:
 *  (none)
 */
class image_t : public obj_desc_t
{
private:
	static freelist_tpl<image_t> ifl;

public:
	static const uint32 rgbtab[SPECIAL];

	scr_coord_val x = 0;  ///< x offset of data[] image
	scr_coord_val y = 0;  ///< y offset of data[] image
	scr_coord_val w = 0;  ///< width of data[] image
	scr_coord_val h = 0;  ///< height of data[] image
	image_id imageid = 0; ///< Graphics renderer image id

	void* operator new(size_t) { return ifl.gimme_node(); }
	void operator delete(void* p) { return ifl.putback_node(p); }

	image_t(size_t len_ = 0)
	{
		(void)len_;
	}

	static image_t* copy_image(const image_t& other);

	const image_t* get_pic() const { return this; }

	STORED_PIXVAL const* get_data() const { return NULL; }
	STORED_PIXVAL* get_data() { return NULL; }

	image_id get_id() const { return imageid; }

	/* rotate_image_data - produces a (rotated) image
	 * only rotates by 90 degrees or multiples thereof, and assumes a square image
	 * Otherwise it will only succeed for angle=0;
	 */
	image_t* copy_rotate(const sint16 angle) const;

	image_t* copy_flipvertical() const;
	image_t* copy_fliphorizontal() const;

	static image_t* create_single_pixel();

	struct RGBA {
		uint8 r, g, b, a; // or uint8 c[4];
	};

	inline bool is_transparent(STORED_PIXVAL pix) const {
		return pix >= 0x8020;
	}

	inline RGBA get_rgba(STORED_PIXVAL pix) const {
		return RGBA{ 0,0,0,0 };
	}

	inline STORED_PIXVAL get_pixval(RGBA) const { return 0xFFFF;  }

	void register_image() { this->imageid = gfx->register_image(this); }

private:
	friend class image_reader_t;
};

#else


/**
 * Data of one image
 *
 * Child nodes:
 *  (none)
 */
class image_t : public obj_desc_t
{
private:
	static freelist_tpl<image_t> ifl;

public:
	static const uint32 rgbtab[SPECIAL];

	size_t len = 0;       ///< length of data[] in STORED_PIXVAL units
	scr_coord_val x = 0;  ///< x offset of data[] image
	scr_coord_val y = 0;  ///< y offset of data[] image
	scr_coord_val w = 0;  ///< width of data[] image
	scr_coord_val h = 0;  ///< height of data[] image
	image_id imageid = 0; ///< Graphics renderer image id
	uint8 zoomable = 0;   ///< some images may not be zoomed i.e. icons
	STORED_PIXVAL *data = NULL;  ///< RLE encoded image data, stored space

	void* operator new(size_t) { return ifl.gimme_node(); }
	void operator delete(void* p) { return ifl.putback_node(p); }

	image_t(size_t len_=0)
	{
		if (len_) {
			alloc(len_);
		}
	}

	~image_t()
	{
		delete [] data;
	}

	void alloc(size_t len_)
	{
		delete [] data;
		data = new STORED_PIXVAL[len_];
		len = len_;
	}

	static image_t* copy_image(const image_t& other);

	const image_t* get_pic() const { return this; }

	STORED_PIXVAL const* get_data() const { return data; }
	STORED_PIXVAL*       get_data()       { return data; }

	image_id get_id() const { return imageid; }

	/* rotate_image_data - produces a (rotated) image
	 * only rotates by 90 degrees or multiples thereof, and assumes a square image
	 * Otherwise it will only succeed for angle=0;
	 */
	image_t* copy_rotate(const sint16 angle) const;

	image_t* copy_flipvertical() const;
	image_t* copy_fliphorizontal() const;

	static image_t* create_single_pixel();

	struct RGBA {
		uint8 r, g, b, a; // or uint8 c[4];
	};

	inline bool is_transparent(STORED_PIXVAL pix) const {
		return pix >= 0x8020;
	}

	inline RGBA get_rgba(STORED_PIXVAL pix) const {
		// assume RGB 555 and special
		// attention, for reading routines, alpha convetion is 0 opaque!

		RGBA rgba;

		// 1. Opaque standard RGB555 pixel (bit 15 is 0)
		if ((pix & 0x8000) == 0) {
			rgba.r = ((pix >> 7) & 0xF8);
			rgba.g = ((pix >> 2) & 0xF8);
			rgba.b = ((pix << 3) & 0xF8);
			rgba.a = 0;
			return rgba;
		}

		// 2. Opaque special color (0x8000 to 0x801F)
		if (pix < 0x8020) {
			int i = pix - 0x8000;
			rgba.r = image_t::rgbtab[i] >> 16;
			rgba.g = image_t::rgbtab[i] >> 8;
			rgba.b = image_t::rgbtab[i];
			rgba.a = 0;
			return rgba;
		}

		// 3. Transparent / Alpha-blended pixel (pix >= 0x8020)
		uint16 val = pix - 0x8020;

		// Check if it is a transparent special color
		if (val < SPECIAL * 31) {
			int i = val / 31;
			rgba.r = image_t::rgbtab[i] >> 16;
			rgba.g = image_t::rgbtab[i] >> 8;
			rgba.b = image_t::rgbtab[i];

			// Reverse alpha formula: alpha = (((255 - a_byte) * 33) / 255) - 1
			int alpha = val % 31; // Range: 0..30
			rgba.a = 255 - (((alpha + 1) * 255 + 16) / 33);

			return rgba;
		}

		// 4. Transparent general RGB (3-bit R, 4-bit G, 3-bit B)
		val -= 31 * 31;
		uint16 rgb10 = val / 31;
		uint16 alpha = val % 31;

		rgba.r = ((rgb10 & 0x0380) << 14); // 3 bits -> bits 23..21
		rgba.g = ((rgb10 & 0x0078) << 9); // 4 bits -> bits 15..12
		rgba.b = ((rgb10 & 0x0007) << 5); // 3 bits -> bits 7..5

		rgba.a = 255 - (((alpha + 1) * 255 + 16) / 33);

		return rgba;
	}

	inline STORED_PIXVAL get_pixval(RGBA rgba) const {
		uint16 pix;

		// find about alpha
		if (rgba.a >= 0xF8) {
			// transparent pixel (illegal data)
			return 0xFFFF;
		}

		// make rgb to test if this is a transparent special color (like player color)
		uint32 rgb = rgba.r * 0x10000ul + rgba.g * 0x100ul + rgba.b;

		if (rgba.a > 0x07) { // transparencies smaller than this are considered opaque
			sint16 alpha = (((255 - rgba.a) * 33) / 255) - 1; // alpha = 31 would be transparent -1 opaque

			for (int i = 0; i < SPECIAL; i++) {
				if (image_t::rgbtab[i] == rgb) {
					// player or light color
					pix = 0x8020 + (i * 31) + alpha;
					return pix;
				}
			}
			// else store color as 3 red, 4, green, 3 red
			pix = ((rgb >> 14) & 0x0380) | ((rgb >> 9) & 0x0078) | ((rgb >> 5) & 0x07);
			pix = 0x8020 + (31 * 31) + (pix * 31) + alpha;
			return pix;
		}

		// force non-transparent pixel special
		for (int i = 0; i < SPECIAL; i++) {
			if (image_t::rgbtab[i] == (uint32)rgb) {
				pix = 0x8000 + i;
				return pix;
			}
		}

		// non transparent normal pixel
		return (rgba.r & 0xF8) * 0x0080u + (rgba.g & 0xF8) * 0x0004u + (rgba.b >> 3);
	}

	void register_image() { this->imageid = gfx->register_image(this); }

private:
	friend class image_reader_t;
};

#endif

#endif
