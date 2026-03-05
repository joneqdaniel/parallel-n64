#include "texture_keying.hpp"
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <vector>

using namespace RDP;

static void check(bool condition, const char *message)
{
	if (!condition)
	{
		std::cerr << "FAIL: " << message << std::endl;
		std::exit(1);
	}
}

static uint32_t reference_crc32_wrapped(const uint8_t *rdram, size_t rdram_size, uint32_t base_addr,
                                        uint32_t width, uint32_t height, uint32_t size, uint32_t row_stride)
{
	if (!rdram || rdram_size == 0 || width == 0 || height == 0)
		return 0;

	const uint32_t bytes_per_line = (width << size) >> 1;
	if (bytes_per_line < 4)
		return 0;

	uint32_t crc = 0;
	uint32_t line = 0;
	for (int y = int(height) - 1; y >= 0; y--, line++)
	{
		uint32_t esi = 0;
		const uint32_t row_addr = (base_addr + line * row_stride) & uint32_t(rdram_size - 1);
		for (int x = int(bytes_per_line) - 4; x >= 0; x -= 4)
		{
			uint32_t v = 0;
			v |= uint32_t(rdram[(row_addr + uint32_t(x) + 0) & uint32_t(rdram_size - 1)]) << 0;
			v |= uint32_t(rdram[(row_addr + uint32_t(x) + 1) & uint32_t(rdram_size - 1)]) << 8;
			v |= uint32_t(rdram[(row_addr + uint32_t(x) + 2) & uint32_t(rdram_size - 1)]) << 16;
			v |= uint32_t(rdram[(row_addr + uint32_t(x) + 3) & uint32_t(rdram_size - 1)]) << 24;
			esi = v ^ uint32_t(x);
			crc = (crc << 4) + ((crc >> 28) & 15);
			crc += esi;
		}

		esi ^= uint32_t(y);
		crc += esi;
	}

	return crc;
}

int main()
{
	check(formatsize_key(TextureFormat::CI, TextureSize::Bpp8) == 258, "formatsize_key CI8 mismatch");
	check(formatsize_key(TextureFormat::RGBA, TextureSize::Bpp32) == 768, "formatsize_key RGBA32 mismatch");

	std::vector<uint8_t> rdram(8);
	for (uint32_t i = 0; i < rdram.size(); i++)
		rdram[i] = uint8_t(i);

	check(wrapped_read_u8(rdram.data(), rdram.size(), 9) == 1, "wrapped_read_u8 did not wrap");
	check(wrapped_read_u32(rdram.data(), rdram.size(), 6) == 0x01000706u, "wrapped_read_u32 mismatch");

	check(rice_crc32_wrapped(rdram.data(), rdram.size(), 0, 1, 1, 1, 1) == 0, "crc should be zero for narrow rows");

	std::vector<uint8_t> crc_buf(32);
	for (uint32_t i = 0; i < crc_buf.size(); i++)
		crc_buf[i] = uint8_t((i * 7u) & 0xffu);

	const uint32_t crc_impl = rice_crc32_wrapped(crc_buf.data(), crc_buf.size(), 2, 4, 3, 1, 8);
	const uint32_t crc_ref = reference_crc32_wrapped(crc_buf.data(), crc_buf.size(), 2, 4, 3, 1, 8);
	check(crc_impl == crc_ref, "rice_crc32_wrapped mismatch vs reference");

	std::vector<uint8_t> ci8(16, 0);
	ci8[3] = 0x7f;
	ci8[5] = 0xc1;
	ci8[12] = 0x9a;
	check(compute_ci8_max_index(ci8.data(), ci8.size(), 0, 8, 2, 8) == 0xc1, "compute_ci8_max_index mismatch");

	std::vector<uint8_t> ci4(8, 0);
	ci4[0] = 0x17;
	ci4[1] = 0xe2;
	ci4[2] = 0x4b;
	check(compute_ci4_max_index(ci4.data(), ci4.size(), 0, 6, 1, 3) == 0xe, "compute_ci4_max_index mismatch");

	std::cout << "hires_keying_test: PASS" << std::endl;
	return 0;
}
