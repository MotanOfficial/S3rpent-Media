#include "lrclibclient.h"
#include <QNetworkRequest>
#include <QUrlQuery>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QRegularExpression>
#include <QDebug>

LRCLibClient::LRCLibClient(QObject *parent)
    : QObject(parent)
    , m_networkManager(new QNetworkAccessManager(this))
    , m_loading(false)
    , m_searchTrackName()
    , m_searchArtistName()
    , m_searchAlbumName()
    , m_retryingWithoutArtist(false)
{
    connect(m_networkManager, &QNetworkAccessManager::finished,
            this, &LRCLibClient::onReplyFinished);
}

LRCLibClient::~LRCLibClient()
{
}

void LRCLibClient::fetchLyrics(const QString &trackName, const QString &artistName, 
                               const QString &albumName, int durationSeconds)
{
    if (trackName.isEmpty()) {
        qWarning() << "[LRCLIB] Invalid parameters for fetchLyrics - trackName is required";
        emit lyricsFetched(false, "Invalid parameters");
        return;
    }

    // Store search parameters to match results
    m_searchTrackName = trackName;
    m_searchArtistName = artistName;
    m_searchAlbumName = albumName;
    m_retryingWithoutArtist = false;  // Reset retry flag

    setLoading(true);
    
    // Use search API which is more flexible - can work with just track_name
    QUrl url("https://lrclib.net/api/search");
    QUrlQuery query;
    query.addQueryItem("track_name", trackName);
    // Artist name is optional - include it in first attempt
    if (!artistName.isEmpty()) {
        query.addQueryItem("artist_name", artistName);
    }
    // Album name is optional
    if (!albumName.isEmpty()) {
        query.addQueryItem("album_name", albumName);
    }
    url.setQuery(query);

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader, 
                     "s3rp3nt_media v0.1 (https://github.com/s3rp3nt/s3rp3nt_media)");
    
    qDebug() << "[LRCLIB] Searching lyrics:" << url.toString();
    m_networkManager->get(request);
}

void LRCLibClient::fetchLyricsCached(const QString &trackName, const QString &artistName, 
                                     const QString &albumName, int durationSeconds)
{
    if (trackName.isEmpty() || artistName.isEmpty() || albumName.isEmpty()) {
        qWarning() << "[LRCLIB] Invalid parameters for fetchLyricsCached";
        emit lyricsFetched(false, "Invalid parameters");
        return;
    }

    setLoading(true);
    
    QUrl url("https://lrclib.net/api/get-cached");
    QUrlQuery query;
    query.addQueryItem("track_name", trackName);
    query.addQueryItem("artist_name", artistName);
    query.addQueryItem("album_name", albumName);
    // Don't add duration parameter - API works without it
    url.setQuery(query);

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader, 
                     "s3rp3nt_media v0.1 (https://github.com/s3rp3nt/s3rp3nt_media)");
    
    qDebug() << "[LRCLIB] Fetching cached lyrics:" << url.toString();
    m_networkManager->get(request);
}

void LRCLibClient::fetchLyricsById(int id)
{
    if (id <= 0) {
        qWarning() << "[LRCLIB] Invalid ID for fetchLyricsById";
        emit lyricsFetched(false, "Invalid ID");
        return;
    }

    setLoading(true);
    
    QUrl url(QString("https://lrclib.net/api/get/%1").arg(id));

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader, 
                     "s3rp3nt_media v0.1 (https://github.com/s3rp3nt/s3rp3nt_media)");
    
    qDebug() << "[LRCLIB] Fetching lyrics by ID:" << url.toString();
    m_networkManager->get(request);
}

void LRCLibClient::searchLyrics(const QString &query, const QString &trackName, 
                                const QString &artistName, const QString &albumName)
{
    if (query.isEmpty() && trackName.isEmpty()) {
        qWarning() << "[LRCLIB] At least one of 'query' or 'trackName' must be provided";
        emit lyricsFetched(false, "Invalid search parameters");
        return;
    }

    setLoading(true);
    
    QUrl url("https://lrclib.net/api/search");
    QUrlQuery urlQuery;
    
    if (!query.isEmpty()) {
        urlQuery.addQueryItem("q", query);
    }
    if (!trackName.isEmpty()) {
        urlQuery.addQueryItem("track_name", trackName);
    }
    if (!artistName.isEmpty()) {
        urlQuery.addQueryItem("artist_name", artistName);
    }
    if (!albumName.isEmpty()) {
        urlQuery.addQueryItem("album_name", albumName);
    }
    
    url.setQuery(urlQuery);

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader, 
                     "s3rp3nt_media v0.1 (https://github.com/s3rp3nt/s3rp3nt_media)");
    
    qDebug() << "[LRCLIB] Searching lyrics:" << url.toString();
    m_networkManager->get(request);
}

void LRCLibClient::onReplyFinished(QNetworkReply *reply)
{
    setLoading(false);
    
    if (reply->error() != QNetworkReply::NoError) {
        qWarning() << "[LRCLIB] Network error:" << reply->errorString();
        // Clear lyrics on network error to prevent showing old lyrics
        setSyncedLyrics("");
        setPlainLyrics("");
        m_lyricLines.clear();
        emit lyricLinesChanged();
        emit lyricsFetched(false, reply->errorString());
        reply->deleteLater();
        return;
    }

    QByteArray data = reply->readAll();
    QString urlString = reply->url().toString();
    
    reply->deleteLater();

    // Check if this is a search request
    if (urlString.contains("/api/search")) {
        parseSearchResponse(data);
    } else {
        parseLyricsResponse(data);
    }
}

void LRCLibClient::parseLyricsResponse(const QByteArray &data)
{
    QJsonParseError error;
    QJsonDocument doc = QJsonDocument::fromJson(data, &error);
    
    if (error.error != QJsonParseError::NoError) {
        qWarning() << "[LRCLIB] JSON parse error:" << error.errorString();
        emit lyricsFetched(false, "Failed to parse response");
        return;
    }

    QJsonObject obj = doc.object();
    
    // Check for error response
    if (obj.contains("code") && obj["code"].toInt() == 404) {
        qDebug() << "[LRCLIB] Lyrics not found";
        setSyncedLyrics("");
        setPlainLyrics("");
        m_lyricLines.clear();
        emit lyricLinesChanged();
        emit lyricsFetched(false, "Lyrics not found");
        return;
    }

    // Extract lyrics
    QString synced = obj["syncedLyrics"].toString();
    QString plain = obj["plainLyrics"].toString();
    bool instrumental = obj["instrumental"].toBool(false);

    if (instrumental) {
        qDebug() << "[LRCLIB] Track is instrumental";
        setSyncedLyrics("");
        setPlainLyrics("");
        m_lyricLines.clear();
        emit lyricLinesChanged();
        emit lyricsFetched(false, "Track is instrumental");
        return;
    }

    setSyncedLyrics(synced);
    setPlainLyrics(plain);

    // Parse synced lyrics into lines
    if (!synced.isEmpty()) {
        m_lyricLines = parseLRCLines(synced);
        emit lyricLinesChanged();
    } else {
        m_lyricLines.clear();
        emit lyricLinesChanged();
    }

    qDebug() << "[LRCLIB] Lyrics fetched successfully. Lines:" << m_lyricLines.size();
    emit lyricsFetched(true);
}

void LRCLibClient::parseSearchResponse(const QByteArray &data)
{
    QJsonParseError error;
    QJsonDocument doc = QJsonDocument::fromJson(data, &error);
    
    if (error.error != QJsonParseError::NoError) {
        qWarning() << "[LRCLIB] JSON parse error:" << error.errorString();
        emit lyricsFetched(false, "Failed to parse search response");
        return;
    }

    QJsonArray array = doc.array();
    QVariantList results;

    // If this was called from fetchLyrics (has search parameters), find best match and extract lyrics
    if (!m_searchTrackName.isEmpty()) {
        QJsonObject bestMatch;
        int bestScore = -1;
        
        // Find the best matching result
        for (const QJsonValue &value : array) {
            QJsonObject obj = value.toObject();
            QString resultTrack = obj["trackName"].toString();
            QString resultArtist = obj["artistName"].toString();
            QString resultAlbum = obj["albumName"].toString();
            
            // Calculate match score
            int score = 0;
            if (resultTrack.compare(m_searchTrackName, Qt::CaseInsensitive) == 0) {
                score += 100;  // Exact track match
            }
            if (!m_searchAlbumName.isEmpty() && resultAlbum.compare(m_searchAlbumName, Qt::CaseInsensitive) == 0) {
                score += 50;  // Exact album match
            }
            // Only check artist match if we're not retrying without artist
            if (!m_retryingWithoutArtist && !m_searchArtistName.isEmpty()) {
                // Check if any artist in the result matches (handle multiple artists)
                QStringList searchArtists = m_searchArtistName.split(",", Qt::SkipEmptyParts);
                QStringList resultArtists = resultArtist.split(",", Qt::SkipEmptyParts);
                for (const QString &searchArtist : searchArtists) {
                    for (const QString &resultArtistName : resultArtists) {
                        if (resultArtistName.trimmed().compare(searchArtist.trimmed(), Qt::CaseInsensitive) == 0) {
                            score += 25;  // Artist match
                            break;
                        }
                    }
                }
            }
            
            if (score > bestScore) {
                bestScore = score;
                bestMatch = obj;
            }
        }
        
        // Don't clear search parameters yet if we're going to retry
        
        if (bestScore >= 0 && !bestMatch.isEmpty()) {
            // Found a match - clear search parameters
            m_searchTrackName.clear();
            m_searchArtistName.clear();
            m_searchAlbumName.clear();
            m_retryingWithoutArtist = false;
            // Extract lyrics from best match
            QString synced = bestMatch["syncedLyrics"].toString();
            QString plain = bestMatch["plainLyrics"].toString();
            bool instrumental = bestMatch["instrumental"].toBool(false);
            
            if (instrumental) {
                qDebug() << "[LRCLIB] Best match is instrumental";
                setSyncedLyrics("");
                setPlainLyrics("");
                m_lyricLines.clear();
                emit lyricLinesChanged();
                emit lyricsFetched(false, "Track is instrumental");
                return;
            }
            
            setSyncedLyrics(synced);
            setPlainLyrics(plain);
            
            // Parse synced lyrics into lines
            if (!synced.isEmpty()) {
                m_lyricLines = parseLRCLines(synced);
                emit lyricLinesChanged();
            } else {
                m_lyricLines.clear();
                emit lyricLinesChanged();
            }
            
            qDebug() << "[LRCLIB] Lyrics fetched successfully from search. Lines:" << m_lyricLines.size();
            emit lyricsFetched(true);
            return;
        } else {
            // No results found - if we haven't retried without artist, try again
            if (!m_retryingWithoutArtist && !m_searchArtistName.isEmpty()) {
                qDebug() << "[LRCLIB] No results with artist, retrying without artist name";
                m_retryingWithoutArtist = true;
                
                // Retry search without artist name
                QUrl url("https://lrclib.net/api/search");
                QUrlQuery query;
                query.addQueryItem("track_name", m_searchTrackName);
                // Don't include artist_name this time
                if (!m_searchAlbumName.isEmpty()) {
                    query.addQueryItem("album_name", m_searchAlbumName);
                }
                url.setQuery(query);
                
                QNetworkRequest request(url);
                request.setHeader(QNetworkRequest::UserAgentHeader, 
                                 "s3rp3nt_media v0.1 (https://github.com/s3rp3nt/s3rp3nt_media)");
                
                qDebug() << "[LRCLIB] Retrying search without artist:" << url.toString();
                setLoading(true);
                m_networkManager->get(request);
                return;  // Don't clear search parameters yet - wait for retry response
            }
            
            // No results even after retry, or already retried
            qDebug() << "[LRCLIB] No matching results found in search (after retry if applicable)";
            // Clear search parameters
            m_searchTrackName.clear();
            m_searchArtistName.clear();
            m_searchAlbumName.clear();
            m_retryingWithoutArtist = false;
            setSyncedLyrics("");
            setPlainLyrics("");
            m_lyricLines.clear();
            emit lyricLinesChanged();
            emit lyricsFetched(false, "No matching lyrics found");
            return;
        }
    }
    
    // Otherwise, this was called from searchLyrics() - return results as before
    for (const QJsonValue &value : array) {
        QJsonObject obj = value.toObject();
        QVariantMap result;
        result["id"] = obj["id"].toInt();
        result["trackName"] = obj["trackName"].toString();
        result["artistName"] = obj["artistName"].toString();
        result["albumName"] = obj["albumName"].toString();
        result["duration"] = obj["duration"].toInt();
        result["instrumental"] = obj["instrumental"].toBool(false);
        results.append(result);
    }

    qDebug() << "[LRCLIB] Search returned" << results.size() << "results";
    emit searchResultsReceived(results);
    emit lyricsFetched(true);
}

QVariantList LRCLibClient::parseLRCLines(const QString &lrcText)
{
    QVariantList lines;
    
    if (lrcText.isEmpty()) {
        return lines;
    }

    // LRC format: [mm:ss.xx] or [mm:ss.xxx] text
    // Example: [00:17.12] I feel your breath upon my neck
    // Can also have multiple timestamps: [00:17.12][00:20.45]text
    QRegularExpression regex(R"(\[(\d{2}):(\d{2})\.(\d{2,3})\])");
    
    QStringList lrcLines = lrcText.split('\n', Qt::SkipEmptyParts);
    
    for (const QString &line : lrcLines) {
        // Find all timestamps in the line
        QRegularExpressionMatchIterator matches = regex.globalMatch(line);
        QString text = line;
        
        // Remove all timestamp markers to get the text
        text = text.remove(regex);
        text = text.trimmed();
        
        if (text.isEmpty()) {
            continue;
        }
        
        // Process each timestamp found (one line can have multiple timestamps)
        while (matches.hasNext()) {
            QRegularExpressionMatch match = matches.next();
            int minutes = match.captured(1).toInt();
            int seconds = match.captured(2).toInt();
            QString millisecondsStr = match.captured(3);
            
            // Convert to milliseconds
            int milliseconds = millisecondsStr.length() == 2 
                ? millisecondsStr.toInt() * 10  // [mm:ss.xx] -> centiseconds
                : millisecondsStr.toInt();      // [mm:ss.xxx] -> milliseconds
            
            qint64 timestamp = (minutes * 60 + seconds) * 1000 + milliseconds;
            
            QVariantMap lineData;
            lineData["timestamp"] = timestamp;
            lineData["text"] = text;
            lines.append(lineData);
        }
    }
    
    // Sort by timestamp
    std::sort(lines.begin(), lines.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap()["timestamp"].toLongLong() < b.toMap()["timestamp"].toLongLong();
    });

    return lines;
}

QString LRCLibClient::getCurrentLyricLine(qint64 positionMs) const
{
    if (m_lyricLines.isEmpty()) {
        return "";
    }

    // Find the last line that hasn't passed yet
    for (int i = m_lyricLines.size() - 1; i >= 0; --i) {
        QVariantMap line = m_lyricLines[i].toMap();
        qint64 timestamp = line["timestamp"].toLongLong();
        
        if (positionMs >= timestamp) {
            return line["text"].toString();
        }
    }

    return "";
}

void LRCLibClient::clearLyrics()
{
    setSyncedLyrics("");
    setPlainLyrics("");
    m_lyricLines.clear();
    emit lyricLinesChanged();
}

int LRCLibClient::getCurrentLyricLineIndex(qint64 positionMs) const
{
    if (m_lyricLines.isEmpty()) {
        return -1;
    }

    // Find the last line that hasn't passed yet
    for (int i = m_lyricLines.size() - 1; i >= 0; --i) {
        QVariantMap line = m_lyricLines[i].toMap();
        qint64 timestamp = line["timestamp"].toLongLong();
        
        if (positionMs >= timestamp) {
            return i;
        }
    }

    return -1;
}

QString LRCLibClient::urlEncode(const QString &str) const
{
    return QUrl::toPercentEncoding(str);
}

void LRCLibClient::setSyncedLyrics(const QString &lyrics)
{
    if (m_syncedLyrics != lyrics) {
        m_syncedLyrics = lyrics;
        emit syncedLyricsChanged();
    }
}

void LRCLibClient::setPlainLyrics(const QString &lyrics)
{
    if (m_plainLyrics != lyrics) {
        m_plainLyrics = lyrics;
        emit plainLyricsChanged();
    }
}

void LRCLibClient::setLoading(bool loading)
{
    if (m_loading != loading) {
        m_loading = loading;
        emit loadingChanged();
    }
}

