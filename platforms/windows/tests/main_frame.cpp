#include "MainFrame.h"
#include <stdexcept>

using namespace msime::windows;
void require(bool value) {
  if (!value)
    throw std::runtime_error("Main frame validation failed");
}
int main() {
  using namespace FanyImePipeEventType;
  FanyImeNamedpipeData packet{};
  packet.client_id = 42;
  packet.request_id = 1;
  for (auto event : {KeyEvent, HideCandidateWnd, ShowCandidateWnd,
                     MoveCandidateWnd, IMESwitch, PuncSwitch,
                     DoubleSingleByteSwitch, ClientHello, ClientActivated,
                     ClientDeactivated, ClientSuspended, StatusSnapshot,
                     FocusRestored}) {
    packet.event_type = event;
    require(valid_main_frame(packet, 42));
    require(!valid_main_frame(packet, 43));
    require(!valid_main_frame(packet, 0));
  }
  for (auto event : {LangbarRightClick, 5u, 6u, 16u, UINT32_MAX}) {
    packet.event_type = event;
    require(!valid_main_frame(packet, 42));
  }
  packet.event_type = KeyEvent;
  packet.request_id = 0;
  require(!valid_main_frame(packet, 42));
  packet.request_id = FANY_IME_NO_REQUEST_ID;
  require(!valid_main_frame(packet, 42));
  packet.event_type = ClientActivated;
  require(valid_main_frame(packet, 42));
  packet.request_id = 0;
  require(!valid_main_frame(packet, 42));
  packet.request_id = 1;
  packet.modifiers_down = FanyImePipeFlags::UiLess;
  require(valid_main_frame(packet, 42));
  packet.modifiers_down = 0;
  for (int length : {-1, 128, INT32_MAX}) {
    packet.pinyin_length = length;
    require(!valid_main_frame(packet, 42));
  }
  packet.pinyin_length = 127;
  require(valid_main_frame(packet, 42));
  packet.pinyin_string[127] = u'x';
  require(!valid_main_frame(packet, 42));
  packet.pinyin_length = 0;
  require(!valid_main_frame(packet, 42));
  packet.pinyin_string[127] = 0;
  packet.pinyin_string[0] = u'x';
  require(!valid_main_frame(packet, 42));
  packet.pinyin_string[0] = 0;
  for (auto event : {StatusSnapshot, FocusRestored}) {
    packet.event_type = event;
    packet.pinyin_length = 1;
    packet.keycode = packet.modifiers_down = 1;
    require(valid_main_frame(packet, 42));
    packet.keycode = 2;
    require(!valid_main_frame(packet, 42));
    packet.keycode = 1;
    packet.modifiers_down = 2;
    require(!valid_main_frame(packet, 42));
    packet.modifiers_down = 1;
    packet.pinyin_length = 2;
    require(!valid_main_frame(packet, 42));
  }
}
