#include <windows.h>
#include <unknwn.h>

// Link-only fixture; these are not functional COM factories or registration.
STDAPI DllGetClassObject(REFCLSID, REFIID, void **out) {
    if (out) *out = nullptr;
    return CLASS_E_CLASSNOTAVAILABLE;
}
STDAPI DllCanUnloadNow() { return S_OK; }
STDAPI DllRegisterServer() { return E_NOTIMPL; }
STDAPI DllUnregisterServer() { return E_NOTIMPL; }
