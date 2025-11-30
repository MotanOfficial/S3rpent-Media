#include "wmfvideoplayer.h"
#include "wmfvideoplayer_helpers.h"
#include <QDebug>
#include <cmath>
#include <QTimer>

void WMFVideoPlayer::playbackWorker()
{
    // Check if playback has ended (handled by QMediaPlayer signals now)
    if (m_playbackState != 1) {
        return;
    }
    
    // Check if we've reached the correct duration (from audio)
    if (m_duration > 0 && m_position >= m_duration) {
        qDebug() << "[MediaPlayer] Reached correct duration:" << m_duration << "ms, stopping playback";
        stop();
        return;
    }
}

void WMFVideoPlayer::processVideoFrames()
{
    // Video frames are handled by QMediaPlayer - this function is no longer needed
}

void WMFVideoPlayer::play()
{
    qDebug() << "[MediaPlayer] play() called - current state:" << m_playbackState << ", needsSpecialHandling:" << m_needsSpecialHandling;
    
    if (m_playbackState == 1) { // Already playing
        return;
    }
    
    // If detection is still running, wait a bit (but don't block forever)
    // This is a simple check - in practice detection should complete quickly
    if (m_containerDuration > 0 && m_duration == 0) {
        qDebug() << "[MediaPlayer] Detection may still be running, waiting briefly...";
        QThread::msleep(100); // Brief wait
    }
    
    // Start Qt MediaPlayer video
    if (m_mediaPlayer) {
        m_mediaPlayer->play();
    }
    
    // Start FFmpeg audio (only if special handling is needed)
    qDebug() << "[MediaPlayer] Checking FFmpeg audio - needsSpecialHandling:" << m_needsSpecialHandling << ", audioDecoded:" << m_audioDecoded << ", audioSink:" << (m_audioSink != nullptr);
    if (m_needsSpecialHandling && m_audioDecoded && m_audioSink) {
        qDebug() << "[MediaPlayer] Starting FFmpeg audio playback";
        // Only reset audio position if starting fresh (not resuming from pause)
        if (m_playbackState == 0) {
            m_audioBytesWritten = 0;
        }
        
        // CRITICAL: QAudioSink::start() can only be called once per sink instance
        // If the device is already started, we must NOT call start() again
        // Instead, we just resume the sink if it's suspended
        
        // Check if device exists and is open
        if (!m_audioDevice || !m_audioDevice->isOpen()) {
            // Device doesn't exist or isn't open - start it (only if not already started)
            if (!m_audioDevice) {
                // Device was never started - start it now
                m_audioDevice = m_audioSink->start();
                if (!m_audioDevice) {
                    qWarning() << "[FFmpeg Audio] Failed to start audio device on play()";
                    return; // Can't play without audio device
                }
            } else {
                // Device exists but isn't open - this shouldn't happen normally
                // But if it does, we need to stop and restart the sink properly
                qWarning() << "[FFmpeg Audio] Device exists but isn't open - stopping and restarting sink";
                m_audioSink->stop();
                m_audioDevice->close();
                m_audioDevice = nullptr;
                // Wait briefly for device to be released
                QThread::msleep(50);
                m_audioDevice = m_audioSink->start();
                if (!m_audioDevice || !m_audioDevice->isOpen()) {
                    qWarning() << "[FFmpeg Audio] Failed to restart audio device on play()";
                    return;
                }
            }
        } else {
            // Device is already open and running - just resume if needed
            // DO NOT call start() again - this causes "AUDCLNT_E_NOT_STOPPED" errors
            qDebug() << "[FFmpeg Audio] Audio device already open and running";
        }
        
        // Ensure sink is active (resume if paused, or if it was just set up)
        // QAudioSink::resume() is safe to call even if already active
        m_audioSink->resume();
        
        if (m_audioFeedTimer) {
            m_audioFeedTimer->start();
            feedAudioToSink(); // Feed initial chunk
        }
    } else {
        if (m_needsSpecialHandling) {
            if (!m_audioDecoded) {
                qWarning() << "[FFmpeg Audio] Special handling needed but audio not decoded!";
            }
            if (!m_audioSink) {
                qWarning() << "[FFmpeg Audio] Special handling needed but audio sink is null!";
            }
        } else {
            qDebug() << "[MediaPlayer] Using QMediaPlayer audio (normal video)";
        }
    }
    
    if (m_positionTimer) {
        m_positionTimer->start();
    }
    
    m_playbackState = 1; // Playing
    emit playbackStateChanged();
}

void WMFVideoPlayer::pause()
{
    qDebug() << "[MediaPlayer] pause() called";
    
    if (m_playbackState != 1) {
        return;
    }
    
    // Pause Qt MediaPlayer video
    if (m_mediaPlayer) {
        m_mediaPlayer->pause();
    }
    
    // Pause FFmpeg audio
    if (m_audioSink) {
        m_audioSink->suspend();
    }
    
    if (m_audioFeedTimer) {
        m_audioFeedTimer->stop();
    }
    
    if (m_positionTimer) {
        m_positionTimer->stop();
    }
    
    m_playbackState = 2; // Paused
    emit playbackStateChanged();
}

void WMFVideoPlayer::stop()
{
    qDebug() << "[MediaPlayer] stop() called";
    
    // Stop Qt MediaPlayer video
    if (m_mediaPlayer) {
        m_mediaPlayer->stop();
        // Reset playback rate to normal
        m_mediaPlayer->setPlaybackRate(1.0);
    }
    
    // Stop FFmpeg audio - properly stop and close the device
    if (m_audioSink) {
        // Stop the sink first
        m_audioSink->stop();
        m_audioSink->suspend();
        
        // Close and reset the audio device to allow restart
        if (m_audioDevice) {
            m_audioDevice->close();
            m_audioDevice = nullptr;
            qDebug() << "[FFmpeg Audio] Audio device closed and reset in stop()";
        }
    }
    
    if (m_audioFeedTimer) {
        m_audioFeedTimer->stop();
    }
    
    if (m_positionTimer) {
        m_positionTimer->stop();
    }
    
    m_playbackState = 0; // Stopped
    m_position = 0;
    m_audioBytesWritten = 0; // Reset audio position
    
    emit playbackStateChanged();
    emit positionChanged();
}

void WMFVideoPlayer::seek(int position)
{
    if (!m_seekable)
        return;

    // CRITICAL: Clamp position to correct duration (from audio)
    // This prevents seeking past the actual content duration
    if (m_duration > 0 && position > m_duration) {
        qDebug() << "[MediaPlayer] Clamping seek position from" << position << "ms to correct duration:" << m_duration << "ms";
        position = m_duration;
    }

    // Audio seeks to position (1x)
    // Video seeks using full ratio (container/audio duration)
    int videoPosition = position;
    
    if (m_needsSpecialHandling && m_containerDuration > 0 && m_duration > 0) {
        // Use percentage-based: same % of audio = same % of container
        double percent = (double)position / m_duration;
        videoPosition = (int)(percent * m_containerDuration);
        qDebug() << "[MediaPlayer] Seeking: audio" << position << "ms (" << (percent*100) << "%), video" << videoPosition << "ms";
    } else {
        qDebug() << "[MediaPlayer] Seeking to:" << position << "ms";
    }
    
    // Update audio position (1x)
    if (m_audioSink && !m_decodedAudioData.isEmpty()) {
        QAudioFormat format = m_audioSink->format();
        int sampleRate = format.sampleRate();
        int channels = format.channelCount();
        int bytesPerSample = format.bytesPerSample();
        
        if (sampleRate > 0 && channels > 0 && bytesPerSample > 0) {
            qint64 positionSeconds = position / 1000.0;
            qint64 samples = positionSeconds * sampleRate * channels;
            m_audioBytesWritten = samples * bytesPerSample;
            
            // Clamp to valid range
            if (m_audioBytesWritten < 0) {
                m_audioBytesWritten = 0;
            } else if (m_audioBytesWritten > m_decodedAudioData.size()) {
                m_audioBytesWritten = m_decodedAudioData.size();
            }
        }
    }
    
    // Seek video (with playback rate multiplier for special handling)
    if (m_mediaPlayer) {
        m_mediaPlayer->setPosition(videoPosition);
    }
    
    m_position = position;
    emit positionChanged();
}
