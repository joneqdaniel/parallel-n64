set(EMU_BEHAVIOR_SUPPORT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/support")

add_test(
  NAME emu.support.paper_mario_fixture_verification_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_paper_mario_fixture_verification_contract.sh"
)

add_test(
  NAME emu.support.paper_mario_non_menu_fixture_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_paper_mario_non_menu_fixture_contract.sh"
)

add_test(
  NAME emu.support.paper_mario_selected_package_authority_validation_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_paper_mario_selected_package_authority_validation_contract.sh"
)

add_test(
  NAME emu.support.paper_mario_phrb_authority_validation_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_paper_mario_phrb_authority_validation_contract.sh"
)

add_test(
  NAME emu.support.paper_mario_default_authority_cache_preference_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_paper_mario_default_authority_cache_preference_contract.sh"
)

add_test(
  NAME emu.support.libretro_hires_source_mode_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_libretro_hires_source_mode_contract.sh"
)

add_test(
  NAME emu.support.hires_capability_source_policy_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hires_capability_source_policy_contract.sh"
)

add_test(
  NAME emu.support.paper_mario_full_cache_phrb_authority_refresh_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_paper_mario_full_cache_phrb_authority_refresh_contract.sh"
)

add_test(
  NAME emu.support.paper_mario_full_cache_phrb_zero_config_refresh_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_paper_mario_full_cache_phrb_zero_config_refresh_contract.sh"
)

add_test(
  NAME emu.support.paper_mario_title_timeout_selected_package_validation_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_paper_mario_title_timeout_selected_package_validation_contract.sh"
)

add_test(
  NAME emu.support.hires_block_family_probe_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hires_block_family_probe_contract.sh"
)

add_test(
  NAME emu.support.hires_proxy_binding_auto_select_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hires_proxy_binding_auto_select_contract.sh"
)

add_test(
  NAME emu.support.hires_sampled_selector_review_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hires_sampled_selector_review_contract.sh"
)

add_test(
  NAME emu.support.hires_sampled_family_probe_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hires_sampled_family_probe_contract.sh"
)

add_test(
  NAME emu.support.hires_sampled_pool_stream_probe_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hires_sampled_pool_stream_probe_contract.sh"
)

add_test(
  NAME emu.support.hires_sampled_group_capture_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hires_sampled_group_capture_contract.sh"
)

add_test(
  NAME emu.support.hires_sampled_pool_review_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hires_sampled_pool_review_contract.sh"
)

add_test(
  NAME emu.support.hires_pool_regression_review_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hires_pool_regression_review_contract.sh"
)

add_test(
  NAME emu.support.hires_sampled_duplicate_probe_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hires_sampled_duplicate_probe_contract.sh"
)

add_test(
  NAME emu.support.hires_sampled_duplicate_review_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hires_sampled_duplicate_review_contract.sh"
)

add_test(
  NAME emu.support.hires_sampled_duplicate_review_multi_record_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hires_sampled_duplicate_review_multi_record_contract.sh"
)

add_test(
  NAME emu.support.hires_sampled_alias_group_review_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hires_sampled_alias_group_review_contract.sh"
)

add_test(
  NAME emu.support.hires_pack_apply_duplicate_review_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hires_pack_apply_duplicate_review_contract.sh"
)

add_test(
  NAME emu.support.hires_pack_apply_alias_group_review_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hires_pack_apply_alias_group_review_contract.sh"
)

add_test(
  NAME emu.support.hires_pack_build_selected_package_duplicate_review_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hires_pack_build_selected_package_duplicate_review_contract.sh"
)

add_test(
  NAME emu.support.hires_pack_build_selected_package_alias_group_review_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hires_pack_build_selected_package_alias_group_review_contract.sh"
)

add_test(
  NAME emu.support.hires_pack_build_selected_package_review_profile_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hires_pack_build_selected_package_review_profile_contract.sh"
)

add_test(
  NAME emu.support.hires_apply_surface_transport_policy_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hires_apply_surface_transport_policy_contract.sh"
)

add_test(
  NAME emu.support.hires_pack_build_selected_package_surface_transport_policy_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hires_pack_build_selected_package_surface_transport_policy_contract.sh"
)

add_test(
  NAME emu.support.hires_alternate_source_review_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hires_alternate_source_review_contract.sh"
)

add_test(
  NAME emu.support.hires_alternate_source_activation_review_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hires_alternate_source_activation_review_contract.sh"
)

add_test(
  NAME emu.support.hires_runtime_seam_register_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hires_runtime_seam_register_contract.sh"
)

add_test(
  NAME emu.support.hires_sampled_cross_scene_review_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hires_sampled_cross_scene_review_contract.sh"
)

add_test(
  NAME emu.support.hts2phrb_smoke
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_smoke.sh"
)

add_test(
  NAME emu.support.hts2phrb_round_trip
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_round_trip.sh"
)

add_test(
  NAME emu.support.hts2phrb_sampled_bundle_fallback
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_sampled_bundle_fallback.sh"
)

add_test(
  NAME emu.support.hts2phrb_directory_input
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_directory_input.sh"
)

add_test(
  NAME emu.support.hts2phrb_all_families
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_all_families.sh"
)

add_test(
  NAME emu.support.hts2phrb_zero_config_defaults
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_zero_config_defaults.sh"
)

add_test(
  NAME emu.support.hts2phrb_path_scoped_defaults
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_path_scoped_defaults.sh"
)

add_test(
  NAME emu.support.hts2phrb_gates
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_gates.sh"
)

add_test(
  NAME emu.support.hts2phrb_bundle_input_resolution
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_bundle_input_resolution.sh"
)

add_test(
  NAME emu.support.hts2phrb_context_bundle_merge
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_context_bundle_merge.sh"
)

add_test(
  NAME emu.support.hts2phrb_family_inventory_absorbed_variants
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_family_inventory_absorbed_variants.sh"
)

add_test(
  NAME emu.support.hts2phrb_unresolved_family_review
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_unresolved_family_review.sh"
)

add_test(
  NAME emu.support.hts2phrb_exact_scale_equivalent_collapse
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_exact_scale_equivalent_collapse.sh"
)

add_test(
  NAME emu.support.hts2phrb_canonical_family_selection_review
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_canonical_family_selection_review.sh"
)

add_test(
  NAME emu.support.hts2phrb_runtime_overlay_hash_review
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_runtime_overlay_hash_review.sh"
)

add_test(
  NAME emu.support.hts2phrb_context_bundle_generic_family_fallback
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_context_bundle_generic_family_fallback.sh"
)

add_test(
  NAME emu.support.hts2phrb_context_bundle_groups_fallback
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_context_bundle_groups_fallback.sh"
)

add_test(
  NAME emu.support.hts2phrb_context_bundle_fixture_summary
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_context_bundle_fixture_summary.sh"
)

add_test(
  NAME emu.support.hts2phrb_context_dir_discovery
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_context_dir_discovery.sh"
)

add_test(
  NAME emu.support.hts2phrb_context_bundle_provenance_hits
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_context_bundle_provenance_hits.sh"
)

add_test(
  NAME emu.support.hts2phrb_runtime_sampled_probe_family_signal
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_runtime_sampled_probe_family_signal.sh"
)

add_test(
  NAME emu.support.hts2phrb_upload_counter_normalization
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_upload_counter_normalization.sh"
)

add_test(
  NAME emu.support.hts2phrb_paper_mario_full_cache_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_paper_mario_full_cache_contract.sh"
)

add_test(
  NAME emu.support.hts2phrb_paper_mario_pre_v401_full_cache_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_paper_mario_pre_v401_full_cache_contract.sh"
)

add_test(
  NAME emu.support.hts2phrb_paper_mario_review_profile_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_paper_mario_review_profile_contract.sh"
)

add_test(
  NAME emu.support.hts2phrb_paper_mario_runtime_overlay_review_profile_contract
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_paper_mario_runtime_overlay_review_profile_contract.sh"
)

add_test(
  NAME emu.support.hts2phrb_bundle_scoped_defaults
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_bundle_scoped_defaults.sh"
)

add_test(
  NAME emu.support.hts2phrb_runtime_overlay_modes
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_runtime_overlay_modes.sh"
)

add_test(
  NAME emu.support.hts2phrb_auto_overlay_without_runtime_ready
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_auto_overlay_without_runtime_ready.sh"
)

add_test(
  NAME emu.support.hts2phrb_auto_overlay_without_deterministic_bindings
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_auto_overlay_without_deterministic_bindings.sh"
)

add_test(
  NAME emu.support.hts2phrb_reuse_existing
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_reuse_existing.sh"
)

add_test(
  NAME emu.support.hts2phrb_reuse_existing_runtime_ready_consistency
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_reuse_existing_runtime_ready_consistency.sh"
)

add_test(
  NAME emu.support.hts2phrb_reuse_existing_runtime_class_consistency
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_reuse_existing_runtime_class_consistency.sh"
)

add_test(
  NAME emu.support.hts2phrb_reuse_existing_runtime_kind_consistency
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_reuse_existing_runtime_kind_consistency.sh"
)

add_test(
  NAME emu.support.hts2phrb_reuse_existing_manifest_summary_backfill
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_reuse_existing_manifest_summary_backfill.sh"
)

add_test(
  NAME emu.support.hts2phrb_review_profile
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_review_profile.sh"
)

add_test(
  NAME emu.support.hts2phrb_review_profile_inapplicable
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_review_profile_inapplicable.sh"
)

add_test(
  NAME emu.support.hts2phrb_reuse_existing_review_inputs
  COMMAND bash "${EMU_BEHAVIOR_SUPPORT_DIR}/emu_hts2phrb_reuse_existing_review_inputs.sh"
)

add_executable(emu_unit_smoke_test
  emu_unit_smoke_test.cpp
  "${EMU_BEHAVIOR_SUPPORT_DIR}/rdp_memory_fixture.cpp"
)
target_include_directories(emu_unit_smoke_test PRIVATE
  "${EMU_BEHAVIOR_SUPPORT_DIR}"
  "${CMAKE_SOURCE_DIR}"
)
target_compile_features(emu_unit_smoke_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.smoke COMMAND emu_unit_smoke_test)

add_executable(emu_unit_seed_policy_test
  emu_unit_seed_policy_test.cpp
)
target_include_directories(emu_unit_seed_policy_test PRIVATE
  "${CMAKE_SOURCE_DIR}"
)
target_compile_features(emu_unit_seed_policy_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.seed_policy COMMAND emu_unit_seed_policy_test)

add_executable(emu_unit_texture_replacement_provider_test
  emu_unit_texture_replacement_provider_test.cpp
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/texture_replacement.cpp"
)
target_include_directories(emu_unit_texture_replacement_provider_test PRIVATE
  "${CMAKE_SOURCE_DIR}"
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp"
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/util"
)
target_compile_features(emu_unit_texture_replacement_provider_test PRIVATE cxx_std_17)
target_link_libraries(emu_unit_texture_replacement_provider_test PRIVATE z)
add_test(NAME emu.unit.texture_replacement_provider COMMAND emu_unit_texture_replacement_provider_test)

add_executable(emu_unit_hires_ci_palette_policy_test
  emu_unit_hires_ci_palette_policy_test.cpp
)
target_include_directories(emu_unit_hires_ci_palette_policy_test PRIVATE
  "${CMAKE_SOURCE_DIR}"
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp"
)
target_compile_features(emu_unit_hires_ci_palette_policy_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.hires_ci_palette_policy COMMAND emu_unit_hires_ci_palette_policy_test)


add_executable(emu_unit_rdp_command_ingest_test
  emu_unit_rdp_command_ingest_test.cpp
)
target_include_directories(emu_unit_rdp_command_ingest_test PRIVATE
  "${CMAKE_SOURCE_DIR}"
  "${CMAKE_SOURCE_DIR}/mupen64plus-core/src/api"
)
target_compile_features(emu_unit_rdp_command_ingest_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.rdp_command_ingest COMMAND emu_unit_rdp_command_ingest_test)

add_executable(emu_unit_rdp_frame_mapping_test
  emu_unit_rdp_frame_mapping_test.cpp
  "${EMU_BEHAVIOR_SUPPORT_DIR}/rdp_memory_fixture.cpp"
)
target_include_directories(emu_unit_rdp_frame_mapping_test PRIVATE
  "${EMU_BEHAVIOR_SUPPORT_DIR}"
  "${CMAKE_SOURCE_DIR}"
  "${CMAKE_SOURCE_DIR}/mupen64plus-core/src/api"
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp"
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/vulkan"
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/util"
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/volk"
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/vulkan-headers/include"
  "${CMAKE_SOURCE_DIR}/libretro-common/include"
)
target_compile_definitions(emu_unit_rdp_frame_mapping_test PRIVATE GRANITE_VULKAN_MT)
target_compile_features(emu_unit_rdp_frame_mapping_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.rdp_frame_mapping COMMAND emu_unit_rdp_frame_mapping_test)

add_library(emu_obj_rdp_renderer_compile OBJECT EXCLUDE_FROM_ALL
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp/rdp_renderer.cpp"
)
target_include_directories(emu_obj_rdp_renderer_compile PRIVATE
  "${EMU_BEHAVIOR_SUPPORT_DIR}"
  "${CMAKE_SOURCE_DIR}"
  "${CMAKE_SOURCE_DIR}/mupen64plus-core/src/api"
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp"
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/vulkan"
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/util"
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/volk"
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/vulkan-headers/include"
  "${CMAKE_SOURCE_DIR}/libretro-common/include"
)
target_compile_definitions(emu_obj_rdp_renderer_compile PRIVATE GRANITE_VULKAN_MT)
target_compile_features(emu_obj_rdp_renderer_compile PRIVATE cxx_std_17)
add_custom_target(emu_compile_rdp_renderer DEPENDS emu_obj_rdp_renderer_compile)

add_executable(emu_unit_rdp_frame_fallback_policy_test
  emu_unit_rdp_frame_fallback_policy_test.cpp
)
target_include_directories(emu_unit_rdp_frame_fallback_policy_test PRIVATE
  "${CMAKE_SOURCE_DIR}"
)
target_compile_features(emu_unit_rdp_frame_fallback_policy_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.rdp_frame_fallback_policy COMMAND emu_unit_rdp_frame_fallback_policy_test)

add_executable(emu_unit_rdp_scanout_fallback_test
  emu_unit_rdp_scanout_fallback_test.cpp
)
target_include_directories(emu_unit_rdp_scanout_fallback_test PRIVATE
  "${CMAKE_SOURCE_DIR}"
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp"
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/vulkan"
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/util"
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/volk"
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/vulkan-headers/include"
)
target_compile_definitions(emu_unit_rdp_scanout_fallback_test PRIVATE GRANITE_VULKAN_MT)
target_compile_features(emu_unit_rdp_scanout_fallback_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.rdp_scanout_fallback COMMAND emu_unit_rdp_scanout_fallback_test)

add_executable(emu_unit_rdp_init_policy_test
  emu_unit_rdp_init_policy_test.cpp
)
target_include_directories(emu_unit_rdp_init_policy_test PRIVATE
  "${CMAKE_SOURCE_DIR}"
)
target_compile_features(emu_unit_rdp_init_policy_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.rdp_init_policy COMMAND emu_unit_rdp_init_policy_test)

add_executable(emu_unit_rdp_vulkan_glue_test
  emu_unit_rdp_vulkan_glue_test.cpp
)
target_include_directories(emu_unit_rdp_vulkan_glue_test PRIVATE
  "${CMAKE_SOURCE_DIR}"
  "${CMAKE_SOURCE_DIR}/mupen64plus-core/src/api"
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/vulkan-headers/include"
  "${CMAKE_SOURCE_DIR}/libretro-common/include"
)
target_compile_features(emu_unit_rdp_vulkan_glue_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.rdp_vulkan_glue COMMAND emu_unit_rdp_vulkan_glue_test)

add_executable(emu_unit_rdp_retro_image_mapping_test
  emu_unit_rdp_retro_image_mapping_test.cpp
)
target_include_directories(emu_unit_rdp_retro_image_mapping_test PRIVATE
  "${CMAKE_SOURCE_DIR}"
  "${CMAKE_SOURCE_DIR}/mupen64plus-core/src/api"
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/vulkan-headers/include"
  "${CMAKE_SOURCE_DIR}/libretro-common/include"
)
target_compile_features(emu_unit_rdp_retro_image_mapping_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.rdp_retro_image_mapping COMMAND emu_unit_rdp_retro_image_mapping_test)


add_executable(emu_unit_z64_constants_test
  emu_unit_z64_constants_test.cpp
)
target_include_directories(emu_unit_z64_constants_test PRIVATE
  "${CMAKE_SOURCE_DIR}"
  "${CMAKE_SOURCE_DIR}/libretro-common/include"
)
target_compile_features(emu_unit_z64_constants_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.z64_constants COMMAND emu_unit_z64_constants_test)

add_executable(emu_unit_rdp_common_test
  emu_unit_rdp_common_test.cpp
)
target_include_directories(emu_unit_rdp_common_test PRIVATE
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp"
)
target_compile_features(emu_unit_rdp_common_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.rdp_common COMMAND emu_unit_rdp_common_test)

add_executable(emu_unit_rdp_device_capability_policy_test
  emu_unit_rdp_device_capability_policy_test.cpp
)
target_include_directories(emu_unit_rdp_device_capability_policy_test PRIVATE
  "${CMAKE_SOURCE_DIR}"
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/vulkan-headers/include"
)
target_compile_features(emu_unit_rdp_device_capability_policy_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.rdp_device_capability_policy COMMAND emu_unit_rdp_device_capability_policy_test)

add_executable(emu_unit_rdp_hires_cache_source_policy_test
  emu_unit_rdp_hires_cache_source_policy_test.cpp
)
target_include_directories(emu_unit_rdp_hires_cache_source_policy_test PRIVATE
  "${CMAKE_SOURCE_DIR}"
)
target_compile_features(emu_unit_rdp_hires_cache_source_policy_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.rdp_hires_cache_source_policy COMMAND emu_unit_rdp_hires_cache_source_policy_test)

add_executable(emu_unit_rdp_memory_path_policy_test
  emu_unit_rdp_memory_path_policy_test.cpp
)
target_include_directories(emu_unit_rdp_memory_path_policy_test PRIVATE
  "${CMAKE_SOURCE_DIR}"
)
target_compile_features(emu_unit_rdp_memory_path_policy_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.rdp_memory_path_policy COMMAND emu_unit_rdp_memory_path_policy_test)

add_executable(emu_unit_rdp_scanout_coherency_policy_test
  emu_unit_rdp_scanout_coherency_policy_test.cpp
)
target_include_directories(emu_unit_rdp_scanout_coherency_policy_test PRIVATE
  "${CMAKE_SOURCE_DIR}"
)
target_compile_features(emu_unit_rdp_scanout_coherency_policy_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.rdp_scanout_coherency_policy COMMAND emu_unit_rdp_scanout_coherency_policy_test)

add_executable(emu_unit_rdp_data_structures_test
  emu_unit_rdp_data_structures_test.cpp
)
target_include_directories(emu_unit_rdp_data_structures_test PRIVATE
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp"
)
target_compile_features(emu_unit_rdp_data_structures_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.rdp_data_structures COMMAND emu_unit_rdp_data_structures_test)

add_executable(emu_unit_rdp_triangle_setup_policy_test
  emu_unit_rdp_triangle_setup_policy_test.cpp
)
target_include_directories(emu_unit_rdp_triangle_setup_policy_test PRIVATE
  "${CMAKE_SOURCE_DIR}"
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp"
)
target_compile_features(emu_unit_rdp_triangle_setup_policy_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.rdp_triangle_setup_policy COMMAND emu_unit_rdp_triangle_setup_policy_test)

add_executable(emu_unit_rdp_other_modes_policy_test
  emu_unit_rdp_other_modes_policy_test.cpp
)
target_include_directories(emu_unit_rdp_other_modes_policy_test PRIVATE
  "${CMAKE_SOURCE_DIR}"
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp"
)
target_compile_features(emu_unit_rdp_other_modes_policy_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.rdp_other_modes_policy COMMAND emu_unit_rdp_other_modes_policy_test)

add_executable(emu_unit_rdp_scissor_policy_test
  emu_unit_rdp_scissor_policy_test.cpp
)
target_include_directories(emu_unit_rdp_scissor_policy_test PRIVATE
  "${CMAKE_SOURCE_DIR}"
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp"
)
target_compile_features(emu_unit_rdp_scissor_policy_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.rdp_scissor_policy COMMAND emu_unit_rdp_scissor_policy_test)

add_executable(emu_unit_rdp_rect_setup_policy_test
  emu_unit_rdp_rect_setup_policy_test.cpp
)
target_include_directories(emu_unit_rdp_rect_setup_policy_test PRIVATE
  "${CMAKE_SOURCE_DIR}"
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp"
)
target_compile_features(emu_unit_rdp_rect_setup_policy_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.rdp_rect_setup_policy COMMAND emu_unit_rdp_rect_setup_policy_test)

add_executable(emu_unit_rdp_tex_rect_policy_test
  emu_unit_rdp_tex_rect_policy_test.cpp
)
target_include_directories(emu_unit_rdp_tex_rect_policy_test PRIVATE
  "${CMAKE_SOURCE_DIR}"
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp"
)
target_compile_features(emu_unit_rdp_tex_rect_policy_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.rdp_tex_rect_policy COMMAND emu_unit_rdp_tex_rect_policy_test)

add_executable(emu_unit_command_ring_policy_test
  emu_unit_command_ring_policy_test.cpp
)
target_include_directories(emu_unit_command_ring_policy_test PRIVATE
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp"
)
target_compile_features(emu_unit_command_ring_policy_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.command_ring_policy COMMAND emu_unit_command_ring_policy_test)

add_executable(emu_unit_luts_hash_test
  emu_unit_luts_hash_test.cpp
)
target_include_directories(emu_unit_luts_hash_test PRIVATE
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp"
)
target_compile_features(emu_unit_luts_hash_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.luts_hash COMMAND emu_unit_luts_hash_test)

add_executable(emu_unit_worker_thread_test
  emu_unit_worker_thread_test.cpp
)
target_include_directories(emu_unit_worker_thread_test PRIVATE
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp"
)
target_compile_features(emu_unit_worker_thread_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.worker_thread COMMAND emu_unit_worker_thread_test)

add_executable(emu_conformance_vi_register_contract_test
  emu_conformance_vi_register_contract_test.cpp
)
target_include_directories(emu_conformance_vi_register_contract_test PRIVATE
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp"
)
target_compile_features(emu_conformance_vi_register_contract_test PRIVATE cxx_std_17)
add_test(NAME emu.conformance.vi_register_contract COMMAND emu_conformance_vi_register_contract_test)

add_executable(emu_conformance_vi_scanout_range_test
  emu_conformance_vi_scanout_range_test.cpp
)
target_include_directories(emu_conformance_vi_scanout_range_test PRIVATE
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp"
)
target_compile_features(emu_conformance_vi_scanout_range_test PRIVATE cxx_std_17)
add_test(NAME emu.conformance.vi_scanout_range COMMAND emu_conformance_vi_scanout_range_test)

add_executable(emu_conformance_vi_scaling_crop_test
  emu_conformance_vi_scaling_crop_test.cpp
)
target_include_directories(emu_conformance_vi_scaling_crop_test PRIVATE
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp"
)
target_compile_features(emu_conformance_vi_scaling_crop_test PRIVATE cxx_std_17)
add_test(NAME emu.conformance.vi_scaling_crop COMMAND emu_conformance_vi_scaling_crop_test)

add_executable(emu_unit_vi_register_interaction_matrix_test
  emu_unit_vi_register_interaction_matrix_test.cpp
)
target_include_directories(emu_unit_vi_register_interaction_matrix_test PRIVATE
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp"
)
target_compile_features(emu_unit_vi_register_interaction_matrix_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.vi_register_interaction_matrix COMMAND emu_unit_vi_register_interaction_matrix_test)

add_executable(emu_unit_vi_scale_policy_test
  emu_unit_vi_scale_policy_test.cpp
)
target_include_directories(emu_unit_vi_scale_policy_test PRIVATE
  "${CMAKE_SOURCE_DIR}"
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp"
)
target_compile_features(emu_unit_vi_scale_policy_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.vi_scale_policy COMMAND emu_unit_vi_scale_policy_test)

add_executable(emu_conformance_rdp_command_fields_test
  emu_conformance_rdp_command_fields_test.cpp
)
target_include_directories(emu_conformance_rdp_command_fields_test PRIVATE
  "${CMAKE_SOURCE_DIR}"
  "${CMAKE_SOURCE_DIR}/libretro-common/include"
)
target_compile_features(emu_conformance_rdp_command_fields_test PRIVATE cxx_std_17)
add_test(NAME emu.conformance.rdp_command_fields COMMAND emu_conformance_rdp_command_fields_test)

add_executable(emu_conformance_rdp_command_lengths_test
  emu_conformance_rdp_command_lengths_test.cpp
)
target_include_directories(emu_conformance_rdp_command_lengths_test PRIVATE
  "${CMAKE_SOURCE_DIR}"
  "${CMAKE_SOURCE_DIR}/libretro-common/include"
)
target_compile_features(emu_conformance_rdp_command_lengths_test PRIVATE cxx_std_17)
add_test(NAME emu.conformance.rdp_command_lengths COMMAND emu_conformance_rdp_command_lengths_test)

add_executable(emu_conformance_rdp_texture_load_sequence_test
  emu_conformance_rdp_texture_load_sequence_test.cpp
)
target_include_directories(emu_conformance_rdp_texture_load_sequence_test PRIVATE
  "${CMAKE_SOURCE_DIR}"
  "${CMAKE_SOURCE_DIR}/libretro-common/include"
)
target_compile_features(emu_conformance_rdp_texture_load_sequence_test PRIVATE cxx_std_17)
add_test(NAME emu.conformance.rdp_texture_load_sequence COMMAND emu_conformance_rdp_texture_load_sequence_test)

add_test(
  NAME emu.conformance.runtime_smoke_lavapipe
  COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/support/emu_conformance_runtime_smoke.sh"
)
set_tests_properties(emu.conformance.runtime_smoke_lavapipe PROPERTIES SKIP_RETURN_CODE 77)

add_test(
  NAME emu.conformance.lavapipe_frame_hash
  COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/support/emu_conformance_lavapipe_frame_hash.sh"
)
set_tests_properties(emu.conformance.lavapipe_frame_hash PROPERTIES SKIP_RETURN_CODE 77)

add_test(
  NAME emu.conformance.lavapipe_vi_filters_hash
  COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/support/emu_conformance_lavapipe_vi_filters_hash.sh"
)
set_tests_properties(emu.conformance.lavapipe_vi_filters_hash PROPERTIES SKIP_RETURN_CODE 77)

add_test(
  NAME emu.conformance.lavapipe_vi_filters_mixed_hash
  COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/support/emu_conformance_lavapipe_vi_filters_mixed_hash.sh"
)
set_tests_properties(emu.conformance.lavapipe_vi_filters_mixed_hash PROPERTIES SKIP_RETURN_CODE 77)

add_test(
  NAME emu.conformance.lavapipe_vi_downscale_hash
  COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/support/emu_conformance_lavapipe_vi_downscale_hash.sh"
)
set_tests_properties(emu.conformance.lavapipe_vi_downscale_hash PROPERTIES SKIP_RETURN_CODE 77)

add_test(
  NAME emu.conformance.lavapipe_sm64_frame_hash
  COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/support/emu_conformance_lavapipe_sm64_frame_hash.sh"
)
set_tests_properties(emu.conformance.lavapipe_sm64_frame_hash PROPERTIES SKIP_RETURN_CODE 77)

add_test(
  NAME emu.conformance.paper_mario_selected_package_authorities
  COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/support/emu_conformance_paper_mario_selected_package_authorities.sh"
)
set_tests_properties(emu.conformance.paper_mario_selected_package_authorities PROPERTIES SKIP_RETURN_CODE 77)

add_test(
  NAME emu.conformance.paper_mario_full_cache_phrb_authorities
  COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/support/emu_conformance_paper_mario_full_cache_phrb_authorities.sh"
)
set_tests_properties(emu.conformance.paper_mario_full_cache_phrb_authorities PROPERTIES SKIP_RETURN_CODE 77)

add_test(
  NAME emu.conformance.paper_mario_full_cache_phrb_authorities_refresh
  COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/support/emu_conformance_paper_mario_full_cache_phrb_authorities_refresh.sh"
)
set_tests_properties(emu.conformance.paper_mario_full_cache_phrb_authorities_refresh PROPERTIES SKIP_RETURN_CODE 77)

add_test(
  NAME emu.conformance.paper_mario_full_cache_phrb_authorities_zero_config_refresh
  COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/support/emu_conformance_paper_mario_full_cache_phrb_authorities_zero_config_refresh.sh"
)
set_tests_properties(emu.conformance.paper_mario_full_cache_phrb_authorities_zero_config_refresh PROPERTIES SKIP_RETURN_CODE 77)

add_test(
  NAME emu.conformance.paper_mario_selected_package_timeout_validation
  COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/support/emu_conformance_paper_mario_selected_package_timeout_validation.sh"
)
set_tests_properties(emu.conformance.paper_mario_selected_package_timeout_validation PROPERTIES SKIP_RETURN_CODE 77)

add_test(
  NAME emu.conformance.paper_mario_selected_package_timeout_lookup_without_probe
  COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/support/emu_conformance_paper_mario_selected_package_timeout_lookup_without_probe.sh"
)
set_tests_properties(emu.conformance.paper_mario_selected_package_timeout_lookup_without_probe PROPERTIES SKIP_RETURN_CODE 77)

add_test(
  NAME emu.conformance.sm64_hires_boot
  COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/support/emu_conformance_sm64_hires_boot.sh"
)
set_tests_properties(emu.conformance.sm64_hires_boot PROPERTIES SKIP_RETURN_CODE 77)

add_test(
  NAME emu.conformance.oot_hires_boot
  COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/support/emu_conformance_oot_hires_boot.sh"
)
set_tests_properties(emu.conformance.oot_hires_boot PROPERTIES SKIP_RETURN_CODE 77)

add_test(
  NAME emu.unit.test_runner_profile_contract
  COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/support/emu_test_runner_profile_contract.sh"
)

add_test(
  NAME emu.unit.dump_runner_contract
  COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/support/emu_dump_runner_contract.sh"
)

add_test(
  NAME emu.unit.build_runner_contract
  COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/support/emu_build_runner_contract.sh"
)

add_test(
  NAME emu.unit.run_n64_contract
  COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/support/emu_run_n64_contract.sh"
)

add_test(
  NAME emu.dump.validate
  COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/support/emu_dump_validate.sh" normal
)
set_tests_properties(emu.dump.validate PROPERTIES SKIP_RETURN_CODE 77)

add_test(
  NAME emu.dump.validate_sync_only
  COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/support/emu_dump_validate.sh" sync-only
)
set_tests_properties(emu.dump.validate_sync_only PROPERTIES SKIP_RETURN_CODE 77)

add_test(
  NAME emu.dump.manifest
  COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/support/emu_dump_manifest_check.sh"
)
set_tests_properties(emu.dump.manifest PROPERTIES SKIP_RETURN_CODE 77)
