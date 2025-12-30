#include "audiovisualizer.h"
#include <QDebug>
#include <QMediaPlayer>
#include <QTime>
#include <algorithm>
#include <cmath>

#ifdef Q_OS_WIN
#include <comdef.h>
#include <comip.h>
_COM_SMARTPTR_TYPEDEF(IMMDeviceEnumerator, __uuidof(IMMDeviceEnumerator));
_COM_SMARTPTR_TYPEDEF(IMMDevice, __uuidof(IMMDevice));
_COM_SMARTPTR_TYPEDEF(IAudioClient, __uuidof(IAudioClient));
_COM_SMARTPTR_TYPEDEF(IAudioCaptureClient, __uuidof(IAudioCaptureClient));
#endif

AudioVisualizer::AudioVisualizer(QObject *parent)
    : QObject(parent)
    , m_mediaPlayer(nullptr)
    , m_player(nullptr)
    , m_updateTimer(new QTimer(this))
    , m_captureTimer(new QTimer(this))
    , m_overallAmplitude(0.0)
    , m_bassAmplitude(0.0)
    , m_active(false)
    , m_useDirectFeed(false)
#ifdef Q_OS_WIN
    , m_deviceEnumerator(nullptr)
    , m_loopbackDevice(nullptr)
    , m_audioClient(nullptr)
    , m_captureClient(nullptr)
    , m_eventHandle(nullptr)
    , m_wasapiInitialized(false)
#endif
{
    m_samples.reserve(FFT_SIZE);
    m_frequencyBands.reserve(BAND_COUNT);
    for (int i = 0; i < BAND_COUNT; ++i) {
        m_frequencyBands.append(0.0);
    }
    
    connect(m_updateTimer, &QTimer::timeout, this, &AudioVisualizer::updateVisualization);
    m_updateTimer->setInterval(16);  // Update 60 times per second (60 FPS)
    
    connect(m_captureTimer, &QTimer::timeout, this, &AudioVisualizer::processAudioSamples);
    m_captureTimer->setInterval(10);  // Capture every 10ms
}

AudioVisualizer::~AudioVisualizer()
{
    stop();
    cleanupWindowsLoopback();
}

void AudioVisualizer::setMediaPlayer(QObject *mediaPlayer)
{
    m_mediaPlayer = mediaPlayer;
    m_player = qobject_cast<QMediaPlayer*>(mediaPlayer);
    qDebug() << "[AudioVisualizer] Media player set";
}

void AudioVisualizer::start()
{
    if (m_active) {
        return;
    }
    
    // If using direct feed, don't setup WASAPI loopback
    if (!m_useDirectFeed) {
#ifdef Q_OS_WIN
        if (setupWindowsLoopback()) {
            m_captureTimer->start();
            qDebug() << "[AudioVisualizer] Started with Windows WASAPI loopback";
        } else {
            qWarning() << "[AudioVisualizer] Failed to setup WASAPI loopback, using fallback";
        }
#endif
    } else {
        qDebug() << "[AudioVisualizer] Started with direct audio feed (no WASAPI loopback)";
    }
    
    m_active = true;
    m_updateTimer->start();
    emit activeChanged();
}

void AudioVisualizer::stop()
{
    if (!m_active) {
        return;
    }
    
    m_updateTimer->stop();
    m_captureTimer->stop();
    
    if (!m_useDirectFeed) {
#ifdef Q_OS_WIN
        cleanupWindowsLoopback();
#endif
    }
    
    m_samples.clear();
    
    // Reset values
    for (int i = 0; i < BAND_COUNT; ++i) {
        m_frequencyBands[i] = 0.0;
    }
    m_overallAmplitude = 0.0;
    
    m_active = false;
    emit activeChanged();
    emit frequencyBandsChanged();
    emit overallAmplitudeChanged();
    
    qDebug() << "[AudioVisualizer] Stopped";
}

#ifdef Q_OS_WIN
bool AudioVisualizer::setupWindowsLoopback()
{
    HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                                  __uuidof(IMMDeviceEnumerator),
                                  reinterpret_cast<void**>(&m_deviceEnumerator));
    if (FAILED(hr)) {
        qWarning() << "[AudioVisualizer] Failed to create device enumerator:" << hr;
        return false;
    }
    
    hr = m_deviceEnumerator->GetDefaultAudioEndpoint(eRender, eConsole, &m_loopbackDevice);
    if (FAILED(hr)) {
        qWarning() << "[AudioVisualizer] Failed to get default audio endpoint:" << hr;
        m_deviceEnumerator->Release();
        m_deviceEnumerator = nullptr;
        return false;
    }
    
    hr = m_loopbackDevice->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                                    reinterpret_cast<void**>(&m_audioClient));
    if (FAILED(hr)) {
        qWarning() << "[AudioVisualizer] Failed to activate audio client:" << hr;
        m_loopbackDevice->Release();
        m_loopbackDevice = nullptr;
        m_deviceEnumerator->Release();
        m_deviceEnumerator = nullptr;
        return false;
    }
    
    WAVEFORMATEX *pwfx = nullptr;
    hr = m_audioClient->GetMixFormat(&pwfx);
    if (FAILED(hr)) {
        qWarning() << "[AudioVisualizer] Failed to get mix format:" << hr;
        cleanupWindowsLoopback();
        return false;
    }
    
    hr = m_audioClient->Initialize(AUDCLNT_SHAREMODE_SHARED,
                                   AUDCLNT_STREAMFLAGS_LOOPBACK,
                                   0, 0, pwfx, nullptr);
    CoTaskMemFree(pwfx);
    
    if (FAILED(hr)) {
        qWarning() << "[AudioVisualizer] Failed to initialize audio client:" << hr;
        cleanupWindowsLoopback();
        return false;
    }
    
    hr = m_audioClient->GetService(__uuidof(IAudioCaptureClient),
                                   reinterpret_cast<void**>(&m_captureClient));
    if (FAILED(hr)) {
        qWarning() << "[AudioVisualizer] Failed to get capture client:" << hr;
        cleanupWindowsLoopback();
        return false;
    }
    
    hr = m_audioClient->Start();
    if (FAILED(hr)) {
        qWarning() << "[AudioVisualizer] Failed to start audio client:" << hr;
        cleanupWindowsLoopback();
        return false;
    }
    
    m_wasapiInitialized = true;
    return true;
}

void AudioVisualizer::cleanupWindowsLoopback()
{
    if (m_audioClient) {
        m_audioClient->Stop();
        m_audioClient->Release();
        m_audioClient = nullptr;
    }
    
    if (m_captureClient) {
        m_captureClient->Release();
        m_captureClient = nullptr;
    }
    
    if (m_loopbackDevice) {
        m_loopbackDevice->Release();
        m_loopbackDevice = nullptr;
    }
    
    if (m_deviceEnumerator) {
        m_deviceEnumerator->Release();
        m_deviceEnumerator = nullptr;
    }
    
    if (m_eventHandle) {
        CloseHandle(m_eventHandle);
        m_eventHandle = nullptr;
    }
    
    m_wasapiInitialized = false;
}

void AudioVisualizer::feedAudioSamples(const QByteArray &audioData, const QAudioFormat &format)
{
    if (!m_active || audioData.isEmpty()) {
        return;
    }
    
    // Enable direct feed mode
    m_useDirectFeed = true;
    m_audioFormat = format;
    
    // Convert audio data to float samples
    QVector<qreal> newSamples;
    int sampleSize = format.bytesPerSample();
    int channelCount = format.channelCount();
    int sampleCount = audioData.size() / (sampleSize * channelCount);
    
    if (sampleCount == 0) {
        return;
    }
    
    newSamples.reserve(sampleCount);
    
    const quint8 *data = reinterpret_cast<const quint8*>(audioData.constData());
    
    for (int i = 0; i < sampleCount; ++i) {
        qreal sample = 0.0;
        
        // Convert based on sample format
        if (format.sampleFormat() == QAudioFormat::Int16) {
            const qint16 *samples = reinterpret_cast<const qint16*>(data + i * sampleSize * channelCount);
            // Average channels
            qreal sum = 0.0;
            for (int ch = 0; ch < channelCount; ++ch) {
                sum += samples[ch] / 32768.0;
            }
            sample = sum / channelCount;
        } else if (format.sampleFormat() == QAudioFormat::Int32) {
            const qint32 *samples = reinterpret_cast<const qint32*>(data + i * sampleSize * channelCount);
            // Average channels
            qreal sum = 0.0;
            for (int ch = 0; ch < channelCount; ++ch) {
                sum += samples[ch] / 2147483648.0;
            }
            sample = sum / channelCount;
        } else if (format.sampleFormat() == QAudioFormat::Float) {
            const float *samples = reinterpret_cast<const float*>(data + i * sampleSize * channelCount);
            // Average channels
            qreal sum = 0.0;
            for (int ch = 0; ch < channelCount; ++ch) {
                sum += samples[ch];
            }
            sample = sum / channelCount;
        }
        
        newSamples.append(sample);
    }
    
    if (!newSamples.isEmpty()) {
        m_samples.append(newSamples);
        
        // Keep only the last FFT_SIZE samples
        if (m_samples.size() > FFT_SIZE) {
            m_samples = m_samples.mid(m_samples.size() - FFT_SIZE);
        }
        
        // Calculate overall amplitude with smoothing
        qreal maxAmplitude = 0.0;
        for (qreal sample : newSamples) {
            maxAmplitude = qMax(maxAmplitude, qAbs(sample));
        }
        // Smooth amplitude changes
        m_overallAmplitude = m_overallAmplitude * 0.9 + maxAmplitude * 0.1;
        emit overallAmplitudeChanged();
    }
}

void AudioVisualizer::processAudioSamples()
{
    // Skip WASAPI processing if using direct feed
    if (m_useDirectFeed) {
        return;
    }
    
    if (!m_wasapiInitialized || !m_captureClient) {
        return;
    }
    
    UINT32 packetLength = 0;
    HRESULT hr = m_captureClient->GetNextPacketSize(&packetLength);
    
    while (SUCCEEDED(hr) && packetLength > 0) {
        BYTE *pData;
        UINT32 numFramesAvailable;
        DWORD flags;
        
        hr = m_captureClient->GetBuffer(&pData, &numFramesAvailable, &flags, nullptr, nullptr);
        if (SUCCEEDED(hr)) {
            if (!(flags & AUDCLNT_BUFFERFLAGS_SILENT)) {
                // Convert to float samples (assuming 16-bit PCM)
                const qint16 *samples = reinterpret_cast<const qint16*>(pData);
                int sampleCount = numFramesAvailable * 2;  // Stereo
                
                QVector<qreal> newSamples;
                newSamples.reserve(sampleCount);
                
                for (int i = 0; i < sampleCount; i += 2) {
                    // Average stereo channels
                    qreal left = samples[i] / 32768.0;
                    qreal right = samples[i + 1] / 32768.0;
                    newSamples.append((left + right) / 2.0);
                }
                
                m_samples.append(newSamples);
                
                // Keep only the last FFT_SIZE samples
                if (m_samples.size() > FFT_SIZE) {
                    m_samples = m_samples.mid(m_samples.size() - FFT_SIZE);
                }
                
                // Calculate overall amplitude with smoothing
                if (!newSamples.isEmpty()) {
                    qreal maxAmplitude = 0.0;
                    for (qreal sample : newSamples) {
                        maxAmplitude = qMax(maxAmplitude, qAbs(sample));
                    }
                    // Smooth amplitude changes
                    m_overallAmplitude = m_overallAmplitude * 0.9 + maxAmplitude * 0.1;
                }
            }
            
            m_captureClient->ReleaseBuffer(numFramesAvailable);
        }
        
        hr = m_captureClient->GetNextPacketSize(&packetLength);
    }
}
#else
bool AudioVisualizer::setupWindowsLoopback() { return false; }
void AudioVisualizer::cleanupWindowsLoopback() {}
void AudioVisualizer::processAudioSamples() {}
#endif

void AudioVisualizer::performFFT(const QVector<qreal> &samples)
{
    if (samples.size() < 2) {
        return;
    }
    
    // Simple FFT implementation (Cooley-Tukey)
    int N = samples.size();
    int logN = 0;
    int temp = N;
    while (temp > 1) {
        temp >>= 1;
        logN++;
    }
    
    // Pad to power of 2
    int paddedSize = 1 << logN;
    if (paddedSize < N) paddedSize <<= 1;
    
    QVector<std::complex<qreal>> fftData(paddedSize);
    for (int i = 0; i < paddedSize; ++i) {
        if (i < N) {
            fftData[i] = std::complex<qreal>(samples[i], 0.0);
        } else {
            fftData[i] = std::complex<qreal>(0.0, 0.0);
        }
    }
    
    // Bit-reverse permutation
    for (int i = 1, j = 0; i < paddedSize; ++i) {
        int bit = paddedSize >> 1;
        for (; j & bit; bit >>= 1) {
            j ^= bit;
        }
        j ^= bit;
        if (i < j) {
            std::swap(fftData[i], fftData[j]);
        }
    }
    
    // FFT computation
    for (int len = 2; len <= paddedSize; len <<= 1) {
        qreal angle = -2.0 * M_PI / len;
        std::complex<qreal> wlen(std::cos(angle), std::sin(angle));
        for (int i = 0; i < paddedSize; i += len) {
            std::complex<qreal> w(1.0);
            for (int j = 0; j < len / 2; ++j) {
                std::complex<qreal> u = fftData[i + j];
                std::complex<qreal> v = fftData[i + j + len / 2] * w;
                fftData[i + j] = u + v;
                fftData[i + j + len / 2] = u - v;
                w *= wlen;
            }
        }
    }
    
    // Calculate magnitudes
    QVector<qreal> magnitudes(paddedSize / 2);
    for (int i = 0; i < paddedSize / 2; ++i) {
        magnitudes[i] = std::abs(fftData[i]) / paddedSize;
    }
    
    // Calculate kick amplitude (80-150 Hz) - focused on kick drum punch, excludes deep sub bass
    const qreal sampleRate = 44100.0;  // Assume 44.1kHz
    const qreal bassStartFreq = 80.0;  // Kick drum range start (excludes sub bass)
    const qreal bassEndFreq = 150.0;   // Kick drum range end
    int bassStartBin = static_cast<int>(bassStartFreq * paddedSize / sampleRate);
    int bassEndBin = static_cast<int>(bassEndFreq * paddedSize / sampleRate);
    bassStartBin = qBound(0, bassStartBin, magnitudes.size() - 1);
    bassEndBin = qBound(bassStartBin + 1, bassEndBin, magnitudes.size());
    
    qreal bassSum = 0.0;
    for (int i = bassStartBin; i < bassEndBin; ++i) {
        bassSum += magnitudes[i];
    }
    qreal newBassAmplitude = (bassEndBin > bassStartBin) ? (bassSum / (bassEndBin - bassStartBin)) : 0.0;
    newBassAmplitude *= 40.0;  // Slightly increased scale for kick detection
    newBassAmplitude = qBound(0.0, newBassAmplitude, 1.0);  // Clamp to 0-1
    
    // Slightly more smoothing for kick detection - balanced response
    // 75% old, 25% new (slightly smoother while still catching kick hits)
    m_bassAmplitude = m_bassAmplitude * 0.75 + newBassAmplitude * 0.25;
    emit bassAmplitudeChanged();
    
    QVector<qreal> bands = calculateFrequencyBands(magnitudes);
    
    // Update frequency bands with heavy smoothing
    for (int i = 0; i < BAND_COUNT; ++i) {
        qreal newValue = bands[i] * 10.0;  // Scale up
        newValue = qBound(0.0, newValue, 1.0);  // Clamp to 0-1
        
        // Heavy smoothing (exponential moving average) - 85% old, 15% new
        qreal current = m_frequencyBands[i].toReal();
        m_frequencyBands[i] = current * 0.85 + newValue * 0.15;
    }
}

QVector<qreal> AudioVisualizer::calculateFrequencyBands(const QVector<qreal> &fftMagnitudes)
{
    QVector<qreal> bands(BAND_COUNT, 0.0);
    
    if (fftMagnitudes.isEmpty()) {
        return bands;
    }
    
    // Map FFT bins to frequency bands (logarithmic scale)
    const int fftSize = fftMagnitudes.size();
    const qreal sampleRate = 44100.0;  // Assume 44.1kHz
    
    for (int band = 0; band < BAND_COUNT; ++band) {
        // Logarithmic frequency mapping (20 Hz to 20 kHz)
        qreal startFreq = std::pow(10.0, band * 2.0 / BAND_COUNT) * 20.0;
        qreal endFreq = std::pow(10.0, (band + 1) * 2.0 / BAND_COUNT) * 20.0;
        
        int startBin = static_cast<int>(startFreq * fftSize / (sampleRate / 2.0));
        int endBin = static_cast<int>(endFreq * fftSize / (sampleRate / 2.0));
        
        startBin = qBound(0, startBin, fftSize - 1);
        endBin = qBound(startBin + 1, endBin, fftSize);
        
        // Average magnitude in this frequency band
        qreal sum = 0.0;
        for (int bin = startBin; bin < endBin; ++bin) {
            sum += fftMagnitudes[bin];
        }
        bands[band] = (endBin > startBin) ? (sum / (endBin - startBin)) : 0.0;
    }
    
    return bands;
}

void AudioVisualizer::updateVisualization()
{
    if (m_samples.size() >= 512) {  // Need enough samples for FFT
        performFFT(m_samples);
        emit frequencyBandsChanged();
    }
    
    emit overallAmplitudeChanged();
}
