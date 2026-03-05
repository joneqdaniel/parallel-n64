#include "rdp.hpp"
#include "rdp_command_ingest.hpp"
#include "rdp_frame_fallback_policy.hpp"
#include "rdp_frame_mapping.hpp"
#include "rdp_init_policy.hpp"
#include "rdp_retro_image_mapping.hpp"
#include "rdp_scanout_fallback.hpp"
#include "rdp_vulkan_glue.hpp"
#include "Gfx #1.3.h"
#include "parallel.h"
#include "z64.h"
#include "parallel-rdp/parallel-rdp/rdp_hires_runtime_policy.hpp"
#include <assert.h>
#include <stdlib.h>

using namespace Vulkan;
using namespace std;

extern retro_log_printf_t log_cb;
extern retro_environment_t environ_cb;

namespace RDP
{
const struct retro_hw_render_interface_vulkan *vulkan;

static int cmd_cur;
static int cmd_ptr;
static uint32_t cmd_data[0x00040000 >> 2];
static uint64_t pending_timeline_value, timeline_value;

static unique_ptr<CommandProcessor> frontend;
static unique_ptr<Device> device;
static unique_ptr<Context> context;
static QueryPoolHandle begin_ts, end_ts;

static vector<retro_vulkan_image> retro_images;
static vector<ImageHandle> retro_image_handles;
unsigned width, height;
unsigned overscan;
unsigned upscaling = 1;
unsigned downscaling_steps = 0;
bool native_texture_lod = false;
bool native_tex_rect = true;
bool synchronous, divot_filter, gamma_dither, vi_aa, vi_scale, dither_filter, interlacing;
bool hires_textures = false;
unsigned hires_filter = 1;
unsigned hires_srgb = 0;
string hires_cache_path;

void process_commands()
{
	detail::CommandIngestState state = {};
	state.cmd_cur = cmd_cur;
	state.cmd_ptr = cmd_ptr;
	state.cmd_data = cmd_data;

	detail::CommandIngestHooks hooks = {};
	hooks.frontend_available = bool(frontend);
	hooks.synchronous = synchronous;

	struct CallbackState
	{
		CommandProcessor *frontend = nullptr;
	} cb_state;
	cb_state.frontend = frontend.get();
	hooks.userdata = &cb_state;

	hooks.enqueue_command = [](void *userdata, unsigned num_words, const uint32_t *words) {
		auto *cb = static_cast<CallbackState *>(userdata);
		cb->frontend->enqueue_command(num_words, words);
	};
	hooks.signal_timeline = [](void *userdata) -> uint64_t {
		auto *cb = static_cast<CallbackState *>(userdata);
		return cb->frontend->signal_timeline();
	};
	hooks.wait_for_timeline = [](void *userdata, uint64_t timeline) {
		auto *cb = static_cast<CallbackState *>(userdata);
		cb->frontend->wait_for_timeline(timeline);
	};
	hooks.raise_dp_interrupt = [](void *) {
		*gfx_info.MI_INTR_REG |= DP_INTERRUPT;
		gfx_info.CheckInterrupts();
	};

	detail::process_command_ingest(
			state,
			DRAM,
			SP_DMEM,
			*GET_GFX_INFO(DPC_START_REG),
			*GET_GFX_INFO(DPC_END_REG),
			*GET_GFX_INFO(DPC_CURRENT_REG),
			*GET_GFX_INFO(DPC_STATUS_REG),
			hooks);

	cmd_cur = state.cmd_cur;
	cmd_ptr = state.cmd_ptr;
}

static QueryPoolHandle refresh_begin_ts;

void profile_refresh_begin()
{
	if (device)
		refresh_begin_ts = device->write_calibrated_timestamp();
}

void profile_refresh_end()
{
	if (device)
	{
		device->register_time_interval("Emulation", refresh_begin_ts, device->write_calibrated_timestamp(), "refresh");
		refresh_begin_ts.reset();
	}
}

void begin_frame()
{
	unsigned mask = vulkan->get_sync_index_mask(vulkan->handle);
	unsigned num_frames = detail::sync_mask_to_num_frames(mask);

	if (num_frames != retro_images.size())
	{
		retro_images.resize(num_frames);
		retro_image_handles.resize(num_frames);
	}

	vulkan->wait_sync_index(vulkan->handle);
	if (!begin_ts)
		begin_ts = device->write_calibrated_timestamp();

	//frontend->wait_for_timeline(pending_timeline_value);
	//pending_timeline_value = timeline_value;
}

bool init()
{
	if (!detail::init_prerequisites_met(context.get(), vulkan))
		return false;

	unsigned mask = vulkan->get_sync_index_mask(vulkan->handle);
	const detail::SyncFrameCounts sync_counts = detail::compute_sync_frame_counts(mask);
	const unsigned num_frames = sync_counts.num_frames;
	const unsigned num_sync_frames = sync_counts.num_sync_frames;

	retro_images.resize(num_frames);
	retro_image_handles.resize(num_frames);

	device.reset(new Device);
	device->set_context(*context);
	device->init_frame_contexts(num_sync_frames);
	log_cb(RETRO_LOG_INFO, "Using %u sync frames for parallel-RDP.\n", num_sync_frames);
	device->set_queue_lock(
			[]() { vulkan->lock_queue(vulkan->handle); },
			[]() { vulkan->unlock_queue(vulkan->handle); });

	const auto &features = device->get_device_features();
	detail::HostMemoryImportPlan host_mem_plan = detail::plan_host_memory_import(
			reinterpret_cast<uintptr_t>(gfx_info.RDRAM),
			features.supports_external_memory_host,
			features.host_memory_properties.minImportedHostPointerAlignment);

	uintptr_t aligned_rdram = host_mem_plan.aligned_rdram;
	uintptr_t offset = host_mem_plan.offset;

	if (!features.supports_external_memory_host)
	{
		log_cb(RETRO_LOG_WARN, "VK_EXT_external_memory_host is not supported by this device. Application might run slower because of this.\n");
	}
	else
	{
		// Keep current behavior: no extra logging on aligned-path success.
	}

	CommandProcessorFlags flags = 0;
	switch (upscaling)
	{
		case 2:
			flags |= COMMAND_PROCESSOR_FLAG_UPSCALING_2X_BIT;
			log_cb(RETRO_LOG_INFO, "Using 2x upscaling!\n");
			break;

		case 4:
			flags |= COMMAND_PROCESSOR_FLAG_UPSCALING_4X_BIT;
			log_cb(RETRO_LOG_INFO, "Using 4x upscaling!\n");
			break;

		case 8:
			flags |= COMMAND_PROCESSOR_FLAG_UPSCALING_8X_BIT;
			log_cb(RETRO_LOG_INFO, "Using 8x upscaling!\n");
			break;

		default:
			break;
	}

	frontend.reset(new CommandProcessor(*device, reinterpret_cast<void *>(aligned_rdram),
				offset, 8 * 1024 * 1024, 4 * 1024 * 1024, flags));

	if (!detail::ensure_frontend_device_supported(frontend))
	{
		log_cb(RETRO_LOG_ERROR, "This device probably does not support 8/16-bit storage. Make sure you're using up-to-date drivers!\n");
		return false;
	}

	RDP::Quirks quirks;
	quirks.set_native_texture_lod(native_texture_lod);
	quirks.set_native_resolution_tex_rect(native_tex_rect);
	frontend->set_quirks(quirks);

	hires_cache_path = detail::resolve_hires_cache_path(hires_cache_path, getenv("PARALLEL_RDP_HIRES_CACHE_PATH"));

	if (hires_textures)
	{
		log_cb(RETRO_LOG_INFO,
		       "Hi-res textures enabled (path=%s, filter=%u, srgb_mode=%u).\n",
		       hires_cache_path.c_str(), hires_filter, hires_srgb);
	}

	frontend->configure_hires_replacement(hires_textures, hires_cache_path.c_str());

	timeline_value = 0;
	pending_timeline_value = 0;
	width = 0;
	height = 0;
	return true;
}

void deinit()
{
	detail::clear_deinit_state(begin_ts, end_ts, retro_image_handles, retro_images, frontend, device, context);
}

static void complete_frame_error()
{
	static const char error_tex[] =
		"ooooooooooooooooooooooooo"
		"ooXXXXXoooXXXXXoooXXXXXoo"
		"ooXXooooooXoooXoooXoooXoo"
		"ooXXXXXoooXXXXXoooXXXXXoo"
		"ooXXXXXoooXoXoooooXoXoooo"
		"ooXXooooooXooXooooXooXooo"
		"ooXXXXXoooXoooXoooXoooXoo"
		"ooooooooooooooooooooooooo";

	auto info = Vulkan::ImageCreateInfo::immutable_2d_image(50, 16, VK_FORMAT_R8G8B8A8_UNORM, false);
	info.usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
	info.misc = IMAGE_MISC_MUTABLE_SRGB_BIT;

	Vulkan::ImageInitialData data = {};

	uint32_t tex_data[16][50];
	for (unsigned y = 0; y < 16; y++)
		for (unsigned x = 0; x < 50; x++)
			tex_data[y][x] = error_tex[25 * (y >> 1) + (x >> 1)] != 'o' ? 0xffffffffu : 0u;
	data.data = tex_data;
	auto image = device->create_image(info, &data);

	unsigned index = vulkan->get_sync_index(vulkan->handle);
	assert(index < retro_images.size());

	detail::populate_retro_image_slot(retro_images[index], image->get_image(), image->get_view().get_view());

	vulkan->set_image(vulkan->handle, &retro_images[index], 0, nullptr, VK_QUEUE_FAMILY_IGNORED);
	width = image->get_width();
	height = image->get_height();
	retro_image_handles[index] = image;

	device->flush_frame();
}

void complete_frame()
{
	if (detail::handle_complete_frame_fallback(
			    bool(frontend),
			    bool(device),
			    [&]() {
				    complete_frame_error();
			    },
			    [&]() {
				    device->next_frame_context();
			    }))
		return;

	timeline_value = frontend->signal_timeline();

	detail::forward_vi_registers(
			[&](VIRegister reg, uint32_t value) {
				frontend->set_vi_register(reg, value);
			},
			gfx_info);

	ScanoutOptions opts = detail::make_scanout_options(
			vi_aa, vi_scale, dither_filter, divot_filter, gamma_dither, downscaling_steps, overscan);
	auto image = frontend->scanout(opts);
	unsigned index = vulkan->get_sync_index(vulkan->handle);

	image = detail::ensure_scanout_image(
			image,
			[&]() {
				return device->create_image(detail::make_null_scanout_image_info());
			},
			[&]() {
				return device->request_command_buffer();
			},
			[&](Vulkan::CommandBufferHandle &cmd, Vulkan::ImageHandle &target_image) {
				cmd->image_barrier(*target_image,
						VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
						VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, 0,
						VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT);
			},
			[&](Vulkan::CommandBufferHandle &cmd, Vulkan::ImageHandle &target_image) {
				cmd->clear_image(*target_image, {});
			},
			[&](Vulkan::CommandBufferHandle &cmd, Vulkan::ImageHandle &target_image) {
				cmd->image_barrier(*target_image,
						VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
						VK_PIPELINE_STAGE_TRANSFER_BIT, VK_ACCESS_TRANSFER_WRITE_BIT,
						VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, VK_ACCESS_SHADER_READ_BIT);
			},
			[&](Vulkan::CommandBufferHandle &cmd) {
				device->submit(cmd);
			});

	assert(index < retro_images.size());

	detail::populate_retro_image_slot(retro_images[index], image->get_image(), image->get_view().get_view());

	vulkan->set_image(vulkan->handle, &retro_images[index], 0, nullptr, VK_QUEUE_FAMILY_IGNORED);
	width = image->get_width();
	height = image->get_height();
	retro_image_handles[index] = image;

	end_ts = device->write_calibrated_timestamp();
	device->register_time_interval("Emulation", begin_ts, end_ts, "frame");
	begin_ts.reset();
	end_ts.reset();

	RDP::Quirks quirks;
	quirks.set_native_texture_lod(native_texture_lod);
	quirks.set_native_resolution_tex_rect(native_tex_rect);
	frontend->set_quirks(quirks);

	frontend->begin_frame_context();
}
}

bool parallel_create_device(struct retro_vulkan_context *frontend_context, VkInstance instance, VkPhysicalDevice gpu,
                            VkSurfaceKHR surface, PFN_vkGetInstanceProcAddr get_instance_proc_addr,
                            const char **required_device_extensions, unsigned num_required_device_extensions,
                            const char **required_device_layers, unsigned num_required_device_layers,
                            const VkPhysicalDeviceFeatures *required_features)
{
	::RDP::detail::CreateDeviceHooks hooks = {};
	hooks.userdata = &::RDP::context;
	hooks.context_creation_flags = Vulkan::CONTEXT_CREATION_DISABLE_BINDLESS_BIT;
	hooks.init_loader = [](PFN_vkGetInstanceProcAddr proc_addr, void *) -> bool {
		return Vulkan::Context::init_loader(proc_addr);
	};
	hooks.create_context = [](void *userdata) -> void * {
		auto *ctx_holder = static_cast<std::unique_ptr<Vulkan::Context> *>(userdata);
		ctx_holder->reset(new Vulkan::Context);
		return ctx_holder->get();
	};
	hooks.init_device_from_instance = [](void *context_ptr,
			VkInstance init_instance, VkPhysicalDevice init_gpu, VkSurfaceKHR init_surface,
			const char **req_device_extensions, unsigned req_num_device_extensions,
			const char **req_device_layers, unsigned req_num_device_layers,
			const VkPhysicalDeviceFeatures *req_features,
			uint32_t creation_flags, void *) -> bool {
		auto *ctx = static_cast<Vulkan::Context *>(context_ptr);
		return ctx->init_device_from_instance(
				init_instance, init_gpu, init_surface,
				req_device_extensions, req_num_device_extensions,
				req_device_layers, req_num_device_layers,
				req_features, creation_flags);
	};
	hooks.destroy_context = [](void *, void *userdata) {
		auto *ctx_holder = static_cast<std::unique_ptr<Vulkan::Context> *>(userdata);
		ctx_holder->reset();
	};
	hooks.populate_frontend_context = [](retro_vulkan_context *frontend, void *context_ptr, void *) {
		auto *ctx = static_cast<Vulkan::Context *>(context_ptr);
		::RDP::detail::populate_frontend_context_from_context(frontend, *ctx);
	};
	hooks.release_device = [](void *context_ptr, void *) {
		// Frontend owns the device.
		static_cast<Vulkan::Context *>(context_ptr)->release_device();
	};

	return ::RDP::detail::create_device_with_hooks(
			hooks, frontend_context, instance, gpu, surface, get_instance_proc_addr,
			required_device_extensions, num_required_device_extensions,
			required_device_layers, num_required_device_layers, required_features);
}

const VkApplicationInfo *parallel_get_application_info(void)
{
	return ::RDP::detail::parallel_application_info();
}
