#ifndef YOUTUBEEXTRACTOR_H
#define YOUTUBEEXTRACTOR_H

#include <QByteArray>
#include <QElapsedTimer>
#include <QObject>
#include <QProcess>
#include <QString>
#include <QStringList>
#include <QTimer>

/**
 * Runs yt-dlp asynchronously to resolve a direct audio stream URL.
 * Resolves stream URL with yt-dlp; prefers non-JS clients, then browser cookies.
 */
class YouTubeExtractor : public QObject
{
    Q_OBJECT

public:
    explicit YouTubeExtractor(QObject *parent = nullptr);
    ~YouTubeExtractor() override;

    void startExtract(const QString &videoUrl);
    void setPreferredVideoMaxHeight(int maxHeight);

signals:
    void finished(const QString &audioStreamUrl, const QString &title, const QString &artist,
                  const QString &thumbnailUrl, const QString &videoStreamUrl);
    void failed(const QString &errorMessage);

private:
    void killActiveProcess();
    void tryNextAttempt();
    void launchYtDlpForAttempt();
    void fail(const QString &message);
    void onProcessFinished(int exitCode, QProcess::ExitStatus status);
    void onReadyReadStdout();
    void onTimeout();

    QProcess *m_process = nullptr;
    QTimer *m_timeoutTimer = nullptr;
    QString m_videoUrl;
    QStringList m_browsers;
    /** Attempt index: cookieless + clients, then browser cookies (see tryNextAttempt). */
    int m_attemptIndex = 0;
    QByteArray m_stdoutAccum;
    QString m_activeBrowser;

    QString m_lastVideoUrl;
    QString m_lastStreamUrl;
    QString m_lastTitle;
    QString m_lastArtist;
    QString m_lastThumbnailUrl;
    QString m_lastVideoStreamUrl;
    int m_preferredVideoMaxHeight = 0; // 0 = auto
    int m_lastPreferredVideoMaxHeight = 0;
    QElapsedTimer m_lastSuccessTimer;
    QString m_resolvedYtDlp;
    static constexpr int kCacheTtlMs = 30000;
    static constexpr int kTimeoutMs = 45000;
};

#endif
