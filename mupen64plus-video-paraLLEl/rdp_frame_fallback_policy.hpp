#ifndef PARALLEL_RDP_FRAME_FALLBACK_POLICY_HPP
#define PARALLEL_RDP_FRAME_FALLBACK_POLICY_HPP

namespace RDP
{
namespace detail
{
template <typename CompleteFrameErrorFn, typename NextFrameContextFn>
inline bool handle_complete_frame_fallback(bool frontend_available,
                                           bool device_available,
                                           CompleteFrameErrorFn &&complete_frame_error,
                                           NextFrameContextFn &&next_frame_context)
{
	if (frontend_available)
		return false;

	if (!device_available)
		return true;

	complete_frame_error();
	next_frame_context();
	return true;
}
}
}

#endif
