#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

namespace RDP
{
struct ReplacementMeta
{
	uint32_t repl_w = 0;
	uint32_t repl_h = 0;
	uint32_t orig_w = 0;
	uint32_t orig_h = 0;
	uint32_t vk_image_index = 0xffffffffu;
	bool has_mips = false;
	bool srgb = false;
};

struct ReplacementImage
{
	ReplacementMeta meta;
	std::vector<uint8_t> rgba8;
};

struct CILow32FamilyDiagnostics
{
	bool available = false;
	bool prefer_exact_formatsize = false;
	uint32_t exact_formatsize_entries = 0;
	uint32_t generic_formatsize_entries = 0;
	uint32_t active_entry_count = 0;
	uint32_t active_unique_checksum_count = 0;
	uint32_t active_unique_palette_count = 0;
	uint32_t active_unique_repl_dim_count = 0;
	uint32_t active_preferred_palette_match_count = 0;
	uint32_t sample_repl_w = 0;
	uint32_t sample_repl_h = 0;
	bool active_repl_dims_uniform = false;
};

struct CILow32DimsSelector
{
	uint32_t checksum_low32 = 0;
	uint16_t formatsize = 0;
	uint32_t repl_w = 0;
	uint32_t repl_h = 0;
};

class ReplacementProvider
{
public:
	bool enabled() const;
	void set_enabled(bool enable);
	bool load_cache_dir(const std::string &path);
	bool lookup(uint64_t checksum64, uint16_t formatsize, ReplacementMeta *out) const;
	bool lookup_with_selector(uint64_t checksum64, uint16_t formatsize, uint64_t selector_checksum64, ReplacementMeta *out) const;
	bool lookup_sampled_with_selector(uint32_t sampled_fmt,
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
	                                  uint64_t *resolved_checksum64 = nullptr) const;
	uint32_t ordered_surface_selector_count(uint64_t checksum64, uint16_t formatsize) const;
	uint64_t ordered_surface_selector_checksum64(uint64_t checksum64, uint16_t formatsize, uint32_t selector_index) const;
	static uint64_t ordered_surface_slot_selector_checksum64(uint32_t slot_index);
	bool lookup_ci_low32_unique(uint32_t checksum_low32, uint16_t formatsize, ReplacementMeta *out, uint64_t *resolved_checksum64 = nullptr) const;
	bool lookup_ci_low32_repl_dims_unique(uint32_t checksum_low32, uint16_t formatsize, ReplacementMeta *out, uint64_t *resolved_checksum64 = nullptr) const;
	bool lookup_ci_low32_selected_dims(uint32_t checksum_low32,
	                                   uint16_t formatsize,
	                                   uint32_t repl_w,
	                                   uint32_t repl_h,
	                                   ReplacementMeta *out,
	                                   uint64_t *resolved_checksum64 = nullptr) const;
	bool lookup_ci_low32_any(uint32_t checksum_low32,
	                         uint16_t formatsize,
	                         uint32_t preferred_palette_crc,
	                         ReplacementMeta *out,
	                         uint64_t *resolved_checksum64 = nullptr,
	                         bool *matched_preferred_palette = nullptr) const;
	bool describe_ci_low32_family(uint32_t checksum_low32,
	                              uint16_t formatsize,
	                              uint32_t preferred_palette_crc,
	                              CILow32FamilyDiagnostics *out) const;
	bool decode_rgba8(uint64_t checksum64, uint16_t formatsize, ReplacementImage *out) const;
	bool decode_rgba8_with_selector(uint64_t checksum64, uint16_t formatsize, uint64_t selector_checksum64, ReplacementImage *out) const;
	void trim_to_budget(size_t bytes);
	void clear();
	size_t entry_count() const;

private:
	struct Entry
	{
		std::string source_path;
		std::string phrb_policy_key;
		std::string phrb_sampled_object_id;
		uint64_t checksum64 = 0;
		uint64_t data_offset = 0;
		uint32_t data_size = 0;
		uint32_t width = 0;
		uint32_t height = 0;
		uint32_t format = 0;
		uint16_t texture_format = 0;
		uint16_t pixel_type = 0;
		uint16_t formatsize = 0;
		uint64_t selector_checksum64 = 0;
		uint32_t sampled_fmt = 0;
		uint32_t sampled_siz = 0;
		uint32_t sampled_tex_offset = 0;
		uint32_t sampled_stride = 0;
		uint32_t sampled_width = 0;
		uint32_t sampled_height = 0;
		uint32_t sampled_low32 = 0;
		uint32_t sampled_palette_crc = 0;
		uint32_t sampled_entry_pcrc = 0;
		uint32_t sampled_sparse_pcrc = 0;
		bool has_native_sampled_identity = false;
		bool is_hires = false;
		bool inline_blob = false;
		std::vector<uint8_t> blob;
	};

	struct SampledLookupKey
	{
		uint32_t sampled_fmt = 0;
		uint32_t sampled_siz = 0;
		uint32_t sampled_tex_offset = 0;
		uint32_t sampled_stride = 0;
		uint32_t sampled_width = 0;
		uint32_t sampled_height = 0;
		uint32_t sampled_low32 = 0;
		uint32_t sampled_palette_crc = 0;
		uint16_t formatsize = 0;
		uint64_t selector_checksum64 = 0;

		bool operator==(const SampledLookupKey &other) const
		{
			return sampled_fmt == other.sampled_fmt &&
			       sampled_siz == other.sampled_siz &&
			       sampled_tex_offset == other.sampled_tex_offset &&
			       sampled_stride == other.sampled_stride &&
			       sampled_width == other.sampled_width &&
			       sampled_height == other.sampled_height &&
			       sampled_low32 == other.sampled_low32 &&
			       sampled_palette_crc == other.sampled_palette_crc &&
			       formatsize == other.formatsize &&
			       selector_checksum64 == other.selector_checksum64;
		}
	};

	struct SampledLookupKeyHash
	{
		size_t operator()(const SampledLookupKey &key) const;
	};

	const Entry *find_entry(uint64_t checksum64, uint16_t formatsize) const;
	const Entry *find_entry(uint64_t checksum64, uint16_t formatsize, uint64_t selector_checksum64) const;
	const Entry *find_sampled_entry(uint32_t sampled_fmt,
	                                uint32_t sampled_siz,
	                                uint32_t sampled_tex_offset,
	                                uint32_t sampled_stride,
	                                uint32_t sampled_width,
	                                uint32_t sampled_height,
	                                uint32_t sampled_low32,
	                                uint32_t palette_crc,
	                                uint16_t formatsize,
	                                uint64_t selector_checksum64) const;
	bool load_hts(const std::string &path);
	bool load_htc(const std::string &path);
	bool load_phrb(const std::string &path);
	bool read_blob(const Entry &entry, std::vector<uint8_t> &blob) const;
	static bool decode_pixels_rgba8(const Entry &entry, const std::vector<uint8_t> &pixel_data, std::vector<uint8_t> &rgba8);
	static bool decompress_if_needed(const Entry &entry, const std::vector<uint8_t> &blob, std::vector<uint8_t> &pixel_data);
	static uint32_t expected_decoded_size(const Entry &entry);
	static SampledLookupKey make_sampled_lookup_key(uint32_t sampled_fmt,
	                                                uint32_t sampled_siz,
	                                                uint32_t sampled_tex_offset,
	                                                uint32_t sampled_stride,
	                                                uint32_t sampled_width,
	                                                uint32_t sampled_height,
	                                                uint32_t sampled_low32,
	                                                uint32_t sampled_palette_crc,
	                                                uint16_t formatsize,
	                                                uint64_t selector_checksum64);
	void add_entry(Entry &&entry);

	bool enabled_ = false;
	std::string cache_dir_;
	std::vector<Entry> entries_;
	std::unordered_map<uint64_t, std::vector<size_t>> checksum_index_;
	std::unordered_map<uint32_t, std::vector<size_t>> checksum_low32_index_;
	std::unordered_map<uint32_t, std::vector<size_t>> compat_checksum_low32_index_;
	std::unordered_map<SampledLookupKey, size_t, SampledLookupKeyHash> sampled_index_;
	std::unordered_map<uint64_t, std::vector<uint64_t>> ordered_surface_selectors_;
	size_t memory_budget_bytes_ = 0;
};
}
