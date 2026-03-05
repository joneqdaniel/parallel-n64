#ifndef PARALLEL_RDP_SCANOUT_FALLBACK_HPP
#define PARALLEL_RDP_SCANOUT_FALLBACK_HPP

#include "parallel-rdp/vulkan/image.hpp"

namespace RDP
{
namespace detail
{
inline Vulkan::ImageCreateInfo make_null_scanout_image_info()
{
	auto info = Vulkan::ImageCreateInfo::immutable_2d_image(1, 1, VK_FORMAT_R8G8B8A8_UNORM);
	info.usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
	             VK_IMAGE_USAGE_TRANSFER_DST_BIT;
	info.misc = Vulkan::IMAGE_MISC_MUTABLE_SRGB_BIT;
	info.initial_layout = VK_IMAGE_LAYOUT_UNDEFINED;
	return info;
}

template <typename ImageHandle,
          typename CreateFallbackImageFn,
          typename RequestCommandBufferFn,
          typename BarrierToTransferDstFn,
          typename ClearImageFn,
          typename BarrierToShaderReadFn,
          typename SubmitFn>
inline ImageHandle ensure_scanout_image(ImageHandle image,
                                        CreateFallbackImageFn &&create_fallback_image,
                                        RequestCommandBufferFn &&request_command_buffer,
                                        BarrierToTransferDstFn &&barrier_to_transfer_dst,
                                        ClearImageFn &&clear_image,
                                        BarrierToShaderReadFn &&barrier_to_shader_read,
                                        SubmitFn &&submit)
{
	if (image)
		return image;

	image = create_fallback_image();
	auto cmd = request_command_buffer();
	barrier_to_transfer_dst(cmd, image);
	clear_image(cmd, image);
	barrier_to_shader_read(cmd, image);
	submit(cmd);
	return image;
}
}
}

#endif
