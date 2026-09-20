#pragma once

#include "FocusGate.h"

#include <atomic>
#include <condition_variable>
#include <functional>
#include <mutex>
#include <optional>
#include <string>
#include <thread>

namespace msime::windows
{
// Performs the optional cloud-candidate request away from the input queue.
// The query is copied from the shared host and the completion carries only a
// bounded response body back to the owner for session-thread application.
class CloudCandidateWorker final
{
  public:
    struct Result
    {
        FocusLease lease;
        std::string query;
        std::string body;
    };
    using Completed = std::function<void(Result)>;
    // Performs one request. `cancelled` answers true once this request has been
    // superseded or the worker is stopping, and is polled during the transfer
    // so a superseded request stops paying for itself. Injected so the queueing
    // above it can be exercised without a network: what goes wrong here is
    // ordering, not HTTP.
    using Fetcher =
        std::function<std::string(const std::string &, const std::function<bool()> &)>;

    explicit CloudCandidateWorker(Completed completed);
    CloudCandidateWorker(Completed completed, Fetcher fetcher);
    ~CloudCandidateWorker();
    CloudCandidateWorker(const CloudCandidateWorker &) = delete;
    CloudCandidateWorker &operator=(const CloudCandidateWorker &) = delete;

    // Keeps only the newest request. The caller must be outside the worker's
    // network operation; this function never waits for a response.
    bool submit(const FocusLease &lease, std::string query);
    void request_stop();
    void stop();

  private:
    struct Request
    {
        FocusLease lease;
        std::string query;
        uint64_t serial = 0;
    };

    void run() noexcept;
    bool cancelled(uint64_t serial) const noexcept;
    static std::string fetch(const std::string &query,
                             const std::function<bool()> &cancelled);

    Completed completed_;
    Fetcher fetch_;
    mutable std::mutex mutex_;
    std::condition_variable wake_;
    std::optional<Request> pending_;
    uint64_t next_serial_ = 0;
    std::atomic<uint64_t> latest_serial_{0};
    std::atomic<bool> stopping_{false};
    std::mutex join_mutex_;
    std::thread worker_;
};
} // namespace msime::windows
