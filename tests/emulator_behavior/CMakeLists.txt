set(EMU_BEHAVIOR_SUPPORT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/support")

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

add_executable(emu_unit_plugin_contract_test
  emu_unit_plugin_contract_test.cpp
)
target_include_directories(emu_unit_plugin_contract_test PRIVATE
  "${CMAKE_SOURCE_DIR}"
  "${CMAKE_SOURCE_DIR}/mupen64plus-core/src/api"
  "${CMAKE_SOURCE_DIR}/libretro-common/include"
)
target_compile_features(emu_unit_plugin_contract_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.plugin_contract COMMAND emu_unit_plugin_contract_test)

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

add_executable(emu_unit_parallel_option_wiring_test
  emu_unit_parallel_option_wiring_test.cpp
)
target_include_directories(emu_unit_parallel_option_wiring_test PRIVATE
  "${CMAKE_SOURCE_DIR}"
  "${CMAKE_SOURCE_DIR}/mupen64plus-core/src/api"
  "${CMAKE_SOURCE_DIR}/libretro-common/include"
)
target_compile_features(emu_unit_parallel_option_wiring_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.parallel_option_wiring COMMAND emu_unit_parallel_option_wiring_test)

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

add_executable(emu_unit_rdp_data_structures_test
  emu_unit_rdp_data_structures_test.cpp
)
target_include_directories(emu_unit_rdp_data_structures_test PRIVATE
  "${CMAKE_SOURCE_DIR}/mupen64plus-video-paraLLEl/parallel-rdp/parallel-rdp"
)
target_compile_features(emu_unit_rdp_data_structures_test PRIVATE cxx_std_17)
add_test(NAME emu.unit.rdp_data_structures COMMAND emu_unit_rdp_data_structures_test)

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
  NAME emu.dump.validate
  COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/support/emu_dump_validate.sh" normal
)
set_tests_properties(emu.dump.validate PROPERTIES SKIP_RETURN_CODE 77)

add_test(
  NAME emu.dump.validate_sync_only
  COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/support/emu_dump_validate.sh" sync-only
)
set_tests_properties(emu.dump.validate_sync_only PROPERTIES SKIP_RETURN_CODE 77)
