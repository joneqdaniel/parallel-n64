#pragma once

#include "rdp_common.hpp"
#include "rdp_data_structures.hpp"
#include "rdp_rect_setup_policy.hpp"

namespace RDP
{
namespace detail
{
struct TextureRectanglePolicyInput
{
	RectangleCoordinates rect = {};
	uint32_t word1 = 0;
	uint32_t word2 = 0;
	uint32_t word3 = 0;
	uint32_t raster_flags = 0;
	bool flip = false;
	bool native_resolution_tex_rect = false;
	bool native_texture_lod = false;
};

struct TextureRectanglePolicyOutput
{
	TriangleSetup setup = {};
	AttributeSetup attr = {};
};

inline TextureRectanglePolicyOutput build_texture_rectangle_policy(const TextureRectanglePolicyInput &in)
{
	TextureRectanglePolicyOutput out = {};

	out.setup.xh = in.rect.xh << 13;
	out.setup.xl = in.rect.xl << 13;
	out.setup.xm = in.rect.xl << 13;
	out.setup.ym = in.rect.yl;
	out.setup.yl = in.rect.yl;
	out.setup.yh = in.rect.yh;
	out.setup.tile = (in.word1 >> 24) & 0x7;

	out.setup.flags = TRIANGLE_SETUP_FLIP_BIT;
	if (in.flip || in.native_resolution_tex_rect)
		out.setup.flags |= TRIANGLE_SETUP_DISABLE_UPSCALING_BIT;
	if (in.native_texture_lod)
		out.setup.flags |= TRIANGLE_SETUP_NATIVE_LOD_BIT;
	if ((in.raster_flags & RASTERIZATION_COPY_BIT) != 0)
		out.setup.flags |= TRIANGLE_SETUP_SKIP_XFRAC_BIT;

	int32_t s = (in.word2 >> 16) & 0xffff;
	int32_t t = (in.word2 >> 0) & 0xffff;
	int32_t dsdx = (in.word3 >> 16) & 0xffff;
	int32_t dtdy = (in.word3 >> 0) & 0xffff;
	dsdx = sext<16>(dsdx);
	dtdy = sext<16>(dtdy);

	out.attr.s = s << 16;
	out.attr.t = t << 16;
	if (in.flip)
	{
		out.attr.dtdx = dtdy << 11;
		out.attr.dsde = dsdx << 11;
		out.attr.dsdy = dsdx << 11;
	}
	else
	{
		out.attr.dsdx = dsdx << 11;
		out.attr.dtde = dtdy << 11;
		out.attr.dtdy = dtdy << 11;
	}

	return out;
}
}
}
