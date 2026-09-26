#include "PassthroughStatisticsQueue.h"

#include "Globals.h"
#include "Ipc.h"
#include "../../common/AuxMessage.h"

#include <atomic>
#include <string>
#include <windows.h>

namespace
{
SRWLOCK g_queueLock = SRWLOCK_INIT;
std::wstring g_english;
std::wstring g_chinese;
bool g_flushInFlight = false;
std::atomic<ULONGLONG> g_suppressedUntil{0};

// Bounds the memory a stalled Server can make this process hold; anything past it is a dropped count.
constexpr std::size_t MaximumPendingCharacters = 1024;
// The Server answers "OK" only while statistics are enabled. Statistics ship disabled, so without this every English keystroke would cost a pipe round trip to be told no; after an unanswered batch the queue stays closed this long, which is also how soon turning statistics on starts counting passthrough keys.
constexpr ULONGLONG SuppressionMilliseconds = 30000;

bool SendBatch(bool english, const std::wstring &characters)
{
    for (const auto &message : msime::windows::aux_typing_statistics_messages(english, characters))
    {
        if (!SendToAuxNamedpipe(message, true))
        {
            return false;
        }
    }
    return true;
}

void CALLBACK FlushPassthroughStatistics(PTP_CALLBACK_INSTANCE instance, void *context)
{
    // Drops the submit-time loader reference only after this callback has returned.
    FreeLibraryWhenCallbackReturns(instance, static_cast<HMODULE>(context));
    for (;;)
    {
        std::wstring english;
        std::wstring chinese;
        AcquireSRWLockExclusive(&g_queueLock);
        english.swap(g_english);
        chinese.swap(g_chinese);
        if (english.empty() && chinese.empty())
        {
            // Cleared under the lock so a character queued after this point submits a new flush.
            g_flushInFlight = false;
            ReleaseSRWLockExclusive(&g_queueLock);
            break;
        }
        ReleaseSRWLockExclusive(&g_queueLock);
        if (!SendBatch(true, english) || !SendBatch(false, chinese))
        {
            g_suppressedUntil.store(GetTickCount64() + SuppressionMilliseconds, std::memory_order_relaxed);
        }
    }
}
} // namespace

void QueuePassthroughStatistics(wchar_t wch, bool english)
{
    if (GetTickCount64() < g_suppressedUntil.load(std::memory_order_relaxed))
    {
        return;
    }
    AcquireSRWLockExclusive(&g_queueLock);
    if (g_english.size() + g_chinese.size() < MaximumPendingCharacters)
    {
        (english ? g_english : g_chinese).push_back(wch);
    }
    if (!g_flushInFlight)
    {
        // In-memory enqueue plus one thread-pool submission; a running flush keeps the flag set until it has drained the queue. A loader reference (not the COM lock count, which DllCanUnloadNow reads) keeps the DLL mapped while the callback runs.
        HMODULE module = nullptr;
        if (GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,
                               reinterpret_cast<LPCWSTR>(&FlushPassthroughStatistics), &module))
        {
            g_flushInFlight = true;
            if (!TrySubmitThreadpoolCallback(FlushPassthroughStatistics, module, nullptr))
            {
                g_flushInFlight = false;
                FreeLibrary(module);
            }
        }
    }
    ReleaseSRWLockExclusive(&g_queueLock);
}
