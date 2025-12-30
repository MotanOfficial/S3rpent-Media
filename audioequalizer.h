#ifndef AUDIOEQUALIZER_H
#define AUDIOEQUALIZER_H

#include <QObject>
#include <QVariant>
#include <QVector>

class CustomAudioPlayer; // forward declare

class AudioEqualizer : public QObject
{
    Q_OBJECT
    // Note: Q_PROPERTY(bool) removed due to Qt 6.10.1 MOC bug with bool properties
    // Using Q_INVOKABLE methods instead
    Q_PROPERTY(QObject* customAudioPlayer READ customAudioPlayer WRITE setCustomAudioPlayer)

public:
    explicit AudioEqualizer(QObject *parent = nullptr);
    ~AudioEqualizer();

    Q_INVOKABLE bool enabled() const { return m_enabled; }
    Q_INVOKABLE void setEnabled(bool enabled);

    Q_INVOKABLE int bandCount() const;
    Q_INVOKABLE qreal bandGain(int band) const;
    Q_INVOKABLE void setBandGain(int band, qreal gainDb);
    Q_INVOKABLE qreal getBandGain(int band) const;
    Q_INVOKABLE void reset();
    Q_INVOKABLE qreal getVolumeMultiplier() const;
    
    QObject* customAudioPlayer() const { return (QObject*)(m_customAudioPlayer); }
    void setCustomAudioPlayer(QObject* player);

signals:
    void eqBandsChanged();
    void enabledChanged();

private:
    QVector<qreal> m_bandGains;
    QVariantList m_eqBands;
    bool m_enabled = false;

    CustomAudioPlayer* m_customAudioPlayer = nullptr;

    qreal dbToLinear(qreal db) const;
    qreal calculateVolumeMultiplier() const;
    void syncToCustomPlayer();
};

#endif // AUDIOEQUALIZER_H
