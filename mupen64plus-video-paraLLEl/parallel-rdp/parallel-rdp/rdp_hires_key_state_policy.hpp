#pragma once

#include <algorithm>
#include <cstdint>

namespace RDP
{
namespace detail
{
inline uint64_t compose_hires_checksum64(uint32_t texture_crc, uint32_t palette_crc)
{
	return (uint64_t(palette_crc) << 32) | uint64_t(texture_crc);
}

inline uint16_t clamp_hires_dimension_u16(uint32_t dim)
{
	return static_cast<uint16_t>(std::min<uint32_t>(dim, 0xffffu));
}

template <typename TileState>
inline void write_hires_lookup_tile_state(TileState &state,
                                          bool hit,
                                          uint64_t checksum64,
                                          uint64_t upload_checksum64,
                                          uint64_t selector_checksum64,
                                          uint16_t formatsize,
                                          uint32_t orig_w,
                                          uint32_t orig_h)
{
	state.valid = true;
	state.hit = hit;
	state.checksum64 = checksum64;
	state.upload_checksum64 = upload_checksum64;
	state.selector_checksum64 = selector_checksum64;
	state.formatsize = formatsize;
	state.orig_w = clamp_hires_dimension_u16(orig_w);
	state.orig_h = clamp_hires_dimension_u16(orig_h);
}
}
}
