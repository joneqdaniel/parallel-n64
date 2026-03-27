#pragma once

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <vector>

#include "rdp_common.hpp"
#include "texture_keying.hpp"

namespace RDP
{
namespace detail
{
struct HiresCIPaletteUsage
{
	std::array<uint8_t, 32> used_mask = {};
	uint32_t used_count = 0;
	uint32_t min_index = 0;
	uint32_t max_index = 0;
	bool valid = false;
};

struct HiresCI32TLUTUsage
{
	std::array<uint8_t, 128> used_mask = {};
	uint32_t used_count = 0;
	uint32_t min_entry = 0;
	uint32_t max_entry = 0;
	bool valid = false;
};

inline uint32_t legacy_hash_calculate_words(uint32_t hash, const uint8_t *data, size_t size)
{
	if (!data)
		return hash;

	const size_t count = size / 4;
	for (size_t i = 0; i < count; i++)
	{
		const size_t offset = i * 4;
		const uint32_t word =
				(uint32_t(data[offset + 0]) << 0) |
				(uint32_t(data[offset + 1]) << 8) |
				(uint32_t(data[offset + 2]) << 16) |
				(uint32_t(data[offset + 3]) << 24);
		hash += word;
		hash += (hash << 10);
		hash ^= (hash >> 6);
	}

	hash += (hash << 3);
	hash ^= (hash >> 11);
	hash += (hash << 15);
	return hash;
}

inline uint32_t legacy_crc32_reflected(uint32_t crc, const uint8_t *data, size_t size)
{
	if (!data)
		return crc;

	for (size_t i = 0; i < size; i++)
	{
		crc ^= data[i];
		for (unsigned bit = 0; bit < 8; bit++)
			crc = (crc >> 1) ^ ((crc & 1u) ? 0xedb88320u : 0u);
	}
	return crc;
}

inline uint32_t compute_hires_palette_bank_hash(uint32_t bank,
                                                const uint8_t *tlut_shadow,
                                                size_t tlut_shadow_size,
                                                bool tlut_shadow_valid)
{
	if (!tlut_shadow_valid || !tlut_shadow || tlut_shadow_size < 512)
		return 0;

	const uint32_t clamped_bank = std::min<uint32_t>(bank, 15u);
	return legacy_hash_calculate_words(0xffffffffu, tlut_shadow + clamped_bank * 32u, 32u);
}

inline uint32_t compute_hires_palette_bank_crc32(uint32_t bank,
                                                 const uint8_t *tlut_shadow,
                                                 size_t tlut_shadow_size,
                                                 bool tlut_shadow_valid)
{
	if (!tlut_shadow_valid || !tlut_shadow || tlut_shadow_size < 512)
		return 0;

	const uint32_t clamped_bank = std::min<uint32_t>(bank, 15u);
	return legacy_crc32_reflected(0xffffffffu, tlut_shadow + clamped_bank * 32u, 32u);
}

inline uint32_t compute_hires_ci_palette_entry_count(TextureSize size,
                                                     const uint8_t *cpu_rdram,
                                                     size_t rdram_size,
                                                     uint32_t src_base_addr,
                                                     uint32_t key_width_pixels,
                                                     uint32_t key_height_pixels,
                                                     uint32_t row_stride_bytes)
{
	if (!cpu_rdram || rdram_size == 0)
		return 0;

	if (size == TextureSize::Bpp8)
	{
		const uint32_t cimax = compute_ci8_max_index(cpu_rdram, rdram_size, src_base_addr,
		                                              key_width_pixels, key_height_pixels, row_stride_bytes);
		return std::min<uint32_t>(cimax + 1, 256u);
	}

	if (size == TextureSize::Bpp4)
	{
		const uint32_t cimax = compute_ci4_max_index(cpu_rdram, rdram_size, src_base_addr,
		                                              key_width_pixels, key_height_pixels, row_stride_bytes);
		return std::min<uint32_t>(cimax + 1, 16u);
	}

	return 0;
}

inline HiresCIPaletteUsage compute_hires_ci_palette_usage(TextureSize size,
                                                          const uint8_t *cpu_rdram,
                                                          size_t rdram_size,
                                                          uint32_t src_base_addr,
                                                          uint32_t key_width_pixels,
                                                          uint32_t key_height_pixels,
                                                          uint32_t row_stride_bytes)
{
	HiresCIPaletteUsage usage = {};
	if (!cpu_rdram || rdram_size == 0)
		return usage;

	auto mark_index = [&](uint32_t index) {
		if (size == TextureSize::Bpp4)
			index &= 0xfu;
		else if (size == TextureSize::Bpp8)
			index &= 0xffu;
		else
			return;

		const uint32_t byte_index = index >> 3;
		const uint8_t bit = uint8_t(1u << (index & 7u));
		if ((usage.used_mask[byte_index] & bit) == 0)
		{
			usage.used_mask[byte_index] |= bit;
			if (!usage.valid)
			{
				usage.min_index = index;
				usage.max_index = index;
				usage.valid = true;
			}
			else
			{
				usage.min_index = std::min(usage.min_index, index);
				usage.max_index = std::max(usage.max_index, index);
			}
			usage.used_count++;
		}
	};

	if (size == TextureSize::Bpp8)
	{
		for (uint32_t y = 0; y < key_height_pixels; y++)
		{
			const uint32_t row_addr = (src_base_addr + y * row_stride_bytes) & uint32_t(rdram_size - 1);
			for (uint32_t x = 0; x < key_width_pixels; x++)
				mark_index(wrapped_read_u8(cpu_rdram, rdram_size, row_addr + x));
		}
	}
	else if (size == TextureSize::Bpp4)
	{
		const uint32_t row_bytes = (key_width_pixels + 1) >> 1;
		for (uint32_t y = 0; y < key_height_pixels; y++)
		{
			const uint32_t row_addr = (src_base_addr + y * row_stride_bytes) & uint32_t(rdram_size - 1);
			for (uint32_t x = 0; x < row_bytes; x++)
			{
				const uint8_t v = wrapped_read_u8(cpu_rdram, rdram_size, row_addr + x);
				mark_index((v >> 4) & 0xfu);
				mark_index(v & 0xfu);
			}
		}
	}

	return usage;
}

inline HiresCIPaletteUsage compute_hires_ci_palette_usage_tmem(TextureSize size,
                                                               const uint8_t *tmem,
                                                               size_t tmem_size,
                                                               uint32_t src_base_addr,
                                                               uint32_t key_width_pixels,
                                                               uint32_t key_height_pixels,
                                                               uint32_t row_stride_bytes)
{
	HiresCIPaletteUsage usage = {};
	if (!tmem || tmem_size == 0)
		return usage;

	auto mark_index = [&](uint32_t index) {
		if (size == TextureSize::Bpp4)
			index &= 0xfu;
		else if (size == TextureSize::Bpp8)
			index &= 0xffu;
		else
			return;

		const uint32_t byte_index = index >> 3;
		const uint8_t bit = uint8_t(1u << (index & 7u));
		if ((usage.used_mask[byte_index] & bit) == 0)
		{
			usage.used_mask[byte_index] |= bit;
			if (!usage.valid)
			{
				usage.min_index = index;
				usage.max_index = index;
				usage.valid = true;
			}
			else
			{
				usage.min_index = std::min(usage.min_index, index);
				usage.max_index = std::max(usage.max_index, index);
			}
			usage.used_count++;
		}
	};

	if (size == TextureSize::Bpp8)
	{
		for (uint32_t y = 0; y < key_height_pixels; y++)
		{
			const uint32_t row_addr = (src_base_addr + y * row_stride_bytes) & uint32_t(tmem_size - 1);
			for (uint32_t x = 0; x < key_width_pixels; x++)
				mark_index(wrapped_read_u8(tmem, tmem_size, row_addr + x));
		}
	}
	else if (size == TextureSize::Bpp4)
	{
		const uint32_t row_bytes = (key_width_pixels + 1) >> 1;
		for (uint32_t y = 0; y < key_height_pixels; y++)
		{
			const uint32_t row_addr = (src_base_addr + y * row_stride_bytes) & uint32_t(tmem_size - 1);
			for (uint32_t x = 0; x < row_bytes; x++)
			{
				const uint8_t v = wrapped_read_u8(tmem, tmem_size, row_addr + x);
				mark_index((v >> 4) & 0xfu);
				mark_index(v & 0xfu);
			}
		}
	}

	return usage;
}

inline uint32_t compute_hires_ci_palette_entry_count_tmem(TextureSize size,
                                                          const uint8_t *tmem,
                                                          size_t tmem_size,
                                                          uint32_t src_base_addr,
                                                          uint32_t key_width_pixels,
                                                          uint32_t key_height_pixels,
                                                          uint32_t row_stride_bytes)
{
	const auto usage = compute_hires_ci_palette_usage_tmem(
			size,
			tmem,
			tmem_size,
			src_base_addr,
			key_width_pixels,
			key_height_pixels,
			row_stride_bytes);
	if (!usage.valid)
		return 0;

	if (size == TextureSize::Bpp8)
		return std::min<uint32_t>(usage.max_index + 1u, 256u);
	else if (size == TextureSize::Bpp4)
		return std::min<uint32_t>(usage.max_index + 1u, 16u);
	else
		return 0;
}

inline HiresCI32TLUTUsage compute_hires_ci32_tlut_usage(const uint8_t *cpu_rdram,
                                                        size_t rdram_size,
                                                        uint32_t src_base_addr,
                                                        uint32_t key_width_pixels,
                                                        uint32_t key_height_pixels,
                                                        uint32_t row_stride_bytes)
{
	HiresCI32TLUTUsage usage = {};
	if (!cpu_rdram || rdram_size == 0)
		return usage;

	auto mark_entry = [&](uint32_t entry) {
		entry &= 0x3ffu;
		const uint32_t byte_index = entry >> 3;
		const uint8_t bit = uint8_t(1u << (entry & 7u));
		if ((usage.used_mask[byte_index] & bit) != 0)
			return;

		usage.used_mask[byte_index] |= bit;
		if (!usage.valid)
		{
			usage.min_entry = entry;
			usage.max_entry = entry;
			usage.valid = true;
		}
		else
		{
			usage.min_entry = std::min(usage.min_entry, entry);
			usage.max_entry = std::max(usage.max_entry, entry);
		}
		usage.used_count++;
	};

	for (uint32_t y = 0; y < key_height_pixels; y++)
	{
		const uint32_t row_addr = (src_base_addr + y * row_stride_bytes) & uint32_t(rdram_size - 1);
		for (uint32_t x = 0; x < key_width_pixels; x++)
		{
			const uint32_t texel_addr = (row_addr + x * 2u) & uint32_t(rdram_size - 1);
			const uint16_t word =
					uint16_t(wrapped_read_u8(cpu_rdram, rdram_size, texel_addr + 0u)) |
					(uint16_t(wrapped_read_u8(cpu_rdram, rdram_size, texel_addr + 1u)) << 8u);
			const uint32_t base_entry = (uint32_t(word >> 6u) & ~3u) & 0x3ffu;
			for (uint32_t i = 0; i < 4u; i++)
				mark_entry(base_entry + i);
		}
	}

	return usage;
}

inline uint32_t compute_hires_ci32_tlut_group_texture_crc(const uint8_t *cpu_rdram,
                                                          size_t rdram_size,
                                                          uint32_t src_base_addr,
                                                          uint32_t key_width_pixels,
                                                          uint32_t key_height_pixels,
                                                          uint32_t row_stride_bytes)
{
	if (!cpu_rdram || rdram_size == 0 || key_width_pixels == 0 || key_height_pixels == 0)
		return 0;

	std::vector<uint8_t> packed(size_t(key_width_pixels) * size_t(key_height_pixels) * 2u);
	for (uint32_t y = 0; y < key_height_pixels; y++)
	{
		const uint32_t row_addr = (src_base_addr + y * row_stride_bytes) & uint32_t(rdram_size - 1);
		for (uint32_t x = 0; x < key_width_pixels; x++)
		{
			const uint32_t texel_addr = (row_addr + x * 2u) & uint32_t(rdram_size - 1);
			const uint16_t word =
					uint16_t(wrapped_read_u8(cpu_rdram, rdram_size, texel_addr + 0u)) |
					(uint16_t(wrapped_read_u8(cpu_rdram, rdram_size, texel_addr + 1u)) << 8u);
			const uint16_t group_word = uint16_t((uint32_t(word >> 6u) & ~3u) & 0x3ffu);
			const size_t dst = (size_t(y) * size_t(key_width_pixels) + size_t(x)) * 2u;
			packed[dst + 0u] = uint8_t(group_word & 0xffu);
			packed[dst + 1u] = uint8_t(group_word >> 8u);
		}
	}

	return rice_crc32_wrapped(
			packed.data(),
			packed.size(),
			0,
			key_width_pixels,
			key_height_pixels,
			2,
			key_width_pixels * 2u);
}

inline uint32_t compute_hires_ci32_tlut_group_palette_crc(const uint8_t *tlut_tmem_shadow,
                                                          size_t tlut_tmem_shadow_size,
                                                          bool tlut_shadow_valid,
                                                          const HiresCI32TLUTUsage &usage)
{
	if (!usage.valid || usage.used_count == 0)
		return 0;
	if (!tlut_shadow_valid || !tlut_tmem_shadow || tlut_tmem_shadow_size < 2048)
		return 0;

	std::array<uint8_t, 2048> packed = {};
	uint32_t packed_entries = 0;
	for (uint32_t entry = 0; entry < 1024u; entry++)
	{
		if ((usage.used_mask[entry >> 3] & (1u << (entry & 7u))) == 0)
			continue;

		const uint32_t src = entry * 8u;
		packed[packed_entries * 2u + 0u] = tlut_tmem_shadow[src + 0u];
		packed[packed_entries * 2u + 1u] = tlut_tmem_shadow[src + 1u];
		packed_entries++;
	}

	if (packed_entries == 0)
		return 0;

	return rice_crc32_wrapped(packed.data(), packed.size(), 0, packed_entries, 1, 2, packed_entries * 2u);
}

inline uint32_t compute_hires_ci_palette_crc_for_used_indices(TextureSize size,
                                                              uint32_t palette,
                                                              const uint8_t *tlut_shadow,
                                                              size_t tlut_shadow_size,
                                                              bool tlut_shadow_valid,
                                                              const HiresCIPaletteUsage &usage)
{
	if (!usage.valid || usage.used_count == 0)
		return 0;
	if (!tlut_shadow_valid || !tlut_shadow || tlut_shadow_size < 512)
		return 0;

	std::array<uint8_t, 512> packed = {};
	uint32_t packed_entries = 0;

	if (size == TextureSize::Bpp8)
	{
		for (uint32_t index = 0; index < 256; index++)
		{
			if ((usage.used_mask[index >> 3] & (1u << (index & 7u))) == 0)
				continue;
			const uint32_t src = index * 2u;
			packed[packed_entries * 2u + 0u] = tlut_shadow[src + 0u];
			packed[packed_entries * 2u + 1u] = tlut_shadow[src + 1u];
			packed_entries++;
		}
	}
	else if (size == TextureSize::Bpp4)
	{
		const uint32_t bank = std::min<uint32_t>(palette, 15u);
		const uint32_t bank_base = bank * 32u;
		for (uint32_t index = 0; index < 16; index++)
		{
			if ((usage.used_mask[index >> 3] & (1u << (index & 7u))) == 0)
				continue;
			const uint32_t src = bank_base + index * 2u;
			packed[packed_entries * 2u + 0u] = tlut_shadow[src + 0u];
			packed[packed_entries * 2u + 1u] = tlut_shadow[src + 1u];
			packed_entries++;
		}
	}
	else
		return 0;

	if (packed_entries == 0)
		return 0;

	return rice_crc32_wrapped(packed.data(), packed.size(), 0, packed_entries, 1, 2, packed_entries * 2u);
}

inline uint32_t compute_hires_ci_palette_crc_for_entries_tmem(TextureSize size,
                                                              uint32_t palette,
                                                              const uint8_t *tlut_tmem_shadow,
                                                              size_t tlut_tmem_shadow_size,
                                                              bool tlut_shadow_valid,
                                                              uint32_t entries)
{
	if (!tlut_shadow_valid || !tlut_tmem_shadow || tlut_tmem_shadow_size < 2048)
		return 0;

	std::array<uint8_t, 512> packed = {};
	uint32_t packed_entries = 0;

	if (size == TextureSize::Bpp8)
	{
		entries = std::min<uint32_t>(entries, 256u);
		for (uint32_t index = 0; index < entries; index++)
		{
			const uint32_t src = index * 8u;
			packed[packed_entries * 2u + 0u] = tlut_tmem_shadow[src + 0u];
			packed[packed_entries * 2u + 1u] = tlut_tmem_shadow[src + 1u];
			packed_entries++;
		}
	}
	else if (size == TextureSize::Bpp4)
	{
		entries = std::min<uint32_t>(entries, 16u);
		const uint32_t bank = std::min<uint32_t>(palette, 15u);
		const uint32_t bank_base = bank * 16u * 8u;
		for (uint32_t index = 0; index < entries; index++)
		{
			const uint32_t src = bank_base + index * 8u;
			packed[packed_entries * 2u + 0u] = tlut_tmem_shadow[src + 0u];
			packed[packed_entries * 2u + 1u] = tlut_tmem_shadow[src + 1u];
			packed_entries++;
		}
	}
	else
		return 0;

	if (packed_entries == 0)
		return 0;

	return rice_crc32_wrapped(packed.data(), packed.size(), 0, packed_entries, 1, 2, packed_entries * 2u);
}

inline uint32_t compute_hires_ci_palette_crc_for_used_indices_tmem(TextureSize size,
                                                                   uint32_t palette,
                                                                   const uint8_t *tlut_tmem_shadow,
                                                                   size_t tlut_tmem_shadow_size,
                                                                   bool tlut_shadow_valid,
                                                                   const HiresCIPaletteUsage &usage)
{
	if (!usage.valid || usage.used_count == 0)
		return 0;
	if (!tlut_shadow_valid || !tlut_tmem_shadow || tlut_tmem_shadow_size < 2048)
		return 0;

	std::array<uint8_t, 512> packed = {};
	uint32_t packed_entries = 0;

	if (size == TextureSize::Bpp8)
	{
		for (uint32_t index = 0; index < 256; index++)
		{
			if ((usage.used_mask[index >> 3] & (1u << (index & 7u))) == 0)
				continue;
			const uint32_t src = index * 8u;
			packed[packed_entries * 2u + 0u] = tlut_tmem_shadow[src + 0u];
			packed[packed_entries * 2u + 1u] = tlut_tmem_shadow[src + 1u];
			packed_entries++;
		}
	}
	else if (size == TextureSize::Bpp4)
	{
		const uint32_t bank = std::min<uint32_t>(palette, 15u);
		const uint32_t bank_base = bank * 16u * 8u;
		for (uint32_t index = 0; index < 16; index++)
		{
			if ((usage.used_mask[index >> 3] & (1u << (index & 7u))) == 0)
				continue;
			const uint32_t src = bank_base + index * 8u;
			packed[packed_entries * 2u + 0u] = tlut_tmem_shadow[src + 0u];
			packed[packed_entries * 2u + 1u] = tlut_tmem_shadow[src + 1u];
			packed_entries++;
		}
	}
	else
		return 0;

	if (packed_entries == 0)
		return 0;

	return rice_crc32_wrapped(packed.data(), packed.size(), 0, packed_entries, 1, 2, packed_entries * 2u);
}

inline uint32_t compute_hires_ci_palette_crc_for_entries(TextureSize size,
                                                         uint32_t palette,
                                                         const uint8_t *tlut_shadow,
                                                         size_t tlut_shadow_size,
                                                         bool tlut_shadow_valid,
                                                         uint32_t entries)
{
	if (!tlut_shadow_valid || !tlut_shadow || tlut_shadow_size < 512)
		return 0;

	if (size == TextureSize::Bpp8)
	{
		entries = std::min<uint32_t>(entries, 256u);
		if (entries == 0)
			return 0;
		return rice_crc32_wrapped(tlut_shadow, tlut_shadow_size, 0, entries, 1, 2, 512);
	}

	if (size == TextureSize::Bpp4)
	{
		entries = std::min<uint32_t>(entries, 16u);
		if (entries == 0)
			return 0;
		const uint32_t bank = std::min<uint32_t>(palette, 15u);
		return rice_crc32_wrapped(tlut_shadow, tlut_shadow_size, bank * 32, entries, 1, 2, 32);
	}

	return 0;
}

inline void decode_hires_tlut_word_logical_rgba8(uint16_t word, bool tlut_type, uint8_t *rgba8)
{
	if (!rgba8)
		return;

	if (tlut_type)
	{
		const uint8_t intensity = uint8_t(word >> 8);
		const uint8_t alpha = uint8_t(word & 0xff);
		rgba8[0] = intensity;
		rgba8[1] = intensity;
		rgba8[2] = intensity;
		rgba8[3] = alpha;
	}
	else
	{
		const uint8_t r5 = uint8_t((word >> 11) & 31u);
		const uint8_t g5 = uint8_t((word >> 6) & 31u);
		const uint8_t b5 = uint8_t((word >> 1) & 31u);
		rgba8[0] = uint8_t((r5 << 3u) | (r5 >> 2u));
		rgba8[1] = uint8_t((g5 << 3u) | (g5 >> 2u));
		rgba8[2] = uint8_t((b5 << 3u) | (b5 >> 2u));
		rgba8[3] = (word & 1u) ? 0xffu : 0x00u;
	}
}

inline uint32_t compute_hires_ci_palette_crc_for_entries_logical(TextureSize size,
                                                                 uint32_t palette,
                                                                 const uint8_t *tlut_shadow,
                                                                 size_t tlut_shadow_size,
                                                                 bool tlut_shadow_valid,
                                                                 uint32_t entries,
                                                                 bool tlut_type)
{
	if (!tlut_shadow_valid || !tlut_shadow || tlut_shadow_size < 512)
		return 0;

	std::array<uint8_t, 1024> packed = {};
	uint32_t packed_entries = 0;

	if (size == TextureSize::Bpp8)
	{
		entries = std::min<uint32_t>(entries, 256u);
		for (uint32_t index = 0; index < entries; index++)
		{
			const uint32_t src = index * 2u;
			const uint16_t word = uint16_t(tlut_shadow[src + 0u]) | (uint16_t(tlut_shadow[src + 1u]) << 8u);
			decode_hires_tlut_word_logical_rgba8(word, tlut_type, packed.data() + packed_entries * 4u);
			packed_entries++;
		}
	}
	else if (size == TextureSize::Bpp4)
	{
		entries = std::min<uint32_t>(entries, 16u);
		const uint32_t bank = std::min<uint32_t>(palette, 15u);
		const uint32_t bank_base = bank * 32u;
		for (uint32_t index = 0; index < entries; index++)
		{
			const uint32_t src = bank_base + index * 2u;
			const uint16_t word = uint16_t(tlut_shadow[src + 0u]) | (uint16_t(tlut_shadow[src + 1u]) << 8u);
			decode_hires_tlut_word_logical_rgba8(word, tlut_type, packed.data() + packed_entries * 4u);
			packed_entries++;
		}
	}
	else
		return 0;

	if (packed_entries == 0)
		return 0;

	return rice_crc32_wrapped(packed.data(), packed.size(), 0, packed_entries, 1, 3, packed_entries * 4u);
}

inline uint32_t compute_hires_ci_palette_crc_for_used_indices_logical(TextureSize size,
                                                                      uint32_t palette,
                                                                      const uint8_t *tlut_shadow,
                                                                      size_t tlut_shadow_size,
                                                                      bool tlut_shadow_valid,
                                                                      const HiresCIPaletteUsage &usage,
                                                                      bool tlut_type)
{
	if (!usage.valid || usage.used_count == 0)
		return 0;
	if (!tlut_shadow_valid || !tlut_shadow || tlut_shadow_size < 512)
		return 0;

	std::array<uint8_t, 1024> packed = {};
	uint32_t packed_entries = 0;

	if (size == TextureSize::Bpp8)
	{
		for (uint32_t index = 0; index < 256; index++)
		{
			if ((usage.used_mask[index >> 3] & (1u << (index & 7u))) == 0)
				continue;
			const uint32_t src = index * 2u;
			const uint16_t word = uint16_t(tlut_shadow[src + 0u]) | (uint16_t(tlut_shadow[src + 1u]) << 8u);
			decode_hires_tlut_word_logical_rgba8(word, tlut_type, packed.data() + packed_entries * 4u);
			packed_entries++;
		}
	}
	else if (size == TextureSize::Bpp4)
	{
		const uint32_t bank = std::min<uint32_t>(palette, 15u);
		const uint32_t bank_base = bank * 32u;
		for (uint32_t index = 0; index < 16; index++)
		{
			if ((usage.used_mask[index >> 3] & (1u << (index & 7u))) == 0)
				continue;
			const uint32_t src = bank_base + index * 2u;
			const uint16_t word = uint16_t(tlut_shadow[src + 0u]) | (uint16_t(tlut_shadow[src + 1u]) << 8u);
			decode_hires_tlut_word_logical_rgba8(word, tlut_type, packed.data() + packed_entries * 4u);
			packed_entries++;
		}
	}
	else
		return 0;

	if (packed_entries == 0)
		return 0;

	return rice_crc32_wrapped(packed.data(), packed.size(), 0, packed_entries, 1, 3, packed_entries * 4u);
}

inline uint32_t compute_hires_ci_palette_crc(TextureSize size,
                                             uint32_t palette,
                                             const uint8_t *cpu_rdram,
                                             size_t rdram_size,
                                             uint32_t src_base_addr,
                                             uint32_t key_width_pixels,
                                             uint32_t key_height_pixels,
                                             uint32_t row_stride_bytes,
                                             const uint8_t *tlut_shadow,
                                             size_t tlut_shadow_size,
                                             bool tlut_shadow_valid)
{
	const uint32_t entries = compute_hires_ci_palette_entry_count(
			size,
			cpu_rdram,
			rdram_size,
			src_base_addr,
			key_width_pixels,
			key_height_pixels,
			row_stride_bytes);
	return compute_hires_ci_palette_crc_for_entries(
			size,
			palette,
			tlut_shadow,
			tlut_shadow_size,
			tlut_shadow_valid,
			entries);
}

inline uint32_t compute_hires_ci_palette_crc_legacy_bank_hash(TextureSize size,
                                                              uint32_t palette,
                                                              const uint8_t *tlut_shadow,
                                                              size_t tlut_shadow_size,
                                                              bool tlut_shadow_valid)
{
	if (!tlut_shadow_valid || !tlut_shadow || tlut_shadow_size < 512)
		return 0;

	constexpr uint32_t bank_count = 16;
	const uint32_t bank = std::min<uint32_t>(palette, bank_count - 1);

	if (size == TextureSize::Bpp4)
		return compute_hires_palette_bank_hash(bank, tlut_shadow, tlut_shadow_size, tlut_shadow_valid);

	if (size == TextureSize::Bpp8)
	{
		uint32_t bank_hashes[bank_count] = {};
		for (uint32_t i = 0; i < bank_count; i++)
			bank_hashes[i] = compute_hires_palette_bank_hash(i, tlut_shadow, tlut_shadow_size, tlut_shadow_valid);
		return legacy_hash_calculate_words(0xffffffffu,
		                                   reinterpret_cast<const uint8_t *>(bank_hashes),
		                                   sizeof(bank_hashes));
	}

	return 0;
}

inline uint32_t compute_hires_ci_palette_crc_legacy_bank_crc32(TextureSize size,
                                                               uint32_t palette,
                                                               const uint8_t *tlut_shadow,
                                                               size_t tlut_shadow_size,
                                                               bool tlut_shadow_valid)
{
	if (!tlut_shadow_valid || !tlut_shadow || tlut_shadow_size < 512)
		return 0;

	constexpr uint32_t bank_count = 16;
	const uint32_t bank = std::min<uint32_t>(palette, bank_count - 1);

	if (size == TextureSize::Bpp4)
		return compute_hires_palette_bank_crc32(bank, tlut_shadow, tlut_shadow_size, tlut_shadow_valid);

	if (size == TextureSize::Bpp8)
	{
		uint32_t bank_crcs[bank_count] = {};
		for (uint32_t i = 0; i < bank_count; i++)
			bank_crcs[i] = compute_hires_palette_bank_crc32(i, tlut_shadow, tlut_shadow_size, tlut_shadow_valid);
		return legacy_crc32_reflected(0xffffffffu,
		                              reinterpret_cast<const uint8_t *>(bank_crcs),
		                              sizeof(bank_crcs));
	}

	return 0;
}

inline uint32_t compute_hires_ci_palette_crc_legacy_tmem_hash(TextureSize size,
                                                              uint32_t palette,
                                                              const uint8_t *tlut_tmem_shadow,
                                                              size_t tlut_tmem_shadow_size,
                                                              bool tlut_shadow_valid)
{
	if (!tlut_shadow_valid || !tlut_tmem_shadow || tlut_tmem_shadow_size < 2048)
		return 0;

	constexpr uint32_t bank_count = 16;
	constexpr uint32_t bank_stride_bytes = 16u * 8u;
	const uint32_t bank = std::min<uint32_t>(palette, bank_count - 1);

	if (size == TextureSize::Bpp4)
		return legacy_hash_calculate_words(0xffffffffu,
		                                   tlut_tmem_shadow + bank * bank_stride_bytes,
		                                   16u);

	if (size == TextureSize::Bpp8)
	{
		uint32_t bank_hashes[bank_count] = {};
		for (uint32_t i = 0; i < bank_count; i++)
		{
			bank_hashes[i] = legacy_hash_calculate_words(0xffffffffu,
			                                             tlut_tmem_shadow + i * bank_stride_bytes,
			                                             16u);
		}
		return legacy_hash_calculate_words(0xffffffffu,
		                                   reinterpret_cast<const uint8_t *>(bank_hashes),
		                                   sizeof(bank_hashes));
	}

	return 0;
}
}
}
