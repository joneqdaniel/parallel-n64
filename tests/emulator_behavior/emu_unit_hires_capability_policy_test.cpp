#include "mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/rdp_hires_capability_policy.hpp"

#include <cstdlib>
#include <iostream>
#include <string>

using namespace RDP::detail;

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

static HiresDescriptorFeatureSupport all_supported()
{
	HiresDescriptorFeatureSupport support = {};
	support.descriptor_indexing = true;
	support.runtime_descriptor_array = true;
	support.sampled_image_array_non_uniform_indexing = true;
	support.descriptor_binding_variable_descriptor_count = true;
	support.descriptor_binding_partially_bound = true;
	support.descriptor_binding_update_after_bind = true;
	return support;
}

static void test_validate_hires_descriptor_support_matrix()
{
	check(validate_hires_descriptor_support(all_supported()) == HiresDescriptorRequirement::Supported,
	      "all-required descriptor features should be accepted");
	check(validate_hires_descriptor_support(all_supported(),
	                                        hires_min_update_after_bind_sampled_images()) == HiresDescriptorRequirement::Supported,
	      "all-required descriptor features with required sampled-image limit should be accepted");

	{
		auto support = all_supported();
		support.descriptor_indexing = false;
		check(validate_hires_descriptor_support(support) == HiresDescriptorRequirement::MissingDescriptorIndexing,
		      "descriptor indexing missing should be reported");
	}
	{
		auto support = all_supported();
		support.runtime_descriptor_array = false;
		check(validate_hires_descriptor_support(support) == HiresDescriptorRequirement::MissingRuntimeDescriptorArray,
		      "runtime descriptor array missing should be reported");
	}
	{
		auto support = all_supported();
		support.sampled_image_array_non_uniform_indexing = false;
		check(validate_hires_descriptor_support(support) == HiresDescriptorRequirement::MissingSampledImageArrayNonUniformIndexing,
		      "sampled-image non-uniform indexing missing should be reported");
	}
	{
		auto support = all_supported();
		support.descriptor_binding_variable_descriptor_count = false;
		check(validate_hires_descriptor_support(support) == HiresDescriptorRequirement::MissingDescriptorBindingVariableDescriptorCount,
		      "variable descriptor count missing should be reported");
	}
	{
		auto support = all_supported();
		support.descriptor_binding_partially_bound = false;
		check(validate_hires_descriptor_support(support) == HiresDescriptorRequirement::MissingDescriptorBindingPartiallyBound,
		      "partially bound missing should be reported");
	}
	{
		auto support = all_supported();
		support.descriptor_binding_update_after_bind = false;
		check(validate_hires_descriptor_support(support) == HiresDescriptorRequirement::MissingDescriptorBindingUpdateAfterBind,
		      "update-after-bind missing should be reported");
	}
	{
		auto support = all_supported();
		check(validate_hires_descriptor_support(support,
		                                        hires_min_update_after_bind_sampled_images() - 1) ==
		              HiresDescriptorRequirement::MissingUpdateAfterBindSampledImageLimit,
		      "insufficient update-after-bind sampled-image limit should be reported");
	}
}

static void test_should_enable_hires_after_capability_check()
{
	check(!should_enable_hires_after_capability_check(false, HiresDescriptorRequirement::Supported),
	      "hires should stay disabled when user request is off");
	check(should_enable_hires_after_capability_check(true, HiresDescriptorRequirement::Supported),
	      "hires should enable when requested and requirements are met");
	check(!should_enable_hires_after_capability_check(true, HiresDescriptorRequirement::MissingDescriptorBindingPartiallyBound),
	      "hires should auto-disable when required descriptor features are missing");
}

static void test_describe_hires_descriptor_requirement()
{
	check(std::string(describe_hires_descriptor_requirement(HiresDescriptorRequirement::Supported)) == "supported",
	      "supported requirement text mismatch");
	check(std::string(describe_hires_descriptor_requirement(HiresDescriptorRequirement::MissingDescriptorIndexing)) ==
	              "descriptor indexing is unavailable",
	      "descriptor indexing requirement text mismatch");
	check(std::string(describe_hires_descriptor_requirement(HiresDescriptorRequirement::MissingUpdateAfterBindSampledImageLimit)) ==
	              "maxDescriptorSetUpdateAfterBindSampledImages is below required minimum",
	      "sampled-image limit requirement text mismatch");
}
}

int main()
{
	test_validate_hires_descriptor_support_matrix();
	test_should_enable_hires_after_capability_check();
	test_describe_hires_descriptor_requirement();

	std::cout << "emu_unit_hires_capability_policy_test: PASS" << std::endl;
	return 0;
}
