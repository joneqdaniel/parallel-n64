#pragma once

#include "rdp_data_structures.hpp"

namespace RDP
{
namespace detail
{
struct RectangleCoordinates
{
	uint32_t xl = 0;
	uint32_t yl = 0;
	uint32_t xh = 0;
	uint32_t yh = 0;
};

inline RectangleCoordinates decode_rectangle_coordinates(uint32_t word0, uint32_t word1)
{
	RectangleCoordinates rect = {};
	rect.xl = (word0 >> 12) & 0xfffu;
	rect.yl = (word0 >> 0) & 0xfffu;
	rect.xh = (word1 >> 12) & 0xfffu;
	rect.yh = (word1 >> 0) & 0xfffu;
	return rect;
}

inline RectangleCoordinates apply_copy_fill_y_adjust(RectangleCoordinates rect, uint32_t raster_flags)
{
	if ((raster_flags & (RASTERIZATION_COPY_BIT | RASTERIZATION_FILL_BIT)) != 0)
		rect.yl |= 3u;
	return rect;
}

inline TriangleSetup build_fill_rectangle_setup(const RectangleCoordinates &rect)
{
	TriangleSetup setup = {};
	setup.xh = rect.xh << 13;
	setup.xl = rect.xl << 13;
	setup.xm = rect.xl << 13;
	setup.ym = rect.yl;
	setup.yl = rect.yl;
	setup.yh = rect.yh;
	setup.flags = TRIANGLE_SETUP_FLIP_BIT | TRIANGLE_SETUP_DISABLE_UPSCALING_BIT;
	return setup;
}
}
}
