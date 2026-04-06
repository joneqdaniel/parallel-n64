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
	header.asset_count = 1;
	header.record_table_offset = sizeof(PHRBHeader);
	header.asset_table_offset = header.record_table_offset + sizeof(PHRBRecordV2);
	header.string_table_offset = header.asset_table_offset + sizeof(PHRBAssetV3);
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
	record.asset_candidate_count = 1;

	PHRBAssetV3 asset = {};
	asset.record_index = 0;
	asset.width = 2;
	asset.height = 2;
	asset.selector_checksum64 = 0x5352464300000001ull;
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

	ReplacementProvider provider;
	check(provider.load_cache_dir(path), "provider should load synthetic PHRB");
	provider.set_enabled(true);
	check(provider.entry_count() == 2, "provider should load one entry for each distinct palette CRC");

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
	check(provider.sampled_index_.size() == 2, "sampled lookup index should contain both palette aliases");
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
	check(!provider.lookup_ci_low32_any(
	          record.sampled_low32,
	          record.formatsize,
	          record.sampled_sparse_pcrc,
	          &sampled_meta,
	          &resolved_checksum64),
	      "compat low32 fallback should ignore native sampled records");

	ReplacementProvider::Entry compat_alias = entry;
	compat_alias.source_path = dir + "/compat.hts";
	compat_alias.width = 7;
	compat_alias.height = 9;
	compat_alias.phrb_policy_key.clear();
	compat_alias.phrb_sampled_object_id.clear();
	compat_alias.sampled_palette_crc = 0;
	compat_alias.sampled_entry_pcrc = 0;
	compat_alias.sampled_sparse_pcrc = 0;
	compat_alias.has_native_sampled_identity = false;
	provider.add_entry(std::move(compat_alias));

	ReplacementMeta compat_meta = {};
	check(provider.lookup_with_selector(
	          structured_sparse_entry->checksum64,
	          record.formatsize,
	          asset.selector_checksum64,
	          &compat_meta),
	      "checksum lookup should still find later compat aliases");
	check(compat_meta.repl_w == 7 && compat_meta.repl_h == 9,
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
	check(compat_meta.repl_w == 7 && compat_meta.repl_h == 9,
	      "compat low32 fallback should stay inside the compat alias pool");

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

	remove_tree(dir);
	std::cout << "emu_unit_texture_replacement_provider_test: PASS" << std::endl;
	return 0;
}
