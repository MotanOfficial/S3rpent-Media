#ifndef LYRICSTRANSLATIONCLIENT_H
#define LYRICSTRANSLATIONCLIENT_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QNetworkAccessManager>
#include <QNetworkReply>

class LyricsTranslationClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    explicit LyricsTranslationClient(QObject *parent = nullptr);
    ~LyricsTranslationClient();

    Q_INVOKABLE void translateLyrics(const QString &trackName, const QString &artistName,
                                     const QString &albumName, const QVariantList &lyricLines,
                                     const QString &apiKey, const QString &targetLanguage = "en");
    
    bool loading() const { return m_loading; }
    QString lastError() const { return m_lastError; }

signals:
    void loadingChanged();
    void translationComplete(const QVariantList &translatedLines);
    void translationFailed(const QString &error);
    void lastErrorChanged();

private slots:
    void onReplyFinished(QNetworkReply *reply);

private:
    QNetworkAccessManager *m_networkManager;
    bool m_loading;
    QString m_lastError;
    
    QString getCacheFilePath(const QString &trackName, const QString &artistName, 
                            const QString &albumName, const QString &targetLanguage) const;
    bool loadFromCache(const QString &cachePath, QVariantList &outLines) const;
    void saveToCache(const QString &cachePath, const QVariantList &lines) const;
    QVariantList parseTranslationResponse(const QByteArray &data) const;
    QJsonObject buildTranslationRequest(const QVariantList &lyricLines) const;
    void setLoading(bool loading);
    void setLastError(const QString &error);
};

#endif // LYRICSTRANSLATIONCLIENT_H

