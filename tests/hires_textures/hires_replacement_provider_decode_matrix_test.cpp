#include "texture_replacement.hpp"

#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <string>
#include <unistd.h>
#include <vector>
#include <zlib.h>

using namespace RDP;

namespace
{
constexpr int32_t TXCACHE_FORMAT_VERSION = 0x08000000;
constexpr uint32_t GL_TEXFMT_GZ = 0x80000000u;

constexpr uint32_t GL_RGB8 = 0x8051;
constexpr uint32_t GL_RGBA8 = 0x8058;

constexpr uint16_t GL_RGB = 0x1907;
constexpr uint16_t GL_RGBA = 0x1908;
constexpr uint16_t GL_LUMINANCE = 0x1909;

constexpr uint16_t GL_UNSIGNED_BYTE = 0x1401;
constexpr uint16_t GL_UNSIGNED_SHORT_4_4_4_4 = 0x8033;
constexpr uint16_t GL_UNSIGNED_SHORT_5_5_5_1 = 0x8034;
constexpr uint16_t GL_UNSIGNED_SHORT_5_6_5 = 0x8363;

struct HtcRecord
{
	uint64_t checksum64 = 0;
	uint16_t formatsize = 0;
	uint32_t width = 0;
	uint32_t height = 0;
	uint32_t format = GL_RGBA8;
	uint16_t texture_format = GL_RGBA;
	uint16_t pixel_type = GL_UNSIGNED_BYTE;
	bool is_hires = true;
	std::vector<uint8_t> blob;
};

static void check(bool condition, const char *message)
{
	if (!condition)
	{
		std::cerr << "FAIL: " << message << std::endl;
		std::exit(1);
	}
}

static std::vector<uint8_t> compress_blob(const std::vector<uint8_t> &input)
{
	uLongf out_bound = compressBound(static_cast<uLong>(input.size()));
	std::vector<uint8_t> out(out_bound);
	const int ret = compress2(out.data(), &out_bound, input.data(), static_cast<uLong>(input.size()), Z_BEST_COMPRESSION);
	check(ret == Z_OK, "compress2 failed");
	out.resize(static_cast<size_t>(out_bound));
	return out;
}

static void write_record_htc(gzFile fp, const HtcRecord &record)
{
	const uint8_t is_hires = record.is_hires ? 1 : 0;
	const uint32_t data_size = static_cast<uint32_t>(record.blob.size());

	gzwrite(fp, &record.checksum64, sizeof(record.checksum64));
	gzwrite(fp, &record.width, sizeof(record.width));
	gzwrite(fp, &record.height, sizeof(record.height));
	gzwrite(fp, &record.format, sizeof(record.format));
	gzwrite(fp, &record.texture_format, sizeof(record.texture_format));
	gzwrite(fp, &record.pixel_type, sizeof(record.pixel_type));
	gzwrite(fp, &is_hires, sizeof(is_hires));
	gzwrite(fp, &record.formatsize, sizeof(record.formatsize));
	gzwrite(fp, &data_size, sizeof(data_size));
	if (!record.blob.empty())
		gzwrite(fp, record.blob.data(), static_cast<unsigned>(record.blob.size()));
}

static void write_htc(const std::filesystem::path &path, const std::vector<HtcRecord> &records)
{
	gzFile fp = gzopen(path.c_str(), "wb");
	check(fp != nullptr, "failed to create .htc fixture");

	const int32_t version = TXCACHE_FORMAT_VERSION;
	const int32_t config = 0;
	gzwrite(fp, &version, sizeof(version));
	gzwrite(fp, &config, sizeof(config));

	for (const auto &record : records)
		write_record_htc(fp, record);

	gzclose(fp);
}

static void write_truncated_htc(const std::filesystem::path &path)
{
	gzFile fp = gzopen(path.c_str(), "wb");
	check(fp != nullptr, "failed to create truncated .htc fixture");

	const int32_t version = TXCACHE_FORMAT_VERSION;
	const int32_t config = 0;
	gzwrite(fp, &version, sizeof(version));
	gzwrite(fp, &config, sizeof(config));

	const uint32_t partial_checksum = 0xaabbccddu;
	gzwrite(fp, &partial_checksum, sizeof(partial_checksum));
	gzclose(fp);
}

static ReplacementImage decode_or_die(const ReplacementProvider &provider, uint64_t key, uint16_t formatsize)
{
	ReplacementImage image = {};
	check(provider.decode_rgba8(key, formatsize, &image), "decode_rgba8 failed for expected key");
	return image;
}

static std::filesystem::path make_temp_dir(const char *prefix)
{
	const auto root = std::filesystem::temp_directory_path();
	const auto dir = root / (std::string(prefix) + "_" + std::to_string(getpid()));
	std::filesystem::remove_all(dir);
	std::filesystem::create_directories(dir);
	return dir;
}

static void test_decode_matrix_and_compressed_payloads()
{
	const auto dir = make_temp_dir("parallel_n64_hires_decode_matrix");

	const uint64_t key_rgba8 = 0x1000ull;
	const uint64_t key_rgb8 = 0x1001ull;
	const uint64_t key_rgb565 = 0x1002ull;
	const uint64_t key_rgba5551 = 0x1003ull;
	const uint64_t key_rgba4444 = 0x1004ull;
	const uint64_t key_luma = 0x1005ull;
	const uint64_t key_rgba8_gz = 0x1006ull;
	const uint16_t fs = 0x0201;

	const std::vector<uint8_t> rgba8 = { 0x10, 0x20, 0x30, 0x40, 0x90, 0xa0, 0xb0, 0xc0 };
	const std::vector<uint8_t> rgb8 = { 0x11, 0x22, 0x33, 0x80, 0x90, 0xa0 };
	const std::vector<uint8_t> rgb565 = { 0x00, 0xf8, 0xe0, 0x07 };
	const std::vector<uint8_t> rgba5551 = { 0x3f, 0x00, 0x00, 0xf8 };
	const std::vector<uint8_t> rgba4444 = { 0xcd, 0xab, 0x23, 0x01 };
	const std::vector<uint8_t> luma8 = { 0x10, 0x80 };
	const std::vector<uint8_t> rgba8_gz_src = { 0xaa, 0xbb, 0xcc, 0xdd, 0x01, 0x02, 0x03, 0x04 };

	std::vector<HtcRecord> records;
	records.push_back({ key_rgba8, fs, 2, 1, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, true, rgba8 });
	records.push_back({ key_rgb8, fs, 2, 1, GL_RGB8, GL_RGB, GL_UNSIGNED_BYTE, true, rgb8 });
	records.push_back({ key_rgb565, fs, 2, 1, GL_RGB8, GL_RGB, GL_UNSIGNED_SHORT_5_6_5, true, rgb565 });
	records.push_back({ key_rgba5551, fs, 2, 1, GL_RGBA8, GL_RGBA, GL_UNSIGNED_SHORT_5_5_5_1, true, rgba5551 });
	records.push_back({ key_rgba4444, fs, 2, 1, GL_RGBA8, GL_RGBA, GL_UNSIGNED_SHORT_4_4_4_4, true, rgba4444 });
	records.push_back({ key_luma, fs, 2, 1, GL_RGB8, GL_LUMINANCE, GL_UNSIGNED_BYTE, true, luma8 });
	records.push_back({ key_rgba8_gz,
	                   fs,
	                   2,
	                   1,
	                   GL_RGBA8 | GL_TEXFMT_GZ,
	                   GL_RGBA,
	                   GL_UNSIGNED_BYTE,
	                   true,
	                   compress_blob(rgba8_gz_src) });

	write_htc(dir / "decode_matrix.htc", records);

	ReplacementProvider provider;
	provider.set_enabled(true);
	check(provider.load_cache_dir(dir.string()), "failed to load decode matrix cache dir");

	check(decode_or_die(provider, key_rgba8, fs).rgba8 == rgba8, "RGBA8 decode mismatch");

	const std::vector<uint8_t> expected_rgb8 = {
		0x11, 0x22, 0x33, 0xff,
		0x80, 0x90, 0xa0, 0xff,
	};
	check(decode_or_die(provider, key_rgb8, fs).rgba8 == expected_rgb8, "RGB8 decode mismatch");

	const std::vector<uint8_t> expected_rgb565 = {
		0xff, 0x00, 0x00, 0xff,
		0x00, 0xff, 0x00, 0xff,
	};
	check(decode_or_die(provider, key_rgb565, fs).rgba8 == expected_rgb565, "RGB565 decode mismatch");

	const std::vector<uint8_t> expected_rgba5551 = {
		0x00, 0x00, 0xff, 0xff,
		0xff, 0x00, 0x00, 0x00,
	};
	check(decode_or_die(provider, key_rgba5551, fs).rgba8 == expected_rgba5551, "RGBA5551 decode mismatch");

	const std::vector<uint8_t> expected_rgba4444 = {
		0xaa, 0xbb, 0xcc, 0xdd,
		0x00, 0x11, 0x22, 0x33,
	};
	check(decode_or_die(provider, key_rgba4444, fs).rgba8 == expected_rgba4444, "RGBA4444 decode mismatch");

	const std::vector<uint8_t> expected_luma = {
		0x10, 0x10, 0x10, 0xff,
		0x80, 0x80, 0x80, 0xff,
	};
	check(decode_or_die(provider, key_luma, fs).rgba8 == expected_luma, "LUMINANCE decode mismatch");

	check(decode_or_die(provider, key_rgba8_gz, fs).rgba8 == rgba8_gz_src, "compressed RGBA8 decode mismatch");

	std::filesystem::remove_all(dir);
}

static void test_lookup_precedence_exact_vs_wildcard()
{
	const auto dir = make_temp_dir("parallel_n64_hires_precedence");

	const uint64_t key = 0x5566778899aabbccull;
	const uint16_t fs_exact = 0x1234;
	const uint8_t px_red[4] = { 0xff, 0x00, 0x00, 0xff };
	const uint8_t px_blue[4] = { 0x00, 0x00, 0xff, 0xff };
	const uint8_t px_green[4] = { 0x00, 0xff, 0x00, 0xff };

	write_htc(dir / "a_base.htc", { HtcRecord{ key, fs_exact, 1, 1, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, true, std::vector<uint8_t>(px_red, px_red + 4) } });
	write_htc(dir / "b_wildcard.htc", { HtcRecord{ key, 0, 1, 1, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, true, std::vector<uint8_t>(px_blue, px_blue + 4) } });
	write_htc(dir / "c_override.htc", { HtcRecord{ key, fs_exact, 1, 1, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, true, std::vector<uint8_t>(px_green, px_green + 4) } });

	ReplacementProvider provider;
	provider.set_enabled(true);
	check(provider.load_cache_dir(dir.string()), "failed to load precedence fixtures");

	check(decode_or_die(provider, key, fs_exact).rgba8 == std::vector<uint8_t>(px_green, px_green + 4),
	      "latest exact formatsize entry should win for exact lookup");
	check(decode_or_die(provider, key, 0x9999).rgba8 == std::vector<uint8_t>(px_blue, px_blue + 4),
	      "wildcard entry should satisfy non-matching formatsize lookup");

	std::filesystem::remove_all(dir);
}

static void test_malformed_files_do_not_block_valid_entries_and_missing_dir_clears_state()
{
	const auto dir = make_temp_dir("parallel_n64_hires_malformed");
	const uint64_t good_key = 0xfeedfacecafebeefull;
	const uint16_t fs = 0x0201;
	const std::vector<uint8_t> rgba = { 0xde, 0xad, 0xbe, 0xef };

	write_htc(dir / "good.HTC", { HtcRecord{ good_key, fs, 1, 1, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, true, rgba } });
	write_truncated_htc(dir / "bad.htc");

	ReplacementProvider provider;
	provider.set_enabled(true);
	check(provider.load_cache_dir(dir.string()), "valid entries should still load even when one cache file is malformed");
	check(provider.entry_count() == 1, "malformed file should not inject extra entries");
	check(decode_or_die(provider, good_key, fs).rgba8 == rgba, "valid entry decode failed after malformed neighbor file");

	const auto missing = dir / "missing-cache-dir";
	check(!provider.load_cache_dir(missing.string()), "missing cache directory should fail load");
	check(provider.entry_count() == 0, "failed load should clear stale entries");

	ReplacementImage image = {};
	check(!provider.decode_rgba8(good_key, fs, &image), "decode should fail after cache clear on failed load");

	std::filesystem::remove_all(dir);
}
}

int main()
{
	test_decode_matrix_and_compressed_payloads();
	test_lookup_precedence_exact_vs_wildcard();
	test_malformed_files_do_not_block_valid_entries_and_missing_dir_clears_state();

	std::cout << "hires_replacement_provider_decode_matrix_test: PASS" << std::endl;
	return 0;
}
