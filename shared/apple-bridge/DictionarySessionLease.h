#pragma once
#import <Foundation/Foundation.h>
#include <functional>

namespace metasequoia::apple
{
// Each live keyboard bridge holds a shared lease, including idle sessions.
// Publication requires the sole remaining lease. A second gate serializes
// upgrades so a failed non-atomic flock conversion can safely restore sharing.
class DictionarySessionLease
{
  public:
    explicit DictionarySessionLease(NSURL *user);
    ~DictionarySessionLease();
    DictionarySessionLease(const DictionarySessionLease &) = delete;
    DictionarySessionLease &operator=(const DictionarySessionLease &) = delete;
    bool exclusively(const std::function<void()> &operation);
  private:
    int sessions_ = -1;
    int gate_ = -1;
};
}
