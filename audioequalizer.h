#ifndef AUDIOEQUALIZER_H
#define AUDIOEQUALIZER_H

#include <QObject>
#include <QVariant>
#include <QAudioFormat>
#include <QVector>
#include <QAudioSink>
#include <QIODevice>
#include <QtMultimedia/QMediaPlayer>
#include <QtMultimedia/QAudioOutput>

class CustomAudioPlayer;  // Forward declaration

class AudioEqualizer : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList eqBands READ eqBands NOTIFY eqBandsChanged)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(QObject* customAudioPlayer WRITE setCustomAudioPlayer)

public:
    explicit AudioEqualizer(QObject *parent = nullptr);
    ~AudioEqualizer();

    QVariantList eqBands() const { return m_eqBands; }
    bool enabled() const { return m_enabled; }
    void setEnabled(bool enabled);

    // Set EQ band gain in dB (-12 to +12)
    Q_INVOKABLE void setBandGain(int band, qreal gainDb);
    Q_INVOKABLE qreal getBandGain(int band) const;
    Q_INVOKABLE void reset();

    // Apply EQ to MediaPlayer's AudioOutput (not used - kept for compatibility)
    Q_INVOKABLE void applyToAudioOutput(QAudioOutput *audioOutput);
    
    // Get the volume multiplier based on EQ settings
    Q_INVOKABLE qreal getVolumeMultiplier() const;
    
    // Set CustomAudioPlayer to sync EQ settings with
    void setCustomAudioPlayer(QObject* customPlayer);

signals:
    void eqBandsChanged();
    void enabledChanged();

private:
    QVector<qreal> m_bandGains;  // 10 bands, values in dB
    QVariantList m_eqBands;
    bool m_enabled;
    CustomAudioPlayer* m_customAudioPlayer;  // Reference to CustomAudioPlayer for real EQ

    // Convert dB to linear gain
    qreal dbToLinear(qreal db) const;
    
    // Apply EQ gain to volume (simplified approach)
    qreal calculateVolumeMultiplier() const;
    
    // Sync band gains to CustomAudioPlayer if available
    void syncToCustomPlayer();
};

#endif // AUDIOEQUALIZER_H

