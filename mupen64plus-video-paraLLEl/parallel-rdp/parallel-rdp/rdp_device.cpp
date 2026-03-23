/* Copyright (c) 2020 Themaister
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#include "rdp_device.hpp"
#include "rdp_common.hpp"
#include "rdp_hires_runtime_policy.hpp"
#include "rdp_memory_path_policy.hpp"
#include "rdp_other_modes_policy.hpp"
#include "rdp_rect_setup_policy.hpp"
#include "rdp_scanout_coherency_policy.hpp"
#include "rdp_scissor_policy.hpp"
#include "rdp_tex_rect_policy.hpp"
#include "rdp_triangle_setup_policy.hpp"
#include <chrono>
#include <string>

#ifdef __SSE2__
#include <emmintrin.h>
#endif

#ifndef PARALLEL_RDP_SHADER_DIR
#include "shaders/slangmosh.hpp"
#endif

using namespace Vulkan;

#define STATE_MASK(flag, cond, mask) do { \
    (flag) &= ~(mask); \
    if (cond) (flag) |= (mask); \
} while(0)

namespace RDP
{
namespace
{
static bool parse_optional_bool_env(const char *env, bool fallback)
{
	if (!env || !*env)
		return fallback;
	return strtol(env, nullptr, 0) > 0;
}

static std::unordered_set<std::string> parse_hires_filter_signatures_env(const char *env)
{
	std::unordered_set<std::string> signatures;
	if (!env || !*env)
		return signatures;

	const std::string raw(env);
	size_t start = 0;
	while (start < raw.size())
	{
		size_t end = raw.find(';', start);
		if (end == std::string::npos)
			end = raw.size();

		std::string signature = raw.substr(start, end - start);
		size_t first = signature.find_first_not_of(" \t\r\n");
		size_t last = signature.find_last_not_of(" \t\r\n");
		if (first != std::string::npos && last != std::string::npos)
			signatures.emplace(signature.substr(first, last - first + 1));

		start = end + 1;
	}

	return signatures;
}
}

CommandProcessor::CommandProcessor(Vulkan::Device &device_, void *rdram_ptr,
                                   size_t rdram_offset_, size_t rdram_size_, size_t hidden_rdram_size,
                                   CommandProcessorFlags flags_)
	: device(device_), rdram_offset(rdram_offset_), rdram_size(rdram_size_), flags(flags_), renderer(*this),
#ifdef PARALLEL_RDP_SHADER_DIR
	  timeline_worker(Granite::Global::create_thread_context(), FenceExecutor{&device, &thread_timeline_value})
#else
	  timeline_worker(FenceExecutor{&device, &thread_timeline_value})
#endif
{
	if (rdram_ptr)
		host_rdram = static_cast<uint8_t *>(rdram_ptr) + rdram_offset_;

	BufferCreateInfo info = {};
	info.size = rdram_size;
	info.usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
	info.domain = BufferDomain::CachedCoherentHostPreferCached;
	info.misc = BUFFER_MISC_ZERO_INITIALIZE_BIT;

	if (rdram_ptr)
	{
		const auto decision = detail::decide_rdram_memory_path(
				true,
				device.get_device_features().supports_external_memory_host,
				rdram_size,
				rdram_offset,
				device.get_device_features().host_memory_properties.minImportedHostPointerAlignment,
				getenv("PARALLEL_RDP_ALLOW_EXTERNAL_HOST"));

		if (decision.use_external_host_import)
		{
			info.size = decision.imported_size;
			rdram = device.create_imported_host_buffer(info, VK_EXTERNAL_MEMORY_HANDLE_TYPE_HOST_ALLOCATION_BIT_EXT, rdram_ptr);
		}
		else
		{
			LOGW("VK_EXT_external_memory_host is not supported on this device. Falling back to a slower path.\n");
			is_host_coherent = decision.host_coherent;
			rdram_offset = decision.effective_rdram_offset;
			host_rdram = static_cast<uint8_t *>(rdram_ptr) + rdram_offset_;

			BufferCreateInfo device_rdram = {};
			device_rdram.size = rdram_size * 2; // Need twice the memory amount so we can also store a writemask.
			device_rdram.usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT |
			                     VK_BUFFER_USAGE_TRANSFER_SRC_BIT |
			                     VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;

			if (device.get_gpu_properties().deviceType == VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU)
				device_rdram.domain = BufferDomain::CachedCoherentHostPreferCached;
			else
				device_rdram.domain = BufferDomain::Device;

			device_rdram.misc = BUFFER_MISC_ZERO_INITIALIZE_BIT;
			rdram = device.create_buffer(device_rdram);
		}
	}
	else
		rdram = device.create_buffer(info);

	if (!rdram)
		LOGE("Failed to allocate RDRAM.\n");

	info.size = hidden_rdram_size;
	// Should be CachedHost, but seeing some insane bug on incoherent Arm systems for time being,
	// so just forcing coherent memory here for now. Not sure what is going on.
	info.domain = (flags & COMMAND_PROCESSOR_FLAG_HOST_VISIBLE_HIDDEN_RDRAM_BIT) != 0 ?
	              BufferDomain::CachedCoherentHostPreferCoherent : BufferDomain::Device;
	info.misc = 0;
	hidden_rdram = device.create_buffer(info);

	info.size = 0x1000;
	info.domain = (flags & COMMAND_PROCESSOR_FLAG_HOST_VISIBLE_TMEM_BIT) != 0 ?
	              BufferDomain::CachedCoherentHostPreferCoherent : BufferDomain::Device;
	tmem = device.create_buffer(info);

	clear_hidden_rdram();
	clear_tmem();
	init_renderer();

	if (const char *env = getenv("PARALLEL_RDP_BENCH"))
	{
		measure_stall_time = strtol(env, nullptr, 0) > 0;
		if (measure_stall_time)
			LOGI("Will measure stall timings.\n");
	}

	if (const char *env = getenv("PARALLEL_RDP_SINGLE_THREADED_COMMAND"))
	{
		single_threaded_processing = strtol(env, nullptr, 0) > 0;
		if (single_threaded_processing)
			LOGI("Will use single threaded command processing.\n");
	}

	if (!single_threaded_processing)
	{
		ring.init(
#ifdef PARALLEL_RDP_SHADER_DIR
				Granite::Global::create_thread_context(),
#endif
				this, 4 * 1024);
	}

	if (const char *env = getenv("PARALLEL_RDP_BENCH"))
		timestamp = strtol(env, nullptr, 0) > 0;

	if (const char *env = getenv("PARALLEL_RDP_HIRES_DEBUG"))
		renderer.set_hires_debug(strtol(env, nullptr, 0) > 0);
	if (const char *env = getenv("PARALLEL_RDP_HIRES_BLOCK_SHAPE_PROBE"))
		renderer.set_hires_debug_block_shape_probe(strtol(env, nullptr, 0) > 0);
	if (const char *env = getenv("PARALLEL_RDP_HIRES_CI_PALETTE_PROBE"))
		renderer.set_hires_debug_ci_palette_probe(strtol(env, nullptr, 0) > 0);

	const bool allow_tile = parse_optional_bool_env(getenv("PARALLEL_RDP_HIRES_FILTER_ALLOW_TILE"), true);
	const bool allow_block = parse_optional_bool_env(getenv("PARALLEL_RDP_HIRES_FILTER_ALLOW_BLOCK"), true);
	auto blocked_signatures = parse_hires_filter_signatures_env(getenv("PARALLEL_RDP_HIRES_FILTER_SIGNATURES"));
	renderer.set_hires_debug_filter(allow_tile, allow_block, std::move(blocked_signatures));
}

CommandProcessor::~CommandProcessor()
{
	renderer.log_hires_summary();
	idle();
}

void CommandProcessor::begin_frame_context()
{
	flush();
	drain_command_ring();
	device.next_frame_context();
}

void CommandProcessor::init_renderer()
{
	if (!rdram)
	{
		is_supported = false;
		return;
	}

	renderer.set_device(&device);
	renderer.set_rdram(rdram.get(), host_rdram, rdram_offset, rdram_size, is_host_coherent);
	renderer.set_hidden_rdram(hidden_rdram.get());
	renderer.set_tmem(tmem.get());
	renderer.set_replacement_provider(nullptr);

	unsigned factor = 1;
	if (flags & COMMAND_PROCESSOR_FLAG_UPSCALING_8X_BIT)
		factor = 8;
	else if (flags & COMMAND_PROCESSOR_FLAG_UPSCALING_4X_BIT)
		factor = 4;
	else if (flags & COMMAND_PROCESSOR_FLAG_UPSCALING_2X_BIT)
		factor = 2;

	if (factor != 1)
		LOGI("Enabling upscaling: %ux.\n", factor);

	RendererOptions opts;
	opts.upscaling_factor = factor;

	is_supported = renderer.init_renderer(opts);

	vi.set_device(&device);
	vi.set_rdram(rdram.get(), rdram_offset, rdram_size);
	vi.set_hidden_rdram(hidden_rdram.get());
	vi.set_renderer(&renderer);

#ifndef PARALLEL_RDP_SHADER_DIR
	shader_bank.reset(new ShaderBank(device, [&](const char *name, const char *define) -> int {
		if (strncmp(name, "vi_", 3) == 0)
			return vi.resolve_shader_define(name, define);
		else
			return renderer.resolve_shader_define(name, define);
	}));
	renderer.set_shader_bank(shader_bank.get());
	vi.set_shader_bank(shader_bank.get());
#endif
}

bool CommandProcessor::device_is_supported() const
{
	return is_supported;
}

void CommandProcessor::clear_hidden_rdram()
{
	clear_buffer(*hidden_rdram, 0x03030303);
}

void CommandProcessor::clear_tmem()
{
	clear_buffer(*tmem, 0);
}

void CommandProcessor::clear_buffer(Vulkan::Buffer &buffer, uint32_t value)
{
	if (!buffer.get_allocation().is_host_allocation())
	{
		auto cmd = device.request_command_buffer();
		cmd->fill_buffer(buffer, value);
		Fence fence;
		device.submit(cmd, &fence);
		fence->wait();
	}
	else
	{
		auto *mapped = device.map_host_buffer(buffer, MEMORY_ACCESS_WRITE_BIT);
		memset(mapped, value & 0xff, buffer.get_create_info().size);
		device.unmap_host_buffer(buffer, MEMORY_ACCESS_WRITE_BIT);
	}
}

void CommandProcessor::op_sync_full(const uint32_t *)
{
	renderer.flush_and_signal();
}

void CommandProcessor::decode_triangle_setup(TriangleSetup &setup, const uint32_t *words) const
{
	const bool copy_cycle = (static_state.flags & RASTERIZATION_COPY_BIT) != 0;
	detail::decode_triangle_setup_words(
			setup,
			words,
			copy_cycle,
			quirks.u.options.native_texture_lod);
}

static void decode_tex_setup(AttributeSetup &attr, const uint32_t *words)
{
	attr.s = (words[0] & 0xffff0000u) | ((words[4] >> 16) & 0x0000ffffu);
	attr.t = ((words[0] << 16) & 0xffff0000u) | (words[4] & 0x0000ffffu);
	attr.w = (words[1] & 0xffff0000u) | ((words[5] >> 16) & 0x0000ffffu);

	attr.dsdx = (words[2] & 0xffff0000u) | ((words[6] >> 16) & 0x0000ffffu);
	attr.dtdx = ((words[2] << 16) & 0xffff0000u) | (words[6] & 0x0000ffffu);
	attr.dwdx = (words[3] & 0xffff0000u) | ((words[7] >> 16) & 0x0000ffffu);

	attr.dsde = (words[8] & 0xffff0000u) | ((words[12] >> 16) & 0x0000ffffu);
	attr.dtde = ((words[8] << 16) & 0xffff0000u) | (words[12] & 0x0000ffffu);
	attr.dwde = (words[9] & 0xffff0000u) | ((words[13] >> 16) & 0x0000ffffu);

	attr.dsdy = (words[10] & 0xffff0000u) | ((words[14] >> 16) & 0x0000ffffu);
	attr.dtdy = ((words[10] << 16) & 0xffff0000u) | (words[14] & 0x0000ffffu);
	attr.dwdy = (words[11] & 0xffff0000u) | ((words[15] >> 16) & 0x0000ffffu);
}

static void decode_rgba_setup(AttributeSetup &attr, const uint32_t *words)
{
	attr.r = (words[0] & 0xffff0000u) | ((words[4] >> 16) & 0xffff);
	attr.g = (words[0] << 16) | (words[4] & 0xffff);
	attr.b = (words[1] & 0xffff0000u) | ((words[5] >> 16) & 0xffff);
	attr.a = (words[1] << 16) | (words[5] & 0xffff);

	attr.drdx = (words[2] & 0xffff0000u) | ((words[6] >> 16) & 0xffff);
	attr.dgdx = (words[2] << 16) | (words[6] & 0xffff);
	attr.dbdx = (words[3] & 0xffff0000u) | ((words[7] >> 16) & 0xffff);
	attr.dadx = (words[3] << 16) | (words[7] & 0xffff);

	attr.drde = (words[8] & 0xffff0000u) | ((words[12] >> 16) & 0xffff);
	attr.dgde = (words[8] << 16) | (words[12] & 0xffff);
	attr.dbde = (words[9] & 0xffff0000u) | ((words[13] >> 16) & 0xffff);
	attr.dade = (words[9] << 16) | (words[13] & 0xffff);

	attr.drdy = (words[10] & 0xffff0000u) | ((words[14] >> 16) & 0xffff);
	attr.dgdy = (words[10] << 16) | (words[14] & 0xffff);
	attr.dbdy = (words[11] & 0xffff0000u) | ((words[15] >> 16) & 0xffff);
	attr.dady = (words[11] << 16) | (words[15] & 0xffff);
}

static void decode_z_setup(AttributeSetup &attr, const uint32_t *words)
{
	attr.z = words[0];
	attr.dzdx = words[1];
	attr.dzde = words[2];
	attr.dzdy = words[3];
}

void CommandProcessor::op_fill_triangle(const uint32_t *words)
{
	TriangleSetup setup = {};
	decode_triangle_setup(setup, words);
	renderer.draw_flat_primitive(setup);
}

void CommandProcessor::op_shade_triangle(const uint32_t *words)
{
	TriangleSetup setup = {};
	AttributeSetup attr = {};
	decode_triangle_setup(setup, words);
	decode_rgba_setup(attr, words + 8);
	renderer.draw_shaded_primitive(setup, attr);
}

void CommandProcessor::op_shade_z_buffer_triangle(const uint32_t *words)
{
	TriangleSetup setup = {};
	AttributeSetup attr = {};
	decode_triangle_setup(setup, words);
	decode_rgba_setup(attr, words + 8);
	decode_z_setup(attr, words + 24);
	renderer.draw_shaded_primitive(setup, attr);
}

void CommandProcessor::op_shade_texture_z_buffer_triangle(const uint32_t *words)
{
	TriangleSetup setup = {};
	AttributeSetup attr = {};
	decode_triangle_setup(setup, words);
	decode_rgba_setup(attr, words + 8);
	decode_tex_setup(attr, words + 24);
	decode_z_setup(attr, words + 40);
	renderer.draw_shaded_primitive(setup, attr);
}

void CommandProcessor::op_fill_z_buffer_triangle(const uint32_t *words)
{
	TriangleSetup setup = {};
	AttributeSetup attr = {};
	decode_triangle_setup(setup, words);
	decode_z_setup(attr, words + 8);
	renderer.draw_shaded_primitive(setup, attr);
}

void CommandProcessor::op_texture_triangle(const uint32_t *words)
{
	TriangleSetup setup = {};
	AttributeSetup attr = {};
	decode_triangle_setup(setup, words);
	decode_tex_setup(attr, words + 8);
	renderer.draw_shaded_primitive(setup, attr);
}

void CommandProcessor::op_texture_z_buffer_triangle(const uint32_t *words)
{
	TriangleSetup setup = {};
	AttributeSetup attr = {};
	decode_triangle_setup(setup, words);
	decode_tex_setup(attr, words + 8);
	decode_z_setup(attr, words + 24);
	renderer.draw_shaded_primitive(setup, attr);
}

void CommandProcessor::op_shade_texture_triangle(const uint32_t *words)
{
	TriangleSetup setup = {};
	AttributeSetup attr = {};
	decode_triangle_setup(setup, words);
	decode_rgba_setup(attr, words + 8);
	decode_tex_setup(attr, words + 24);
	renderer.draw_shaded_primitive(setup, attr);
}

void CommandProcessor::op_set_color_image(const uint32_t *words)
{
	unsigned fmt = (words[0] >> 21) & 7;
	unsigned size = (words[0] >> 19) & 3;
	unsigned width = (words[0] & 1023) + 1;
	unsigned addr = words[1] & 0xffffff;

	FBFormat fbfmt;
	switch (size)
	{
	case 0:
		fbfmt = FBFormat::I4;
		break;

	case 1:
		fbfmt = FBFormat::I8;
		break;

	case 2:
		fbfmt = fmt ? FBFormat::IA88 : FBFormat::RGBA5551;
		break;

	case 3:
		fbfmt = FBFormat::RGBA8888;
		break;

	default:
		LOGE("Invalid pixel size %u.\n", size);
		return;
	}

	renderer.set_color_framebuffer(addr, width, fbfmt);
}

void CommandProcessor::op_set_mask_image(const uint32_t *words)
{
	unsigned addr = words[1] & 0xffffff;
	renderer.set_depth_framebuffer(addr);
}

void CommandProcessor::op_set_scissor(const uint32_t *words)
{
	detail::apply_set_scissor_words(scissor_state, static_state, words[0], words[1]);
	renderer.set_scissor_state(scissor_state);
	renderer.set_static_rasterization_state(static_state);
}

void CommandProcessor::op_set_other_modes(const uint32_t *words)
{
	const bool enable_primitive_depth = detail::apply_set_other_modes_words(
			static_state,
			depth_blend,
			words[0],
			words[1]);

	renderer.set_static_rasterization_state(static_state);
	renderer.set_depth_blend_state(depth_blend);
	renderer.set_enable_primitive_depth(enable_primitive_depth);
}

void CommandProcessor::op_set_texture_image(const uint32_t *words)
{
	auto fmt = TextureFormat((words[0] >> 21) & 7);
	auto size = TextureSize((words[0] >> 19) & 3);
	uint32_t width = (words[0] & 0x3ff) + 1;
	uint32_t addr = words[1] & 0x00ffffffu;

	texture_image.addr = addr;
	texture_image.width = width;
	texture_image.size = size;
	texture_image.fmt = fmt;
}

void CommandProcessor::op_set_tile(const uint32_t *words)
{
	uint32_t tile = (words[1] >> 24) & 7;

	TileMeta info = {};
	info.offset = ((words[0] >> 0) & 511) << 3;
	info.stride = ((words[0] >> 9) & 511) << 3;
	info.size = TextureSize((words[0] >> 19) & 3);
	info.fmt = TextureFormat((words[0] >> 21) & 7);

	info.palette = (words[1] >> 20) & 15;

	info.shift_s = (words[1] >> 0) & 15;
	info.mask_s = (words[1] >> 4) & 15;
	info.shift_t = (words[1] >> 10) & 15;
	info.mask_t = (words[1] >> 14) & 15;

	if (words[1] & (1 << 8))
		info.flags |= TILE_INFO_MIRROR_S_BIT;
	if (words[1] & (1 << 9))
		info.flags |= TILE_INFO_CLAMP_S_BIT;
	if (words[1] & (1 << 18))
		info.flags |= TILE_INFO_MIRROR_T_BIT;
	if (words[1] & (1 << 19))
		info.flags |= TILE_INFO_CLAMP_T_BIT;

	if (info.mask_s > 10)
		info.mask_s = 10;
	else if (info.mask_s == 0)
		info.flags |= TILE_INFO_CLAMP_S_BIT;

	if (info.mask_t > 10)
		info.mask_t = 10;
	else if (info.mask_t == 0)
		info.flags |= TILE_INFO_CLAMP_T_BIT;

	renderer.set_tile(tile, info);
}

void CommandProcessor::op_load_tile(const uint32_t *words)
{
	uint32_t tile = (words[1] >> 24) & 7;

	LoadTileInfo info = {};

	info.tex_addr = texture_image.addr;
	info.tex_width = texture_image.width;
	info.fmt = texture_image.fmt;
	info.size = texture_image.size;
	info.slo = (words[0] >> 12) & 0xfff;
	info.shi = (words[1] >> 12) & 0xfff;
	info.tlo = (words[0] >> 0) & 0xfff;
	info.thi = (words[1] >> 0) & 0xfff;
	info.mode = UploadMode::Tile;

	renderer.load_tile(tile, info);
}

void CommandProcessor::op_load_tlut(const uint32_t *words)
{
	uint32_t tile = (words[1] >> 24) & 7;

	LoadTileInfo info = {};

	info.tex_addr = texture_image.addr;
	info.tex_width = texture_image.width;
	info.fmt = texture_image.fmt;
	info.size = texture_image.size;
	info.slo = (words[0] >> 12) & 0xfff;
	info.shi = (words[1] >> 12) & 0xfff;
	info.tlo = (words[0] >> 0) & 0xfff;
	info.thi = (words[1] >> 0) & 0xfff;
	info.mode = UploadMode::TLUT;

	renderer.load_tile(tile, info);
}

void CommandProcessor::op_load_block(const uint32_t *words)
{
	uint32_t tile = (words[1] >> 24) & 7;

	LoadTileInfo info = {};

	info.tex_addr = texture_image.addr;
	info.tex_width = texture_image.width;
	info.fmt = texture_image.fmt;
	info.size = texture_image.size;
	info.slo = (words[0] >> 12) & 0xfff;
	info.shi = (words[1] >> 12) & 0xfff;
	info.tlo = (words[0] >> 0) & 0xfff;
	info.thi = (words[1] >> 0) & 0xfff;
	info.mode = UploadMode::Block;

	renderer.load_tile(tile, info);
}

void CommandProcessor::op_set_tile_size(const uint32_t *words)
{
	uint32_t tile = (words[1] >> 24) & 7;
	auto slo = (words[0] >> 12) & 0xfff;
	auto shi = (words[1] >> 12) & 0xfff;
	auto tlo = (words[0] >> 0) & 0xfff;
	auto thi = (words[1] >> 0) & 0xfff;
	renderer.set_tile_size(tile, slo, shi, tlo, thi);
}

void CommandProcessor::op_set_combine(const uint32_t *words)
{
	static_state.combiner[0].rgb.muladd = static_cast<RGBMulAdd>((words[0] >> 20) & 0xf);
	static_state.combiner[0].rgb.mul = static_cast<RGBMul>((words[0] >> 15) & 0x1f);
	static_state.combiner[0].rgb.mulsub = static_cast<RGBMulSub>((words[1] >> 28) & 0xf);
	static_state.combiner[0].rgb.add = static_cast<RGBAdd>(words[1] >> 15 & 0x7);

	static_state.combiner[0].alpha.muladd = static_cast<AlphaAddSub>((words[0] >> 12) & 0x7);
	static_state.combiner[0].alpha.mulsub = static_cast<AlphaAddSub>((words[1] >> 12) & 0x7);
	static_state.combiner[0].alpha.mul = static_cast<AlphaMul>((words[0] >> 9) & 0x7);
	static_state.combiner[0].alpha.add = static_cast<AlphaAddSub>((words[1] >> 9) & 0x7);

	static_state.combiner[1].rgb.muladd = static_cast<RGBMulAdd>((words[0] >> 5) & 0xf);
	static_state.combiner[1].rgb.mul = static_cast<RGBMul>((words[0] >> 0) & 0x1f);
	static_state.combiner[1].rgb.mulsub = static_cast<RGBMulSub>((words[1] >> 24) & 0xf);
	static_state.combiner[1].rgb.add = static_cast<RGBAdd>(words[1] >> 6 & 0x7);

	static_state.combiner[1].alpha.muladd = static_cast<AlphaAddSub>((words[1] >> 21) & 0x7);
	static_state.combiner[1].alpha.mulsub = static_cast<AlphaAddSub>((words[1] >> 3) & 0x7);
	static_state.combiner[1].alpha.mul = static_cast<AlphaMul>((words[1] >> 18) & 0x7);
	static_state.combiner[1].alpha.add = static_cast<AlphaAddSub>((words[1] >> 0) & 0x7);

	renderer.set_static_rasterization_state(static_state);
}

void CommandProcessor::op_set_blend_color(const uint32_t *words)
{
	renderer.set_blend_color(words[1]);
}

void CommandProcessor::op_set_env_color(const uint32_t *words)
{
	renderer.set_env_color(words[1]);
}

void CommandProcessor::op_set_fog_color(const uint32_t *words)
{
	renderer.set_fog_color(words[1]);
}

void CommandProcessor::op_set_prim_color(const uint32_t *words)
{
	uint8_t prim_min_level = (words[0] >> 8) & 31;
	uint8_t prim_level_frac = (words[0] >> 0) & 0xff;
	renderer.set_primitive_color(prim_min_level, prim_level_frac, words[1]);
}

void CommandProcessor::op_set_fill_color(const uint32_t *words)
{
	renderer.set_fill_color(words[1]);
}

void CommandProcessor::op_fill_rectangle(const uint32_t *words)
{
	auto rect = detail::decode_rectangle_coordinates(words[0], words[1]);
	rect = detail::apply_copy_fill_y_adjust(rect, static_state.flags);
	renderer.draw_flat_primitive(detail::build_fill_rectangle_setup(rect));
}

void CommandProcessor::op_texture_rectangle(const uint32_t *words)
{
	auto rect = detail::decode_rectangle_coordinates(words[0], words[1]);
	rect = detail::apply_copy_fill_y_adjust(rect, static_state.flags);

	detail::TextureRectanglePolicyInput input = {};
	input.rect = rect;
	input.word1 = words[1];
	input.word2 = words[2];
	input.word3 = words[3];
	input.raster_flags = static_state.flags;
	input.flip = false;
	input.native_resolution_tex_rect = quirks.u.options.native_resolution_tex_rect;
	input.native_texture_lod = quirks.u.options.native_texture_lod;

	auto policy = detail::build_texture_rectangle_policy(input);
	renderer.draw_shaded_primitive(policy.setup, policy.attr);
}

void CommandProcessor::op_texture_rectangle_flip(const uint32_t *words)
{
	auto rect = detail::decode_rectangle_coordinates(words[0], words[1]);
	rect = detail::apply_copy_fill_y_adjust(rect, static_state.flags);

	detail::TextureRectanglePolicyInput input = {};
	input.rect = rect;
	input.word1 = words[1];
	input.word2 = words[2];
	input.word3 = words[3];
	input.raster_flags = static_state.flags;
	input.flip = true;
	input.native_resolution_tex_rect = quirks.u.options.native_resolution_tex_rect;
	input.native_texture_lod = quirks.u.options.native_texture_lod;

	auto policy = detail::build_texture_rectangle_policy(input);
	renderer.draw_shaded_primitive(policy.setup, policy.attr);
}

void CommandProcessor::op_set_prim_depth(const uint32_t *words)
{
	renderer.set_primitive_depth((words[1] >> 16) & 0xffff, words[1] & 0xffff);
}

void CommandProcessor::op_set_convert(const uint32_t *words)
{
	uint64_t merged = (uint64_t(words[0]) << 32) | words[1];

	uint16_t k5 = (merged >> 0) & 0x1ff;
	uint16_t k4 = (merged >> 9) & 0x1ff;
	uint16_t k3 = (merged >> 18) & 0x1ff;
	uint16_t k2 = (merged >> 27) & 0x1ff;
	uint16_t k1 = (merged >> 36) & 0x1ff;
	uint16_t k0 = (merged >> 45) & 0x1ff;
	renderer.set_convert(k0, k1, k2, k3, k4, k5);
}

void CommandProcessor::op_set_key_gb(const uint32_t *words)
{
	uint32_t g_width = (words[0] >> 12) & 0xfff;
	uint32_t b_width = (words[0] >> 0) & 0xfff;
	uint32_t g_center = (words[1] >> 24) & 0xff;
	uint32_t g_scale = (words[1] >> 16) & 0xff;
	uint32_t b_center = (words[1] >> 8) & 0xff;
	uint32_t b_scale = (words[1] >> 0) & 0xff;
	renderer.set_color_key(1, g_width, g_center, g_scale);
	renderer.set_color_key(2, b_width, b_center, b_scale);
}

void CommandProcessor::op_set_key_r(const uint32_t *words)
{
	uint32_t r_width = (words[1] >> 16) & 0xfff;
	uint32_t r_center = (words[1] >> 8) & 0xff;
	uint32_t r_scale = (words[1] >> 0) & 0xff;
	renderer.set_color_key(0, r_width, r_center, r_scale);
}

#define OP(x) void CommandProcessor::op_##x(const uint32_t *) {}
OP(sync_load) OP(sync_pipe)
OP(sync_tile)
#undef OP

void CommandProcessor::enqueue_command(unsigned num_words, const uint32_t *words)
{
	if (single_threaded_processing)
		enqueue_command_direct(num_words, words);
	else
		ring.enqueue_command(num_words, words);
}

void CommandProcessor::enqueue_command_direct(unsigned, const uint32_t *words)
{
#define OP(x) &CommandProcessor::op_##x
	using CommandFunc = void (CommandProcessor::*)(const uint32_t *words);
	static const CommandFunc funcs[64] = {
		/* 0x00 */ nullptr, nullptr, nullptr, nullptr,
		/* 0x04 */ nullptr, nullptr, nullptr, nullptr,
		/* 0x08 */ OP(fill_triangle), OP(fill_z_buffer_triangle), OP(texture_triangle), OP(texture_z_buffer_triangle),
		/* 0x0c */ OP(shade_triangle), OP(shade_z_buffer_triangle), OP(shade_texture_triangle), OP(shade_texture_z_buffer_triangle),
		/* 0x10 */ nullptr, nullptr, nullptr, nullptr,
		/* 0x14 */ nullptr, nullptr, nullptr, nullptr,
		/* 0x18 */ nullptr, nullptr, nullptr, nullptr,
		/* 0x1c */ nullptr, nullptr, nullptr, nullptr,
		/* 0x20 */ nullptr, nullptr, nullptr, nullptr,
		/* 0x24 */ OP(texture_rectangle), OP(texture_rectangle_flip), OP(sync_load), OP(sync_pipe),
		/* 0x28 */ OP(sync_tile), OP(sync_full), OP(set_key_gb), OP(set_key_r),
		/* 0x2c */ OP(set_convert), OP(set_scissor), OP(set_prim_depth), OP(set_other_modes),
		/* 0x30 */ OP(load_tlut), nullptr, OP(set_tile_size), OP(load_block),
		/* 0x34 */ OP(load_tile), OP(set_tile), OP(fill_rectangle), OP(set_fill_color),
		/* 0x38 */ OP(set_fog_color), OP(set_blend_color), OP(set_prim_color), OP(set_env_color),
		/* 0x3c */ OP(set_combine), OP(set_texture_image), OP(set_mask_image), OP(set_color_image),
	};
#undef OP

	unsigned op = (words[0] >> 24) & 63;
	switch (Op(op))
	{
	case Op::MetaSignalTimeline:
	{
		renderer.flush_and_signal();
		uint64_t val = words[1] | (uint64_t(words[2]) << 32);
		CoherencyOperation signal_op;
		signal_op.timeline_value = val;
		timeline_worker.push(std::move(signal_op));
		break;
	}

	case Op::MetaFlush:
	{
		renderer.flush_and_signal();
		break;
	}

	case Op::MetaIdle:
	{
		renderer.notify_idle_command_thread();
		break;
	}

	case Op::MetaSetQuirks:
	{
		quirks.u.words[0] = words[1];
		break;
	}

	default:
		if (funcs[op])
			(this->*funcs[op])(words);
		break;
	}
}

void CommandProcessor::set_quirks(const Quirks &quirks_)
{
	const uint32_t words[2] = {
		uint32_t(Op::MetaSetQuirks) << 24u,
		quirks_.u.words[0],
	};
	enqueue_command(2, words);
}

void CommandProcessor::configure_hires_replacement(bool enable, const char *cache_path)
{
	replacement_provider.clear();
	replacement_provider.set_enabled(enable);
	renderer.set_replacement_provider(nullptr);

	auto outcome = detail::classify_hires_configure_outcome(enable, cache_path, false);
	if (outcome == detail::HiresConfigureOutcome::Disabled)
		return;

	if (outcome == detail::HiresConfigureOutcome::MissingPath)
	{
		LOGW("Hi-res replacement enabled, but cache path is empty.\n");
		return;
	}

	const bool load_ok = replacement_provider.load_cache_dir(cache_path);
	outcome = detail::classify_hires_configure_outcome(enable, cache_path, load_ok);
	if (outcome == detail::HiresConfigureOutcome::LoadFailed)
	{
		LOGW("Hi-res replacement cache load failed for path: %s\n", cache_path);
		return;
	}

	LOGI("Hi-res replacement cache loaded: %zu entries from %s\n",
	     replacement_provider.entry_count(), cache_path);
	if (detail::should_attach_hires_provider(outcome))
		renderer.set_replacement_provider(&replacement_provider);
}

void CommandProcessor::set_vi_register(VIRegister reg, uint32_t value)
{
	vi.set_vi_register(reg, value);
}

void *CommandProcessor::begin_read_rdram()
{
	if (rdram)
		return device.map_host_buffer(*rdram, MEMORY_ACCESS_READ_BIT);
	else
		return nullptr;
}

void CommandProcessor::end_write_rdram()
{
	if (rdram)
		device.unmap_host_buffer(*rdram, MEMORY_ACCESS_WRITE_BIT);
}

void *CommandProcessor::begin_read_hidden_rdram()
{
	return device.map_host_buffer(*hidden_rdram, MEMORY_ACCESS_READ_BIT);
}

void CommandProcessor::end_write_hidden_rdram()
{
	device.unmap_host_buffer(*hidden_rdram, MEMORY_ACCESS_WRITE_BIT);
}

size_t CommandProcessor::get_rdram_size() const
{
	if (is_host_coherent)
		return rdram->get_create_info().size;
	else
		return rdram->get_create_info().size / 2;
}

size_t CommandProcessor::get_hidden_rdram_size() const
{
	return hidden_rdram->get_create_info().size;
}

void *CommandProcessor::get_tmem()
{
	return device.map_host_buffer(*tmem, MEMORY_ACCESS_READ_BIT);
}

void CommandProcessor::idle()
{
	flush();
	wait_for_timeline(signal_timeline());
}

void CommandProcessor::flush()
{
	const uint32_t words[1] = {
		uint32_t(Op::MetaFlush) << 24,
	};
	enqueue_command(1, words);
}

uint64_t CommandProcessor::signal_timeline()
{
	timeline_value++;

	const uint32_t words[3] = {
		uint32_t(Op::MetaSignalTimeline) << 24,
		uint32_t(timeline_value),
		uint32_t(timeline_value >> 32),
	};
	enqueue_command(3, words);

	return timeline_value;
}

void CommandProcessor::wait_for_timeline(uint64_t index)
{
	Vulkan::QueryPoolHandle start_ts, end_ts;
	if (measure_stall_time)
		start_ts = device.write_calibrated_timestamp();
	timeline_worker.wait([this, index]() -> bool {
		return thread_timeline_value >= index;
	});
	if (measure_stall_time)
	{
		end_ts = device.write_calibrated_timestamp();
		device.register_time_interval("RDP CPU", std::move(start_ts), std::move(end_ts), "wait-for-timeline");
	}
}

Vulkan::ImageHandle CommandProcessor::scanout(const ScanoutOptions &opts)
{
	Vulkan::QueryPoolHandle start_ts, end_ts;
	drain_command_ring();

	// Block idle callbacks triggering while we're doing this.
	renderer.lock_command_processing();
	{
		detail::run_scanout_coherency_sequence(
				is_host_coherent,
				[&]() {
					renderer.flush_and_signal();
				},
				[&](unsigned &offset, unsigned &length) {
					vi.scanout_memory_range(offset, length);
				},
				[&](unsigned offset, unsigned length) {
					renderer.resolve_coherency_external(offset, length);
				});
	}
	renderer.unlock_command_processing();

	auto scanout = vi.scanout(VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, opts, renderer.get_scaling_factor());
	return scanout;
}

void CommandProcessor::drain_command_ring()
{
	Vulkan::QueryPoolHandle start_ts, end_ts;
	if (timestamp)
		start_ts = device.write_calibrated_timestamp();
	ring.drain();
	if (timestamp)
	{
		end_ts = device.write_calibrated_timestamp();
		device.register_time_interval("RDP CPU", std::move(start_ts), std::move(end_ts), "drain-command-ring");
	}
}

void CommandProcessor::scanout_sync(std::vector<RGBA> &colors, unsigned &width, unsigned &height)
{
	drain_command_ring();
	detail::run_scanout_coherency_sequence(
			is_host_coherent,
			[&]() {
				renderer.flush_and_signal();
			},
			[&](unsigned &offset, unsigned &length) {
				vi.scanout_memory_range(offset, length);
			},
			[&](unsigned offset, unsigned length) {
				renderer.resolve_coherency_external(offset, length);
			});

	ScanoutOptions opts = {};
	// Downscale down to 1x, always.
	opts.downscale_steps = 32;
	opts.blend_previous_frame = true;
	opts.upscale_deinterlacing = false;

	auto handle = vi.scanout(VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, opts, renderer.get_scaling_factor());

	if (!handle)
	{
		width = 0;
		height = 0;
		colors.clear();
		return;
	}

	width = handle->get_width();
	height = handle->get_height();

	Vulkan::BufferCreateInfo info = {};
	info.size = width * height * sizeof(uint32_t);
	info.usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT;
	info.domain = Vulkan::BufferDomain::CachedHost;
	auto readback = device.create_buffer(info);

	auto cmd = device.request_command_buffer();
	cmd->copy_image_to_buffer(*readback, *handle, 0, {}, { width, height, 1 }, 0, 0, { VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1 });
	cmd->barrier(VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT,
	             VK_PIPELINE_STAGE_HOST_BIT, VK_ACCESS_HOST_READ_BIT);

	Vulkan::Fence fence;
	device.submit(cmd, &fence);
	fence->wait();

	colors.resize(width * height);
	memcpy(colors.data(), device.map_host_buffer(*readback, Vulkan::MEMORY_ACCESS_READ_BIT),
	       width * height * sizeof(uint32_t));
	device.unmap_host_buffer(*readback, Vulkan::MEMORY_ACCESS_READ_BIT);
}

void CommandProcessor::FenceExecutor::notify_work_locked(const CoherencyOperation &work)
{
	if (work.timeline_value)
		*value = work.timeline_value;
}

bool CommandProcessor::FenceExecutor::is_sentinel(const CoherencyOperation &work) const
{
	return !work.fence && !work.timeline_value;
}

static void masked_memcpy(uint8_t * __restrict dst,
                          const uint8_t * __restrict data_src,
                          const uint8_t * __restrict masked_src,
                          size_t size)
{
#if defined(__SSE2__)
	for (size_t i = 0; i < size; i += 16)
	{
		__m128i data = _mm_loadu_si128(reinterpret_cast<const __m128i *>(data_src + i));
		__m128i mask = _mm_loadu_si128(reinterpret_cast<const __m128i *>(masked_src + i));
		_mm_maskmoveu_si128(data, mask, reinterpret_cast<char *>(dst + i));
	}
#else
	auto * __restrict data32 = reinterpret_cast<const uint32_t *>(data_src);
	auto * __restrict mask32 = reinterpret_cast<const uint32_t *>(masked_src);
	auto * __restrict dst32 = reinterpret_cast<uint32_t *>(dst);
	auto size32 = size >> 2;

	for (size_t i = 0; i < size32; i++)
	{
		auto mask = mask32[i];
		if (mask == ~0u)
		{
			dst32[i] = data32[i];
		}
		else if (mask)
		{
			// Fairly rare path.
			for (unsigned j = 0; j < 4; j++)
				if (masked_src[4 * i + j])
					dst[4 * i + j] = data_src[4 * i + j];
		}
	}
#endif
}

void CommandProcessor::FenceExecutor::perform_work(CoherencyOperation &work)
{
	if (work.fence)
		work.fence->wait();

	if (work.unlock_cookie)
		work.unlock_cookie->fetch_sub(1, std::memory_order_relaxed);

	if (work.src)
	{
		for (auto &copy : work.copies)
		{
			auto *mapped_data = static_cast<uint8_t *>(device->map_host_buffer(*work.src, MEMORY_ACCESS_READ_BIT, copy.src_offset, copy.size));
			auto *mapped_mask = static_cast<uint8_t *>(device->map_host_buffer(*work.src, MEMORY_ACCESS_READ_BIT, copy.mask_offset, copy.size));
			masked_memcpy(work.dst + copy.dst_offset, mapped_data, mapped_mask, copy.size);
			for (unsigned i = 0; i < copy.counters; i++)
			{
				unsigned val = copy.counter_base[i].fetch_sub(1, std::memory_order_release);
				(void)val;
				assert(val > 0);
			}
		}

#ifdef __SSE2__
		_mm_mfence();
#endif
	}
}

void CommandProcessor::enqueue_coherency_operation(CoherencyOperation &&op)
{
	timeline_worker.push(std::move(op));
}
}
