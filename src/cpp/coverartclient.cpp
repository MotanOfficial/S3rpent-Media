#include "coverartclient.h"
#include <QNetworkRequest>
#include <QUrlQuery>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDebug>

CoverArtClient::CoverArtClient(QObject *parent)
    : QObject(parent)
    , m_networkManager(new QNetworkAccessManager(this))
    , m_loading(false)
    , m_lastError("")
{
    connect(m_networkManager, &QNetworkAccessManager::finished,
            this, &CoverArtClient::onMusicBrainzReplyFinished);
}

CoverArtClient::~CoverArtClient()
{
}

void CoverArtClient::fetchCoverArt(const QString &trackName, const QString &artistName, 
                                   const QString &albumName)
{
    if (trackName.isEmpty()) {
        setLastError("Track name is required");
        emit coverArtError("Track name is required");
        return;
    }

    m_currentTrackName = trackName;
    m_currentArtistName = artistName;
    m_currentAlbumName = albumName;

    setLoading(true);
    setLastError("");

    // First, search MusicBrainz to get the MBID
    searchMusicBrainz(trackName, artistName, albumName);
}

void CoverArtClient::searchMusicBrainz(const QString &trackName, const QString &artistName, 
                                       const QString &albumName)
{
    // MusicBrainz search API - search for releases directly (better for cover art)
    QUrl url("https://musicbrainz.org/ws/2/release/");
    QUrlQuery query;
    
    // Build search query: recording title AND artist name
    QString searchQuery = QString("recording:\"%1\"").arg(trackName);
    if (!artistName.isEmpty()) {
        searchQuery += QString(" AND artist:\"%1\"").arg(artistName);
    }
    if (!albumName.isEmpty()) {
        searchQuery += QString(" AND release:\"%1\"").arg(albumName);
    }
    
    query.addQueryItem("query", searchQuery);
    query.addQueryItem("limit", "1");  // Only need the first result
    query.addQueryItem("fmt", "json");
    
    url.setQuery(query);

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader, 
                     "s3rpent_media/0.1 (https://github.com/s3rpent/s3rpent_media)");
    request.setRawHeader("Accept", "application/json");

    qDebug() << "[CoverArt] Searching MusicBrainz for:" << trackName << "-" << artistName;
    
    QNetworkReply *reply = m_networkManager->get(request);
    reply->setProperty("requestType", "musicbrainz");
}

void CoverArtClient::fetchFromCoverArtArchive(const QString &mbid, bool isReleaseGroup)
{
    if (mbid.isEmpty()) {
        setLoading(false);
        setLastError("No MBID found");
        emit coverArtNotFound();
        return;
    }

    // Try release-group first (more likely to have cover art)
    QString endpoint;
    if (isReleaseGroup) {
        endpoint = QString("https://coverartarchive.org/release-group/%1/front-500").arg(mbid);
    } else {
        endpoint = QString("https://coverartarchive.org/release/%1/front-500").arg(mbid);
    }

    QUrl url(endpoint);
    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader, 
                     "s3rpent_media/0.1 (https://github.com/s3rpent/s3rpent_media)");

    qDebug() << "[CoverArt] Fetching from Cover Art Archive:" << endpoint;
    
    // Disconnect from MusicBrainz handler and connect to Cover Art Archive handler
    disconnect(m_networkManager, &QNetworkAccessManager::finished,
               this, &CoverArtClient::onMusicBrainzReplyFinished);
    connect(m_networkManager, &QNetworkAccessManager::finished,
            this, &CoverArtClient::onCoverArtArchiveReplyFinished);

    QNetworkReply *reply = m_networkManager->get(request);
    reply->setProperty("requestType", "coverartarchive");
    reply->setProperty("mbid", mbid);
    reply->setProperty("isReleaseGroup", isReleaseGroup);
}

void CoverArtClient::onMusicBrainzReplyFinished(QNetworkReply *reply)
{
    if (reply->error() != QNetworkReply::NoError) {
        qWarning() << "[CoverArt] MusicBrainz search error:" << reply->errorString();
        setLoading(false);
        setLastError(reply->errorString());
        emit coverArtError(reply->errorString());
        reply->deleteLater();
        return;
    }

    QByteArray data = reply->readAll();
    reply->deleteLater();

    QString mbid = extractMBIDFromMusicBrainzResponse(data);
    
    if (mbid.isEmpty()) {
        qDebug() << "[CoverArt] No MBID found in MusicBrainz response";
        setLoading(false);
        setLastError("No matching release found");
        emit coverArtNotFound();
        return;
    }

    qDebug() << "[CoverArt] Found MBID:" << mbid;
    
    // Determine if this is a release-group or release MBID
    // If we have both, try release-group first
    bool isReleaseGroup = !m_currentReleaseGroupMbid.isEmpty() && mbid == m_currentReleaseGroupMbid;
    
    // Try release-group first (more likely to have cover art)
    // We'll try release if release-group fails
    fetchFromCoverArtArchive(mbid, isReleaseGroup);
}

void CoverArtClient::onCoverArtArchiveReplyFinished(QNetworkReply *reply)
{
    if (reply->error() != QNetworkReply::NoError) {
        // If release-group failed, try release
        bool isReleaseGroup = reply->property("isReleaseGroup").toBool();
        QString mbid = reply->property("mbid").toString();
        
        if (isReleaseGroup && !m_currentReleaseMbid.isEmpty() && m_currentReleaseMbid != mbid) {
            qDebug() << "[CoverArt] Release-group not found, trying release MBID:" << m_currentReleaseMbid;
            reply->deleteLater();
            fetchFromCoverArtArchive(m_currentReleaseMbid, false);
            return;
        }
        
        qWarning() << "[CoverArt] Cover Art Archive error:" << reply->errorString();
        setLoading(false);
        setLastError(reply->errorString());
        emit coverArtNotFound();
        reply->deleteLater();
        return;
    }

    int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    
    // Check if we got a redirect (307) - that's the actual image URL
    QVariant redirectUrl = reply->attribute(QNetworkRequest::RedirectionTargetAttribute);
    if (redirectUrl.isValid()) {
        QString coverArtUrl = redirectUrl.toUrl().toString();
        qDebug() << "[CoverArt] Found cover art URL (redirect):" << coverArtUrl;
        setLoading(false);
        emit coverArtFound(coverArtUrl);
        reply->deleteLater();
        return;
    }

    // If status is 307, check Location header
    if (statusCode == 307) {
        QUrl location = reply->header(QNetworkRequest::LocationHeader).toUrl();
        if (!location.isEmpty()) {
            QString coverArtUrl = location.toString();
            qDebug() << "[CoverArt] Found cover art URL (from Location header):" << coverArtUrl;
            setLoading(false);
            emit coverArtFound(coverArtUrl);
            reply->deleteLater();
            return;
        }
    }

    // If status is 200, Qt might have followed redirects automatically
    // Check the final URL - if it's different from the request URL, it's the image URL
    if (statusCode == 200) {
        QUrl finalUrl = reply->url();
        QUrl requestUrl = reply->request().url();
        
        // If the final URL is different from the request URL, it means redirects were followed
        // The final URL should be the actual image URL (usually from archive.org)
        if (finalUrl != requestUrl) {
            QString coverArtUrl = finalUrl.toString();
            qDebug() << "[CoverArt] Found cover art URL (after redirect, status 200):" << coverArtUrl;
            setLoading(false);
            emit coverArtFound(coverArtUrl);
            reply->deleteLater();
            return;
        }
        
        // If URLs are the same but status is 200, check Content-Type
        // If it's an image, the URL itself is the image URL
        QString contentType = reply->header(QNetworkRequest::ContentTypeHeader).toString();
        if (contentType.startsWith("image/")) {
            QString coverArtUrl = finalUrl.toString();
            qDebug() << "[CoverArt] Found cover art URL (direct image, status 200):" << coverArtUrl;
            setLoading(false);
            emit coverArtFound(coverArtUrl);
            reply->deleteLater();
            return;
        }
        
        // Even if URLs are the same, if we got 200, the request URL itself might be the image URL
        // (Cover Art Archive might serve images directly from their domain)
        QString coverArtUrl = finalUrl.toString();
        // Check if it's a valid image URL (contains image extension or is from archive.org)
        if (coverArtUrl.contains(".jpg") || coverArtUrl.contains(".png") || 
            coverArtUrl.contains("archive.org") || coverArtUrl.contains("coverartarchive.org")) {
            qDebug() << "[CoverArt] Found cover art URL (status 200, using final URL):" << coverArtUrl;
            setLoading(false);
            emit coverArtFound(coverArtUrl);
            reply->deleteLater();
            return;
        }
    }

    // If we get here, something went wrong
    qWarning() << "[CoverArt] Unexpected response from Cover Art Archive, status:" << statusCode 
               << "URL:" << reply->url().toString();
    setLoading(false);
    setLastError("Unexpected response format");
    emit coverArtNotFound();
    reply->deleteLater();
}

QString CoverArtClient::extractMBIDFromMusicBrainzResponse(const QByteArray &data)
{
    QJsonParseError error;
    QJsonDocument doc = QJsonDocument::fromJson(data, &error);
    
    if (error.error != QJsonParseError::NoError) {
        qWarning() << "[CoverArt] JSON parse error:" << error.errorString();
        return QString();
    }

    QJsonObject root = doc.object();
    QJsonArray releases = root.value("releases").toArray();
    
    if (releases.isEmpty()) {
        qDebug() << "[CoverArt] No releases found in MusicBrainz response";
        return QString();
    }

    // Get the first release
    QJsonObject firstRelease = releases.first().toObject();
    
    // Store both release and release-group MBIDs
    QString releaseMbid = firstRelease.value("id").toString();
    QJsonObject releaseGroup = firstRelease.value("release-group").toObject();
    QString releaseGroupMbid;
    if (!releaseGroup.isEmpty()) {
        releaseGroupMbid = releaseGroup.value("id").toString();
    }
    
    // Store MBIDs as properties for later use
    // We'll try release-group first, then release
    if (!releaseGroupMbid.isEmpty()) {
        qDebug() << "[CoverArt] Found release-group MBID:" << releaseGroupMbid << "and release MBID:" << releaseMbid;
        // Store both - we'll try release-group first
        m_currentReleaseGroupMbid = releaseGroupMbid;
        m_currentReleaseMbid = releaseMbid;
        return releaseGroupMbid;  // Return release-group for first attempt
    } else if (!releaseMbid.isEmpty()) {
        qDebug() << "[CoverArt] Found release MBID:" << releaseMbid;
        m_currentReleaseMbid = releaseMbid;
        m_currentReleaseGroupMbid = "";
        return releaseMbid;
    }
    
    qDebug() << "[CoverArt] No MBID found in MusicBrainz response";
    return QString();
}

QString CoverArtClient::extractCoverArtUrlFromResponse(const QByteArray &data)
{
    // This is not used since we handle redirects directly
    // But kept for potential future use
    QJsonParseError error;
    QJsonDocument doc = QJsonDocument::fromJson(data, &error);
    
    if (error.error != QJsonParseError::NoError) {
        return QString();
    }

    QJsonObject root = doc.object();
    QJsonArray images = root.value("images").toArray();
    
    if (images.isEmpty()) {
        return QString();
    }

    // Find front cover
    for (const QJsonValue &value : images) {
        QJsonObject image = value.toObject();
        bool isFront = image.value("front").toBool();
        if (isFront) {
            QJsonObject thumbnails = image.value("thumbnails").toObject();
            // Use 500px thumbnail for Discord
            QString url = thumbnails.value("500").toString();
            if (url.isEmpty()) {
                url = image.value("image").toString();
            }
            return url;
        }
    }

    // If no front cover, use first image
    QJsonObject firstImage = images.first().toObject();
    QJsonObject thumbnails = firstImage.value("thumbnails").toObject();
    QString url = thumbnails.value("500").toString();
    if (url.isEmpty()) {
        url = firstImage.value("image").toString();
    }
    return url;
}

void CoverArtClient::setLoading(bool loading)
{
    if (m_loading != loading) {
        m_loading = loading;
        emit loadingChanged();
    }
}

void CoverArtClient::setLastError(const QString &error)
{
    if (m_lastError != error) {
        m_lastError = error;
        emit lastErrorChanged();
    }
}

