#include "../src/candidates/CandidateWheelPaging.h"

#include <cassert>

int main() {
  using msime::linux_host::CandidateWheelPagingSync;
  using msime::linux_host::read_candidate_wheel_paging;
  using Json = nlohmann::json;

  assert(!read_candidate_wheel_paging(Json()));
  assert(!read_candidate_wheel_paging(Json::object()));
  assert(!read_candidate_wheel_paging({{"navigation", {{"mouse_wheel", "yes"}}}}));
  assert(!read_candidate_wheel_paging({{"navigation", {{"mouse_wheel", false}}}}));
  assert(read_candidate_wheel_paging({{"navigation", {{"mouse_wheel", true}}}}));

  // The untouched default leaves the desktop's value; later changes are written once each.
  CandidateWheelPagingSync untouched;
  assert(!untouched.next(false));
  assert(!untouched.next(false));
  assert(untouched.next(true) == true);
  assert(!untouched.next(true));
  assert(untouched.next(false) == false);
  assert(!untouched.next(false));

  // A preference already enabled when the addon starts is written straight away.
  CandidateWheelPagingSync enabled;
  assert(enabled.next(true) == true);
  assert(!enabled.next(true));
  return 0;
}
