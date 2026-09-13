#pragma once

#include <Windows.h>
#include <msctf.h>

#ifndef TF_CLIENTID_NULL
#define TF_CLIENTID_NULL ((TfClientId)0)
#endif

extern HINSTANCE g_hInst;
extern ITfThreadMgr *g_pThreadMgr;
extern TfClientId g_TfClientId;

BOOL InitializeTsfTextServices(HINSTANCE hInstance);
void UninitializeTsfTextServices();
