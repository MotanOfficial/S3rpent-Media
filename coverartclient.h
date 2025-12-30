#ifndef COVERARTCLIENT_H
#define COVERARTCLIENT_H

#include <QObject>
#include <QString>
#include <QNetworkAccessManager>
#include <QNetworkReply>

class CoverArtClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    explicit CoverArtClient(QObject *parent = nullptr);
    ~CoverArtClient();

    // Search for cover art by track metadata
    Q_INVOKABLE void fetchCoverArt(const QString &trackName, const QString &artistName, 
                                   const QString &albumName = "");
    
    bool loading() const { return m_loading; }
    QString lastError() const { return m_lastError; }

signals:
    void loadingChanged();
    void coverArtFound(const QString &coverArtUrl);
    void coverArtNotFound();
    void coverArtError(const QString &error);
    void lastErrorChanged();

private slots:
    void onMusicBrainzReplyFinished(QNetworkReply *reply);
    void onCoverArtArchiveReplyFinished(QNetworkReply *reply);

private:
    QNetworkAccessManager *m_networkManager;
    bool m_loading;
    QString m_lastError;
    QString m_currentTrackName;
    QString m_currentArtistName;
    QString m_currentAlbumName;
    QString m_currentReleaseGroupMbid;  // Store release-group MBID separately
    QString m_currentReleaseMbid;       // Store release MBID separately
    
    void searchMusicBrainz(const QString &trackName, const QString &artistName, 
                          const QString &albumName);
    void fetchFromCoverArtArchive(const QString &mbid, bool isReleaseGroup = false);
    QString extractMBIDFromMusicBrainzResponse(const QByteArray &data);
    QString extractCoverArtUrlFromResponse(const QByteArray &data);
    void setLoading(bool loading);
    void setLastError(const QString &error);
};

#endif // COVERARTCLIENT_H

