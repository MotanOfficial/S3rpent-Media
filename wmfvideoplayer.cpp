#include "wmfvideoplayer.h"
#include "wmfvideoplayer_helpers.h"
#include <QDebug>
#include <QFileInfo>
#include <QThread>
#include <QImage>
#include <QVideoFrame>
#include <QAudioFormat>
#include <QAudioDevice>
#include <QMediaDevices>
#include <QAudioSink>
#include <QMutex>
#include <QWaitCondition>
#include <QStandardPaths>
#include <QIODevice>
#include <QVariant>
#include <QProcess>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QMediaPlayer>
#include <QAudioOutput>
#include <QElapsedTimer>
#include <QRegularExpression>
#include <QSettings>
#include <QDateTime>
#include <cmath>

WMFVideoPlayer::WMFVideoPlayer(QObject *parent)
    : QObject(parent)
    , m_position(0)
    , m_duration(0)
    , m_containerDuration(0)
    , m_playbackState(0) // Stopped
    , m_volume(1.0)
    , m_seekable(false)
    , m_videoSink(nullptr)
    , m_videoReady(false)
    , m_audioSink(nullptr)
    , m_audioDevice(nullptr)
    , m_audioBytesWritten(0)
    , m_audioDecoded(false)
    , m_audioFeedTimer(nullptr)
    , m_mediaPlayer(nullptr)
    , m_audioOutput(nullptr)
    , m_ffmpegProcess(nullptr)
    , m_needsSpecialHandling(false)
    , m_lastSyncTime(0)
{
    // Load saved volume from settings
    QSettings settings;
    m_volume = settings.value("video/volume", 1.0).toReal();
    qDebug() << "[WMFVideoPlayer] Loaded saved volume:" << m_volume;
    
    // Setup QMediaPlayer for video (no audio - we use FFmpeg for that)
    setupMediaPlayer();
    
    m_positionTimer = new QTimer(this);
    m_positionTimer->setInterval(100); // Update every 100ms
    connect(m_positionTimer, &QTimer::timeout, this, &WMFVideoPlayer::updatePosition);
    
    // Timer to continuously feed audio to QAudioSink
    m_audioFeedTimer = new QTimer(this);
    m_audioFeedTimer->setInterval(50); // Check every 50ms
    connect(m_audioFeedTimer, &QTimer::timeout, this, [this]() {
        feedAudioToSink();
    });
}

WMFVideoPlayer::~WMFVideoPlayer()
{
    if (m_mediaPlayer) {
        m_mediaPlayer->stop();
    }
}

void WMFVideoPlayer::setSource(const QUrl &source)
{
    if (m_source == source)
        return;

    m_source = source;
    emit sourceChanged();

    if (!source.isEmpty()) {
        // Reset state when changing source
        m_containerDuration = 0;
        m_duration = 0;
        m_needsSpecialHandling = false;
        m_audioDecoded = false;
        m_decodedAudioData.clear();
        m_audioBytesWritten = 0;
        
        // Stop any existing audio feed
        if (m_audioFeedTimer) {
            m_audioFeedTimer->stop();
        }
        
        // Clean up FFmpeg audio sink if it exists
        if (m_audioSink) {
            if (m_audioDevice) {
                m_audioDevice->close();
                m_audioDevice = nullptr;
            }
            m_audioSink->stop();
            delete m_audioSink;
            m_audioSink = nullptr;
        }
        
        // Setup media player with video source
        if (m_mediaPlayer) {
            m_mediaPlayer->setSource(source);
            m_mediaPlayer->setPlaybackRate(1.0); // Reset to normal speed
            m_seekable = true;
            m_videoReady = true;
            emit seekableChanged();
        }
        
        // Enable QMediaPlayer audio by default (will be muted if special handling needed)
        if (m_audioOutput) {
            m_audioOutput->setVolume(m_volume);
        }
        
        // Wait for container duration, then detect if special handling is needed
        // Detection will happen in durationChanged signal
    } else {
        if (m_mediaPlayer) {
            m_mediaPlayer->setSource(QUrl());
            m_mediaPlayer->setPlaybackRate(1.0); // Reset to normal speed
        }
        m_videoReady = false;
        m_containerDuration = 0;
    }
}


void WMFVideoPlayer::setVolume(qreal volume)
{
    if (qFuzzyCompare(m_volume, volume))
        return;

    m_volume = qBound(0.0, volume, 1.0);
    qDebug() << "[WMFVideoPlayer] setVolume called:" << m_volume << ", needsSpecialHandling:" << m_needsSpecialHandling;
    
    if (m_needsSpecialHandling) {
        // For special handling videos, only set volume on FFmpeg audio sink
        // QMediaPlayer audio should remain muted (volume = 0.0)
        if (m_audioSink) {
            m_audioSink->setVolume(m_volume);
            qDebug() << "[WMFVideoPlayer] Set audioSink volume to:" << m_volume << "(special handling)";
        }
        // Keep QMediaPlayer audio muted
        if (m_audioOutput) {
            m_audioOutput->setVolume(0.0);
        }
    } else {
        // For normal videos, set volume on QMediaPlayer audio output
        if (m_audioOutput) {
            m_audioOutput->setVolume(m_volume);
            qDebug() << "[WMFVideoPlayer] Set audioOutput volume to:" << m_volume << "(normal video)";
        }
        // FFmpeg audio sink shouldn't exist for normal videos, but set it if it does
        if (m_audioSink) {
            m_audioSink->setVolume(m_volume);
        }
    }
    
    // Save volume to settings
    QSettings settings;
    settings.setValue("video/volume", m_volume);
    
    emit volumeChanged();
}


void WMFVideoPlayer::setVideoSink(QVideoSink *sink)
{
    if (m_videoSink == sink)
        return;

    m_videoSink = sink;
    
    // Set video sink on media player
    if (m_mediaPlayer) {
        m_mediaPlayer->setVideoSink(sink);
    }
    
    emit videoSinkChanged();
}

void WMFVideoPlayer::setupMediaPlayer()
{
    m_mediaPlayer = new QMediaPlayer(this);
    
    // Create audio output - volume will be set based on whether special handling is needed
    m_audioOutput = new QAudioOutput(this);
    m_audioOutput->setVolume(m_volume); // Start with normal volume (will be muted if special handling needed)
    m_mediaPlayer->setAudioOutput(m_audioOutput);
    
    // Connect signals
    connect(m_mediaPlayer, &QMediaPlayer::durationChanged, this, [this](qint64 duration) {
        // Store container duration (may be broken/inaccurate)
        int oldContainerDuration = m_containerDuration;
        m_containerDuration = (int)duration;
        
        // If we have container duration but haven't detected special handling yet, check now
        if (m_containerDuration > 0 && !m_needsSpecialHandling && m_duration == 0) {
            // Detect if special handling is needed (will decode audio and compare durations)
            detectSpecialHandling();
            return; // detectSpecialHandling will set m_duration and handle everything
        }
        
        // Only use Qt's duration if we don't have audio duration yet
        // Audio duration is more accurate (from actual decoded data)
        if (m_duration == 0 && duration > 0) {
            m_duration = (int)duration;
            emit durationChanged();
        }
        
        // Adjust video playback rate - use square root of ratio for smoother adjustment
        // Full ratio (2x) is too fast, 1x is too slow, sqrt gives middle ground (~1.4x for 2x ratio)
        if (m_duration > 0 && m_containerDuration > 0 && m_containerDuration != m_duration && 
            oldContainerDuration != m_containerDuration && m_needsSpecialHandling) {
            double fullRatio = (double)m_containerDuration / (double)m_duration;
            double adjustedRate = sqrt(fullRatio); // e.g., sqrt(2) ≈ 1.41
            m_mediaPlayer->setPlaybackRate(adjustedRate);
            qDebug() << "[MediaPlayer] Container:" << m_containerDuration << "ms, Audio:" << m_duration << "ms";
            qDebug() << "[MediaPlayer] Playback rate:" << adjustedRate << "x";
        } else if (m_containerDuration > 0 && !m_needsSpecialHandling) {
            qDebug() << "[MediaPlayer] Normal video - using QMediaPlayer audio (container duration:" << m_containerDuration << "ms)";
        }
    });
    
    connect(m_mediaPlayer, &QMediaPlayer::positionChanged, this, [this](qint64 position) {
        // Use audio position as the master timeline for special handling videos
        int newPosition = (int)position;
        
        if (m_needsSpecialHandling) {
            int audioPosition = calculateAudioPosition();
            newPosition = audioPosition;
            
            // Fall back to video position if audio not ready
            if (!m_audioDecoded || m_decodedAudioData.isEmpty()) {
                newPosition = (int)position;
            }
        }
        
        if (newPosition != m_position) {
            m_position = newPosition;
            emit positionChanged();
        }
    });
    
    connect(m_mediaPlayer, &QMediaPlayer::playbackStateChanged, this, [this]() {
        // Sync playback state
        QMediaPlayer::PlaybackState qtState = m_mediaPlayer->playbackState();
        int newState = 0;
        if (qtState == QMediaPlayer::PlayingState) {
            newState = 1;
        } else if (qtState == QMediaPlayer::PausedState) {
            newState = 2;
        }
        
        if (newState != m_playbackState) {
            m_playbackState = newState;
            emit playbackStateChanged();
        }
        
        // Video playback state changed - no need to stop early, let it sync with audio
    });
    
    m_videoReady = true;
}

void WMFVideoPlayer::updatePosition()
{
    // Calculate position from audio (master timeline) and update
    if (m_playbackState == 1) {
        int audioPosition = calculateAudioPosition();
        
        // No dynamic sync - playback rate is set once at start
        
        // Update position from audio
        if (audioPosition != m_position) {
            m_position = audioPosition;
            emit positionChanged();
        }
    }
}

int WMFVideoPlayer::calculateAudioPosition()
{
    // Calculate current playback position from audio bytes written
    // Audio is the master timeline since it's accurately decoded
    if (!m_audioDecoded || m_decodedAudioData.isEmpty() || !m_audioSink) {
        return m_position; // Fall back to current position
    }
    
    QAudioFormat format = m_audioSink->format();
    int sampleRate = format.sampleRate();
    int channels = format.channelCount();
    int bytesPerSample = format.bytesPerSample();
    
    if (sampleRate > 0 && channels > 0 && bytesPerSample > 0) {
        // Calculate position in milliseconds from bytes written
        qint64 totalSamples = m_audioBytesWritten / bytesPerSample;
        qint64 positionMs = (totalSamples * 1000) / (sampleRate * channels);
        return (int)positionMs;
    }
    
    return m_position; // Fall back to current position
}

void WMFVideoPlayer::detectSpecialHandling()
{
    // Check if video has broken timestamps by decoding a small sample of audio
    // and comparing the calculated duration with container duration
    
    if (m_source.isEmpty() || !m_source.isLocalFile() || m_containerDuration <= 0) {
        // Can't detect, assume normal handling
        m_needsSpecialHandling = false;
        m_duration = m_containerDuration;
        emit durationChanged();
        return;
    }
    
    QString filePath = m_source.toLocalFile();
    if (!QFileInfo::exists(filePath)) {
        m_needsSpecialHandling = false;
        m_duration = m_containerDuration;
        emit durationChanged();
        return;
    }
    
    qDebug() << "[MediaPlayer] Detecting if special handling needed (container duration:" << m_containerDuration << "ms)...";
    
    // Decode a small sample of audio (first 2 seconds) to estimate actual duration
    // This is faster than decoding the full track
    QString program = "ffmpeg";
#ifdef Q_OS_WIN
    program = "ffmpeg.exe";
#endif
    
    QStringList arguments;
    arguments << "-fflags" << "+genpts+igndts+discardcorrupt"
              << "-err_detect" << "ignore_err"
              << "-avoid_negative_ts" << "make_zero"
              << "-i" << filePath
              << "-vn"                            // No video
              << "-acodec" << "pcm_s16le"         // PCM 16-bit little-endian
              << "-ar" << "44100"                 // 44.1kHz sample rate
              << "-ac" << "1"                     // Mono (faster for detection)
              << "-f" << "s16le"                  // Format: signed 16-bit little-endian
              << "-loglevel" << "fatal"           // Minimal logging
              << "-hide_banner"
              << "pipe:1";                        // Output to stdout
    
    QProcess ffmpegProcess;
    ffmpegProcess.setProcessChannelMode(QProcess::SeparateChannels);
    ffmpegProcess.start(program, arguments);
    
    if (!ffmpegProcess.waitForStarted(5000)) {
        // FFmpeg failed, assume normal handling
        qDebug() << "[MediaPlayer] FFmpeg detection failed, using normal handling";
        m_needsSpecialHandling = false;
        m_duration = m_containerDuration;
        emit durationChanged();
        return;
    }
    
    // Read all audio data (decode full track to get accurate duration)
    QByteArray fullAudioData;
    QElapsedTimer decodeTimer;
    decodeTimer.start();
    
    while (ffmpegProcess.state() == QProcess::Running && decodeTimer.elapsed() < 30000) {
        if (ffmpegProcess.waitForReadyRead(500)) {
            QByteArray chunk = ffmpegProcess.readAllStandardOutput();
            if (!chunk.isEmpty()) {
                fullAudioData.append(chunk);
            }
        }
        
        // Check if process finished
        if (ffmpegProcess.atEnd()) {
            break;
        }
    }
    
    // Wait for process to finish
    if (!ffmpegProcess.waitForFinished(5000)) {
        qWarning() << "[MediaPlayer] FFmpeg detection timed out after" << decodeTimer.elapsed() << "ms, using normal handling";
        ffmpegProcess.kill();
        m_needsSpecialHandling = false;
        m_duration = m_containerDuration;
        emit durationChanged();
        return;
    }
    
    // Check exit code
    if (ffmpegProcess.exitCode() != 0) {
        QByteArray errorOutput = ffmpegProcess.readAllStandardError();
        qWarning() << "[MediaPlayer] FFmpeg detection failed with exit code" << ffmpegProcess.exitCode();
        if (!errorOutput.isEmpty() && errorOutput.size() < 500) {
            qWarning() << "[MediaPlayer] FFmpeg error:" << errorOutput;
        }
    }
    
    // Get any remaining data
    QByteArray remainingData = ffmpegProcess.readAllStandardOutput();
    if (!remainingData.isEmpty()) {
        fullAudioData.append(remainingData);
    }
    
    if (fullAudioData.isEmpty()) {
        // No audio data, assume normal handling
        qDebug() << "[MediaPlayer] No audio data decoded, using normal handling";
        m_needsSpecialHandling = false;
        m_duration = m_containerDuration;
        emit durationChanged();
        return;
    }
    
    qDebug() << "[MediaPlayer] Decoded" << fullAudioData.size() << "bytes of audio for detection";
    
    // Calculate actual duration from audio data size
    // Duration = bytes / (sample_rate * channels * bytes_per_sample)
    int sampleRate = 44100;
    int channels = 1;
    int bytesPerSample = 2;
    qint64 totalSamples = fullAudioData.size() / bytesPerSample;
    int actualDurationMs = (int)((totalSamples * 1000) / (sampleRate * channels));
    
    qDebug() << "[MediaPlayer] Calculated actual duration:" << actualDurationMs << "ms from" << fullAudioData.size() << "bytes";
    
    // Compare durations - if they differ by more than 5% or 1 second, use special handling
    int durationDiff = qAbs(m_containerDuration - actualDurationMs);
    double durationRatio = actualDurationMs > 0 ? (double)qMax(m_containerDuration, actualDurationMs) / (double)qMin(m_containerDuration, actualDurationMs) : 1.0;
    bool significantDifference = durationDiff > 1000 || durationRatio > 1.05;
    
    qDebug() << "[MediaPlayer] Duration comparison - Container:" << m_containerDuration << "ms, Actual:" << actualDurationMs << "ms, Diff:" << durationDiff << "ms, Ratio:" << durationRatio << ", Significant:" << significantDifference;
    
    if (significantDifference && actualDurationMs > 0) {
        m_needsSpecialHandling = true;
        qDebug() << "[MediaPlayer] Special handling needed! Container:" << m_containerDuration << "ms, Actual:" << actualDurationMs << "ms (diff:" << durationDiff << "ms, ratio:" << durationRatio << ")";
        
        // Mute QMediaPlayer audio
        if (m_audioOutput) {
            m_audioOutput->setVolume(0.0);
            qDebug() << "[MediaPlayer] Muted QMediaPlayer audio (volume set to 0.0)";
        } else {
            qWarning() << "[MediaPlayer] m_audioOutput is null, cannot mute QMediaPlayer audio!";
        }
        
        // Store the decoded audio data and set duration
        m_decodedAudioData = fullAudioData;
        m_duration = actualDurationMs;
        m_audioDecoded = true;
        qDebug() << "[MediaPlayer] Stored decoded audio data:" << m_decodedAudioData.size() << "bytes, audioDecoded:" << m_audioDecoded;
        
        // Setup audio output for FFmpeg audio (but preserve audioDecoded flag and decoded data)
        bool wasDecoded = m_audioDecoded;
        QByteArray savedAudioData = m_decodedAudioData;
        setupAudioOutput(1); // Mono for now, will be updated if needed
        // Restore the decoded audio data and flag after setupAudioOutput resets them
        m_audioDecoded = wasDecoded;
        m_decodedAudioData = savedAudioData;
        qDebug() << "[MediaPlayer] Audio sink setup complete, audioSink:" << (m_audioSink != nullptr) << ", audioDecoded restored:" << m_audioDecoded;
        
        // Set adjusted playback rate
        if (m_mediaPlayer && m_containerDuration > 0 && m_duration > 0 && m_containerDuration != m_duration) {
            double fullRatio = (double)m_containerDuration / (double)m_duration;
            double adjustedRate = sqrt(fullRatio);
            m_mediaPlayer->setPlaybackRate(adjustedRate);
            qDebug() << "[MediaPlayer] Set video playback rate to" << adjustedRate << "x";
        }
        
        emit durationChanged();
        
        // Auto-start playback if video is ready
        if (m_playbackState == 0 && m_videoReady) {
            qDebug() << "[FFmpeg Audio] Auto-starting playback after detection (video ready)";
            play();
        }
    } else {
        m_needsSpecialHandling = false;
        m_duration = m_containerDuration;
        qDebug() << "[MediaPlayer] Normal video detected (container:" << m_containerDuration << "ms, actual:" << actualDurationMs << "ms) - using QMediaPlayer audio";
        
        // Ensure QMediaPlayer audio is enabled with correct volume
        if (m_audioOutput) {
            m_audioOutput->setVolume(m_volume);
            qDebug() << "[MediaPlayer] Set audioOutput volume to:" << m_volume << "after normal video detection";
        }
        
        emit durationChanged();
        
        // Auto-start playback if video is ready (same as special handling case)
        if (m_playbackState == 0 && m_videoReady) {
            qDebug() << "[MediaPlayer] Auto-starting playback after detection (video ready)";
            play();
        }
    }
}

void WMFVideoPlayer::decodeAllAudio()
{
    // Decode entire audio track using FFmpeg (handles corrupted samples better than WMF)
    // This allows audio to play independently from video
    
    if (m_source.isEmpty() || !m_source.isLocalFile()) {
        qDebug() << "[FFmpeg Audio] Source is not a local file";
        m_audioDecoded = false;
        return;
    }
    
    QString filePath = m_source.toLocalFile();
    if (!QFileInfo::exists(filePath)) {
        qDebug() << "[FFmpeg Audio] File does not exist:" << filePath;
        m_audioDecoded = false;
        return;
    }
    
    qDebug() << "[FFmpeg Audio] Decoding entire audio track with FFmpeg (handles corrupted samples)...";
    m_decodedAudioData.clear();
    m_audioDecoded = false;
    
    // Use FFmpeg to decode audio with flags to handle corrupted samples
    QString program = "ffmpeg";
#ifdef Q_OS_WIN
    program = "ffmpeg.exe";
#endif
    
    QStringList arguments;
    // Get channel count from audio sink (if already set up)
    int ffmpegChannels = 1; // Default to mono
    if (m_audioSink) {
        QAudioFormat format = m_audioSink->format();
        ffmpegChannels = format.channelCount();
        qDebug() << "[FFmpeg Audio] Using" << ffmpegChannels << "channels for FFmpeg decode (matching audio output)";
    } else {
        // Setup audio output first (default to mono, will be updated if needed)
        setupAudioOutput(1);
        if (m_audioSink) {
            QAudioFormat format = m_audioSink->format();
            ffmpegChannels = format.channelCount();
        }
    }
    
    arguments << "-fflags" << "+genpts+igndts+discardcorrupt"  // Generate PTS, ignore DTS, discard corrupt
              << "-err_detect" << "ignore_err"                 // Ignore errors
              << "-avoid_negative_ts" << "make_zero"           // Handle negative timestamps
              << "-i" << filePath
              << "-vn"                            // No video
              << "-acodec" << "pcm_s16le"         // PCM 16-bit little-endian
              << "-ar" << "44100"                 // 44.1kHz sample rate
              << "-ac" << QString::number(ffmpegChannels)  // Use detected channel count
              << "-f" << "s16le"                  // Format: signed 16-bit little-endian
              << "-loglevel" << "fatal"           // Only show fatal errors (suppress AAC warnings)
              << "-hide_banner"                   // Hide banner
              << "pipe:1";                        // Output to stdout
    
    QProcess ffmpegProcess;
    ffmpegProcess.setProcessChannelMode(QProcess::SeparateChannels);
    // Don't redirect stderr - just ignore it by not reading from it
    // The AAC warnings are non-fatal and will just appear in console
    // Redirecting stderr was causing "Could not open output redirection for writing" error
    ffmpegProcess.start(program, arguments);
    
    if (!ffmpegProcess.waitForStarted(5000)) {
        qWarning() << "[FFmpeg Audio] Failed to start FFmpeg:" << ffmpegProcess.errorString();
        m_audioDecoded = false;
        return;
    }
    
    // Read all audio data from FFmpeg's stdout
    QByteArray audioData;
    while (ffmpegProcess.state() == QProcess::Running) {
        ffmpegProcess.waitForReadyRead(100);
        QByteArray chunk = ffmpegProcess.readAllStandardOutput();
        if (!chunk.isEmpty()) {
            audioData.append(chunk);
        } else if (ffmpegProcess.atEnd()) {
            break;
        }
    }
    
    // Wait for process to finish
    ffmpegProcess.waitForFinished(30000); // Wait up to 30 seconds
    
    if (ffmpegProcess.exitCode() != 0) {
        QByteArray errorOutput = ffmpegProcess.readAllStandardError();
        qWarning() << "[FFmpeg Audio] FFmpeg failed with exit code" << ffmpegProcess.exitCode();
        qWarning() << "[FFmpeg Audio] Error output:" << errorOutput;
        m_audioDecoded = false;
        return;
    }
    
    // Get any remaining data
    QByteArray remainingData = ffmpegProcess.readAllStandardOutput();
    if (!remainingData.isEmpty()) {
        audioData.append(remainingData);
    }
    
    if (audioData.isEmpty()) {
        qWarning() << "[FFmpeg Audio] No audio data decoded";
        m_audioDecoded = false;
        return;
    }
    
    m_decodedAudioData = audioData;
    
    // Calculate actual duration from decoded audio data size
    // This is more reliable than timestamps which may be broken
    // Duration = bytes / (sample_rate * channels * bytes_per_sample)
    if (!m_decodedAudioData.isEmpty() && m_audioSink) {
        // Get audio format from QAudioSink
        QAudioFormat format = m_audioSink->format();
        int sampleRate = format.sampleRate();
        int channels = format.channelCount();
        int bytesPerSample = format.bytesPerSample();
        
        if (sampleRate > 0 && channels > 0 && bytesPerSample > 0) {
            // Calculate duration in milliseconds
            qint64 totalSamples = m_decodedAudioData.size() / bytesPerSample;
            qint64 durationMs = (totalSamples * 1000) / (sampleRate * channels);
            
            if (durationMs > 0) {
                int newDuration = (int)durationMs;
                int oldDuration = m_duration;
                // CRITICAL: Always use the audio-calculated duration - it's more accurate than container timestamps
                // This will override Qt Multimedia's broken duration
                m_duration = newDuration;
                emit durationChanged();
                qDebug() << "[FFmpeg Audio] Actual duration from audio data size:" << m_duration << "ms (was" << oldDuration << "ms from broken timestamps)";
            }
        }
    }
    
    m_audioDecoded = true;
    qDebug() << "[FFmpeg Audio] Decoded audio track, total size:" << m_decodedAudioData.size() << "bytes";
    
    // Auto-start playback if video is ready (autoplay behavior)
    if (m_playbackState == 0 && m_videoReady) {
        // Video is loaded and ready, auto-start playback
        qDebug() << "[FFmpeg Audio] Auto-starting playback after audio decode (video ready)";
        play();
    } else {
        qDebug() << "[FFmpeg Audio] Not auto-starting - video not ready yet (ready:" << m_videoReady << ")";
    }
}

void WMFVideoPlayer::feedAudioToSink()
{
    // Continuously feed decoded audio to QAudioSink
    // This runs independently of video playback
    // QAudioSink handles the playback rate automatically
    
    static int callCount = 0;
    callCount++;
    
    try {
        if (m_playbackState != 1) {
            if (callCount <= 5) qDebug() << "[FFmpeg Audio] feedAudioToSink #" << callCount << "- not playing, state:" << m_playbackState;
            return; // Not playing
        }
        
        if (!m_audioDecoded) {
            if (callCount <= 5) qWarning() << "[FFmpeg Audio] feedAudioToSink #" << callCount << "- audio not decoded yet";
            return; // Audio not decoded
        }
        
        if (!m_audioSink) {
            if (callCount <= 5) qWarning() << "[FFmpeg Audio] feedAudioToSink #" << callCount << "- audio sink is null";
            return; // Audio sink is null
        }
        
        if (!m_audioDevice) {
            if (callCount <= 5) qWarning() << "[FFmpeg Audio] feedAudioToSink #" << callCount << "- audio device is null";
            return; // Audio device is null
        }
        
        if (m_decodedAudioData.isEmpty()) {
            if (callCount <= 5) qWarning() << "[FFmpeg Audio] feedAudioToSink #" << callCount << "- decoded audio data is empty";
            return; // Decoded audio data is empty
        }
        
        if (callCount <= 5) {
            qDebug() << "[FFmpeg Audio] feedAudioToSink #" << callCount << "- feeding audio, bytes written so far:" << m_audioBytesWritten << "of" << m_decodedAudioData.size();
        }
        
        // Additional safety check - make sure audio device is still valid
        bool deviceOpen = false;
        try {
            deviceOpen = m_audioDevice->isOpen();
        } catch (...) {
            // Device might be destroyed - stop timer
            if (m_audioFeedTimer) {
                m_audioFeedTimer->stop();
            }
            return;
        }
        
        if (!deviceOpen) {
            // Device not open - stop timer
            if (m_audioFeedTimer) {
                m_audioFeedTimer->stop();
            }
            return;
        }
        
        // Calculate how much audio data we haven't written yet
        qint64 remainingBytes = m_decodedAudioData.size() - m_audioBytesWritten;
        if (remainingBytes <= 0) {
            // All audio has been written, stop the timer
            if (m_audioFeedTimer) {
                m_audioFeedTimer->stop();
            }
            qDebug() << "[FFmpeg Audio] Finished feeding all audio data to QAudioSink";
            // Don't stop playback - let video continue if needed, it will sync via position updates
            return;
        }
        
        // Write chunks of audio data to keep the buffer filled
        // QAudioSink will consume at its natural rate
        const qint64 chunkSize = 8192; // 8KB chunks
        qint64 bytesToWrite = qMin(remainingBytes, chunkSize);
        
        // Safety check - make sure we don't go out of bounds
        if (m_audioBytesWritten < 0 || m_audioBytesWritten >= m_decodedAudioData.size()) {
            qWarning() << "[FFmpeg Audio] Invalid audio position:" << m_audioBytesWritten << "of" << m_decodedAudioData.size();
            m_audioBytesWritten = 0; // Reset to beginning
            return;
        }
        
        // Additional bounds check before accessing data
        if (m_audioBytesWritten + bytesToWrite > m_decodedAudioData.size()) {
            bytesToWrite = m_decodedAudioData.size() - m_audioBytesWritten;
        }
        
        if (bytesToWrite <= 0) {
            return; // Nothing to write
        }
        
        // Write data safely
        const char *dataToWrite = m_decodedAudioData.constData() + m_audioBytesWritten;
        qint64 written = 0;
        
        try {
            written = m_audioDevice->write(dataToWrite, bytesToWrite);
        } catch (...) {
            qWarning() << "[FFmpeg Audio] Exception writing to audio device";
            if (m_audioFeedTimer) {
                m_audioFeedTimer->stop();
            }
            return;
        }
        
        if (written > 0) {
            m_audioBytesWritten += written;
            // Log first few writes to verify it's working
            static int writeCount = 0;
            writeCount++;
            if (writeCount <= 5 || m_audioBytesWritten % (1024 * 100) == 0) { // First 5 writes + every ~100KB
                qDebug() << "[FFmpeg Audio] Fed" << written << "bytes (total:" << m_audioBytesWritten << "of" << m_decodedAudioData.size() << ")";
            }
        } else if (written < 0) {
            // Error writing - stop feeding
            qWarning() << "[FFmpeg Audio] Error writing to audio device, written:" << written;
            if (m_audioFeedTimer) {
                m_audioFeedTimer->stop();
            }
        } else {
            // Can't write more right now (buffer might be full), will try again next time
        }
    } catch (...) {
        qWarning() << "[FFmpeg Audio] Exception in feedAudioToSink()";
        if (m_audioFeedTimer) {
            m_audioFeedTimer->stop();
        }
    }
}

void WMFVideoPlayer::setupAudioOutput(int channels)
{
    // Clean up existing audio output FIRST to prevent multiple audio streams
    if (m_audioFeedTimer) {
        m_audioFeedTimer->stop();
    }
    
    if (m_audioSink) {
        // Stop the audio device before closing
        if (m_audioDevice) {
            m_audioDevice->close();
            m_audioDevice = nullptr;
        }
        // Stop the sink before deleting
        m_audioSink->stop();
        delete m_audioSink;
        m_audioSink = nullptr;
    }
    
    // Reset audio state
    m_audioBytesWritten = 0;
    m_audioDecoded = false;
    
    // Always use 44100 Hz for audio output (standard sample rate)
    const int outputSampleRate = 44100;
    
    // Set up QAudioSink with 44100 Hz format
    QAudioFormat format;
    format.setSampleRate(outputSampleRate);
    format.setChannelCount(channels);
    format.setSampleFormat(QAudioFormat::Int16);
    
    QAudioDevice device = QMediaDevices::defaultAudioOutput();
    if (!device.isFormatSupported(format)) {
        // If 44100 Hz is not supported, try preferred format but log a warning
        format = device.preferredFormat();
        qDebug() << "[FFmpeg] Warning: 44100 Hz not supported, using preferred format:" << format.sampleRate() << "Hz," << format.channelCount() << "channels";
    }
    
    m_audioSink = new QAudioSink(device, format, this);
    m_audioSink->setVolume(m_volume);
    
    // CRITICAL: Only start the device if we're not already playing
    // If we're already playing, the device should already be started from play()
    if (m_playbackState != 1) {
        m_audioDevice = m_audioSink->start();
        
        if (!m_audioDevice) {
            qDebug() << "[FFmpeg] Failed to start audio sink";
            delete m_audioSink;
            m_audioSink = nullptr;
            return;
        }
        
        // Ensure device is open and ready
        if (!m_audioDevice->isOpen()) {
            qWarning() << "[FFmpeg] Audio device is not open after start()";
        } else {
            qDebug() << "[FFmpeg] Audio device is open and ready for FFmpeg audio";
        }
    } else {
        // Already playing - device should already be started, don't start it again
        qDebug() << "[FFmpeg] Audio sink setup called while playing - device should already be started";
        // Just update volume, don't restart device
    }
    
    m_audioBuffer.clear();
    qDebug() << "[FFmpeg] Audio output setup -" << format.sampleRate() << "Hz," << format.channelCount() << "channels";
}
