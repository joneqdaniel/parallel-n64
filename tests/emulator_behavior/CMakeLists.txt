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
