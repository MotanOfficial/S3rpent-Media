#pragma once

#include <QFutureWatcher>
#include <QObject>
#include <QUrl>

class ModelSourceResolver : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(bool resolving READ resolving NOTIFY resolvingChanged)

public:
    explicit ModelSourceResolver(QObject *parent = nullptr);

    Q_INVOKABLE QUrl resolveForViewing(const QUrl &sourceUrl);
    Q_INVOKABLE void resolveForViewingAsync(const QUrl &sourceUrl);
    QString lastError() const;
    bool resolving() const;

signals:
    void lastErrorChanged();
    void resolvingChanged();
    void resolveFinished(const QUrl &originalSource, const QUrl &resolvedSource, const QString &error);

private:
    QString m_lastError;
    bool m_resolving = false;
    quint64 m_requestToken = 0;

    void setLastError(const QString &error);
    void setResolving(bool value);
    static QUrl resolveForViewingInternal(const QUrl &sourceUrl, QString *errorOut);
    static QString extensionLower(const QString &filePath);
    static QString findObjForMtl(const QString &mtlPath);
    static QString findBlenderExecutable();
    static QString ensureCacheDir();
    static QString cachePathForBlend(const QString &blendPath);
    static QString convertBlendToGlb(const QString &blendPath, QString *errorOut);
};
