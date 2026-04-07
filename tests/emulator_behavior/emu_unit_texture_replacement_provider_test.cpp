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

struct PHRBRecordV2
{
	uint32_t policy_key_offset;
	uint32_t sampled_object_id_offset;
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

struct PHRBAssetV3
{
	uint32_t record_index;
	uint32_t replacement_id_offset;
	uint32_t legacy_source_path_offset;
	uint32_t rgba_rel_path_offset;
	uint32_t variant_group_id_offset;
	uint32_t width;
	uint32_t height;
	uint32_t texture_format;
	uint32_t pixel_type;
	uint32_t legacy_formatsize;
	uint64_t selector_checksum64;
	uint32_t rgba_blob_offset;
	uint32_t rgba_blob_size;
};

constexpr int32_t TXCACHE_FORMAT_VERSION = 0x08000000;
constexpr uint16_t GL_RGBA = 0x1908;
constexpr uint16_t GL_UNSIGNED_BYTE = 0x1401;
constexpr uint32_t GL_RGBA8 = 0x8058;

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
                                    const std::vector<uint8_t> &rgba)
{
	std::string strings;
	strings.append(policy_key);
	strings.push_back('\0');
	const uint32_t sampled_object_id_offset = uint32_t(strings.size());
	strings.append(sampled_object_id);
	strings.push_back('\0');

	PHRBHeader header = {};
	header.magic[0] = 'P';
	header.magic[1] = 'H';
	header.magic[2] = 'R';
	header.magic[3] = 'B';
	header.version = 3;
	header.record_count = 1;
	header.asset_count = 1;
	header.record_table_offset = sizeof(PHRBHeader);
	header.asset_table_offset = header.record_table_offset + sizeof(PHRBRecordV2);
	header.string_table_offset = header.asset_table_offset + uint32_t(sizeof(PHRBAssetV3));
	header.blob_offset = header.string_table_offset + uint32_t(strings.size());

	PHRBRecordV2 record = {};
	record.policy_key_offset = 0;
	record.sampled_object_id_offset = sampled_object_id_offset;
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

	PHRBAssetV3 asset = {};
	asset.record_index = 0;
	asset.width = repl_width;
	asset.height = repl_height;
	asset.selector_checksum64 = selector_checksum64;
	asset.rgba_blob_offset = 0;
	asset.rgba_blob_size = uint32_t(rgba.size());

	std::vector<uint8_t> data(sizeof(header) + sizeof(record) + sizeof(asset) + strings.size() + rgba.size());
	size_t offset = 0;
	std::memcpy(data.data() + offset, &header, sizeof(header));
	offset += sizeof(header);
	std::memcpy(data.data() + offset, &record, sizeof(record));
	offset += sizeof(record);
	std::memcpy(data.data() + offset, &asset, sizeof(asset));
	offset += sizeof(asset);
	std::memcpy(data.data() + offset, strings.data(), strings.size());
	offset += strings.size();
	std::memcpy(data.data() + offset, rgba.data(), rgba.size());

	write_file(path, data);
}
}

int main()
{
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
	header.version = 3;
	header.record_count = 1;
	header.asset_count = 2;
	header.record_table_offset = sizeof(PHRBHeader);
	header.asset_table_offset = header.record_table_offset + sizeof(PHRBRecordV2);
	header.string_table_offset = header.asset_table_offset + uint32_t(2 * sizeof(PHRBAssetV3));
	header.blob_offset = header.string_table_offset + uint32_t(strings.size());

	PHRBRecordV2 record = {};
	record.policy_key_offset = 0;
	record.sampled_object_id_offset = sampled_object_id_offset;
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

	PHRBAssetV3 asset = {};
	asset.record_index = 0;
	asset.width = 2;
	asset.height = 2;
	asset.selector_checksum64 = 0x1122334455667788ull;
	asset.rgba_blob_offset = 0;
	asset.rgba_blob_size = uint32_t(rgba.size());

	PHRBAssetV3 second_asset = asset;
	second_asset.selector_checksum64 = 0x123456789abcdef0ull;
	second_asset.rgba_blob_offset = uint32_t(rgba.size());

	std::vector<uint8_t> data(sizeof(header) + sizeof(record) + 2 * sizeof(PHRBAssetV3) + strings.size() + 2 * rgba.size());
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
	check(stats.sampled_family_count == 2, "provider stats should report sampled family count");
	check(stats.compat_low32_family_count == 1, "provider stats should report compat low32 family count");
	check(stats.source_phrb_entry_count == 4, "provider stats should report PHRB-backed entries");
	check(stats.source_hts_entry_count == 1, "provider stats should report HTS-backed entries");
	check(stats.source_htc_entry_count == 0, "provider stats should not invent HTC-backed entries");

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

	ReplacementProvider mixed_provider;
	check(mixed_provider.load_cache_dir(mixed_dir), "provider should load mixed-source cache directories");
	mixed_provider.set_enabled(true);
	check(mixed_provider.entry_count() == 2, "mixed-source provider should load both native and compat entries");
	check(mixed_provider.native_checksum_index_.size() == 1, "mixed-source provider should keep a native checksum family index");
	check(mixed_provider.compat_checksum_index_.size() == 1, "mixed-source provider should keep a compat checksum family index");
	const auto *mixed_entry = mixed_provider.find_entry(mixed_checksum64, 258);
	check(mixed_entry != nullptr, "mixed-source provider should resolve duplicate checksum entries");
	check(mixed_entry->source_path.find(".phrb") != std::string::npos,
	      "directory load should prefer PHRB entries over later-sorting legacy files");
	const auto *mixed_native_entry = mixed_provider.find_native_entry(mixed_checksum64, 258, 0);
	check(mixed_native_entry != nullptr, "mixed-source provider should expose the native duplicate explicitly");
	check(mixed_native_entry->source_path.find(".phrb") != std::string::npos,
	      "native duplicate lookup should resolve the PHRB entry");
	const auto *mixed_compat_entry = mixed_provider.find_compat_entry(mixed_checksum64, 258, 0);
	check(mixed_compat_entry != nullptr, "mixed-source provider should expose the compat duplicate explicitly");
	check(mixed_compat_entry->source_path.find(".htc") != std::string::npos,
	      "compat duplicate lookup should resolve the legacy entry");
	ReplacementMeta mixed_native_meta = {};
	check(mixed_provider.lookup_native_with_selector(mixed_checksum64, 258, 0, &mixed_native_meta),
	      "mixed-source native lookup should resolve duplicate checksum entries");
	ReplacementMeta mixed_compat_meta = {};
	check(mixed_provider.lookup_compat_with_selector(mixed_checksum64, 258, 0, &mixed_compat_meta),
	      "mixed-source compat lookup should resolve duplicate checksum entries");
	check(mixed_compat_meta.repl_w == 4 && mixed_compat_meta.repl_h == 1,
	      "mixed-source compat lookup should preserve compat replacement dimensions");
	ReplacementImage mixed_image = {};
	check(mixed_provider.decode_rgba8(mixed_checksum64, 258, &mixed_image),
	      "mixed-source checksum decode should resolve duplicate entries");
	check(!mixed_image.rgba8.empty() && mixed_image.rgba8[0] == mixed_native_rgba[0],
	      "mixed-source checksum decode should prefer the native PHRB payload");
	ReplacementImage mixed_native_image = {};
	check(mixed_provider.decode_rgba8_native_with_selector(mixed_checksum64, 258, 0, &mixed_native_image),
	      "mixed-source native decode should resolve the PHRB duplicate explicitly");
	check(!mixed_native_image.rgba8.empty() && mixed_native_image.rgba8[0] == mixed_native_rgba[0],
	      "mixed-source native decode should expose the PHRB payload");
	ReplacementImage mixed_compat_image = {};
	check(mixed_provider.decode_rgba8_compat_with_selector(mixed_checksum64, 258, 0, &mixed_compat_image),
	      "mixed-source compat decode should resolve the legacy duplicate explicitly");
	check(!mixed_compat_image.rgba8.empty() && mixed_compat_image.rgba8[0] == mixed_compat_rgba[0],
	      "mixed-source compat decode should expose the legacy payload");
	ReplacementMeta mixed_compat_low32_meta = {};
	check(mixed_provider.lookup_ci_low32_unique(uint32_t(mixed_checksum64 & 0xffffffffu), 258, &mixed_compat_low32_meta),
	      "compat low32 unique lookup should still resolve the compat duplicate in mixed-source caches");
	check(mixed_compat_low32_meta.repl_w == 4 && mixed_compat_low32_meta.repl_h == 1,
	      "compat low32 unique lookup should stay inside the compat pool even when a native duplicate exists");
	ReplacementProviderStats mixed_stats = mixed_provider.get_stats();
	check(mixed_stats.entry_count == 2, "mixed-source stats should report total entry count");
	check(mixed_stats.native_sampled_entry_count == 1, "mixed-source stats should preserve native sampled entry count");
	check(mixed_stats.compat_entry_count == 1, "mixed-source stats should preserve compat entry count");
	check(mixed_stats.source_phrb_entry_count == 1, "mixed-source stats should preserve PHRB source count");
	check(mixed_stats.source_htc_entry_count == 1, "mixed-source stats should preserve HTC source count");
	remove_tree(mixed_dir);

	remove_tree(dir);
	std::cout << "emu_unit_texture_replacement_provider_test: PASS" << std::endl;
	return 0;
}
