#pragma once

#include <algorithm>
#include <cstddef>
#include <cstdint>

#include "rdp_common.hpp"
#include "texture_keying.hpp"

namespace RDP
{
namespace detail
{
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
}
}
