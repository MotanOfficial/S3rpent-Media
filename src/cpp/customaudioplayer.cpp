#include "customaudioplayer.h"
#include "audiovisualizer.h"
#include <QDebug>
#include <QFileInfo>
#include <QStandardPaths>
#include <QElapsedTimer>
#include <QThread>
#include <QMutex>
#include <QWaitCondition>
#include <QVariant>
#include <QVariantList>
#include <QMediaDevices>
#include <QSettings>
#include <QMediaMetaData>
#include <QAudioOutput>
#include <cstring>

CustomAudioPlayer::CustomAudioPlayer(QObject *parent)
    : QObject(parent)
    , m_position(0)
    , m_duration(0)
    , m_totalFrames(0)
    , m_seekTargetPosition(0)
    , m_durationCalculated(false)
    , m_bytesWritten(0)
    , m_basePosition(0)
    , m_playbackState(StoppedState)
    , m_seekPreserveState(StoppedState)
    , m_volume(1.0)
    , m_seekable(false)
    , m_loop(false)
    , m_decoder(nullptr)
    , m_audioSink(nullptr)
    , m_audioDevice(nullptr)
    , m_processor(nullptr)
    , m_positionTimer(nullptr)
    , m_errorCheckTimer(nullptr)
    , m_formatInitialized(false)
    , m_processingThread(nullptr)
    , m_processingActive(false)
    , m_writeTimer(nullptr)
    , m_audioVisualizer(nullptr)
    , m_cleaningUp(false)
    , m_metadataPlayer(nullptr)  // CRITICAL: Initialize to nullptr
{
    // Load saved volume from settings
    QSettings settings;
    m_volume = settings.value("audio/volume", 1.0).toReal();
    
    m_positionTimer = new QTimer(this);
    m_positionTimer->setInterval(200); // Update position every 200ms to reduce UI lag
    connect(m_positionTimer, &QTimer::timeout, this, &CustomAudioPlayer::updatePosition);
    
    m_errorCheckTimer = new QTimer(this);
    m_errorCheckTimer->setInterval(100); // Check for errors every 100ms
    m_errorCheckTimer->setSingleShot(false);
    connect(m_errorCheckTimer, &QTimer::timeout, this, [this]() {
        // Check cleanup flag before accessing decoder
        {
            QMutexLocker locker(&m_cleanupMutex);
            if (m_cleaningUp) {
                return;
            }
        }
        if (m_decoder && m_decoder->error() != QAudioDecoder::NoError) {
            onError();
        }
    });
    
    // Timer for non-blocking audio writes (prevents UI lag)
    m_writeTimer = new QTimer(this);
    m_writeTimer->setInterval(5);  // Write chunks every 5ms - faster to keep up with decoding
    m_writeTimer->setSingleShot(false);
    connect(m_writeTimer, &QTimer::timeout, this, &CustomAudioPlayer::writeChunkToDevice);
}

CustomAudioPlayer::~CustomAudioPlayer()
{
    cleanupAudioPipeline();
}

void CustomAudioPlayer::setSource(const QUrl &source)
{
    // CRITICAL: Check if source is actually changing
    if (m_source == source) {
        return;
    }


    // CRITICAL: Set cleanup flag to prevent callbacks from accessing deleted objects
    {
        QMutexLocker locker(&m_cleanupMutex);
        m_cleaningUp = true;
    }

    // CRITICAL: Fully stop and cleanup before changing source
    // This prevents audio device conflicts and dual playback
    if (m_playbackState != StoppedState) {
        stop();
    }
    
    // Stop and disconnect metadata player before cleanup to prevent race conditions
    if (m_metadataPlayer) {
        // CRITICAL: Check if pointer is valid by checking if it's a valid QObject
        // This prevents crashes from accessing invalid memory
        QObject *obj = qobject_cast<QObject*>(m_metadataPlayer);
        if (!obj) {
            m_metadataPlayer = nullptr;
        } else {
            // Save pointer and clear member immediately to prevent re-entry
            QMediaPlayer *metadataPlayer = m_metadataPlayer;
            m_metadataPlayer = nullptr;  // Clear pointer first to prevent re-entry
            
            // Stop first - this is safer than disconnect
            metadataPlayer->stop();
            
            // Disconnect from our side - disconnect all signals from metadataPlayer to this
            QObject::disconnect(metadataPlayer, nullptr, this, nullptr);
            
            delete metadataPlayer;
        }
    }
    
    cleanupAudioPipeline();  // Ensure audio sink is fully released
    
    // Reset duration tracking for new source
    m_duration = 0;
    m_totalFrames = 0;
    m_seekTargetPosition = 0;
    m_durationCalculated = false;  // Allow duration calculation for new source
    m_metaData.clear();  // Clear old metadata - will be loaded for new source
    
    m_source = source;
    
    // Clear cleanup flag before emitting signals
    {
        QMutexLocker locker(&m_cleanupMutex);
        m_cleaningUp = false;
    }
    
    emit sourceChanged();
    emit metaDataChanged();  // Notify that metadata changed

    if (source.isEmpty()) {
        m_seekable = false;
        emit durationChanged();
        emit seekableChanged();
        return;
    }

    // CRITICAL: Reset EQ settings when loading a new song (don't auto-apply)
    if (m_processor) {
        m_processor->resetEQ();
    }

    setupAudioPipeline();
}

void CustomAudioPlayer::setVolume(qreal volume)
{
    volume = qBound(0.0, volume, 1.0);
    if (qAbs(m_volume - volume) < 0.01)
        return;

    m_volume = volume;
    if (m_audioSink) {
        m_audioSink->setVolume(volume);
    }
    
    // Save volume to settings
    QSettings settings;
    settings.setValue("audio/volume", m_volume);
    
    emit volumeChanged();
}

void CustomAudioPlayer::setLoop(bool loop)
{
    if (m_loop == loop)
        return;
    
    m_loop = loop;
    emit loopChanged();
}

void CustomAudioPlayer::setBandGain(int band, qreal gainDb)
{
    if (m_processor) {
        m_processor->setBandGain(band, gainDb);
        
        // CRITICAL: For real-time EQ, re-process raw buffers with new EQ settings
        // Raw buffers are stored and processed on-demand, so EQ changes apply immediately
    }
}

qreal CustomAudioPlayer::getBandGain(int band) const
{
    if (m_processor) {
        return m_processor->getBandGain(band);
    }
    return 0.0;
}

void CustomAudioPlayer::setAllBandGains(const QVariantList &gains)
{
    if (m_processor) {
        m_processor->setAllBandGains(gains);
        
        // CRITICAL: For real-time EQ, re-process raw buffers with new EQ settings
        // Raw buffers are stored and processed on-demand, so EQ changes apply immediately
    }
}

void CustomAudioPlayer::setEQEnabled(bool enabled)
{
    if (m_processor) {
        m_processor->setEnabled(enabled);
        
        // Save EQ enabled state to settings
        QSettings settings;
        settings.setValue("audio/eqEnabled", enabled);
    }
}

bool CustomAudioPlayer::isEQEnabled() const
{
    if (m_processor) {
        return m_processor->isEnabled();
    }
    // Return saved state if processor doesn't exist yet
    QSettings settings;
    return settings.value("audio/eqEnabled", false).toBool();
}

void CustomAudioPlayer::play()
{
    if (m_source.isEmpty())
        return;

    // CRITICAL: Ensure decoder exists - if not, setup pipeline first
    if (!m_decoder) {
        setupAudioPipeline();
        if (!m_decoder) {
            return;
        }
    }

    if (m_playbackState == PausedState && m_audioSink) {
        // Resume from pause
        m_audioSink->resume();
        // Update base position to current position and restart timer
        m_basePosition = m_position;
        m_playbackStartTime.restart();  // Restart elapsed timer from current position
        m_positionTimer->start();
        // No feed timer needed - QAudioSink reads directly from processor
        updatePlaybackState(PlayingState);
        return;
    }

    if (m_playbackState == StoppedState) {
        // Start from beginning (or restart if at end)
        m_position = 0;
        m_basePosition = 0;  // Reset base position
        m_bytesWritten = 0;  // Reset bytes written counter
        m_playbackStartTime.invalidate();  // Reset playback start time
        m_seekTargetPosition = 0;  // Clear any seek target
        emit positionChanged();
        
        // Clear any pending data
        {
            QMutexLocker locker(&m_bufferMutex);
            m_pendingBuffers.clear();
        }
        {
            QMutexLocker locker(&m_writeMutex);
            m_pendingWrites.clear();
        }
        m_partialProcessedData.clear();
        
        // Restart decoder - always stop and restart to ensure clean state
        if (m_decoder) {
            // Stop decoder if it's running
            m_decoder->stop();
            
            // Reset decoder source to restart from beginning
            if (m_source.isLocalFile()) {
                QString filePath = m_source.toLocalFile();
                m_decoder->setSource(filePath);
            }
            
            // Start decoder
            m_decoder->start();
        }
        
        // Restart audio sink if format is already initialized
        if (m_audioSink && m_formatInitialized) {
            if (m_audioDevice) {
                m_audioSink->stop();
                m_audioDevice = nullptr;
            }
            m_audioDevice = m_audioSink->start();
            if (m_audioDevice && m_writeTimer) {
                m_writeTimer->start();
            }
        }
        
        updatePlaybackState(PlayingState);
    }
}

void CustomAudioPlayer::pause()
{
    if (m_playbackState != PlayingState)
        return;

    if (m_audioSink) {
        m_audioSink->suspend();
    }
    m_positionTimer->stop();
           // No feed timer needed - QAudioSink reads directly from processor
    updatePlaybackState(PausedState);
}

void CustomAudioPlayer::stop()
{
    if (m_playbackState == StoppedState)
        return;

    // CRITICAL: Fully stop and cleanup to prevent audio device conflicts
    if (m_decoder) {
        m_decoder->stop();
    }
    if (m_audioSink) {
        m_audioSink->stop();
        m_audioSink->suspend();  // Ensure it's fully stopped
    }
    m_audioDevice = nullptr;  // QAudioSink owns it
    m_positionTimer->stop();
    m_position = 0;
    m_basePosition = 0;  // Reset base position
    m_bytesWritten = 0;  // Reset bytes written counter
    m_playbackStartTime.invalidate();  // Reset playback start time
    m_metaData.clear();  // Clear metadata when stopping
    emit positionChanged();
    emit metaDataChanged();
    updatePlaybackState(StoppedState);
}

void CustomAudioPlayer::seek(qint64 position)
{
    if (!m_seekable || !m_decoder) {
        return;
    }
    
    // Clamp position to valid range
    qint64 targetPosition = qBound(0LL, position, m_duration);
    
    // Update position immediately for UI responsiveness
    m_position = targetPosition;
    m_basePosition = targetPosition;  // Set base position to seek position
    // Reset bytes written - will be recalculated from seek position
    // We'll calculate bytes from position: bytes = (positionMs * sampleRate * channels * bytesPerSample) / 1000
    if (m_audioFormat.sampleRate() > 0 && m_audioFormat.channelCount() > 0 && m_audioFormat.bytesPerSample() > 0) {
        qint64 samples = (targetPosition * m_audioFormat.sampleRate() * m_audioFormat.channelCount()) / 1000;
        m_bytesWritten = samples * m_audioFormat.bytesPerSample();
    } else {
        m_bytesWritten = 0;
    }
    m_playbackStartTime.invalidate();  // Reset playback start time - will restart when audio resumes
    emit positionChanged();
    
    // If decoder is still running, we need to restart it to seek
    // Stop current playback and save state to restore after seeking
    m_seekPreserveState = m_playbackState;  // Save current state (Playing or Paused)
    bool wasPlaying = (m_playbackState == PlayingState);
    
    // Stop decoder
    if (m_decoder) {
        m_decoder->stop();
    }
    
    // Stop audio sink and clear device
    if (m_audioSink) {
        m_audioSink->stop();
        m_audioSink->suspend();
        m_audioDevice = nullptr;  // Clear device so we know to restart it
    }
    
    // Clear all pending buffers
    {
        QMutexLocker locker(&m_bufferMutex);
        m_pendingBuffers.clear();
    }
    {
        QMutexLocker locker(&m_writeMutex);
        m_pendingWrites.clear();
        m_partialProcessedData.clear();
    }
    
    // Set seek target - we'll skip buffers until we reach this position
    m_seekTargetPosition = targetPosition;
    m_totalFrames = 0;  // Reset frame counter for seeking
    
    // Don't reset format initialization - keep using existing format
    // This prevents duration recalculation
    
    // Restart decoder from beginning (QAudioDecoder doesn't support seeking, so we decode from start and skip)
    if (m_decoder && m_source.isLocalFile()) {
        QString filePath = m_source.toLocalFile();
        m_decoder->setSource(filePath);
        m_decoder->start();
    }
    
    // Don't restart audio sink yet - we'll start it once we reach the seek position
    // This prevents audio from playing while we're skipping to the target
}

void CustomAudioPlayer::onBufferReady()
{
    // CRITICAL: Check if we're cleaning up - don't process buffers during cleanup
    {
        QMutexLocker locker(&m_cleanupMutex);
        if (m_cleaningUp) {
            return;
        }
    }
    
    // Check if decoder/processor still exist (might be deleted during cleanup)
    if (!m_decoder || !m_processor) {
        return;
    }

    QAudioBuffer buffer = m_decoder->read();
    if (!buffer.isValid()) {
        return;
    }

    // Initialize format on first buffer
    if (!m_formatInitialized) {
        m_audioFormat = buffer.format();
        
        
        // Normalize format to Int16 for consistent processing
        // Keep sample rate and channels from file, but force Int16 sample format
        m_audioFormat.setSampleFormat(QAudioFormat::Int16);
        
        // Check if format is supported by audio device
        QAudioDevice device = QMediaDevices::defaultAudioOutput();
        if (!device.isFormatSupported(m_audioFormat)) {
            QAudioFormat preferredFormat = device.preferredFormat();
            // Try to keep the sample rate and channels from the file, but use Int16
            preferredFormat.setSampleRate(m_audioFormat.sampleRate());
            preferredFormat.setChannelCount(m_audioFormat.channelCount());
            preferredFormat.setSampleFormat(QAudioFormat::Int16);  // Always use Int16
            
            // Check if this modified format is supported
            if (!device.isFormatSupported(preferredFormat)) {
                // Fall back to device's preferred format but force Int16
                preferredFormat = device.preferredFormat();
                preferredFormat.setSampleFormat(QAudioFormat::Int16);
                if (!device.isFormatSupported(preferredFormat)) {
                    // Last resort: use device preferred as-is
                    preferredFormat = device.preferredFormat();
                }
            }
            m_audioFormat = preferredFormat;
        }
        
        m_processor->initialize(m_audioFormat);
        
        // Create audio sink with the format
        if (m_audioSink) {
            m_audioSink->stop();
            m_audioSink->suspend();
            delete m_audioSink;
            m_audioSink = nullptr;
        }
        
        m_audioSink = new QAudioSink(m_audioFormat, this);
        m_audioSink->setVolume(m_volume);
        
        
        // Start the audio sink - this returns a QIODevice we can write to
        m_audioDevice = m_audioSink->start();
        
        if (!m_audioDevice) {
            return;
        }
        
        m_formatInitialized = true;
        m_seekable = true;
        emit seekableChanged();
        
        // Start position timer now that we have audio
        // Don't start position timer here - it will start when first bytes are written
        // This ensures position tracking starts when audio actually begins playing
        
        // Start processing thread - move processor to thread for processing
        startProcessingThread();
    }

    // Track total frames decoded for accurate duration calculation
    qint64 frameCount = buffer.frameCount();
    if (frameCount > 0) {
        m_totalFrames += frameCount;
        
        // Calculate duration from total frames: duration_ms = (totalFrames * 1000) / sampleRate
        // Note: frameCount() already accounts for all channels, so we don't divide by channelCount
        if (m_audioFormat.sampleRate() > 0) {
            qint64 newDuration = (m_totalFrames * 1000) / m_audioFormat.sampleRate();
            
            // Update duration if it changed significantly (avoid spam - only update every 100ms or more)
            // But only if we haven't already calculated it (preserve duration after first calculation)
            if (!m_durationCalculated && (qAbs(newDuration - m_duration) >= 100 || (m_duration == 0 && newDuration > 0))) {
                m_duration = newDuration;
                emit durationChanged();
                // Removed logging to reduce verbosity
            }
            
            // Check if we're seeking and need to skip buffers
            if (m_seekTargetPosition > 0) {
                qint64 currentPosition = (m_totalFrames * 1000) / m_audioFormat.sampleRate();
                if (currentPosition < m_seekTargetPosition) {
                    // We haven't reached the seek position yet - skip this buffer (don't add to queue)
                    return;
                } else {
                    // We've reached the seek position - start playback
                    m_seekTargetPosition = 0;  // Clear seek target
                    m_position = currentPosition;
                    m_basePosition = currentPosition;  // Set base position to seek position
                    // Reset bytes written to match seek position
                    if (m_audioFormat.sampleRate() > 0 && m_audioFormat.channelCount() > 0 && m_audioFormat.bytesPerSample() > 0) {
                        qint64 samples = (currentPosition * m_audioFormat.sampleRate() * m_audioFormat.channelCount()) / 1000;
                        m_bytesWritten = samples * m_audioFormat.bytesPerSample();
                    } else {
                        m_bytesWritten = 0;
                    }
                    m_playbackStartTime.invalidate();  // Reset playback start time - will restart when audio resumes
                    
                    // CRITICAL: Restart audio sink and device for playback
                    if (m_audioSink) {
                        // Stop and restart to ensure clean state
                        if (m_audioDevice) {
                            m_audioSink->stop();
                            m_audioDevice = nullptr;
                        }
                        m_audioDevice = m_audioSink->start();
                        
                        if (m_audioDevice && m_audioDevice->isOpen()) {
                            // Start position timer
                            if (m_positionTimer) {
                                m_positionTimer->start();
                            }
                            // Start write timer to begin feeding audio
                            if (m_writeTimer && !m_writeTimer->isActive()) {
                                m_writeTimer->start();
                            }
                            // Restore playback state (only play if it was playing before seeking)
                            if (m_seekPreserveState == PlayingState) {
                            if (m_playbackState != PlayingState) {
                                updatePlaybackState(PlayingState);
                            }
                            } else {
                                // Was paused - keep it paused (don't start audio sink)
                                if (m_audioSink) {
                                    m_audioSink->suspend();
                                }
                                if (m_playbackState != PausedState) {
                                    updatePlaybackState(PausedState);
                                }
                                // Don't start write timer or position timer if paused
                                if (m_writeTimer && m_writeTimer->isActive()) {
                                    m_writeTimer->stop();
                                }
                                if (m_positionTimer && m_positionTimer->isActive()) {
                                    m_positionTimer->stop();
                                }
                            }
                        }
                    }
                    
                    emit positionChanged();
                }
            }
        }
    }

    // CRITICAL: Process buffer in background thread to prevent UI lag
    // Add buffer to queue for processing thread (only if not seeking or we've reached seek position)
    {
        QMutexLocker locker(&m_bufferMutex);
        m_pendingBuffers.append(buffer);
        m_bufferReady.wakeOne();
    }
}

void CustomAudioPlayer::onFinished()
{
    // CRITICAL: Check if we're cleaning up - don't process during cleanup
    {
        QMutexLocker locker(&m_cleanupMutex);
        if (m_cleaningUp) {
            return;
        }
    }
    
    
    // Final duration update when decoder finishes (only if not already calculated)
    // Note: frameCount() already accounts for all channels, so we don't divide by channelCount
    if (!m_durationCalculated && m_audioFormat.sampleRate() > 0 && m_totalFrames > 0) {
        qint64 finalDuration = (m_totalFrames * 1000) / m_audioFormat.sampleRate();
        if (finalDuration > 0) {
            m_duration = finalDuration;
            m_durationCalculated = true;  // Mark as calculated - preserve it from now on
            emit durationChanged();
        }
    }
    
    // Don't stop immediately - check if there are pending buffers or writes
    // The decoder finishing just means it's done decoding, not that playback is done
    
    // Check if there are still buffers being processed
    {
        QMutexLocker locker(&m_bufferMutex);
        if (!m_pendingBuffers.isEmpty()) {
            return;  // Still processing
        }
    }
    
    // Check if there are still writes pending
    {
        QMutexLocker locker(&m_writeMutex);
        if (!m_pendingWrites.isEmpty()) {
            return;  // Still writing
        }
    }
}

void CustomAudioPlayer::onError()
{
    // CRITICAL: Check if we're cleaning up - don't process during cleanup
    {
        QMutexLocker locker(&m_cleanupMutex);
        if (m_cleaningUp) {
            return;
        }
    }
    
    QString errorString = m_decoder ? m_decoder->errorString() : "Unknown error";
    int errorCode = m_decoder ? static_cast<int>(m_decoder->error()) : 0;
    emit errorOccurred(errorCode, errorString);
}

void CustomAudioPlayer::onMetaDataChanged()
{
    // CRITICAL: Check if we're cleaning up - don't process during cleanup
    {
        QMutexLocker locker(&m_cleanupMutex);
        if (m_cleaningUp) {
            return;
        }
    }
    
    if (!m_metadataPlayer) {
        return;
    }
    
    // CRITICAL: Check if source has changed since metadata extraction started
    // This prevents race conditions where metadata from old file overwrites new file
    QUrl currentSource = m_metadataPlayer->source();
    if (currentSource != m_source) {
        return;
    }
    
    // Extract metadata from QMediaPlayer
    QMediaMetaData metaData = m_metadataPlayer->metaData();
    m_metaData.clear();
    
    // Extract common metadata fields
    QString title = metaData.value(QMediaMetaData::Title).toString();
    if (!title.isEmpty()) {
        m_metaData["Title"] = title;
    }
    
    QString artist = metaData.value(QMediaMetaData::ContributingArtist).toString();
    if (artist.isEmpty()) {
        artist = metaData.value(QMediaMetaData::AlbumArtist).toString();
    }
    if (!artist.isEmpty()) {
        m_metaData["ContributingArtist"] = artist;
        m_metaData["Artist"] = artist;
    }
    
    QString album = metaData.value(QMediaMetaData::AlbumTitle).toString();
    if (!album.isEmpty()) {
        m_metaData["AlbumTitle"] = album;
        m_metaData["Album"] = album;
    }
    
    // Get bitrate from metadata (if available)
    QVariant bitrateVariant = metaData.value(QMediaMetaData::AudioBitRate);
    if (bitrateVariant.isValid()) {
        int bitrate = bitrateVariant.toInt();
        if (bitrate > 0) {
            m_metaData["AudioBitRate"] = bitrate;
        }
    }
    
    // Sample rate and channel count are already available from m_audioFormat
    // We'll add them to metadata map for consistency
    if (m_audioFormat.sampleRate() > 0) {
        m_metaData["SampleRate"] = m_audioFormat.sampleRate();
    }
    if (m_audioFormat.channelCount() > 0) {
        m_metaData["ChannelCount"] = m_audioFormat.channelCount();
    }
    
    QString codec = metaData.value(QMediaMetaData::AudioCodec).toString();
    if (!codec.isEmpty()) {
        m_metaData["AudioCodec"] = codec;
    }
    
    emit metaDataChanged();
}

void CustomAudioPlayer::setAudioVisualizer(QObject* visualizer)
{
    m_audioVisualizer = visualizer;
}

void CustomAudioPlayer::updatePosition()
{
    // Update position based on elapsed time since playback actually started
    // This is more accurate than bytes-written tracking which can drift due to buffering
    if (m_playbackState == PlayingState && m_playbackStartTime.isValid()) {
        // Calculate position from elapsed time since playback started
        qint64 elapsedMs = m_playbackStartTime.elapsed();
        qint64 newPosition = m_basePosition + elapsedMs;
        
        if (m_duration > 0 && newPosition >= m_duration) {
            newPosition = m_duration;
            
            // Check if playback has finished (all data written and audio device buffer is empty)
            bool allDataWritten = false;
            bool audioBufferEmpty = false;
            
            // Check if all pending writes are done
            {
                QMutexLocker locker(&m_writeMutex);
                allDataWritten = m_pendingWrites.isEmpty() && m_partialProcessedData.isEmpty();
            }
            
            // Check if audio device buffer is empty (all data has been played)
            if (m_audioSink && allDataWritten) {
                qint64 bytesFree = m_audioSink->bytesFree();
                qint64 bufferSize = m_audioSink->bufferSize();
                // Buffer is empty when bytesFree equals or exceeds bufferSize
                audioBufferEmpty = (bytesFree >= bufferSize || bufferSize == 0);
            }
            
            // If we've reached the end and all data is played, stop or loop
            if (allDataWritten && (audioBufferEmpty || !m_audioSink)) {
                // Playback finished
                if (m_loop) {
                    // Loop: restart from beginning
                    m_position = 0;
                    m_basePosition = 0;
                    m_bytesWritten = 0;
                    m_playbackStartTime.invalidate();
                    m_seekTargetPosition = 0;
                    emit positionChanged();
                    
                    // Clear pending data
                    {
                        QMutexLocker locker(&m_bufferMutex);
                        m_pendingBuffers.clear();
                    }
                    {
                        QMutexLocker locker(&m_writeMutex);
                        m_pendingWrites.clear();
                    }
                    m_partialProcessedData.clear();
                    
                    // Restart decoder
                    if (m_decoder) {
                        m_decoder->stop();
                        if (m_source.isLocalFile()) {
                            QString filePath = m_source.toLocalFile();
                            m_decoder->setSource(filePath);
                        }
                        m_decoder->start();
                    }
                    
                    // Restart audio sink
                    if (m_audioSink && m_formatInitialized) {
                        if (m_audioDevice) {
                            m_audioSink->stop();
                            m_audioDevice = nullptr;
                        }
                        m_audioDevice = m_audioSink->start();
                        if (m_audioDevice && m_writeTimer) {
                            m_writeTimer->start();
                        }
                    }
                } else {
                    // No loop: stop playback
                    m_position = m_duration;
                    emit positionChanged();
                    
                    // Stop playback
                    if (m_audioSink) {
                        m_audioSink->stop();
                    }
                    if (m_positionTimer) {
                        m_positionTimer->stop();
                    }
                    if (m_writeTimer) {
                        m_writeTimer->stop();
                    }
                    m_playbackStartTime.invalidate();
                    updatePlaybackState(StoppedState);
                }
                return;
            }
        }
        
        if (newPosition != m_position) {
            m_position = newPosition;
            emit positionChanged();
        }
    } else if (m_playbackState == PlayingState && m_audioFormat.sampleRate() > 0 && m_bytesWritten > 0) {
        // Fallback: Calculate position from bytes written if start time not available
        int sampleRate = m_audioFormat.sampleRate();
        int channels = m_audioFormat.channelCount();
        int bytesPerSample = m_audioFormat.bytesPerSample();
        
        if (sampleRate > 0 && channels > 0 && bytesPerSample > 0) {
            qint64 totalSamples = m_bytesWritten / bytesPerSample;
            qint64 positionMs = (totalSamples * 1000) / (sampleRate * channels);
            
            if (m_duration > 0 && positionMs >= m_duration) {
                positionMs = m_duration;
                
                // Check if playback has finished
                bool allDataWritten = false;
                {
                    QMutexLocker locker(&m_writeMutex);
                    allDataWritten = m_pendingWrites.isEmpty() && m_partialProcessedData.isEmpty();
                }
                
                if (allDataWritten) {
                    if (m_loop) {
                        // Loop: restart from beginning
                        m_position = 0;
                        m_basePosition = 0;
                        m_bytesWritten = 0;
                        m_playbackStartTime.invalidate();
                        m_seekTargetPosition = 0;
                        emit positionChanged();
                        
                        // Clear pending data
                        {
                            QMutexLocker locker(&m_bufferMutex);
                            m_pendingBuffers.clear();
                        }
                        {
                            QMutexLocker locker(&m_writeMutex);
                            m_pendingWrites.clear();
                        }
                        m_partialProcessedData.clear();
                        
                        // Restart decoder
                        if (m_decoder) {
                            m_decoder->stop();
                            if (m_source.isLocalFile()) {
                                QString filePath = m_source.toLocalFile();
                                m_decoder->setSource(filePath);
                            }
                            m_decoder->start();
                        }
                        
                        // Restart audio sink
                        if (m_audioSink && m_formatInitialized) {
                            if (m_audioDevice) {
                                m_audioSink->stop();
                                m_audioDevice = nullptr;
                            }
                            m_audioDevice = m_audioSink->start();
                            if (m_audioDevice && m_writeTimer) {
                                m_writeTimer->start();
                            }
                        }
                    } else {
                        // No loop: stop playback
                        m_position = m_duration;
                        emit positionChanged();
                        
                        // Stop playback
                        if (m_audioSink) {
                            m_audioSink->stop();
                        }
                        if (m_positionTimer) {
                            m_positionTimer->stop();
                        }
                        if (m_writeTimer) {
                            m_writeTimer->stop();
                        }
                        m_playbackStartTime.invalidate();
                        updatePlaybackState(StoppedState);
                    }
                    return;
                }
            }
            
            if (positionMs != m_position) {
                m_position = positionMs;
                emit positionChanged();
            }
        }
    }
}

void CustomAudioPlayer::setupAudioPipeline()
{
    // CRITICAL: Prevent duplicate setup - if decoder already exists, cleanup first
    if (m_decoder) {
        cleanupAudioPipeline();
    }

    if (m_source.isEmpty())
        return;

    QString filePath;
    if (m_source.isLocalFile()) {
        filePath = m_source.toLocalFile();
    } else {
        return;
    }

    if (!QFileInfo::exists(filePath)) {
        return;
    }

    // Create metadata player for extracting metadata (title, artist, etc.)
    if (!m_metadataPlayer) {
        m_metadataPlayer = new QMediaPlayer(this);
        QAudioOutput *audioOutput = new QAudioOutput(this);
        audioOutput->setVolume(0);  // Mute it - we only want metadata
        m_metadataPlayer->setAudioOutput(audioOutput);
    }
    
    // Reconnect signal (in case it was disconnected during cleanup)
    connect(m_metadataPlayer, &QMediaPlayer::metaDataChanged, this, &CustomAudioPlayer::onMetaDataChanged, Qt::UniqueConnection);
    
    // Stop any previous metadata extraction before loading new source
    m_metadataPlayer->stop();
    
    // Load metadata from file
    m_metadataPlayer->setSource(QUrl::fromLocalFile(filePath));
    // Metadata will be extracted asynchronously
    
    // Create decoder - always create new one to avoid race conditions
    // (cleanupAudioPipeline() deletes the old one, so this should always be null here)
    if (m_decoder) {
        cleanupAudioPipeline();
    }
    
    m_decoder = new QAudioDecoder(this);
    m_decoder->setSource(filePath);

    connect(m_decoder, &QAudioDecoder::bufferReady, this, &CustomAudioPlayer::onBufferReady);
    connect(m_decoder, &QAudioDecoder::finished, this, &CustomAudioPlayer::onFinished);
    
    // Start error check timer (QAudioDecoder doesn't have errorOccurred signal in Qt 6)
    m_errorCheckTimer->start();

    // Create processor - only if it doesn't exist
    // CRITICAL: Preserve processor across source changes to maintain EQ settings
    if (!m_processor) {
        m_processor = new CustomAudioProcessor(this);
        
        // Restore EQ enabled state from settings
        QSettings settings;
        bool eqEnabled = settings.value("audio/eqEnabled", false).toBool();
        m_processor->setEnabled(eqEnabled);
    } else {
        // Restore EQ enabled state from settings
        QSettings settings;
        bool eqEnabled = settings.value("audio/eqEnabled", false).toBool();
        m_processor->setEnabled(eqEnabled);
    }

    m_formatInitialized = false;
}

void CustomAudioPlayer::cleanupAudioPipeline()
{
    // CRITICAL: Set cleanup flag to prevent callbacks
    {
        QMutexLocker locker(&m_cleanupMutex);
        m_cleaningUp = true;
    }
    
    // Stop processing thread first - must be done before deleting objects it might access
    stopProcessingThread();
    
    // Stop error check timer to prevent it from accessing deleted decoder
    if (m_errorCheckTimer) {
        m_errorCheckTimer->stop();
    }
    
    // CRITICAL: Disconnect all signals first to prevent callbacks during cleanup
    if (m_decoder) {
        m_decoder->disconnect(this);  // Disconnect all signals
        m_decoder->stop();
        delete m_decoder;
        m_decoder = nullptr;
    }

    if (m_positionTimer) {
        m_positionTimer->stop();
    }

    if (m_audioDevice) {
        m_audioDevice = nullptr;  // QAudioSink owns it, don't delete
    }

    if (m_audioSink) {
        // CRITICAL: Stop and suspend before deleting to release audio device
        // This prevents "AUDCLNT_E_NOT_STOPPED" errors
        m_audioSink->stop();
        m_audioSink->suspend();  // Ensure it's fully stopped
        delete m_audioSink;
        m_audioSink = nullptr;
    }

    // CRITICAL: Don't delete the processor - preserve EQ settings across source changes
    // Just reset its filter state, but keep the band gains
    // The processor will be re-initialized with new format when next buffer arrives
    // This preserves EQ settings when switching songs

    m_formatInitialized = false;
    
    // Stop write timer
    if (m_writeTimer) {
        m_writeTimer->stop();
    }
    
    // Clear pending buffers
    {
        QMutexLocker locker(&m_bufferMutex);
        m_pendingBuffers.clear();
    }
    
    // Clear pending writes and partial data
    {
        QMutexLocker locker(&m_writeMutex);
        m_pendingWrites.clear();
    }
    m_partialProcessedData.clear();
    
    // Clear cleanup flag
    {
        QMutexLocker locker(&m_cleanupMutex);
        m_cleaningUp = false;
    }
}

void CustomAudioPlayer::updatePlaybackState(PlaybackState state)
{
    if (m_playbackState != state) {
        m_playbackState = state;
        emit playbackStateChanged();
    }
}

void CustomAudioPlayer::startProcessingThread()
{
    if (m_processingThread || !m_formatInitialized || !m_processor) {
        return;
    }
    
    m_processingActive = true;
    m_processingThread = new QThread(this);
    
    // Create a worker object that will live in the worker thread
    QObject *worker = new QObject();
    worker->moveToThread(m_processingThread);
    
    // Use QTimer::singleShot to run processing in the worker thread's event loop
    connect(m_processingThread, &QThread::started, worker, [this, worker]() {
        // This lambda runs in the worker thread context (worker is in the worker thread)
        QTimer::singleShot(0, worker, [this, worker]() {
            processBuffersInThread();
        });
    });
    connect(m_processingThread, &QThread::finished, worker, &QObject::deleteLater);
    connect(m_processingThread, &QThread::finished, m_processingThread, &QThread::deleteLater);
    
    m_processingThread->start();
}

void CustomAudioPlayer::stopProcessingThread()
{
    if (!m_processingThread) {
        return;
    }
    
    m_processingActive = false;
    m_bufferReady.wakeAll();  // Wake thread so it can exit
    
    m_processingThread->quit();
    if (!m_processingThread->wait(2000)) {  // Wait up to 2 seconds for thread to finish
        m_processingThread->terminate();
        m_processingThread->wait(1000);  // Wait for termination
    }
    
    m_processingThread = nullptr;
}

void CustomAudioPlayer::processBuffersInThread()
{
    // This runs in the processing thread
    while (m_processingActive) {
        QAudioBuffer buffer;
        
        // Get next buffer from queue
        {
            QMutexLocker locker(&m_bufferMutex);
            while (m_pendingBuffers.isEmpty() && m_processingActive) {
                m_bufferReady.wait(&m_bufferMutex, 100);  // Wait up to 100ms
            }
            
            if (!m_pendingBuffers.isEmpty()) {
                buffer = m_pendingBuffers.takeFirst();
            }
        }
        
        if (!buffer.isValid()) {
            continue;
        }
        
        // For real-time EQ: Send raw buffer to main thread for processing with current EQ settings
        // This ensures EQ changes apply immediately to the next buffers
        QMetaObject::invokeMethod(this, "processAndQueueBuffer", Qt::QueuedConnection, 
                                  Q_ARG(QAudioBuffer, buffer));
    }
}

void CustomAudioPlayer::processAndQueueBuffer(const QAudioBuffer &rawBuffer)
{
    // CRITICAL: Check if we're cleaning up - don't process during cleanup
    {
        QMutexLocker locker(&m_cleanupMutex);
        if (m_cleaningUp) {
            return;
        }
    }
    
    if (!rawBuffer.isValid()) {
        return;
    }
    
    // CRITICAL: Store RAW buffers for real-time EQ processing
    // Buffers will be processed right before writing with CURRENT EQ settings
    // This ensures EQ changes apply immediately to the next buffers to be written
    if (!m_audioDevice || !m_audioDevice->isOpen()) {
        return;
    }
    
    // Add raw buffer to write queue - will be processed on-demand
    {
        QMutexLocker locker(&m_writeMutex);
        m_pendingWrites.append(rawBuffer);
    }
    
    // Start write timer if not already running (writes chunks periodically without blocking)
    if (m_writeTimer && !m_writeTimer->isActive()) {
        m_writeTimer->start();
    }
}

void CustomAudioPlayer::writeChunkToDevice()
{
    // CRITICAL: Check if we're cleaning up - don't write during cleanup
    {
        QMutexLocker locker(&m_cleanupMutex);
        if (m_cleaningUp) {
            if (m_writeTimer) {
                m_writeTimer->stop();
            }
            return;
        }
    }
    
    // This runs on the main thread via timer - write small chunks at proper rate
    if (!m_audioDevice || !m_audioDevice->isOpen() || !m_processor || !m_audioSink) {
        if (m_writeTimer) {
            m_writeTimer->stop();
        }
        return;
    }
    
    // Check how much space is available in the audio device buffer
    qint64 bytesFree = m_audioSink->bytesFree();
    if (bytesFree <= 0) {
        // Buffer is full - wait for next tick
        return;
    }
    
    // Write small chunks to match audio consumption rate (not entire buffers at once)
    const qint64 MAX_CHUNK_SIZE = 8192;  // 8KB chunks - matches audio consumption rate
    qint64 bytesToWrite = qMin(bytesFree, MAX_CHUNK_SIZE);
    
    // First, write any partial processed data from previous write
    if (!m_partialProcessedData.isEmpty()) {
        qint64 partialSize = qMin(static_cast<qint64>(m_partialProcessedData.size()), bytesToWrite);
        qint64 written = m_audioDevice->write(m_partialProcessedData.constData(), partialSize);
        if (written > 0) {
            m_bytesWritten += written;
            // Start position timer on first write if not already started
            if (!m_playbackStartTime.isValid()) {
                m_basePosition = m_position;  // Set base position to current position
                m_playbackStartTime.start();
                if (m_positionTimer && !m_positionTimer->isActive()) {
                    m_positionTimer->start();
                }
            }
            
            // Feed audio samples to visualizer if available (avoids WASAPI loopback capturing all system audio)
            if (m_audioVisualizer && m_audioFormat.isValid()) {
                QByteArray sampleData = m_partialProcessedData.left(written);
                // Use direct call instead of QMetaObject::invokeMethod to avoid QAudioFormat metatype issues
                AudioVisualizer *visualizer = qobject_cast<AudioVisualizer*>(m_audioVisualizer);
                if (visualizer) {
                    visualizer->feedAudioSamples(sampleData, m_audioFormat);
                }
            }
        }
        
        if (written < 0) {
            m_partialProcessedData.clear();
            return;
        }
        
        if (written > 0) {
            m_bytesWritten += written;  // Track bytes written for accurate position
            // Start position timer on first write if not already started
            if (!m_playbackStartTime.isValid()) {
                m_basePosition = m_position;  // Set base position to current position
                m_playbackStartTime.start();
                if (m_positionTimer && !m_positionTimer->isActive()) {
                    m_positionTimer->start();
                }
            }
            // Remove written bytes from partial buffer
            m_partialProcessedData.remove(0, written);
            bytesToWrite -= written;
        }
        
        // If we still have partial data, wait for next tick
        if (!m_partialProcessedData.isEmpty()) {
            return;
        }
    }
    
    // Now process and write new buffers
    while (bytesToWrite > 0) {
        QAudioBuffer rawBuffer;
        
        // Get next raw buffer from queue
        {
            QMutexLocker locker(&m_writeMutex);
            if (m_pendingWrites.isEmpty()) {
                // No more data - stop timer
                if (m_writeTimer) {
                    m_writeTimer->stop();
                }
                
                // Check if playback has finished (all data written and audio device buffer is empty)
                if (m_playbackState == PlayingState && m_duration > 0 && m_position >= m_duration) {
                    // Check if audio device buffer is empty
                    if (m_audioSink) {
                        qint64 bytesFree = m_audioSink->bytesFree();
                        qint64 bufferSize = m_audioSink->bufferSize();
                        bool audioBufferEmpty = (bytesFree >= bufferSize || bufferSize == 0);
                        
                        if (audioBufferEmpty && m_partialProcessedData.isEmpty()) {
                            // All data written and buffer is empty - playback finished
                            // Position update will handle stopping, but we can check here too
                            locker.unlock();  // Release lock before calling updatePosition
                            updatePosition();  // This will detect end and stop playback
                            return;
                        }
                    }
                }
                
                return;
            }
            rawBuffer = m_pendingWrites.takeFirst();
        }
        
        if (!rawBuffer.isValid()) {
            continue;
        }
        
        // CRITICAL: Process buffer with CURRENT EQ settings RIGHT BEFORE writing
        // This ensures EQ changes apply immediately to the next buffers to be written
        QByteArray processedData = m_processor->processBuffer(rawBuffer);
        
        if (processedData.isEmpty()) {
            continue;
        }
        
        // Write as much as we can
        qint64 chunkSize = qMin(static_cast<qint64>(processedData.size()), bytesToWrite);
        qint64 written = m_audioDevice->write(processedData.constData(), chunkSize);
        
        if (written < 0) {
            // Error writing - put buffer back
            QMutexLocker locker(&m_writeMutex);
            m_pendingWrites.prepend(rawBuffer);
            return;
        }
        
        if (written > 0) {
            m_bytesWritten += written;  // Track bytes written for reference
            // Start position timer on first write if not already started
            if (!m_playbackStartTime.isValid()) {
                m_basePosition = m_position;  // Set base position to current position
                m_playbackStartTime.start();
                if (m_positionTimer && !m_positionTimer->isActive()) {
                    m_positionTimer->start();
                }
            }
            
            // Feed audio samples to visualizer if available (avoids WASAPI loopback capturing all system audio)
            if (m_audioVisualizer && m_audioFormat.isValid()) {
                QByteArray sampleData = processedData.left(written);
                // Use direct call instead of QMetaObject::invokeMethod to avoid QAudioFormat metatype issues
                AudioVisualizer *visualizer = qobject_cast<AudioVisualizer*>(m_audioVisualizer);
                if (visualizer) {
                    visualizer->feedAudioSamples(sampleData, m_audioFormat);
                }
            }
        }
        
        if (written < processedData.size()) {
            // Couldn't write all - store remainder for next tick
            m_partialProcessedData = processedData.mid(written);
            return;
        }
        
        bytesToWrite -= written;
    }
}

