#ifndef LASTFMCLIENT_H
#define LASTFMCLIENT_H

#include <QObject>
#include <QString>
#include <QNetworkAccessManager>
#include <QNetworkReply>

class LastFMClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    explicit LastFMClient(QObject *parent = nullptr);
    ~LastFMClient();

    bool loading() const { return m_loading; }
    QString lastError() const { return m_lastError; }

    // Fetch cover art from Last.fm API
    Q_INVOKABLE void fetchCoverArt(const QString &trackName, const QString &artistName, const QString &apiKey = "");

signals:
    void coverArtFound(const QString &url);
    void coverArtNotFound();
    void coverArtError(const QString &error);
    void loadingChanged();
    void lastErrorChanged();

private slots:
    void onLastFMReplyFinished(QNetworkReply *reply);
    void onTrackSearchReplyFinished(QNetworkReply *reply);
    void onAlbumInfoReplyFinished(QNetworkReply *reply);

private:
    void setLoading(bool loading);
    void setLastError(const QString &error);
    QString extractCoverArtUrlFromResponse(const QByteArray &data);
    void searchTrack(const QString &trackName, const QString &artistName);
    void fetchAlbumInfo(const QString &artistName, const QString &albumName);
    void searchAlbum(const QString &artistName, const QString &albumName);
    QString cleanArtistName(const QString &artistName);
    QString extractAlbumNameFromTrackSearch(const QByteArray &data);
    QString extractCoverArtUrlFromAlbumInfo(const QByteArray &data);
    
    QString m_currentTrackName;
    QString m_currentArtistName;
    bool m_hasTriedFirstArtistOnly;  // Flag to prevent infinite loop when retrying with first artist

    QNetworkAccessManager *m_networkManager;
    bool m_loading;
    QString m_lastError;
    QString m_apiKey;
};

#endif // LASTFMCLIENT_H

