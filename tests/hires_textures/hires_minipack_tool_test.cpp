#include "texture_replacement.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <sys/wait.h>
#include <unistd.h>
#include <vector>

using namespace RDP;

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

static std::string shell_quote(const std::filesystem::path &path)
{
	const std::string in = path.string();
	std::string out;
	out.reserve(in.size() + 2);
	out.push_back('"');
	for (char c : in)
	{
		if (c == '\\' || c == '"' || c == '$' || c == '`')
			out.push_back('\\');
		out.push_back(c);
	}
	out.push_back('"');
	return out;
}

static int run_command(const std::string &command)
{
	const int rc = std::system(command.c_str());
	if (rc < 0)
		return rc;
#ifdef WIFEXITED
	if (WIFEXITED(rc))
		return WEXITSTATUS(rc);
#endif
	return rc;
}
}

int main()
{
	const auto source_root = std::filesystem::path(PARALLEL_N64_SOURCE_DIR);
	const auto script = source_root / "tools" / "hires_minipack.py";
	check(std::filesystem::exists(script), "missing tools/hires_minipack.py");

	const auto temp_root = std::filesystem::temp_directory_path();
	const auto test_dir = temp_root / ("parallel_n64_hires_minipack_tool_" + std::to_string(getpid()));
	std::filesystem::remove_all(test_dir);
	std::filesystem::create_directories(test_dir);

	const auto keys_csv = test_dir / "keys.csv";
	const auto out_dir = test_dir / "cache";
	{
		std::ofstream fp(keys_csv);
		check(fp.good(), "failed to create keys.csv fixture");
		fp << "checksum64,formatsize,orig_w,orig_h\n";
		fp << "0x1122334455667788,0x0032,8,8\n";
		fp << "0x8877665544332211,0x0000,4,2\n";
	}

	const std::string gen_cmd =
	    "python3 " + shell_quote(script) + " from-keys --keys " + shell_quote(keys_csv) +
	    " --out-dir " + shell_quote(out_dir) +
	    " --name TESTPACK --emit hts,htc --scale 2 --compress zlib";
	check(run_command(gen_cmd) == 0, "hires_minipack from-keys command failed");

	check(std::filesystem::exists(out_dir / "TESTPACK.hts"), "generated .hts is missing");
	check(std::filesystem::exists(out_dir / "TESTPACK.htc"), "generated .htc is missing");
	check(std::filesystem::exists(out_dir / "TESTPACK_manifest.json"), "generated manifest is missing");

	const std::string validate_cmd =
	    "python3 " + shell_quote(script) + " validate --path " + shell_quote(out_dir);
	check(run_command(validate_cmd) == 0, "hires_minipack validate command failed");

	const auto manifest_path = out_dir / "TESTPACK_manifest.json";
	const std::string manifest = [] (const std::filesystem::path &path) {
		std::ifstream fp(path);
		return std::string((std::istreambuf_iterator<char>(fp)), std::istreambuf_iterator<char>());
	}(manifest_path);
	check(manifest.find("\"entry_count\": 2") != std::string::npos, "manifest entry_count mismatch");
	check(manifest.find("0x1122334455667788") != std::string::npos, "manifest missing key checksum");

	ReplacementProvider provider;
	provider.set_enabled(true);
	check(provider.load_cache_dir(out_dir.string()), "provider failed to load generated minipack");
	check(provider.entry_count() >= 4, "provider entry count mismatch for emitted hts+htc");

	ReplacementImage image_exact = {};
	check(provider.decode_rgba8(0x1122334455667788ull, 0x0032, &image_exact),
	      "decode failed for exact formatsize key");
	check(image_exact.meta.repl_w == 16 && image_exact.meta.repl_h == 16,
	      "decoded dimensions mismatch for exact formatsize key");
	check(image_exact.rgba8.size() == size_t(16 * 16 * 4),
	      "decoded pixel payload size mismatch for exact formatsize key");

	ReplacementImage image_wildcard = {};
	check(provider.decode_rgba8(0x8877665544332211ull, 0x1234, &image_wildcard),
	      "wildcard formatsize decode failed");
	check(image_wildcard.meta.repl_w == 8 && image_wildcard.meta.repl_h == 4,
	      "decoded dimensions mismatch for wildcard key");
	check(!image_wildcard.rgba8.empty(), "wildcard decode payload is empty");

	bool saw_nonzero = false;
	for (uint8_t byte : image_exact.rgba8)
	{
		if (byte != 0)
		{
			saw_nonzero = true;
			break;
		}
	}
	check(saw_nonzero, "generated texture unexpectedly all zeros");

	std::filesystem::remove_all(test_dir);
	std::cout << "hires_minipack_tool_test: PASS (entries=" << provider.entry_count() << ")" << std::endl;
	return 0;
}
