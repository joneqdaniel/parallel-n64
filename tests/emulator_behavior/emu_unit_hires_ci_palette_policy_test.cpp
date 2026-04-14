#include "mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/rdp_hires_ci_palette_policy.hpp"
#include "mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/rdp_hires_texture_layout.hpp"

#include <array>
#include <cstdint>
#include <cstdlib>
#include <iostream>

namespace
{
using namespace RDP;

static void check(bool condition, const char *message)
{
	if (!condition)
	{
		std::cerr << "FAIL: " << message << std::endl;
		std::exit(1);
	}
}

static uint16_t emulate_load_tlut_entry_word_from_raw(const uint8_t *raw, size_t size, uint32_t addr)
{
	const uint32_t mapped_addr = addr ^ 2u;
	const uint8_t b0 = raw[mapped_addr & uint32_t(size - 1)];
	const uint8_t b1 = raw[(mapped_addr + 1u) & uint32_t(size - 1)];
	return uint16_t(b1) | (uint16_t(b0) << 8u);
}

static std::array<uint8_t, 2048> build_tlut_tmem_shadow(const std::array<uint8_t, 512> &raw, uint32_t palette_entry_base)
{
	std::array<uint8_t, 2048> tmem = {};
	for (uint32_t entry = 0; entry < 256u; entry++)
	{
		const uint32_t tmem_entry = palette_entry_base + entry;
		const uint32_t tmem_byte_offset = tmem_entry * 8u;
		const uint16_t word = emulate_load_tlut_entry_word_from_raw(raw.data(), raw.size(), entry * 2u);
		tmem[tmem_byte_offset + 0u] = uint8_t(word & 0xffu);
		tmem[tmem_byte_offset + 1u] = uint8_t(word >> 8u);
	}
	return tmem;
}

static uint32_t manual_sparse_crc_from_raw(TextureSize size,
                                           uint32_t palette,
                                           const std::array<uint8_t, 512> &raw,
                                           const RDP::detail::HiresCIPaletteUsage &usage)
{
	std::array<uint8_t, 512> packed = {};
	uint32_t packed_entries = 0;

	if (size == TextureSize::Bpp8)
	{
		for (uint32_t index = 0; index < 256u; index++)
		{
			if ((usage.used_mask[index >> 3u] & (1u << (index & 7u))) == 0)
				continue;
			const uint32_t src = index * 2u;
			packed[packed_entries * 2u + 0u] = raw[src + 0u];
			packed[packed_entries * 2u + 1u] = raw[src + 1u];
			packed_entries++;
		}
	}
	else
	{
		const uint32_t bank = std::min<uint32_t>(palette, 15u);
		const uint32_t bank_base = bank * 32u;
		for (uint32_t index = 0; index < 16u; index++)
		{
			if ((usage.used_mask[index >> 3u] & (1u << (index & 7u))) == 0)
				continue;
			const uint32_t src = bank_base + index * 2u;
			packed[packed_entries * 2u + 0u] = raw[src + 0u];
			packed[packed_entries * 2u + 1u] = raw[src + 1u];
			packed_entries++;
		}
	}

	return rice_crc32_wrapped(packed.data(), packed.size(), 0, packed_entries, 1, 2, packed_entries * 2u);
}

static uint32_t manual_sparse_crc_from_tmem(TextureSize size,
                                            uint32_t palette,
                                            const std::array<uint8_t, 2048> &tmem,
                                            const RDP::detail::HiresCIPaletteUsage &usage)
{
	std::array<uint8_t, 512> packed = {};
	uint32_t packed_entries = 0;

	if (size == TextureSize::Bpp8)
	{
		for (uint32_t index = 0; index < 256u; index++)
		{
			if ((usage.used_mask[index >> 3u] & (1u << (index & 7u))) == 0)
				continue;
			const uint32_t src = index * 8u;
			packed[packed_entries * 2u + 0u] = tmem[src + 0u];
			packed[packed_entries * 2u + 1u] = tmem[src + 1u];
			packed_entries++;
		}
	}
	else
	{
		const uint32_t bank = std::min<uint32_t>(palette, 15u);
		const uint32_t bank_base = bank * 16u * 8u;
		for (uint32_t index = 0; index < 16u; index++)
		{
			if ((usage.used_mask[index >> 3u] & (1u << (index & 7u))) == 0)
				continue;
			const uint32_t src = bank_base + index * 8u;
			packed[packed_entries * 2u + 0u] = tmem[src + 0u];
			packed[packed_entries * 2u + 1u] = tmem[src + 1u];
			packed_entries++;
		}
	}

	return rice_crc32_wrapped(packed.data(), packed.size(), 0, packed_entries, 1, 2, packed_entries * 2u);
}

static uint32_t manual_entry_crc_from_tmem(TextureSize size,
                                           uint32_t palette,
                                           const std::array<uint8_t, 2048> &tmem,
                                           uint32_t entries)
{
	std::array<uint8_t, 512> packed = {};
	uint32_t packed_entries = 0;

	if (size == TextureSize::Bpp8)
	{
		entries = std::min<uint32_t>(entries, 256u);
		for (uint32_t index = 0; index < entries; index++)
		{
			const uint32_t src = index * 8u;
			packed[packed_entries * 2u + 0u] = tmem[src + 0u];
			packed[packed_entries * 2u + 1u] = tmem[src + 1u];
			packed_entries++;
		}
	}
	else
	{
		entries = std::min<uint32_t>(entries, 16u);
		const uint32_t bank = std::min<uint32_t>(palette, 15u);
		const uint32_t bank_base = bank * 16u * 8u;
		for (uint32_t index = 0; index < entries; index++)
		{
			const uint32_t src = bank_base + index * 8u;
			packed[packed_entries * 2u + 0u] = tmem[src + 0u];
			packed[packed_entries * 2u + 1u] = tmem[src + 1u];
			packed_entries++;
		}
	}

	return rice_crc32_wrapped(packed.data(), packed.size(), 0, packed_entries, 1, 2, packed_entries * 2u);
}

static void test_ci8_raw_palette_crc_matches_legacy_contract()
{
	std::array<uint8_t, 512> tlut_shadow = {};
	for (uint32_t i = 0; i < tlut_shadow.size(); i++)
		tlut_shadow[i] = uint8_t((i * 37u + 13u) & 0xffu);

	const std::array<uint8_t, 8> ci8_texels = { 0u, 3u, 7u, 1u, 2u, 6u, 4u, 5u };
	const uint32_t entries = RDP::detail::compute_hires_ci_palette_entry_count(
		TextureSize::Bpp8,
		ci8_texels.data(),
		ci8_texels.size(),
		0,
		4,
		2,
		4);
	check(entries == 8u, "CI8 entry count should follow cimax + 1");

	const uint32_t palette_crc = RDP::detail::compute_hires_ci_palette_crc(
		TextureSize::Bpp8,
		0,
		ci8_texels.data(),
		ci8_texels.size(),
		0,
		4,
		2,
		4,
		tlut_shadow.data(),
		tlut_shadow.size(),
		true);
	const uint32_t expected_crc = rice_crc32_wrapped(
		tlut_shadow.data(),
		tlut_shadow.size(),
		0,
		entries,
		1,
		2,
		512);
	check(palette_crc == expected_crc, "CI8 raw palette CRC should match legacy raw TLUT bytes");

	const auto usage = RDP::detail::compute_hires_ci_palette_usage(
		TextureSize::Bpp8,
		ci8_texels.data(),
		ci8_texels.size(),
		0,
		4,
		2,
		4);
	check(usage.valid, "CI8 usage should be valid");
	check(usage.used_count == 8u, "CI8 usage should contain all eight unique texels");

	const uint32_t sparse_crc = RDP::detail::compute_hires_ci_palette_crc_for_used_indices(
		TextureSize::Bpp8,
		0,
		tlut_shadow.data(),
		tlut_shadow.size(),
		true,
		usage);
	const uint32_t expected_sparse_crc = manual_sparse_crc_from_raw(TextureSize::Bpp8, 0, tlut_shadow, usage);
	check(sparse_crc == expected_sparse_crc, "CI8 sparse CRC should pack only used raw TLUT entries");
}

static void test_ci4_raw_palette_crc_matches_legacy_contract()
{
	std::array<uint8_t, 512> tlut_shadow = {};
	for (uint32_t i = 0; i < tlut_shadow.size(); i++)
		tlut_shadow[i] = uint8_t((i * 19u + 7u) & 0xffu);

	const std::array<uint8_t, 4> ci4_texels = {
		uint8_t((0x1u << 4u) | 0x7u),
		uint8_t((0x2u << 4u) | 0x5u),
		uint8_t((0x6u << 4u) | 0x0u),
		uint8_t((0x4u << 4u) | 0x3u),
	};

	const uint32_t palette = 5u;
	const uint32_t entries = RDP::detail::compute_hires_ci_palette_entry_count(
		TextureSize::Bpp4,
		ci4_texels.data(),
		ci4_texels.size(),
		0,
		4,
		2,
		2);
	check(entries == 8u, "CI4 entry count should follow cimax + 1");

	const uint32_t palette_crc = RDP::detail::compute_hires_ci_palette_crc(
		TextureSize::Bpp4,
		palette,
		ci4_texels.data(),
		ci4_texels.size(),
		0,
		4,
		2,
		2,
		tlut_shadow.data(),
		tlut_shadow.size(),
		true);
	const uint32_t expected_crc = rice_crc32_wrapped(
		tlut_shadow.data(),
		tlut_shadow.size(),
		palette * 32u,
		entries,
		1,
		2,
		32);
	check(palette_crc == expected_crc, "CI4 raw palette CRC should match legacy banked raw TLUT bytes");

	const auto usage = RDP::detail::compute_hires_ci_palette_usage(
		TextureSize::Bpp4,
		ci4_texels.data(),
		ci4_texels.size(),
		0,
		4,
		2,
		2);
	check(usage.valid, "CI4 usage should be valid");
	check(usage.used_count == 8u, "CI4 usage should contain all eight unique texels");

	const uint32_t sparse_crc = RDP::detail::compute_hires_ci_palette_crc_for_used_indices(
		TextureSize::Bpp4,
		palette,
		tlut_shadow.data(),
		tlut_shadow.size(),
		true,
		usage);
	const uint32_t expected_sparse_crc = manual_sparse_crc_from_raw(TextureSize::Bpp4, palette, tlut_shadow, usage);
	check(sparse_crc == expected_sparse_crc, "CI4 sparse CRC should pack only used raw TLUT entries");
}

static void test_ci4_row_bytes_round_up_for_odd_width()
{
	check(RDP::detail::compute_hires_texture_row_bytes(0, TextureSize::Bpp4) == 0u,
	      "CI4 row bytes should keep zero-width textures at zero bytes");
	check(RDP::detail::compute_hires_texture_row_bytes(1, TextureSize::Bpp4) == 1u,
	      "CI4 row bytes should round width=1 up to one byte");
	check(RDP::detail::compute_hires_texture_row_bytes(3, TextureSize::Bpp4) == 2u,
	      "CI4 row bytes should round odd widths up instead of truncating");
	check(RDP::detail::compute_hires_texture_row_bytes(5, TextureSize::Bpp4) == 3u,
	      "CI4 row bytes should keep rounding odd widths up");
	check(RDP::detail::compute_hires_texture_row_bytes(3, TextureSize::Bpp8) == 3u,
	      "CI8 row bytes should stay width-sized");
}

static void test_ci4_odd_width_stride_reaches_second_row_palette_indices()
{
	const std::array<uint8_t, 4> ci4_texels = {
		uint8_t((0x1u << 4u) | 0x2u),
		uint8_t((0x3u << 4u) | 0x0u),
		uint8_t((0x4u << 4u) | 0x5u),
		uint8_t((0xfu << 4u) | 0x0u),
	};

	const uint32_t row_stride = RDP::detail::compute_hires_texture_row_bytes(3u, TextureSize::Bpp4);
	check(row_stride == 2u, "CI4 odd-width textures should reserve two bytes per row");

	const auto usage = RDP::detail::compute_hires_ci_palette_usage(
		TextureSize::Bpp4,
		ci4_texels.data(),
		ci4_texels.size(),
		0,
		3,
		2,
		row_stride);
	check(usage.valid, "CI4 odd-width usage should remain valid");
	check(usage.max_index == 15u, "CI4 odd-width usage should scan the second row at the rounded stride");

	const uint32_t entries = RDP::detail::compute_hires_ci_palette_entry_count(
		TextureSize::Bpp4,
		ci4_texels.data(),
		ci4_texels.size(),
		0,
		3,
		2,
		row_stride);
	check(entries == 16u, "CI4 odd-width entry count should reflect second-row max index coverage");
}

static void test_tmem_palette_crc_tracks_sampled_object_view()
{
	std::array<uint8_t, 512> tlut_shadow = {};
	for (uint32_t i = 0; i < tlut_shadow.size(); i++)
		tlut_shadow[i] = uint8_t((i * 41u + 3u) & 0xffu);

	const auto tlut_tmem_shadow = build_tlut_tmem_shadow(tlut_shadow, 0);

	const std::array<uint8_t, 8> ci8_texels = { 0u, 3u, 7u, 1u, 2u, 6u, 4u, 5u };
	const auto usage = RDP::detail::compute_hires_ci_palette_usage_tmem(
		TextureSize::Bpp8,
		ci8_texels.data(),
		ci8_texels.size(),
		0,
		4,
		2,
		4);
	const uint32_t entries = RDP::detail::compute_hires_ci_palette_entry_count_tmem(
		TextureSize::Bpp8,
		ci8_texels.data(),
		ci8_texels.size(),
		0,
		4,
		2,
		4);
	check(entries == 8u, "TMEM CI8 entry count should follow max sampled index");
	check(usage.valid && usage.used_count == 8u, "TMEM CI8 usage should contain all eight unique texels");

	const uint32_t entry_crc = RDP::detail::compute_hires_ci_palette_crc_for_entries_tmem(
		TextureSize::Bpp8,
		0,
		tlut_tmem_shadow.data(),
		tlut_tmem_shadow.size(),
		true,
		entries);
	const uint32_t sparse_crc = RDP::detail::compute_hires_ci_palette_crc_for_used_indices_tmem(
		TextureSize::Bpp8,
		0,
		tlut_tmem_shadow.data(),
		tlut_tmem_shadow.size(),
		true,
		usage);

	const uint32_t expected_entry_crc_contiguous = manual_entry_crc_from_tmem(
		TextureSize::Bpp8,
		0,
		tlut_tmem_shadow,
		entries);
	const uint32_t expected_sparse_crc = manual_sparse_crc_from_tmem(
		TextureSize::Bpp8,
		0,
		tlut_tmem_shadow,
		usage);

	check(entry_crc == expected_entry_crc_contiguous, "TMEM entry CRC should hash the sampled-object TLUT view");
	check(sparse_crc == expected_sparse_crc, "TMEM sparse CRC should hash only used sampled-object TLUT entries");

	const uint32_t raw_entry_crc = RDP::detail::compute_hires_ci_palette_crc_for_entries(
		TextureSize::Bpp8,
		0,
		tlut_shadow.data(),
		tlut_shadow.size(),
		true,
		entries);
	check(raw_entry_crc != entry_crc, "raw and TMEM palette CRCs should remain distinct for the same upload bytes");
}
}

int main()
{
	test_ci8_raw_palette_crc_matches_legacy_contract();
	test_ci4_raw_palette_crc_matches_legacy_contract();
	test_ci4_row_bytes_round_up_for_odd_width();
	test_ci4_odd_width_stride_reaches_second_row_palette_indices();
	test_tmem_palette_crc_tracks_sampled_object_view();

	std::cout << "emu_unit_hires_ci_palette_policy_test: PASS" << std::endl;
	return 0;
}
