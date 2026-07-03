#ifndef YOUTUBEPLAYBACKHELPER_H
#define YOUTUBEPLAYBACKHELPER_H

#include <QObject>
#include <QUrl>

class YouTubeExtractor;

/**
 * QML-facing entry: playYouTube() runs yt-dlp async; playFromUrl() forwards a URL to the UI.
 */
class YouTubePlaybackHelper : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int preferredVideoMaxHeight READ preferredVideoMaxHeight WRITE setPreferredVideoMaxHeight NOTIFY preferredVideoMaxHeightChanged)

public:
    explicit YouTubePlaybackHelper(QObject *parent = nullptr);

    Q_INVOKABLE void playYouTube(const QString &videoUrl);
    Q_INVOKABLE void playFromUrl(const QString &url);

    int preferredVideoMaxHeight() const { return m_preferredVideoMaxHeight; }
    Q_INVOKABLE void setPreferredVideoMaxHeight(int maxHeight);

signals:
    void playUrlRequested(const QUrl &url, const QString &title, const QString &artist,
                          const QString &thumbnailUrl, const QString &videoStreamUrl);
    void extractFailed(const QString &reason);
    void preferredVideoMaxHeightChanged();

private:
    YouTubeExtractor *m_extractor = nullptr;
    int m_preferredVideoMaxHeight = 0; // 0 = auto
};

#endif
