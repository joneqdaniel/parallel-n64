#include "texture_replacement.hpp"
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>
#include <unistd.h>
#include <zlib.h>

using namespace RDP;

namespace
{
constexpr int32_t TXCACHE_FORMAT_VERSION = 0x08000000;
constexpr uint32_t GL_RGBA8 = 0x8058;
constexpr uint16_t GL_RGBA = 0x1908;
constexpr uint16_t GL_UNSIGNED_BYTE = 0x1401;

static void check(bool condition, const char *message)
{
	if (!condition)
	{
		std::cerr << "FAIL: " << message << std::endl;
		std::exit(1);
	}
}

template <typename T>
static void write_value(std::ofstream &file, const T &value)
{
	file.write(reinterpret_cast<const char *>(&value), sizeof(value));
}

static void write_record_htc(gzFile fp, uint64_t checksum64, uint16_t formatsize,
                             uint32_t width, uint32_t height, const std::vector<uint8_t> &rgba)
{
	const uint32_t data_size = static_cast<uint32_t>(rgba.size());
	const uint8_t is_hires = 1;
	const int32_t format = static_cast<int32_t>(GL_RGBA8);
	const uint16_t texture_format = GL_RGBA;
	const uint16_t pixel_type = GL_UNSIGNED_BYTE;

	gzwrite(fp, &checksum64, sizeof(checksum64));
	gzwrite(fp, &width, sizeof(width));
	gzwrite(fp, &height, sizeof(height));
	gzwrite(fp, &format, sizeof(format));
	gzwrite(fp, &texture_format, sizeof(texture_format));
	gzwrite(fp, &pixel_type, sizeof(pixel_type));
	gzwrite(fp, &is_hires, sizeof(is_hires));
	gzwrite(fp, &formatsize, sizeof(formatsize));
	gzwrite(fp, &data_size, sizeof(data_size));
	gzwrite(fp, rgba.data(), static_cast<unsigned>(rgba.size()));
}

static void write_fixture_htc(const std::filesystem::path &path, uint64_t key_exact, uint16_t fs_exact,
                              uint64_t key_wildcard, const std::vector<uint8_t> &rgba)
{
	gzFile fp = gzopen(path.c_str(), "wb");
	check(fp != nullptr, "failed to create fixture .htc");

	const int32_t version = TXCACHE_FORMAT_VERSION;
	const int32_t config = 0;
	gzwrite(fp, &version, sizeof(version));
	gzwrite(fp, &config, sizeof(config));

	write_record_htc(fp, key_exact, fs_exact, 2, 1, rgba);
	write_record_htc(fp, key_wildcard, 0, 1, 1, { 0xff, 0x80, 0x10, 0x20 });
	gzclose(fp);
}

static void write_fixture_hts(const std::filesystem::path &path, uint64_t key, uint16_t formatsize,
                              const std::vector<uint8_t> &rgba)
{
	std::ofstream file(path, std::ofstream::binary);
	check(file.good(), "failed to create fixture .hts");

	const int32_t version = TXCACHE_FORMAT_VERSION;
	const int32_t config = 0;
	int64_t storage_pos = 0;
	write_value(file, version);
	write_value(file, config);
	write_value(file, storage_pos);

	const int64_t record_offset = static_cast<int64_t>(file.tellp());
	const uint32_t width = 2;
	const uint32_t height = 1;
	const int32_t format = static_cast<int32_t>(GL_RGBA8);
	const uint16_t texture_format = GL_RGBA;
	const uint16_t pixel_type = GL_UNSIGNED_BYTE;
	const uint8_t is_hires = 1;
	const uint32_t data_size = static_cast<uint32_t>(rgba.size());

	write_value(file, width);
	write_value(file, height);
	write_value(file, format);
	write_value(file, texture_format);
	write_value(file, pixel_type);
	write_value(file, is_hires);
	write_value(file, formatsize);
	write_value(file, data_size);
	file.write(reinterpret_cast<const char *>(rgba.data()), static_cast<std::streamsize>(rgba.size()));

	storage_pos = static_cast<int64_t>(file.tellp());
	const int32_t storage_size = 1;
	write_value(file, storage_size);

	const uint64_t packed_u64 =
	    (static_cast<uint64_t>(formatsize) << 48) | (static_cast<uint64_t>(record_offset) & 0x0000ffffffffffffull);
	const int64_t packed_i64 = static_cast<int64_t>(packed_u64);
	write_value(file, key);
	write_value(file, packed_i64);

	file.seekp(sizeof(int32_t) * 2, std::ofstream::beg);
	write_value(file, storage_pos);
}
}

int main()
{
	const uint64_t key_htc = 0x1122334455667788ull;
	const uint64_t key_hts = 0x2233445566778899ull;
	const uint64_t key_wildcard = 0x33445566778899aall;
	const uint16_t formatsize = 0x0201;
	const std::vector<uint8_t> rgba = { 0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80 };

	const auto temp_root = std::filesystem::temp_directory_path();
	const auto test_dir = temp_root / ("parallel_n64_m3_provider_test_" + std::to_string(getpid()));
	std::filesystem::remove_all(test_dir);
	std::filesystem::create_directories(test_dir);
	write_fixture_htc(test_dir / "fixture.htc", key_htc, formatsize, key_wildcard, rgba);
	write_fixture_hts(test_dir / "fixture.hts", key_hts, formatsize, rgba);

	ReplacementProvider provider;
	provider.set_enabled(true);
	check(provider.load_cache_dir(test_dir.string()), "failed to load fixture cache directory");
	check(provider.entry_count() > 0, "no hi-res cache entries found");

	ReplacementMeta meta = {};
	check(provider.lookup(key_htc, formatsize, &meta), "expected .htc key not found");
	check(meta.repl_w > 0 && meta.repl_h > 0, "invalid replacement dimensions");

	ReplacementImage image = {};
	check(provider.decode_rgba8(key_htc, formatsize, &image), "failed to decode .htc replacement");
	check(image.meta.repl_w == meta.repl_w && image.meta.repl_h == meta.repl_h, "meta mismatch after decode");
	check(!image.rgba8.empty(), "decoded image is empty");
	check(image.rgba8 == rgba, "decoded .htc RGBA mismatch");

	ReplacementImage image_hts = {};
	check(provider.decode_rgba8(key_hts, formatsize, &image_hts), "failed to decode .hts replacement");
	check(image_hts.rgba8 == rgba, "decoded .hts RGBA mismatch");

	ReplacementMeta wildcard_meta = {};
	check(provider.lookup(key_wildcard, 0x9999, &wildcard_meta), "formatsize wildcard fallback failed");
	check(wildcard_meta.repl_w == 1 && wildcard_meta.repl_h == 1, "wildcard dimensions mismatch");

	const size_t expected_size = size_t(image.meta.repl_w) * size_t(image.meta.repl_h) * 4u;
	check(image.rgba8.size() == expected_size, "decoded image does not match RGBA8 size");

	provider.set_enabled(false);
	check(!provider.lookup(key_htc, formatsize, &meta), "disabled provider should not match");

	provider.clear();
	check(provider.entry_count() == 0, "provider clear should remove all loaded entries");
	check(!provider.lookup(key_htc, formatsize, &meta), "cleared provider should not match");
	check(!provider.decode_rgba8(key_htc, formatsize, &image), "cleared provider should not decode entries");

	provider.set_enabled(true);
	check(provider.load_cache_dir(test_dir.string()), "provider should reload fixtures after clear");
	check(provider.lookup(key_htc, formatsize, &meta), "reloaded provider should match expected key");

	std::filesystem::remove_all(test_dir);
	std::cout << "hires_replacement_provider_test: PASS (entries=" << provider.entry_count() << ")" << std::endl;
	return 0;
}
