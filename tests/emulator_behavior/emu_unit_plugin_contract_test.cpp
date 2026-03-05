#include <libretro.h>
#include <libretro_vulkan.h>

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>

#define PARALLEL_RDP_HPP
namespace RDP
{
extern const struct retro_hw_render_interface_vulkan *vulkan;
extern unsigned width;
extern unsigned height;
extern unsigned upscaling;
extern unsigned downscaling_steps;
extern unsigned overscan;
extern bool synchronous;
extern bool divot_filter;
extern bool gamma_dither;
extern bool vi_aa;
extern bool vi_scale;
extern bool dither_filter;
extern bool interlacing;
extern bool native_texture_lod;
extern bool native_tex_rect;
extern bool hires_textures;
extern unsigned hires_filter;
extern unsigned hires_srgb;
extern std::string hires_cache_path;

bool init();
void deinit();
void begin_frame();
void process_commands();
void complete_frame();
void profile_refresh_begin();
void profile_refresh_end();
}

#include "mupen64plus-video-paraLLEl/parallel.cpp"

namespace
{
struct StubState
{
	bool init_result = true;
	bool last_just_flipping = false;
	unsigned init_calls = 0;
	unsigned deinit_calls = 0;
	unsigned begin_frame_calls = 0;
	unsigned process_commands_calls = 0;
	unsigned complete_frame_calls = 0;
	unsigned refresh_begin_calls = 0;
	unsigned refresh_end_calls = 0;
	unsigned retro_return_calls = 0;
};

StubState g_state;

static void reset_state()
{
	g_state = {};
	g_state.init_result = true;
}

static void check(bool condition, const char *message)
{
	if (!condition)
	{
		std::cerr << "FAIL: " << message << std::endl;
		std::exit(1);
	}
}

static void test_dll_info_contract()
{
	PLUGIN_INFO info = {};
	parallelGetDllInfo(&info);
	check(info.Version == 0x0001, "parallelGetDllInfo Version mismatch");
	check(info.Type == 2, "parallelGetDllInfo Type mismatch");
	check(std::strcmp(info.Name, "paraLLEl-RDP") == 0, "parallelGetDllInfo Name mismatch");
	check(info.NormalMemory == true, "parallelGetDllInfo NormalMemory mismatch");
	check(info.MemoryBswaped == true, "parallelGetDllInfo MemoryBswaped mismatch");
}

static void test_plugin_version_contract()
{
	m64p_plugin_type plugin_type = M64PLUGIN_NULL;
	int plugin_version = 0;
	int api_version = 0;
	const char *plugin_name = nullptr;
	int capabilities = -1;

	const m64p_error rc = parallelPluginGetVersion(&plugin_type, &plugin_version, &api_version, &plugin_name, &capabilities);
	check(rc == M64ERR_SUCCESS, "parallelPluginGetVersion should return success");
	check(plugin_type == M64PLUGIN_GFX, "parallelPluginGetVersion PluginType mismatch");
	check(plugin_version == 0x016304, "parallelPluginGetVersion PluginVersion mismatch");
	check(api_version == 0x020100, "parallelPluginGetVersion APIVersion mismatch");
	check(plugin_name != nullptr && std::strcmp(plugin_name, "paraLLEl-RDP") == 0, "parallelPluginGetVersion PluginName mismatch");
	check(capabilities == 0, "parallelPluginGetVersion Capabilities mismatch");

	check(parallelPluginGetVersion(nullptr, nullptr, nullptr, nullptr, nullptr) == M64ERR_SUCCESS,
	      "parallelPluginGetVersion should tolerate null out-params");
}

static void test_entrypoint_link_surface()
{
	// Link-time surface check. If these symbols are removed/renamed, this test will fail to build.
	check(&parallelProcessRDPList != nullptr, "missing symbol parallelProcessRDPList");
	check(&parallelUpdateScreen != nullptr, "missing symbol parallelUpdateScreen");
	check(&parallelShowCFB != nullptr, "missing symbol parallelShowCFB");
	check(&parallelRomOpen != nullptr, "missing symbol parallelRomOpen");
	check(&parallelRomClosed != nullptr, "missing symbol parallelRomClosed");
	check(&parallelGetDllInfo != nullptr, "missing symbol parallelGetDllInfo");
	check(&parallelPluginGetVersion != nullptr, "missing symbol parallelPluginGetVersion");
}

static void test_entrypoint_delegation()
{
	reset_state();
	parallelProcessRDPList();
	check(g_state.process_commands_calls == 1, "parallelProcessRDPList should delegate once");

	parallelUpdateScreen();
	check(g_state.complete_frame_calls == 1, "parallelUpdateScreen should call complete_frame");
	check(g_state.retro_return_calls == 1, "parallelUpdateScreen should call retro_return");
	check(g_state.last_just_flipping == true, "parallelUpdateScreen should pass true to retro_return");

	parallelShowCFB();
	check(g_state.complete_frame_calls == 2, "parallelShowCFB should call complete_frame via update");
	check(g_state.retro_return_calls == 2, "parallelShowCFB should call retro_return via update");

	check(parallelRomOpen() == 1, "parallelRomOpen should return 1");
	parallelRomClosed();
}

static void test_init_deinit_contract()
{
	reset_state();
	retro_hw_render_interface_vulkan vk = {};

	g_state.init_result = false;
	check(parallel_init(&vk) == false, "parallel_init should return RDP::init result (false)");
	check(g_state.init_calls == 1, "parallel_init should call RDP::init once");
	check(RDP::vulkan == &vk, "parallel_init should set RDP::vulkan pointer");

	g_state.init_result = true;
	check(parallel_init(&vk) == true, "parallel_init should return RDP::init result (true)");
	check(g_state.init_calls == 2, "parallel_init should call RDP::init for each invocation");

	RDP::width = 640;
	RDP::height = 480;
	check(parallel_frame_width() == 640, "parallel_frame_width mismatch");
	check(parallel_frame_height() == 480, "parallel_frame_height mismatch");
	check(parallel_frame_is_valid() == true, "parallel_frame_is_valid should remain true");

	parallel_begin_frame();
	check(g_state.begin_frame_calls == 1, "parallel_begin_frame should delegate once");

	parallel_deinit();
	check(g_state.deinit_calls == 1, "parallel_deinit should call RDP::deinit once");
	check(RDP::vulkan == nullptr, "parallel_deinit should clear RDP::vulkan pointer");
}
}

namespace RDP
{
const struct retro_hw_render_interface_vulkan *vulkan = nullptr;
unsigned width = 0;
unsigned height = 0;
unsigned upscaling = 1;
unsigned downscaling_steps = 0;
unsigned overscan = 0;
bool synchronous = false;
bool divot_filter = false;
bool gamma_dither = false;
bool vi_aa = false;
bool vi_scale = false;
bool dither_filter = false;
bool interlacing = false;
bool native_texture_lod = false;
bool native_tex_rect = true;
bool hires_textures = false;
unsigned hires_filter = 1;
unsigned hires_srgb = 0;
std::string hires_cache_path;

bool init()
{
	g_state.init_calls++;
	return g_state.init_result;
}

void deinit()
{
	g_state.deinit_calls++;
}

void begin_frame()
{
	g_state.begin_frame_calls++;
}

void process_commands()
{
	g_state.process_commands_calls++;
}

void complete_frame()
{
	g_state.complete_frame_calls++;
}

void profile_refresh_begin()
{
	g_state.refresh_begin_calls++;
}

void profile_refresh_end()
{
	g_state.refresh_end_calls++;
}
}

extern "C" int retro_return(bool just_flipping)
{
	g_state.retro_return_calls++;
	g_state.last_just_flipping = just_flipping;
	return 0;
}

int main()
{
	test_dll_info_contract();
	test_plugin_version_contract();
	test_entrypoint_link_surface();
	test_entrypoint_delegation();
	test_init_deinit_contract();
	std::cout << "emu_unit_plugin_contract_test: PASS" << std::endl;
	return 0;
}
