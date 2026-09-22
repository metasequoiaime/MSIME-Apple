#include "../src/core/DictionaryQuiesceLease.h"

#include <cassert>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <unistd.h>

int main() {
  using msime::linux_host::dictionary_quiesce_lease_live;
  using msime::linux_host::dictionary_quiesced;

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
  std::filesystem::remove_all(root);
  return 0;
}
