#include "lastfmclient.h"
#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QUrlQuery>
#include <QRegularExpression>

LastFMClient::LastFMClient(QObject *parent)
    : QObject(parent)
    , m_loading(false)
    , m_lastError("")
    , m_apiKey("")
    , m_hasTriedFirstArtistOnly(false)
{
    m_networkManager = new QNetworkAccessManager(this);
}

LastFMClient::~LastFMClient()
{
}

void LastFMClient::fetchCoverArt(const QString &trackName, const QString &artistName, const QString &apiKey)
{
    if (trackName.isEmpty() || artistName.isEmpty()) {
        qDebug() << "[LastFM] Missing track name or artist name";
        setLastError("Missing track or artist name");
        emit coverArtNotFound();
        return;
    }

    // Use provided API key or default public key
    m_apiKey = apiKey.isEmpty() ? "b25b959554ed76058ac220b7b2e0a026" : apiKey;  // Default public key for testing

    setLoading(true);
    setLastError("");

    // Store current search parameters
    m_currentTrackName = trackName;
    m_currentArtistName = artistName;
    m_hasTriedFirstArtistOnly = false;  // Reset flag for new search

    // Clean artist name - normalize separators (same as lyrics fetching)
    QString cleanedArtistName = artistName;
    // Replace semicolons with commas
    cleanedArtistName.replace(";", ",");
    // Normalize ampersands
    cleanedArtistName.replace(" &amp; ", ", ");
    cleanedArtistName.replace(" & ", ", ");
    // Clean up extra spaces
    cleanedArtistName.replace(QRegularExpression("\\s+"), " ");
    cleanedArtistName.replace(QRegularExpression(",\\s*,"), ",");
    cleanedArtistName.replace(QRegularExpression(",\\s+"), ", ");
    cleanedArtistName.replace(QRegularExpression("\\s+,"), ",");
    cleanedArtistName = cleanedArtistName.trimmed();
    
    if (cleanedArtistName != artistName) {
        qDebug() << "[LastFM] Cleaned artist name:" << artistName << "->" << cleanedArtistName;
    }

    // Step 1: Try track.getInfo first
    QUrl url("https://ws.audioscrobbler.com/2.0/");
    QUrlQuery query;
    query.addQueryItem("method", "track.getInfo");
    query.addQueryItem("api_key", m_apiKey);
    query.addQueryItem("artist", cleanedArtistName);
    query.addQueryItem("track", trackName);
    query.addQueryItem("format", "json");
    query.addQueryItem("autocorrect", "1");  // Auto-correct misspellings
    url.setQuery(query);

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader, 
                     "s3rpent_media/0.1 (https://github.com/s3rpent/s3rpent_media)");

    qDebug() << "[LastFM] Step 1: Fetching track.getInfo from Last.fm API:" << url.toString();

    QNetworkReply *reply = m_networkManager->get(request);
    reply->setProperty("requestType", "trackgetinfo");
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        onLastFMReplyFinished(reply);
    });
}

void LastFMClient::onLastFMReplyFinished(QNetworkReply *reply)
{
    QString requestType = reply->property("requestType").toString();
    
    if (reply->error() != QNetworkReply::NoError) {
        // If track.getInfo failed, try track.search as fallback
        if (requestType == "trackgetinfo") {
            qDebug() << "[LastFM] track.getInfo failed, trying track.search...";
            reply->deleteLater();
            searchTrack(m_currentTrackName, m_currentArtistName);
            return;
        }
        qWarning() << "[LastFM] Last.fm API error:" << reply->errorString();
        setLoading(false);
        setLastError(reply->errorString());
        emit coverArtNotFound();
        reply->deleteLater();
        return;
    }

    QByteArray data = reply->readAll();
    reply->deleteLater();

    QString coverArtUrl = extractCoverArtUrlFromResponse(data);
    
    if (!coverArtUrl.isEmpty()) {
        qDebug() << "[LastFM] Found cover art URL from track.getInfo:" << coverArtUrl;
        setLoading(false);
        emit coverArtFound(coverArtUrl);
    } else {
        // No album in track.getInfo, try track.search to find album name
        qDebug() << "[LastFM] No album in track.getInfo, trying track.search...";
        searchTrack(m_currentTrackName, m_currentArtistName);
    }
}

QString LastFMClient::extractCoverArtUrlFromResponse(const QByteArray &data)
{
    QJsonParseError error;
    QJsonDocument doc = QJsonDocument::fromJson(data, &error);
    
    if (error.error != QJsonParseError::NoError) {
        qWarning() << "[LastFM] JSON parse error:" << error.errorString();
        return QString();
    }

    QJsonObject root = doc.object();
    
    // Check for error
    if (root.contains("error")) {
        int errorCode = root.value("error").toInt();
        QString errorMessage = root.value("message").toString();
        qWarning() << "[LastFM] Last.fm API error:" << errorCode << errorMessage;
        setLastError(QString("Last.fm API error %1: %2").arg(errorCode).arg(errorMessage));
        return QString();
    }

    QJsonObject track = root.value("track").toObject();
    if (track.isEmpty()) {
        qDebug() << "[LastFM] No track object in response";
        return QString();
    }

    QJsonObject album = track.value("album").toObject();
    if (album.isEmpty()) {
        qDebug() << "[LastFM] No album object in track";
        return QString();
    }

    QJsonArray images = album.value("image").toArray();
    if (images.isEmpty()) {
        qDebug() << "[LastFM] No images in album";
        return QString();
    }

    // Last.fm provides images in order: small, medium, large, extralarge, mega
    // We want "large" or "extralarge" for Discord (500px is good)
    QString coverArtUrl;
    
    // Try to find "large" first (usually ~300-500px)
    for (const QJsonValue &value : images) {
        QJsonObject image = value.toObject();
        QString size = image.value("size").toString();
        QString url = image.value("#text").toString();
        
        if (size == "large" && !url.isEmpty()) {
            coverArtUrl = url;
            break;
        }
    }
    
    // If no "large", try "extralarge" (usually ~500-600px)
    if (coverArtUrl.isEmpty()) {
        for (const QJsonValue &value : images) {
            QJsonObject image = value.toObject();
            QString size = image.value("size").toString();
            QString url = image.value("#text").toString();
            
            if (size == "extralarge" && !url.isEmpty()) {
                coverArtUrl = url;
                break;
            }
        }
    }
    
    // If still no URL, try "medium" as fallback
    if (coverArtUrl.isEmpty()) {
        for (const QJsonValue &value : images) {
            QJsonObject image = value.toObject();
            QString size = image.value("size").toString();
            QString url = image.value("#text").toString();
            
            if (size == "medium" && !url.isEmpty()) {
                coverArtUrl = url;
                break;
            }
        }
    }

    return coverArtUrl;
}

void LastFMClient::setLoading(bool loading)
{
    if (m_loading != loading) {
        m_loading = loading;
        emit loadingChanged();
    }
}

void LastFMClient::searchTrack(const QString &trackName, const QString &artistName)
{
    // Clean artist name
    QString cleanedArtistName = artistName;
    cleanedArtistName.replace(";", ",");
    cleanedArtistName.replace(" &amp; ", ", ");
    cleanedArtistName.replace(" & ", ", ");
    cleanedArtistName.replace(QRegularExpression("\\s+"), " ");
    cleanedArtistName.replace(QRegularExpression(",\\s*,"), ",");
    cleanedArtistName.replace(QRegularExpression(",\\s+"), ", ");
    cleanedArtistName.replace(QRegularExpression("\\s+,"), ",");
    cleanedArtistName = cleanedArtistName.trimmed();

    // Step 2: Use track.search to find the track and get album info
    QUrl url("https://ws.audioscrobbler.com/2.0/");
    QUrlQuery query;
    query.addQueryItem("method", "track.search");
    query.addQueryItem("api_key", m_apiKey);
    query.addQueryItem("track", trackName);
    query.addQueryItem("artist", cleanedArtistName);
    query.addQueryItem("limit", "5");  // Get top 5 results
    query.addQueryItem("format", "json");
    url.setQuery(query);

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader, 
                     "s3rpent_media/0.1 (https://github.com/s3rpent/s3rpent_media)");

    qDebug() << "[LastFM] Step 2: Searching tracks from Last.fm API:" << url.toString();

    QNetworkReply *reply = m_networkManager->get(request);
    reply->setProperty("requestType", "tracksearch");
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        onTrackSearchReplyFinished(reply);
    });
}

void LastFMClient::onTrackSearchReplyFinished(QNetworkReply *reply)
{
    if (reply->error() != QNetworkReply::NoError) {
        qWarning() << "[LastFM] track.search error:" << reply->errorString();
        setLoading(false);
        setLastError("Track search failed");
        emit coverArtNotFound();
        reply->deleteLater();
        return;
    }

    QByteArray data = reply->readAll();
    reply->deleteLater();

    QString albumName = extractAlbumNameFromTrackSearch(data);
    
    if (!albumName.isEmpty()) {
        qDebug() << "[LastFM] Found album name from track.search:" << albumName;
        // Step 3: Fetch album info to get cover art
        fetchAlbumInfo(m_currentArtistName, albumName);
    } else {
        // If track.search didn't work, try album.search as fallback
        qDebug() << "[LastFM] No album found in track.search, trying album.search...";
        searchAlbum(m_currentArtistName, m_currentTrackName);
    }
}

QString LastFMClient::extractAlbumNameFromTrackSearch(const QByteArray &data)
{
    QJsonParseError error;
    QJsonDocument doc = QJsonDocument::fromJson(data, &error);
    
    if (error.error != QJsonParseError::NoError) {
        qWarning() << "[LastFM] JSON parse error in track.search:" << error.errorString();
        return QString();
    }

    QJsonObject root = doc.object();
    
    // Check for error
    if (root.contains("error")) {
        int errorCode = root.value("error").toInt();
        QString errorMessage = root.value("message").toString();
        qWarning() << "[LastFM] Last.fm API error:" << errorCode << errorMessage;
        return QString();
    }

    QJsonObject results = root.value("results").toObject();
    QJsonObject trackMatches = results.value("trackmatches").toObject();
    
    // track.search can return a single object or an array
    QJsonValue trackValue = trackMatches.value("track");
    QJsonArray tracks;
    
    if (trackValue.isArray()) {
        tracks = trackValue.toArray();
    } else if (trackValue.isObject()) {
        tracks.append(trackValue);
    } else {
        qDebug() << "[LastFM] No tracks found in search results";
        return QString();
    }
    
    if (tracks.isEmpty()) {
        qDebug() << "[LastFM] No tracks found in search results";
        return QString();
    }

    // Try all tracks to find one with an album
    for (const QJsonValue &trackVal : tracks) {
        QJsonObject track = trackVal.toObject();
        QString albumName = track.value("album").toString();
        
        if (!albumName.isEmpty()) {
            qDebug() << "[LastFM] Extracted album name from track.search:" << albumName;
            return albumName;
        }
    }
    
    // If no album found in search results, try using track name as album name
    // (common for singles where track name = album name)
    qDebug() << "[LastFM] No album in track.search, trying track name as album name";
    return m_currentTrackName;
}

QString LastFMClient::cleanArtistName(const QString &artistName)
{
    QString cleaned = artistName;
    cleaned.replace(";", ",");
    cleaned.replace(" &amp; ", ", ");
    cleaned.replace(" & ", ", ");
    cleaned.replace(QRegularExpression("\\s+"), " ");
    cleaned.replace(QRegularExpression(",\\s*,"), ",");
    cleaned.replace(QRegularExpression(",\\s+"), ", ");
    cleaned.replace(QRegularExpression("\\s+,"), ",");
    return cleaned.trimmed();
}

void LastFMClient::fetchAlbumInfo(const QString &artistName, const QString &albumName)
{
    QString cleanedArtistName = cleanArtistName(artistName);

    // Step 3: Use album.getInfo to get cover art
    QUrl url("https://ws.audioscrobbler.com/2.0/");
    QUrlQuery query;
    query.addQueryItem("method", "album.getInfo");
    query.addQueryItem("api_key", m_apiKey);
    query.addQueryItem("artist", cleanedArtistName);
    query.addQueryItem("album", albumName);
    query.addQueryItem("format", "json");
    query.addQueryItem("autocorrect", "1");
    url.setQuery(query);

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader, 
                     "s3rpent_media/0.1 (https://github.com/s3rpent/s3rpent_media)");

    qDebug() << "[LastFM] Step 3: Fetching album.getInfo from Last.fm API:" << url.toString();

    QNetworkReply *reply = m_networkManager->get(request);
    reply->setProperty("requestType", "albuminfo");
    reply->setProperty("requestArtist", cleanedArtistName);  // Store the artist used in this request
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        onAlbumInfoReplyFinished(reply);
    });
}

void LastFMClient::searchAlbum(const QString &artistName, const QString &albumName)
{
    QString cleanedArtistName = cleanArtistName(artistName);

    // Step 3b: Use album.search to find the album
    QUrl url("https://ws.audioscrobbler.com/2.0/");
    QUrlQuery query;
    query.addQueryItem("method", "album.search");
    query.addQueryItem("api_key", m_apiKey);
    query.addQueryItem("album", albumName);
    query.addQueryItem("artist", cleanedArtistName);
    query.addQueryItem("limit", "5");
    query.addQueryItem("format", "json");
    url.setQuery(query);

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader, 
                     "s3rpent_media/0.1 (https://github.com/s3rpent/s3rpent_media)");

    qDebug() << "[LastFM] Step 3b: Searching albums from Last.fm API:" << url.toString();

    QNetworkReply *reply = m_networkManager->get(request);
    reply->setProperty("requestType", "albumsearch");
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        onAlbumInfoReplyFinished(reply);
    });
}

void LastFMClient::onAlbumInfoReplyFinished(QNetworkReply *reply)
{
    QString requestType = reply->property("requestType").toString();
    QString requestArtist = reply->property("requestArtist").toString();  // Store before deleting
    
    if (reply->error() != QNetworkReply::NoError) {
        // If album.getInfo failed and we haven't tried album.search yet, try it
        if (requestType == "albuminfo") {
            qDebug() << "[LastFM] album.getInfo failed, trying album.search...";
            reply->deleteLater();
            searchAlbum(m_currentArtistName, m_currentTrackName);
            return;
        }
        qWarning() << "[LastFM] Album API error:" << reply->errorString();
        setLoading(false);
        setLastError("Album info fetch failed");
        emit coverArtNotFound();
        reply->deleteLater();
        return;
    }

    QByteArray data = reply->readAll();
    reply->deleteLater();

    // Handle album.search response
    if (requestType == "albumsearch") {
        QJsonParseError error;
        QJsonDocument doc = QJsonDocument::fromJson(data, &error);
        
        if (error.error == QJsonParseError::NoError) {
            QJsonObject root = doc.object();
            QJsonObject results = root.value("results").toObject();
            QJsonObject albumMatches = results.value("albummatches").toObject();
            
            QJsonValue albumValue = albumMatches.value("album");
            QJsonArray albums;
            
            if (albumValue.isArray()) {
                albums = albumValue.toArray();
            } else if (albumValue.isObject()) {
                albums.append(albumValue);
            }
            
            if (!albums.isEmpty()) {
                // Get the first matching album and try to fetch its info
                QJsonObject firstAlbum = albums.first().toObject();
                QString foundAlbumName = firstAlbum.value("name").toString();
                QString foundArtistName = firstAlbum.value("artist").toString();
                
                if (!foundAlbumName.isEmpty()) {
                    qDebug() << "[LastFM] Found album from album.search:" << foundAlbumName << "by" << foundArtistName;
                    // Try to get album info with the found names
                    fetchAlbumInfo(foundArtistName.isEmpty() ? m_currentArtistName : foundArtistName, foundAlbumName);
                    return;
                }
            }
        }
        
        // If album.search didn't work, give up
        qDebug() << "[LastFM] No album found via album.search";
        setLoading(false);
        setLastError("No album found");
        emit coverArtNotFound();
        return;
    }

    // Handle album.getInfo response
    QString coverArtUrl = extractCoverArtUrlFromAlbumInfo(data);
    
    if (!coverArtUrl.isEmpty()) {
        qDebug() << "[LastFM] Found cover art URL from album.getInfo:" << coverArtUrl;
        setLoading(false);
        emit coverArtFound(coverArtUrl);
    } else {
        // If no cover art found, try with just the first artist name (before comma)
        // This handles cases where Last.fm has the album under the main artist only
        // BUT: Only try this once to prevent infinite loops
        if (!m_hasTriedFirstArtistOnly && requestType == "albuminfo") {
            QString cleanedArtist = cleanArtistName(m_currentArtistName);
            QString firstArtist = cleanedArtist.split(",").first().trimmed();
            
            // Get the artist that was used in this request (stored before reply deletion)
            if (requestArtist.isEmpty()) {
                requestArtist = cleanArtistName(m_currentArtistName);
            }
            QString requestFirstArtist = requestArtist.split(",").first().trimmed();
            
            // Only try if:
            // 1. First artist is different from full artist name
            // 2. We haven't already tried with just the first artist
            // 3. The current request wasn't already using just the first artist (prevents infinite loop)
            if (firstArtist != cleanedArtist && !firstArtist.isEmpty() && requestArtist != requestFirstArtist) {
                qDebug() << "[LastFM] No cover art with full artist name, trying with first artist only:" << firstArtist;
                m_hasTriedFirstArtistOnly = true;  // Set flag to prevent infinite loop
                // Try again with just the first artist
                fetchAlbumInfo(firstArtist, m_currentTrackName);
                return;  // Exit early, will continue in next callback
            }
        }
        
        // If we've already tried first artist only, or it's the same, give up
        qDebug() << "[LastFM] No cover art found in album.getInfo (all attempts exhausted)";
        setLoading(false);
        setLastError("No cover art found");
        emit coverArtNotFound();
    }
}

QString LastFMClient::extractCoverArtUrlFromAlbumInfo(const QByteArray &data)
{
    QJsonParseError error;
    QJsonDocument doc = QJsonDocument::fromJson(data, &error);
    
    if (error.error != QJsonParseError::NoError) {
        qWarning() << "[LastFM] JSON parse error in album.getInfo:" << error.errorString();
        return QString();
    }

    QJsonObject root = doc.object();
    
    // Check for error
    if (root.contains("error")) {
        int errorCode = root.value("error").toInt();
        QString errorMessage = root.value("message").toString();
        qWarning() << "[LastFM] Last.fm API error:" << errorCode << errorMessage;
        return QString();
    }

    QJsonObject album = root.value("album").toObject();
    if (album.isEmpty()) {
        qDebug() << "[LastFM] No album object in album.getInfo response";
        return QString();
    }

    // Verify the track is in this album's tracklist
    QJsonObject tracksObj = album.value("tracks").toObject();
    QJsonArray tracks = tracksObj.value("track").toArray();
    bool trackFound = false;
    
    if (!tracks.isEmpty()) {
        QString searchTrackName = m_currentTrackName.toLower().trimmed();
        for (const QJsonValue &trackVal : tracks) {
            QJsonObject track = trackVal.toObject();
            QString trackName = track.value("name").toString().toLower().trimmed();
            
            if (trackName == searchTrackName || trackName.contains(searchTrackName) || searchTrackName.contains(trackName)) {
                trackFound = true;
                qDebug() << "[LastFM] Verified track is in album tracklist:" << track.value("name").toString();
                break;
            }
        }
        
        if (!trackFound) {
            qDebug() << "[LastFM] Track not found in album tracklist, might be wrong album";
        }
    } else {
        qDebug() << "[LastFM] No tracklist in album response";
    }

    // Get images - can be array or single object
    QJsonValue imageValue = album.value("image");
    QJsonArray images;
    
    if (imageValue.isArray()) {
        images = imageValue.toArray();
    } else if (imageValue.isObject()) {
        images.append(imageValue);
    }
    
    if (images.isEmpty()) {
        qDebug() << "[LastFM] No images array in album";
        return QString();
    }

    // Last.fm provides images in order: small, medium, large, extralarge, mega
    // We want "large" or "extralarge" for Discord (500px is good)
    QString coverArtUrl;
    
    // Try to find "large" first (usually ~300-500px)
    for (const QJsonValue &value : images) {
        QJsonObject image = value.toObject();
        QString size = image.value("size").toString();
        QString url = image.value("#text").toString();
        
        if (size == "large" && !url.isEmpty()) {
            coverArtUrl = url;
            qDebug() << "[LastFM] Found large image:" << url;
            break;
        }
    }
    
    // If no "large", try "extralarge" (usually ~500-600px)
    if (coverArtUrl.isEmpty()) {
        for (const QJsonValue &value : images) {
            QJsonObject image = value.toObject();
            QString size = image.value("size").toString();
            QString url = image.value("#text").toString();
            
            if (size == "extralarge" && !url.isEmpty()) {
                coverArtUrl = url;
                qDebug() << "[LastFM] Found extralarge image:" << url;
                break;
            }
        }
    }
    
    // If still no URL, try "mega" (largest size)
    if (coverArtUrl.isEmpty()) {
        for (const QJsonValue &value : images) {
            QJsonObject image = value.toObject();
            QString size = image.value("size").toString();
            QString url = image.value("#text").toString();
            
            if (size == "mega" && !url.isEmpty()) {
                coverArtUrl = url;
                qDebug() << "[LastFM] Found mega image:" << url;
                break;
            }
        }
    }
    
    // If still no URL, try "medium" as fallback
    if (coverArtUrl.isEmpty()) {
        for (const QJsonValue &value : images) {
            QJsonObject image = value.toObject();
            QString size = image.value("size").toString();
            QString url = image.value("#text").toString();
            
            if (size == "medium" && !url.isEmpty()) {
                coverArtUrl = url;
                qDebug() << "[LastFM] Found medium image:" << url;
                break;
            }
        }
    }
    
    // Last resort: try any non-empty image URL
    if (coverArtUrl.isEmpty()) {
        for (const QJsonValue &value : images) {
            QJsonObject image = value.toObject();
            QString url = image.value("#text").toString();
            
            if (!url.isEmpty()) {
                coverArtUrl = url;
                qDebug() << "[LastFM] Found fallback image:" << url;
                break;
            }
        }
    }
    
    if (coverArtUrl.isEmpty()) {
        qDebug() << "[LastFM] All image URLs in album are empty";
    }

    return coverArtUrl;
}

void LastFMClient::setLastError(const QString &error)
{
    if (m_lastError != error) {
        m_lastError = error;
        emit lastErrorChanged();
    }
}

