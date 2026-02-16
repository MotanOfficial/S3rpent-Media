#include "lrclibclient.h"
#include <QNetworkRequest>
#include <QUrlQuery>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QRegularExpression>
#include <QDebug>

namespace {
constexpr const char kReplySignatureProperty[] = "lrclibRequestSignature";
constexpr const char kReplyAutoFetchProperty[] = "lrclibAutoFetch";

QString statusToString(LRCLibClient::Status status)
{
    switch (status) {
    case LRCLibClient::StatusIdle: return "idle";
    case LRCLibClient::StatusSearching: return "searching";
    case LRCLibClient::StatusLoaded: return "loaded";
    case LRCLibClient::StatusNoMatch: return "no_match";
    case LRCLibClient::StatusNetworkError: return "network_error";
    case LRCLibClient::StatusParseError: return "parse_error";
    case LRCLibClient::StatusInstrumental: return "instrumental";
    case LRCLibClient::StatusInvalidRequest: return "invalid_request";
    }
    return "unknown";
}
}

LRCLibClient::LRCLibClient(QObject *parent)
    : QObject(parent)
    , m_networkManager(new QNetworkAccessManager(this))
    , m_loading(false)
    , m_lyricLines()
    , m_lastStatus(StatusIdle)
    , m_currentSearchMode(SearchWithArtist)
    , m_activeRequestSignature()
{
    m_lastStatusInfo = {
        { "status", static_cast<int>(m_lastStatus) },
        { "statusName", statusToString(m_lastStatus) }
    };
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
        updateStatus(StatusInvalidRequest, "Track name is required");
        emit lyricsFetched(false, "Invalid parameters");
        return;
    }

    // Store search parameters to match results
    m_searchTrackName = trackName;
    m_searchArtistName = artistName;
    m_searchAlbumName = albumName;

    const QString requestSignature = buildRequestSignature(trackName, artistName, albumName);
    m_activeRequestSignature = requestSignature;
    m_currentSearchMode = SearchWithArtist;
    sendSearchRequest(m_currentSearchMode);
}

void LRCLibClient::fetchLyricsCached(const QString &trackName, const QString &artistName, 
                                     const QString &albumName, int durationSeconds)
{
    if (trackName.isEmpty() || artistName.isEmpty() || albumName.isEmpty()) {
        qWarning() << "[LRCLIB] Invalid parameters for fetchLyricsCached";
        updateStatus(StatusInvalidRequest, "Track, artist and album are required for cached fetch");
        emit lyricsFetched(false, "Invalid parameters");
        return;
    }

    const QString requestSignature = buildRequestSignature(trackName, artistName, albumName);
    m_activeRequestSignature = requestSignature;
    updateStatus(StatusSearching, "Fetching cached lyrics",
                 { { "track", trackName }, { "artist", artistName }, { "album", albumName } });
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
                     "s3rpent_media v0.1 (https://github.com/s3rpent/s3rpent_media)");
    
    qDebug() << "[LRCLIB] Fetching cached lyrics:" << url.toString();
    QNetworkReply *reply = m_networkManager->get(request);
    tagReplyWithSignature(reply, requestSignature, true);
}

void LRCLibClient::fetchLyricsById(int id)
{
    if (id <= 0) {
        qWarning() << "[LRCLIB] Invalid ID for fetchLyricsById";
        updateStatus(StatusInvalidRequest, "Invalid lyrics ID");
        emit lyricsFetched(false, "Invalid ID");
        return;
    }

    const QString requestSignature = QStringLiteral("id:%1").arg(id);
    m_activeRequestSignature = requestSignature;
    updateStatus(StatusSearching, "Fetching lyrics by ID", { { "id", id } });
    setLoading(true);
    
    QUrl url(QString("https://lrclib.net/api/get/%1").arg(id));

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader, 
                     "s3rpent_media v0.1 (https://github.com/s3rpent/s3rpent_media)");
    
    qDebug() << "[LRCLIB] Fetching lyrics by ID:" << url.toString();
    QNetworkReply *reply = m_networkManager->get(request);
    tagReplyWithSignature(reply, requestSignature, true);
}

void LRCLibClient::searchLyrics(const QString &query, const QString &trackName, 
                                const QString &artistName, const QString &albumName)
{
    if (query.isEmpty() && trackName.isEmpty()) {
        qWarning() << "[LRCLIB] At least one of 'query' or 'trackName' must be provided";
        updateStatus(StatusInvalidRequest, "Provide either a query or track name");
        emit lyricsFetched(false, "Invalid search parameters");
        return;
    }

    updateStatus(StatusSearching, "Searching lyrics (manual)",
                 { { "query", query }, { "track", trackName }, { "artist", artistName }, { "album", albumName } });
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
                     "s3rpent_media v0.1 (https://github.com/s3rpent/s3rpent_media)");
    
    qDebug() << "[LRCLIB] Searching lyrics:" << url.toString();
    QNetworkReply *reply = m_networkManager->get(request);
    tagReplyWithSignature(reply, QStringLiteral("search:%1|%2|%3|%4")
                                   .arg(query, trackName, artistName, albumName),
                          false);
}

void LRCLibClient::onReplyFinished(QNetworkReply *reply)
{
    if (shouldIgnoreReply(reply)) {
        qDebug() << "[LRCLIB] Ignoring stale lyrics reply";
        reply->deleteLater();
        return;
    }

    setLoading(false);
    
    if (reply->error() != QNetworkReply::NoError) {
        qWarning() << "[LRCLIB] Network error:" << reply->errorString();
        // Clear lyrics on network error to prevent showing old lyrics
        setSyncedLyrics("");
        setPlainLyrics("");
        m_lyricLines.clear();
        emit lyricLinesChanged();
        QVariantMap details {
            { "code", static_cast<int>(reply->error()) },
            { "url", reply->url().toString() }
        };
        updateStatus(StatusNetworkError, reply->errorString(), details);
        if (!m_searchTrackName.isEmpty()) {
            resetSearchState();
        }
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
        updateStatus(StatusParseError, error.errorString());
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
        updateStatus(StatusNoMatch, "Lyrics not found",
                     { { "track", obj["trackName"].toString() }, { "artist", obj["artistName"].toString() } });
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
        updateStatus(StatusInstrumental, "Track is instrumental",
                     { { "track", obj["trackName"].toString() } });
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
    updateStatus(StatusLoaded, "Lyrics loaded",
                 { { "track", obj["trackName"].toString() },
                   { "artist", obj["artistName"].toString() },
                   { "album", obj["albumName"].toString() } });
    emit lyricsFetched(true);
}

void LRCLibClient::parseSearchResponse(const QByteArray &data)
{
    QJsonParseError error;
    QJsonDocument doc = QJsonDocument::fromJson(data, &error);
    
    if (error.error != QJsonParseError::NoError) {
        qWarning() << "[LRCLIB] JSON parse error:" << error.errorString();
        if (!m_searchTrackName.isEmpty()) {
            resetSearchState();
        }
        emit lyricsFetched(false, "Failed to parse search response");
        return;
    }

    QJsonArray array = doc.array();
    QVariantList results;

    // If this was called from fetchLyrics (has search parameters), find best match and extract lyrics
    if (!m_searchTrackName.isEmpty()) {
        QJsonObject bestMatch;
        int bestScore = -1;
        
        const bool checkArtistMatch = (m_currentSearchMode == SearchWithArtist) && !m_searchArtistName.isEmpty();

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
            if (checkArtistMatch) {
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
            QVariantMap successDetails {
                { "track", bestMatch["trackName"].toString() },
                { "artist", bestMatch["artistName"].toString() },
                { "album", bestMatch["albumName"].toString() },
                { "attemptLabel", (m_currentSearchMode == SearchWithArtist) ? "track+artist"
                                 : (m_currentSearchMode == SearchWithoutArtist) ? "track-only"
                                 : "fallback-q" }
            };
            resetSearchState();
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
                updateStatus(StatusInstrumental, "Track is instrumental", successDetails);
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
            updateStatus(StatusLoaded, "Lyrics loaded", successDetails);
            emit lyricsFetched(true);
            return;
        } else {
            if (tryNextSearchAttempt()) {
                return;
            }
            
            qDebug() << "[LRCLIB] No matching results found after all attempts";
            QString failedTrack = m_searchTrackName;
            QString failedArtist = m_searchArtistName;
            QString failedAlbum = m_searchAlbumName;
            resetSearchState();
            setSyncedLyrics("");
            setPlainLyrics("");
            m_lyricLines.clear();
            emit lyricLinesChanged();
            updateStatus(StatusNoMatch, "No matching lyrics found",
                         { { "track", failedTrack }, { "artist", failedArtist }, { "album", failedAlbum } });
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
        if (results.isEmpty()) {
            updateStatus(StatusNoMatch, "No matching lyrics found (manual search)");
        } else {
            updateStatus(StatusLoaded, "Search results ready",
                         { { "results", results.size() } });
        }
        emit lyricsFetched(!results.isEmpty(), results.isEmpty() ? "No results" : "");
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
    m_activeRequestSignature.clear();
    setLoading(false);
    updateStatus(StatusIdle, "Lyrics cleared");
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

QString LRCLibClient::buildRequestSignature(const QString &trackName,
                                            const QString &artistName,
                                            const QString &albumName) const
{
    return trackName + "|" + artistName + "|" + albumName;
}

void LRCLibClient::tagReplyWithSignature(QNetworkReply *reply,
                                         const QString &signature,
                                         bool autoFetch) const
{
    if (!reply)
        return;

    reply->setProperty(kReplySignatureProperty, signature);
    reply->setProperty(kReplyAutoFetchProperty, autoFetch);
}

bool LRCLibClient::shouldIgnoreReply(QNetworkReply *reply) const
{
    if (!reply)
        return true;

    const bool autoFetch = reply->property(kReplyAutoFetchProperty).toBool();
    if (!autoFetch) {
        // Independent searches shouldn't be filtered
        return false;
    }

    const QString replySignature = reply->property(kReplySignatureProperty).toString();
    if (replySignature.isEmpty()) {
        return false;
    }

    if (m_activeRequestSignature.isEmpty()) {
        return true;
    }

    return replySignature != m_activeRequestSignature;
}

void LRCLibClient::sendSearchRequest(SearchAttemptMode mode)
{
    if (m_searchTrackName.isEmpty() && mode != SearchQueryFallback) {
        qWarning() << "[LRCLIB] Cannot start search attempt - track name missing";
        return;
    }

    setLoading(true);

    QUrl url("https://lrclib.net/api/search");
    QUrlQuery query;
    QString attemptLabel;

    switch (mode) {
    case SearchWithArtist:
        query.addQueryItem("track_name", m_searchTrackName);
        if (!m_searchArtistName.isEmpty()) {
            query.addQueryItem("artist_name", m_searchArtistName);
        }
        if (!m_searchAlbumName.isEmpty()) {
            query.addQueryItem("album_name", m_searchAlbumName);
        }
        attemptLabel = "track+artist";
        break;
    case SearchWithoutArtist:
        query.addQueryItem("track_name", m_searchTrackName);
        if (!m_searchAlbumName.isEmpty()) {
            query.addQueryItem("album_name", m_searchAlbumName);
        }
        attemptLabel = "track-only";
        break;
    case SearchQueryFallback: {
        QString q = m_searchTrackName;
        if (!m_searchAlbumName.isEmpty()) {
            q += " " + m_searchAlbumName;
        }
        if (q.trimmed().isEmpty()) {
            q = m_searchTrackName;
        }
        query.addQueryItem("q", q.trimmed());
        if (!m_searchTrackName.isEmpty()) {
            query.addQueryItem("track_name", m_searchTrackName);
        }
        if (!m_searchAlbumName.isEmpty()) {
            query.addQueryItem("album_name", m_searchAlbumName);
        }
        attemptLabel = "fallback-q";
        break;
    }
    }

    url.setQuery(query);

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader, 
                     "s3rpent_media v0.1 (https://github.com/s3rpent/s3rpent_media)");

    const int attemptNumber = static_cast<int>(mode) + 1;
    QVariantMap details {
        { "track", m_searchTrackName },
        { "artist", m_searchArtistName },
        { "album", m_searchAlbumName },
        { "attempt", attemptNumber },
        { "attemptLabel", attemptLabel }
    };
    updateStatus(StatusSearching, "Searching lyrics", details);
    qDebug() << "[LRCLIB] Searching lyrics (attempt" << attemptNumber << "-" << attemptLabel << "):" << url.toString();
    QNetworkReply *reply = m_networkManager->get(request);
    tagReplyWithSignature(reply, m_activeRequestSignature, true);
}

bool LRCLibClient::tryNextSearchAttempt()
{
    if (m_currentSearchMode == SearchQueryFallback) {
        return false;
    }

    if (m_currentSearchMode == SearchWithArtist) {
        m_currentSearchMode = SearchWithoutArtist;
    } else if (m_currentSearchMode == SearchWithoutArtist) {
        m_currentSearchMode = SearchQueryFallback;
    } else {
        return false;
    }

    sendSearchRequest(m_currentSearchMode);
    return true;
}

void LRCLibClient::resetSearchState()
{
    m_searchTrackName.clear();
    m_searchArtistName.clear();
    m_searchAlbumName.clear();
    m_currentSearchMode = SearchWithArtist;
    m_activeRequestSignature.clear();
}

void LRCLibClient::updateStatus(Status status,
                                const QString &message,
                                const QVariantMap &details)
{
    QVariantMap info = details;
    info["status"] = static_cast<int>(status);
    info["statusName"] = statusToString(status);
    if (!message.isEmpty()) {
        info["message"] = message;
    } else if (!info.contains("message")) {
        info["message"] = "";
    }

    if (m_lastStatus != status || m_lastStatusInfo != info) {
        m_lastStatus = status;
        m_lastStatusInfo = info;
        emit lastStatusChanged();
    }
}
