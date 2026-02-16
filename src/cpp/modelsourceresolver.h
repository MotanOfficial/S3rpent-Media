#pragma once

#include <QFutureWatcher>
#include <QObject>
#include <QUrl>
#include <QVariantMap>

class ModelSourceResolver : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(bool resolving READ resolving NOTIFY resolvingChanged)

public:
    explicit ModelSourceResolver(QObject *parent = nullptr);

    Q_INVOKABLE QUrl resolveForViewing(const QUrl &sourceUrl);
    Q_INVOKABLE void resolveForViewingAsync(const QUrl &sourceUrl);
    Q_INVOKABLE void resolveForViewingAsync(const QUrl &sourceUrl, const QVariantMap &propertyOverrides);
    Q_INVOKABLE QVariantList getDiscoveredBlendProperties(const QUrl &blendUrl) const;
    Q_INVOKABLE QVariantMap getBlendVisibilityMap(const QUrl &blendUrl) const;
    // Property -> { materials: [...], objects: [...] } from driver analysis during conversion (data-driven, not hard-coded).
    Q_INVOKABLE QVariantMap getBlendMaterialMap(const QUrl &blendUrl) const;
    // When a blend was exported with split GLBs (base + part per visibility property), returns
    // a map with "base" (QUrl) and "parts" (property name -> QUrl). Empty if not split.
    Q_INVOKABLE QVariantMap getResolvedModelParts(const QUrl &blendUrl) const;
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
    static QUrl resolveForViewingInternal(const QUrl &sourceUrl, QString *errorOut, const QVariantMap &propertyOverrides = QVariantMap());
    static QString extensionLower(const QString &filePath);
    static QString findObjForMtl(const QString &mtlPath);
    static QString findBlenderExecutable();
    static QString ensureCacheDir();
    static QString cachePathForBlend(const QString &blendPath, const QVariantMap &propertyOverrides = QVariantMap());
    static QString propsPathForBlend(const QString &blendPath);
    static QString visibilityMapPathForBlend(const QString &blendPath);
    static QString matMapPathForBlend(const QString &blendPath);
    static QString partsJsonPathForBlend(const QString &blendPath);
    static QString convertBlendToGlb(const QString &blendPath, QString *errorOut, const QVariantMap &propertyOverrides = QVariantMap());
};
