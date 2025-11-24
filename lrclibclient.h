#ifndef LRCLIBCLIENT_H
#define LRCLIBCLIENT_H

#include <QObject>
#include <QString>
#include <QUrl>
#include <QVariantMap>
#include <QNetworkAccessManager>
#include <QNetworkReply>

// Structure to hold a single lyric line with timestamp
struct LyricLine {
    qint64 timestamp;  // in milliseconds
    QString text;
};

class LRCLibClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString syncedLyrics READ syncedLyrics NOTIFY syncedLyricsChanged)
    Q_PROPERTY(QString plainLyrics READ plainLyrics NOTIFY plainLyricsChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(QVariantList lyricLines READ lyricLines NOTIFY lyricLinesChanged)

public:
    explicit LRCLibClient(QObject *parent = nullptr);
    ~LRCLibClient();

    Q_INVOKABLE void fetchLyrics(const QString &trackName, const QString &artistName, 
                                 const QString &albumName, int durationSeconds);
    Q_INVOKABLE void fetchLyricsCached(const QString &trackName, const QString &artistName, 
                                       const QString &albumName, int durationSeconds);
    Q_INVOKABLE void fetchLyricsById(int id);
    Q_INVOKABLE void searchLyrics(const QString &query, const QString &trackName = "", 
                                  const QString &artistName = "", const QString &albumName = "");
    
    QString syncedLyrics() const { return m_syncedLyrics; }
    QString plainLyrics() const { return m_plainLyrics; }
    bool loading() const { return m_loading; }
    QVariantList lyricLines() const { return m_lyricLines; }

    // Helper function to get current lyric line based on position (in milliseconds)
    Q_INVOKABLE QString getCurrentLyricLine(qint64 positionMs) const;
    Q_INVOKABLE int getCurrentLyricLineIndex(qint64 positionMs) const;
    Q_INVOKABLE void clearLyrics();  // Clear all lyrics

signals:
    void syncedLyricsChanged();
    void plainLyricsChanged();
    void loadingChanged();
    void lyricLinesChanged();
    void lyricsFetched(bool success, const QString &errorMessage = "");
    void searchResultsReceived(const QVariantList &results);

private slots:
    void onReplyFinished(QNetworkReply *reply);
    void parseLyricsResponse(const QByteArray &data);
    void parseSearchResponse(const QByteArray &data);
    QVariantList parseLRCLines(const QString &lrcText);

private:
    QNetworkAccessManager *m_networkManager;
    QString m_syncedLyrics;
    QString m_plainLyrics;
    bool m_loading;
    QVariantList m_lyricLines;  // List of {timestamp, text} objects
    
    // Store search parameters to match results
    QString m_searchTrackName;
    QString m_searchArtistName;
    QString m_searchAlbumName;
    bool m_retryingWithoutArtist;  // Track if we're retrying without artist
    
    QString urlEncode(const QString &str) const;
    void setSyncedLyrics(const QString &lyrics);
    void setPlainLyrics(const QString &lyrics);
    void setLoading(bool loading);
};

#endif // LRCLIBCLIENT_H

