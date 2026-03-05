#ifndef PARALLEL_RDP_FRAME_MAPPING_HPP
#define PARALLEL_RDP_FRAME_MAPPING_HPP

#include "Gfx #1.3.h"
#include "parallel-rdp/parallel-rdp/rdp_common.hpp"
#include "parallel-rdp/parallel-rdp/video_interface.hpp"
#include <utility>

namespace RDP
{
namespace detail
{
inline unsigned sync_mask_to_num_frames(unsigned mask)
{
	unsigned num_frames = 0;
	for (unsigned i = 0; i < 32; i++)
		if (mask & (1u << i))
			num_frames = i + 1;
	return num_frames;
}

template <typename SetViRegisterFn>
inline void forward_vi_registers(SetViRegisterFn &&set_vi_register, const GFX_INFO &info)
{
	set_vi_register(VIRegister::Control, *info.VI_STATUS_REG);
	set_vi_register(VIRegister::Origin, *info.VI_ORIGIN_REG);
	set_vi_register(VIRegister::Width, *info.VI_WIDTH_REG);
	set_vi_register(VIRegister::Intr, *info.VI_INTR_REG);
	set_vi_register(VIRegister::VCurrentLine, *info.VI_V_CURRENT_LINE_REG);
	set_vi_register(VIRegister::Timing, *info.VI_V_BURST_REG);
	set_vi_register(VIRegister::VSync, *info.VI_V_SYNC_REG);
	set_vi_register(VIRegister::HSync, *info.VI_H_SYNC_REG);
	set_vi_register(VIRegister::Leap, *info.VI_LEAP_REG);
	set_vi_register(VIRegister::HStart, *info.VI_H_START_REG);
	set_vi_register(VIRegister::VStart, *info.VI_V_START_REG);
	set_vi_register(VIRegister::VBurst, *info.VI_V_BURST_REG);
	set_vi_register(VIRegister::XScale, *info.VI_X_SCALE_REG);
	set_vi_register(VIRegister::YScale, *info.VI_Y_SCALE_REG);
}

inline ScanoutOptions make_scanout_options(bool vi_aa,
                                           bool vi_scale,
                                           bool dither_filter,
                                           bool divot_filter,
                                           bool gamma_dither,
                                           unsigned downscaling_steps,
                                           unsigned overscan)
{
	ScanoutOptions opts = {};
	opts.persist_frame_on_invalid_input = true;
	opts.vi.aa = vi_aa;
	opts.vi.scale = vi_scale;
	opts.vi.dither_filter = dither_filter;
	opts.vi.divot_filter = divot_filter;
	opts.vi.gamma_dither = gamma_dither;
	opts.downscale_steps = downscaling_steps;
	opts.crop_overscan_pixels = overscan;
	return opts;
}
}
}

#endif
