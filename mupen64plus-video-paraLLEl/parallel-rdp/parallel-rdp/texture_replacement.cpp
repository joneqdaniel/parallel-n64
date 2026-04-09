#include "texture_replacement.hpp"
#include "logging.hpp"
#include <algorithm>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <fstream>
#include <sys/stat.h>
#include <zlib.h>

namespace RDP
{
namespace
{
constexpr int32_t TXCACHE_FORMAT_VERSION = 0x08000000;
constexpr uint32_t GL_TEXFMT_GZ = 0x80000000u;

constexpr uint16_t GL_RGB = 0x1907;
constexpr uint16_t GL_RGBA = 0x1908;
constexpr uint16_t GL_LUMINANCE = 0x1909;

constexpr uint16_t GL_UNSIGNED_BYTE = 0x1401;
constexpr uint16_t GL_UNSIGNED_SHORT_4_4_4_4 = 0x8033;
constexpr uint16_t GL_UNSIGNED_SHORT_5_5_5_1 = 0x8034;
constexpr uint16_t GL_UNSIGNED_SHORT_5_6_5 = 0x8363;

constexpr uint32_t GL_RGB8 = 0x8051;
constexpr uint32_t GL_RGBA8 = 0x8058;
constexpr uint64_t ORDERED_SURFACE_SELECTOR_TAG = 0x5352464300000000ull;
constexpr uint64_t ORDERED_SURFACE_SELECTOR_MASK = 0xffffffff00000000ull;

inline bool is_ordered_surface_selector(uint64_t selector_checksum64)
{
	return (selector_checksum64 & ORDERED_SURFACE_SELECTOR_MASK) == ORDERED_SURFACE_SELECTOR_TAG;
}

inline uint32_t get_ordered_surface_slot_index(uint64_t selector_checksum64)
{
	return uint32_t(selector_checksum64 & 0xffffffffu);
}

inline void append_unique_ordered_surface_selector(std::vector<uint64_t> &selectors, uint64_t selector_checksum64)
{
	for (auto existing : selectors)
		if (existing == selector_checksum64)
			return;
	selectors.push_back(selector_checksum64);
	std::sort(selectors.begin(), selectors.end());
}

inline uint64_t compose_ordered_surface_index_key(uint64_t checksum64, uint16_t formatsize)
{
	return checksum64 ^ (uint64_t(formatsize) << 48);
}

inline int cache_source_priority(const std::string &path)
{
	const char suffix[] = ".phrb";
	if (path.size() < sizeof(suffix) - 1)
		return 0;
	const size_t base = path.size() - (sizeof(suffix) - 1);
	for (size_t i = 0; i < sizeof(suffix) - 1; i++)
	{
		char a = path[base + i];
		char b = suffix[i];
		if (a >= 'A' && a <= 'Z')
			a = char(a - 'A' + 'a');
		if (a != b)
			return 0;
	}
	return 1;
}


#pragma pack(push, 1)

struct PHRBHeader
{
	char magic[4] = {};
	uint32_t version = 0;
	uint32_t record_count = 0;
	uint32_t asset_count = 0;
	uint32_t record_table_offset = 0;
	uint32_t asset_table_offset = 0;
	uint32_t string_table_offset = 0;
	uint32_t blob_offset = 0;
};

struct PHRBRecordV2
{
	uint32_t policy_key_offset = 0;
	uint32_t sampled_object_id_offset = 0;
	uint32_t fmt = 0;
	uint32_t siz = 0;
	uint32_t tex_offset = 0;
	uint32_t stride = 0;
	uint32_t width = 0;
	uint32_t height = 0;
	uint32_t formatsize = 0;
	uint32_t sampled_low32 = 0;
	uint32_t sampled_entry_pcrc = 0;
	uint32_t sampled_sparse_pcrc = 0;
	uint32_t asset_candidate_count = 0;
};

struct PHRBRecordV4
{
	uint32_t policy_key_offset = 0;
	uint32_t sampled_object_id_offset = 0;
	uint32_t record_flags = 0;
	uint32_t fmt = 0;
	uint32_t siz = 0;
	uint32_t tex_offset = 0;
	uint32_t stride = 0;
	uint32_t width = 0;
	uint32_t height = 0;
	uint32_t formatsize = 0;
	uint32_t sampled_low32 = 0;
	uint32_t sampled_entry_pcrc = 0;
	uint32_t sampled_sparse_pcrc = 0;
	uint32_t asset_candidate_count = 0;
};

constexpr uint32_t PHRB_RECORD_FLAG_RUNTIME_READY = 1u << 0;

struct PHRBAssetV2
{
	uint32_t record_index = 0;
	uint32_t replacement_id_offset = 0;
	uint32_t legacy_source_path_offset = 0;
	uint32_t rgba_rel_path_offset = 0;
	uint32_t variant_group_id_offset = 0;
	uint32_t width = 0;
	uint32_t height = 0;
	uint32_t texture_format = 0;
	uint32_t pixel_type = 0;
	uint32_t legacy_formatsize = 0;
	uint32_t rgba_blob_offset = 0;
	uint32_t rgba_blob_size = 0;
};

struct PHRBAssetV3
{
	uint32_t record_index = 0;
	uint32_t replacement_id_offset = 0;
	uint32_t legacy_source_path_offset = 0;
	uint32_t rgba_rel_path_offset = 0;
	uint32_t variant_group_id_offset = 0;
	uint32_t width = 0;
	uint32_t height = 0;
	uint32_t texture_format = 0;
	uint32_t pixel_type = 0;
	uint32_t legacy_formatsize = 0;
	uint64_t selector_checksum64 = 0;
	uint32_t rgba_blob_offset = 0;
	uint32_t rgba_blob_size = 0;
};

struct PHRBAssetV5
{
	uint32_t record_index = 0;
	uint32_t replacement_id_offset = 0;
	uint32_t legacy_source_path_offset = 0;
	uint32_t rgba_rel_path_offset = 0;
	uint32_t variant_group_id_offset = 0;
	uint32_t width = 0;
	uint32_t height = 0;
	uint32_t texture_format = 0;
	uint32_t pixel_type = 0;
	uint32_t legacy_formatsize = 0;
	uint64_t selector_checksum64 = 0;
	uint64_t legacy_checksum64 = 0;
	uint32_t rgba_blob_offset = 0;
	uint32_t rgba_blob_size = 0;
};

struct PHRBAssetV6
{
	uint32_t record_index = 0;
	uint32_t replacement_id_offset = 0;
	uint32_t legacy_source_path_offset = 0;
	uint32_t rgba_rel_path_offset = 0;
	uint32_t variant_group_id_offset = 0;
	uint32_t width = 0;
	uint32_t height = 0;
	uint32_t texture_format = 0;
	uint32_t pixel_type = 0;
	uint32_t legacy_formatsize = 0;
	uint64_t selector_checksum64 = 0;
	uint64_t legacy_checksum64 = 0;
	uint64_t rgba_blob_offset = 0;
	uint64_t rgba_blob_size = 0;
};

struct PHRBAssetV7
{
	uint32_t record_index = 0;
	uint32_t replacement_id_offset = 0;
	uint32_t legacy_source_path_offset = 0;
	uint32_t rgba_rel_path_offset = 0;
	uint32_t variant_group_id_offset = 0;
	uint32_t width = 0;
	uint32_t height = 0;
	uint32_t format = 0;
	uint32_t texture_format = 0;
	uint32_t pixel_type = 0;
	uint32_t legacy_formatsize = 0;
	uint64_t selector_checksum64 = 0;
	uint64_t legacy_checksum64 = 0;
	uint64_t rgba_blob_offset = 0;
	uint64_t rgba_blob_size = 0;
};

#pragma pack(pop)

static_assert(sizeof(PHRBHeader) == 32, "PHRBHeader must stay packed on disk.");
static_assert(sizeof(PHRBRecordV2) == 52, "PHRBRecordV2 must stay packed on disk.");
static_assert(sizeof(PHRBRecordV4) == 56, "PHRBRecordV4 must stay packed on disk.");
static_assert(sizeof(PHRBAssetV2) == 48, "PHRBAssetV2 must stay packed on disk.");
static_assert(sizeof(PHRBAssetV3) == 56, "PHRBAssetV3 must stay packed on disk.");
static_assert(sizeof(PHRBAssetV5) == 64, "PHRBAssetV5 must stay packed on disk.");
static_assert(sizeof(PHRBAssetV6) == 72, "PHRBAssetV6 must stay packed on disk.");
static_assert(sizeof(PHRBAssetV7) == 76, "PHRBAssetV7 must stay packed on disk.");

inline bool phrb_magic_ok(const char magic[4])
{
	return magic[0] == 'P' && magic[1] == 'H' && magic[2] == 'R' && magic[3] == 'B';
}

template <typename T>
inline bool read_pod_from_blob(const std::vector<uint8_t> &blob, size_t offset, T &value)
{
	if (offset + sizeof(T) > blob.size())
		return false;
	std::memcpy(&value, blob.data() + offset, sizeof(T));
	return true;
}

inline bool read_c_string_from_blob(const uint8_t *data, size_t size, uint32_t offset, std::string &value)
{
	if (!data || offset >= size)
		return false;
	const char *str = reinterpret_cast<const char *>(data + offset);
	size_t len = 0;
	while (offset + len < size && str[len] != '\0')
		len++;
	if (offset + len >= size)
		return false;
	value.assign(str, len);
	return true;
}

template <typename T>
inline bool read_exact(std::ifstream &file, T &value)
{
	file.read(reinterpret_cast<char *>(&value), sizeof(value));
	return file.good();
}

inline bool read_exact(std::ifstream &file, std::vector<uint8_t> &blob)
{
	if (blob.empty())
		return true;
	file.read(reinterpret_cast<char *>(blob.data()), static_cast<std::streamsize>(blob.size()));
	return file.good();
}

inline bool gz_read_exact(gzFile fp, void *data, size_t size)
{
	auto *bytes = static_cast<uint8_t *>(data);
	size_t offset = 0;
	while (offset < size)
	{
		const unsigned chunk = static_cast<unsigned>(std::min<size_t>(size - offset, 1u << 20));
		const int ret = gzread(fp, bytes + offset, chunk);
		if (ret != int(chunk))
			return false;
		offset += chunk;
	}
	return true;
}

inline bool has_suffix(const std::string &name, const char *suffix)
{
	const size_t name_len = name.size();
	const size_t suffix_len = std::strlen(suffix);
	if (name_len < suffix_len)
		return false;

	for (size_t i = 0; i < suffix_len; i++)
	{
		char a = name[name_len - suffix_len + i];
		char b = suffix[i];
		if (a >= 'A' && a <= 'Z')
			a = char(a - 'A' + 'a');
		if (b >= 'A' && b <= 'Z')
			b = char(b - 'A' + 'a');
		if (a != b)
			return false;
	}

	return true;
}

inline bool is_legacy_cache_path(const std::string &name)
{
	return has_suffix(name, ".hts") || has_suffix(name, ".htc");
}

inline bool is_phrb_cache_path(const std::string &name)
{
	return has_suffix(name, ".phrb");
}

inline bool cache_source_allowed_by_policy(const std::string &name, ReplacementProvider::CacheSourcePolicy policy)
{
	switch (policy)
	{
	case ReplacementProvider::CacheSourcePolicy::Auto:
	case ReplacementProvider::CacheSourcePolicy::All:
		return is_legacy_cache_path(name) || is_phrb_cache_path(name);

	case ReplacementProvider::CacheSourcePolicy::PHRBOnly:
		return is_phrb_cache_path(name);

	case ReplacementProvider::CacheSourcePolicy::LegacyOnly:
		return is_legacy_cache_path(name);
	}

	return false;
}

inline uint8_t expand_4_to_8(uint32_t v)
{
	return static_cast<uint8_t>((v << 4) | v);
}

inline uint8_t expand_5_to_8(uint32_t v)
{
	return static_cast<uint8_t>((v << 3) | (v >> 2));
}

inline uint8_t expand_6_to_8(uint32_t v)
{
	return static_cast<uint8_t>((v << 2) | (v >> 4));
}

template <typename T>
inline void push_unique(std::vector<T> &values, const T &value)
{
	for (const auto &existing : values)
		if (existing == value)
			return;
	values.push_back(value);
}

template <typename T>
inline void hash_combine(size_t &seed, const T &value)
{
	seed ^= std::hash<T>{}(value) + 0x9e3779b97f4a7c15ull + (seed << 6u) + (seed >> 2u);
}
}

bool ReplacementProvider::enabled() const
{
	return enabled_;
}

void ReplacementProvider::set_enabled(bool enable)
{
	enabled_ = enable;
}

size_t ReplacementProvider::SampledLookupKeyHash::operator()(const SampledLookupKey &key) const
{
	size_t seed = 0;
	hash_combine(seed, key.sampled_fmt);
	hash_combine(seed, key.sampled_siz);
	hash_combine(seed, key.sampled_tex_offset);
	hash_combine(seed, key.sampled_stride);
	hash_combine(seed, key.sampled_width);
	hash_combine(seed, key.sampled_height);
	hash_combine(seed, key.sampled_low32);
	hash_combine(seed, key.sampled_palette_crc);
	hash_combine(seed, key.formatsize);
	hash_combine(seed, key.selector_checksum64);
	return seed;
}

size_t ReplacementProvider::SampledFamilyLookupKeyHash::operator()(const SampledFamilyLookupKey &key) const
{
	size_t seed = 0;
	hash_combine(seed, key.sampled_fmt);
	hash_combine(seed, key.sampled_siz);
	hash_combine(seed, key.sampled_tex_offset);
	hash_combine(seed, key.sampled_stride);
	hash_combine(seed, key.sampled_width);
	hash_combine(seed, key.sampled_height);
	hash_combine(seed, key.sampled_low32);
	hash_combine(seed, key.sampled_palette_crc);
	hash_combine(seed, key.formatsize);
	return seed;
}

ReplacementProvider::SampledLookupKey ReplacementProvider::make_sampled_lookup_key(uint32_t sampled_fmt,
                                                                                    uint32_t sampled_siz,
                                                                                    uint32_t sampled_tex_offset,
                                                                                    uint32_t sampled_stride,
                                                                                    uint32_t sampled_width,
                                                                                    uint32_t sampled_height,
                                                                                    uint32_t sampled_low32,
                                                                                    uint32_t sampled_palette_crc,
                                                                                    uint16_t formatsize,
                                                                                    uint64_t selector_checksum64)
{
	SampledLookupKey key = {};
	key.sampled_fmt = sampled_fmt;
	key.sampled_siz = sampled_siz;
	key.sampled_tex_offset = sampled_tex_offset;
	key.sampled_stride = sampled_stride;
	key.sampled_width = sampled_width;
	key.sampled_height = sampled_height;
	key.sampled_low32 = sampled_low32;
	key.sampled_palette_crc = sampled_palette_crc;
	key.formatsize = formatsize;
	key.selector_checksum64 = selector_checksum64;
	return key;
}

ReplacementProvider::SampledFamilyLookupKey ReplacementProvider::make_sampled_family_lookup_key(uint32_t sampled_fmt,
                                                                                                 uint32_t sampled_siz,
                                                                                                 uint32_t sampled_tex_offset,
                                                                                                 uint32_t sampled_stride,
                                                                                                 uint32_t sampled_width,
                                                                                                 uint32_t sampled_height,
                                                                                                 uint32_t sampled_low32,
                                                                                                 uint32_t sampled_palette_crc,
                                                                                                 uint16_t formatsize)
{
	SampledFamilyLookupKey key = {};
	key.sampled_fmt = sampled_fmt;
	key.sampled_siz = sampled_siz;
	key.sampled_tex_offset = sampled_tex_offset;
	key.sampled_stride = sampled_stride;
	key.sampled_width = sampled_width;
	key.sampled_height = sampled_height;
	key.sampled_low32 = sampled_low32;
	key.sampled_palette_crc = sampled_palette_crc;
	key.formatsize = formatsize;
	return key;
}

bool ReplacementProvider::prefer_sampled_duplicate_candidate(const Entry &active, const Entry &candidate)
{
	auto compare_string_pref = [](const std::string &a, const std::string &b) -> int {
		const bool a_empty = a.empty();
		const bool b_empty = b.empty();
		if (a_empty != b_empty)
			return a_empty ? 1 : -1;
		if (a < b)
			return -1;
		if (a > b)
			return 1;
		return 0;
	};

	auto compare_uint32 = [](uint32_t a, uint32_t b) -> int {
		if (a < b)
			return -1;
		if (a > b)
			return 1;
		return 0;
	};

	int cmp = compare_string_pref(candidate.phrb_replacement_id, active.phrb_replacement_id);
	if (cmp != 0)
		return cmp < 0;

	cmp = compare_string_pref(candidate.source_path, active.source_path);
	if (cmp != 0)
		return cmp < 0;

	cmp = compare_uint32(candidate.width, active.width);
	if (cmp != 0)
		return cmp < 0;

	cmp = compare_uint32(candidate.height, active.height);
	if (cmp != 0)
		return cmp < 0;

	cmp = compare_uint32(candidate.data_size, active.data_size);
	if (cmp != 0)
		return cmp < 0;

	if (candidate.blob.size() != active.blob.size())
		return candidate.blob.size() < active.blob.size();

	if (std::lexicographical_compare(candidate.blob.begin(), candidate.blob.end(), active.blob.begin(), active.blob.end()))
		return true;
	if (std::lexicographical_compare(active.blob.begin(), active.blob.end(), candidate.blob.begin(), candidate.blob.end()))
		return false;

	return false;
}

void ReplacementProvider::add_entry(Entry &&entry)
{
	const size_t index = entries_.size();
	entries_.push_back(std::move(entry));
	const Entry &stored = entries_.back();
	checksum_index_[stored.checksum64].push_back(index);
	checksum_low32_index_[uint32_t(stored.checksum64 & 0xffffffffu)].push_back(index);
	if (stored.has_native_sampled_identity)
		native_checksum_index_[stored.checksum64].push_back(index);
	else
		compat_checksum_index_[stored.checksum64].push_back(index);
	if (!stored.has_native_sampled_identity)
		compat_checksum_low32_index_[uint32_t(stored.checksum64 & 0xffffffffu)].push_back(index);
	if (stored.has_native_sampled_identity)
	{
		auto sampled_key = make_sampled_lookup_key(
			stored.sampled_fmt,
			stored.sampled_siz,
			stored.sampled_tex_offset,
			stored.sampled_stride,
			stored.sampled_width,
			stored.sampled_height,
			stored.sampled_low32,
			stored.sampled_palette_crc,
			stored.formatsize,
			stored.selector_checksum64);
		auto duplicate_it = sampled_index_.find(sampled_key);
		if (duplicate_it != sampled_index_.end())
		{
			auto inserted = sampled_duplicate_index_.emplace(sampled_key, 1u);
			if (!inserted.second)
				inserted.first->second++;
			if (prefer_sampled_duplicate_candidate(entries_[duplicate_it->second], stored))
				duplicate_it->second = index;
		}
		else
			sampled_index_[sampled_key] = index;

		auto sampled_family_key = make_sampled_family_lookup_key(
			stored.sampled_fmt,
			stored.sampled_siz,
			stored.sampled_tex_offset,
			stored.sampled_stride,
			stored.sampled_width,
			stored.sampled_height,
			stored.sampled_low32,
			stored.sampled_palette_crc,
			stored.formatsize);
		sampled_family_index_[sampled_family_key].push_back(index);
	}
	if (is_ordered_surface_selector(stored.selector_checksum64))
	{
		auto ordered_key = compose_ordered_surface_index_key(stored.checksum64, stored.formatsize);
		append_unique_ordered_surface_selector(ordered_surface_selectors_[ordered_key], stored.selector_checksum64);
	}
}

void ReplacementProvider::clear()
{
	cache_dir_.clear();
	entries_.clear();
	checksum_index_.clear();
	native_checksum_index_.clear();
	compat_checksum_index_.clear();
	checksum_low32_index_.clear();
	compat_checksum_low32_index_.clear();
	sampled_index_.clear();
	sampled_duplicate_index_.clear();
	sampled_family_index_.clear();
	ordered_surface_selectors_.clear();
}

size_t ReplacementProvider::entry_count() const
{
	return entries_.size();
}

bool ReplacementProvider::load_cache_dir(const std::string &path)
{
	return load_cache_dir(path, CacheSourcePolicy::Auto);
}

bool ReplacementProvider::load_cache_dir(const std::string &path, CacheSourcePolicy policy)
{
	clear();
	cache_dir_ = path;

	std::vector<std::string> files;
	std::vector<std::string> auto_candidates;
	std::vector<std::string> auto_phrb_files;
	std::vector<std::string> auto_legacy_files;
	DIR *dir = opendir(path.c_str());
	if (dir)
	{
		for (;;)
		{
			dirent *ent = readdir(dir);
			if (!ent)
				break;
			if (ent->d_name[0] == '.')
				continue;
			const std::string name = ent->d_name;
			if (policy == CacheSourcePolicy::Auto)
			{
				if (is_legacy_cache_path(name) || is_phrb_cache_path(name))
					auto_candidates.push_back(path + "/" + name);
				continue;
			}
			if (!cache_source_allowed_by_policy(name, policy))
				continue;
			files.push_back(path + "/" + name);
		}
		closedir(dir);
	}
	else if (policy == CacheSourcePolicy::Auto)
	{
		if (is_legacy_cache_path(path) || is_phrb_cache_path(path))
			files.push_back(path);
		else
			return false;
	}
	else if (cache_source_allowed_by_policy(path, policy))
	{
		files.push_back(path);
	}
	else
	{
		return false;
	}

	if (policy == CacheSourcePolicy::Auto && dir)
	{
		for (const auto &file : auto_candidates)
		{
			if (is_phrb_cache_path(file))
				auto_phrb_files.push_back(file);
			else if (is_legacy_cache_path(file))
				auto_legacy_files.push_back(file);
		}
		files = !auto_phrb_files.empty() ? auto_phrb_files : auto_legacy_files;
	}

	auto sort_files = [](std::vector<std::string> &candidate_files) {
		std::sort(candidate_files.begin(), candidate_files.end(), [](const std::string &a, const std::string &b) {
			const int a_priority = cache_source_priority(a);
			const int b_priority = cache_source_priority(b);
			if (a_priority != b_priority)
				return a_priority < b_priority;
			return a < b;
		});
	};
	sort_files(files);
	sort_files(auto_phrb_files);
	sort_files(auto_legacy_files);

	auto load_files = [&](const std::vector<std::string> &candidate_files) {
		for (const auto &file : candidate_files)
		{
			if (is_legacy_cache_path(file) && has_suffix(file, ".hts"))
				load_hts(file);
			else if (is_legacy_cache_path(file) && has_suffix(file, ".htc"))
				load_htc(file);
			else if (is_phrb_cache_path(file))
				load_phrb(file);
		}
	};

	load_files(files);

	if (policy == CacheSourcePolicy::Auto && dir && entries_.empty() && !auto_phrb_files.empty() && !auto_legacy_files.empty())
	{
		clear();
		cache_dir_ = path;
		load_files(auto_legacy_files);
	}

	return !entries_.empty();
}

const ReplacementProvider::Entry *ReplacementProvider::find_entry(uint64_t checksum64, uint16_t formatsize) const
{
	return find_entry(checksum64, formatsize, 0);
}

const ReplacementProvider::Entry *ReplacementProvider::find_indexed_entry(const std::unordered_map<uint64_t, std::vector<size_t>> &index_map,
                                                                          uint64_t checksum64,
                                                                          uint16_t formatsize,
                                                                          uint64_t selector_checksum64) const
{
	auto it = index_map.find(checksum64);
	if (it == index_map.end())
		return nullptr;

	const auto &indices = it->second;
	auto find_matching = [&](uint16_t candidate_formatsize, uint64_t candidate_selector) -> const ReplacementProvider::Entry * {
		for (auto itr = indices.rbegin(); itr != indices.rend(); ++itr)
		{
			const auto &entry = entries_[*itr];
			if (entry.formatsize == candidate_formatsize && entry.selector_checksum64 == candidate_selector)
				return &entry;
		}
		return nullptr;
	};

	if (selector_checksum64 != 0)
	{
		if (const auto *entry = find_matching(formatsize, selector_checksum64))
			return entry;
		if (const auto *entry = find_matching(0, selector_checksum64))
			return entry;
	}

	if (const auto *entry = find_matching(formatsize, 0))
		return entry;
	if (const auto *entry = find_matching(0, 0))
		return entry;

	if (selector_checksum64 == 0 && formatsize == 0 && !indices.empty())
		return &entries_[indices.back()];

	return nullptr;
}

const ReplacementProvider::Entry *ReplacementProvider::find_entry(uint64_t checksum64, uint16_t formatsize, uint64_t selector_checksum64) const
{
	const Entry *entry = find_indexed_entry(checksum_index_, checksum64, formatsize, selector_checksum64);
	if (entry && !entry->has_native_sampled_identity && entry->is_runtime_family_compat)
	{
		if (const auto *native_entry = find_native_entry(checksum64, formatsize, selector_checksum64))
			return native_entry;
	}
	return entry;
}

const ReplacementProvider::Entry *ReplacementProvider::find_native_entry(uint64_t checksum64, uint16_t formatsize, uint64_t selector_checksum64) const
{
	return find_indexed_entry(native_checksum_index_, checksum64, formatsize, selector_checksum64);
}

const ReplacementProvider::Entry *ReplacementProvider::find_compat_entry(uint64_t checksum64, uint16_t formatsize, uint64_t selector_checksum64) const
{
	return find_indexed_entry(compat_checksum_index_, checksum64, formatsize, selector_checksum64);
}

const ReplacementProvider::Entry *ReplacementProvider::find_sampled_entry(uint32_t sampled_fmt,
                                                                          uint32_t sampled_siz,
                                                                          uint32_t sampled_tex_offset,
                                                                          uint32_t sampled_stride,
                                                                          uint32_t sampled_width,
                                                                          uint32_t sampled_height,
                                                                          uint32_t sampled_low32,
                                                                          uint32_t palette_crc,
                                                                          uint16_t formatsize,
                                                                          uint64_t selector_checksum64) const
{
	auto find_matching = [&](uint16_t candidate_formatsize, uint64_t candidate_selector) -> const Entry * {
		auto key = make_sampled_lookup_key(
			sampled_fmt,
			sampled_siz,
			sampled_tex_offset,
			sampled_stride,
			sampled_width,
			sampled_height,
			sampled_low32,
			palette_crc,
			candidate_formatsize,
			candidate_selector);
		auto it = sampled_index_.find(key);
		if (it == sampled_index_.end())
			return nullptr;
		return &entries_[it->second];
	};

	if (selector_checksum64 != 0)
	{
		if (const Entry *entry = find_matching(formatsize, selector_checksum64))
			return entry;
		if (const Entry *entry = find_matching(0, selector_checksum64))
			return entry;
	}

	if (const Entry *entry = find_matching(formatsize, 0))
		return entry;
	if (const Entry *entry = find_matching(0, 0))
		return entry;

	return nullptr;
}

const ReplacementProvider::Entry *ReplacementProvider::find_unique_sampled_family_entry(uint32_t sampled_fmt,
                                                                                        uint32_t sampled_siz,
                                                                                        uint32_t sampled_tex_offset,
                                                                                        uint32_t sampled_stride,
                                                                                        uint32_t sampled_width,
                                                                                        uint32_t sampled_height,
                                                                                        uint32_t sampled_low32,
                                                                                        uint32_t palette_crc,
                                                                                        uint16_t formatsize,
                                                                                        uint64_t *resolved_selector_checksum64) const
{
	return find_singleton_sampled_family_entry(
		sampled_fmt,
		sampled_siz,
		sampled_tex_offset,
		sampled_stride,
		sampled_width,
		sampled_height,
		sampled_low32,
		palette_crc,
		formatsize,
		false,
		resolved_selector_checksum64,
		nullptr);
}

const ReplacementProvider::Entry *ReplacementProvider::find_singleton_sampled_family_entry(uint32_t sampled_fmt,
                                                                                            uint32_t sampled_siz,
                                                                                            uint32_t sampled_tex_offset,
                                                                                            uint32_t sampled_stride,
                                                                                            uint32_t sampled_width,
                                                                                            uint32_t sampled_height,
                                                                                            uint32_t sampled_low32,
                                                                                            uint32_t palette_crc,
                                                                                            uint16_t formatsize,
                                                                                            bool allow_ordered_surface_selectors,
                                                                                            uint64_t *resolved_selector_checksum64,
                                                                                            bool *resolved_ordered_surface_singleton) const
{
	auto find_family = [&](uint16_t candidate_formatsize) -> const std::vector<size_t> * {
		auto key = make_sampled_family_lookup_key(
			sampled_fmt,
			sampled_siz,
			sampled_tex_offset,
			sampled_stride,
			sampled_width,
			sampled_height,
			sampled_low32,
			palette_crc,
			candidate_formatsize);
		auto it = sampled_family_index_.find(key);
		if (it == sampled_family_index_.end())
			return nullptr;
		return &it->second;
	};

	const std::vector<size_t> *exact_family = find_family(formatsize);
	const std::vector<size_t> *generic_family = find_family(0);
	if (!exact_family && !generic_family)
		return nullptr;

	const std::vector<size_t> &active_family = exact_family ? *exact_family : *generic_family;
	std::vector<uint64_t> unique_selectors;
	for (size_t index : active_family)
		push_unique(unique_selectors, entries_[index].selector_checksum64);

	if (unique_selectors.size() != 1)
		return nullptr;

	const uint64_t selected_selector_checksum64 = unique_selectors.front();
	const bool ordered_surface_singleton =
		selected_selector_checksum64 != 0 && is_ordered_surface_selector(selected_selector_checksum64);
	if (ordered_surface_singleton && !allow_ordered_surface_selectors)
		return nullptr;

	const Entry *entry = find_sampled_entry(
		sampled_fmt,
		sampled_siz,
		sampled_tex_offset,
		sampled_stride,
		sampled_width,
		sampled_height,
		sampled_low32,
		palette_crc,
		formatsize,
		selected_selector_checksum64);
	if (!entry)
		return nullptr;

	if (resolved_selector_checksum64)
		*resolved_selector_checksum64 = selected_selector_checksum64;
	if (resolved_ordered_surface_singleton)
		*resolved_ordered_surface_singleton = ordered_surface_singleton;
	return entry;
}

void ReplacementProvider::populate_meta_from_entry(const Entry &entry, ReplacementMeta *out) const
{
	if (!out)
		return;

	out->repl_w = entry.width;
	out->repl_h = entry.height;
	out->orig_w = 0;
	out->orig_h = 0;
	out->vk_image_index = 0xffffffffu;
	out->has_mips = false;
	out->srgb = false;
}

void ReplacementProvider::populate_identity_from_entry(const Entry &entry, NativeSampledIdentity *out) const
{
	if (!out)
		return;

	out->valid = entry.has_native_sampled_identity;
	out->sampled_fmt = entry.sampled_fmt;
	out->sampled_siz = entry.sampled_siz;
	out->sampled_tex_offset = entry.sampled_tex_offset;
	out->sampled_stride = entry.sampled_stride;
	out->sampled_width = entry.sampled_width;
	out->sampled_height = entry.sampled_height;
	out->sampled_low32 = entry.sampled_low32;
	out->sampled_palette_crc = entry.sampled_palette_crc;
	out->formatsize = entry.formatsize;
	out->selector_checksum64 = entry.selector_checksum64;
}

bool ReplacementProvider::populate_resolution_from_entry(const Entry *entry,
                                                         ReplacementResolutionKind kind,
                                                         bool ordered_surface_singleton,
                                                         ReplacementResolution *out) const
{
	if (!entry || !out)
		return false;

	out->available = true;
	out->kind = kind;
	populate_meta_from_entry(*entry, &out->meta);
	populate_identity_from_entry(*entry, &out->identity);
	out->source_class = entry->has_native_sampled_identity ? ResolvedEntrySourceClass::Native : ResolvedEntrySourceClass::Compat;
	out->resolved_checksum64 = entry->checksum64;
	out->resolved_selector_checksum64 = entry->selector_checksum64;
	out->ordered_surface_singleton = ordered_surface_singleton;
	out->matched_preferred_palette = false;
	return true;
}

bool ReplacementProvider::lookup(uint64_t checksum64, uint16_t formatsize, ReplacementMeta *out) const
{
	return lookup_with_selector(checksum64, formatsize, 0, out);
}

uint64_t ReplacementProvider::ordered_surface_slot_selector_checksum64(uint32_t slot_index)
{
	return ORDERED_SURFACE_SELECTOR_TAG | uint64_t(slot_index);
}

uint32_t ReplacementProvider::ordered_surface_selector_count(uint64_t checksum64, uint16_t formatsize) const
{
	auto it = ordered_surface_selectors_.find(compose_ordered_surface_index_key(checksum64, formatsize));
	if (it == ordered_surface_selectors_.end())
		return 0;
	return uint32_t(it->second.size());
}

uint64_t ReplacementProvider::ordered_surface_selector_checksum64(uint64_t checksum64, uint16_t formatsize, uint32_t selector_index) const
{
	auto it = ordered_surface_selectors_.find(compose_ordered_surface_index_key(checksum64, formatsize));
	if (it == ordered_surface_selectors_.end() || selector_index >= it->second.size())
		return 0;
	return it->second[selector_index];
}

bool ReplacementProvider::lookup_with_selector(uint64_t checksum64, uint16_t formatsize, uint64_t selector_checksum64, ReplacementMeta *out) const
{
	if (!enabled_ || !out)
		return false;

	const Entry *entry = find_entry(checksum64, formatsize, selector_checksum64);
	if (!entry)
		return false;

	populate_meta_from_entry(*entry, out);
	return true;
}

bool ReplacementProvider::lookup_with_selector_and_identity(uint64_t checksum64,
                                                            uint16_t formatsize,
                                                            uint64_t selector_checksum64,
                                                            ReplacementMeta *out,
                                                            NativeSampledIdentity *identity,
                                                            ResolvedEntrySourceClass *resolved_source_class,
                                                            uint64_t *resolved_checksum64,
                                                            uint64_t *resolved_selector_checksum64) const
{
	if (!enabled_ || !out)
		return false;

	const Entry *entry = find_entry(checksum64, formatsize, selector_checksum64);
	if (!entry)
		return false;

	populate_meta_from_entry(*entry, out);
	if (resolved_source_class)
		*resolved_source_class = entry->has_native_sampled_identity ? ResolvedEntrySourceClass::Native : ResolvedEntrySourceClass::Compat;
	populate_identity_from_entry(*entry, identity);
	if (resolved_checksum64)
		*resolved_checksum64 = entry->checksum64;
	if (resolved_selector_checksum64)
		*resolved_selector_checksum64 = entry->selector_checksum64;
	return true;
}

bool ReplacementProvider::resolve_with_selector(uint64_t checksum64,
                                                uint16_t formatsize,
                                                uint64_t selector_checksum64,
                                                ReplacementResolution *out) const
{
	if (!enabled_ || !out)
		return false;

	const Entry *entry = find_entry(checksum64, formatsize, selector_checksum64);
	if (!entry)
		return false;

	ReplacementResolutionKind kind = ReplacementResolutionKind::GenericUnknown;
	if (entry->has_native_sampled_identity)
		kind = ReplacementResolutionKind::GenericNativeIdentity;
	else
		kind = ReplacementResolutionKind::GenericCompat;

	return populate_resolution_from_entry(entry, kind, false, out);
}

bool ReplacementProvider::resolve_upload_candidate(uint64_t checksum64,
                                                   uint16_t formatsize,
                                                   uint32_t sampled_fmt,
                                                   uint32_t sampled_siz,
                                                   uint32_t sampled_tex_offset,
                                                   uint32_t sampled_stride,
                                                   uint32_t sampled_width,
                                                   uint32_t sampled_height,
                                                   uint32_t sampled_low32,
                                                   uint32_t palette_crc,
                                                   uint64_t selector_checksum64,
                                                   ReplacementResolution *out) const
{
	if (!enabled_ || !out)
		return false;

	bool ordered_surface_singleton = false;
	const Entry *family_entry = find_singleton_sampled_family_entry(
		sampled_fmt,
		sampled_siz,
		sampled_tex_offset,
		sampled_stride,
		sampled_width,
		sampled_height,
		sampled_low32,
		palette_crc,
		formatsize,
		true,
		nullptr,
		&ordered_surface_singleton);
	if (family_entry)
		return populate_resolution_from_entry(
			family_entry,
			ReplacementResolutionKind::SampledFamilySingleton,
			ordered_surface_singleton,
			out);

	const Entry *native_entry = find_native_entry(checksum64, formatsize, selector_checksum64);
	if (native_entry)
		return populate_resolution_from_entry(
			native_entry,
			ReplacementResolutionKind::ExactNativeSampled,
			false,
			out);

	return resolve_with_selector(checksum64, formatsize, selector_checksum64, out);
}

bool ReplacementProvider::resolve_sampled_candidate(uint32_t sampled_fmt,
                                                    uint32_t sampled_siz,
                                                    uint32_t sampled_tex_offset,
                                                    uint32_t sampled_stride,
                                                    uint32_t sampled_width,
                                                    uint32_t sampled_height,
                                                    uint32_t sampled_low32,
                                                    uint32_t palette_crc,
                                                    uint16_t formatsize,
                                                    uint64_t selector_checksum64,
                                                    ReplacementResolution *out) const
{
	if (!enabled_ || !out)
		return false;

	const Entry *sampled_entry = find_sampled_entry(
		sampled_fmt,
		sampled_siz,
		sampled_tex_offset,
		sampled_stride,
		sampled_width,
		sampled_height,
		sampled_low32,
		palette_crc,
		formatsize,
		selector_checksum64);
	if (sampled_entry)
		return populate_resolution_from_entry(
			sampled_entry,
			ReplacementResolutionKind::SampledExactSelector,
			false,
			out);

	bool ordered_surface_singleton = false;
	const Entry *family_entry = find_singleton_sampled_family_entry(
		sampled_fmt,
		sampled_siz,
		sampled_tex_offset,
		sampled_stride,
		sampled_width,
		sampled_height,
		sampled_low32,
		palette_crc,
		formatsize,
		true,
		nullptr,
		&ordered_surface_singleton);
	if (family_entry)
		return populate_resolution_from_entry(
			family_entry,
			ReplacementResolutionKind::SampledFamilySingleton,
			ordered_surface_singleton,
			out);

	return false;
}

const ReplacementProvider::Entry *ReplacementProvider::find_ci_low32_entry(uint32_t checksum_low32,
                                                                           uint16_t formatsize,
                                                                           uint32_t preferred_palette_crc,
                                                                           uint32_t repl_w,
                                                                           uint32_t repl_h,
                                                                           CILow32ResolutionMode mode,
                                                                           bool *matched_preferred_palette) const
{
	if (!enabled_)
		return nullptr;

	if (matched_preferred_palette)
		*matched_preferred_palette = false;

	auto it = compat_checksum_low32_index_.find(checksum_low32);
	if (it == compat_checksum_low32_index_.end())
		return nullptr;

	auto find_matching = [&](uint16_t candidate_formatsize, auto &&predicate) -> const Entry * {
		for (auto itr = it->second.rbegin(); itr != it->second.rend(); ++itr)
		{
			const Entry &entry = entries_[*itr];
			if (entry.formatsize != candidate_formatsize)
				continue;
			if (!predicate(entry))
				continue;
			return &entry;
		}
		return nullptr;
	};

	auto collect_unique_checksums = [&](uint16_t candidate_formatsize, std::vector<uint64_t> &unique) {
		for (size_t index : it->second)
		{
			const Entry &entry = entries_[index];
			if (entry.formatsize != candidate_formatsize)
				continue;

			bool seen = false;
			for (uint64_t existing : unique)
			{
				if (existing == entry.checksum64)
				{
					seen = true;
					break;
				}
			}
			if (!seen)
				unique.push_back(entry.checksum64);
		}
	};

	switch (mode)
	{
	case CILow32ResolutionMode::SelectedDims:
	{
		const Entry *entry = find_matching(formatsize, [&](const Entry &entry) {
			return entry.width == repl_w && entry.height == repl_h;
		});
		if (!entry)
			entry = find_matching(0, [&](const Entry &entry) {
				return entry.width == repl_w && entry.height == repl_h;
			});
		return entry;
	}

	case CILow32ResolutionMode::ReplacementDimsUnique:
	{
		auto pick_candidate = [&](uint16_t candidate_formatsize) -> const Entry * {
			const Entry *selected = nullptr;
			for (auto itr = it->second.rbegin(); itr != it->second.rend(); ++itr)
			{
				const Entry &entry = entries_[*itr];
				if (entry.formatsize != candidate_formatsize)
					continue;

				if (!selected)
				{
					selected = &entry;
					continue;
				}

				if (entry.width != selected->width || entry.height != selected->height)
					return nullptr;
			}
			return selected;
		};

		const Entry *entry = pick_candidate(formatsize);
		if (!entry)
			entry = pick_candidate(0);
		return entry;
	}

	case CILow32ResolutionMode::Unique:
	{
		std::vector<uint64_t> unique;
		collect_unique_checksums(formatsize, unique);
		if (unique.empty())
			collect_unique_checksums(0, unique);

		if (unique.size() != 1)
			return nullptr;

		return find_compat_entry(unique.front(), formatsize, 0);
	}

	case CILow32ResolutionMode::Any:
	{
		auto pick_candidate = [&](uint16_t candidate_formatsize, uint32_t palette_crc_or_any) -> const Entry * {
			for (auto itr = it->second.rbegin(); itr != it->second.rend(); ++itr)
			{
				const Entry &entry = entries_[*itr];
				if (entry.formatsize != candidate_formatsize)
					continue;

				const uint32_t entry_palette_crc = uint32_t((entry.checksum64 >> 32) & 0xffffffffu);
				if (palette_crc_or_any != 0 && entry_palette_crc != palette_crc_or_any)
					continue;

				return &entry;
			}
			return nullptr;
		};

		const Entry *entry = nullptr;
		bool matched_preferred = false;
		if (preferred_palette_crc != 0)
		{
			entry = pick_candidate(formatsize, preferred_palette_crc);
			if (!entry)
				entry = pick_candidate(0, preferred_palette_crc);
			if (entry)
				matched_preferred = true;
		}

		if (!entry)
			entry = pick_candidate(formatsize, 0);
		if (!entry)
			entry = pick_candidate(0, 0);

		if (matched_preferred_palette)
			*matched_preferred_palette = matched_preferred;
		return entry;
	}
	}

	return nullptr;
}

bool ReplacementProvider::lookup_native_with_selector(uint64_t checksum64,
                                                      uint16_t formatsize,
                                                      uint64_t selector_checksum64,
                                                      ReplacementMeta *out,
                                                      NativeSampledIdentity *identity,
                                                      uint64_t *resolved_checksum64) const
{
	if (!enabled_ || !out)
		return false;

	const Entry *entry = find_native_entry(checksum64, formatsize, selector_checksum64);
	if (!entry)
		return false;

	populate_meta_from_entry(*entry, out);
	populate_identity_from_entry(*entry, identity);
	if (resolved_checksum64)
		*resolved_checksum64 = entry->checksum64;
	return true;
}

bool ReplacementProvider::lookup_compat_with_selector(uint64_t checksum64, uint16_t formatsize, uint64_t selector_checksum64, ReplacementMeta *out) const
{
	if (!enabled_ || !out)
		return false;

	const Entry *entry = find_compat_entry(checksum64, formatsize, selector_checksum64);
	if (!entry)
		return false;

	populate_meta_from_entry(*entry, out);
	return true;
}

bool ReplacementProvider::lookup_sampled_with_selector(uint32_t sampled_fmt,
                                                       uint32_t sampled_siz,
                                                       uint32_t sampled_tex_offset,
                                                       uint32_t sampled_stride,
                                                       uint32_t sampled_width,
                                                       uint32_t sampled_height,
                                                       uint32_t sampled_low32,
                                                       uint32_t palette_crc,
                                                       uint16_t formatsize,
                                                       uint64_t selector_checksum64,
                                                       ReplacementMeta *out,
                                                       uint64_t *resolved_checksum64) const
{
	if (!enabled_ || !out)
		return false;

	const Entry *entry = find_sampled_entry(
		sampled_fmt,
		sampled_siz,
		sampled_tex_offset,
		sampled_stride,
		sampled_width,
		sampled_height,
		sampled_low32,
		palette_crc,
		formatsize,
		selector_checksum64);
	if (!entry)
		return false;

	populate_meta_from_entry(*entry, out);
	if (resolved_checksum64)
		*resolved_checksum64 = entry->checksum64;
	return true;
}

bool ReplacementProvider::lookup_sampled_family_unique(uint32_t sampled_fmt,
                                                       uint32_t sampled_siz,
                                                       uint32_t sampled_tex_offset,
                                                       uint32_t sampled_stride,
                                                       uint32_t sampled_width,
                                                       uint32_t sampled_height,
                                                       uint32_t sampled_low32,
                                                       uint32_t palette_crc,
                                                       uint16_t formatsize,
                                                       ReplacementMeta *out,
                                                       uint64_t *resolved_checksum64,
                                                       uint64_t *resolved_selector_checksum64) const
{
	if (!enabled_ || !out)
		return false;

	const Entry *entry = find_unique_sampled_family_entry(
		sampled_fmt,
		sampled_siz,
		sampled_tex_offset,
		sampled_stride,
		sampled_width,
		sampled_height,
		sampled_low32,
		palette_crc,
		formatsize,
		resolved_selector_checksum64);
	if (!entry)
		return false;

	populate_meta_from_entry(*entry, out);
	if (resolved_checksum64)
		*resolved_checksum64 = entry->checksum64;
	return true;
}

bool ReplacementProvider::lookup_sampled_family_singleton(uint32_t sampled_fmt,
                                                          uint32_t sampled_siz,
                                                          uint32_t sampled_tex_offset,
                                                          uint32_t sampled_stride,
                                                          uint32_t sampled_width,
                                                          uint32_t sampled_height,
                                                          uint32_t sampled_low32,
                                                          uint32_t palette_crc,
                                                          uint16_t formatsize,
                                                          ReplacementMeta *out,
                                                          uint64_t *resolved_checksum64,
                                                          uint64_t *resolved_selector_checksum64,
                                                          bool *resolved_ordered_surface_singleton) const
{
	if (!enabled_ || !out)
		return false;

	const Entry *entry = find_singleton_sampled_family_entry(
		sampled_fmt,
		sampled_siz,
		sampled_tex_offset,
		sampled_stride,
		sampled_width,
		sampled_height,
		sampled_low32,
		palette_crc,
		formatsize,
		true,
		resolved_selector_checksum64,
		resolved_ordered_surface_singleton);
	if (!entry)
		return false;

	populate_meta_from_entry(*entry, out);
	if (resolved_checksum64)
		*resolved_checksum64 = entry->checksum64;
	return true;
}

bool ReplacementProvider::decode_sampled_rgba8_with_selector(uint32_t sampled_fmt,
                                                             uint32_t sampled_siz,
                                                             uint32_t sampled_tex_offset,
                                                             uint32_t sampled_stride,
                                                             uint32_t sampled_width,
                                                             uint32_t sampled_height,
                                                             uint32_t sampled_low32,
                                                             uint32_t palette_crc,
                                                             uint16_t formatsize,
                                                             uint64_t selector_checksum64,
                                                             ReplacementImage *out,
                                                             uint64_t *resolved_checksum64) const
{
	if (!enabled_ || !out)
		return false;

	const Entry *entry = find_sampled_entry(
		sampled_fmt,
		sampled_siz,
		sampled_tex_offset,
		sampled_stride,
		sampled_width,
		sampled_height,
		sampled_low32,
		palette_crc,
		formatsize,
		selector_checksum64);
	if (!entry)
		return false;

	if (!decode_entry_rgba8(*entry, out))
		return false;

	if (resolved_checksum64)
		*resolved_checksum64 = entry->checksum64;
	return true;
}

bool ReplacementProvider::lookup_ci_low32_unique(uint32_t checksum_low32,
                                                 uint16_t formatsize,
                                                 ReplacementMeta *out,
                                                 uint64_t *resolved_checksum64) const
{
	if (!enabled_ || !out)
		return false;

	const Entry *entry = find_ci_low32_entry(
		checksum_low32,
		formatsize,
		0,
		0,
		0,
		CILow32ResolutionMode::Unique);
	if (!entry)
		return false;

	populate_meta_from_entry(*entry, out);
	if (resolved_checksum64)
		*resolved_checksum64 = entry->checksum64;
	return true;
}

bool ReplacementProvider::lookup_ci_low32_repl_dims_unique(uint32_t checksum_low32,
                                                           uint16_t formatsize,
                                                           ReplacementMeta *out,
                                                           uint64_t *resolved_checksum64) const
{
	if (!enabled_ || !out)
		return false;

	const Entry *entry = find_ci_low32_entry(
		checksum_low32,
		formatsize,
		0,
		0,
		0,
		CILow32ResolutionMode::ReplacementDimsUnique);
	if (!entry)
		return false;

	populate_meta_from_entry(*entry, out);
	if (resolved_checksum64)
		*resolved_checksum64 = entry->checksum64;
	return true;
}

bool ReplacementProvider::lookup_ci_low32_selected_dims(uint32_t checksum_low32,
                                                        uint16_t formatsize,
                                                        uint32_t repl_w,
                                                        uint32_t repl_h,
                                                        ReplacementMeta *out,
                                                        uint64_t *resolved_checksum64) const
{
	if (!enabled_ || !out)
		return false;

	const Entry *entry = find_ci_low32_entry(
		checksum_low32,
		formatsize,
		0,
		repl_w,
		repl_h,
		CILow32ResolutionMode::SelectedDims);
	if (!entry)
		return false;

	populate_meta_from_entry(*entry, out);
	if (resolved_checksum64)
		*resolved_checksum64 = entry->checksum64;
	return true;
}

bool ReplacementProvider::lookup_ci_low32_any(uint32_t checksum_low32,
                                              uint16_t formatsize,
                                              uint32_t preferred_palette_crc,
                                              ReplacementMeta *out,
                                              uint64_t *resolved_checksum64,
                                              bool *matched_preferred_palette) const
{
	if (!enabled_ || !out)
		return false;

	bool matched_preferred = false;
	const Entry *entry = find_ci_low32_entry(
		checksum_low32,
		formatsize,
		preferred_palette_crc,
		0,
		0,
		CILow32ResolutionMode::Any,
		&matched_preferred);
	if (!entry)
		return false;

	populate_meta_from_entry(*entry, out);
	if (resolved_checksum64)
		*resolved_checksum64 = entry->checksum64;
	if (matched_preferred_palette)
		*matched_preferred_palette = matched_preferred;
	return true;
}

bool ReplacementProvider::resolve_ci_low32_candidate(uint32_t checksum_low32,
                                                     uint16_t formatsize,
                                                     uint32_t preferred_palette_crc,
                                                     uint32_t repl_w,
                                                     uint32_t repl_h,
                                                     CILow32ResolutionMode mode,
                                                     ReplacementResolution *out) const
{
	if (!enabled_ || !out)
		return false;

	bool matched_preferred = false;
	const Entry *entry = find_ci_low32_entry(
		checksum_low32,
		formatsize,
		preferred_palette_crc,
		repl_w,
		repl_h,
		mode,
		&matched_preferred);
	if (!entry)
		return false;

	ReplacementResolutionKind kind = ReplacementResolutionKind::GenericCompat;
	switch (mode)
	{
	case CILow32ResolutionMode::SelectedDims:
		kind = ReplacementResolutionKind::CILow32SelectedDims;
		break;
	case CILow32ResolutionMode::ReplacementDimsUnique:
		kind = ReplacementResolutionKind::CILow32ReplacementDimsUnique;
		break;
	case CILow32ResolutionMode::Unique:
		kind = ReplacementResolutionKind::CILow32Unique;
		break;
	case CILow32ResolutionMode::Any:
		kind = ReplacementResolutionKind::CILow32Any;
		break;
	}

	if (!populate_resolution_from_entry(entry, kind, false, out))
		return false;

	out->matched_preferred_palette = matched_preferred;
	return true;
}

bool ReplacementProvider::describe_sampled_family(uint32_t sampled_fmt,
                                                  uint32_t sampled_siz,
                                                  uint32_t sampled_tex_offset,
                                                  uint32_t sampled_stride,
                                                  uint32_t sampled_width,
                                                  uint32_t sampled_height,
                                                  uint32_t sampled_low32,
                                                  uint32_t palette_crc,
                                                  uint16_t formatsize,
                                                  uint64_t requested_selector_checksum64,
                                                  SampledFamilyDiagnostics *out) const
{
	if (!enabled_ || !out)
		return false;

	auto find_family = [&](uint16_t candidate_formatsize) -> const std::vector<size_t> * {
		auto key = make_sampled_family_lookup_key(
			sampled_fmt,
			sampled_siz,
			sampled_tex_offset,
			sampled_stride,
			sampled_width,
			sampled_height,
			sampled_low32,
			palette_crc,
			candidate_formatsize);
		auto it = sampled_family_index_.find(key);
		if (it == sampled_family_index_.end())
			return nullptr;
		return &it->second;
	};

	const std::vector<size_t> *exact_family = find_family(formatsize);
	const std::vector<size_t> *generic_family = find_family(0);
	if (!exact_family && !generic_family)
		return false;

	SampledFamilyDiagnostics diag = {};
	diag.available = true;
	diag.exact_formatsize_entries = exact_family ? uint32_t(exact_family->size()) : 0;
	diag.generic_formatsize_entries = generic_family ? uint32_t(generic_family->size()) : 0;
	diag.prefer_exact_formatsize = exact_family != nullptr;

	const std::vector<size_t> &active_family = exact_family ? *exact_family : *generic_family;
	std::vector<uint64_t> unique_checksums;
	std::vector<uint64_t> unique_selectors;
	std::vector<uint64_t> unique_repl_dims;

	for (size_t index : active_family)
	{
		const Entry &entry = entries_[index];
		diag.active_entry_count++;
		push_unique(unique_checksums, entry.checksum64);
		push_unique(unique_repl_dims, (uint64_t(entry.width) << 32) | uint64_t(entry.height));
		if (entry.selector_checksum64 != 0)
		{
			push_unique(unique_selectors, entry.selector_checksum64);
			diag.active_has_any_selector = true;
			if (entry.selector_checksum64 == requested_selector_checksum64)
				diag.active_matching_selector_count++;
			if (is_ordered_surface_selector(entry.selector_checksum64))
			{
				diag.active_has_ordered_surface_selectors = true;
				diag.active_ordered_surface_selector_count++;
			}
		}
		else
			diag.active_zero_selector_count++;

		if (diag.sample_repl_w == 0 && diag.sample_repl_h == 0)
		{
			diag.sample_repl_w = entry.width;
			diag.sample_repl_h = entry.height;
		}
		if (diag.sample_policy_key.empty())
			diag.sample_policy_key = entry.phrb_policy_key;
		if (diag.sample_replacement_id.empty())
			diag.sample_replacement_id = entry.phrb_replacement_id;
		if (diag.sample_sampled_object_id.empty())
			diag.sample_sampled_object_id = entry.phrb_sampled_object_id;
	}

	diag.active_unique_checksum_count = uint32_t(unique_checksums.size());
	diag.active_unique_selector_count = uint32_t(unique_selectors.size());
	diag.active_unique_repl_dim_count = uint32_t(unique_repl_dims.size());
	diag.active_repl_dims_uniform = diag.active_unique_repl_dim_count == 1 && diag.active_entry_count > 0;
	if (diag.active_repl_dims_uniform && !unique_repl_dims.empty())
	{
		diag.sample_repl_w = uint32_t(unique_repl_dims.front() >> 32);
		diag.sample_repl_h = uint32_t(unique_repl_dims.front() & 0xffffffffu);
	}
	diag.active_is_pool =
		diag.active_unique_selector_count > 1 ||
		(diag.active_entry_count > 1 && diag.active_matching_selector_count == 0);
	*out = diag;
	return true;
}

bool ReplacementProvider::describe_ci_low32_family(uint32_t checksum_low32,
                                                   uint16_t formatsize,
                                                   uint32_t preferred_palette_crc,
                                                   CILow32FamilyDiagnostics *out) const
{
	if (!enabled_ || !out)
		return false;

	auto it = compat_checksum_low32_index_.find(checksum_low32);
	if (it == compat_checksum_low32_index_.end())
		return false;

	CILow32FamilyDiagnostics diag = {};
	diag.available = true;

	for (size_t index : it->second)
	{
		const Entry &entry = entries_[index];
		if (entry.formatsize == formatsize)
			diag.exact_formatsize_entries++;
		else if (entry.formatsize == 0)
			diag.generic_formatsize_entries++;
	}

	const bool use_exact_formatsize = diag.exact_formatsize_entries > 0;
	diag.prefer_exact_formatsize = use_exact_formatsize;
	const uint16_t active_formatsize = use_exact_formatsize ? formatsize : 0;

	std::vector<uint64_t> unique_checksums;
	std::vector<uint32_t> unique_palettes;
	std::vector<uint64_t> unique_repl_dims;

	for (size_t index : it->second)
	{
		const Entry &entry = entries_[index];
		if (entry.formatsize != active_formatsize)
			continue;

		diag.active_entry_count++;
		push_unique(unique_checksums, entry.checksum64);
		push_unique(unique_palettes, uint32_t((entry.checksum64 >> 32) & 0xffffffffu));
		push_unique(unique_repl_dims, (uint64_t(entry.width) << 32) | uint64_t(entry.height));

		if (((entry.checksum64 >> 32) & 0xffffffffu) == preferred_palette_crc)
			diag.active_preferred_palette_match_count++;

		if (diag.sample_repl_w == 0 && diag.sample_repl_h == 0)
		{
			diag.sample_repl_w = entry.width;
			diag.sample_repl_h = entry.height;
		}
	}

	diag.active_unique_checksum_count = uint32_t(unique_checksums.size());
	diag.active_unique_palette_count = uint32_t(unique_palettes.size());
	diag.active_unique_repl_dim_count = uint32_t(unique_repl_dims.size());
	diag.active_repl_dims_uniform = diag.active_unique_repl_dim_count == 1 && diag.active_entry_count > 0;
	if (diag.active_repl_dims_uniform && !unique_repl_dims.empty())
	{
		diag.sample_repl_w = uint32_t(unique_repl_dims.front() >> 32);
		diag.sample_repl_h = uint32_t(unique_repl_dims.front() & 0xffffffffu);
	}

	*out = diag;
	return true;
}

uint32_t ReplacementProvider::expected_decoded_size(const Entry &entry)
{
	uint64_t bpp = 0;
	if (entry.texture_format == GL_RGBA && entry.pixel_type == GL_UNSIGNED_BYTE)
		bpp = 4;
	else if (entry.texture_format == GL_RGB && entry.pixel_type == GL_UNSIGNED_BYTE)
		bpp = 3;
	else if (entry.texture_format == GL_RGB && entry.pixel_type == GL_UNSIGNED_SHORT_5_6_5)
		bpp = 2;
	else if (entry.texture_format == GL_RGBA &&
	         (entry.pixel_type == GL_UNSIGNED_SHORT_4_4_4_4 || entry.pixel_type == GL_UNSIGNED_SHORT_5_5_5_1))
		bpp = 2;
	else if (entry.texture_format == GL_LUMINANCE && entry.pixel_type == GL_UNSIGNED_BYTE)
		bpp = 1;
	else if (entry.format == GL_RGBA8)
		bpp = 4;
	else if (entry.format == GL_RGB8)
		bpp = 3;

	const uint64_t pixels = uint64_t(entry.width) * uint64_t(entry.height);
	const uint64_t bytes = pixels * bpp;
	if (bpp == 0 || bytes > UINT32_MAX)
		return 0;
	return static_cast<uint32_t>(bytes);
}

bool ReplacementProvider::decompress_if_needed(const Entry &entry, const std::vector<uint8_t> &blob, std::vector<uint8_t> &pixel_data)
{
	if ((entry.format & GL_TEXFMT_GZ) == 0)
	{
		pixel_data = blob;
		return true;
	}

	const uint32_t expected_size = expected_decoded_size(entry);
	if (expected_size == 0)
		return false;

	pixel_data.resize(expected_size);
	uLongf dst_len = expected_size;
	const int ret = uncompress(pixel_data.data(), &dst_len, blob.data(), static_cast<uLong>(blob.size()));
	if (ret != Z_OK)
		return false;

	if (dst_len != expected_size)
		pixel_data.resize(static_cast<size_t>(dst_len));
	return true;
}

bool ReplacementProvider::decode_pixels_rgba8(const Entry &entry, const std::vector<uint8_t> &pixel_data, std::vector<uint8_t> &rgba8)
{
	const uint64_t pixel_count = uint64_t(entry.width) * uint64_t(entry.height);
	if (pixel_count == 0 || pixel_count > (SIZE_MAX / 4))
		return false;

	rgba8.resize(static_cast<size_t>(pixel_count) * 4);

	if (entry.texture_format == GL_RGBA && entry.pixel_type == GL_UNSIGNED_BYTE)
	{
		if (pixel_data.size() < rgba8.size())
			return false;
		std::copy(pixel_data.begin(), pixel_data.begin() + ptrdiff_t(rgba8.size()), rgba8.begin());
		return true;
	}

	if (entry.texture_format == GL_RGB && entry.pixel_type == GL_UNSIGNED_BYTE)
	{
		if (pixel_data.size() < size_t(pixel_count) * 3)
			return false;
		for (size_t i = 0; i < size_t(pixel_count); i++)
		{
			rgba8[4 * i + 0] = pixel_data[3 * i + 0];
			rgba8[4 * i + 1] = pixel_data[3 * i + 1];
			rgba8[4 * i + 2] = pixel_data[3 * i + 2];
			rgba8[4 * i + 3] = 255;
		}
		return true;
	}

	if (entry.texture_format == GL_RGB && entry.pixel_type == GL_UNSIGNED_SHORT_5_6_5)
	{
		if (pixel_data.size() < size_t(pixel_count) * 2)
			return false;
		for (size_t i = 0; i < size_t(pixel_count); i++)
		{
			const uint16_t v = uint16_t(pixel_data[2 * i + 0]) | (uint16_t(pixel_data[2 * i + 1]) << 8);
			rgba8[4 * i + 0] = expand_5_to_8((v >> 11) & 0x1f);
			rgba8[4 * i + 1] = expand_6_to_8((v >> 5) & 0x3f);
			rgba8[4 * i + 2] = expand_5_to_8(v & 0x1f);
			rgba8[4 * i + 3] = 255;
		}
		return true;
	}

	if (entry.texture_format == GL_RGBA && entry.pixel_type == GL_UNSIGNED_SHORT_5_5_5_1)
	{
		if (pixel_data.size() < size_t(pixel_count) * 2)
			return false;
		for (size_t i = 0; i < size_t(pixel_count); i++)
		{
			const uint16_t v = uint16_t(pixel_data[2 * i + 0]) | (uint16_t(pixel_data[2 * i + 1]) << 8);
			rgba8[4 * i + 0] = expand_5_to_8((v >> 11) & 0x1f);
			rgba8[4 * i + 1] = expand_5_to_8((v >> 6) & 0x1f);
			rgba8[4 * i + 2] = expand_5_to_8((v >> 1) & 0x1f);
			rgba8[4 * i + 3] = (v & 1) ? 255 : 0;
		}
		return true;
	}

	if (entry.texture_format == GL_RGBA && entry.pixel_type == GL_UNSIGNED_SHORT_4_4_4_4)
	{
		if (pixel_data.size() < size_t(pixel_count) * 2)
			return false;
		for (size_t i = 0; i < size_t(pixel_count); i++)
		{
			const uint16_t v = uint16_t(pixel_data[2 * i + 0]) | (uint16_t(pixel_data[2 * i + 1]) << 8);
			rgba8[4 * i + 0] = expand_4_to_8((v >> 12) & 0x0f);
			rgba8[4 * i + 1] = expand_4_to_8((v >> 8) & 0x0f);
			rgba8[4 * i + 2] = expand_4_to_8((v >> 4) & 0x0f);
			rgba8[4 * i + 3] = expand_4_to_8(v & 0x0f);
		}
		return true;
	}

	if (entry.texture_format == GL_LUMINANCE && entry.pixel_type == GL_UNSIGNED_BYTE)
	{
		if (pixel_data.size() < size_t(pixel_count))
			return false;
		for (size_t i = 0; i < size_t(pixel_count); i++)
		{
			const uint8_t l = pixel_data[i];
			rgba8[4 * i + 0] = l;
			rgba8[4 * i + 1] = l;
			rgba8[4 * i + 2] = l;
			rgba8[4 * i + 3] = 255;
		}
		return true;
	}

	if (pixel_data.size() == rgba8.size())
	{
		std::copy(pixel_data.begin(), pixel_data.end(), rgba8.begin());
		return true;
	}

	return false;
}

bool ReplacementProvider::read_blob(const Entry &entry, std::vector<uint8_t> &blob) const
{
	if (entry.inline_blob)
	{
		blob = entry.blob;
		return true;
	}

	std::ifstream file(entry.source_path, std::ifstream::in | std::ifstream::binary);
	if (!file.good())
		return false;

	file.seekg(static_cast<std::streamoff>(entry.data_offset), std::ifstream::beg);
	if (!file.good())
		return false;

	blob.resize(entry.data_size);
	return read_exact(file, blob);
}

bool ReplacementProvider::decode_rgba8(uint64_t checksum64, uint16_t formatsize, ReplacementImage *out) const
{
	return decode_rgba8_with_selector(checksum64, formatsize, 0, out);
}

bool ReplacementProvider::decode_rgba8_with_selector(uint64_t checksum64, uint16_t formatsize, uint64_t selector_checksum64, ReplacementImage *out) const
{
	if (!enabled_ || !out)
		return false;

	const Entry *entry = find_entry(checksum64, formatsize, selector_checksum64);
	if (!entry)
		return false;

	return decode_entry_rgba8(*entry, out);
}

bool ReplacementProvider::decode_rgba8_native_with_selector(uint64_t checksum64, uint16_t formatsize, uint64_t selector_checksum64, ReplacementImage *out) const
{
	if (!enabled_ || !out)
		return false;

	const Entry *entry = find_native_entry(checksum64, formatsize, selector_checksum64);
	if (!entry)
		return false;

	return decode_entry_rgba8(*entry, out);
}

bool ReplacementProvider::decode_rgba8_compat_with_selector(uint64_t checksum64, uint16_t formatsize, uint64_t selector_checksum64, ReplacementImage *out) const
{
	if (!enabled_ || !out)
		return false;

	const Entry *entry = find_compat_entry(checksum64, formatsize, selector_checksum64);
	if (!entry)
		return false;

	return decode_entry_rgba8(*entry, out);
}

bool ReplacementProvider::decode_entry_rgba8(const Entry &entry, ReplacementImage *out) const
{
	if (!out)
		return false;

	std::vector<uint8_t> blob;
	if (!read_blob(entry, blob))
		return false;

	std::vector<uint8_t> pixels;
	if (!decompress_if_needed(entry, blob, pixels))
		return false;

	ReplacementImage image;
	image.meta.repl_w = entry.width;
	image.meta.repl_h = entry.height;
	image.meta.vk_image_index = 0xffffffffu;
	if (!decode_pixels_rgba8(entry, pixels, image.rgba8))
		return false;

	*out = std::move(image);
	return true;
}

ReplacementProviderStats ReplacementProvider::get_stats() const
{
	ReplacementProviderStats stats = {};
	stats.entry_count = uint32_t(entries_.size());
	stats.sampled_index_count = uint32_t(sampled_index_.size());
	stats.sampled_duplicate_key_count = uint32_t(sampled_duplicate_index_.size());
	stats.sampled_family_count = uint32_t(sampled_family_index_.size());
	stats.compat_low32_family_count = uint32_t(compat_checksum_low32_index_.size());
	for (const auto &it : sampled_duplicate_index_)
		stats.sampled_duplicate_entry_count += it.second;

	for (const auto &entry : entries_)
	{
		if (entry.has_native_sampled_identity)
			stats.native_sampled_entry_count++;
		else
			stats.compat_entry_count++;

		if (entry.source_path.find(".phrb") != std::string::npos)
			stats.source_phrb_entry_count++;
		else if (entry.source_path.find(".hts") != std::string::npos)
			stats.source_hts_entry_count++;
		else if (entry.source_path.find(".htc") != std::string::npos)
			stats.source_htc_entry_count++;
	}

	return stats;
}

std::vector<SampledDuplicateDiagnostics> ReplacementProvider::get_sampled_duplicate_diagnostics(size_t limit) const
{
	std::vector<SampledDuplicateDiagnostics> diagnostics;
	diagnostics.reserve(sampled_duplicate_index_.size());
	for (const auto &it : sampled_duplicate_index_)
	{
		const auto active_it = sampled_index_.find(it.first);
		if (active_it == sampled_index_.end())
			continue;

		const Entry &active_entry = entries_[active_it->second];
		SampledDuplicateDiagnostics diag = {};
		diag.sampled_fmt = it.first.sampled_fmt;
		diag.sampled_siz = it.first.sampled_siz;
		diag.sampled_tex_offset = it.first.sampled_tex_offset;
		diag.sampled_stride = it.first.sampled_stride;
		diag.sampled_width = it.first.sampled_width;
		diag.sampled_height = it.first.sampled_height;
		diag.sampled_low32 = it.first.sampled_low32;
		diag.sampled_palette_crc = it.first.sampled_palette_crc;
		diag.formatsize = it.first.formatsize;
		diag.selector_checksum64 = it.first.selector_checksum64;
		diag.total_entry_count = 1u + it.second;
		diag.duplicate_entry_count = it.second;
		diag.active_checksum64 = active_entry.checksum64;
		diag.active_repl_w = active_entry.width;
		diag.active_repl_h = active_entry.height;
		diag.active_source_path = active_entry.source_path;
		diag.active_policy_key = active_entry.phrb_policy_key;
		diag.active_replacement_id = active_entry.phrb_replacement_id;
		diag.active_sampled_object_id = active_entry.phrb_sampled_object_id;
		diagnostics.push_back(std::move(diag));
	}

	std::sort(diagnostics.begin(), diagnostics.end(), [](const SampledDuplicateDiagnostics &a, const SampledDuplicateDiagnostics &b) {
		if (a.duplicate_entry_count != b.duplicate_entry_count)
			return a.duplicate_entry_count > b.duplicate_entry_count;
		if (a.sampled_low32 != b.sampled_low32)
			return a.sampled_low32 < b.sampled_low32;
		if (a.sampled_palette_crc != b.sampled_palette_crc)
			return a.sampled_palette_crc < b.sampled_palette_crc;
		if (a.formatsize != b.formatsize)
			return a.formatsize < b.formatsize;
		return a.selector_checksum64 < b.selector_checksum64;
	});

	if (limit != 0 && diagnostics.size() > limit)
		diagnostics.resize(limit);

	return diagnostics;
}



bool ReplacementProvider::load_phrb(const std::string &path)
{
	std::ifstream file(path, std::ios::binary);
	if (!file)
		return false;

	file.seekg(0, std::ios::end);
	const std::streamoff size = file.tellg();
	if (size < std::streamoff(sizeof(PHRBHeader)))
		return false;
	file.seekg(0, std::ios::beg);

	std::vector<uint8_t> blob;
	blob.resize(static_cast<size_t>(size));
	if (!read_exact(file, blob))
		return false;

	PHRBHeader header = {};
	if (!read_pod_from_blob(blob, 0, header))
		return false;
	if (!phrb_magic_ok(header.magic) || (header.version != 2 && header.version != 3 && header.version != 4 && header.version != 5 && header.version != 6 && header.version != 7))
		return false;
	if (header.string_table_offset > header.blob_offset || header.blob_offset > blob.size())
		return false;

	const bool version3 = header.version >= 3;
	const bool version4 = header.version >= 4;
	const bool version5 = header.version >= 5;
	const bool version6 = header.version >= 6;
	const bool version7 = header.version >= 7;
	const bool phrb_debug = []() {
		if (const char *env = getenv("PARALLEL_RDP_HIRES_PHRB_DEBUG"))
			return strtol(env, nullptr, 0) > 0;
		return false;
	}();
	const uint8_t *string_blob = blob.data() + header.string_table_offset;
	const size_t string_blob_size = size_t(header.blob_offset - header.string_table_offset);
	const uint8_t *rgba_blob_base = blob.data() + header.blob_offset;
	const size_t rgba_blob_size = size_t(blob.size() - header.blob_offset);
	uint32_t loaded_count = 0;

	if (phrb_debug)
		LOGI("Hi-res PHRB load: path=%s version=%u record_count=%u asset_count=%u string_table_bytes=%zu blob_bytes=%zu.\n",
		     path.c_str(), header.version, header.record_count, header.asset_count, string_blob_size, rgba_blob_size);

	for (uint32_t record_index = 0; record_index < header.record_count; record_index++)
	{
		PHRBRecordV2 record = {};
		uint32_t record_flags = PHRB_RECORD_FLAG_RUNTIME_READY;
		if (version4)
		{
			PHRBRecordV4 record_v4 = {};
			const size_t record_offset = size_t(header.record_table_offset) + size_t(record_index) * sizeof(PHRBRecordV4);
			if (!read_pod_from_blob(blob, record_offset, record_v4))
				return false;
			record.policy_key_offset = record_v4.policy_key_offset;
			record.sampled_object_id_offset = record_v4.sampled_object_id_offset;
			record.fmt = record_v4.fmt;
			record.siz = record_v4.siz;
			record.tex_offset = record_v4.tex_offset;
			record.stride = record_v4.stride;
			record.width = record_v4.width;
			record.height = record_v4.height;
			record.formatsize = record_v4.formatsize;
			record.sampled_low32 = record_v4.sampled_low32;
			record.sampled_entry_pcrc = record_v4.sampled_entry_pcrc;
			record.sampled_sparse_pcrc = record_v4.sampled_sparse_pcrc;
			record.asset_candidate_count = record_v4.asset_candidate_count;
			record_flags = record_v4.record_flags;
		}
		else
		{
			const size_t record_offset = size_t(header.record_table_offset) + size_t(record_index) * sizeof(PHRBRecordV2);
			if (!read_pod_from_blob(blob, record_offset, record))
				return false;
		}

		std::string policy_key;
		if (!read_c_string_from_blob(string_blob, string_blob_size, record.policy_key_offset, policy_key))
			policy_key = "phrb-record";
		std::string sampled_object_id;
		if (!read_c_string_from_blob(string_blob, string_blob_size, record.sampled_object_id_offset, sampled_object_id))
			sampled_object_id.clear();

		if ((record_flags & PHRB_RECORD_FLAG_RUNTIME_READY) == 0)
		{
			if (phrb_debug)
				LOGI("Hi-res PHRB record skipped: policy=%s runtime_ready=0 asset_candidates=%u.\n",
				     policy_key.c_str(), record.asset_candidate_count);
			continue;
		}

		uint32_t loaded_asset_count = 0;
		uint32_t zero_selector_count = 0;
		uint32_t duplicate_selector_count = 0;
		std::vector<uint64_t> unique_selectors;
		std::vector<uint64_t> duplicate_selectors;

		auto add_sampled_entry = [&](uint32_t palette_crc,
		                            uint64_t selector_checksum64,
		                            const std::string &replacement_id,
		                            uint32_t width,
		                            uint32_t height,
		                            uint32_t format,
		                            uint32_t texture_format,
		                            uint32_t pixel_type,
		                            uint64_t rgba_offset,
		                            uint32_t rgba_size) {
			Entry entry = {};
			entry.source_path = path + "#" + policy_key;
			entry.phrb_policy_key = policy_key;
			entry.phrb_replacement_id = replacement_id;
			entry.phrb_sampled_object_id = sampled_object_id;
			entry.checksum64 = (uint64_t(palette_crc) << 32u) | uint64_t(record.sampled_low32);
			entry.data_offset = 0;
			entry.data_size = rgba_size;
			entry.width = width;
			entry.height = height;
			entry.format = format;
			entry.texture_format = texture_format;
			entry.pixel_type = pixel_type;
			entry.formatsize = uint16_t(record.formatsize);
			entry.selector_checksum64 = selector_checksum64;
			entry.sampled_fmt = record.fmt;
			entry.sampled_siz = record.siz;
			entry.sampled_tex_offset = record.tex_offset;
			entry.sampled_stride = record.stride;
			entry.sampled_width = record.width;
			entry.sampled_height = record.height;
			entry.sampled_low32 = record.sampled_low32;
			entry.sampled_palette_crc = palette_crc;
			entry.sampled_entry_pcrc = record.sampled_entry_pcrc;
			entry.sampled_sparse_pcrc = record.sampled_sparse_pcrc;
			entry.has_native_sampled_identity = true;
			entry.is_hires = true;
			entry.inline_blob = true;
			entry.blob.assign(rgba_blob_base + rgba_offset,
			                 rgba_blob_base + rgba_offset + rgba_size);
			add_entry(std::move(entry));
			loaded_count++;
		};
		auto add_family_entry = [&](uint64_t legacy_checksum64,
		                           uint16_t legacy_formatsize,
		                           uint64_t selector_checksum64,
		                           const std::string &replacement_id,
		                           uint32_t width,
		                           uint32_t height,
		                           uint32_t format,
		                           uint32_t texture_format,
		                           uint32_t pixel_type,
		                           uint64_t rgba_offset,
		                           uint32_t rgba_size) {
			if (legacy_checksum64 == 0)
				return;
			Entry entry = {};
			entry.source_path = path + "#" + policy_key;
			entry.phrb_policy_key = policy_key;
			entry.phrb_replacement_id = replacement_id;
			entry.phrb_sampled_object_id = sampled_object_id;
			entry.checksum64 = legacy_checksum64;
			entry.data_offset = 0;
			entry.data_size = rgba_size;
			entry.width = width;
			entry.height = height;
			entry.format = format;
			entry.texture_format = texture_format;
			entry.pixel_type = pixel_type;
			entry.formatsize = legacy_formatsize != 0 ? legacy_formatsize : uint16_t(record.formatsize);
			entry.selector_checksum64 = selector_checksum64;
			entry.sampled_low32 = record.sampled_low32;
			entry.sampled_palette_crc = uint32_t(legacy_checksum64 >> 32u);
			entry.sampled_entry_pcrc = record.sampled_entry_pcrc;
			entry.sampled_sparse_pcrc = record.sampled_sparse_pcrc;
			entry.has_native_sampled_identity = false;
			entry.is_runtime_family_compat = true;
			entry.is_hires = true;
			entry.inline_blob = true;
			entry.blob.assign(rgba_blob_base + rgba_offset,
			                 rgba_blob_base + rgba_offset + rgba_size);
			add_entry(std::move(entry));
			loaded_count++;
		};
		const bool family_runtime_record =
			record.fmt == 0 &&
			record.siz == 0 &&
			record.tex_offset == 0 &&
			record.stride == 0 &&
			record.width == 0 &&
			record.height == 0;

		for (uint32_t asset_index = 0; asset_index < header.asset_count; asset_index++)
		{
			uint32_t asset_record_index = 0;
			uint32_t width = 0;
			uint32_t height = 0;
			uint32_t format = GL_RGBA8;
			uint32_t texture_format = GL_RGBA;
			uint32_t pixel_type = GL_UNSIGNED_BYTE;
			uint64_t rgba_offset = 0;
			uint64_t rgba_size = 0;
			uint64_t selector_checksum64 = 0;
			uint64_t legacy_checksum64 = 0;
			uint16_t legacy_formatsize = 0;
			size_t asset_offset = 0;
			std::string replacement_id;
			if (version7)
			{
				PHRBAssetV7 asset = {};
				asset_offset = size_t(header.asset_table_offset) + size_t(asset_index) * sizeof(PHRBAssetV7);
				if (!read_pod_from_blob(blob, asset_offset, asset))
					return false;
				asset_record_index = asset.record_index;
				width = asset.width;
				height = asset.height;
				format = asset.format;
				texture_format = asset.texture_format;
				pixel_type = asset.pixel_type;
				rgba_offset = asset.rgba_blob_offset;
				rgba_size = asset.rgba_blob_size;
				legacy_formatsize = uint16_t(asset.legacy_formatsize);
				selector_checksum64 = asset.selector_checksum64;
				legacy_checksum64 = asset.legacy_checksum64;
				read_c_string_from_blob(string_blob, string_blob_size, asset.replacement_id_offset, replacement_id);
			}
			else if (version6)
			{
				PHRBAssetV6 asset = {};
				asset_offset = size_t(header.asset_table_offset) + size_t(asset_index) * sizeof(PHRBAssetV6);
				if (!read_pod_from_blob(blob, asset_offset, asset))
					return false;
				asset_record_index = asset.record_index;
				width = asset.width;
				height = asset.height;
				texture_format = asset.texture_format;
				pixel_type = asset.pixel_type;
				rgba_offset = asset.rgba_blob_offset;
				rgba_size = asset.rgba_blob_size;
				legacy_formatsize = uint16_t(asset.legacy_formatsize);
				selector_checksum64 = asset.selector_checksum64;
				legacy_checksum64 = asset.legacy_checksum64;
				read_c_string_from_blob(string_blob, string_blob_size, asset.replacement_id_offset, replacement_id);
			}
			else if (version5)
			{
				PHRBAssetV5 asset = {};
				asset_offset = size_t(header.asset_table_offset) + size_t(asset_index) * sizeof(PHRBAssetV5);
				if (!read_pod_from_blob(blob, asset_offset, asset))
					return false;
				asset_record_index = asset.record_index;
				width = asset.width;
				height = asset.height;
				texture_format = asset.texture_format;
				pixel_type = asset.pixel_type;
				rgba_offset = asset.rgba_blob_offset;
				rgba_size = asset.rgba_blob_size;
				legacy_formatsize = uint16_t(asset.legacy_formatsize);
				selector_checksum64 = asset.selector_checksum64;
				legacy_checksum64 = asset.legacy_checksum64;
				read_c_string_from_blob(string_blob, string_blob_size, asset.replacement_id_offset, replacement_id);
			}
			else if (version3)
			{
				PHRBAssetV3 asset = {};
				asset_offset = size_t(header.asset_table_offset) + size_t(asset_index) * sizeof(PHRBAssetV3);
				if (!read_pod_from_blob(blob, asset_offset, asset))
					return false;
				asset_record_index = asset.record_index;
				width = asset.width;
				height = asset.height;
				texture_format = asset.texture_format;
				pixel_type = asset.pixel_type;
				rgba_offset = asset.rgba_blob_offset;
				rgba_size = asset.rgba_blob_size;
				legacy_formatsize = uint16_t(asset.legacy_formatsize);
				selector_checksum64 = asset.selector_checksum64;
				read_c_string_from_blob(string_blob, string_blob_size, asset.replacement_id_offset, replacement_id);
			}
			else
			{
				PHRBAssetV2 asset = {};
				asset_offset = size_t(header.asset_table_offset) + size_t(asset_index) * sizeof(PHRBAssetV2);
				if (!read_pod_from_blob(blob, asset_offset, asset))
					return false;
				asset_record_index = asset.record_index;
				width = asset.width;
				height = asset.height;
				texture_format = asset.texture_format;
				pixel_type = asset.pixel_type;
				rgba_offset = asset.rgba_blob_offset;
				rgba_size = asset.rgba_blob_size;
				legacy_formatsize = uint16_t(asset.legacy_formatsize);
				read_c_string_from_blob(string_blob, string_blob_size, asset.replacement_id_offset, replacement_id);
			}

			if (asset_record_index != record_index)
				continue;
			if (rgba_offset > rgba_blob_size || rgba_size > (rgba_blob_size - rgba_offset))
				continue;
			if (width == 0 || height == 0 || rgba_size == 0 || rgba_size > uint64_t(UINT32_MAX))
				continue;
			if (!version7)
			{
				const uint64_t expected_rgba_size = uint64_t(width) * uint64_t(height) * 4ull;
				if (rgba_size != expected_rgba_size)
					continue;
			}
			const uint32_t rgba_size_u32 = uint32_t(rgba_size);

			loaded_asset_count++;
			if (selector_checksum64 == 0)
				zero_selector_count++;
			bool selector_seen = false;
			for (uint64_t existing : unique_selectors)
			{
				if (existing == selector_checksum64)
				{
					selector_seen = true;
					break;
				}
			}
			if (selector_seen)
			{
				duplicate_selector_count++;
				push_unique(duplicate_selectors, selector_checksum64);
			}
			else
				unique_selectors.push_back(selector_checksum64);

			if (family_runtime_record)
			{
				add_family_entry(
					legacy_checksum64,
					legacy_formatsize,
					selector_checksum64,
					replacement_id,
					width,
					height,
					format,
					texture_format,
					pixel_type,
					rgba_offset,
					rgba_size_u32);
				continue;
			}

			bool added = false;
			if (record.sampled_sparse_pcrc != 0)
			{
				add_sampled_entry(
					record.sampled_sparse_pcrc,
					selector_checksum64,
					replacement_id,
					width,
					height,
					format,
					texture_format,
					pixel_type,
					rgba_offset,
					rgba_size_u32);
				added = true;
			}
			if (record.sampled_entry_pcrc != 0 && record.sampled_entry_pcrc != record.sampled_sparse_pcrc)
			{
				add_sampled_entry(
					record.sampled_entry_pcrc,
					selector_checksum64,
					replacement_id,
					width,
					height,
					format,
					texture_format,
					pixel_type,
					rgba_offset,
					rgba_size_u32);
				added = true;
			}
			if (!added)
				add_sampled_entry(
					0,
					selector_checksum64,
					replacement_id,
					width,
					height,
					format,
					texture_format,
					pixel_type,
					rgba_offset,
					rgba_size_u32);
		}

		if (phrb_debug)
		{
			const uint64_t first_selector = !unique_selectors.empty() ? unique_selectors.front() : 0;
			const uint64_t last_selector = !unique_selectors.empty() ? unique_selectors.back() : 0;
			const uint32_t self_test_palette_crc =
				record.sampled_sparse_pcrc != 0 ? record.sampled_sparse_pcrc : record.sampled_entry_pcrc;
			const uint64_t self_test_checksum64 = (uint64_t(self_test_palette_crc) << 32u) | uint64_t(record.sampled_low32);
			const Entry *self_test_entry = loaded_asset_count != 0
				? find_entry(self_test_checksum64, uint16_t(record.formatsize), first_selector)
				: nullptr;
			LOGI("Hi-res PHRB record: policy=%s sampled_low32=%08x fs=%u asset_candidates=%u loaded_assets=%u unique_selectors=%zu duplicate_selectors=%u zero_selectors=%u first_selector=%016llx last_selector=%016llx self_test=%u self_test_key=%016llx.\n",
			     policy_key.c_str(),
			     record.sampled_low32,
			     record.formatsize,
			     record.asset_candidate_count,
			     loaded_asset_count,
			     unique_selectors.size(),
			     duplicate_selector_count,
			     zero_selector_count,
			     static_cast<unsigned long long>(first_selector),
			     static_cast<unsigned long long>(last_selector),
			     self_test_entry ? 1u : 0u,
			     static_cast<unsigned long long>(self_test_checksum64));
			for (uint64_t selector : duplicate_selectors)
				LOGI("Hi-res PHRB duplicate selector: policy=%s selector=%016llx.\n",
				     policy_key.c_str(), static_cast<unsigned long long>(selector));
		}
	}

	return loaded_count != 0;
}
void ReplacementProvider::trim_to_budget(size_t bytes)
{
	memory_budget_bytes_ = bytes;
}

bool ReplacementProvider::load_hts(const std::string &path)
{
	std::ifstream file(path, std::ifstream::in | std::ifstream::binary);
	if (!file.good())
		return false;

	file.seekg(0, std::ifstream::end);
	const uint64_t file_size = static_cast<uint64_t>(file.tellg());
	file.seekg(0, std::ifstream::beg);
	if (!file.good() || file_size < 16)
		return false;

	int32_t version = 0;
	if (!read_exact(file, version))
		return false;

	bool old_version = false;
	int64_t storage_pos = 0;
	if (version == TXCACHE_FORMAT_VERSION)
	{
		int32_t config = 0;
		if (!read_exact(file, config) || !read_exact(file, storage_pos))
			return false;
	}
	else
	{
		old_version = true;
		if (!read_exact(file, storage_pos))
			return false;
	}

	if (storage_pos <= 0 || uint64_t(storage_pos) >= file_size)
		return false;

	file.seekg(storage_pos, std::ifstream::beg);
	if (!file.good())
		return false;

	int32_t storage_size = 0;
	if (!read_exact(file, storage_size) || storage_size <= 0)
		return false;

	struct IndexEntry
	{
		uint64_t checksum64 = 0;
		uint64_t offset = 0;
		uint16_t formatsize = 0;
	};
	std::vector<IndexEntry> index_entries;
	index_entries.reserve(static_cast<size_t>(storage_size));
	for (int32_t i = 0; i < storage_size; i++)
	{
		uint64_t key = 0;
		int64_t packed = 0;
		if (!read_exact(file, key) || !read_exact(file, packed))
			return false;

		IndexEntry index = {};
		index.checksum64 = key;
		index.offset = static_cast<uint64_t>(packed) & 0x0000ffffffffffffull;
		index.formatsize = static_cast<uint16_t>((static_cast<uint64_t>(packed) >> 48) & 0xffffu);
		index_entries.push_back(index);
	}

	for (const auto &index : index_entries)
	{
		if (index.offset >= file_size)
			continue;

		file.seekg(static_cast<std::streamoff>(index.offset), std::ifstream::beg);
		if (!file.good())
			continue;

		Entry entry = {};
		entry.source_path = path;
		entry.checksum64 = index.checksum64;
		entry.formatsize = index.formatsize;

		if (!read_exact(file, entry.width) ||
		    !read_exact(file, entry.height) ||
		    !read_exact(file, entry.format) ||
		    !read_exact(file, entry.texture_format) ||
		    !read_exact(file, entry.pixel_type))
			continue;

		uint8_t is_hires = 0;
		if (!read_exact(file, is_hires))
			continue;
		entry.is_hires = is_hires != 0;

		uint16_t record_formatsize = 0;
		if (!old_version && !read_exact(file, record_formatsize))
			continue;
		if (entry.formatsize == 0)
			entry.formatsize = record_formatsize;

		if (!read_exact(file, entry.data_size))
			continue;
		if (entry.data_size == 0)
			continue;

		const uint64_t data_offset = static_cast<uint64_t>(file.tellg());
		if (data_offset + entry.data_size > file_size)
			continue;

		entry.data_offset = data_offset;
		entry.inline_blob = false;
		add_entry(std::move(entry));
	}

	return true;
}

bool ReplacementProvider::load_htc(const std::string &path)
{
	gzFile fp = gzopen(path.c_str(), "rb");
	if (!fp)
		return false;

	int32_t version = 0;
	if (!gz_read_exact(fp, &version, sizeof(version)))
	{
		gzclose(fp);
		return false;
	}

	const bool old_version = version != TXCACHE_FORMAT_VERSION;
	if (!old_version)
	{
		int32_t config = 0;
		if (!gz_read_exact(fp, &config, sizeof(config)))
		{
			gzclose(fp);
			return false;
		}
	}

	for (;;)
	{
		Entry entry = {};
		entry.source_path = path;
		entry.inline_blob = true;

		const int checksum_read = gzread(fp, &entry.checksum64, sizeof(entry.checksum64));
		if (checksum_read == 0)
			break;
		if (checksum_read != int(sizeof(entry.checksum64)))
		{
			gzclose(fp);
			return false;
		}

		if (!gz_read_exact(fp, &entry.width, sizeof(entry.width)) ||
		    !gz_read_exact(fp, &entry.height, sizeof(entry.height)) ||
		    !gz_read_exact(fp, &entry.format, sizeof(entry.format)) ||
		    !gz_read_exact(fp, &entry.texture_format, sizeof(entry.texture_format)) ||
		    !gz_read_exact(fp, &entry.pixel_type, sizeof(entry.pixel_type)))
		{
			gzclose(fp);
			return false;
		}

		uint8_t is_hires = 0;
		if (!gz_read_exact(fp, &is_hires, sizeof(is_hires)))
		{
			gzclose(fp);
			return false;
		}
		entry.is_hires = is_hires != 0;

		if (!old_version)
		{
			if (!gz_read_exact(fp, &entry.formatsize, sizeof(entry.formatsize)))
			{
				gzclose(fp);
				return false;
			}
		}

		if (!gz_read_exact(fp, &entry.data_size, sizeof(entry.data_size)) || entry.data_size == 0)
		{
			gzclose(fp);
			return false;
		}

		entry.blob.resize(entry.data_size);
		if (!gz_read_exact(fp, entry.blob.data(), entry.blob.size()))
		{
			gzclose(fp);
			return false;
		}

		add_entry(std::move(entry));
	}

	gzclose(fp);
	return true;
}
}
