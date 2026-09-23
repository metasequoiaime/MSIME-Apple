#pragma once

// Queue one passed-through character for the Server's typing statistics. Never blocks the caller: the pipe work happens on the thread pool.
void QueuePassthroughStatistics(wchar_t wch, bool english);
