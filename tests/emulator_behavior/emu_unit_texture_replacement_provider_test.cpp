#define private public
#include "mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/texture_replacement.hpp"
#undef private

#include <array>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>
#include <zlib.h>

namespace
{
using namespace RDP;

#pragma pack(push, 1)

struct PHRBHeader
{
	char magic[4];
	uint32_t version;
	uint32_t record_count;
	uint32_t asset_count;
	uint32_t record_table_offset;
	uint32_t asset_table_offset;
	uint32_t string_table_offset;
	uint32_t blob_offset;
};

struct PHRBRecordV4
{
	uint32_t policy_key_offset;
	uint32_t sampled_object_id_offset;
	uint32_t record_flags;
	uint32_t fmt;
	uint32_t siz;
	uint32_t tex_offset;
	uint32_t stride;
	uint32_t width;
	uint32_t height;
	uint32_t formatsize;
	uint32_t sampled_low32;
	uint32_t sampled_entry_pcrc;
	uint32_t sampled_sparse_pcrc;
	uint32_t asset_candidate_count;
};

struct PHRBAssetV7
{
	uint32_t record_index;
	uint32_t replacement_id_offset;
	uint32_t legacy_source_path_offset;
	uint32_t rgba_rel_path_offset;
	uint32_t variant_group_id_offset;
	uint32_t width;
	uint32_t height;
	uint32_t format;
	uint32_t texture_format;
	uint32_t pixel_type;
	uint32_t legacy_formatsize;
	uint64_t selector_checksum64;
	uint64_t legacy_checksum64;
	uint64_t rgba_blob_offset;
	uint64_t rgba_blob_size;
};

#pragma pack(pop)

static_assert(sizeof(PHRBHeader) == 32, "PHRBHeader must stay packed on disk.");
static_assert(sizeof(PHRBRecordV4) == 56, "PHRBRecordV4 must stay packed on disk.");
static_assert(sizeof(PHRBAssetV7) == 76, "PHRBAssetV7 must stay packed on disk.");

constexpr int32_t TXCACHE_FORMAT_VERSION = 0x08000000;
constexpr uint16_t GL_RGB = 0x1907;
constexpr uint16_t GL_RGBA = 0x1908;
constexpr uint16_t GL_UNSIGNED_BYTE = 0x1401;
constexpr uint16_t GL_UNSIGNED_SHORT_5_6_5 = 0x8363;
constexpr uint32_t GL_RGB8 = 0x8051;
constexpr uint32_t GL_RGBA8 = 0x8058;
constexpr uint32_t PHRB_RECORD_FLAG_RUNTIME_READY = 1u << 0;

static void check(bool condition, const char *message)
{
	if (!condition)
	{
		std::cerr << "FAIL: " << message << std::endl;
		std::exit(1);
	}
}

static std::string make_temp_dir()
{
	char tmpl[] = "/tmp/parallel-n64-texture-provider-XXXXXX";
	char *dir = mkdtemp(tmpl);
	check(dir != nullptr, "mkdtemp failed");
	return dir;
}

static void remove_tree(const std::string &dir)
{
	std::string command = "rm -rf '" + dir + "'";
	int ret = std::system(command.c_str());
	(void)ret;
}

static void write_file(const std::string &path, const std::vector<uint8_t> &data)
{
	std::ofstream file(path, std::ios::binary);
	check(bool(file), "failed to open temporary PHRB file");
	file.write(reinterpret_cast<const char *>(data.data()), std::streamsize(data.size()));
	check(bool(file), "failed to write temporary PHRB file");
}

template <typename T>
static void gz_write_exact(gzFile fp, const T &value)
{
	check(gzwrite(fp, &value, unsigned(sizeof(T))) == int(sizeof(T)), "failed to write temporary HTC record");
}

static void gz_write_bytes(gzFile fp, const void *data, size_t size)
{
	check(gzwrite(fp, data, unsigned(size)) == int(size), "failed to write temporary HTC payload");
}

static void write_htc_file(const std::string &path,
                           uint64_t checksum64,
                           uint16_t formatsize,
                           uint32_t width,
                           uint32_t height,
                           const std::vector<uint8_t> &rgba)
{
	gzFile fp = gzopen(path.c_str(), "wb");
	check(fp != nullptr, "failed to open temporary HTC file");

	const int32_t version = TXCACHE_FORMAT_VERSION;
	const int32_t config = 0;
	const uint32_t format = GL_RGBA8;
	const uint16_t texture_format = GL_RGBA;
	const uint16_t pixel_type = GL_UNSIGNED_BYTE;
	const uint8_t is_hires = 1;
	const uint32_t data_size = uint32_t(rgba.size());

	gz_write_exact(fp, version);
	gz_write_exact(fp, config);
	gz_write_exact(fp, checksum64);
	gz_write_exact(fp, width);
	gz_write_exact(fp, height);
	gz_write_exact(fp, format);
	gz_write_exact(fp, texture_format);
	gz_write_exact(fp, pixel_type);
	gz_write_exact(fp, is_hires);
	gz_write_exact(fp, formatsize);
	gz_write_exact(fp, data_size);
	gz_write_bytes(fp, rgba.data(), rgba.size());

	check(gzclose(fp) == Z_OK, "failed to close temporary HTC file");
}

static void write_single_asset_phrb(const std::string &path,
                                    const std::string &policy_key,
                                    const std::string &replacement_id,
                                    const std::string &sampled_object_id,
                                    uint32_t fmt,
                                    uint32_t siz,
                                    uint32_t tex_offset,
                                    uint32_t stride,
                                    uint32_t width,
                                    uint32_t height,
                                    uint32_t formatsize,
                                    uint32_t sampled_low32,
                                    uint32_t palette_crc,
                                    uint64_t selector_checksum64,
                                    uint32_t repl_width,
                                    uint32_t repl_height,
                                    const std::vector<uint8_t> &blob,
                                    uint32_t record_flags = PHRB_RECORD_FLAG_RUNTIME_READY,
                                    uint64_t legacy_checksum64 = 0,
                                    uint32_t asset_format = GL_RGBA8,
                                    uint16_t asset_texture_format = GL_RGBA,
                                    uint16_t asset_pixel_type = GL_UNSIGNED_BYTE)
{
	if (legacy_checksum64 == 0)
		legacy_checksum64 = (uint64_t(palette_crc) << 32u) | uint64_t(sampled_low32);
	std::string strings;
	strings.append(policy_key);
	strings.push_back('\0');
	const uint32_t replacement_id_offset = uint32_t(strings.size());
	strings.append(replacement_id);
	strings.push_back('\0');
	const uint32_t sampled_object_id_offset = uint32_t(strings.size());
	strings.append(sampled_object_id);
	strings.push_back('\0');

	PHRBHeader header = {};
	header.magic[0] = 'P';
	header.magic[1] = 'H';
	header.magic[2] = 'R';
	header.magic[3] = 'B';
	header.version = 7;
	header.record_count = 1;
	header.asset_count = 1;
	header.record_table_offset = sizeof(PHRBHeader);
	header.asset_table_offset = header.record_table_offset + sizeof(PHRBRecordV4);
	header.string_table_offset = header.asset_table_offset + uint32_t(sizeof(PHRBAssetV7));
	header.blob_offset = header.string_table_offset + uint32_t(strings.size());

	PHRBRecordV4 record = {};
	record.policy_key_offset = 0;
	record.sampled_object_id_offset = sampled_object_id_offset;
	record.record_flags = record_flags;
	record.fmt = fmt;
	record.siz = siz;
	record.tex_offset = tex_offset;
	record.stride = stride;
	record.width = width;
	record.height = height;
	record.formatsize = formatsize;
	record.sampled_low32 = sampled_low32;
	record.sampled_entry_pcrc = palette_crc;
	record.sampled_sparse_pcrc = palette_crc;
	record.asset_candidate_count = 1;

	PHRBAssetV7 asset = {};
	asset.record_index = 0;
	asset.replacement_id_offset = replacement_id_offset;
	asset.width = repl_width;
	asset.height = repl_height;
	asset.format = asset_format;
	asset.texture_format = asset_texture_format;
	asset.pixel_type = asset_pixel_type;
	asset.legacy_formatsize = formatsize;
	asset.selector_checksum64 = selector_checksum64;
	asset.legacy_checksum64 = legacy_checksum64;
	asset.rgba_blob_offset = 0;
	asset.rgba_blob_size = uint64_t(blob.size());

	std::vector<uint8_t> data(sizeof(header) + sizeof(record) + sizeof(asset) + strings.size() + blob.size());
	size_t offset = 0;
	std::memcpy(data.data() + offset, &header, sizeof(header));
	offset += sizeof(header);
	std::memcpy(data.data() + offset, &record, sizeof(record));
	offset += sizeof(record);
	std::memcpy(data.data() + offset, &asset, sizeof(asset));
	offset += sizeof(asset);
	std::memcpy(data.data() + offset, strings.data(), strings.size());
	offset += strings.size();
	std::memcpy(data.data() + offset, blob.data(), blob.size());

	write_file(path, data);
}
}

int main()
{
	if (const char *load_path = std::getenv("PARALLEL_N64_PROVIDER_LOAD_CACHE_PATH"))
	{
		ReplacementProvider provider;
		ReplacementProvider::CacheSourcePolicy policy = ReplacementProvider::CacheSourcePolicy::Auto;
		if (const char *policy_env = std::getenv("PARALLEL_N64_PROVIDER_LOAD_CACHE_POLICY"))
		{
			const std::string value = policy_env;
			if (value == "auto")
				policy = ReplacementProvider::CacheSourcePolicy::Auto;
			else if (value == "phrb-only")
				policy = ReplacementProvider::CacheSourcePolicy::PHRBOnly;
			else if (value == "legacy-only")
				policy = ReplacementProvider::CacheSourcePolicy::LegacyOnly;
		}

		if (!provider.load_cache_dir(load_path, policy))
		{
			std::cerr << "FAIL: provider could not load cache path " << load_path << std::endl;
			return 1;
		}

		const auto stats = provider.get_stats();
		std::cout
			<< "provider_load_ok path=" << load_path
			<< " entries=" << stats.entry_count
			<< " native_sampled=" << stats.native_sampled_entry_count
			<< " compat=" << stats.compat_entry_count
			<< " phrb=" << stats.source_phrb_entry_count
			<< " hts=" << stats.source_hts_entry_count
			<< " htc=" << stats.source_htc_entry_count
			<< std::endl;
		return 0;
	}

	const std::string dir = make_temp_dir();
	const std::string path = dir + "/sample.phrb";

	const std::string policy_key = "policy";
	const std::string sampled_object_id = "sampled-fmt2-siz1-off288-stride296-wh296x6-fs258-low32940cea6e";
	std::string strings;
	strings.append(policy_key);
	strings.push_back('\0');
	const uint32_t sampled_object_id_offset = uint32_t(strings.size());
	strings.append(sampled_object_id);
	strings.push_back('\0');
	const std::array<uint8_t, 16> rgba = {
		0x10, 0x20, 0x30, 0xff,
		0x40, 0x50, 0x60, 0xff,
		0x70, 0x80, 0x90, 0xff,
		0xa0, 0xb0, 0xc0, 0xff,
	};

	PHRBHeader header = {};
	header.magic[0] = 'P';
	header.magic[1] = 'H';
	header.magic[2] = 'R';
	header.magic[3] = 'B';
	header.version = 7;
	header.record_count = 1;
	header.asset_count = 2;
	header.record_table_offset = sizeof(PHRBHeader);
	header.asset_table_offset = header.record_table_offset + uint32_t(sizeof(PHRBRecordV4));
	header.string_table_offset = header.asset_table_offset + uint32_t(2 * sizeof(PHRBAssetV7));
	header.blob_offset = header.string_table_offset + uint32_t(strings.size());

	PHRBRecordV4 record = {};
	record.policy_key_offset = 0;
	record.sampled_object_id_offset = sampled_object_id_offset;
	record.record_flags = PHRB_RECORD_FLAG_RUNTIME_READY;
	record.fmt = 2;
	record.siz = 1;
	record.tex_offset = 0x120;
	record.stride = 296;
	record.width = 296;
	record.height = 6;
	record.formatsize = 258;
	record.sampled_low32 = 0x940cea6eu;
	record.sampled_entry_pcrc = 0x11223344u;
	record.sampled_sparse_pcrc = 0x55667788u;
	record.asset_candidate_count = 2;

	PHRBAssetV7 asset = {};
	asset.record_index = 0;
	asset.width = 2;
	asset.height = 2;
	asset.format = GL_RGBA8;
	asset.texture_format = GL_RGBA;
	asset.pixel_type = GL_UNSIGNED_BYTE;
	asset.legacy_formatsize = 258;
	asset.selector_checksum64 = 0x1122334455667788ull;
	asset.legacy_checksum64 = (uint64_t(record.sampled_sparse_pcrc) << 32u) | uint64_t(record.sampled_low32);
	asset.rgba_blob_offset = 0;
	asset.rgba_blob_size = uint64_t(rgba.size());

	PHRBAssetV7 second_asset = asset;
	second_asset.selector_checksum64 = 0x123456789abcdef0ull;
	second_asset.legacy_checksum64 = (uint64_t(record.sampled_sparse_pcrc) << 32u) | uint64_t(record.sampled_low32);
	second_asset.rgba_blob_offset = uint64_t(rgba.size());

	std::vector<uint8_t> data(sizeof(header) + sizeof(record) + 2 * sizeof(PHRBAssetV7) + strings.size() + 2 * rgba.size());
	size_t offset = 0;
	std::memcpy(data.data() + offset, &header, sizeof(header));
	offset += sizeof(header);
	std::memcpy(data.data() + offset, &record, sizeof(record));
	offset += sizeof(record);
	std::memcpy(data.data() + offset, &asset, sizeof(asset));
	offset += sizeof(asset);
	std::memcpy(data.data() + offset, &second_asset, sizeof(second_asset));
	offset += sizeof(second_asset);
	std::memcpy(data.data() + offset, strings.data(), strings.size());
	offset += strings.size();
	std::memcpy(data.data() + offset, rgba.data(), rgba.size());
	offset += rgba.size();
	std::memcpy(data.data() + offset, rgba.data(), rgba.size());

	write_file(path, data);

	ReplacementProvider provider;
	check(provider.load_cache_dir(path), "provider should load synthetic PHRB");
	provider.set_enabled(true);
	check(provider.entry_count() == 4, "provider should load one entry for each selector and distinct palette CRC");

	const auto &entry = provider.entries_[0];
	check(entry.sampled_fmt == record.fmt, "sampled fmt should be preserved");
	check(entry.sampled_siz == record.siz, "sampled siz should be preserved");
	check(entry.sampled_tex_offset == record.tex_offset, "sampled tex_offset should be preserved");
	check(entry.sampled_stride == record.stride, "sampled stride should be preserved");
	check(entry.sampled_width == record.width, "sampled width should be preserved");
	check(entry.sampled_height == record.height, "sampled height should be preserved");
	check(entry.sampled_low32 == record.sampled_low32, "sampled low32 should be preserved");
	check(entry.sampled_palette_crc == record.sampled_sparse_pcrc, "sampled palette crc should be preserved");
	check(entry.sampled_entry_pcrc == record.sampled_entry_pcrc, "sampled entry pcrc should be preserved");
	check(entry.sampled_sparse_pcrc == record.sampled_sparse_pcrc, "sampled sparse pcrc should be preserved");
	check(entry.has_native_sampled_identity, "PHRB entry should retain native sampled identity");
	check(entry.phrb_policy_key == policy_key, "PHRB policy_key should be preserved");
	check(entry.phrb_sampled_object_id == sampled_object_id, "PHRB sampled_object_id should be preserved");
	check(entry.selector_checksum64 == asset.selector_checksum64, "selector should be preserved");
	check(entry.formatsize == record.formatsize, "formatsize should remain preserved");
	check(provider.sampled_index_.size() == 4, "sampled lookup index should contain both palette aliases for both selectors");
	check(provider.sampled_family_index_.size() == 2, "sampled family index should collapse selectors into palette families");
	check(provider.compat_checksum_low32_index_.empty(), "native PHRB entries should not populate compat low32 families");

	const auto *structured_sparse_entry = provider.find_sampled_entry(
		record.fmt,
		record.siz,
		record.tex_offset,
		record.stride,
		record.width,
		record.height,
		record.sampled_low32,
		record.sampled_sparse_pcrc,
		record.formatsize,
		asset.selector_checksum64);
	check(structured_sparse_entry != nullptr, "structured sparse sampled entry should be discoverable");
	check(structured_sparse_entry->checksum64 == ((uint64_t(record.sampled_sparse_pcrc) << 32u) | uint64_t(record.sampled_low32)),
	      "structured sparse sampled entry should resolve the sparse alias checksum");

	ReplacementMeta sampled_meta = {};
	uint64_t resolved_checksum64 = 0;
	check(provider.lookup_sampled_with_selector(
	          record.fmt,
	          record.siz,
	          record.tex_offset,
	          record.stride,
	          record.width,
	          record.height,
	          record.sampled_low32,
	          record.sampled_sparse_pcrc,
	          record.formatsize,
	          asset.selector_checksum64,
	          &sampled_meta,
	          &resolved_checksum64),
	      "structured sampled lookup should resolve the sparse alias");
	check(sampled_meta.repl_w == asset.width, "structured sampled lookup should preserve replacement width");
	check(sampled_meta.repl_h == asset.height, "structured sampled lookup should preserve replacement height");
	check(resolved_checksum64 == ((uint64_t(record.sampled_sparse_pcrc) << 32u) | uint64_t(record.sampled_low32)),
	      "structured sampled lookup should return the resolved sparse alias checksum");

	check(provider.lookup_sampled_with_selector(
	          record.fmt,
	          record.siz,
	          record.tex_offset,
	          record.stride,
	          record.width,
	          record.height,
	          record.sampled_low32,
	          record.sampled_entry_pcrc,
	          record.formatsize,
	          asset.selector_checksum64,
	          &sampled_meta,
	          &resolved_checksum64),
	      "structured sampled lookup should resolve the entry alias too");
	check(resolved_checksum64 == ((uint64_t(record.sampled_entry_pcrc) << 32u) | uint64_t(record.sampled_low32)),
	      "structured sampled lookup should return the resolved entry alias checksum");
	check(!provider.lookup_sampled_with_selector(
	          record.fmt,
	          record.siz,
	          record.tex_offset,
	          record.stride,
	          record.width,
	          record.height,
	          record.sampled_low32,
	          record.sampled_sparse_pcrc,
	          record.formatsize,
	          0xaaaaaaaa55555555ull,
	          &sampled_meta,
	          &resolved_checksum64),
	      "structured sampled lookup should not silently collapse selector conflicts");
	uint64_t resolved_selector_checksum64 = 0xffffffffu;
	check(!provider.lookup_sampled_family_unique(
	          record.fmt,
	          record.siz,
	          record.tex_offset,
	          record.stride,
	          record.width,
	          record.height,
	          record.sampled_low32,
	          record.sampled_sparse_pcrc,
	          record.formatsize,
	          &sampled_meta,
	          &resolved_checksum64,
	          &resolved_selector_checksum64),
	      "family-unique sampled lookup should stay disabled for multi-selector pools");

	SampledFamilyDiagnostics sampled_diag = {};
	check(provider.describe_sampled_family(
	          record.fmt,
	          record.siz,
	          record.tex_offset,
	          record.stride,
	          record.width,
	          record.height,
	          record.sampled_low32,
	          record.sampled_sparse_pcrc,
	          record.formatsize,
	          0xaaaaaaaa55555555ull,
	          &sampled_diag),
	      "sampled family diagnostics should be available for native PHRB records");
	check(sampled_diag.available, "sampled family diagnostics should report availability");
	check(sampled_diag.prefer_exact_formatsize, "sampled family diagnostics should prefer exact formatsize");
	check(sampled_diag.exact_formatsize_entries == 2, "sampled family diagnostics should see both selector variants");
	check(sampled_diag.generic_formatsize_entries == 0, "sampled family diagnostics should not report generic entries");
	check(sampled_diag.active_entry_count == 2, "sampled family diagnostics should stay inside the sparse palette family");
	check(sampled_diag.active_unique_checksum_count == 1, "sampled family diagnostics should preserve a single checksum alias");
	check(sampled_diag.active_unique_selector_count == 2, "sampled family diagnostics should preserve both selectors");
	check(sampled_diag.active_matching_selector_count == 0, "sampled family diagnostics should report selector conflicts");
	check(sampled_diag.active_has_any_selector, "sampled family diagnostics should report selector availability");
	check(!sampled_diag.active_has_ordered_surface_selectors, "sampled family diagnostics should not invent ordered selectors");
	check(sampled_diag.active_is_pool, "sampled family diagnostics should classify multi-selector sampled families as pools");
	check(sampled_diag.sample_repl_w == asset.width && sampled_diag.sample_repl_h == asset.height,
	      "sampled family diagnostics should preserve replacement dimensions");
	check(sampled_diag.sample_policy_key == policy_key, "sampled family diagnostics should preserve the policy key");
	check(sampled_diag.sample_sampled_object_id == sampled_object_id,
	      "sampled family diagnostics should preserve the sampled object id");
	check(!provider.lookup_ci_low32_any(
	          record.sampled_low32,
	          record.formatsize,
	          record.sampled_sparse_pcrc,
	          &sampled_meta,
	          &resolved_checksum64),
	      "compat low32 fallback should ignore native sampled records");

	ReplacementProvider::Entry compat_alias = entry;
	compat_alias.source_path = dir + "/compat.hts";
	compat_alias.phrb_policy_key.clear();
	compat_alias.phrb_sampled_object_id.clear();
	compat_alias.sampled_palette_crc = 0;
	compat_alias.sampled_entry_pcrc = 0;
	compat_alias.sampled_sparse_pcrc = 0;
	compat_alias.has_native_sampled_identity = false;
	compat_alias.inline_blob = true;
	compat_alias.blob[0] = 0xfe;
	provider.add_entry(std::move(compat_alias));

	ReplacementMeta compat_meta = {};
	check(provider.lookup_with_selector(
	          structured_sparse_entry->checksum64,
	          record.formatsize,
	          asset.selector_checksum64,
	          &compat_meta),
	      "checksum lookup should still find later compat aliases");
	check(provider.find_entry(
	          structured_sparse_entry->checksum64,
	          record.formatsize,
	          asset.selector_checksum64)->source_path == dir + "/compat.hts",
	      "checksum lookup should prefer the latest compat alias");
	check(provider.compat_checksum_low32_index_.size() == 1,
	      "compat aliases should populate the explicit compat low32 index");
	check(provider.lookup_ci_low32_any(
	          record.sampled_low32,
	          record.formatsize,
	          record.sampled_sparse_pcrc,
	          &compat_meta,
	          &resolved_checksum64),
	      "compat low32 fallback should resolve explicit compat aliases");
	check(provider.find_entry(
	          resolved_checksum64,
	          record.formatsize,
	          asset.selector_checksum64)->source_path == dir + "/compat.hts",
	      "compat low32 fallback should stay inside the compat alias pool");

	ReplacementImage compat_image = {};
	check(provider.decode_rgba8_with_selector(
	          structured_sparse_entry->checksum64,
	          record.formatsize,
	          asset.selector_checksum64,
	          &compat_image),
	      "checksum decode should still resolve the latest compat alias");
	check(!compat_image.rgba8.empty() && compat_image.rgba8[0] == 0xfe,
	      "checksum decode should expose compat alias payload");

	ReplacementMeta native_meta = {};
	check(provider.lookup_sampled_with_selector(
	          record.fmt,
	          record.siz,
	          record.tex_offset,
	          record.stride,
	          record.width,
	          record.height,
	          record.sampled_low32,
	          record.sampled_sparse_pcrc,
	          record.formatsize,
	          asset.selector_checksum64,
	          &native_meta,
	          &resolved_checksum64),
	      "structured sampled lookup should continue to resolve native sampled entries");
	check(native_meta.repl_w == asset.width && native_meta.repl_h == asset.height,
	      "structured sampled lookup should ignore checksum-only compat aliases");
	check(resolved_checksum64 == ((uint64_t(record.sampled_sparse_pcrc) << 32u) | uint64_t(record.sampled_low32)),
	      "structured sampled lookup should keep the native sparse alias checksum");

	ReplacementImage native_image = {};
	check(provider.decode_sampled_rgba8_with_selector(
	          record.fmt,
	          record.siz,
	          record.tex_offset,
	          record.stride,
	          record.width,
	          record.height,
	          record.sampled_low32,
	          record.sampled_sparse_pcrc,
	          record.formatsize,
	          asset.selector_checksum64,
	          &native_image,
	          &resolved_checksum64),
	      "structured sampled decode should resolve native sampled entries directly");
	check(!native_image.rgba8.empty() && native_image.rgba8[0] == rgba[0],
	      "structured sampled decode should ignore checksum-only compat aliases");
	check(resolved_checksum64 == ((uint64_t(record.sampled_sparse_pcrc) << 32u) | uint64_t(record.sampled_low32)),
	      "structured sampled decode should preserve the native sparse alias checksum");

	ReplacementProviderStats stats = provider.get_stats();
	check(stats.entry_count == 5, "provider stats should report total entry count");
	check(stats.native_sampled_entry_count == 4, "provider stats should report native sampled entry count");
	check(stats.compat_entry_count == 1, "provider stats should report compat entry count");
	check(stats.sampled_index_count == 4, "provider stats should report sampled lookup entry count");
	check(stats.sampled_duplicate_key_count == 0, "provider stats should report zero sampled duplicate keys for unique inputs");
	check(stats.sampled_duplicate_entry_count == 0, "provider stats should report zero sampled duplicate entries for unique inputs");
	check(stats.sampled_family_count == 2, "provider stats should report sampled family count");
	check(stats.compat_low32_family_count == 1, "provider stats should report compat low32 family count");
	check(stats.source_phrb_entry_count == 4, "provider stats should report PHRB-backed entries");
	check(stats.source_hts_entry_count == 1, "provider stats should report HTS-backed entries");
	check(stats.source_htc_entry_count == 0, "provider stats should not invent HTC-backed entries");

	const std::string deferred_dir = make_temp_dir();
	const uint32_t deferred_palette_crc = 0x1234abcdU;
	const uint32_t deferred_low32 = 0x89abcdefU;
	const uint64_t deferred_checksum64 = (uint64_t(deferred_palette_crc) << 32u) | uint64_t(deferred_low32);
	const std::vector<uint8_t> deferred_runtime_rgba = {
		0x01, 0x02, 0x03, 0xff,
		0x04, 0x05, 0x06, 0xff,
		0x07, 0x08, 0x09, 0xff,
		0x0a, 0x0b, 0x0c, 0xff,
	};
	const std::vector<uint8_t> deferred_canonical_rgba = {
		0x55, 0x66, 0x77, 0xff,
		0x88, 0x99, 0xaa, 0xff,
		0xbb, 0xcc, 0xdd, 0xff,
		0xee, 0xf0, 0xf1, 0xff,
	};
	write_single_asset_phrb(
		deferred_dir + "/runtime-ready.phrb",
		"runtime-ready",
		"runtime-ready-replacement",
		"sampled-fmt2-siz1-off64-stride32-wh2x2-fs258-low3289abcdef",
		2,
		1,
		64,
		32,
		2,
		2,
		258,
		deferred_low32,
		deferred_palette_crc,
		0,
		2,
		2,
		deferred_runtime_rgba,
		PHRB_RECORD_FLAG_RUNTIME_READY);
	write_single_asset_phrb(
		deferred_dir + "/runtime-deferred.phrb",
		"runtime-deferred",
		"runtime-deferred-replacement",
		"legacy-family-89abcdef-fs258",
		0,
		0,
		0,
		0,
		0,
		0,
		258,
		deferred_low32,
		0,
		0,
		2,
		2,
		deferred_canonical_rgba,
		0);

	ReplacementProvider deferred_provider;
	check(deferred_provider.load_cache_dir(deferred_dir), "provider should load directories with mixed runtime-ready and runtime-deferred PHRB files");
	deferred_provider.set_enabled(true);
	check(deferred_provider.entry_count() == 1, "runtime-deferred PHRB records should be ignored by the runtime loader");
	const auto *deferred_entry = deferred_provider.find_entry(deferred_checksum64, 258);
	check(deferred_entry != nullptr, "runtime-ready PHRB record should still load");
	check(deferred_entry->phrb_policy_key == "runtime-ready", "runtime-ready record should preserve its policy key");
	check(deferred_provider.find_entry(uint64_t(deferred_low32), 258) == nullptr,
	      "runtime-deferred record should not synthesize a runtime lookup entry");
	ReplacementProviderStats deferred_stats = deferred_provider.get_stats();
	check(deferred_stats.source_phrb_entry_count == 1, "runtime-deferred PHRB records should not count as loaded source entries");
	check(deferred_stats.native_sampled_entry_count == 1, "runtime-deferred PHRB records should not inflate native sampled entry counts");
	remove_tree(deferred_dir);

	const std::string family_dir = make_temp_dir();
	const uint32_t family_low32 = 0x01020304u;
	const uint32_t family_palette_crc = 0x99887766u;
	const uint64_t family_checksum64 = (uint64_t(family_palette_crc) << 32u) | uint64_t(family_low32);
	const std::vector<uint8_t> family_rgba = {
		0x12, 0x34, 0x56, 0xff,
		0x78, 0x9a, 0xbc, 0xff,
		0xde, 0xf0, 0x11, 0xff,
		0x22, 0x33, 0x44, 0xff,
	};
	write_single_asset_phrb(
		family_dir + "/family-runtime-ready.phrb",
		"family-runtime-ready",
		"family-runtime-ready-replacement",
		"legacy-family-01020304-fs258",
		0,
		0,
		0,
		0,
		0,
		0,
		258,
		family_low32,
		0,
		0,
		2,
		2,
		family_rgba,
		PHRB_RECORD_FLAG_RUNTIME_READY,
		family_checksum64);

	ReplacementProvider family_provider;
	check(family_provider.load_cache_dir(family_dir), "provider should load runtime-ready family PHRB records");
	family_provider.set_enabled(true);
	check(family_provider.entry_count() == 1, "family runtime-ready PHRB record should synthesize one compat entry");
	check(family_provider.find_native_entry(family_checksum64, 258, 0) == nullptr,
	      "family runtime-ready PHRB record should not pretend to be a native sampled entry");
	const auto *family_entry = family_provider.find_compat_entry(family_checksum64, 258, 0);
	check(family_entry != nullptr, "family runtime-ready PHRB record should load into the compat checksum path");
	check(family_entry->phrb_policy_key == "family-runtime-ready", "family runtime-ready record should preserve its policy key");
	check(family_entry->phrb_sampled_object_id == "legacy-family-01020304-fs258",
	      "family runtime-ready record should preserve its sampled object id");
	ReplacementMeta family_meta = {};
	NativeSampledIdentity family_identity = {};
	ResolvedEntrySourceClass family_source_class = ResolvedEntrySourceClass::Unknown;
	check(family_provider.lookup_with_selector_and_identity(
	          family_checksum64,
	          258,
	          0,
	          &family_meta,
	          &family_identity,
	          &family_source_class,
	          &resolved_checksum64),
	      "family runtime-ready PHRB record should resolve through the generic exact checksum path");
	check(!family_identity.valid, "family runtime-ready PHRB record should not synthesize native sampled identity");
	check(family_source_class == ResolvedEntrySourceClass::Compat,
	      "family runtime-ready PHRB record should classify the generic winning entry as compat");
	check(family_meta.repl_w == 2 && family_meta.repl_h == 2,
	      "family runtime-ready PHRB record should preserve replacement dimensions");
	check(resolved_checksum64 == family_checksum64,
	      "family runtime-ready PHRB record should preserve the exact legacy checksum");
	ReplacementImage family_image = {};
	check(family_provider.decode_rgba8(family_checksum64, 258, &family_image),
	      "family runtime-ready PHRB record should decode through the generic exact checksum path");
	check(family_image.rgba8 == family_rgba,
	      "family runtime-ready PHRB record should preserve its payload");
	ReplacementProviderStats family_stats = family_provider.get_stats();
	check(family_stats.entry_count == 1, "family stats should report one loaded entry");
	check(family_stats.native_sampled_entry_count == 0, "family stats should not count family stubs as native sampled entries");
	check(family_stats.compat_entry_count == 1, "family stats should count family stubs as compat entries");
	check(family_stats.source_phrb_entry_count == 1, "family stats should count the loaded family PHRB entry");
	remove_tree(family_dir);

	const std::string legacy_payload_dir = make_temp_dir();
	const uint32_t legacy_payload_low32 = 0x0f1e2d3cu;
	const uint32_t legacy_payload_palette_crc = 0x55667788u;
	const uint64_t legacy_payload_checksum64 = (uint64_t(legacy_payload_palette_crc) << 32u) | uint64_t(legacy_payload_low32);
	const std::vector<uint8_t> legacy_payload_blob = {
		0x00, 0xf8,
		0xe0, 0x07,
		0x1f, 0x00,
		0xff, 0xff,
	};
	const std::vector<uint8_t> legacy_payload_expected_rgba = {
		0xff, 0x00, 0x00, 0xff,
		0x00, 0xff, 0x00, 0xff,
		0x00, 0x00, 0xff, 0xff,
		0xff, 0xff, 0xff, 0xff,
	};
	write_single_asset_phrb(
		legacy_payload_dir + "/legacy-payload-runtime-ready.phrb",
		"legacy-payload-runtime-ready",
		"legacy-payload-runtime-ready-replacement",
		"legacy-family-0f1e2d3c-fs258",
		0,
		0,
		0,
		0,
		0,
		0,
		258,
		legacy_payload_low32,
		0,
		0,
		2,
		2,
		legacy_payload_blob,
		PHRB_RECORD_FLAG_RUNTIME_READY,
		legacy_payload_checksum64,
		GL_RGB8,
		GL_RGB,
		GL_UNSIGNED_SHORT_5_6_5);

	ReplacementProvider legacy_payload_provider;
	check(legacy_payload_provider.load_cache_dir(legacy_payload_dir), "provider should load v7 legacy-payload PHRB records");
	legacy_payload_provider.set_enabled(true);
	check(legacy_payload_provider.entry_count() == 1, "legacy-payload runtime-ready PHRB record should synthesize one compat entry");
	const auto *legacy_payload_entry = legacy_payload_provider.find_compat_entry(legacy_payload_checksum64, 258, 0);
	check(legacy_payload_entry != nullptr, "legacy-payload runtime-ready PHRB record should load into the compat checksum path");
	check(legacy_payload_entry->format == GL_RGB8, "legacy-payload runtime-ready record should preserve the stored format");
	check(legacy_payload_entry->texture_format == GL_RGB, "legacy-payload runtime-ready record should preserve the stored texture format");
	check(legacy_payload_entry->pixel_type == GL_UNSIGNED_SHORT_5_6_5, "legacy-payload runtime-ready record should preserve the stored pixel type");
	ReplacementImage legacy_payload_image = {};
	check(legacy_payload_provider.decode_rgba8(legacy_payload_checksum64, 258, &legacy_payload_image),
	      "legacy-payload runtime-ready PHRB record should decode through the generic exact checksum path");
	check(legacy_payload_image.rgba8 == legacy_payload_expected_rgba,
	      "legacy-payload runtime-ready PHRB record should decode legacy payload bytes to the expected RGBA output");
	remove_tree(legacy_payload_dir);

	const std::string mixed_dir = make_temp_dir();
	const uint32_t mixed_palette_crc = 0xa1b2c3d4u;
	const uint32_t mixed_sampled_low32 = 0x0badbeefu;
	const uint64_t mixed_checksum64 = (uint64_t(mixed_palette_crc) << 32u) | uint64_t(mixed_sampled_low32);
	const std::vector<uint8_t> mixed_native_rgba = {
		0x11, 0x22, 0x33, 0xff,
		0x44, 0x55, 0x66, 0xff,
		0x77, 0x88, 0x99, 0xff,
		0xaa, 0xbb, 0xcc, 0xff,
	};
	const std::vector<uint8_t> mixed_compat_rgba = {
		0xde, 0xad, 0xbe, 0xff,
		0xef, 0x10, 0x20, 0xff,
		0x30, 0x40, 0x50, 0xff,
		0x60, 0x70, 0x80, 0xff,
	};
	write_single_asset_phrb(
		mixed_dir + "/a-native.phrb",
		"native-priority",
		"native-priority-replacement",
		"sampled-fmt2-siz1-off32-stride16-wh2x2-fs258-low320badbeef",
		2,
		1,
		32,
		16,
		2,
		2,
		258,
		mixed_sampled_low32,
		mixed_palette_crc,
		0,
		2,
		2,
		mixed_native_rgba);
	write_htc_file(
		mixed_dir + "/z-compat.htc",
		mixed_checksum64,
		258,
		4,
		1,
		mixed_compat_rgba);

	ReplacementProvider mixed_all_provider;
	check(mixed_all_provider.load_cache_dir(mixed_dir, ReplacementProvider::CacheSourcePolicy::All),
	      "explicit all-policy provider should still load mixed-source cache directories");
	mixed_all_provider.set_enabled(true);
	check(mixed_all_provider.entry_count() == 2, "all-policy provider should load both native and compat entries");
	check(mixed_all_provider.native_checksum_index_.size() == 1, "all-policy provider should keep a native checksum family index");
	check(mixed_all_provider.compat_checksum_index_.size() == 1, "all-policy provider should keep a compat checksum family index");
	const auto *mixed_entry = mixed_all_provider.find_entry(mixed_checksum64, 258);
	check(mixed_entry != nullptr, "all-policy provider should resolve duplicate checksum entries");
	check(mixed_entry->source_path.find(".phrb") != std::string::npos,
	      "all-policy directory load should still prefer PHRB entries over later-sorting legacy files");
	const auto *mixed_native_entry = mixed_all_provider.find_native_entry(mixed_checksum64, 258, 0);
	check(mixed_native_entry != nullptr, "all-policy provider should expose the native duplicate explicitly");
	check(mixed_native_entry->source_path.find(".phrb") != std::string::npos,
	      "all-policy native duplicate lookup should resolve the PHRB entry");
	const auto *mixed_compat_entry = mixed_all_provider.find_compat_entry(mixed_checksum64, 258, 0);
	check(mixed_compat_entry != nullptr, "all-policy provider should expose the compat duplicate explicitly");
	check(mixed_compat_entry->source_path.find(".htc") != std::string::npos,
	      "all-policy compat duplicate lookup should resolve the legacy entry");
	ReplacementMeta mixed_native_meta = {};
	NativeSampledIdentity mixed_native_identity = {};
	check(mixed_all_provider.lookup_native_with_selector(
	          mixed_checksum64,
	          258,
	          0,
	          &mixed_native_meta,
	          &mixed_native_identity,
	          &resolved_checksum64),
	      "mixed-source native lookup should resolve duplicate checksum entries");
	check(mixed_native_identity.valid, "mixed-source native lookup should preserve structured sampled identity");
	check(mixed_native_identity.sampled_fmt == 2 && mixed_native_identity.sampled_siz == 1,
	      "mixed-source native lookup should report sampled format/size");
	check(mixed_native_identity.sampled_tex_offset == 32 && mixed_native_identity.sampled_stride == 16,
	      "mixed-source native lookup should report sampled offset/stride");
	check(mixed_native_identity.sampled_width == 2 && mixed_native_identity.sampled_height == 2,
	      "mixed-source native lookup should report sampled dimensions");
	check(mixed_native_identity.sampled_low32 == mixed_sampled_low32 &&
	          mixed_native_identity.sampled_palette_crc == mixed_palette_crc,
	      "mixed-source native lookup should report sampled checksum identity");
	check(mixed_native_identity.formatsize == 258 && mixed_native_identity.selector_checksum64 == 0,
	      "mixed-source native lookup should preserve formatsize and selector");
	check(resolved_checksum64 == mixed_checksum64,
	      "mixed-source native lookup should report the resolved checksum");
	ReplacementMeta mixed_lookup_meta = {};
	NativeSampledIdentity mixed_lookup_identity = {};
	ResolvedEntrySourceClass mixed_lookup_source_class = ResolvedEntrySourceClass::Unknown;
	check(mixed_all_provider.lookup_with_selector_and_identity(
	          mixed_checksum64,
	          258,
	          0,
	          &mixed_lookup_meta,
	          &mixed_lookup_identity,
	          &mixed_lookup_source_class,
	          &resolved_checksum64),
	      "mixed-source generic lookup helper should resolve duplicate checksum entries");
	check(mixed_lookup_meta.repl_w == 2 && mixed_lookup_meta.repl_h == 2,
	      "mixed-source generic lookup helper should preserve the winning replacement dimensions");
	check(mixed_lookup_source_class == ResolvedEntrySourceClass::Native,
	      "mixed-source generic lookup helper should classify the winning PHRB entry as native");
	check(mixed_lookup_identity.valid,
	      "mixed-source generic lookup helper should preserve native sampled identity for the winning PHRB entry");
	check(mixed_lookup_identity.sampled_low32 == mixed_sampled_low32 &&
	          mixed_lookup_identity.sampled_palette_crc == mixed_palette_crc,
	      "mixed-source generic lookup helper should expose the winning sampled checksum identity");
	check(resolved_checksum64 == mixed_checksum64,
	      "mixed-source generic lookup helper should report the resolved checksum");
	uint64_t mixed_resolved_selector_checksum64 = 0xffffffffu;
	check(mixed_all_provider.lookup_sampled_family_unique(
	          2,
	          1,
	          32,
	          16,
	          2,
	          2,
	          mixed_sampled_low32,
	          mixed_palette_crc,
	          258,
	          &mixed_native_meta,
	          &resolved_checksum64,
	          &mixed_resolved_selector_checksum64),
	      "family-unique sampled lookup should resolve singleton native sampled families");
	check(mixed_resolved_selector_checksum64 == 0,
	      "family-unique sampled lookup should preserve the singleton selector");
	check(resolved_checksum64 == mixed_checksum64,
	      "family-unique sampled lookup should preserve the singleton checksum");
	bool mixed_ordered_surface_singleton = true;
	check(mixed_all_provider.lookup_sampled_family_singleton(
	          2,
	          1,
	          32,
	          16,
	          2,
	          2,
	          mixed_sampled_low32,
	          mixed_palette_crc,
	          258,
	          &mixed_native_meta,
	          &resolved_checksum64,
	          &mixed_resolved_selector_checksum64,
	          &mixed_ordered_surface_singleton),
	      "family-singleton sampled lookup should continue to resolve plain singleton native sampled families");
	check(mixed_resolved_selector_checksum64 == 0,
	      "family-singleton sampled lookup should preserve the singleton selector");
	check(!mixed_ordered_surface_singleton,
	      "family-singleton sampled lookup should not classify plain singletons as ordered-surface families");
	check(resolved_checksum64 == mixed_checksum64,
	      "family-singleton sampled lookup should preserve the singleton checksum");
	ReplacementMeta mixed_compat_meta = {};
	check(mixed_all_provider.lookup_compat_with_selector(mixed_checksum64, 258, 0, &mixed_compat_meta),
	      "all-policy compat lookup should resolve duplicate checksum entries");
	check(mixed_compat_meta.repl_w == 4 && mixed_compat_meta.repl_h == 1,
	      "all-policy compat lookup should preserve compat replacement dimensions");
	ReplacementImage mixed_image = {};
	check(mixed_all_provider.decode_rgba8(mixed_checksum64, 258, &mixed_image),
	      "all-policy checksum decode should resolve duplicate entries");
	check(!mixed_image.rgba8.empty() && mixed_image.rgba8[0] == mixed_native_rgba[0],
	      "all-policy checksum decode should prefer the native PHRB payload");
	ReplacementImage mixed_native_image = {};
	check(mixed_all_provider.decode_rgba8_native_with_selector(mixed_checksum64, 258, 0, &mixed_native_image),
	      "all-policy native decode should resolve the PHRB duplicate explicitly");
	check(!mixed_native_image.rgba8.empty() && mixed_native_image.rgba8[0] == mixed_native_rgba[0],
	      "all-policy native decode should expose the PHRB payload");
	ReplacementImage mixed_compat_image = {};
	check(mixed_all_provider.decode_rgba8_compat_with_selector(mixed_checksum64, 258, 0, &mixed_compat_image),
	      "all-policy compat decode should resolve the legacy duplicate explicitly");
	check(!mixed_compat_image.rgba8.empty() && mixed_compat_image.rgba8[0] == mixed_compat_rgba[0],
	      "all-policy compat decode should expose the legacy payload");
	ReplacementMeta mixed_compat_low32_meta = {};
	check(mixed_all_provider.lookup_ci_low32_unique(uint32_t(mixed_checksum64 & 0xffffffffu), 258, &mixed_compat_low32_meta),
	      "compat low32 unique lookup should still resolve the compat duplicate in all-policy mixed-source caches");
	check(mixed_compat_low32_meta.repl_w == 4 && mixed_compat_low32_meta.repl_h == 1,
	      "compat low32 unique lookup should stay inside the compat pool even when a native duplicate exists");
	ReplacementProviderStats mixed_stats = mixed_all_provider.get_stats();
	check(mixed_stats.entry_count == 2, "all-policy stats should report total entry count");
	check(mixed_stats.native_sampled_entry_count == 1, "all-policy stats should preserve native sampled entry count");
	check(mixed_stats.compat_entry_count == 1, "all-policy stats should preserve compat entry count");
	check(mixed_stats.source_phrb_entry_count == 1, "all-policy stats should preserve PHRB source count");
	check(mixed_stats.source_htc_entry_count == 1, "all-policy stats should preserve HTC source count");

	ReplacementProvider default_provider;
	check(default_provider.load_cache_dir(mixed_dir),
	      "default provider load should now use auto source policy for mixed-source cache directories");
	default_provider.set_enabled(true);
	check(default_provider.entry_count() == 1,
	      "default provider load should prefer the native PHRB entry when mixed-source cache directories contain both formats");
	check(default_provider.find_entry(mixed_checksum64, 258) != nullptr,
	      "default provider load should still resolve the preferred native PHRB duplicate");
	check(default_provider.find_compat_entry(mixed_checksum64, 258, 0) == nullptr,
	      "default provider load should fence out compat entries in mixed-source auto mode");
	ReplacementProviderStats default_stats = default_provider.get_stats();
	check(default_stats.source_phrb_entry_count == 1, "default load stats should preserve the preferred PHRB source count");
	check(default_stats.source_htc_entry_count == 0, "default load stats should exclude HTC-backed entries in mixed-source auto mode");
	check(default_stats.compat_entry_count == 0, "default load stats should exclude compat entries in mixed-source auto mode");

	ReplacementProvider phrb_only_provider;
	check(phrb_only_provider.load_cache_dir(mixed_dir, ReplacementProvider::CacheSourcePolicy::PHRBOnly),
	      "phrb-only provider should load native entries from mixed-source cache directories");
	phrb_only_provider.set_enabled(true);
	check(phrb_only_provider.entry_count() == 1, "phrb-only provider should only load the native PHRB entry");
	check(phrb_only_provider.find_entry(mixed_checksum64, 258) != nullptr,
	      "phrb-only provider should still resolve the native PHRB duplicate");
	check(phrb_only_provider.find_compat_entry(mixed_checksum64, 258, 0) == nullptr,
	      "phrb-only provider should not expose compat entries");
	ReplacementProviderStats phrb_only_stats = phrb_only_provider.get_stats();
	check(phrb_only_stats.source_phrb_entry_count == 1, "phrb-only stats should preserve only the PHRB source count");
	check(phrb_only_stats.source_htc_entry_count == 0, "phrb-only stats should exclude HTC-backed entries");
	check(phrb_only_stats.compat_entry_count == 0, "phrb-only stats should exclude compat entries");

	ReplacementProvider legacy_only_provider;
	check(legacy_only_provider.load_cache_dir(mixed_dir, ReplacementProvider::CacheSourcePolicy::LegacyOnly),
	      "legacy-only provider should load legacy entries from mixed-source cache directories");
	legacy_only_provider.set_enabled(true);
	check(legacy_only_provider.entry_count() == 1, "legacy-only provider should only load the legacy entry");
	check(legacy_only_provider.find_native_entry(mixed_checksum64, 258, 0) == nullptr,
	      "legacy-only provider should not expose native entries");
	check(legacy_only_provider.find_compat_entry(mixed_checksum64, 258, 0) != nullptr,
	      "legacy-only provider should still expose the legacy compat entry");
	ReplacementMeta legacy_only_lookup_meta = {};
	NativeSampledIdentity legacy_only_identity = {};
	ResolvedEntrySourceClass legacy_only_source_class = ResolvedEntrySourceClass::Unknown;
	check(legacy_only_provider.lookup_with_selector_and_identity(
	          mixed_checksum64,
	          258,
	          0,
	          &legacy_only_lookup_meta,
	          &legacy_only_identity,
	          &legacy_only_source_class,
	          &resolved_checksum64),
	      "legacy-only generic lookup helper should still resolve compat entries");
	check(!legacy_only_identity.valid,
	      "legacy-only generic lookup helper should not synthesize native sampled identity for compat entries");
	check(legacy_only_source_class == ResolvedEntrySourceClass::Compat,
	      "legacy-only generic lookup helper should classify compat entries explicitly");
	ReplacementProviderStats legacy_only_stats = legacy_only_provider.get_stats();
	check(legacy_only_stats.source_phrb_entry_count == 0, "legacy-only stats should exclude PHRB-backed entries");
	check(legacy_only_stats.source_htc_entry_count == 1, "legacy-only stats should preserve HTC-backed entries");
	check(legacy_only_stats.compat_entry_count == 1, "legacy-only stats should preserve compat entries");

	ReplacementProvider auto_provider;
	check(auto_provider.load_cache_dir(mixed_dir, ReplacementProvider::CacheSourcePolicy::Auto),
	      "auto provider should load supported entries from mixed-source cache directories");
	auto_provider.set_enabled(true);
	check(auto_provider.entry_count() == 1,
	      "auto provider should prefer the native PHRB entry when mixed-source cache directories contain both formats");
	check(auto_provider.find_entry(mixed_checksum64, 258) != nullptr,
	      "auto provider should still resolve the preferred native PHRB duplicate");
	check(auto_provider.find_compat_entry(mixed_checksum64, 258, 0) == nullptr,
	      "auto provider should fence out compat entries when a mixed-source directory contains PHRB data");
	ReplacementProviderStats auto_stats = auto_provider.get_stats();
	check(auto_stats.source_phrb_entry_count == 1, "auto stats should preserve the preferred PHRB source count");
	check(auto_stats.source_htc_entry_count == 0, "auto stats should exclude HTC-backed entries from mixed-source directories");
	check(auto_stats.compat_entry_count == 0, "auto stats should exclude compat entries in mixed-source auto mode");
	remove_tree(mixed_dir);

	const std::string ordered_singleton_dir = make_temp_dir();
	const uint32_t ordered_singleton_palette_crc = 0x13572468u;
	const uint32_t ordered_singleton_sampled_low32 = 0x24681357u;
	const uint64_t ordered_singleton_selector = ReplacementProvider::ordered_surface_slot_selector_checksum64(0);
	const uint64_t ordered_singleton_checksum64 =
		(uint64_t(ordered_singleton_palette_crc) << 32u) | uint64_t(ordered_singleton_sampled_low32);
	const std::vector<uint8_t> ordered_singleton_rgba = {
		0x21, 0x43, 0x65, 0xff,
		0x87, 0xa9, 0xcb, 0xff,
		0xed, 0x0f, 0x10, 0xff,
		0x32, 0x54, 0x76, 0xff,
	};
	write_single_asset_phrb(
		ordered_singleton_dir + "/ordered-singleton.phrb",
		"ordered-singleton",
		"ordered-singleton-replacement",
		"sampled-fmt2-siz1-off96-stride16-wh2x2-fs258-low3224681357",
		2,
		1,
		96,
		16,
		2,
		2,
		258,
		ordered_singleton_sampled_low32,
		ordered_singleton_palette_crc,
		ordered_singleton_selector,
		2,
		2,
		ordered_singleton_rgba);

	ReplacementProvider ordered_singleton_provider;
	check(ordered_singleton_provider.load_cache_dir(ordered_singleton_dir),
	      "provider should load ordered-surface singleton sampled families");
	ordered_singleton_provider.set_enabled(true);
	ReplacementMeta ordered_singleton_meta = {};
	uint64_t ordered_singleton_resolved_checksum64 = 0;
	uint64_t ordered_singleton_resolved_selector_checksum64 = 0xffffffffu;
	check(!ordered_singleton_provider.lookup_sampled_family_unique(
	          2,
	          1,
	          96,
	          16,
	          2,
	          2,
	          ordered_singleton_sampled_low32,
	          ordered_singleton_palette_crc,
	          258,
	          &ordered_singleton_meta,
	          &ordered_singleton_resolved_checksum64,
	          &ordered_singleton_resolved_selector_checksum64),
	      "family-unique sampled lookup should continue to reject ordered-surface singleton families");
	bool ordered_singleton_flag = false;
	check(ordered_singleton_provider.lookup_sampled_family_singleton(
	          2,
	          1,
	          96,
	          16,
	          2,
	          2,
	          ordered_singleton_sampled_low32,
	          ordered_singleton_palette_crc,
	          258,
	          &ordered_singleton_meta,
	          &ordered_singleton_resolved_checksum64,
	          &ordered_singleton_resolved_selector_checksum64,
	          &ordered_singleton_flag),
	      "family-singleton sampled lookup should resolve ordered-surface singleton families");
	check(ordered_singleton_flag,
	      "family-singleton sampled lookup should classify ordered-surface singleton families explicitly");
	check(ordered_singleton_resolved_selector_checksum64 == ordered_singleton_selector,
	      "family-singleton sampled lookup should preserve the ordered-surface selector");
	check(ordered_singleton_resolved_checksum64 == ordered_singleton_checksum64,
	      "family-singleton sampled lookup should preserve the singleton checksum");
	check(ordered_singleton_meta.repl_w == 2 && ordered_singleton_meta.repl_h == 2,
	      "family-singleton sampled lookup should preserve ordered-surface singleton replacement dimensions");
	SampledFamilyDiagnostics ordered_singleton_diag = {};
	check(ordered_singleton_provider.describe_sampled_family(
	          2,
	          1,
	          96,
	          16,
	          2,
	          2,
	          ordered_singleton_sampled_low32,
	          ordered_singleton_palette_crc,
	          258,
	          ordered_singleton_selector,
	          &ordered_singleton_diag),
	      "ordered-surface singleton sampled family should expose diagnostics");
	check(ordered_singleton_diag.active_has_ordered_surface_selectors,
	      "ordered-surface singleton diagnostics should report ordered selectors");
	check(ordered_singleton_diag.active_ordered_surface_selector_count == 1,
	      "ordered-surface singleton diagnostics should preserve the ordered selector count");
	check(!ordered_singleton_diag.active_is_pool,
	      "ordered-surface singleton diagnostics should not classify the family as a pool");
	ReplacementImage ordered_singleton_image = {};
	check(ordered_singleton_provider.decode_sampled_rgba8_with_selector(
	          2,
	          1,
	          96,
	          16,
	          2,
	          2,
	          ordered_singleton_sampled_low32,
	          ordered_singleton_palette_crc,
	          258,
	          ordered_singleton_selector,
	          &ordered_singleton_image,
	          &ordered_singleton_resolved_checksum64),
	      "ordered-surface singleton sampled decode should resolve via the explicit selector path");
	check(ordered_singleton_image.rgba8 == ordered_singleton_rgba,
	      "ordered-surface singleton sampled decode should preserve the payload");
	remove_tree(ordered_singleton_dir);

	const std::string auto_fallback_dir = make_temp_dir();
	const uint32_t auto_fallback_palette_crc = 0x0badc0deu;
	const uint32_t auto_fallback_sampled_low32 = 0x00c0ffeeu;
	const uint64_t auto_fallback_checksum64 =
		(uint64_t(auto_fallback_palette_crc) << 32u) | uint64_t(auto_fallback_sampled_low32);
	const std::vector<uint8_t> auto_fallback_compat_rgba = {
		0xaa, 0x10, 0x20, 0xff,
		0xbb, 0x30, 0x40, 0xff,
		0xcc, 0x50, 0x60, 0xff,
		0xdd, 0x70, 0x80, 0xff,
	};
	write_single_asset_phrb(
		auto_fallback_dir + "/deferred.phrb",
		"auto-deferred-record",
		"auto-deferred-replacement",
		"sampled-fmt2-siz1-off48-stride16-wh2x2-fs258-low3200c0ffee",
		2,
		1,
		48,
		16,
		2,
		2,
		258,
		auto_fallback_sampled_low32,
		auto_fallback_palette_crc,
		0,
		2,
		2,
		auto_fallback_compat_rgba,
		0);
	write_htc_file(
		auto_fallback_dir + "/fallback.htc",
		auto_fallback_checksum64,
		258,
		2,
		2,
		auto_fallback_compat_rgba);

	ReplacementProvider auto_fallback_provider;
	check(auto_fallback_provider.load_cache_dir(auto_fallback_dir, ReplacementProvider::CacheSourcePolicy::Auto),
	      "auto provider should fall back to legacy entries when mixed-source directories only contain deferred or unusable PHRB records");
	auto_fallback_provider.set_enabled(true);
	check(auto_fallback_provider.entry_count() == 1,
	      "auto fallback provider should load the legacy entry when no runtime-ready PHRB records are available");
	check(auto_fallback_provider.find_compat_entry(auto_fallback_checksum64, 258, 0) != nullptr,
	      "auto fallback provider should expose the legacy compat entry after the PHRB lane fails empty");
	ReplacementProviderStats auto_fallback_stats = auto_fallback_provider.get_stats();
	check(auto_fallback_stats.source_phrb_entry_count == 0,
	      "auto fallback stats should not count deferred PHRB records that failed to load");
	check(auto_fallback_stats.source_htc_entry_count == 1,
	      "auto fallback stats should preserve the legacy source count after fallback");
	check(auto_fallback_stats.compat_entry_count == 1,
	      "auto fallback stats should preserve compat entries after fallback");
	remove_tree(auto_fallback_dir);

	const std::string phrb_preference_dir = make_temp_dir();
	const uint32_t phrb_preference_palette_crc = 0x2468ace0u;
	const uint32_t phrb_preference_sampled_low32 = 0x13579bdfu;
	const uint64_t phrb_preference_checksum64 =
		(uint64_t(phrb_preference_palette_crc) << 32u) | uint64_t(phrb_preference_sampled_low32);
	const std::vector<uint8_t> phrb_preference_native_rgba = {
		0x01, 0x23, 0x45, 0xff,
		0x67, 0x89, 0xab, 0xff,
		0xcd, 0xef, 0x10, 0xff,
		0x32, 0x54, 0x76, 0xff,
	};
	const std::vector<uint8_t> phrb_preference_family_rgba = {
		0xf1, 0xe2, 0xd3, 0xff,
		0xc4, 0xb5, 0xa6, 0xff,
		0x97, 0x88, 0x79, 0xff,
		0x6a, 0x5b, 0x4c, 0xff,
	};
	write_single_asset_phrb(
		phrb_preference_dir + "/a-native.phrb",
		"phrb-native-first",
		"phrb-native-first-replacement",
		"sampled-fmt2-siz1-off64-stride16-wh2x2-fs258-low3213579bdf",
		2,
		1,
		64,
		16,
		2,
		2,
		258,
		phrb_preference_sampled_low32,
		phrb_preference_palette_crc,
		0,
		2,
		2,
		phrb_preference_native_rgba);
	write_single_asset_phrb(
		phrb_preference_dir + "/z-family.phrb",
		"phrb-family-fallback",
		"phrb-family-fallback-replacement",
		"family-runtime-record",
		0,
		0,
		0,
		0,
		0,
		0,
		258,
		phrb_preference_sampled_low32,
		phrb_preference_palette_crc,
		0,
		4,
		1,
		phrb_preference_family_rgba,
		PHRB_RECORD_FLAG_RUNTIME_READY,
		phrb_preference_checksum64);

	ReplacementProvider phrb_preference_provider;
	check(phrb_preference_provider.load_cache_dir(phrb_preference_dir),
	      "provider should load native and family-runtime PHRB duplicates");
	phrb_preference_provider.set_enabled(true);
	check(phrb_preference_provider.entry_count() == 2,
	      "provider should expose both native sampled and family-runtime compat records");
	check(phrb_preference_provider.find_native_entry(phrb_preference_checksum64, 258, 0) != nullptr,
	      "native PHRB duplicate should remain visible explicitly");
	check(phrb_preference_provider.find_compat_entry(phrb_preference_checksum64, 258, 0) != nullptr,
	      "family-runtime PHRB duplicate should remain visible explicitly");
	const auto *phrb_preference_entry = phrb_preference_provider.find_entry(phrb_preference_checksum64, 258);
	check(phrb_preference_entry != nullptr, "generic entry lookup should still resolve the duplicate checksum");
	check(phrb_preference_entry->has_native_sampled_identity,
	      "generic entry lookup should prefer native sampled PHRB entries over later family-runtime compat records");
	check(phrb_preference_entry->width == 2 && phrb_preference_entry->height == 2,
	      "generic entry lookup should preserve the native replacement dimensions");
	ReplacementMeta phrb_preference_meta = {};
	NativeSampledIdentity phrb_preference_identity = {};
	ResolvedEntrySourceClass phrb_preference_source_class = ResolvedEntrySourceClass::Unknown;
	uint64_t phrb_preference_resolved_checksum64 = 0;
	uint64_t phrb_preference_resolved_selector_checksum64 = 0xffffffffu;
	check(phrb_preference_provider.lookup_with_selector_and_identity(
	          phrb_preference_checksum64,
	          258,
	          0,
	          &phrb_preference_meta,
	          &phrb_preference_identity,
	          &phrb_preference_source_class,
	          &phrb_preference_resolved_checksum64,
	          &phrb_preference_resolved_selector_checksum64),
	      "generic lookup helper should resolve native sampled PHRB entries ahead of family-runtime compat duplicates");
	check(phrb_preference_meta.repl_w == 2 && phrb_preference_meta.repl_h == 2,
	      "generic lookup helper should preserve native replacement dimensions when a compat family stub shares the checksum");
	check(phrb_preference_identity.valid,
	      "generic lookup helper should preserve native sampled identity when a compat family stub shares the checksum");
	check(phrb_preference_source_class == ResolvedEntrySourceClass::Native,
	      "generic lookup helper should classify native sampled PHRB winners explicitly");
	check(phrb_preference_identity.sampled_low32 == phrb_preference_sampled_low32 &&
	          phrb_preference_identity.sampled_palette_crc == phrb_preference_palette_crc,
	      "generic lookup helper should expose the native sampled checksum identity");
	check(phrb_preference_resolved_checksum64 == phrb_preference_checksum64 &&
	          phrb_preference_resolved_selector_checksum64 == 0,
	      "generic lookup helper should report the native exact checksum and selector");
	ReplacementMeta phrb_preference_compat_meta = {};
	check(phrb_preference_provider.lookup_compat_with_selector(
	          phrb_preference_checksum64,
	          258,
	          0,
	          &phrb_preference_compat_meta),
	      "compat lookup should still expose the family-runtime fallback explicitly");
	check(phrb_preference_compat_meta.repl_w == 4 && phrb_preference_compat_meta.repl_h == 1,
	      "compat lookup should preserve the family-runtime fallback dimensions");
	ReplacementImage phrb_preference_image = {};
	check(phrb_preference_provider.decode_rgba8_with_selector(
	          phrb_preference_checksum64,
	          258,
	          0,
	          &phrb_preference_image),
	      "generic checksum decode should resolve native sampled PHRB entries ahead of family-runtime compat duplicates");
	check(!phrb_preference_image.rgba8.empty() && phrb_preference_image.rgba8[0] == phrb_preference_native_rgba[0],
	      "generic checksum decode should expose the native sampled payload when a compat family stub shares the checksum");
	remove_tree(phrb_preference_dir);

	const std::string duplicate_dir = make_temp_dir();
	const uint32_t duplicate_palette_crc = 0x31415926u;
	const uint32_t duplicate_sampled_low32 = 0x7701ac09u;
	const uint64_t duplicate_selector = 0x0000000071c71cddull;
	const std::vector<uint8_t> duplicate_a_rgba = {
		0x10, 0x20, 0x30, 0xff,
		0x40, 0x50, 0x60, 0xff,
		0x70, 0x80, 0x90, 0xff,
		0xa0, 0xb0, 0xc0, 0xff,
	};
	const std::vector<uint8_t> duplicate_b_rgba = {
		0xca, 0xfe, 0xba, 0xff,
		0xbe, 0x11, 0x22, 0xff,
		0x33, 0x44, 0x55, 0xff,
		0x66, 0x77, 0x88, 0xff,
	};
	write_single_asset_phrb(
		duplicate_dir + "/a-duplicate.phrb",
		"duplicate-a",
		"duplicate-a",
		"sampled-fmt0-siz3-off0-stride400-wh200x2-fs768-low327701ac09",
		0,
		3,
		0,
		400,
		200,
		2,
		768,
		duplicate_sampled_low32,
		duplicate_palette_crc,
		duplicate_selector,
		2,
		2,
		duplicate_a_rgba);
	write_single_asset_phrb(
		duplicate_dir + "/b-duplicate.phrb",
		"duplicate-b",
		"duplicate-z",
		"sampled-fmt0-siz3-off0-stride400-wh200x2-fs768-low327701ac09",
		0,
		3,
		0,
		400,
		200,
		2,
		768,
		duplicate_sampled_low32,
		duplicate_palette_crc,
		duplicate_selector,
		2,
		2,
		duplicate_b_rgba);

	ReplacementProvider duplicate_provider;
	check(duplicate_provider.load_cache_dir(duplicate_dir), "provider should load duplicate sampled key cache");
	duplicate_provider.set_enabled(true);
	ReplacementProviderStats duplicate_stats = duplicate_provider.get_stats();
	check(duplicate_stats.entry_count == 2, "duplicate provider should report both entries");
	check(duplicate_stats.native_sampled_entry_count == 2, "duplicate provider should report both native sampled entries");
	check(duplicate_stats.sampled_index_count == 1, "duplicate provider should collapse duplicate sampled lookup keys to one active entry");
	check(duplicate_stats.sampled_duplicate_key_count == 1, "duplicate provider should report one sampled duplicate key");
	check(duplicate_stats.sampled_duplicate_entry_count == 1, "duplicate provider should report one extra sampled duplicate entry");
	auto duplicate_diags = duplicate_provider.get_sampled_duplicate_diagnostics();
	check(duplicate_diags.size() == 1, "duplicate provider should expose one sampled duplicate diagnostic");
	check(duplicate_diags[0].sampled_low32 == duplicate_sampled_low32, "duplicate diagnostic should preserve sampled low32");
	check(duplicate_diags[0].sampled_palette_crc == duplicate_palette_crc, "duplicate diagnostic should preserve palette crc");
	check(duplicate_diags[0].formatsize == 768, "duplicate diagnostic should preserve formatsize");
	check(duplicate_diags[0].selector_checksum64 == duplicate_selector, "duplicate diagnostic should preserve selector");
	check(duplicate_diags[0].total_entry_count == 2, "duplicate diagnostic should report total entry count");
	check(duplicate_diags[0].duplicate_entry_count == 1, "duplicate diagnostic should report extra duplicate entries");
	check(duplicate_diags[0].active_policy_key == "duplicate-a", "duplicate diagnostic should report the stable active policy");
	check(duplicate_diags[0].active_replacement_id == "duplicate-a", "duplicate diagnostic should report the stable replacement id");
	check(duplicate_diags[0].active_repl_w == 2 && duplicate_diags[0].active_repl_h == 2,
	      "duplicate diagnostic should preserve active replacement dimensions");
	ReplacementMeta duplicate_lookup_meta = {};
	NativeSampledIdentity duplicate_lookup_identity = {};
	ResolvedEntrySourceClass duplicate_lookup_source_class = ResolvedEntrySourceClass::Unknown;
	uint64_t duplicate_resolved_checksum64 = 0;
	uint64_t duplicate_resolved_selector_checksum64 = 0;
	check(duplicate_provider.lookup_with_selector_and_identity(
	          duplicate_diags[0].active_checksum64,
	          768,
	          duplicate_selector,
	          &duplicate_lookup_meta,
	          &duplicate_lookup_identity,
	          &duplicate_lookup_source_class,
	          &duplicate_resolved_checksum64,
	          &duplicate_resolved_selector_checksum64),
	      "selector-bearing generic lookup helper should resolve duplicate sampled entries");
	check(duplicate_lookup_identity.valid,
	      "selector-bearing generic lookup helper should preserve native sampled identity");
	check(duplicate_lookup_source_class == ResolvedEntrySourceClass::Native,
	      "selector-bearing generic lookup helper should classify sampled duplicate winners as native");
	check(duplicate_resolved_checksum64 == duplicate_diags[0].active_checksum64,
	      "selector-bearing generic lookup helper should report the resolved checksum");
	check(duplicate_resolved_selector_checksum64 == duplicate_selector,
	      "selector-bearing generic lookup helper should report the resolved selector checksum");

	ReplacementImage duplicate_image = {};
	check(duplicate_provider.decode_sampled_rgba8_with_selector(
	          0,
	          3,
	          0,
	          400,
	          200,
	          2,
	          duplicate_sampled_low32,
	          duplicate_palette_crc,
	          768,
	          duplicate_selector,
	          &duplicate_image),
	      "duplicate sampled decode should still resolve the active entry");
	check(duplicate_image.rgba8 == duplicate_a_rgba, "duplicate sampled decode should resolve the stable replacement-id winner");
	remove_tree(duplicate_dir);

	remove_tree(dir);
	std::cout << "emu_unit_texture_replacement_provider_test: PASS" << std::endl;
	return 0;
}
