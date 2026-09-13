#pragma once

#include "stdafx.h"
#include "sal.h"

#include <combaseapi.h>
#include <olectl.h>
#include <assert.h>

#include <strsafe.h>
#include <intsafe.h>

#include "initguid.h"
#include "msctf.h"
#ifdef __MINGW32__
#include <algorithm>
#include <cstring>
#include "ctffunc_compat.h"
#undef UNREFERENCED_PARAMETER
#define UNREFERENCED_PARAMETER(parameter) (void)(parameter)
using std::min;
using std::max;
#endif
