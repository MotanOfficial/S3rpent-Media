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
    m_bandGains.resize(10);
    m_eqBands.clear();

    for (int i = 0; i < 10; ++i) {
        m_bandGains[i] = 0.0;
        m_eqBands.append(0.0);
    }
}

AudioEqualizer::~AudioEqualizer() = default;

int AudioEqualizer::bandCount() const
{
    return m_bandGains.size();
}

qreal AudioEqualizer::bandGain(int band) const
{
    return getBandGain(band);
}

void AudioEqualizer::setEnabled(bool enabled)
{
    if (m_enabled == enabled)
        return;

        m_enabled = enabled;
        
    if (m_customAudioPlayer)
            m_customAudioPlayer->setEQEnabled(enabled);
        
        emit enabledChanged();
}

void AudioEqualizer::setBandGain(int band, qreal gainDb)
{
    if (band < 0 || band >= 10)
        return;
    
    gainDb = qBound(-12.0, gainDb, 12.0);
    
    if (qFuzzyCompare(m_bandGains[band], gainDb))
        return;

        m_bandGains[band] = gainDb;
    m_eqBands[band] = gainDb;
        
    if (m_customAudioPlayer)
            m_customAudioPlayer->setBandGain(band, gainDb);
        
        emit eqBandsChanged();
}

qreal AudioEqualizer::getBandGain(int band) const
{
    if (band < 0 || band >= 10)
        return 0.0;
    return m_bandGains[band];
}

void AudioEqualizer::reset()
{
    for (int i = 0; i < 10; ++i) {
            m_bandGains[i] = 0.0;
        m_eqBands[i] = 0.0;
    }
    
        syncToCustomPlayer();
        emit eqBandsChanged();
}

void AudioEqualizer::setCustomAudioPlayer(QObject *player)
{
    auto cap = qobject_cast<CustomAudioPlayer *>(player);
    if (m_customAudioPlayer == cap)
        return;

    m_customAudioPlayer = cap;
                syncToCustomPlayer();
}

void AudioEqualizer::syncToCustomPlayer()
{
    if (!m_customAudioPlayer)
        return;
    
    for (int i = 0; i < 10; ++i)
        m_customAudioPlayer->setBandGain(i, m_bandGains[i]);

    m_customAudioPlayer->setEQEnabled(m_enabled);
}

qreal AudioEqualizer::dbToLinear(qreal db) const
{
    return qPow(10.0, db / 20.0);
}

qreal AudioEqualizer::getVolumeMultiplier() const
{
    if (!m_enabled)
        return 1.0;

    qreal avg = 0.0;
    for (qreal g : m_bandGains)
        avg += g;

    return dbToLinear(avg / m_bandGains.size());
}
