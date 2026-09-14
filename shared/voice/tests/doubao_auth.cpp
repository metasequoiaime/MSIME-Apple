#include "DoubaoAuth.h"
#include <cassert>

int main() {
  using msime::voice::doubao_auth_headers;
  const auto api = doubao_auth_headers("api_key", "stale-app", "synthetic-token", "fixture-resource");
  assert(api);
  assert(api->find("x-api-key: synthetic-token\r\n") != std::string::npos);
  assert(api->find("x-api-app-key:") == std::string::npos);
  assert(api->find("stale-app") == std::string::npos);
  const auto legacy = doubao_auth_headers("legacy", "synthetic-app", "synthetic-token", "fixture-resource");
  assert(legacy);
  assert(legacy->find("x-api-app-key: synthetic-app\r\n") != std::string::npos);
  assert(legacy->find("x-api-access-key: synthetic-token\r\n") != std::string::npos);
  assert(legacy->find("x-api-key:") == std::string::npos);
  assert(!doubao_auth_headers("legacy", "", "synthetic-token", "fixture-resource"));
  assert(!doubao_auth_headers("invalid", "synthetic-app", "synthetic-token", "fixture-resource"));
  assert(!doubao_auth_headers("api_key", "", "injected\r\nheader", "fixture-resource"));
  assert(doubao_auth_headers("", "synthetic-app", "synthetic-token", "fixture-resource"));
}
