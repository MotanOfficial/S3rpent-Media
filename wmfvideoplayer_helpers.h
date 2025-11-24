#ifndef WMFVIDEOPLAYER_HELPERS_H
#define WMFVIDEOPLAYER_HELPERS_H

#include <QString>

#ifdef Q_OS_WIN
#include <windows.h>
#include <comdef.h>

// Helper to convert HRESULT to QString
QString hresultToString(HRESULT hr);

// Helper to get GUID as string
QString guidToString(const GUID &guid);

#endif

#endif // WMFVIDEOPLAYER_HELPERS_H

