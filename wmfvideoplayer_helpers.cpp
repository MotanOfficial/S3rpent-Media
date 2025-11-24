#include "wmfvideoplayer_helpers.h"

#ifdef Q_OS_WIN
// Helper to convert HRESULT to QString
QString hresultToString(HRESULT hr) {
    _com_error err(hr);
    return QString::fromWCharArray(err.ErrorMessage());
}

// Helper to get GUID as string
QString guidToString(const GUID &guid) {
    OLECHAR *guidString;
    StringFromCLSID(guid, &guidString);
    QString result = QString::fromWCharArray(guidString);
    CoTaskMemFree(guidString);
    return result;
}
#endif

