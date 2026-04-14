#pragma once

#include <cstdint>

#include "rdp_common.hpp"

namespace RDP
{
namespace detail
{
inline uint32_t compute_hires_texture_row_bytes(uint32_t width, TextureSize size)
{
	if (size == TextureSize::Bpp4)
		return (width + 1u) >> 1u;

	return (width << unsigned(size)) >> 1u;
}
}
}
