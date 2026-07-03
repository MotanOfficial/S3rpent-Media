#include "ffmpegvideoplayer.h"
#include "ffmpegvideorenderer.h"
#include <QDebug>
#include <QDir>
#include <QVideoFrame>
#include <QVideoFrameFormat>
#include <QImage>
#include <QQuickWindow>
#include <QtGui/rhi/qrhi.h>
#include <QCoreApplication>
#include <QtGlobal>
#include <QStandardPaths>
#include <QFileInfo>
#include <cstdint>
#include <cmath>

#if 0
#define FFLOG(x) qDebug() << x
#else
#define FFLOG(x) do{}while(0)
#endif

#ifdef Q_OS_WIN
#include <windows.h>
#include <d3d11.h>
#include <d3d11_1.h>
#include <dxgi1_6.h>
#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")
#endif

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libavutil/hwcontext.h>
#include <libavutil/hwcontext_d3d11va.h>
#include <libavutil/imgutils.h>
#include <libavutil/time.h>
#include <libavutil/version.h>
#include <libavutil/channel_layout.h>
#include <libavutil/samplefmt.h>
#include <libswresample/swresample.h>
#include <libswscale/swscale.h>
#include <libavfilter/avfilter.h>
#include <libavfilter/buffersink.h>
#include <libavfilter/buffersrc.h>
}

#ifdef _MSC_VER
#pragma comment(lib, "swscale.lib")
#pragma comment(lib, "avfilter.lib")
#endif

#include "ffmpegvideoplayer_p.h"

using namespace FfVp;

FFmpegVideoPlayer::FFmpegVideoPlayer(QObject* parent)
    : QObject(parent)
{
    initFFmpeg();
    
    av_log_set_level(AV_LOG_WARNING);
}

FFmpegVideoPlayer::~FFmpegVideoPlayer()
{
    stop();
    
    {
        QMutexLocker locker(&m_decodeMutex);
        m_decodeThreadRunning = false;
        m_decodeCondition.wakeAll();
    }
    
    if (m_decodeThread) {
        m_decodeThread->wait(5000);
        delete m_decodeThread;
        m_decodeThread = nullptr;
    }

    if (m_openThread) {
        m_openThreadRunning.store(false, std::memory_order_release);
        m_openThread->wait(5000);
        delete m_openThread;
        m_openThread = nullptr;
    }
    
    closeMedia();
    cleanupYtDlpPipe();
    cleanupD3D11();
    cleanupFFmpeg();
}

void FFmpegVideoPlayer::setUseYtDlpPipe(bool v)
{
    if (m_useYtDlpPipe == v)
        return;
    m_useYtDlpPipe = v;
    emit useYtDlpPipeChanged();
}

void FFmpegVideoPlayer::setYtDlpMaxHeight(int v)
{
    if (v < 0)
        v = 0;
    if (m_ytDlpMaxHeight == v)
        return;
    m_ytDlpMaxHeight = v;
    emit ytDlpMaxHeightChanged();
}

static QString resolveLocalExecutable(const QString &baseName, const QString &winName)
{
    QString p = QStandardPaths::findExecutable(baseName);
    if (!p.isEmpty())
        return QFileInfo(p).absoluteFilePath();
#ifdef Q_OS_WIN
    p = QStandardPaths::findExecutable(winName);
    if (!p.isEmpty())
        return QFileInfo(p).absoluteFilePath();
#endif
    const QString appDir = QCoreApplication::applicationDirPath();
    const QString appCandidate = QDir(appDir).filePath(
#ifdef Q_OS_WIN
        winName
#else
        baseName
#endif
    );
    if (QFileInfo::exists(appCandidate) && QFileInfo(appCandidate).isFile())
        return QFileInfo(appCandidate).absoluteFilePath();
    const QString cwdCandidate = QDir(QDir::currentPath()).filePath(
#ifdef Q_OS_WIN
        winName
#else
        baseName
#endif
    );
    if (QFileInfo::exists(cwdCandidate) && QFileInfo(cwdCandidate).isFile())
        return QFileInfo(cwdCandidate).absoluteFilePath();
    return {};
}

void FFmpegVideoPlayer::cleanupYtDlpPipe()
{
    {
        QMutexLocker locker(&m_pipeMutex);
        m_pipeEof = true;
        m_pipeCond.wakeAll();
    }
    if (m_ytMuxProcess) {
        m_ytMuxProcess->disconnect(this);
        if (m_ytMuxProcess->state() != QProcess::NotRunning) {
            m_ytMuxProcess->kill();
            m_ytMuxProcess->waitForFinished(2000);
        }
        m_ytMuxProcess->deleteLater();
        m_ytMuxProcess = nullptr;
    }
    if (m_ytDlpProcess) {
        m_ytDlpProcess->disconnect(this);
        if (m_ytDlpProcess->state() != QProcess::NotRunning) {
            m_ytDlpProcess->kill();
            m_ytDlpProcess->waitForFinished(2000);
        }
        m_ytDlpProcess->deleteLater();
        m_ytDlpProcess = nullptr;
    }
    m_pipeBuffer.clear();
    if (m_avioContext) {
        avio_context_free(&m_avioContext);
        m_avioContext = nullptr;
    }
    if (m_avioBuffer) {
        av_free(m_avioBuffer);
        m_avioBuffer = nullptr;
    }
}

int FFmpegVideoPlayer::ytDlpReadPacket(void *opaque, uint8_t *buf, int buf_size)
{
    auto *self = static_cast<FFmpegVideoPlayer*>(opaque);
    if (!self || buf_size <= 0)
        return AVERROR_EOF;

    QMutexLocker locker(&self->m_pipeMutex);
    while (self->m_pipeBuffer.isEmpty() && !self->m_pipeEof) {
        self->m_pipeCond.wait(&self->m_pipeMutex, 200);
    }
    if (self->m_pipeBuffer.isEmpty() && self->m_pipeEof)
        return AVERROR_EOF;

    const int n = qMin(buf_size, self->m_pipeBuffer.size());
    memcpy(buf, self->m_pipeBuffer.constData(), static_cast<size_t>(n));
    self->m_pipeBuffer.remove(0, n);
    return n;
}

static QString ytDlpGetDirectUrl(const QUrl& pageUrl, const QString& formatExpr)
{
    const QString ytDlp = resolveLocalExecutable(QStringLiteral("yt-dlp"), QStringLiteral("yt-dlp.exe"));
    if (ytDlp.isEmpty())
        return {};

    QProcess p;
    p.setProcessChannelMode(QProcess::MergedChannels);
    QStringList args;
    args << QStringLiteral("--no-playlist") << QStringLiteral("--force-ipv4")
         << QStringLiteral("-f") << formatExpr
         << QStringLiteral("-g")
         << pageUrl.toString();
    p.start(ytDlp, args);
    if (!p.waitForStarted(5000))
        return {};
    if (!p.waitForFinished(15000)) {
        p.kill();
        p.waitForFinished(2000);
        return {};
    }
    const QString out = QString::fromUtf8(p.readAllStandardOutput()).trimmed();
    // yt-dlp -g can output multiple lines (video+audio). For our pipe-safe formatExpr we expect 1 URL.
    const QString firstLine = out.section(QChar('\n'), 0, 0).trimmed();
    if (firstLine.startsWith(QStringLiteral("http://")) || firstLine.startsWith(QStringLiteral("https://"))) {
        // Reject HLS manifests for "direct URL" mode. They can behave like live-ish streams, loop/reload segments,
        // and are often not reliably seekable with our current demux+sync logic.
        const QString lower = firstLine.toLower();
        if (lower.contains(QStringLiteral("manifest.googlevideo.com"))
            || lower.endsWith(QStringLiteral(".m3u8"))
            || lower.contains(QStringLiteral("hls_playlist"))
            || lower.contains(QStringLiteral("playlist/index.m3u8"))) {
            return {};
        }
        return firstLine;
    }
    return {};
}

static bool ytDlpGetAdaptiveUrls(QString& outVideoUrl, QString& outAudioUrl, const QUrl& pageUrl, int maxHeight)
{
    outVideoUrl.clear();
    outAudioUrl.clear();

    const QString ytDlp = resolveLocalExecutable(QStringLiteral("yt-dlp"), QStringLiteral("yt-dlp.exe"));
    if (ytDlp.isEmpty())
        return false;

    // Request DASH adaptive (separate video+audio), prefer MP4/M4A, and cap height if requested.
    // Prefer H.264/AVC for video to avoid AV1 decode issues on some systems.
    const QString h = (maxHeight > 0) ? QString::number(maxHeight) : QString();
    const QString fmt = (maxHeight > 0)
        ? QStringLiteral("bestvideo[vcodec^=avc1][height<=%1][ext=mp4][vcodec!=none]+bestaudio[ext=m4a][acodec!=none]/bestvideo[height<=%1][ext=mp4][vcodec!=none]+bestaudio[ext=m4a][acodec!=none]/bestvideo[height<=%1][vcodec!=none]+bestaudio[acodec!=none]/best").arg(h)
        : QStringLiteral("bestvideo[vcodec^=avc1][ext=mp4][vcodec!=none]+bestaudio[ext=m4a][acodec!=none]/bestvideo[ext=mp4][vcodec!=none]+bestaudio[ext=m4a][acodec!=none]/bestvideo[vcodec!=none]+bestaudio[acodec!=none]/best");

    QProcess p;
    p.setProcessChannelMode(QProcess::MergedChannels);
    QStringList args;
    args << QStringLiteral("--no-playlist") << QStringLiteral("--force-ipv4")
         << QStringLiteral("-f") << fmt
         << QStringLiteral("-g")
         << pageUrl.toString();
    p.start(ytDlp, args);
    if (!p.waitForStarted(5000))
        return false;
    if (!p.waitForFinished(20000)) {
        p.kill();
        p.waitForFinished(2000);
        return false;
    }

    const QString out = QString::fromUtf8(p.readAllStandardOutput());
    const QStringList lines = out.split(QChar('\n'), Qt::SkipEmptyParts);
    if (lines.size() < 2)
        return false;
    const QString l0 = lines[0].trimmed();
    const QString l1 = lines[1].trimmed();
    if (!(l0.startsWith(QStringLiteral("http://")) || l0.startsWith(QStringLiteral("https://"))))
        return false;
    if (!(l1.startsWith(QStringLiteral("http://")) || l1.startsWith(QStringLiteral("https://"))))
        return false;
    outVideoUrl = l0;
    outAudioUrl = l1;
    return true;
}

bool FFmpegVideoPlayer::startYtDlpPipeProcess(const QUrl &url)
{
    cleanupYtDlpPipe();

    const QString ytDlp = resolveLocalExecutable(QStringLiteral("yt-dlp"), QStringLiteral("yt-dlp.exe"));
    if (ytDlp.isEmpty()) {
        emit errorOccurred(-1, "yt-dlp not found for pipe mode");
        return false;
    }

    QStringList args;
    args << QStringLiteral("--no-playlist") << QStringLiteral("--force-ipv4");

    // Enable EJS if deno is available.
    const QString deno = resolveLocalExecutable(QStringLiteral("deno"), QStringLiteral("deno.exe"));
    if (!deno.isEmpty())
        args << QStringLiteral("--js-runtimes") << QStringLiteral("deno:%1").arg(deno);
    else
        args << QStringLiteral("--js-runtimes") << QStringLiteral("deno");
    args << QStringLiteral("--remote-components") << QStringLiteral("ejs:npm");

    // IMPORTANT:
    // - For direct URL mode: prefer progressive muxed mp4 (seekable).
    // - For high qualities (>1080p): YouTube is often adaptive (separate video+audio). For that case
    //   we can spawn ffmpeg to mux bestvideo+bestaudio to stdout and feed that into our pipe.
    const QString muxedUnderCap = (m_ytDlpMaxHeight > 0)
        ? QStringLiteral("best[protocol^=http][ext=mp4][acodec!=none][vcodec!=none][height<=%1]").arg(m_ytDlpMaxHeight)
        : QStringLiteral("best[protocol^=http][ext=mp4][acodec!=none][vcodec!=none]");
    const QString muxedFallback = (m_ytDlpMaxHeight > 0)
        ? QStringLiteral("best[protocol^=http][acodec!=none][vcodec!=none][height<=%1]/best[protocol^=http][acodec!=none][vcodec!=none]").arg(m_ytDlpMaxHeight)
        : QStringLiteral("best[protocol^=http][acodec!=none][vcodec!=none]");
    const QString capExpr = muxedUnderCap + QStringLiteral("/") + muxedFallback;

    // Selection strategy:
    // - If user requests >1080p (or "no cap"), YouTube often requires adaptive (bestvideo+bestaudio).
    //   Prefer adaptive mux (ffmpeg -> stdout -> our pipe) to guarantee audio at high resolutions.
    // - Otherwise prefer direct muxed URL (seekable) and fall back to pipe.
    const bool preferAdaptive = (m_ytDlpMaxHeight <= 0) || (m_ytDlpMaxHeight > 1080);

    m_youTubeDirectUrl.clear();

    if (preferAdaptive && m_tryYouTubeAdaptiveMux) {
        QString vUrl, aUrl;
        const bool got = ytDlpGetAdaptiveUrls(vUrl, aUrl, url, m_ytDlpMaxHeight);
        if (got) {
            const QString ffmpegExe = resolveLocalExecutable(QStringLiteral("ffmpeg"), QStringLiteral("ffmpeg.exe"));
            if (!ffmpegExe.isEmpty()) {
                qDebug() << "[FFmpeg] Opening YouTube via ffmpeg mux (adaptive A/V -> pipe)";
                qDebug() << "[FFmpeg] Adaptive URLs:"
                         << "\n  video =" << vUrl.left(220)
                         << "\n  audio =" << aUrl.left(220);
                m_pipeEof = false;
                m_pipeBuffer.clear();

                m_ytMuxProcess = new QProcess(this);
                m_ytMuxProcess->setProcessChannelMode(QProcess::SeparateChannels);

                connect(m_ytMuxProcess, &QProcess::readyReadStandardOutput, this, [this]() {
                    if (!m_ytMuxProcess)
                        return;
                    constexpr int kMaxPipeBufferBytes = 128 * 1024 * 1024;
                    {
                        QMutexLocker locker(&m_pipeMutex);
                        if (m_pipeBuffer.size() >= kMaxPipeBufferBytes)
                            return;
                    }
                    const qint64 remaining = qint64(kMaxPipeBufferBytes) - qint64(m_pipeBuffer.size());
                    const qint64 toRead = qMin<qint64>(m_ytMuxProcess->bytesAvailable(), remaining);
                    if (toRead <= 0)
                        return;
                    const QByteArray chunk = m_ytMuxProcess->read(toRead);
                    if (chunk.isEmpty())
                        return;
                    QMutexLocker locker(&m_pipeMutex);
                    m_pipeBuffer.append(chunk);
                    m_pipeCond.wakeAll();
                });
                connect(m_ytMuxProcess, &QProcess::readyReadStandardError, this, [this]() {
                    if (!m_ytMuxProcess)
                        return;
                    const QByteArray err = m_ytMuxProcess->readAllStandardError();
                    if (err.isEmpty())
                        return;
                    const QByteArray trimmed = err.left(2048);
                    qWarning().noquote() << "[FFmpeg][YTMux] stderr:" << QString::fromUtf8(trimmed);
                });
                connect(m_ytMuxProcess, &QProcess::finished, this, [this](int, QProcess::ExitStatus) {
                    QMutexLocker locker(&m_pipeMutex);
                    m_pipeEof = true;
                    m_pipeCond.wakeAll();
                });

                QStringList ffArgs;
                ffArgs << QStringLiteral("-hide_banner") << QStringLiteral("-loglevel") << QStringLiteral("error")
                      << QStringLiteral("-i") << vUrl
                      << QStringLiteral("-i") << aUrl
                      << QStringLiteral("-c") << QStringLiteral("copy")
                      << QStringLiteral("-f") << QStringLiteral("matroska")
                      << QStringLiteral("pipe:1");
                qDebug() << "[FFmpeg] YT mux command:" << ffmpegExe << ffArgs;
                m_ytMuxProcess->start(ffmpegExe, ffArgs);
                if (!m_ytMuxProcess->waitForStarted(5000)) {
                    cleanupYtDlpPipe();
                } else {
                    // Our AVIO reader will now read muxed bytes from m_pipeBuffer.
                    return true;
                }
            }
        }
    }

    // Try to resolve a direct URL (enables seek) for <=1080p cases, or if adaptive mux wasn't available.
    if (m_tryYouTubeDirectUrl) {
        const QString direct = ytDlpGetDirectUrl(url, capExpr);
        if (!direct.isEmpty())
            m_youTubeDirectUrl = direct;
    }

    args << QStringLiteral("-f") << capExpr
         << QStringLiteral("-o") << QStringLiteral("-")
         << url.toString();

    m_pipeEof = false;
    m_pipeBuffer.clear();

    m_ytDlpProcess = new QProcess(this);
    m_ytDlpProcess->setProcessChannelMode(QProcess::SeparateChannels);

    connect(m_ytDlpProcess, &QProcess::readyReadStandardOutput, this, [this]() {
        if (!m_ytDlpProcess)
            return;

        // IMPORTANT:
        // Never drop bytes from the front of the buffer. That corrupts the byte stream and can make
        // FFmpeg "jump" to later keyframes/segments. Instead, apply backpressure: stop reading
        // when the buffer is full and let the OS pipe block yt-dlp until we drain.
        constexpr int kMaxPipeBufferBytes = 128 * 1024 * 1024; // 128MB

        {
            QMutexLocker locker(&m_pipeMutex);
            if (m_pipeBuffer.size() >= kMaxPipeBufferBytes)
                return;
        }

        // Read only up to remaining capacity.
        const qint64 remaining = qint64(kMaxPipeBufferBytes) - qint64(m_pipeBuffer.size());
        const qint64 toRead = qMin<qint64>(m_ytDlpProcess->bytesAvailable(), remaining);
        if (toRead <= 0)
            return;

        const QByteArray chunk = m_ytDlpProcess->read(toRead);
        if (chunk.isEmpty())
            return;

        QMutexLocker locker(&m_pipeMutex);
        m_pipeBuffer.append(chunk);
        m_pipeCond.wakeAll();
    });
    connect(m_ytDlpProcess, &QProcess::finished, this, [this](int, QProcess::ExitStatus) {
        QMutexLocker locker(&m_pipeMutex);
        m_pipeEof = true;
        m_pipeCond.wakeAll();
    });

    m_ytDlpProcess->start(ytDlp, args);
    if (!m_ytDlpProcess->waitForStarted(5000)) {
        emit errorOccurred(-1, "Failed to start yt-dlp for pipe mode");
        cleanupYtDlpPipe();
        return false;
    }
    return true;
}

void FFmpegVideoPlayer::openMediaFromYtDlpPipe()
{
    // Runs in a background thread to avoid freezing the UI:
    // avformat_open_input + avformat_find_stream_info can block waiting for initial bytes.
    // yt-dlp stdout provides those bytes asynchronously via readyRead in the GUI thread.

    // Custom AVIO for piping.
    m_avioBuffer = static_cast<uint8_t*>(av_malloc(1024 * 1024));
    if (!m_avioBuffer) {
        emit errorOccurred(-1, "Failed to allocate AVIO buffer");
        return;
    }

    m_avioContext = avio_alloc_context(m_avioBuffer, 1024 * 1024, 0, this, &FFmpegVideoPlayer::ytDlpReadPacket, nullptr, nullptr);
    if (!m_avioContext) {
        emit errorOccurred(-1, "Failed to allocate AVIO context");
        return;
    }

    m_formatContext = avformat_alloc_context();
    if (!m_formatContext) {
        emit errorOccurred(-1, "Failed to allocate format context");
        return;
    }
    m_formatContext->pb = m_avioContext;
    m_formatContext->flags |= AVFMT_FLAG_CUSTOM_IO;

    int ret = avformat_open_input(&m_formatContext, nullptr, nullptr, nullptr);
    if (ret < 0) {
        char errbuf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(ret, errbuf, AV_ERROR_MAX_STRING_SIZE);
        emit errorOccurred(ret, QString::fromUtf8(errbuf));
        return;
    }
}

void FFmpegVideoPlayer::initFFmpeg()
{
    qDebug() << "[FFmpeg] Player initialized";
    qDebug() << "[FFmpeg] Version:" << av_version_info();
    qDebug() << "[FFmpeg] libavformat version:" << LIBAVFORMAT_VERSION_MAJOR << "." << LIBAVFORMAT_VERSION_MINOR << "." << LIBAVFORMAT_VERSION_MICRO;
    qDebug() << "[FFmpeg] libavcodec version:" << LIBAVCODEC_VERSION_MAJOR << "." << LIBAVCODEC_VERSION_MINOR << "." << LIBAVCODEC_VERSION_MICRO;
    qDebug() << "[FFmpeg] libavutil version:" << LIBAVUTIL_VERSION_MAJOR << "." << LIBAVUTIL_VERSION_MINOR << "." << LIBAVUTIL_VERSION_MICRO;
}

void FFmpegVideoPlayer::cleanupFFmpeg()
{
}

void FFmpegVideoPlayer::onSceneGraphInitialized()
{
    qDebug() << "[FFmpeg] Scene graph initialized — RHI is now available";
    
    if (!initD3D11FromRHI()) {
        qWarning() << "[FFmpeg] Failed to initialize D3D11 from RHI (Video Processor may not work)";
    } else {
        qDebug() << "[FFmpeg] Qt D3D11 device acquired (for Video Processor)";
    }
    
    if (!m_source.isEmpty() && !m_formatContext) {
        qDebug() << "[FFmpeg] Opening media (FFmpeg will create its own video device)";
        openMedia();
    }
}

void FFmpegVideoPlayer::openMedia()
{
    QMutexLocker lifecycle(&m_mediaLifecycleMutex);
    if (m_mediaOpening || m_mediaOpened) {
        qDebug() << "[FFmpeg] openMedia() ignored (already opening/opened)";
        return;
    }
    
    if (m_source.isEmpty() || !m_source.isValid()) {
        qWarning() << "[FFmpeg] Invalid source";
        m_mediaOpening = false;
        m_mediaOpened = false;
        return;
    }
    
    m_mediaOpening = true;
    
    const QString srcStr = m_source.toString();
    const bool isYouTube = srcStr.contains(QStringLiteral("youtube.com"), Qt::CaseInsensitive)
        || srcStr.contains(QStringLiteral("youtu.be"), Qt::CaseInsensitive);
    int ret = 0;
    if (m_useYtDlpPipe && isYouTube) {
        if (!m_youTubeDirectUrl.isEmpty()) {
            qDebug() << "[FFmpeg] Opening YouTube via direct URL (seekable):" << m_youTubeDirectUrl;
            QString filePath = m_youTubeDirectUrl;
            m_formatContext = avformat_alloc_context();
            if (!m_formatContext) {
                qWarning() << "[FFmpeg] Failed to allocate format context";
                emit errorOccurred(-1, "Failed to allocate format context");
                m_mediaOpening = false;
                m_mediaOpened = false;
                return;
            }
            ret = avformat_open_input(&m_formatContext, filePath.toUtf8().constData(), nullptr, nullptr);
            if (ret < 0) {
                char errbuf[AV_ERROR_MAX_STRING_SIZE];
                av_strerror(ret, errbuf, AV_ERROR_MAX_STRING_SIZE);
                qWarning() << "[FFmpeg] Failed to open direct YouTube URL, falling back to pipe:" << errbuf;
                avformat_free_context(m_formatContext);
                m_formatContext = nullptr;
            }
        }

        if (!m_formatContext) {
            qDebug() << "[FFmpeg] Opening media via yt-dlp pipe:" << srcStr;
            openMediaFromYtDlpPipe();
            if (!m_formatContext) {
                m_mediaOpening = false;
                m_mediaOpened = false;
                cleanupYtDlpPipe();
                return;
            }
        }
    } else {
        QString filePath = m_source.toLocalFile();
        if (filePath.isEmpty()) {
            filePath = m_source.toString();
        }
        qDebug() << "[FFmpeg] Opening media:" << filePath;

        m_formatContext = avformat_alloc_context();
        if (!m_formatContext) {
            qWarning() << "[FFmpeg] Failed to allocate format context";
            emit errorOccurred(-1, "Failed to allocate format context");
            m_mediaOpening = false;
            m_mediaOpened = false;
            return;
        }

        ret = avformat_open_input(&m_formatContext, filePath.toUtf8().constData(), nullptr, nullptr);
        if (ret < 0) {
            char errbuf[AV_ERROR_MAX_STRING_SIZE];
            av_strerror(ret, errbuf, AV_ERROR_MAX_STRING_SIZE);
            qWarning() << "[FFmpeg] Failed to open input:" << errbuf;
            emit errorOccurred(ret, QString::fromUtf8(errbuf));
            avformat_free_context(m_formatContext);
            m_formatContext = nullptr;
            m_mediaOpening = false;
            m_mediaOpened = false;
            return;
        }
    }
    
    ret = avformat_find_stream_info(m_formatContext, nullptr);
    if (ret < 0) {
        qWarning() << "[FFmpeg] Failed to find stream info";
        avformat_close_input(&m_formatContext);
        m_formatContext = nullptr;
        m_mediaOpening = false;
        m_mediaOpened = false;
        return;
    }
    
    m_videoStreamIndex = -1;
    for (unsigned int i = 0; i < m_formatContext->nb_streams; i++) {
        if (m_formatContext->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            m_videoStreamIndex = static_cast<int>(i);
            m_videoStream = m_formatContext->streams[i];
            break;
        }
    }
    
    if (m_videoStreamIndex < 0) {
        qWarning() << "[FFmpeg] No video stream found";
        avformat_close_input(&m_formatContext);
        m_formatContext = nullptr;
        m_mediaOpening = false;
        m_mediaOpened = false;
        return;
    }
    
    m_audioStreamIndex = -1;
    if (m_audioEnabled) {
        for (unsigned int i = 0; i < m_formatContext->nb_streams; i++) {
            if (m_formatContext->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
                m_audioStreamIndex = static_cast<int>(i);
                break;
            }
        }
    } else {
        qDebug().noquote() << "[FFmpeg]" << (m_logTag.isEmpty() ? QStringLiteral("") : QStringLiteral("[%1]").arg(m_logTag))
                           << "Audio disabled for this player instance";
    }

    m_avSyncOffsetValid = false;
    m_avSyncOffsetSec = 0.0;
    
    if (m_audioEnabled && m_audioStreamIndex >= 0) {
        AVStream* audioStream = m_formatContext->streams[m_audioStreamIndex];
        const AVCodec* audioCodec = avcodec_find_decoder(audioStream->codecpar->codec_id);
        
        if (audioCodec) {
            m_audioCodecContext = avcodec_alloc_context3(audioCodec);
            if (m_audioCodecContext) {
                int ret = avcodec_parameters_to_context(m_audioCodecContext, audioStream->codecpar);
                if (ret >= 0) {
                    ret = avcodec_open2(m_audioCodecContext, audioCodec, nullptr);
                    if (ret >= 0) {
                        m_audioFrame = av_frame_alloc();
                        int inputChannels = m_audioCodecContext->ch_layout.nb_channels;
                        int inputSampleRate = m_audioCodecContext->sample_rate;
                        qDebug() << "[FFmpeg] Audio decoder opened - sample rate:" << inputSampleRate 
                                 << "channels:" << inputChannels;
                        
                        QAudioDevice defaultDevice = QMediaDevices::defaultAudioOutput();
                        if (defaultDevice.description().isEmpty()) {
                            qWarning() << "[FFmpeg] No default audio output device available - audio disabled";
                            avcodec_free_context(&m_audioCodecContext);
                            m_audioCodecContext = nullptr;
                        } else {
                            int outputChannels = inputChannels;
                            int outputSampleRate = inputSampleRate;
                        
                            m_audioFormat.setSampleRate(outputSampleRate);
                            m_audioFormat.setChannelCount(outputChannels);
                            m_audioFormat.setSampleFormat(QAudioFormat::Int16);
                        
                            if (!defaultDevice.isFormatSupported(m_audioFormat)) {
                                outputChannels = 2;
                                m_audioFormat.setChannelCount(outputChannels);
                            
                                if (!defaultDevice.isFormatSupported(m_audioFormat)) {
                                    outputSampleRate = 44100;
                                    m_audioFormat.setSampleRate(outputSampleRate);
                                
                                    if (!defaultDevice.isFormatSupported(m_audioFormat)) {
                                        m_audioFormat = defaultDevice.preferredFormat();
                                        if (m_audioFormat.sampleFormat() != QAudioFormat::Int16) {
                                            m_audioFormat.setSampleFormat(QAudioFormat::Int16);
                                            if (!defaultDevice.isFormatSupported(m_audioFormat)) {
                                                m_audioFormat = defaultDevice.preferredFormat();
                                            }
                                        }
                                        outputSampleRate = m_audioFormat.sampleRate();
                                        outputChannels = m_audioFormat.channelCount();
                                    }
                                }
                            }
                        
                            qDebug() << "[FFmpeg] Selected audio output format:" << m_audioFormat.sampleRate() << "Hz,"
                                     << m_audioFormat.channelCount() << "channels,"
                                     << "format:" << m_audioFormat.sampleFormat();
                        
                            const QAudioDevice audioDev = defaultDevice;
                            const QAudioFormat fmt = m_audioFormat;
                            const float vol = m_volume;
                            const auto createAudioSinkOnObjectThread = [this, audioDev, fmt, vol]() {
                                QMutexLocker audioLock(&m_audioMutex);
                                if (m_audioSink) {
                                    if (m_audioDevice && m_audioDevice->isOpen())
                                        m_audioDevice->close();
                                    m_audioSink->stop();
                                    m_audioSink->deleteLater();
                                    m_audioSink = nullptr;
                                    m_audioDevice = nullptr;
                                }
                                m_audioSink = new QAudioSink(audioDev, fmt, this);
                                m_audioSink->setBufferSize(512 * 1024);
                                m_audioSink->setVolume(vol);
                                m_audioDevice = m_audioSink->start();
                                if (!m_audioDevice || !m_audioDevice->isOpen()) {
                                    qWarning() << "[FFmpeg] Failed to start audio device - audio playback disabled";
                                } else {
                                    m_audioRemainder.clear();
                                }
                            };
                            if (QThread::currentThread() == this->thread()) {
                                createAudioSinkOnObjectThread();
                            } else {
                                QMetaObject::invokeMethod(this, createAudioSinkOnObjectThread, Qt::BlockingQueuedConnection);
                            }
                        
                            if (m_audioDevice && m_audioDevice->isOpen() && m_audioSink) {
                                if (m_swr) {
                                    swr_free(&m_swr);
                                }
                            
                                AVChannelLayout outLayout = {};
                                av_channel_layout_default(&outLayout, m_audioFormat.channelCount());
                            
                                const AVChannelLayout* inLayout = &m_audioCodecContext->ch_layout;
                            
                                int r = swr_alloc_set_opts2(
                                    &m_swr,
                                    &outLayout,
                                    AV_SAMPLE_FMT_S16,
                                    m_audioFormat.sampleRate(),
                                    inLayout,
                                    m_audioCodecContext->sample_fmt,
                                    m_audioCodecContext->sample_rate,
                                    0,
                                    nullptr
                                );
                            
                                av_channel_layout_uninit(&outLayout);
                            
                                if (r < 0 || !m_swr) {
                                    qWarning() << "[FFmpeg] Failed to allocate resampler - audio disabled";
                                    swr_free(&m_swr);
                                    m_swr = nullptr;
                                    if (m_audioSink) {
                                        if (m_audioDevice) {
                                            m_audioDevice->close();
                                        }
                                        m_audioSink->stop();
                                        m_audioSink->deleteLater();
                                        m_audioSink = nullptr;
                                        m_audioDevice = nullptr;
                                    }
                                } else {
                                    if (swr_init(m_swr) < 0) {
                                        qWarning() << "[FFmpeg] Failed to init resampler - audio disabled";
                                        swr_free(&m_swr);
                                        m_swr = nullptr;
                                        if (m_audioSink) {
                                            if (m_audioDevice) {
                                                m_audioDevice->close();
                                            }
                                            m_audioSink->stop();
                                            m_audioSink->deleteLater();
                                            m_audioSink = nullptr;
                                            m_audioDevice = nullptr;
                                        }
                                    } else {
                                        qDebug() << "[FFmpeg] Audio resampler initialized - input:" << inputSampleRate << "Hz," 
                                                 << inputChannels << "ch -> output:" << m_audioFormat.sampleRate() << "Hz," 
                                                 << m_audioFormat.channelCount() << "ch";
                                    }
                                }
                            }
                        }
                    } else {
                        qWarning() << "[FFmpeg] Failed to open audio decoder";
                        avcodec_free_context(&m_audioCodecContext);
                        m_audioCodecContext = nullptr;
                    }
                } else {
                    qWarning() << "[FFmpeg] Failed to copy audio codec parameters";
                    avcodec_free_context(&m_audioCodecContext);
                    m_audioCodecContext = nullptr;
                }
            } else {
                qWarning() << "[FFmpeg] Failed to allocate audio codec context";
            }
        } else {
            qWarning() << "[FFmpeg] Audio codec not found";
        }
    } else {
        qDebug() << "[FFmpeg] No audio stream found";
    }
    
    AVCodecParameters* codecpar = m_formatContext->streams[m_videoStreamIndex]->codecpar;
    
    const AVCodec* codec = avcodec_find_decoder(codecpar->codec_id);
    if (!codec) {
        qWarning() << "[FFmpeg] Codec not found";
        avformat_close_input(&m_formatContext);
        m_formatContext = nullptr;
        m_mediaOpening = false;
        m_mediaOpened = false;
        return;
    }
    
    m_codecContext = avcodec_alloc_context3(codec);
    if (!m_codecContext) {
        qWarning() << "[FFmpeg] Failed to allocate codec context";
        avformat_close_input(&m_formatContext);
        m_formatContext = nullptr;
        m_mediaOpening = false;
        m_mediaOpened = false;
        return;
    }
    
    ret = avcodec_parameters_to_context(m_codecContext, codecpar);
    if (ret < 0) {
        qWarning() << "[FFmpeg] Failed to copy codec parameters";
        avcodec_free_context(&m_codecContext);
        avformat_close_input(&m_formatContext);
        m_formatContext = nullptr;
        m_mediaOpening = false;
        m_mediaOpened = false;
        return;
    }
    
    m_gpuVendor = detectGPUVendor();
    if (!setupHardwareDecoder()) {
        qWarning() << "[FFmpeg] Failed to setup hardware decoder";
        avcodec_free_context(&m_codecContext);
        avformat_close_input(&m_formatContext);
        m_formatContext = nullptr;
        m_mediaOpening = false;
        m_mediaOpened = false;
        return;
    }
    
    if (!m_codecContext->opaque) {
        m_codecContext->opaque = this;
    }
    
    ret = avcodec_open2(m_codecContext, codec, nullptr);
    if (ret < 0) {
        char errbuf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(ret, errbuf, AV_ERROR_MAX_STRING_SIZE);
        qWarning() << "[FFmpeg] Failed to open codec:" << errbuf;
        avcodec_free_context(&m_codecContext);
        avformat_close_input(&m_formatContext);
        m_formatContext = nullptr;
        m_mediaOpening = false;
        m_mediaOpened = false;
        return;
    }
    
    m_width = m_codecContext->width;
    m_height = m_codecContext->height;
    
    emit implicitSizeChanged();
    
    if (m_formatContext->duration != AV_NOPTS_VALUE) {
        m_duration = (m_formatContext->duration / AV_TIME_BASE) * 1000;
        emit durationChanged();
        emit durationAvailable();
    }
    
    m_isSeekable = m_formatContext->pb != nullptr && 
                   (m_formatContext->pb->seekable & AVIO_SEEKABLE_NORMAL) != 0;
    emit seekableChanged();
    
    m_frame = av_frame_alloc();
    m_hwFrame = av_frame_alloc();
    if (m_useCUDA) {
        m_swFrame = av_frame_alloc();
    }
    m_transferFrame = av_frame_alloc();
    m_packet = av_packet_alloc();
    
    if (!m_frame || !m_hwFrame || !m_packet || (m_useCUDA && !m_swFrame) || !m_transferFrame) {
        qWarning() << "[FFmpeg] Failed to allocate frames/packet";
        closeMedia();
        return;
    }
    
    qDebug() << "[FFmpeg] Media opened successfully:" << m_width << "x" << m_height << "duration:" << m_duration << "ms";
    
    m_mediaOpening = false;
    m_mediaOpened = true;
    
    {
        QMutexLocker locker(&m_decodeMutex);
        m_decodeThreadRunning = true;
    }
    
    m_decodeThread = QThread::create([this]() { decodeThreadFunc(); });
    m_decodeThread->start();
}

void FFmpegVideoPlayer::closeMedia()
{
    QMutexLocker lifecycle(&m_mediaLifecycleMutex);
    stopPresenterThread();
    cleanupYtDlpPipe();
    if (m_openThread) {
        m_openThreadRunning.store(false, std::memory_order_release);
        m_openThread->wait(5000);
        delete m_openThread;
        m_openThread = nullptr;
    }
    m_avDiagFirstAudioWriteLogged.store(false, std::memory_order_release);
    m_avDiagFirstVideoQueuedLogged.store(false, std::memory_order_release);
    m_avDiagFirstVideoSinkLogged.store(false, std::memory_order_release);
    m_avDiagPacedFrameIndex = 0;
    m_avDiagAudioWriteSeq.store(0, std::memory_order_release);
    m_streamPtsGateDone = false;
    m_startupNoDropFrames = 6;
    m_lastVideoPtsRaw = NAN;
    m_timingInitialized = false;
    m_startTime = 0.0;
    m_startPts = 0.0;
    m_videoStream = nullptr;
    
    {
        QMutexLocker locker(&m_decodeMutex);
        m_decodeThreadRunning = false;
        m_decodeCondition.wakeAll();
    }
    
    if (m_decodeThread) {
        m_decodeThread->wait(5000);
        delete m_decodeThread;
        m_decodeThread = nullptr;
    }
    
    if (m_packet) {
        av_packet_free(&m_packet);
        m_packet = nullptr;
    }
    
    if (m_frame) {
        av_frame_free(&m_frame);
        m_frame = nullptr;
    }
    
    if (m_hwFrame) {
        av_frame_free(&m_hwFrame);
        m_hwFrame = nullptr;
    }
    
    if (m_swFrame) {
        av_frame_free(&m_swFrame);
        m_swFrame = nullptr;
    }
    
    if (m_transferFrame) {
        av_frame_free(&m_transferFrame);
        m_transferFrame = nullptr;
    }
    
    if (m_codecContext) {
        avcodec_free_context(&m_codecContext);
        m_codecContext = nullptr;
    }
    
    if (m_hwFramesContext) {
        av_buffer_unref(&m_hwFramesContext);
        m_hwFramesContext = nullptr;
    }
    
    if (m_hwDeviceContext) {
        av_buffer_unref(&m_hwDeviceContext);
        m_hwDeviceContext = nullptr;
    }
    
    if (m_audioSink) {
        m_audioSink->stop();
        delete m_audioSink;
        m_audioSink = nullptr;
        m_audioDevice = nullptr;
    }
    
    if (m_swr) {
        swr_free(&m_swr);
        m_swr = nullptr;
    }
    
    if (m_sws10to8) {
        sws_freeContext(m_sws10to8);
        m_sws10to8 = nullptr;
    }
    if (m_tmp8bitFrame) {
        av_frame_free(&m_tmp8bitFrame);
        m_tmp8bitFrame = nullptr;
    }
    
    cleanupHDRToneMappingFilter();
    
    if (m_audioFrame) {
        av_frame_free(&m_audioFrame);
        m_audioFrame = nullptr;
    }
    
    if (m_audioCodecContext) {
        avcodec_free_context(&m_audioCodecContext);
        m_audioCodecContext = nullptr;
    }
    
    if (m_formatContext) {
        avformat_close_input(&m_formatContext);
        m_formatContext = nullptr;
    }
    
    m_videoStreamIndex = -1;
    m_audioStreamIndex = -1;
    m_audioRemainder.clear();
    m_width = 0;
    m_height = 0;
    m_duration = 0;
    m_position = 0;
    m_audioClock = 0.0;
    m_firstAudioPts = NAN;
    m_firstVideoPts = NAN;
    m_avSyncOffsetValid = false;
    m_avSyncOffsetSec = 0.0;
    
    m_mediaOpened = false;
    m_mediaOpening = false;
    
    m_decoderDrained = false;
    m_sentAnyPacket = false;
    
    m_outWidth = 0;
    m_outHeight = 0;
    
    emit implicitSizeChanged();
    emit durationChanged();
}

FFmpegVideoPlayer::GPUVendor FFmpegVideoPlayer::detectGPUVendor()
{
#ifdef Q_OS_WIN
    if (!m_d3d11Device) {
        qWarning() << "[FFmpeg] Cannot detect GPU vendor: D3D11 device not available";
        return GPU_VENDOR_UNKNOWN;
    }
    
    // Query DXGI adapter from D3D11 device
    IDXGIDevice* dxgiDevice = nullptr;
    HRESULT hr = m_d3d11Device->QueryInterface(__uuidof(IDXGIDevice), reinterpret_cast<void**>(&dxgiDevice));
    if (FAILED(hr) || !dxgiDevice) {
        qWarning() << "[FFmpeg] Failed to query DXGI device:" << hr;
        return GPU_VENDOR_UNKNOWN;
    }
    
    IDXGIAdapter* adapter = nullptr;
    hr = dxgiDevice->GetAdapter(&adapter);
    dxgiDevice->Release();
    
    if (FAILED(hr) || !adapter) {
        qWarning() << "[FFmpeg] Failed to get DXGI adapter:" << hr;
        return GPU_VENDOR_UNKNOWN;
    }
    
    DXGI_ADAPTER_DESC desc = {};
    hr = adapter->GetDesc(&desc);
    adapter->Release();
    
    if (FAILED(hr)) {
        qWarning() << "[FFmpeg] Failed to get adapter description:" << hr;
        return GPU_VENDOR_UNKNOWN;
    }
    
    // Check vendor ID
    // NVIDIA: 0x10DE
    // Intel: 0x8086
    // AMD: 0x1002
    GPUVendor vendor = GPU_VENDOR_UNKNOWN;
    if (desc.VendorId == 0x10DE) {
        vendor = GPU_VENDOR_NVIDIA;
        qDebug() << "[FFmpeg] Detected NVIDIA GPU:" << QString::fromWCharArray(desc.Description);
    } else if (desc.VendorId == 0x8086) {
        vendor = GPU_VENDOR_INTEL;
        qDebug() << "[FFmpeg] Detected Intel GPU:" << QString::fromWCharArray(desc.Description);
    } else if (desc.VendorId == 0x1002) {
        vendor = GPU_VENDOR_AMD;
        qDebug() << "[FFmpeg] Detected AMD GPU:" << QString::fromWCharArray(desc.Description);
    } else {
        qDebug() << "[FFmpeg] Unknown GPU vendor ID:" << QString::number(desc.VendorId, 16) << QString::fromWCharArray(desc.Description);
    }
    
    return vendor;
#else
    return GPU_VENDOR_UNKNOWN;
#endif
}

bool FFmpegVideoPlayer::setupHardwareDecoder()
{
#ifdef Q_OS_WIN
    // On Windows, use D3D11VA for all GPUs (NVIDIA, Intel, AMD)
    // D3D11VA uses NVDEC under the hood on NVIDIA GPUs, so we get hardware acceleration
    // without needing CUDA/CUVID, and we get zero-copy D3D11 textures
    qDebug() << "[FFmpeg] Using D3D11VA hardware decode (works on NVIDIA/Intel/AMD)";
    m_useCUDA = false;
    return setupD3D11VADecoder();
#else
    // Non-Windows platforms would use other hwaccel (VAAPI, VideoToolbox, etc.)
    return false;
#endif
}

bool FFmpegVideoPlayer::setupD3D11VADecoder()
{
#ifdef Q_OS_WIN
    if (!m_codecContext) {
        qWarning() << "[FFmpeg] Missing codec context";
        return false;
    }

    // Free any existing device context
    av_buffer_unref(&m_hwDeviceContext);
    
    // Let FFmpeg create its own D3D11VA device (nullptr = auto-create)
    int ret = av_hwdevice_ctx_create(&m_hwDeviceContext, AV_HWDEVICE_TYPE_D3D11VA, nullptr, nullptr, 0);
    if (ret < 0) {
        char errbuf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(ret, errbuf, sizeof(errbuf));
        qWarning() << "[FFmpeg] Failed to create D3D11VA device:" << errbuf;
        av_buffer_unref(&m_hwDeviceContext);
        return false;
    }
    
    qDebug() << "[FFmpeg] D3D11VA device created by FFmpeg (independent device, more stable for decode)";
    
    m_codecContext->hw_device_ctx = av_buffer_ref(m_hwDeviceContext);
    m_codecContext->opaque = this;
    m_codecContext->get_format = getFormatCallback;

    qDebug() << "[FFmpeg] D3D11VA device initialized (FFmpeg-managed frames)";
    return true;
#else
    return false;
#endif
}

bool FFmpegVideoPlayer::setupCUDADecoder()
{
#ifdef Q_OS_WIN
    if (!m_codecContext || !m_formatContext || m_videoStreamIndex < 0) {
        qWarning() << "[FFmpeg] Missing codec context or stream info for CUVID setup";
        return false;
    }
    
    // Get codec ID from stream parameters (before we replace codec context)
    AVCodecParameters* codecpar = m_formatContext->streams[m_videoStreamIndex]->codecpar;
    AVCodecID codecId = codecpar->codec_id;
    
    // Get codec name based on codec ID
    const char* codecName = nullptr;
    switch (codecId) {
        case AV_CODEC_ID_H264:
            codecName = "h264_cuvid";
            break;
        case AV_CODEC_ID_HEVC:
            codecName = "hevc_cuvid";
            break;
        case AV_CODEC_ID_VP8:
            codecName = "vp8_cuvid";
            break;
        case AV_CODEC_ID_VP9:
            codecName = "vp9_cuvid";
            break;
        case AV_CODEC_ID_AV1:
            codecName = "av1_cuvid";
            break;
        default:
            qWarning() << "[FFmpeg] CUVID decoder not available for codec:" << codecId;
            return false;
    }
    
    // Create CUDA device context
    int ret = av_hwdevice_ctx_create(&m_hwDeviceContext, AV_HWDEVICE_TYPE_CUDA, nullptr, nullptr, 0);
    if (ret < 0) {
        char errbuf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(ret, errbuf, sizeof(errbuf));
        qWarning() << "[FFmpeg] Failed to create CUDA device context:" << errbuf;
        return false;
    }
    
    // Find CUVID decoder
    const AVCodec* cuvidCodec = avcodec_find_decoder_by_name(codecName);
    if (!cuvidCodec) {
        qWarning() << "[FFmpeg] CUVID decoder not found:" << codecName;
        av_buffer_unref(&m_hwDeviceContext);
        return false;
    }
    
    // Replace codec context with CUVID decoder
    avcodec_free_context(&m_codecContext);
    m_codecContext = avcodec_alloc_context3(cuvidCodec);
    if (!m_codecContext) {
        qWarning() << "[FFmpeg] Failed to allocate CUVID codec context";
        av_buffer_unref(&m_hwDeviceContext);
        return false;
    }
    
    // Copy codec parameters from stream
    ret = avcodec_parameters_to_context(m_codecContext, codecpar);
    if (ret < 0) {
        qWarning() << "[FFmpeg] Failed to copy codec parameters to CUVID context";
        avcodec_free_context(&m_codecContext);
        av_buffer_unref(&m_hwDeviceContext);
        return false;
    }
    
    // Attach CUDA device to codec context
    m_codecContext->hw_device_ctx = av_buffer_ref(m_hwDeviceContext);
    
    // Create hardware frames context for CUDA
    m_hwFramesContext = av_hwframe_ctx_alloc(m_hwDeviceContext);
    if (!m_hwFramesContext) {
        qWarning() << "[FFmpeg] Failed to allocate CUDA frames context";
        avcodec_free_context(&m_codecContext);
        av_buffer_unref(&m_hwDeviceContext);
        return false;
    }
    
    AVHWFramesContext* framesCtx = reinterpret_cast<AVHWFramesContext*>(m_hwFramesContext->data);
    framesCtx->format = AV_PIX_FMT_CUDA;
    framesCtx->sw_format = AV_PIX_FMT_NV12;  // CUVID outputs NV12
    framesCtx->width = m_codecContext->width;
    framesCtx->height = m_codecContext->height;
    framesCtx->initial_pool_size = 20;  // Frame pool size
    
    ret = av_hwframe_ctx_init(m_hwFramesContext);
    if (ret < 0) {
        char errbuf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(ret, errbuf, sizeof(errbuf));
        qWarning() << "[FFmpeg] Failed to initialize CUDA frames context:" << errbuf;
        av_buffer_unref(&m_hwFramesContext);
        avcodec_free_context(&m_codecContext);
        av_buffer_unref(&m_hwDeviceContext);
        return false;
    }
    
    m_codecContext->hw_frames_ctx = av_buffer_ref(m_hwFramesContext);
    
    qDebug() << "[FFmpeg] CUVID decoder initialized:" << codecName;
    return true;
#else
    return false;
#endif
}

QUrl FFmpegVideoPlayer::source() const
{
    return m_source;
}

void FFmpegVideoPlayer::setSource(const QUrl& source)
{
    QMutexLocker lifecycle(&m_mediaLifecycleMutex);
    if (!source.isValid() || source.isEmpty()) {
        qDebug() << "[FFmpeg] setSource(): ignoring empty/invalid source";
        return;
    }
    
    if (m_source == source) {
        return;
    }
    
    qDebug() << "[FFmpeg] setSource() called with:" << source;
    
    stop();
    closeMedia();
    
    m_source = source;
    emit sourceChanged();
    
    const QString srcStr = m_source.toString();
    const bool isYouTube = srcStr.contains(QStringLiteral("youtube.com"), Qt::CaseInsensitive)
        || srcStr.contains(QStringLiteral("youtu.be"), Qt::CaseInsensitive);
    if (m_useYtDlpPipe && isYouTube) {
        // Start yt-dlp on the object's thread so readyRead signals fire.
        if (!startYtDlpPipeProcess(m_source)) {
            return;
        }
        // Open FFmpeg on a dedicated thread to avoid UI freeze while waiting for pipe bytes.
        if (!m_openThread) {
            m_openThreadRunning.store(true, std::memory_order_release);
            m_openThread = QThread::create([this]() {
                this->openMedia();
                m_openThreadRunning.store(false, std::memory_order_release);
            });
            m_openThread->start();
        }
        return;
    }

    // Only open media if D3D11 is already initialized; otherwise, onSceneGraphInitialized() will open it.
    if (m_d3d11Device && m_d3d11Context) {
        openMedia();
    } else {
        qDebug() << "[FFmpeg] Source set, waiting for D3D11 initialization...";
    }
}

void FFmpegVideoPlayer::setVideoSink(QVideoSink* sink)
{
    if (m_videoSink == sink) return;
    m_videoSink = sink;
    emit videoSinkChanged();
}

void FFmpegVideoPlayer::setWindow(QQuickWindow* window)
{
    qDebug() << "[FFmpeg] setWindow called with:" << (window ? "valid window" : "nullptr");
    
    if (m_window == window) {
        return;
    }
    
    // Disconnect from old window
    if (m_window) {
        disconnect(m_window, nullptr, this, nullptr);
    }
    
    m_window = window;
    emit windowChanged();
    
    if (!m_window) {
        qDebug() << "[FFmpeg] Window set to nullptr";
        return;
    }
    
    connect(
        m_window,
        &QQuickWindow::sceneGraphInitialized,
        this,
        &FFmpegVideoPlayer::onSceneGraphInitialized,
        Qt::DirectConnection
    );
    
    // CRITICAL: If scene graph is already initialized, call immediately
    // This handles the case where window is set after scene graph is ready
    if (m_window->rhi()) {
        qDebug() << "[FFmpeg] Scene graph already initialized, initializing immediately";
        onSceneGraphInitialized();
    } else {
        qDebug() << "[FFmpeg] Window set, waiting for scene graph initialization...";
    }
}

void FFmpegVideoPlayer::play()
{
    QMutexLocker locker(&m_decodeMutex);
    
    // In pipe mode, allow play() to trigger openMedia() if the overlay calls play quickly after setSource().
    if (!m_mediaOpened) {
        const QString srcStr = m_source.toString();
        const bool isYouTube = srcStr.contains(QStringLiteral("youtube.com"), Qt::CaseInsensitive)
            || srcStr.contains(QStringLiteral("youtu.be"), Qt::CaseInsensitive);
        if (m_useYtDlpPipe && isYouTube && !m_mediaOpening) {
            locker.unlock();
            openMedia();
            locker.relock();
        }
        if (!m_mediaOpened) {
            qDebug() << "[FFmpeg] play(): media not opened yet";
            return;
        }
    }
    
    if (!m_formatContext) {
        qWarning() << "[FFmpeg] Cannot play - format context is null despite media being opened";
        return;
    }
    
    // If already playing and not paused, do nothing
    if (m_isPlaying.load(std::memory_order_acquire) && !m_isPaused.load(std::memory_order_acquire)) {
        qDebug() << "[FFmpeg] play() called but already playing - ignoring";
        return;
    }
    
    m_playStartWallTime = nowSeconds();

    // Ensure presenter is running (decode thread will start filling the queue).
    startPresenterThreadIfNeeded();
    
    // Handle resume from pause
    if (m_isPaused.load(std::memory_order_acquire)) {
        m_isPaused.store(false, std::memory_order_release);
        double pausedDuration = nowSeconds() - m_pauseTime;
        qDebug() << "[FFmpeg] Resuming from pause - paused for:" << pausedDuration << "seconds";

        // If audio master clock is wall-time anchored, make sure it does NOT advance while paused.
        // Otherwise masterClockAbs jumps forward on resume and we drop/burst a lot of video frames.
        if (!std::isnan(m_audioBasePts) && m_audioBaseWallTime > 0.0) {
            m_audioBaseWallTime += pausedDuration;
        }
        
        // Resume audio - check device state first to avoid AUDCLNT_E_NOT_STOPPED
        if (m_audioSink) {
            QMutexLocker audioLock(&m_audioMutex);
            if (m_audioDevice && m_audioDevice->isOpen()) {
                // Device is open - safe to resume
                // NOTE: QAudioSink::processedUSecs() automatically pauses when suspended,
                // so resume() will continue from where it left off - no timing adjustment needed
                m_audioSink->resume();
            } else {
                // Device was stopped - need to restart it
                qDebug() << "[FFmpeg] Audio device was stopped, restarting...";
                // Properly close device first to avoid AUDCLNT_E_NOT_STOPPED
                if (m_audioDevice && m_audioDevice->isOpen()) {
                    m_audioDevice->close();
                }
                m_audioSink->stop();
                m_audioSink->suspend();
                m_audioDevice = nullptr;
                QThread::msleep(20); // Wait for device release
                m_audioSink->setVolume(m_volume); // Ensure volume is set after restart
                m_audioDevice = m_audioSink->start();
                if (!m_audioDevice || !m_audioDevice->isOpen()) {
                    qWarning() << "[FFmpeg] Failed to restart audio device after pause";
                }
                audioLock.unlock(); // Release lock after audio operations
                // Reset audio base PTS since we're restarting
                m_audioBasePts = NAN;
                m_audioClock = 0.0;
            }
        }
        
        if (!m_audioSink || !m_audioDevice || !m_audioDevice->isOpen() || std::isnan(m_audioBasePts)) {
            // No audio - adjust wall clock to account for pause
            m_startTime += pausedDuration;
        } else {
            // Audio exists; keep wall-clock fallback aligned too (defensive).
            m_startTime += pausedDuration;
        }
        // If audio is available, don't adjust m_startTime - audio clock handles it
        
        // Wake up decode thread
        m_decodeCondition.wakeAll();
        locker.unlock();
        
        emit playbackStateChanged();
        return;
    }
    
    if (m_seekPending.load(std::memory_order_acquire)) {
        qDebug() << "[FFmpeg] play() called during seek - preserving seek state";
        m_isPlaying.store(true, std::memory_order_release);
        m_isPaused.store(false, std::memory_order_release);
        m_decodeCondition.wakeAll();
        locker.unlock();
        emit playbackStateChanged();
        return;
    }
    
    // Reset decoder state
    m_decoderDrained = false;
    m_sentAnyPacket = false;
    
    // Reset demuxer and seek to beginning (protected by demux mutex)
    {
        QMutexLocker demuxLocker(&m_demuxMutex);
        
        if (m_formatContext) {
            // Reset demuxer EOF + buffered packets
            avformat_flush(m_formatContext);

            // Seek to the start only if the stream is seekable (yt-dlp pipe often is not).
            if (m_isSeekable) {
                // Some MP4s have a non-zero container start_time. Seeking to 0 can land on a later
                // keyframe/segment and make the beginning appear "missing". Prefer the container start_time.
                const int64_t startTs = (m_formatContext->start_time != AV_NOPTS_VALUE) ? m_formatContext->start_time : 0;
                int seekRet = avformat_seek_file(
                    m_formatContext,
                    -1,                // any stream
                    INT64_MIN,
                    startTs,           // target timestamp (AV_TIME_BASE units)
                    INT64_MAX,
                    AVSEEK_FLAG_BACKWARD | AVSEEK_FLAG_ANY
                );
                
                if (seekRet < 0) {
                    qWarning() << "[FFmpeg] avformat_seek_file(0) failed:" << seekRet;
                } else {
                    qDebug() << "[FFmpeg] Reset to beginning of stream";
                }
            } else {
                qDebug() << "[FFmpeg] Stream not seekable; skipping reset-to-beginning";
            }
        }
    }
    
    // Decoder flush must happen AFTER demux reset
    if (m_codecContext) {
        avcodec_flush_buffers(m_codecContext);
    }
    
    m_timingInitialized = false;
    m_startTime = 0.0;
    m_startPts = 0.0;
    m_position = 0;
    m_audioBasePts = NAN;
    m_audioClock = 0.0;
    m_audioSeekPending.store(false, std::memory_order_release);
    m_audioProcessedBaseUSecs = 0;
    m_holdVideoUntilAudio.store(m_audioCodecContext != nullptr, std::memory_order_release);
    m_firstAudioPts = NAN;
    m_firstVideoPts = NAN;
    m_avSyncOffsetValid = false;
    m_avSyncOffsetSec = 0.0;
    m_audioBaseWallTime = 0.0;
    m_audioRemainder.clear();
    m_avDiagFirstAudioWriteLogged.store(false, std::memory_order_release);
    m_avDiagFirstVideoQueuedLogged.store(false, std::memory_order_release);
    m_avDiagFirstVideoSinkLogged.store(false, std::memory_order_release);
    m_avDiagPacedFrameIndex = 0;
    m_avDiagAudioWriteSeq.store(0, std::memory_order_release);
    m_streamPtsGateDone = false;
    m_startupNoDropFrames = 6;
    m_lastVideoPtsRaw = NAN;
    m_presentedAnyVideo.store(false, std::memory_order_release);

    if (m_audioSink) {
        if (!m_audioDevice || !m_audioDevice->isOpen()) {
            // Device not running - start it
            m_audioSink->setVolume(m_volume);
            m_audioDevice = m_audioSink->start();
            if (!m_audioDevice || !m_audioDevice->isOpen()) {
                qWarning() << "[FFmpeg] Failed to start audio device on play()";
            }
        } else {
            // Device already running - just ensure volume is correct and resume if paused
            m_audioSink->setVolume(m_volume);
            if (m_audioSink->state() == QAudio::SuspendedState) {
                m_audioSink->resume();
            }
        }
    }
    
    m_isPlaying.store(true, std::memory_order_release);
    m_isPaused.store(false, std::memory_order_release);
    
    // Wake up decode thread
    m_decodeCondition.wakeAll();
    locker.unlock();
    
    emit playbackStateChanged();
    emit positionChanged();
    
    qDebug() << "[FFmpeg] play() called - starting playback from beginning";
}

void FFmpegVideoPlayer::pause()
{
    QMutexLocker locker(&m_decodeMutex);
    
    if (!m_isPlaying.load(std::memory_order_acquire) || m_isPaused.load(std::memory_order_acquire)) {
        return; // Already paused or not playing
    }
    
    m_isPaused.store(true, std::memory_order_release);
    m_pauseTime = nowSeconds();

    // Stop presenter to avoid building a backlog while paused.
    stopPresenterThread();
    
    // Pause audio
    if (m_audioSink) {
        QMutexLocker audioLock(&m_audioMutex);
        m_audioSink->suspend();
    }
    
    // Decode thread will block on wait condition (already handled in decode loop)
    locker.unlock();
    
    emit playbackStateChanged();
    
    qDebug() << "[FFmpeg] pause() called";
}

void FFmpegVideoPlayer::stop()
{
    QMutexLocker locker(&m_decodeMutex);
    
    m_isPlaying.store(false, std::memory_order_release);
    m_isPaused.store(false, std::memory_order_release);

    // Stop presenter (clears queue, stops waiting).
    stopPresenterThread();
    
    // Stop audio
    if (m_audioSink) {
        QMutexLocker audioLock(&m_audioMutex);
        m_audioSink->stop();
    }
    
    // Reset timing
    m_timingInitialized = false;
    m_startTime = 0.0;
    m_startPts = 0.0;
    m_position = 0;
    m_audioClock = 0.0;
    m_avSyncOffsetValid = false;
    m_avSyncNeedMasterCalib = false;
    m_avSyncOffsetRefinedFromMaster = false;
    m_avSyncRefineCount = 0;
    m_presentedAnyVideo.store(false, std::memory_order_release);
    
    // Wake decode thread so it can exit cleanly
    m_decodeCondition.wakeAll();
    locker.unlock();
    
    emit playbackStateChanged();
    emit positionChanged();
    
    qDebug() << "[FFmpeg] stop() called";
}

void FFmpegVideoPlayer::seek(int ms)
{
    if (!m_formatContext || !m_codecContext || m_videoStreamIndex < 0 || !m_videoStream) {
        qWarning() << "[FFmpeg] Cannot seek - media not ready";
        return;
    }

    if (!m_isSeekable) {
        qWarning() << "[FFmpeg] Cannot seek - stream not seekable";
        return;
    }
    
    qDebug() << "[FFmpeg] seek() called from C++:" << ms << "ms";
    
    // Clamp seek position to valid range
    qint64 positionMs = qMax<qint64>(qint64(0), qint64(ms));
    if (m_duration > 0)
        positionMs = qMin<qint64>(positionMs, m_duration);
    
    QMutexLocker decodeLocker(&m_decodeMutex);
    QMutexLocker demuxLocker(&m_demuxMutex);
    
    // Convert ms → stream timebase
    AVRational timeBase = m_videoStream->time_base;
    int64_t seekPts = av_rescale_q(
        positionMs,
        AVRational{1, 1000},
        timeBase
    );
    
    qDebug() << "[FFmpeg] seek pts:" << seekPts << "timebase:" << timeBase.num << "/" << timeBase.den;
    
    // Flush demuxer (clears packet queues)
    avformat_flush(m_formatContext);
    
    // Perform seek (AVSEEK_FLAG_BACKWARD ensures we get a keyframe)
    int ret = av_seek_frame(
        m_formatContext,
        m_videoStreamIndex,
        seekPts,
        AVSEEK_FLAG_BACKWARD
    );
    
    if (ret < 0) {
        char errbuf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(ret, errbuf, sizeof(errbuf));
        qWarning() << "[FFmpeg] av_seek_frame failed:" << ret << errbuf;
        return;
    }
    
    // Flush decoders AFTER seek (critical - prevents old frames after seek)
    avcodec_flush_buffers(m_codecContext);
    
    // Reset timing for new position
    m_timingInitialized = false;
    double seekPtsSeconds = seekPts * av_q2d(timeBase);
    m_startPts = seekPtsSeconds;
    m_startTime = nowSeconds();
    m_playStartWallTime = nowSeconds();
    
    // Mark video seek as pending - decode loop will discard frames until we reach target
    m_seekTargetPts = seekPtsSeconds;
    m_seekPending.store(true, std::memory_order_release);
    m_avDiagFirstAudioWriteLogged.store(false, std::memory_order_release);
    m_avDiagFirstVideoQueuedLogged.store(false, std::memory_order_release);
    m_avDiagFirstVideoSinkLogged.store(false, std::memory_order_release);
    m_avDiagPacedFrameIndex = 0;
    m_avDiagAudioWriteSeq.store(0, std::memory_order_release);
    m_streamPtsGateDone = false;
    m_avSyncOffsetRefinedFromMaster = false;
    m_avSyncRefineCount = 0;
    
    if (m_audioCodecContext) {
        avcodec_flush_buffers(m_audioCodecContext);
        // Clear audio buffer - drop old audio data
        m_audioRemainder.clear();
        // Reset audio clock - will be set by first good frame after seek
        m_audioClock = 0.0;
        m_audioBasePts = NAN;
        m_firstAudioPts = NAN;
        m_firstVideoPts = NAN;
        m_avSyncOffsetValid = false;
        m_avSyncOffsetSec = 0.0;
        m_avSyncNeedMasterCalib = false;
        m_avSyncOffsetRefinedFromMaster = false;
        m_avSyncRefineCount = 0;
        // Clear processedUSecs base - will be snapshotted when first good frame arrives
        m_audioProcessedBaseUSecs = m_audioSink ? m_audioSink->processedUSecs() : 0;  // Optional snapshot, will be updated at first frame
        // Set audio seek target (in seconds) - decode loop will drop frames until we reach it
        m_audioSeekTargetSec = positionMs / 1000.0;  // Convert ms to seconds
        // Convert to audio stream timebase if available for better precision
        if (m_audioStreamIndex >= 0 && m_formatContext->streams[m_audioStreamIndex]) {
            AVStream* audioStream = m_formatContext->streams[m_audioStreamIndex];
            int64_t audioSeekPts = av_rescale_q(
                positionMs,
                AVRational{1, 1000},
                audioStream->time_base
            );
            m_audioSeekTargetSec = audioSeekPts * av_q2d(audioStream->time_base);
        }
        m_audioSeekPending.store(true, std::memory_order_release);
        
        m_holdVideoUntilAudio.store(true, std::memory_order_release);
        
        qDebug() << "[FFmpeg] Audio seek pending - target:" << m_audioSeekTargetSec << "seconds (device kept running, video held)";

        if (m_isSeekable && m_audioSink) {
            QMutexLocker audioLock(&m_audioMutex);
            if (m_audioDevice && m_audioDevice->isOpen())
                m_audioDevice->close();
            m_audioSink->stop();
            m_audioDevice = nullptr;
            m_audioSink->setVolume(m_volume);
            m_audioDevice = m_audioSink->start();
            m_audioProcessedBaseUSecs = 0;
            m_audioRemainder.clear();
        }
    } else {
        // No audio stream - video can present immediately
        m_holdVideoUntilAudio.store(false, std::memory_order_release);
    }
    
    // Update position immediately
    m_position = positionMs;
    
    // Reset decoder state
    m_decoderDrained = false;
    m_sentAnyPacket = false;
    
    // Wake decode thread to continue from new position
    m_decodeCondition.wakeAll();
    
    // Locks automatically released by RAII when lockers go out of scope
    emit positionChanged();
    
    qDebug() << "[FFmpeg] seek() completed to:" << positionMs << "ms (PTS:" << seekPts << "seconds:" << seekPtsSeconds << ")";
}

qint64 FFmpegVideoPlayer::position() const
{
    return m_position;
}

qint64 FFmpegVideoPlayer::duration() const
{
    return m_duration;
}

int FFmpegVideoPlayer::playbackState() const
{
    if (m_isPaused.load(std::memory_order_acquire)) return PausedState;
    if (m_isPlaying.load(std::memory_order_acquire)) return PlayingState;
    return StoppedState;
}

float FFmpegVideoPlayer::volume() const
{
    return m_volume;
}

void FFmpegVideoPlayer::setVolume(float volume)
{
    float newVolume = qBound(0.0f, volume, 1.0f);
    if (qFuzzyCompare(m_volume, newVolume)) {
        qDebug() << "[FFmpeg] setVolume called with same value:" << volume << "(ignored)";
        return; // No change
    }
    
    qDebug() << "[FFmpeg] setVolume called:" << volume << "->" << newVolume << "audioSink:" << (m_audioSink != nullptr);
    
    m_volume = newVolume;
    
    // Apply volume to audio sink if it exists
    if (m_audioSink) {
        m_audioSink->setVolume(m_volume);
        qDebug() << "[FFmpeg] Volume applied to audio sink:" << m_volume << "actual:" << m_audioSink->volume();
    } else {
        qDebug() << "[FFmpeg] Volume set but audio sink not available yet (will be applied when audio opens)";
    }
    
    emit volumeChanged();
}

void FFmpegVideoPlayer::setAudioEnabled(bool v)
{
    if (m_audioEnabled == v)
        return;
    m_audioEnabled = v;
    emit audioEnabledChanged();
}

void FFmpegVideoPlayer::setLogTag(const QString& v)
{
    if (m_logTag == v)
        return;
    m_logTag = v;
    emit logTagChanged();
}

bool FFmpegVideoPlayer::seekable() const
{
    return m_isSeekable;
}

enum AVPixelFormat FFmpegVideoPlayer::getFormatCallback(AVCodecContext* ctx, const enum AVPixelFormat* pix_fmts)
{
    auto* self = static_cast<FFmpegVideoPlayer*>(ctx->opaque);
    if (!self) {
        qWarning() << "[FFmpeg] getFormatCallback: opaque pointer is null, using fallback";
        return pix_fmts[0]; // Fallback to first format
    }
    
    // Log what formats FFmpeg is offering (debug)
    qDebug() << "[FFmpeg] get_format offered formats:";
    for (const enum AVPixelFormat* p = pix_fmts; *p != AV_PIX_FMT_NONE; ++p) {
        qDebug() << "  -" << av_get_pix_fmt_name(*p);
    }
    
    // Scan formats to understand what's available
    bool hasFastSysMem = false;
    bool has10BitOnly = false;
    bool hasD3D11 = false;
    
    for (const enum AVPixelFormat* p = pix_fmts; *p != AV_PIX_FMT_NONE; ++p) {
        if (*p == AV_PIX_FMT_NV12 || *p == AV_PIX_FMT_YUV420P || *p == AV_PIX_FMT_BGRA) {
            hasFastSysMem = true;
        } else if (*p == AV_PIX_FMT_YUV420P10LE) {
            has10BitOnly = true;
        } else if (*p == AV_PIX_FMT_D3D11) {
            hasD3D11 = true;
        }
    }
    
    // First: Prefer fast system memory formats (8-bit, direct QVideoSink support)
    for (const enum AVPixelFormat* p = pix_fmts; *p != AV_PIX_FMT_NONE; ++p) {
        if (*p == AV_PIX_FMT_NV12) {
            qDebug() << "[FFmpeg] Selected AV_PIX_FMT_NV12 (system memory, hardware decode)";
            return *p;
        }
        if (*p == AV_PIX_FMT_YUV420P) {
            qDebug() << "[FFmpeg] Selected AV_PIX_FMT_YUV420P (system memory, hardware decode)";
            return *p;
        }
        if (*p == AV_PIX_FMT_BGRA) {
            qDebug() << "[FFmpeg] Selected AV_PIX_FMT_BGRA (system memory, hardware decode)";
            return *p;
        }
    }
    
    if (has10BitOnly && !hasFastSysMem) {
        if (self->m_forceSoftwareHDRPath) {
            // Force software path for stability testing - avoids D3D11VA entirely
            for (const enum AVPixelFormat* p = pix_fmts; *p != AV_PIX_FMT_NONE; ++p) {
                if (*p == AV_PIX_FMT_YUV420P10LE) {
                    qDebug() << "[FFmpeg] Selected AV_PIX_FMT_YUV420P10LE (software HDR path - stability mode)";
                    return *p;
                }
            }
        } else if (hasD3D11) {
            // Default: prefer D3D11 texture over CPU conversion (av_hwframe_transfer_data() often gives NV12 8-bit directly)
            for (const enum AVPixelFormat* p = pix_fmts; *p != AV_PIX_FMT_NONE; ++p) {
                if (*p == AV_PIX_FMT_D3D11) {
                    qDebug() << "[FFmpeg] Selected AV_PIX_FMT_D3D11 (GPU texture) - HDR/DV detected, avoiding CPU 10-bit conversion";
                    return *p;
                }
            }
        }
    }
    
    for (const enum AVPixelFormat* p = pix_fmts; *p != AV_PIX_FMT_NONE; ++p) {
        if (*p == AV_PIX_FMT_YUV420P10LE) {
            qDebug() << "[FFmpeg] Selected AV_PIX_FMT_YUV420P10LE (10-bit HDR, will convert to 8-bit on CPU)";
            return *p;
        }
    }
    qWarning() << "[FFmpeg] No suitable system memory format available - using first offered format";
    return pix_fmts[0];  // Return first format (last-resort fallback)
}

void FFmpegVideoPlayer::setRenderer(QObject* renderer)
{
    // Cast to FFmpegVideoRenderer
    FFmpegVideoRenderer* videoRenderer = qobject_cast<FFmpegVideoRenderer*>(renderer);
    if (videoRenderer) {
        m_renderer = videoRenderer;
        // Set player reference in renderer so it can get pending frames
        videoRenderer->m_player = this;
        
        // Renderer is set - QQuickRhiItemRenderer will call getPendingFrame() in synchronize()
        qDebug() << "[FFmpeg] Renderer set - frames will be delivered via thread-safe handoff in synchronize()";
    } else if (renderer) {
        qWarning() << "[FFmpeg] setRenderer: object is not a FFmpegVideoRenderer";
        m_renderer = nullptr;
    } else {
        m_renderer = nullptr;
    }
}

bool FFmpegVideoPlayer::getPendingFrame(ID3D11Texture2D** texture, int* width, int* height)
{
    QMutexLocker locker(&m_pendingFrameMutex);
    
    if (m_pendingFrame.texture && m_pendingFrame.width > 0 && m_pendingFrame.height > 0) {
        *texture = m_pendingFrame.texture;
        *width = m_pendingFrame.width;
        *height = m_pendingFrame.height;
        
        // Clear pending frame (renderer takes ownership via AddRef)
        m_pendingFrame.texture = nullptr;
        m_pendingFrame.width = 0;
        m_pendingFrame.height = 0;
        
        return true;
    }
    
    return false;
}

