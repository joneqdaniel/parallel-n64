#include "texture_replacement.hpp"
#include <algorithm>
#include <cerrno>
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
}

bool ReplacementProvider::enabled() const
{
	return enabled_;
}

void ReplacementProvider::set_enabled(bool enable)
{
	enabled_ = enable;
}

void ReplacementProvider::add_entry(Entry &&entry)
{
	const size_t index = entries_.size();
	checksum_index_[entry.checksum64].push_back(index);
	checksum_low32_index_[uint32_t(entry.checksum64 & 0xffffffffu)].push_back(index);
	entries_.push_back(std::move(entry));
}

void ReplacementProvider::clear()
{
	cache_dir_.clear();
	entries_.clear();
	checksum_index_.clear();
	checksum_low32_index_.clear();
}

size_t ReplacementProvider::entry_count() const
{
	return entries_.size();
}

bool ReplacementProvider::load_cache_dir(const std::string &path)
{
	clear();
	cache_dir_ = path;

	std::vector<std::string> files;
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
			if (!has_suffix(name, ".hts") && !has_suffix(name, ".htc"))
				continue;
			files.push_back(path + "/" + name);
		}
		closedir(dir);
	}
	else if (has_suffix(path, ".hts") || has_suffix(path, ".htc"))
	{
		files.push_back(path);
	}
	else
	{
		return false;
	}

	std::sort(files.begin(), files.end());
	for (const auto &file : files)
	{
		if (has_suffix(file, ".hts"))
			load_hts(file);
		else
			load_htc(file);
	}

	return !entries_.empty();
}

const ReplacementProvider::Entry *ReplacementProvider::find_entry(uint64_t checksum64, uint16_t formatsize) const
{
	auto it = checksum_index_.find(checksum64);
	if (it == checksum_index_.end())
		return nullptr;

	const auto &indices = it->second;
	for (auto itr = indices.rbegin(); itr != indices.rend(); ++itr)
	{
		const Entry &entry = entries_[*itr];
		if (entry.formatsize == formatsize)
			return &entry;
	}

	for (auto itr = indices.rbegin(); itr != indices.rend(); ++itr)
	{
		const Entry &entry = entries_[*itr];
		if (entry.formatsize == 0)
			return &entry;
	}

	if (formatsize == 0 && !indices.empty())
		return &entries_[indices.back()];

	return nullptr;
}

bool ReplacementProvider::lookup(uint64_t checksum64, uint16_t formatsize, ReplacementMeta *out) const
{
	if (!enabled_ || !out)
		return false;

	const Entry *entry = find_entry(checksum64, formatsize);
	if (!entry)
		return false;

	ReplacementMeta meta = {};
	meta.repl_w = entry->width;
	meta.repl_h = entry->height;
	meta.vk_image_index = 0xffffffffu;
	out->repl_w = meta.repl_w;
	out->repl_h = meta.repl_h;
	out->orig_w = meta.orig_w;
	out->orig_h = meta.orig_h;
	out->vk_image_index = meta.vk_image_index;
	out->has_mips = meta.has_mips;
	out->srgb = meta.srgb;
	return true;
}

bool ReplacementProvider::lookup_ci_low32_unique(uint32_t checksum_low32,
                                                 uint16_t formatsize,
                                                 ReplacementMeta *out,
                                                 uint64_t *resolved_checksum64) const
{
	if (!enabled_ || !out)
		return false;

	auto it = checksum_low32_index_.find(checksum_low32);
	if (it == checksum_low32_index_.end())
		return false;

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

	std::vector<uint64_t> unique;
	collect_unique_checksums(formatsize, unique);
	if (unique.empty())
		collect_unique_checksums(0, unique);

	if (unique.size() != 1)
		return false;

	const uint64_t checksum64 = unique.front();
	const Entry *entry = find_entry(checksum64, formatsize);
	if (!entry)
		return false;

	out->repl_w = entry->width;
	out->repl_h = entry->height;
	out->orig_w = 0;
	out->orig_h = 0;
	out->vk_image_index = 0xffffffffu;
	out->has_mips = false;
	out->srgb = false;
	if (resolved_checksum64)
		*resolved_checksum64 = checksum64;
	return true;
}

bool ReplacementProvider::lookup_ci_low32_repl_dims_unique(uint32_t checksum_low32,
                                                           uint16_t formatsize,
                                                           ReplacementMeta *out,
                                                           uint64_t *resolved_checksum64) const
{
	if (!enabled_ || !out)
		return false;

	auto it = checksum_low32_index_.find(checksum_low32);
	if (it == checksum_low32_index_.end())
		return false;

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
	if (!entry)
		return false;

	out->repl_w = entry->width;
	out->repl_h = entry->height;
	out->orig_w = 0;
	out->orig_h = 0;
	out->vk_image_index = 0xffffffffu;
	out->has_mips = false;
	out->srgb = false;
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

	auto it = checksum_low32_index_.find(checksum_low32);
	if (it == checksum_low32_index_.end())
		return false;

	auto pick_candidate = [&](uint16_t candidate_formatsize) -> const Entry * {
		for (auto itr = it->second.rbegin(); itr != it->second.rend(); ++itr)
		{
			const Entry &entry = entries_[*itr];
			if (entry.formatsize != candidate_formatsize)
				continue;
			if (entry.width != repl_w || entry.height != repl_h)
				continue;
			return &entry;
		}
		return nullptr;
	};

	const Entry *entry = pick_candidate(formatsize);
	if (!entry)
		entry = pick_candidate(0);
	if (!entry)
		return false;

	out->repl_w = entry->width;
	out->repl_h = entry->height;
	out->orig_w = 0;
	out->orig_h = 0;
	out->vk_image_index = 0xffffffffu;
	out->has_mips = false;
	out->srgb = false;
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

	auto it = checksum_low32_index_.find(checksum_low32);
	if (it == checksum_low32_index_.end())
		return false;

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
	if (!entry)
		return false;

	out->repl_w = entry->width;
	out->repl_h = entry->height;
	out->orig_w = 0;
	out->orig_h = 0;
	out->vk_image_index = 0xffffffffu;
	out->has_mips = false;
	out->srgb = false;
	if (resolved_checksum64)
		*resolved_checksum64 = entry->checksum64;
	if (matched_preferred_palette)
		*matched_preferred_palette = matched_preferred;
	return true;
}

bool ReplacementProvider::describe_ci_low32_family(uint32_t checksum_low32,
                                                   uint16_t formatsize,
                                                   uint32_t preferred_palette_crc,
                                                   CILow32FamilyDiagnostics *out) const
{
	if (!enabled_ || !out)
		return false;

	auto it = checksum_low32_index_.find(checksum_low32);
	if (it == checksum_low32_index_.end())
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
	if (!enabled_ || !out)
		return false;

	const Entry *entry = find_entry(checksum64, formatsize);
	if (!entry)
		return false;

	std::vector<uint8_t> blob;
	if (!read_blob(*entry, blob))
		return false;

	std::vector<uint8_t> pixels;
	if (!decompress_if_needed(*entry, blob, pixels))
		return false;

	ReplacementImage image;
	image.meta.repl_w = entry->width;
	image.meta.repl_h = entry->height;
	image.meta.vk_image_index = 0xffffffffu;
	if (!decode_pixels_rgba8(*entry, pixels, image.rgba8))
		return false;

	*out = std::move(image);
	return true;
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
