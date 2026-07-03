#ifndef WINDOWSGLOBALHOTKEY_H
#define WINDOWSGLOBALHOTKEY_H

#include <QAbstractNativeEventFilter>
#include <QObject>
#include <QString>

class WindowsGlobalHotkey final : public QObject, public QAbstractNativeEventFilter
{
    Q_OBJECT
    /// When true, QML should handle the shortcut (Win32 registration failed or unavailable).
    Q_PROPERTY(bool qtShortcutFallback READ qtShortcutFallback NOTIFY qtShortcutFallbackChanged)
    /// Active key sequence for overlay toggle (e.g. "Ctrl+Shift+O" or "Ctrl+Alt+O" when fallback).
    Q_PROPERTY(QString activeShortcutSequence READ activeShortcutSequence NOTIFY activeShortcutSequenceChanged)

public:
    explicit WindowsGlobalHotkey(QObject *parent = nullptr);
    ~WindowsGlobalHotkey() override;

    bool qtShortcutFallback() const { return m_qtShortcutFallback; }
    QString activeShortcutSequence() const { return m_activeShortcutSequence; }

    /// Register overlay toggle hotkey on @p qmlRoot (tries Ctrl+Shift+O, then Ctrl+Alt+O).
    Q_INVOKABLE bool registerOverlayToggleHotkey(QObject *qmlRoot);
    void unregisterHotkey();

signals:
    void qtShortcutFallbackChanged();
    void activeShortcutSequenceChanged();

protected:
    bool nativeEventFilter(const QByteArray &eventType, void *message, qintptr *result) override;

private:
#ifdef Q_OS_WIN
    struct HotkeyCombo {
        unsigned modifiers = 0;
        unsigned vk = 0;
        const char *label = nullptr;
        const char *qmlSequence = nullptr;
    };

    bool tryRegisterCombo(const HotkeyCombo &combo);
#endif
    void setQtShortcutFallback(bool enabled);
    void setActiveShortcutSequence(const QString &sequence);

    QObject *m_qmlRoot = nullptr;
    bool m_registered = false;
    bool m_qtShortcutFallback = true;
    QString m_activeShortcutSequence = QStringLiteral("Ctrl+Shift+O");
    static constexpr int kOverlayHotkeyId = 1001;
};

#endif // WINDOWSGLOBALHOTKEY_H
