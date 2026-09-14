#include <windows.h>
#include <msctf.h>

// MinGW declares these TSF properties but its uuid archive omits them.
// Values verified against Microsoft's windows-sys 0.61.2 TextServices
// bindings (also pinned by this workspace). MSVC uses the SDK's uuid.lib.
extern "C" const GUID GUID_PROP_COMPOSING = {
    0xe12ac060, 0xaf15, 0x11d2, {0xaf, 0xc5, 0x00, 0x10, 0x5a, 0x27, 0x99, 0xb5}};
extern "C" const GUID GUID_PROP_LANGID = {
    0x3280ce20, 0x8032, 0x11d2, {0xb6, 0x03, 0x00, 0x10, 0x5a, 0x27, 0x99, 0xb5}};
