#include "windowsglobalhotkey.h"

#include <QByteArray>
#include <QDebug>
#include <QGuiApplication>

#ifdef Q_OS_WIN
#  ifndef WIN32_LEAN_AND_MEAN
#    define WIN32_LEAN_AND_MEAN
#  endif
#  include <windows.h>
#endif

WindowsGlobalHotkey::WindowsGlobalHotkey(QObject *parent)
    : QObject(parent)
{
    if (auto *app = qobject_cast<QGuiApplication *>(QGuiApplication::instance()))
        app->installNativeEventFilter(this);
}

WindowsGlobalHotkey::~WindowsGlobalHotkey()
{
    unregisterHotkey();
    if (auto *app = qobject_cast<QGuiApplication *>(QGuiApplication::instance()))
        app->removeNativeEventFilter(this);
}

void WindowsGlobalHotkey::setQtShortcutFallback(bool enabled)
{
    if (m_qtShortcutFallback == enabled)
        return;
    m_qtShortcutFallback = enabled;
    emit qtShortcutFallbackChanged();
}

void WindowsGlobalHotkey::setActiveShortcutSequence(const QString &sequence)
{
    if (m_activeShortcutSequence == sequence)
        return;
    m_activeShortcutSequence = sequence;
    emit activeShortcutSequenceChanged();
}

#ifdef Q_OS_WIN
bool WindowsGlobalHotkey::tryRegisterCombo(const HotkeyCombo &combo)
{
    UnregisterHotKey(nullptr, kOverlayHotkeyId);

    if (!RegisterHotKey(nullptr, kOverlayHotkeyId, combo.modifiers, combo.vk)) {
        const DWORD err = GetLastError();
        if (err == ERROR_HOTKEY_ALREADY_REGISTERED) {
            qWarning() << "[GlobalHotkey]" << combo.label
                       << "is already registered globally (error 1409).";
        } else {
            qWarning() << "[GlobalHotkey] RegisterHotKey failed for" << combo.label
                       << "- GetLastError:" << err;
        }
        return false;
    }

    m_registered = true;
    setActiveShortcutSequence(QString::fromLatin1(combo.qmlSequence));
    setQtShortcutFallback(false);
    qDebug() << "[GlobalHotkey] Registered system-wide" << combo.label << "(overlay toggle)";
    return true;
}
#endif

bool WindowsGlobalHotkey::registerOverlayToggleHotkey(QObject *qmlRoot)
{
    unregisterHotkey();
    m_qmlRoot = qmlRoot;
    setActiveShortcutSequence(QStringLiteral("Ctrl+Shift+O"));

    if (!m_qmlRoot) {
        setQtShortcutFallback(true);
        return false;
    }

#ifdef Q_OS_WIN
    static const HotkeyCombo kPrimary = {
        MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT,
        0x4F, // VK_O
        "Ctrl+Shift+O",
        "Ctrl+Shift+O",
    };
    static const HotkeyCombo kFallback = {
        MOD_CONTROL | MOD_ALT | MOD_NOREPEAT,
        0x4F, // VK_O
        "Ctrl+Alt+O",
        "Ctrl+Alt+O",
    };

    if (tryRegisterCombo(kPrimary))
        return true;

    qWarning() << "[GlobalHotkey] Trying fallback shortcut Ctrl+Alt+O...";
    if (tryRegisterCombo(kFallback))
        return true;

    setActiveShortcutSequence(QStringLiteral("Ctrl+Alt+O"));
    setQtShortcutFallback(true);
    qWarning() << "[GlobalHotkey] Global registration failed; use Ctrl+Alt+O while this app is focused.";
    return false;
#else
    setQtShortcutFallback(true);
    return false;
#endif
}

void WindowsGlobalHotkey::unregisterHotkey()
{
#ifdef Q_OS_WIN
    if (m_registered) {
        if (!UnregisterHotKey(nullptr, kOverlayHotkeyId))
            qWarning() << "[GlobalHotkey] UnregisterHotKey failed:" << GetLastError();
    }
#endif
    m_registered = false;
    m_qmlRoot = nullptr;
    setQtShortcutFallback(true);
}

bool WindowsGlobalHotkey::nativeEventFilter(const QByteArray &eventType, void *message, qintptr *result)
{
#ifdef Q_OS_WIN
    Q_UNUSED(result);
    if (!m_registered || !m_qmlRoot || eventType != "windows_generic_MSG")
        return false;
    auto *msg = static_cast<MSG *>(message);
    if (msg->message != WM_HOTKEY || static_cast<int>(msg->wParam) != kOverlayHotkeyId)
        return false;

    const bool cur = m_qmlRoot->property("musicOverlayVisible").toBool();
    m_qmlRoot->setProperty("musicOverlayVisible", !cur);
    return true;
#else
    Q_UNUSED(eventType);
    Q_UNUSED(message);
    Q_UNUSED(result);
    return false;
#endif
}
