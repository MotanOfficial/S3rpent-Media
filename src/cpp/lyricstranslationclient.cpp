#include "lyricstranslationclient.h"
#include <QNetworkRequest>
#include <QUrl>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QCryptographicHash>
#include <QDebug>

LyricsTranslationClient::LyricsTranslationClient(QObject *parent)
    : QObject(parent)
    , m_networkManager(new QNetworkAccessManager(this))
    , m_loading(false)
    , m_lastError("")
{
    connect(m_networkManager, &QNetworkAccessManager::finished,
            this, &LyricsTranslationClient::onReplyFinished);
}

LyricsTranslationClient::~LyricsTranslationClient()
{
}

QString LyricsTranslationClient::getCacheFilePath(const QString &trackName, const QString &artistName,
                                                  const QString &albumName, const QString &targetLanguage) const
{
    // Create a unique filename based on song metadata and target language
    QString cacheKey = QString("%1|%2|%3|%4").arg(trackName, artistName, albumName, targetLanguage);
    
    // Hash the key to create a safe filename
    QCryptographicHash hash(QCryptographicHash::Sha256);
    hash.addData(cacheKey.toUtf8());
    QString filename = hash.result().toHex() + ".json";
    
    // Get cache directory (app data directory)
    QString cacheDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    cacheDir += "/lyrics_translations";
    
    // Ensure directory exists
    QDir dir;
    if (!dir.exists(cacheDir)) {
        dir.mkpath(cacheDir);
    }
    
    return cacheDir + "/" + filename;
}

bool LyricsTranslationClient::loadFromCache(const QString &cachePath, QVariantList &outLines) const
{
    QFile file(cachePath);
    if (!file.exists()) {
        return false;
    }
    
    if (!file.open(QIODevice::ReadOnly)) {
        qWarning() << "[Translation] Failed to open cache file:" << cachePath;
        return false;
    }
    
    QByteArray data = file.readAll();
    file.close();
    
    QJsonParseError error;
    QJsonDocument doc = QJsonDocument::fromJson(data, &error);
    if (error.error != QJsonParseError::NoError) {
        qWarning() << "[Translation] Failed to parse cache file:" << error.errorString();
        return false;
    }
    
    QJsonObject obj = doc.object();
    QJsonArray linesArray = obj["lines"].toArray();
    
    outLines.clear();
    for (const QJsonValue &value : linesArray) {
        QJsonObject lineObj = value.toObject();
        QVariantMap line;
        line["timestamp"] = lineObj["timestamp"].toVariant();
        line["text"] = lineObj["text"].toString();
        outLines.append(line);
    }
    
    qDebug() << "[Translation] Loaded" << outLines.size() << "lines from cache";
    return true;
}

void LyricsTranslationClient::saveToCache(const QString &cachePath, const QVariantList &lines) const
{
    QFile file(cachePath);
    if (!file.open(QIODevice::WriteOnly)) {
        qWarning() << "[Translation] Failed to create cache file:" << cachePath;
        return;
    }
    
    QJsonObject obj;
    QJsonArray linesArray;
    
    for (const QVariant &variant : lines) {
        QVariantMap line = variant.toMap();
        QJsonObject lineObj;
        lineObj["timestamp"] = line["timestamp"].toLongLong();
        lineObj["text"] = line["text"].toString();
        linesArray.append(lineObj);
    }
    
    obj["lines"] = linesArray;
    
    QJsonDocument doc(obj);
    file.write(doc.toJson());
    file.close();
    
    qDebug() << "[Translation] Saved" << lines.size() << "lines to cache";
}

QJsonObject LyricsTranslationClient::buildTranslationRequest(const QVariantList &lyricLines) const
{
    // Build JSON structure for translation API
    // The API expects: { "json_content": { "lyrics": [ { "timestamp": ..., "text": ... } ] } }
    QJsonObject root;
    QJsonObject jsonContent;
    QJsonArray lyricsArray;
    
    for (const QVariant &variant : lyricLines) {
        QVariantMap line = variant.toMap();
        QJsonObject lyricObj;
        lyricObj["timestamp"] = line["timestamp"].toLongLong();
        lyricObj["text"] = line["text"].toString();
        lyricsArray.append(lyricObj);
    }
    
    jsonContent["lyrics"] = lyricsArray;
    root["json_content"] = jsonContent;
    
    return root;
}

QVariantList LyricsTranslationClient::parseTranslationResponse(const QByteArray &data) const
{
    QVariantList result;
    
    QJsonParseError error;
    QJsonDocument doc = QJsonDocument::fromJson(data, &error);
    if (error.error != QJsonParseError::NoError) {
        qWarning() << "[Translation] JSON parse error:" << error.errorString();
        qWarning() << "[Translation] Response data:" << data;
        return result;
    }
    
    QJsonObject obj = doc.object();
    
    // Log the response structure for debugging
    qDebug() << "[Translation] Response keys:" << obj.keys();
    
    // Check for error response
    if (obj.contains("error")) {
        QString errorMsg = obj["error"].toString();
        qWarning() << "[Translation] API error:" << errorMsg;
        return result;
    }
    
    // Extract translated content
    // The API returns the translated JSON in "translated_json" field
    if (!obj.contains("translated_json")) {
        qWarning() << "[Translation] Response missing translated_json field";
        qWarning() << "[Translation] Response structure:" << QJsonDocument(obj).toJson();
        return result;
    }
    
    QJsonObject translatedJson = obj["translated_json"].toObject();
    
    // Check if lyrics array exists
    if (!translatedJson.contains("lyrics")) {
        qWarning() << "[Translation] translated_json missing lyrics field";
        qWarning() << "[Translation] translated_json keys:" << translatedJson.keys();
        return result;
    }
    
    QJsonArray lyricsArray = translatedJson["lyrics"].toArray();
    
    if (lyricsArray.isEmpty()) {
        qWarning() << "[Translation] Lyrics array is empty";
        return result;
    }
    
    for (const QJsonValue &value : lyricsArray) {
        QJsonObject lyricObj = value.toObject();
        QVariantMap line;
        line["timestamp"] = lyricObj["timestamp"].toVariant();
        line["text"] = lyricObj["text"].toString();
        result.append(line);
    }
    
    qDebug() << "[Translation] Parsed" << result.size() << "translated lines";
    return result;
}

void LyricsTranslationClient::translateLyrics(const QString &trackName, const QString &artistName,
                                              const QString &albumName, const QVariantList &lyricLines,
                                              const QString &apiKey, const QString &targetLanguage)
{
    if (lyricLines.isEmpty()) {
        qWarning() << "[Translation] No lyrics to translate";
        emit translationFailed("No lyrics to translate");
        return;
    }
    
    if (apiKey.isEmpty()) {
        qWarning() << "[Translation] API key is empty";
        setLastError("API key is required");
        emit translationFailed("API key is required");
        return;
    }
    
    // Check cache first
    QString cachePath = getCacheFilePath(trackName, artistName, albumName, targetLanguage);
    QVariantList cachedLines;
    if (loadFromCache(cachePath, cachedLines)) {
        qDebug() << "[Translation] Using cached translation";
        emit translationComplete(cachedLines);
        return;
    }
    
    // Build request
    QJsonObject requestObj = buildTranslationRequest(lyricLines);
    requestObj["origin_language"] = "auto";  // Auto-detect source language
    requestObj["target_language"] = targetLanguage;
    
    QJsonDocument doc(requestObj);
    QByteArray requestData = doc.toJson();
    
    // Make API request
    QUrl url("https://translateai.p.rapidapi.com/google/translate/json");
    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    request.setRawHeader("x-rapidapi-host", "translateai.p.rapidapi.com");
    request.setRawHeader("x-rapidapi-key", apiKey.toUtf8());
    
    setLoading(true);
    setLastError("");
    
    qDebug() << "[Translation] Sending translation request for" << lyricLines.size() << "lines";
    
    QNetworkReply *reply = m_networkManager->post(request, requestData);
    // Store metadata in reply for later use
    reply->setProperty("cachePath", cachePath);
    reply->setProperty("originalLines", QVariant::fromValue(lyricLines));
}

void LyricsTranslationClient::onReplyFinished(QNetworkReply *reply)
{
    setLoading(false);
    
    if (reply->error() != QNetworkReply::NoError) {
        QByteArray errorData = reply->readAll();
        QString errorMsg = QString("Network error: %1").arg(reply->errorString());
        
        // Check for 403 Forbidden (usually API key issue)
        if (reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() == 403) {
            errorMsg = "API authentication failed (403). Please check your API key.";
            qWarning() << "[Translation]" << errorMsg;
            qWarning() << "[Translation] Response:" << errorData;
        } else {
            qWarning() << "[Translation]" << errorMsg;
            if (!errorData.isEmpty()) {
                qWarning() << "[Translation] Response:" << errorData;
            }
        }
        
        setLastError(errorMsg);
        emit translationFailed(errorMsg);
        reply->deleteLater();
        return;
    }
    
    QByteArray data = reply->readAll();
    QString cachePath = reply->property("cachePath").toString();
    
    reply->deleteLater();
    
    // Parse response
    QVariantList translatedLines = parseTranslationResponse(data);
    
    if (translatedLines.isEmpty()) {
        QString errorMsg = "Failed to parse translation response or empty result";
        qWarning() << "[Translation]" << errorMsg;
        setLastError(errorMsg);
        emit translationFailed(errorMsg);
        return;
    }
    
    // Save to cache
    saveToCache(cachePath, translatedLines);
    
    qDebug() << "[Translation] Translation complete:" << translatedLines.size() << "lines";
    emit translationComplete(translatedLines);
}

void LyricsTranslationClient::setLoading(bool loading)
{
    if (m_loading != loading) {
        m_loading = loading;
        emit loadingChanged();
    }
}

void LyricsTranslationClient::setLastError(const QString &error)
{
    if (m_lastError != error) {
        m_lastError = error;
        emit lastErrorChanged();
    }
}

