#include "mupen64plus-video-paraLLEl/rdp_vulkan_glue.hpp"

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>

namespace
{
static void check(bool condition, const char *message)
{
	if (!condition)
	{
		std::cerr << "FAIL: " << message << std::endl;
		std::exit(1);
	}
}

struct FakeContext
{
	VkPhysicalDevice get_gpu() const
	{
		return gpu;
	}

	VkDevice get_device() const
	{
		return device;
	}

	VkQueue get_graphics_queue() const
	{
		return queue;
	}

	uint32_t get_graphics_queue_family() const
	{
		return queue_family;
	}

	VkPhysicalDevice gpu = reinterpret_cast<VkPhysicalDevice>(uintptr_t(0x1001));
	VkDevice device = reinterpret_cast<VkDevice>(uintptr_t(0x2002));
	VkQueue queue = reinterpret_cast<VkQueue>(uintptr_t(0x3003));
	uint32_t queue_family = 7;
};

struct HookState
{
	bool loader_result = true;
	bool create_returns_null = false;
	bool init_device_result = true;
	void *created_context = reinterpret_cast<void *>(uintptr_t(0xCAFE0000));

	unsigned init_loader_calls = 0;
	unsigned create_context_calls = 0;
	unsigned init_device_calls = 0;
	unsigned destroy_context_calls = 0;
	unsigned populate_calls = 0;
	unsigned release_calls = 0;

	void *last_context = nullptr;
	VkInstance last_instance = VK_NULL_HANDLE;
	VkPhysicalDevice last_gpu = VK_NULL_HANDLE;
	VkSurfaceKHR last_surface = VK_NULL_HANDLE;
	const VkPhysicalDeviceFeatures *last_required_features = nullptr;
	unsigned last_num_required_extensions = 0;
	unsigned last_num_required_layers = 0;
	uint32_t last_creation_flags = 0;

	retro_vulkan_context frontend_snapshot = {};
};

static bool test_init_loader(PFN_vkGetInstanceProcAddr, void *userdata)
{
	auto *state = static_cast<HookState *>(userdata);
	state->init_loader_calls++;
	return state->loader_result;
}

static void *test_create_context(void *userdata)
{
	auto *state = static_cast<HookState *>(userdata);
	state->create_context_calls++;
	return state->create_returns_null ? nullptr : state->created_context;
}

static bool test_init_device_from_instance(
		void *context,
		VkInstance instance,
		VkPhysicalDevice gpu,
		VkSurfaceKHR surface,
		const char **,
		unsigned num_required_device_extensions,
		const char **,
		unsigned num_required_device_layers,
		const VkPhysicalDeviceFeatures *required_features,
		uint32_t context_creation_flags,
		void *userdata)
{
	auto *state = static_cast<HookState *>(userdata);
	state->init_device_calls++;
	state->last_context = context;
	state->last_instance = instance;
	state->last_gpu = gpu;
	state->last_surface = surface;
	state->last_required_features = required_features;
	state->last_num_required_extensions = num_required_device_extensions;
	state->last_num_required_layers = num_required_device_layers;
	state->last_creation_flags = context_creation_flags;
	return state->init_device_result;
}

static void test_destroy_context(void *context, void *userdata)
{
	auto *state = static_cast<HookState *>(userdata);
	state->destroy_context_calls++;
	state->last_context = context;
}

static void test_populate_frontend_context(retro_vulkan_context *frontend_context, void *context, void *userdata)
{
	auto *state = static_cast<HookState *>(userdata);
	state->populate_calls++;
	state->last_context = context;

	frontend_context->gpu = reinterpret_cast<VkPhysicalDevice>(uintptr_t(0x1111));
	frontend_context->device = reinterpret_cast<VkDevice>(uintptr_t(0x2222));
	frontend_context->queue = reinterpret_cast<VkQueue>(uintptr_t(0x3333));
	frontend_context->queue_family_index = 4;
	frontend_context->presentation_queue = reinterpret_cast<VkQueue>(uintptr_t(0x4444));
	frontend_context->presentation_queue_family_index = 9;
	state->frontend_snapshot = *frontend_context;
}

static void test_release_device(void *context, void *userdata)
{
	auto *state = static_cast<HookState *>(userdata);
	state->release_calls++;
	state->last_context = context;
}

static VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL fake_get_instance_proc_addr(VkInstance, const char *)
{
	return nullptr;
}

static RDP::detail::CreateDeviceHooks make_hooks(HookState &state)
{
	RDP::detail::CreateDeviceHooks hooks = {};
	hooks.init_loader = test_init_loader;
	hooks.create_context = test_create_context;
	hooks.init_device_from_instance = test_init_device_from_instance;
	hooks.destroy_context = test_destroy_context;
	hooks.populate_frontend_context = test_populate_frontend_context;
	hooks.release_device = test_release_device;
	hooks.context_creation_flags = 0xA5u;
	hooks.userdata = &state;
	return hooks;
}

static void test_populate_frontend_context_mapping()
{
	FakeContext context = {};
	retro_vulkan_context frontend = {};
	RDP::detail::populate_frontend_context_from_context(&frontend, context);

	check(frontend.gpu == context.gpu, "gpu mapping mismatch");
	check(frontend.device == context.device, "device mapping mismatch");
	check(frontend.queue == context.queue, "queue mapping mismatch");
	check(frontend.queue_family_index == context.queue_family, "queue family mapping mismatch");
	check(frontend.presentation_queue == context.queue, "presentation queue mapping mismatch");
	check(frontend.presentation_queue_family_index == context.queue_family, "presentation queue family mapping mismatch");
}

static void test_parallel_application_info_contract()
{
	const VkApplicationInfo *info = RDP::detail::parallel_application_info();
	check(info != nullptr, "parallel_application_info returned null");
	check(info->sType == VK_STRUCTURE_TYPE_APPLICATION_INFO, "VkApplicationInfo sType mismatch");
	check(std::strcmp(info->pApplicationName, "paraLLEl-RDP") == 0, "application name mismatch");
	check(std::strcmp(info->pEngineName, "Granite") == 0, "engine name mismatch");
	check(info->apiVersion == VK_API_VERSION_1_1, "api version mismatch");
}

static void test_create_device_loader_failure()
{
	HookState state = {};
	state.loader_result = false;
	auto hooks = make_hooks(state);
	retro_vulkan_context frontend = {};

	const bool ok = RDP::detail::create_device_with_hooks(
			hooks,
			&frontend,
			reinterpret_cast<VkInstance>(uintptr_t(0x1)),
			reinterpret_cast<VkPhysicalDevice>(uintptr_t(0x2)),
			reinterpret_cast<VkSurfaceKHR>(uintptr_t(0x3)),
			fake_get_instance_proc_addr,
			nullptr,
			0,
			nullptr,
			0,
			nullptr);

	check(!ok, "loader failure should fail create_device_with_hooks");
	check(state.init_loader_calls == 1, "init_loader should be called once");
	check(state.create_context_calls == 0, "create_context should not be called when loader fails");
	check(state.init_device_calls == 0, "init_device should not be called when loader fails");
}

static void test_create_device_context_creation_failure()
{
	HookState state = {};
	state.create_returns_null = true;
	auto hooks = make_hooks(state);
	retro_vulkan_context frontend = {};

	const bool ok = RDP::detail::create_device_with_hooks(
			hooks,
			&frontend,
			reinterpret_cast<VkInstance>(uintptr_t(0x1)),
			reinterpret_cast<VkPhysicalDevice>(uintptr_t(0x2)),
			reinterpret_cast<VkSurfaceKHR>(uintptr_t(0x3)),
			fake_get_instance_proc_addr,
			nullptr,
			0,
			nullptr,
			0,
			nullptr);

	check(!ok, "null context creation should fail create_device_with_hooks");
	check(state.init_loader_calls == 1, "init_loader call count mismatch");
	check(state.create_context_calls == 1, "create_context should be called once");
	check(state.init_device_calls == 0, "init_device should not be called when context creation fails");
}

static void test_create_device_init_failure()
{
	HookState state = {};
	state.init_device_result = false;
	auto hooks = make_hooks(state);
	retro_vulkan_context frontend = {};

	const VkPhysicalDeviceFeatures required_features = {};
	const bool ok = RDP::detail::create_device_with_hooks(
			hooks,
			&frontend,
			reinterpret_cast<VkInstance>(uintptr_t(0x11)),
			reinterpret_cast<VkPhysicalDevice>(uintptr_t(0x22)),
			reinterpret_cast<VkSurfaceKHR>(uintptr_t(0x33)),
			fake_get_instance_proc_addr,
			nullptr,
			2,
			nullptr,
			3,
			&required_features);

	check(!ok, "init_device failure should fail create_device_with_hooks");
	check(state.init_loader_calls == 1, "init_loader call count mismatch");
	check(state.create_context_calls == 1, "create_context call count mismatch");
	check(state.init_device_calls == 1, "init_device call count mismatch");
	check(state.destroy_context_calls == 1, "destroy_context should be called on init failure");
	check(state.populate_calls == 0, "populate should not run on init failure");
	check(state.release_calls == 0, "release should not run on init failure");
}

static void test_create_device_success()
{
	HookState state = {};
	auto hooks = make_hooks(state);
	retro_vulkan_context frontend = {};

	const char *required_extensions[] = {"VK_A", "VK_B"};
	const char *required_layers[] = {"LAYER_A"};
	const VkPhysicalDeviceFeatures required_features = {};
	const VkInstance instance = reinterpret_cast<VkInstance>(uintptr_t(0x1111));
	const VkPhysicalDevice gpu = reinterpret_cast<VkPhysicalDevice>(uintptr_t(0x2222));
	const VkSurfaceKHR surface = reinterpret_cast<VkSurfaceKHR>(uintptr_t(0x3333));

	const bool ok = RDP::detail::create_device_with_hooks(
			hooks,
			&frontend,
			instance,
			gpu,
			surface,
			fake_get_instance_proc_addr,
			required_extensions,
			2,
			required_layers,
			1,
			&required_features);

	check(ok, "success path should pass");
	check(state.init_loader_calls == 1, "init_loader call count mismatch");
	check(state.create_context_calls == 1, "create_context call count mismatch");
	check(state.init_device_calls == 1, "init_device call count mismatch");
	check(state.destroy_context_calls == 0, "destroy_context should not run on success");
	check(state.populate_calls == 1, "populate should run on success");
	check(state.release_calls == 1, "release should run on success");
	check(state.last_context == state.created_context, "context pointer forwarding mismatch");
	check(state.last_instance == instance, "instance forwarding mismatch");
	check(state.last_gpu == gpu, "gpu forwarding mismatch");
	check(state.last_surface == surface, "surface forwarding mismatch");
	check(state.last_num_required_extensions == 2u, "required extension count mismatch");
	check(state.last_num_required_layers == 1u, "required layer count mismatch");
	check(state.last_required_features == &required_features, "required features pointer mismatch");
	check(state.last_creation_flags == 0xA5u, "context creation flags mismatch");

	check(frontend.gpu == state.frontend_snapshot.gpu, "frontend gpu should be populated");
	check(frontend.device == state.frontend_snapshot.device, "frontend device should be populated");
	check(frontend.queue == state.frontend_snapshot.queue, "frontend queue should be populated");
	check(frontend.queue_family_index == state.frontend_snapshot.queue_family_index,
	      "frontend queue family should be populated");
	check(frontend.presentation_queue == state.frontend_snapshot.presentation_queue,
	      "frontend presentation queue should be populated");
	check(frontend.presentation_queue_family_index == state.frontend_snapshot.presentation_queue_family_index,
	      "frontend presentation queue family should be populated");
}

static void test_create_device_missing_required_hooks()
{
	RDP::detail::CreateDeviceHooks hooks = {};
	retro_vulkan_context frontend = {};

	const bool ok = RDP::detail::create_device_with_hooks(
			hooks,
			&frontend,
			VK_NULL_HANDLE,
			VK_NULL_HANDLE,
			VK_NULL_HANDLE,
			fake_get_instance_proc_addr,
			nullptr,
			0,
			nullptr,
			0,
			nullptr);

	check(!ok, "missing hooks should fail create_device_with_hooks");
}
}

int main()
{
	test_populate_frontend_context_mapping();
	test_parallel_application_info_contract();
	test_create_device_missing_required_hooks();
	test_create_device_loader_failure();
	test_create_device_context_creation_failure();
	test_create_device_init_failure();
	test_create_device_success();
	std::cout << "emu_unit_rdp_vulkan_glue_test: PASS" << std::endl;
	return 0;
}
