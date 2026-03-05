#pragma once

#include <cstdint>

namespace RDP
{
namespace detail
{
struct HiresDescriptorFeatureSupport
{
	bool descriptor_indexing = false;
	bool runtime_descriptor_array = false;
	bool sampled_image_array_non_uniform_indexing = false;
	bool descriptor_binding_variable_descriptor_count = false;
	bool descriptor_binding_partially_bound = false;
	bool descriptor_binding_update_after_bind = false;
};

enum class HiresDescriptorRequirement
{
	Supported,
	MissingDescriptorIndexing,
	MissingRuntimeDescriptorArray,
	MissingSampledImageArrayNonUniformIndexing,
	MissingDescriptorBindingVariableDescriptorCount,
	MissingDescriptorBindingPartiallyBound,
	MissingDescriptorBindingUpdateAfterBind,
	MissingUpdateAfterBindSampledImageLimit,
};

inline constexpr uint32_t hires_min_update_after_bind_sampled_images()
{
	return 4096u;
}

inline HiresDescriptorRequirement validate_hires_descriptor_support(const HiresDescriptorFeatureSupport &support)
{
	if (!support.descriptor_indexing)
		return HiresDescriptorRequirement::MissingDescriptorIndexing;
	if (!support.runtime_descriptor_array)
		return HiresDescriptorRequirement::MissingRuntimeDescriptorArray;
	if (!support.sampled_image_array_non_uniform_indexing)
		return HiresDescriptorRequirement::MissingSampledImageArrayNonUniformIndexing;
	if (!support.descriptor_binding_variable_descriptor_count)
		return HiresDescriptorRequirement::MissingDescriptorBindingVariableDescriptorCount;
	if (!support.descriptor_binding_partially_bound)
		return HiresDescriptorRequirement::MissingDescriptorBindingPartiallyBound;
	if (!support.descriptor_binding_update_after_bind)
		return HiresDescriptorRequirement::MissingDescriptorBindingUpdateAfterBind;
	return HiresDescriptorRequirement::Supported;
}

inline HiresDescriptorRequirement validate_hires_descriptor_support(
		const HiresDescriptorFeatureSupport &support,
		uint32_t max_update_after_bind_sampled_images)
{
	const auto feature_requirement = validate_hires_descriptor_support(support);
	if (feature_requirement != HiresDescriptorRequirement::Supported)
		return feature_requirement;

	if (max_update_after_bind_sampled_images < hires_min_update_after_bind_sampled_images())
		return HiresDescriptorRequirement::MissingUpdateAfterBindSampledImageLimit;

	return HiresDescriptorRequirement::Supported;
}

inline const char *describe_hires_descriptor_requirement(HiresDescriptorRequirement requirement)
{
	switch (requirement)
	{
	case HiresDescriptorRequirement::Supported:
		return "supported";
	case HiresDescriptorRequirement::MissingDescriptorIndexing:
		return "descriptor indexing is unavailable";
	case HiresDescriptorRequirement::MissingRuntimeDescriptorArray:
		return "runtime descriptor array is unavailable";
	case HiresDescriptorRequirement::MissingSampledImageArrayNonUniformIndexing:
		return "sampled-image non-uniform indexing is unavailable";
	case HiresDescriptorRequirement::MissingDescriptorBindingVariableDescriptorCount:
		return "descriptor binding variable descriptor count is unavailable";
	case HiresDescriptorRequirement::MissingDescriptorBindingPartiallyBound:
		return "descriptor binding partially-bound is unavailable";
	case HiresDescriptorRequirement::MissingDescriptorBindingUpdateAfterBind:
		return "descriptor binding update-after-bind is unavailable";
	case HiresDescriptorRequirement::MissingUpdateAfterBindSampledImageLimit:
		return "maxDescriptorSetUpdateAfterBindSampledImages is below required minimum";
	}

	return "unknown requirement";
}

inline bool should_enable_hires_after_capability_check(bool requested,
                                                       HiresDescriptorRequirement requirement)
{
	return requested && requirement == HiresDescriptorRequirement::Supported;
}
}
}
