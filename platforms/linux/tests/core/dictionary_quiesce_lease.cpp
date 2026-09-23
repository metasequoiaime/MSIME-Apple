#include "../src/core/DictionaryQuiesceLease.h"

#include <cassert>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <unistd.h>

int main() {
  using msime::linux_host::dictionary_quiesce_lease_live;
  using msime::linux_host::dictionary_quiesced;
  using msime::linux_host::preference_save_held;

  assert(dictionary_quiesce_lease_live("1010000", 1000000));
  assert(dictionary_quiesce_lease_live("1010000\n", 1000000));
  assert(dictionary_quiesce_lease_live("1030000", 1000000));
  // Expired, or further out than any real lease (a clock jump or a stray file), is ignored.
  assert(!dictionary_quiesce_lease_live("1000000", 1000000));
  assert(!dictionary_quiesce_lease_live("999999", 1000000));
  assert(!dictionary_quiesce_lease_live("1030001", 1000000));
  assert(!dictionary_quiesce_lease_live("", 1000000));
  assert(!dictionary_quiesce_lease_live("10x0000", 1000000));
  assert(!dictionary_quiesce_lease_live("-1010000", 1000000));
  assert(!dictionary_quiesce_lease_live("99999999999999999999999", 1000000));

  char pattern[] = "/tmp/msime-quiesce-XXXXXX";
  const std::filesystem::path root = mkdtemp(pattern);
  assert(!dictionary_quiesced(root.string(), 1000000));
  assert(!dictionary_quiesced("", 1000000));
  assert(!dictionary_quiesced("relative", 1000000));
  {
    std::ofstream(root / ".msime-dictionary-quiesce") << "1005000";
  }
  assert(dictionary_quiesced(root.string(), 1000000));
  assert(!dictionary_quiesced(root.string(), 1006000));

  // A data directory move holds the lease on the old user directory for the whole copy, in the form the settings window stages and renames into place. A host still configured for the old directory stays off it; one that has read the rewritten locator opens on the copy, which carries no lease.
  const auto old_user = root / "old" / "user";
  const auto new_user = root / "new" / "user";
  std::filesystem::create_directories(old_user);
  std::filesystem::create_directories(new_user);
  {
    std::ofstream(old_user / ".msime-dictionary-quiesce") << "1030000\n";
  }
  assert(dictionary_quiesced(old_user.string(), 1000000));
  assert(dictionary_quiesced(old_user.string() + "/", 1000000));
  assert(!dictionary_quiesced(new_user.string(), 1000000));
  // Menu preference saves into the old root wait while it is copied; saves into the copy go ahead.
  assert(preference_save_held(old_user.string(), 1000000));
  assert(!preference_save_held(new_user.string(), 1000000));
  assert(!preference_save_held("", 1000000));
  assert(!preference_save_held("relative", 1000000));
  // A lease still being staged is not the lease; the rename is what raises it.
  std::filesystem::remove(old_user / ".msime-dictionary-quiesce");
  {
    std::ofstream(old_user / ".msime-dictionary-quiesce.4242") << "1030000\n";
  }
  assert(!dictionary_quiesced(old_user.string(), 1000000));
  // Once the move has taken the old user directory away there is no lease to read; the host's session open fails there instead, so it cannot start an empty library at the old path.
  std::filesystem::remove_all(root / "old");
  assert(!dictionary_quiesced(old_user.string(), 1000000));
  assert(!std::filesystem::exists(old_user));
  // With the lease gone along with the old user directory, a host still configured for it must not put a preferences file back into the old root.
  assert(preference_save_held(old_user.string(), 1000000));
  assert(!preference_save_held(new_user.string(), 1000000));
  std::filesystem::remove_all(root);
  return 0;
}
