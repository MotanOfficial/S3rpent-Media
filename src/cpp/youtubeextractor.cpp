#include "youtubeextractor.h"

#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QProcess>
#include <QStandardPaths>
#include <QTimer>

#ifdef Q_OS_UNIX
#include <QFileDevice>
#endif

namespace {
#ifdef Q_OS_WIN
constexpr auto kYtDlpFileName = "yt-dlp.exe";
constexpr auto kDenoFileName = "deno.exe";
#else
constexpr auto kYtDlpFileName = "yt-dlp";
constexpr auto kDenoFileName = "deno";
#endif

QString cachedYtDlpPath()
{
    const QString base = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    if (base.isEmpty())
        return {};
    return QDir(base).filePath(QLatin1String(kYtDlpFileName));
}

/** Copy bundled/root yt-dlp into AppLocalData if missing or older; return true if dest is usable. */
bool ensureYtDlpCache(const QString &src, const QString &dest)
{
    const QFileInfo fiSrc(src);
    if (!fiSrc.exists() || !fiSrc.isFile())
        return false;

    QFileInfo fiDest(dest);
    if (!QDir().mkpath(fiDest.absolutePath())) {
        qWarning() << "[YouTubeExtractor] Cannot create directory for yt-dlp cache:" << fiDest.absolutePath();
        return false;
    }

    if (fiDest.exists() && fiDest.isFile()) {
        if (fiDest.lastModified() >= fiSrc.lastModified())
            return true;
        if (!QFile::remove(dest)) {
            qWarning() << "[YouTubeExtractor] Cannot replace stale yt-dlp at" << dest;
            return false;
        }
    }

    if (!QFile::copy(src, dest)) {
        qWarning() << "[YouTubeExtractor] Copy yt-dlp failed:" << src << "->" << dest;
        return false;
    }

#ifdef Q_OS_UNIX
    QFile::setPermissions(dest,
                          QFile::permissions(dest) | QFileDevice::ExeOwner | QFileDevice::ExeGroup
                              | QFileDevice::ExeOther);
#endif
    return true;
}

/**
 * 1) PATH
 * 2) AppLocalData copy (refreshed from app dir or cwd when newer)
 * 3) Run from applicationDir() or QDir::current() if present
 */
QString resolveYtDlpExecutable()
{
    QString p = QStandardPaths::findExecutable(QStringLiteral("yt-dlp"));
    if (!p.isEmpty())
        return QFileInfo(p).absoluteFilePath();
#ifdef Q_OS_WIN
    p = QStandardPaths::findExecutable(QStringLiteral("yt-dlp.exe"));
    if (!p.isEmpty())
        return QFileInfo(p).absoluteFilePath();
#endif

    const QString dest = cachedYtDlpPath();
    const QString appDirExe = QDir(QCoreApplication::applicationDirPath()).filePath(QLatin1String(kYtDlpFileName));
    const QString cwdExe = QDir(QDir::currentPath()).filePath(QLatin1String(kYtDlpFileName));

    const auto trySource = [&](const QString &src) -> QString {
        if (!QFileInfo::exists(src) || !QFileInfo(src).isFile())
            return {};
        if (!dest.isEmpty() && ensureYtDlpCache(src, dest))
            return QFileInfo(dest).absoluteFilePath();
        return QFileInfo(src).absoluteFilePath();
    };

    QString r = trySource(appDirExe);
    if (!r.isEmpty())
        return r;
    r = trySource(cwdExe);
    if (!r.isEmpty())
        return r;

    if (!dest.isEmpty() && QFileInfo::exists(dest))
        return QFileInfo(dest).absoluteFilePath();

    return {};
}

QString resolveDenoExecutable()
{
    QString p = QStandardPaths::findExecutable(QStringLiteral("deno"));
    if (!p.isEmpty())
        return QFileInfo(p).absoluteFilePath();
#ifdef Q_OS_WIN
    p = QStandardPaths::findExecutable(QStringLiteral("deno.exe"));
    if (!p.isEmpty())
        return QFileInfo(p).absoluteFilePath();
#endif

    // Check alongside the application and current working directory (common for portable bundling).
    const QString appDirExe = QDir(QCoreApplication::applicationDirPath()).filePath(QLatin1String(kDenoFileName));
    if (QFileInfo::exists(appDirExe) && QFileInfo(appDirExe).isFile())
        return QFileInfo(appDirExe).absoluteFilePath();

    const QString cwdExe = QDir(QDir::currentPath()).filePath(QLatin1String(kDenoFileName));
    if (QFileInfo::exists(cwdExe) && QFileInfo(cwdExe).isFile())
        return QFileInfo(cwdExe).absoluteFilePath();

    return {};
}

QString extractStreamUrlFromJson(const QJsonObject &o)
{
    const QJsonValue urlVal = o.value(QLatin1String("url"));
    if (urlVal.isString()) {
        const QString u = urlVal.toString();
        if (!u.isEmpty())
            return u;
    }
    const QJsonArray requested = o.value(QLatin1String("requested_formats")).toArray();
    for (const QJsonValue &v : requested) {
        const QJsonObject fmt = v.toObject();
        const QString acodec = fmt.value(QLatin1String("acodec")).toString();
        const QString vcodec = fmt.value(QLatin1String("vcodec")).toString();
        // Prefer the audio-only stream when yt-dlp returns split formats (bestvideo+bestaudio).
        if (!acodec.isEmpty() && acodec != QLatin1String("none")
            && (vcodec.isEmpty() || vcodec == QLatin1String("none"))) {
            const QString u = fmt.value(QLatin1String("url")).toString();
            if (!u.isEmpty())
                return u;
        }
    }
    // Fallback: any requested stream URL.
    for (const QJsonValue &v : requested) {
        const QJsonObject fmt = v.toObject();
        const QString u = fmt.value(QLatin1String("url")).toString();
        if (!u.isEmpty())
            return u;
    }
    const QJsonArray formats = o.value(QLatin1String("formats")).toArray();
    QString bestUrl;
    double bestAbr = -1.0;
    for (const QJsonValue &v : formats) {
        const QJsonObject fmt = v.toObject();
        const QString acodec = fmt.value(QLatin1String("acodec")).toString();
        if (acodec == QLatin1String("none"))
            continue;
        const QString u = fmt.value(QLatin1String("url")).toString();
        if (u.isEmpty())
            continue;
        const double abr = fmt.value(QLatin1String("abr")).toDouble();
        if (bestUrl.isEmpty() || abr > bestAbr) {
            bestUrl = u;
            bestAbr = abr;
        }
    }
    return bestUrl;
}

struct VideoPick {
    QString url;
    QString ext;
    QString vcodec;
    int height = -1;
    double tbr = -1.0;
};

VideoPick extractVideoStreamFromJson(const QJsonObject &o, int preferredMaxHeight)
{
    // Prefer a video-only URL (vcodec != none).
    // preferredMaxHeight: 0 = auto, otherwise cap by that height.
    const QJsonArray requested = o.value(QLatin1String("requested_formats")).toArray();
    auto tryList = [&](const QJsonArray &arr, int maxHeight, bool requireVideoOnly) -> VideoPick {
        VideoPick best;
        int bestScore = -1;

        for (const QJsonValue &v : arr) {
            const QJsonObject fmt = v.toObject();
            const QString vcodec = fmt.value(QLatin1String("vcodec")).toString();
            if (vcodec.isEmpty() || vcodec == QLatin1String("none"))
                continue;
            const QString acodec = fmt.value(QLatin1String("acodec")).toString();
            if (requireVideoOnly) {
                // Prefer video-only streams (many YouTube formats are video-only at high resolutions).
                if (!acodec.isEmpty() && acodec != QLatin1String("none"))
                    continue;
            }

            const QString u = fmt.value(QLatin1String("url")).toString();
            if (u.isEmpty())
                continue;

            const QString ext = fmt.value(QLatin1String("ext")).toString().toLower();
            const bool isMp4 = (ext == QLatin1String("mp4") || ext == QLatin1String("m4v"));
            const int h = fmt.value(QLatin1String("height")).toInt(-1);
            const double tbr = fmt.value(QLatin1String("tbr")).toDouble(-1.0);
            const QString vcodecLower = vcodec.toLower();
            const bool isAv1 = vcodecLower.contains(QLatin1String("av01")) || vcodecLower.contains(QLatin1String("av1"));
            const bool isVp9 = vcodecLower.contains(QLatin1String("vp09")) || vcodecLower.contains(QLatin1String("vp9"));
            // Qt Multimedia + FFmpeg on Windows tends to be happiest with H.264 in MP4 for progressive URLs,
            // but the user requested "prefer highest resolution under cap even if VP9/AV1", so codec is a tie-breaker.
            const bool isH264 = vcodecLower.contains(QLatin1String("avc"))
                || vcodecLower.contains(QLatin1String("h264"))
                || vcodecLower.contains(QLatin1String("h.264"));

            if (maxHeight > 0 && h > maxHeight)
                continue;

            const int clampedH = (h > 0) ? qMin(h, maxHeight > 0 ? maxHeight : h) : 0;

            int score = 0;
            // Primary objective: maximize resolution under cap.
            // Use a large weight so height dominates format/container choices.
            if (clampedH > 0)
                score += clampedH * 100000;
            // Secondary: prefer higher bitrate at same height.
            if (tbr > 0.0)
                score += static_cast<int>(qMin(tbr, 20000.0)) * 10;
            // Tertiary: small preferences (still helpful when multiple formats share height/tbr).
            if (isMp4)
                score += 200;
            if (isH264)
                score += 120;
            if (isVp9)
                score += 60;
            if (isAv1)
                score += 40;

            if (score > bestScore) {
                bestScore = score;
                best.url = u;
                best.ext = ext;
                best.vcodec = vcodec;
                best.height = h;
                best.tbr = tbr;
            }
        }
        return best;
    };

    // Auto mode: prefer <=720p first (usually much smoother), then <=1080p, then any.
    if (preferredMaxHeight <= 0) {
        VideoPick r = tryList(requested, 720, true);
        if (!r.url.isEmpty())
            return r;
        r = tryList(requested, 1080, true);
        if (!r.url.isEmpty())
            return r;
        r = tryList(requested, 0, true);
        if (!r.url.isEmpty())
            return r;

        // Fallback: if yt-dlp couldn't provide a video-only URL (some content/clients),
        // allow muxed A/V formats so the overlay can still show video (it is muted in QML).
        r = tryList(requested, 720, false);
        if (!r.url.isEmpty())
            return r;
        r = tryList(requested, 1080, false);
        if (!r.url.isEmpty())
            return r;
        r = tryList(requested, 0, false);
        if (!r.url.isEmpty())
            return r;
    } else {
        // Forced cap: pick the best format under that cap; if nothing found, fall back to auto tiers.
        VideoPick r = tryList(requested, preferredMaxHeight, true);
        if (!r.url.isEmpty())
            return r;
        r = tryList(requested, 720, true);
        if (!r.url.isEmpty())
            return r;
        r = tryList(requested, 1080, true);
        if (!r.url.isEmpty())
            return r;
        r = tryList(requested, 0, true);
        if (!r.url.isEmpty())
            return r;

        // Same fallback to muxed A/V.
        r = tryList(requested, preferredMaxHeight, false);
        if (!r.url.isEmpty())
            return r;
        r = tryList(requested, 720, false);
        if (!r.url.isEmpty())
            return r;
        r = tryList(requested, 1080, false);
        if (!r.url.isEmpty())
            return r;
        r = tryList(requested, 0, false);
        if (!r.url.isEmpty())
            return r;
    }

    const QJsonArray formats = o.value(QLatin1String("formats")).toArray();
    if (preferredMaxHeight <= 0) {
        VideoPick r = tryList(formats, 720, true);
        if (!r.url.isEmpty())
            return r;
        r = tryList(formats, 1080, true);
        if (!r.url.isEmpty())
            return r;
        r = tryList(formats, 0, true);
        if (!r.url.isEmpty())
            return r;

        r = tryList(formats, 720, false);
        if (!r.url.isEmpty())
            return r;
        r = tryList(formats, 1080, false);
        if (!r.url.isEmpty())
            return r;
        return tryList(formats, 0, false);
    } else {
        VideoPick r = tryList(formats, preferredMaxHeight, true);
        if (!r.url.isEmpty())
            return r;
        r = tryList(formats, 720, true);
        if (!r.url.isEmpty())
            return r;
        r = tryList(formats, 1080, true);
        if (!r.url.isEmpty())
            return r;
        r = tryList(formats, 0, true);
        if (!r.url.isEmpty())
            return r;

        r = tryList(formats, preferredMaxHeight, false);
        if (!r.url.isEmpty())
            return r;
        r = tryList(formats, 720, false);
        if (!r.url.isEmpty())
            return r;
        r = tryList(formats, 1080, false);
        if (!r.url.isEmpty())
            return r;
        return tryList(formats, 0, false);
    }
}

QString extractThumbnailFromJson(const QJsonObject &o)
{
    const QJsonValue thumb = o.value(QLatin1String("thumbnail"));
    if (thumb.isString()) {
        const QString u = thumb.toString();
        if (!u.isEmpty())
            return u;
    }
    const QJsonArray thumbs = o.value(QLatin1String("thumbnails")).toArray();
    if (!thumbs.isEmpty()) {
        const QJsonObject last = thumbs.last().toObject();
        const QString u = last.value(QLatin1String("url")).toString();
        if (!u.isEmpty())
            return u;
    }
    return {};
}

QString extractTitleFromJson(const QJsonObject &o)
{
    const QString track = o.value(QLatin1String("track")).toString();
    if (!track.isEmpty())
        return track;
    return o.value(QLatin1String("title")).toString();
}

QString extractArtistFromJson(const QJsonObject &o)
{
    const QString artist = o.value(QLatin1String("artist")).toString();
    if (!artist.isEmpty())
        return artist;
    const QString albumArtist = o.value(QLatin1String("album_artist")).toString();
    if (!albumArtist.isEmpty())
        return albumArtist;
    return o.value(QLatin1String("uploader")).toString();
}
} // namespace

YouTubeExtractor::YouTubeExtractor(QObject *parent)
    : QObject(parent)
    , m_browsers({QStringLiteral("chrome"), QStringLiteral("edge"), QStringLiteral("firefox")})
{
    m_timeoutTimer = new QTimer(this);
    m_timeoutTimer->setSingleShot(true);
    connect(m_timeoutTimer, &QTimer::timeout, this, &YouTubeExtractor::onTimeout);
}

YouTubeExtractor::~YouTubeExtractor()
{
    killActiveProcess();
}

void YouTubeExtractor::setPreferredVideoMaxHeight(int maxHeight)
{
    // 0 = auto; otherwise clamp to sensible values.
    if (maxHeight < 0)
        maxHeight = 0;
    m_preferredVideoMaxHeight = maxHeight;
}

void YouTubeExtractor::startExtract(const QString &videoUrl)
{
    const QString trimmed = videoUrl.trimmed();
    if (trimmed.isEmpty()) {
        fail(QStringLiteral("Empty video URL"));
        return;
    }

    if (trimmed == m_lastVideoUrl && m_lastSuccessTimer.isValid() && m_lastSuccessTimer.elapsed() < kCacheTtlMs
        && !m_lastStreamUrl.isEmpty()
        && m_lastPreferredVideoMaxHeight == m_preferredVideoMaxHeight) {
        emit finished(m_lastStreamUrl, m_lastTitle, m_lastArtist, m_lastThumbnailUrl, m_lastVideoStreamUrl);
        return;
    }

    killActiveProcess();
    m_videoUrl = trimmed;
    m_attemptIndex = 0;
    m_stdoutAccum.clear();
    m_activeBrowser.clear();

    m_resolvedYtDlp = resolveYtDlpExecutable();
    if (m_resolvedYtDlp.isEmpty()) {
        fail(QStringLiteral("yt-dlp not found. Add to PATH, place ") + QLatin1String(kYtDlpFileName)
             + QStringLiteral(" next to the app, or in the process working directory (e.g. project root)."));
        return;
    }

    tryNextAttempt();
}

void YouTubeExtractor::killActiveProcess()
{
    m_timeoutTimer->stop();
    if (m_process) {
        // Disconnect first so kill/crash does not run onProcessFinished (would double-advance browser).
        m_process->disconnect(this);
        if (m_process->state() != QProcess::NotRunning) {
            m_process->kill();
            m_process->waitForFinished(3000);
        }
        m_process->deleteLater();
        m_process = nullptr;
    }
}

void YouTubeExtractor::tryNextAttempt()
{
    // Attempt order is tuned to minimize JS-challenge (EJS/Node) requirements:
    // 0) cookieless + android,web_safari client
    // 1) cookieless + android client
    // 2) cookieless default clients
    // 3) chrome cookies
    // 4) edge cookies
    // 5) firefox cookies
    if (m_attemptIndex > 5) {
        fail(QStringLiteral("yt-dlp could not get an audio stream. Tips: run `yt-dlp -U` for the latest build; "
                           "if browser cookies fail (DPAPI), playback without login may still work; "
                           "age-restricted or premium content may need cookies from a browser launched as the same user."));
        return;
    }
    launchYtDlpForAttempt();
}

void YouTubeExtractor::launchYtDlpForAttempt()
{
    const QString bin = m_resolvedYtDlp;
    if (bin.isEmpty()) {
        fail(QStringLiteral("yt-dlp path not resolved"));
        return;
    }

    m_stdoutAccum.clear();
    switch (m_attemptIndex) {
    case 0:
        m_activeBrowser = QStringLiteral("cookieless+android,web_safari");
        break;
    case 1:
        m_activeBrowser = QStringLiteral("cookieless+android");
        break;
    case 2:
        m_activeBrowser = QStringLiteral("cookieless");
        break;
    case 3:
        m_activeBrowser = QStringLiteral("chrome");
        break;
    case 4:
        m_activeBrowser = QStringLiteral("edge");
        break;
    default:
        m_activeBrowser = QStringLiteral("firefox");
        break;
    }

    m_process = new QProcess(this);
    m_process->setProcessChannelMode(QProcess::SeparateChannels);

    QStringList args;
    // Avoid playlist expansion (extra requests) and prefer IPv4 for stability on some networks/CDNs.
    args << QStringLiteral("--no-playlist") << QStringLiteral("--force-ipv4");

    // Enable modern YouTube extraction which may require a JS runtime (EJS).
    // If deno.exe is bundled next to the app (or in cwd/PATH), use it explicitly.
    // This prevents yt-dlp from falling back to limited clients/formats.
    const QString denoPath = resolveDenoExecutable();
    if (!denoPath.isEmpty()) {
        args << QStringLiteral("--js-runtimes") << (QStringLiteral("deno:%1").arg(denoPath));
    } else {
        args << QStringLiteral("--js-runtimes") << QStringLiteral("deno");
    }
    args << QStringLiteral("--remote-components") << QStringLiteral("ejs:npm");

    // Prefer clients that typically avoid the JS "n" challenge, BUT:
    // For high quality video picks (1440p/2160p), Android clients often only expose low resolutions.
    // In that case, prefer web clients first so yt-dlp can see the full format list.
    const bool wantsHighResVideo = (m_preferredVideoMaxHeight >= 1440);
    if (wantsHighResVideo) {
        if (m_attemptIndex == 0) {
            // "web" tends to expose the richest set of DASH formats (VP9/AV1 included).
            args << QStringLiteral("--extractor-args") << QStringLiteral("youtube:player_client=web");
        } else if (m_attemptIndex == 1) {
            args << QStringLiteral("--extractor-args") << QStringLiteral("youtube:player_client=web_safari");
        } else if (m_attemptIndex == 2) {
            // Fall back to android variants after web attempts.
            args << QStringLiteral("--extractor-args") << QStringLiteral("youtube:player_client=android,web_safari");
        }
    } else {
        if (m_attemptIndex == 0) {
            args << QStringLiteral("--extractor-args") << QStringLiteral("youtube:player_client=android,web_safari");
        } else if (m_attemptIndex == 1) {
            args << QStringLiteral("--extractor-args") << QStringLiteral("youtube:player_client=android");
        }
    }

    // Cookies only after cookieless attempts (DPAPI decrypt can fail; also tends to be noisier).
    if (m_attemptIndex == 3)
        args << QStringLiteral("--cookies-from-browser") << QStringLiteral("chrome");
    else if (m_attemptIndex == 4)
        args << QStringLiteral("--cookies-from-browser") << QStringLiteral("edge");
    else if (m_attemptIndex == 5)
        args << QStringLiteral("--cookies-from-browser") << QStringLiteral("firefox");

    // Audio playback must remain reliable. Request an audio stream explicitly for the main pipeline.
    // We still get the full formats list in the JSON, so we can pick a separate video URL for overlays/UI.
    // -j: single JSON dump including formats[] metadata.
    args << QStringLiteral("-f") << QStringLiteral("bestaudio[ext=m4a]/bestaudio/best")
         << QStringLiteral("-j") << m_videoUrl;

    connect(m_process, &QProcess::finished, this, &YouTubeExtractor::onProcessFinished);
    connect(m_process, &QProcess::readyReadStandardOutput, this, &YouTubeExtractor::onReadyReadStdout);

    m_process->start(bin, args);
    if (!m_process->waitForStarted(5000)) {
        qWarning() << "[YouTubeExtractor] Failed to start yt-dlp:" << m_process->errorString();
        m_process->deleteLater();
        m_process = nullptr;
        ++m_attemptIndex;
        tryNextAttempt();
        return;
    }

    m_timeoutTimer->start(kTimeoutMs);
}

void YouTubeExtractor::onReadyReadStdout()
{
    if (!m_process)
        return;
    m_stdoutAccum.append(m_process->readAllStandardOutput());
}

void YouTubeExtractor::onTimeout()
{
    qWarning() << "[YouTubeExtractor] yt-dlp timed out (attempt:" << m_activeBrowser << ")";
    killActiveProcess();
    ++m_attemptIndex;
    tryNextAttempt();
}

void YouTubeExtractor::onProcessFinished(int exitCode, QProcess::ExitStatus status)
{
    m_timeoutTimer->stop();

    if (!m_process)
        return;

    m_stdoutAccum.append(m_process->readAllStandardOutput());
    const QByteArray err = m_process->readAllStandardError();
    m_process->deleteLater();
    m_process = nullptr;

    if (status == QProcess::CrashExit || exitCode != 0) {
        qWarning() << "[YouTubeExtractor] yt-dlp exit" << exitCode << "attempt:" << m_activeBrowser
                   << QString::fromUtf8(err).trimmed();
        ++m_attemptIndex;
        tryNextAttempt();
        return;
    }

    QJsonParseError pe{};
    const QJsonDocument doc = QJsonDocument::fromJson(m_stdoutAccum, &pe);
    if (pe.error != QJsonParseError::NoError || !doc.isObject()) {
        qWarning() << "[YouTubeExtractor] Invalid JSON from yt-dlp, attempt:" << m_activeBrowser << pe.errorString();
        ++m_attemptIndex;
        tryNextAttempt();
        return;
    }

    const QJsonObject obj = doc.object();
    const QString url = extractStreamUrlFromJson(obj);
    if (url.isEmpty()) {
        qWarning() << "[YouTubeExtractor] No stream URL in yt-dlp JSON, attempt:" << m_activeBrowser
                   << "stderr:" << QString::fromUtf8(err).trimmed();
        ++m_attemptIndex;
        tryNextAttempt();
        return;
    }

    const QString title = extractTitleFromJson(obj);
    const QString artist = extractArtistFromJson(obj);
    const QString thumb = extractThumbnailFromJson(obj);
    const VideoPick vp = extractVideoStreamFromJson(obj, m_preferredVideoMaxHeight);
    const QString videoUrl = vp.url;

    m_lastVideoUrl = m_videoUrl;
    m_lastStreamUrl = url;
    m_lastTitle = title;
    m_lastArtist = artist;
    m_lastThumbnailUrl = thumb;
    m_lastVideoStreamUrl = videoUrl;
    m_lastPreferredVideoMaxHeight = m_preferredVideoMaxHeight;
    m_lastSuccessTimer.restart();
    if (!videoUrl.isEmpty()) {
        qInfo() << "[YouTubeExtractor] Video pick"
                << "cap=" << m_preferredVideoMaxHeight
                << "h=" << vp.height
                << "ext=" << vp.ext
                << "vcodec=" << vp.vcodec
                << "tbr=" << vp.tbr;
    } else {
        qInfo() << "[YouTubeExtractor] Video pick: none (cap=" << m_preferredVideoMaxHeight << ")";
    }
    emit finished(url, title, artist, thumb, videoUrl);
}

void YouTubeExtractor::fail(const QString &message)
{
    qWarning() << "[YouTubeExtractor]" << message;
    emit failed(message);
}
