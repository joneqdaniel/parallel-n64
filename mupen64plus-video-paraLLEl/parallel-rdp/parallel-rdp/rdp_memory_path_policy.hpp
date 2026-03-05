#pragma once

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

namespace RDP::detail
{
struct RDRAMMemoryPathDecision
{
	bool use_external_host_import = false;
	bool fallback_to_device_buffer = false;
	bool host_coherent = true;
	size_t effective_rdram_offset = 0;
	size_t imported_size = 0;
};

inline bool allow_external_host_from_env(const char *allow_external_host_env)
{
	return allow_external_host_env ? (strtol(allow_external_host_env, nullptr, 0) > 0) : true;
}

inline size_t align_imported_host_size(size_t rdram_size, size_t rdram_offset, size_t alignment)
{
	size_t import_size = rdram_size + rdram_offset;
	if (alignment == 0)
		return import_size;
	return (import_size + alignment - 1) & ~(alignment - 1);
}

inline RDRAMMemoryPathDecision decide_rdram_memory_path(bool has_rdram_ptr,
                                                         bool supports_external_memory_host,
                                                         size_t rdram_size,
                                                         size_t rdram_offset,
                                                         size_t min_import_alignment,
                                                         const char *allow_external_host_env)
{
	RDRAMMemoryPathDecision decision = {};
	decision.host_coherent = true;
	decision.effective_rdram_offset = rdram_offset;
	decision.imported_size = rdram_size;

	if (!has_rdram_ptr)
		return decision;

	const bool allow_memory_host = allow_external_host_from_env(allow_external_host_env);
	decision.use_external_host_import = allow_memory_host && supports_external_memory_host;

	if (decision.use_external_host_import)
	{
		decision.imported_size = align_imported_host_size(rdram_size, rdram_offset, min_import_alignment);
	}
	else
	{
		decision.fallback_to_device_buffer = true;
		decision.host_coherent = false;
		decision.effective_rdram_offset = 0;
	}

	return decision;
}
}
