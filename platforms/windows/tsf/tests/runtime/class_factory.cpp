#include <windows.h>
#include <objbase.h>
#include <msctf.h>

#include <stdexcept>
#include <string>
#include <cstring>

namespace {
constexpr CLSID kMetasequoiaImeClsid = {
    0xe3062e9a, 0xd834, 0x4637, {0x89, 0x58, 0xed, 0x8c, 0xfa, 0x42, 0x7d, 0x01}};

using DllGetClassObjectFn = HRESULT(STDAPICALLTYPE *)(REFCLSID, REFIID, void **);

void require(bool condition, const char *message) {
  if (!condition)
    throw std::runtime_error(message);
}

std::wstring module_directory() {
  wchar_t path[MAX_PATH]{};
  const DWORD length = GetModuleFileNameW(nullptr, path, ARRAYSIZE(path));
  require(length != 0 && length < ARRAYSIZE(path), "Could not locate test executable");
  std::wstring result(path, length);
  const auto slash = result.find_last_of(L"\\/");
  require(slash != std::wstring::npos, "Test executable has no directory");
  result.resize(slash + 1);
  return result;
}

HMODULE load_tip() {
  const auto directory = module_directory();
  for (const wchar_t *name : {L"libMetasequoiaImeTsf.dll", L"MetasequoiaImeTsf.dll"}) {
    const auto path = directory + name;
    if (auto module = LoadLibraryW(path.c_str()))
      return module;
  }
  throw std::runtime_error("Could not load the built TSF DLL");
}
} // namespace

int main() {
  bool initialized = false;
  try {
    initialized = SUCCEEDED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED));
    require(initialized,
            "COM initialization failed");
    HMODULE module = load_tip();
    const auto raw_get_class_object = GetProcAddress(module, "DllGetClassObject");
    DllGetClassObjectFn get_class_object = nullptr;
    static_assert(sizeof(get_class_object) == sizeof(raw_get_class_object));
    std::memcpy(&get_class_object, &raw_get_class_object, sizeof(get_class_object));
    require(get_class_object != nullptr, "TSF DLL omitted DllGetClassObject");

    IClassFactory *factory = nullptr;
    require(SUCCEEDED(get_class_object(kMetasequoiaImeClsid, IID_IClassFactory,
                                       reinterpret_cast<void **>(&factory))) &&
                factory != nullptr,
            "TSF class factory could not be created");
    IUnknown *unknown = nullptr;
    require(SUCCEEDED(factory->CreateInstance(nullptr, IID_IUnknown,
                                               reinterpret_cast<void **>(&unknown))) &&
                unknown != nullptr,
            "TSF class factory could not instantiate the TIP");
    ITfTextInputProcessor *processor = nullptr;
    require(SUCCEEDED(unknown->QueryInterface(IID_ITfTextInputProcessor,
                                               reinterpret_cast<void **>(&processor))) &&
                processor != nullptr,
            "TIP object does not implement ITfTextInputProcessor");

    processor->Release();
    unknown->Release();
    factory->Release();
    FreeLibrary(module);
    CoUninitialize();
    initialized = false;
    return 0;
  } catch (...) {
    if (initialized)
      CoUninitialize();
    return 1;
  }
}
