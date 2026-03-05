#pragma once

#include <cstdint>

namespace RDP
{
namespace detail
{
template <typename TileState, unsigned NumTiles>
inline void reset_hires_tracking_state(TileState (&tiles)[NumTiles],
                                       bool &tlut_shadow_valid,
                                       uint64_t &lookup_total,
                                       uint64_t &lookup_hits,
                                       uint64_t &lookup_misses)
{
	for (auto &tile : tiles)
		tile = {};
	tlut_shadow_valid = false;
	lookup_total = 0;
	lookup_hits = 0;
	lookup_misses = 0;
}

inline bool hires_provider_changed(const void *previous_provider, const void *next_provider)
{
	return previous_provider != next_provider;
}
}
}
