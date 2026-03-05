#pragma once

#include <cstdint>
#include <cstring>
#include <vector>

namespace EmuBehaviorTest
{
struct EnqueueRecord
{
	unsigned words = 0;
	std::vector<uint32_t> payload;
};

struct ViWriteRecord
{
	unsigned reg = 0;
	uint32_t value = 0;
};

class FakeCommandProcessor
{
public:
	void enqueue_command(unsigned num_words, const uint32_t *words)
	{
		enqueue_calls++;
		EnqueueRecord rec = {};
		rec.words = num_words;
		if (words && num_words)
			rec.payload.assign(words, words + num_words);
		enqueues.push_back(rec);
	}

	uint64_t signal_timeline()
	{
		signal_calls++;
		last_timeline = ++next_timeline;
		return last_timeline;
	}

	void wait_for_timeline(uint64_t timeline)
	{
		wait_calls++;
		last_waited_timeline = timeline;
	}

	void set_vi_register(unsigned reg, uint32_t value)
	{
		vi_writes.push_back({reg, value});
	}

	void begin_frame_context()
	{
		begin_frame_calls++;
	}

	unsigned enqueue_calls = 0;
	unsigned signal_calls = 0;
	unsigned wait_calls = 0;
	unsigned begin_frame_calls = 0;
	uint64_t last_timeline = 0;
	uint64_t last_waited_timeline = 0;
	std::vector<EnqueueRecord> enqueues;
	std::vector<ViWriteRecord> vi_writes;

private:
	uint64_t next_timeline = 0;
};

class FakeVulkanFrontend
{
public:
	unsigned get_sync_index_mask() const
	{
		return sync_mask;
	}

	void wait_sync_index()
	{
		wait_sync_calls++;
	}

	unsigned get_sync_index() const
	{
		return sync_index;
	}

	void set_image()
	{
		set_image_calls++;
	}

	void lock_queue()
	{
		lock_calls++;
	}

	void unlock_queue()
	{
		unlock_calls++;
	}

	unsigned sync_mask = 0x1;
	unsigned sync_index = 0;
	unsigned wait_sync_calls = 0;
	unsigned set_image_calls = 0;
	unsigned lock_calls = 0;
	unsigned unlock_calls = 0;
};

class FakeDeviceBackend
{
public:
	void init_frame_contexts(unsigned count)
	{
		init_frame_context_calls++;
		last_frame_context_count = count;
	}

	uint64_t write_calibrated_timestamp()
	{
		write_timestamp_calls++;
		return ++next_timestamp;
	}

	void register_time_interval(const char *tag, uint64_t begin, uint64_t end, const char *domain)
	{
		register_interval_calls++;
		last_tag = tag ? tag : "";
		last_domain = domain ? domain : "";
		last_begin = begin;
		last_end = end;
	}

	void flush_frame()
	{
		flush_frame_calls++;
	}

	void next_frame_context()
	{
		next_frame_context_calls++;
	}

	unsigned init_frame_context_calls = 0;
	unsigned last_frame_context_count = 0;
	unsigned write_timestamp_calls = 0;
	unsigned register_interval_calls = 0;
	unsigned flush_frame_calls = 0;
	unsigned next_frame_context_calls = 0;
	uint64_t last_begin = 0;
	uint64_t last_end = 0;
	const char *last_tag = "";
	const char *last_domain = "";

private:
	uint64_t next_timestamp = 0;
};
}
