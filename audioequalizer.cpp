#include "audioequalizer.h"
#include "customaudioplayer.h"
#include <QtMath>
#include <QDebug>

AudioEqualizer::AudioEqualizer(QObject *parent)
    : QObject(parent)
    , m_enabled(false)
    , m_customAudioPlayer(nullptr)
{
    // Initialize 10-band EQ with 0 dB gain
    m_bandGains.resize(10, 0.0);
    
    // Initialize QVariantList for QML
    m_eqBands.clear();
    for (int i = 0; i < 10; ++i) {
        m_eqBands.append(QVariant(0.0));
    }
}

AudioEqualizer::~AudioEqualizer()
{
}

void AudioEqualizer::setEnabled(bool enabled)
{
    if (m_enabled != enabled) {
        m_enabled = enabled;
        
        // Sync to CustomAudioPlayer if available
        if (m_customAudioPlayer) {
            m_customAudioPlayer->setEQEnabled(enabled);
        }
        
        emit enabledChanged();
    }
}

void AudioEqualizer::setBandGain(int band, qreal gainDb)
{
    if (band < 0 || band >= 10) {
        qWarning() << "[AudioEqualizer] Invalid band index:" << band;
        return;
    }
    
    // Clamp gain to -12 to +12 dB
    gainDb = qBound(-12.0, gainDb, 12.0);
    
    if (qAbs(m_bandGains[band] - gainDb) > 0.01) {  // Only update if changed significantly
        m_bandGains[band] = gainDb;
        m_eqBands[band] = QVariant(gainDb);
        
        // Sync to CustomAudioPlayer if available
        if (m_customAudioPlayer) {
            m_customAudioPlayer->setBandGain(band, gainDb);
        }
        
        emit eqBandsChanged();
        
        qDebug() << "[AudioEqualizer] Band" << band << "set to" << gainDb << "dB";
    }
}

qreal AudioEqualizer::getBandGain(int band) const
{
    if (band < 0 || band >= 10) {
        return 0.0;
    }
    return m_bandGains[band];
}

void AudioEqualizer::reset()
{
    bool changed = false;
    for (int i = 0; i < 10; ++i) {
        if (qAbs(m_bandGains[i]) > 0.01) {
            m_bandGains[i] = 0.0;
            m_eqBands[i] = QVariant(0.0);
            changed = true;
        }
    }
    
    if (changed) {
        // Sync to CustomAudioPlayer if available
        syncToCustomPlayer();
        
        emit eqBandsChanged();
        qDebug() << "[AudioEqualizer] Reset all bands to 0 dB";
    }
}

void AudioEqualizer::setCustomAudioPlayer(QObject* customPlayer)
{
    CustomAudioPlayer* player = qobject_cast<CustomAudioPlayer*>(customPlayer);
    if (player != m_customAudioPlayer) {
        m_customAudioPlayer = player;
        
        // Sync current EQ settings to CustomAudioPlayer
        if (m_customAudioPlayer) {
            // First, load existing settings from CustomAudioPlayer (if any)
            // This ensures we don't overwrite saved EQ settings
            QVariantList existingGains;
            bool hasExistingSettings = false;
            for (int i = 0; i < 10; ++i) {
                qreal gain = m_customAudioPlayer->getBandGain(i);
                existingGains.append(gain);
                if (qAbs(gain) > 0.01) {
                    hasExistingSettings = true;
                }
            }
            
            // If CustomAudioPlayer has existing settings, use those
            if (hasExistingSettings) {
                for (int i = 0; i < 10; ++i) {
                    m_bandGains[i] = existingGains[i].toReal();
                    m_eqBands[i] = existingGains[i];
                }
                emit eqBandsChanged();
            } else {
                // Otherwise, sync our settings to CustomAudioPlayer
                syncToCustomPlayer();
            }
            
            // Sync enabled state
            bool customEnabled = m_customAudioPlayer->isEQEnabled();
            if (customEnabled != m_enabled) {
                m_enabled = customEnabled;
                emit enabledChanged();
            } else {
                m_customAudioPlayer->setEQEnabled(m_enabled);
            }
        }
    }
}

void AudioEqualizer::syncToCustomPlayer()
{
    if (!m_customAudioPlayer) {
        return;
    }
    
    // Sync all band gains to CustomAudioPlayer
    for (int i = 0; i < 10; ++i) {
        m_customAudioPlayer->setBandGain(i, m_bandGains[i]);
    }
}

qreal AudioEqualizer::dbToLinear(qreal db) const
{
    return qPow(10.0, db / 20.0);
}

qreal AudioEqualizer::calculateVolumeMultiplier() const
{
    if (!m_enabled) {
        return 1.0;
    }
    
    // Calculate average gain across all bands
    // This is a simplified approach - real EQ would apply filters per frequency band
    qreal avgGainDb = 0.0;
    for (int i = 0; i < 10; ++i) {
        avgGainDb += m_bandGains[i];
    }
    avgGainDb /= 10.0;
    
    // Convert to linear and apply as a volume multiplier
    // Note: This is a simplified implementation
    // Real EQ would require frequency-domain filtering
    return dbToLinear(avgGainDb);
}

qreal AudioEqualizer::getVolumeMultiplier() const
{
    return calculateVolumeMultiplier();
}

void AudioEqualizer::applyToAudioOutput(QAudioOutput *audioOutput)
{
    if (!audioOutput) {
        return;
    }
    
    // Note: Qt's AudioOutput doesn't directly support EQ
    // This is a placeholder for future implementation
    // Real EQ would require:
    // 1. Intercepting audio samples
    // 2. Applying FFT to get frequency components
    // 3. Applying band-specific gains
    // 4. Converting back to time domain
    // 5. Outputting processed audio
    
    // For now, we can't directly modify the audio stream
    // This would require a custom audio processing pipeline
    qDebug() << "[AudioEqualizer] applyToAudioOutput called (not yet implemented for direct audio stream processing)";
}

