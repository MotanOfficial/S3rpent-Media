#include "youtubeplaybackhelper.h"
#include "youtubeextractor.h"

#include <QUrl>

YouTubePlaybackHelper::YouTubePlaybackHelper(QObject *parent)
    : QObject(parent)
{
    m_extractor = new YouTubeExtractor(this);
    m_extractor->setPreferredVideoMaxHeight(m_preferredVideoMaxHeight);
    connect(m_extractor, &YouTubeExtractor::finished, this,
            [this](const QString &streamUrl, const QString &title, const QString &artist,
                   const QString &thumbnailUrl, const QString &videoStreamUrl) {
                const QUrl u = QUrl::fromUserInput(streamUrl.trimmed());
                if (!u.isValid() || u.scheme().isEmpty()) {
                    emit extractFailed(QStringLiteral("Invalid stream URL from yt-dlp"));
                    return;
                }
                emit playUrlRequested(u, title, artist, thumbnailUrl, videoStreamUrl);
            });
    connect(m_extractor, &YouTubeExtractor::failed, this, &YouTubePlaybackHelper::extractFailed);
}

void YouTubePlaybackHelper::setPreferredVideoMaxHeight(int maxHeight)
{
    if (maxHeight < 0)
        maxHeight = 0;
    if (m_preferredVideoMaxHeight == maxHeight)
        return;
    m_preferredVideoMaxHeight = maxHeight;
    if (m_extractor)
        m_extractor->setPreferredVideoMaxHeight(m_preferredVideoMaxHeight);
    emit preferredVideoMaxHeightChanged();
}

void YouTubePlaybackHelper::playYouTube(const QString &videoUrl)
{
    if (!m_extractor) {
        emit extractFailed(QStringLiteral("Extractor not available"));
        return;
    }
    m_extractor->startExtract(videoUrl);
}

void YouTubePlaybackHelper::playFromUrl(const QString &url)
{
    const QString t = url.trimmed();
    if (t.isEmpty()) {
        emit extractFailed(QStringLiteral("Empty playback URL"));
        return;
    }
    const QUrl u = QUrl::fromUserInput(t);
    if (!u.isValid() || u.scheme().isEmpty()) {
        emit extractFailed(QStringLiteral("Invalid URL"));
        return;
    }
    emit playUrlRequested(u, QString(), QString(), QString(), QString());
}
