#include "DictionarySessionLease.h"
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#include <cerrno>
#include <stdexcept>

namespace metasequoia::apple
{
namespace
{
int Lock(int fd, int flags)
{
    int result;
    do
    {
        result = flock(fd, flags);
    } while (result < 0 && errno == EINTR);
    return result;
}
} // namespace
DictionarySessionLease::DictionarySessionLease(NSURL *user)
{
    if (![NSFileManager.defaultManager createDirectoryAtURL:user
                                withIntermediateDirectories:YES
                                                 attributes:@{
                                                     NSFilePosixPermissions : @0700
                                                 }
                                                      error:nil])
        throw std::runtime_error("Cannot create dictionary session directory");
    sessions_ = open([user URLByAppendingPathComponent:@"dictionary-sessions.lock"].fileSystemRepresentation,
                     O_CREAT | O_RDWR | O_CLOEXEC, 0600);
    gate_ = open([user URLByAppendingPathComponent:@"dictionary-publication.lock"].fileSystemRepresentation,
                 O_CREAT | O_RDWR | O_CLOEXEC, 0600);
    if (sessions_ < 0 || gate_ < 0 || Lock(sessions_, LOCK_SH) != 0)
    {
        if (sessions_ >= 0)
            close(sessions_);
        if (gate_ >= 0)
            close(gate_);
        throw std::runtime_error("Cannot acquire dictionary session lease");
    }
}
DictionarySessionLease::~DictionarySessionLease()
{
    Lock(sessions_, LOCK_UN);
    close(sessions_);
    close(gate_);
}
bool DictionarySessionLease::exclusively(const std::function<void()> &operation)
{
    if (Lock(gate_, LOCK_EX | LOCK_NB) != 0)
        return false;
    // Keep the publisher gate until the shared lease has been restored. Another
    // publisher cannot acquire exclusivity in the conversion's unlocked window.
    Lock(sessions_, LOCK_UN);
    if (Lock(sessions_, LOCK_EX | LOCK_NB) != 0)
    {
        Lock(sessions_, LOCK_SH);
        Lock(gate_, LOCK_UN);
        return false;
    }
    try
    {
        operation();
    }
    catch (...)
    {
        Lock(sessions_, LOCK_SH);
        Lock(gate_, LOCK_UN);
        throw;
    }
    Lock(sessions_, LOCK_SH);
    Lock(gate_, LOCK_UN);
    return true;
}
} // namespace metasequoia::apple
