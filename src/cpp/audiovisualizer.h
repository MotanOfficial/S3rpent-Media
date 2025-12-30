#ifndef AUDIOVISUALIZER_H
#define AUDIOVISUALIZER_H

#include <QObject>
#include <QMediaPlayer>
#include <QAudioSource>
#include <QAudioDevice>
#include <QAudioFormat>
#include <QIODevice>
#include <QVector>
#include <QVariantList>
#include <QTimer>
#include <QByteArray>
#include <QMediaDevices>
#include <cmath>
#include <complex>

#ifdef Q_OS_WIN
#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <functiondiscoverykeys_devpkey.h>
#endif

class AudioVisualizer : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList frequencyBands READ frequencyBands NOTIFY frequencyBandsChanged)
    Q_PROPERTY(qreal overallAmplitude READ overallAmplitude NOTIFY overallAmplitudeChanged)
    Q_PROPERTY(qreal bassAmplitude READ bassAmplitude NOTIFY bassAmplitudeChanged)
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)

public:
    explicit AudioVisualizer(QObject *parent = nullptr);
    ~AudioVisualizer();

    Q_INVOKABLE void setMediaPlayer(QObject *mediaPlayer);
    Q_INVOKABLE void start();
    Q_INVOKABLE void stop();
    
    // Feed audio samples directly from CustomAudioPlayer (avoids WASAPI loopback capturing all system audio)
    Q_INVOKABLE void feedAudioSamples(const QByteArray &audioData, const QAudioFormat &format);
    
    QVariantList frequencyBands() const { return m_frequencyBands; }
    qreal overallAmplitude() const { return m_overallAmplitude; }
    qreal bassAmplitude() const { return m_bassAmplitude; }
    bool active() const { return m_active; }

signals:
    void frequencyBandsChanged();
    void overallAmplitudeChanged();
    void bassAmplitudeChanged();
    void activeChanged();

private slots:
    void processAudioSamples();
    void updateVisualization();

private:
    void performFFT(const QVector<qreal> &samples);
    QVector<qreal> calculateFrequencyBands(const QVector<qreal> &fftMagnitudes);
    bool setupWindowsLoopback();
    void cleanupWindowsLoopback();
    
    QObject *m_mediaPlayer;
    QMediaPlayer *m_player;
    QTimer *m_updateTimer;
    QTimer *m_captureTimer;
    
    QVector<qreal> m_samples;
    QVariantList m_frequencyBands;
    qreal m_overallAmplitude;
    qreal m_bassAmplitude;
    bool m_active;
    bool m_useDirectFeed;  // Use direct audio feed instead of WASAPI loopback
    QAudioFormat m_audioFormat;  // Format for direct feed
    
#ifdef Q_OS_WIN
    IMMDeviceEnumerator *m_deviceEnumerator;
    IMMDevice *m_loopbackDevice;
    IAudioClient *m_audioClient;
    IAudioCaptureClient *m_captureClient;
    HANDLE m_eventHandle;
    bool m_wasapiInitialized;
#endif
    
    static const int FFT_SIZE = 2048;
    static const int BAND_COUNT = 32;
};

#endif // AUDIOVISUALIZER_H
