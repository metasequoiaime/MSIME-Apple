#include <cstdint>
#include <cstdlib>
#include <iostream>
using HRESULT = std::int32_t;
using BOOL = bool;
#define S_OK 0
constexpr HRESULT E_FAIL = -1;
constexpr bool FALSE = false, TRUE = true;
constexpr int CLSID_TF_CategoryMgr = 1, CLSCTX_INPROC_SERVER = 2;
constexpr int IID_ITfCategoryMgr = 3;
using GUID = int;
constexpr int GUID_TFCAT_TIP_KEYBOARD = 11;
constexpr int GUID_TFCAT_DISPLAYATTRIBUTEPROVIDER = 12;
constexpr GUID SupportCategories[] = {GUID_TFCAT_TIP_KEYBOARD, GUID_TFCAT_DISPLAYATTRIBUTEPROVIDER};
namespace Global { constexpr int MetasequoiaIMECLSID = 7; }
constexpr bool FAILED(HRESULT result) { return result < 0; }
struct Scenario { HRESULT create = S_OK; int fail_at = -1; int calls = 0; int releases = 0; } scenario;
struct ITfCategoryMgr {
  HRESULT RegisterCategory(int, GUID, int) {
    const int call = scenario.calls++;
    return call == scenario.fail_at ? E_FAIL : S_OK;
  }
  HRESULT UnregisterCategory(int, GUID, int) {
    const int call = scenario.calls++;
    return call == scenario.fail_at ? E_FAIL : S_OK;
  }
  void Release() { ++scenario.releases; }
} manager;
HRESULT CoCreateInstance(int, void *, int, int, void **result) {
  *result = FAILED(scenario.create) ? nullptr : &manager;
  return scenario.create;
}
#include "registration_categories.inc"
void require(bool value, const char *message) { if (!value) { std::cerr << message << '\n'; std::exit(1); } }
int main() {
  scenario = {};
  require(RegisterCategories(), "all categories should register");
  require(scenario.calls == 2 && scenario.releases == 1, "successful category lifecycle wrong");
  scenario = {};
  scenario.fail_at = 0;
  require(!RegisterCategories(), "first category failure should fail");
  require(scenario.calls == 1 && scenario.releases == 1, "first failure was not fail-fast");
  scenario = {};
  scenario.fail_at = 1;
  require(!RegisterCategories(), "later category failure should fail");
  require(scenario.calls == 2 && scenario.releases == 1, "later failure lifecycle wrong");
  scenario = {};
  scenario.create = E_FAIL;
  require(!RegisterCategories() && scenario.calls == 0 && scenario.releases == 0,
          "COM activation failure should not call categories");
  scenario = {};
  require(UnregisterCategories(), "all categories should unregister");
  require(scenario.calls == 2 && scenario.releases == 1, "successful cleanup lifecycle wrong");
  for (int failure : {0, 1}) {
    scenario = {};
    scenario.fail_at = failure;
    require(!UnregisterCategories(), "category cleanup failure was hidden");
    require(scenario.calls == 2 && scenario.releases == 1,
            "cleanup must attempt all categories even after a failure");
  }
  scenario = {};
  scenario.create = E_FAIL;
  require(!UnregisterCategories() && scenario.calls == 0 && scenario.releases == 0,
          "cleanup must preserve COM activation failure");
}
