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
    Q_PROPERTY(Status lastStatus READ lastStatus NOTIFY lastStatusChanged)
    Q_PROPERTY(QVariantMap lastStatusInfo READ lastStatusInfo NOTIFY lastStatusChanged)

public:
    enum Status {
        StatusIdle = 0,
        StatusSearching,
        StatusLoaded,
        StatusNoMatch,
        StatusNetworkError,
        StatusParseError,
        StatusInstrumental,
        StatusInvalidRequest
    };
    Q_ENUM(Status)

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
    Status lastStatus() const { return m_lastStatus; }
    QVariantMap lastStatusInfo() const { return m_lastStatusInfo; }

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
    void lastStatusChanged();

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
    Status m_lastStatus;
    QVariantMap m_lastStatusInfo;
    
    enum SearchAttemptMode {
        SearchWithArtist = 0,
        SearchWithoutArtist,
        SearchQueryFallback
    };

    // Store search parameters to match results
    QString m_searchTrackName;
    QString m_searchArtistName;
    QString m_searchAlbumName;
    SearchAttemptMode m_currentSearchMode;
    QString m_activeRequestSignature;
    
    QString urlEncode(const QString &str) const;
    void setSyncedLyrics(const QString &lyrics);
    void setPlainLyrics(const QString &lyrics);
    void setLoading(bool loading);
    QString buildRequestSignature(const QString &trackName,
                                  const QString &artistName,
                                  const QString &albumName) const;
    void tagReplyWithSignature(QNetworkReply *reply,
                               const QString &signature,
                               bool autoFetch) const;
    bool shouldIgnoreReply(QNetworkReply *reply) const;
    void sendSearchRequest(SearchAttemptMode mode);
    bool tryNextSearchAttempt();
    void resetSearchState();
    void updateStatus(Status status,
                      const QString &message = QString(),
                      const QVariantMap &details = QVariantMap());
};

#endif // LRCLIBCLIENT_H

