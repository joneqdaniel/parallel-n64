#include "texture_replacement.hpp"

#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
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

constexpr uint16_t GL_UNSIGNED_BYTE = 0x1401;

struct HtsRecord
{
	uint64_t checksum64 = 0;
	uint16_t index_formatsize = 0;
	uint16_t record_formatsize = 0;
	uint32_t width = 0;
	uint32_t height = 0;
	uint32_t format = GL_RGBA8;
	uint16_t texture_format = GL_RGBA;
	uint16_t pixel_type = GL_UNSIGNED_BYTE;
	bool is_hires = true;
	std::vector<uint8_t> blob;
};

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

template <typename T>
static void write_value(std::ofstream &file, const T &value)
{
	file.write(reinterpret_cast<const char *>(&value), sizeof(value));
}

static std::filesystem::path make_temp_dir(const char *prefix)
{
	const auto root = std::filesystem::temp_directory_path();
	const auto dir = root / (std::string(prefix) + "_" + std::to_string(getpid()));
	std::filesystem::remove_all(dir);
	std::filesystem::create_directories(dir);
	return dir;
}

static void write_hts_new(const std::filesystem::path &path,
                          const std::vector<HtsRecord> &records,
                          bool add_invalid_index_entry)
{
	std::ofstream file(path, std::ofstream::binary);
	check(file.good(), "failed to create new-format .hts fixture");

	const int32_t version = TXCACHE_FORMAT_VERSION;
	const int32_t config = 0;
	int64_t storage_pos = 0;
	write_value(file, version);
	write_value(file, config);
	write_value(file, storage_pos);

	std::vector<int64_t> offsets;
	offsets.reserve(records.size());
	for (const auto &record : records)
	{
		offsets.push_back(static_cast<int64_t>(file.tellp()));
		const uint8_t is_hires = record.is_hires ? 1 : 0;
		const uint32_t data_size = static_cast<uint32_t>(record.blob.size());

		write_value(file, record.width);
		write_value(file, record.height);
		write_value(file, record.format);
		write_value(file, record.texture_format);
		write_value(file, record.pixel_type);
		write_value(file, is_hires);
		write_value(file, record.record_formatsize);
		write_value(file, data_size);
		if (!record.blob.empty())
			file.write(reinterpret_cast<const char *>(record.blob.data()), static_cast<std::streamsize>(record.blob.size()));
	}

	const int64_t invalid_offset = static_cast<int64_t>(file.tellp()) + 0x400;
	storage_pos = static_cast<int64_t>(file.tellp());
	const int32_t storage_size = static_cast<int32_t>(records.size() + (add_invalid_index_entry ? 1 : 0));
	write_value(file, storage_size);

	for (size_t i = 0; i < records.size(); i++)
	{
		const auto &record = records[i];
		const uint64_t packed_u64 = (static_cast<uint64_t>(record.index_formatsize) << 48) |
		                            (static_cast<uint64_t>(offsets[i]) & 0x0000ffffffffffffull);
		const int64_t packed_i64 = static_cast<int64_t>(packed_u64);
		write_value(file, record.checksum64);
		write_value(file, packed_i64);
	}

	if (add_invalid_index_entry)
	{
		const uint64_t invalid_key = 0x9999888877776666ull;
		const uint64_t packed_u64 = static_cast<uint64_t>(invalid_offset) & 0x0000ffffffffffffull;
		const int64_t packed_i64 = static_cast<int64_t>(packed_u64);
		write_value(file, invalid_key);
		write_value(file, packed_i64);
	}

	file.seekp(sizeof(int32_t) * 2, std::ofstream::beg);
	write_value(file, storage_pos);
}

static void write_hts_old(const std::filesystem::path &path, const HtsRecord &record)
{
	std::ofstream file(path, std::ofstream::binary);
	check(file.good(), "failed to create old-format .hts fixture");

	const int32_t old_version = 0x07000000;
	int64_t storage_pos = 0;
	write_value(file, old_version);
	write_value(file, storage_pos);

	const int64_t record_offset = static_cast<int64_t>(file.tellp());
	const uint8_t is_hires = record.is_hires ? 1 : 0;
	const uint32_t data_size = static_cast<uint32_t>(record.blob.size());

	write_value(file, record.width);
	write_value(file, record.height);
	write_value(file, record.format);
	write_value(file, record.texture_format);
	write_value(file, record.pixel_type);
	write_value(file, is_hires);
	write_value(file, data_size);
	if (!record.blob.empty())
		file.write(reinterpret_cast<const char *>(record.blob.data()), static_cast<std::streamsize>(record.blob.size()));

	storage_pos = static_cast<int64_t>(file.tellp());
	const int32_t storage_size = 1;
	write_value(file, storage_size);

	const uint64_t packed_u64 = (static_cast<uint64_t>(record.index_formatsize) << 48) |
	                            (static_cast<uint64_t>(record_offset) & 0x0000ffffffffffffull);
	const int64_t packed_i64 = static_cast<int64_t>(packed_u64);
	write_value(file, record.checksum64);
	write_value(file, packed_i64);

	file.seekp(sizeof(int32_t), std::ofstream::beg);
	write_value(file, storage_pos);
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

	gzclose(fp);
}

static void write_htc_old(const std::filesystem::path &path, const std::vector<HtcRecord> &records)
{
	gzFile fp = gzopen(path.c_str(), "wb");
	check(fp != nullptr, "failed to create old .htc fixture");

	const int32_t old_version = 0x07000000;
	gzwrite(fp, &old_version, sizeof(old_version));

	for (const auto &record : records)
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
		gzwrite(fp, &data_size, sizeof(data_size));
		if (!record.blob.empty())
			gzwrite(fp, record.blob.data(), static_cast<unsigned>(record.blob.size()));
	}

	gzclose(fp);
}

static void test_hts_formatsize_fallback_and_invalid_offsets()
{
	const auto dir = make_temp_dir("parallel_n64_hires_hts_new");
	const uint64_t key_from_record_fs = 0x1010ull;
	const uint64_t key_from_index_fs = 0x1011ull;

	const std::vector<HtsRecord> records = {
		{ key_from_record_fs, 0, 0x2201, 1, 1, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, true, { 0x11, 0x22, 0x33, 0x44 } },
		{ key_from_index_fs, 0x3301, 0x9999, 1, 1, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, true, { 0x55, 0x66, 0x77, 0x88 } },
	};

	write_hts_new(dir / "new_format.hts", records, true);

	ReplacementProvider provider;
	provider.set_enabled(true);
	check(provider.load_cache_dir(dir.string()), "failed to load new-format .hts fixture");
	check(provider.entry_count() == 2, "invalid index entries should be skipped");

	ReplacementImage image = {};
	check(provider.decode_rgba8(key_from_record_fs, 0x2201, &image), "record formatsize fallback decode failed");
	check(image.rgba8 == std::vector<uint8_t>({ 0x11, 0x22, 0x33, 0x44 }), "record formatsize fallback payload mismatch");

	check(provider.decode_rgba8(key_from_index_fs, 0x3301, &image), "index formatsize decode failed");
	check(image.rgba8 == std::vector<uint8_t>({ 0x55, 0x66, 0x77, 0x88 }), "index formatsize payload mismatch");
	check(!provider.decode_rgba8(key_from_index_fs, 0x9999, &image), "index formatsize should win over record formatsize");

	std::filesystem::remove_all(dir);
}

static void test_old_version_hts_parsing()
{
	const auto dir = make_temp_dir("parallel_n64_hires_hts_old");
	const uint64_t key = 0xabcdef01ull;
	const uint16_t formatsize = 0x4402;
	const std::vector<uint8_t> payload = { 0xa0, 0xb0, 0xc0, 0xd0 };

	write_hts_old(dir / "old_format.hts", HtsRecord{ key, formatsize, 0, 1, 1, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, true, payload });

	ReplacementProvider provider;
	provider.set_enabled(true);
	check(provider.load_cache_dir(dir.string()), "failed to load old-format .hts fixture");

	ReplacementImage image = {};
	check(provider.decode_rgba8(key, formatsize, &image), "old-format .hts decode failed");
	check(image.rgba8 == payload, "old-format .hts payload mismatch");

	std::filesystem::remove_all(dir);
}

static void test_decode_failures_are_stable_for_corrupt_entries()
{
	const auto dir = make_temp_dir("parallel_n64_hires_decode_failures");
	const uint64_t key_bad_gz = 0x2200ull;
	const uint64_t key_short_rgb = 0x2201ull;
	const uint16_t fs = 0x1001;

	const std::vector<HtcRecord> records = {
		{ key_bad_gz, fs, 2, 1, GL_RGBA8 | GL_TEXFMT_GZ, GL_RGBA, GL_UNSIGNED_BYTE, true, { 0x01, 0x02, 0x03 } },
		{ key_short_rgb, fs, 2, 1, GL_RGB8, GL_RGB, GL_UNSIGNED_BYTE, true, { 0x10, 0x20, 0x30 } },
	};
	write_htc(dir / "decode_failures.htc", records);

	ReplacementProvider provider;
	provider.set_enabled(true);
	check(provider.load_cache_dir(dir.string()), "failed to load corrupt decode fixture");

	ReplacementMeta meta = {};
	check(provider.lookup(key_bad_gz, fs, &meta), "lookup should still find corrupt gzip entry");
	check(provider.lookup(key_short_rgb, fs, &meta), "lookup should still find short RGB entry");

	ReplacementImage image = {};
	check(!provider.decode_rgba8(key_bad_gz, fs, &image), "corrupt gzip payload should fail decode");
	check(!provider.decode_rgba8(key_short_rgb, fs, &image), "short RGB payload should fail decode");

	std::filesystem::remove_all(dir);
}

static void test_old_version_htc_parsing_uses_wildcard_formatsize()
{
	const auto dir = make_temp_dir("parallel_n64_hires_htc_old");
	const uint64_t key = 0x778899aabbccddeeull;
	const std::vector<uint8_t> payload = { 0x12, 0x34, 0x56, 0x78 };

	write_htc_old(dir / "old_format.htc", {
		HtcRecord{ key, 0, 1, 1, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, true, payload },
	});

	ReplacementProvider provider;
	provider.set_enabled(true);
	check(provider.load_cache_dir(dir.string()), "failed to load old-format .htc fixture");

	ReplacementImage image = {};
	check(provider.decode_rgba8(key, 0x2201, &image),
	      "old-format .htc entry should match through wildcard formatsize");
	check(image.rgba8 == payload, "old-format .htc payload mismatch");

	std::filesystem::remove_all(dir);
}
}

int main()
{
	test_hts_formatsize_fallback_and_invalid_offsets();
	test_old_version_hts_parsing();
	test_decode_failures_are_stable_for_corrupt_entries();
	test_old_version_htc_parsing_uses_wildcard_formatsize();

	std::cout << "hires_replacement_provider_parser_edge_test: PASS" << std::endl;
	return 0;
}
