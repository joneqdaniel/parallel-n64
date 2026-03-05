#pragma once

#include <libretro_vulkan.h>
#include <vulkan/vulkan.h>

namespace RDP::detail
{
struct CreateDeviceHooks
{
	bool (*init_loader)(PFN_vkGetInstanceProcAddr get_instance_proc_addr, void *userdata) = nullptr;
	void *(*create_context)(void *userdata) = nullptr;
	bool (*init_device_from_instance)(
			void *context,
			VkInstance instance,
			VkPhysicalDevice gpu,
			VkSurfaceKHR surface,
			const char **required_device_extensions,
			unsigned num_required_device_extensions,
			const char **required_device_layers,
			unsigned num_required_device_layers,
			const VkPhysicalDeviceFeatures *required_features,
			uint32_t context_creation_flags,
			void *userdata) = nullptr;
	void (*destroy_context)(void *context, void *userdata) = nullptr;
	void (*populate_frontend_context)(retro_vulkan_context *frontend_context, void *context, void *userdata) = nullptr;
	void (*release_device)(void *context, void *userdata) = nullptr;
	uint32_t context_creation_flags = 0;
	void *userdata = nullptr;
};

template <typename ContextLike>
inline void populate_frontend_context_from_context(retro_vulkan_context *frontend_context, ContextLike &context)
{
	frontend_context->gpu = context.get_gpu();
	frontend_context->device = context.get_device();
	frontend_context->queue = context.get_graphics_queue();
	frontend_context->queue_family_index = context.get_graphics_queue_family();
	frontend_context->presentation_queue = context.get_graphics_queue();
	frontend_context->presentation_queue_family_index = context.get_graphics_queue_family();
}

inline bool create_device_with_hooks(
		CreateDeviceHooks &hooks,
		retro_vulkan_context *frontend_context,
		VkInstance instance,
		VkPhysicalDevice gpu,
		VkSurfaceKHR surface,
		PFN_vkGetInstanceProcAddr get_instance_proc_addr,
		const char **required_device_extensions,
		unsigned num_required_device_extensions,
		const char **required_device_layers,
		unsigned num_required_device_layers,
		const VkPhysicalDeviceFeatures *required_features)
{
	if (!hooks.init_loader || !hooks.create_context || !hooks.init_device_from_instance ||
	    !hooks.populate_frontend_context || !hooks.release_device)
		return false;

	if (!hooks.init_loader(get_instance_proc_addr, hooks.userdata))
		return false;

	void *context = hooks.create_context(hooks.userdata);
	if (!context)
		return false;

	if (!hooks.init_device_from_instance(
				context, instance, gpu, surface,
				required_device_extensions, num_required_device_extensions,
				required_device_layers, num_required_device_layers, required_features,
				hooks.context_creation_flags, hooks.userdata))
	{
		if (hooks.destroy_context)
			hooks.destroy_context(context, hooks.userdata);
		return false;
	}

	hooks.populate_frontend_context(frontend_context, context, hooks.userdata);
	hooks.release_device(context, hooks.userdata);
	return true;
}

inline const VkApplicationInfo *parallel_application_info()
{
	static const VkApplicationInfo info = {
		VK_STRUCTURE_TYPE_APPLICATION_INFO,
		nullptr,
		"paraLLEl-RDP",
		0,
		"Granite",
		0,
		VK_API_VERSION_1_1,
	};

	return &info;
}
}
