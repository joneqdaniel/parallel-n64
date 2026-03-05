#pragma once

#include <cstddef>
#include <cstdint>

namespace RDP
{
namespace detail
{
inline bool hires_rdram_view_valid(const void *cpu_rdram, size_t rdram_size)
{
	return cpu_rdram && rdram_size && ((rdram_size & (rdram_size - 1)) == 0);
}

inline bool should_update_tlut_shadow(bool rdram_view_ok, bool is_tlut_mode)
{
	return rdram_view_ok && is_tlut_mode;
}

inline bool should_run_hires_lookup(bool rdram_view_ok,
                                    bool has_replacement_provider,
                                    bool is_tlut_mode,
                                    uint32_t key_width_pixels,
                                    uint32_t key_height_pixels)
{
	return rdram_view_ok &&
	       has_replacement_provider &&
	       !is_tlut_mode &&
	       key_width_pixels > 0 &&
	       key_height_pixels > 0;
}

inline void record_hires_lookup_result(bool hit,
                                       uint64_t &lookup_total,
                                       uint64_t &lookup_hits,
                                       uint64_t &lookup_misses)
{
	lookup_total++;
	if (hit)
		lookup_hits++;
	else
		lookup_misses++;
}
}
}
