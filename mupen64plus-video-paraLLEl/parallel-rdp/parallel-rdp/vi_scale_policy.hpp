#pragma once

#include "rdp_common.hpp"

namespace RDP::detail
{
struct VIScalePolicyInput
{
	bool is_pal = false;
	uint32_t status = 0;
	int v_start = 0;
	int v_res = 0;
	int v_current_line = 0;
	unsigned crop_overscan_pixels = 0;
	unsigned scaling_factor = 1;
	bool upscale_deinterlacing = true;
};

struct VIScalePolicy
{
	bool serrate = false;
	unsigned crop_pixels_x = 0;
	unsigned crop_pixels_y = 0;
	unsigned render_target_width = 0;
	unsigned render_target_height = 0;
	int adjusted_v_start = 0;
	int adjusted_v_res = 0;
	uint32_t serrate_shift = 0;
	uint32_t serrate_mask = 0;
	uint32_t serrate_select = 0;
};

inline VIScalePolicy derive_vi_scale_policy(const VIScalePolicyInput &in)
{
	VIScalePolicy out = {};
	out.serrate = (in.status & VI_CONTROL_SERRATE_BIT) != 0 && !in.upscale_deinterlacing;
	out.crop_pixels_x = in.crop_overscan_pixels * in.scaling_factor;
	out.crop_pixels_y = out.crop_pixels_x * (out.serrate ? 2u : 1u);

	out.render_target_width = VI_SCANOUT_WIDTH * in.scaling_factor - 2u * out.crop_pixels_x;
	out.render_target_height =
			((in.is_pal ? VI_V_RES_PAL : VI_V_RES_NTSC) >> int(!out.serrate)) * in.scaling_factor -
			2u * out.crop_pixels_y;

	out.adjusted_v_start = in.v_start;
	out.adjusted_v_res = in.v_res;
	if (out.serrate)
	{
		out.adjusted_v_start *= 2;
		out.adjusted_v_res *= 2;
		out.serrate_shift = 1;
		out.serrate_mask = 1;
		out.serrate_select = uint32_t(in.v_current_line == 0);
	}

	return out;
}
}
