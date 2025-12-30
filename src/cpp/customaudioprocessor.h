#ifndef CUSTOMAUDIOPROCESSOR_H
#define CUSTOMAUDIOPROCESSOR_H

#include <QObject>
#include <QAudioFormat>
#include <QAudioBuffer>
#include <QByteArray>
#include <atomic>
#include <cstdint>

// Real-time safe biquad filter structure
struct Biquad {
    float b0, b1, b2, a1, a2;  // Filter coefficients
    float x1, x2, y1, y2;       // State (delayed samples)
    
    Biquad() : b0(1.0f), b1(0.0f), b2(0.0f), a1(0.0f), a2(0.0f),
               x1(0.0f), x2(0.0f), y1(0.0f), y2(0.0f) {}
    
    void reset() {
        x1 = x2 = y1 = y2 = 0.0f;
    }
    
    // Process one sample - real-time safe, no allocations
    inline float process(float input) {
        float output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
        x2 = x1;
        x1 = input;
        y2 = y1;
        y1 = output;
        return output;
    }
};

// Double-buffered filter coefficients for lock-free updates
struct FilterBank {
    Biquad filters[2][10];  // [buffer_index][band] - double buffered
    std::atomic<int> activeBuffer{0};  // Lock-free swap
    
    Biquad* getActive() { return filters[activeBuffer.load()]; }
    Biquad* getInactive() { return filters[1 - activeBuffer.load()]; }
    void swap() { activeBuffer.store(1 - activeBuffer.load()); }
};

class CustomAudioProcessor : public QObject
{
    Q_OBJECT

public:
    explicit CustomAudioProcessor(QObject *parent = nullptr);
    ~CustomAudioProcessor();

    // Initialize with audio format
    void initialize(const QAudioFormat &format);
    
    // Set EQ band gain in dB (-12 to +12) - updates on UI thread, swapped lock-free
    void setBandGain(int band, qreal gainDb);
    qreal getBandGain(int band) const;
    void resetEQ();
    
    // Set all band gains at once (useful for restoring saved EQ settings)
    // Takes QVariantList of 10 gain values in dB
    void setAllBandGains(const QVariantList &gains);
    
    // Enable/disable processing
    void setEnabled(bool enabled);
    bool isEnabled() const { return m_enabled; }
    
    // Process audio buffer - returns processed QByteArray
    // Simple approach: decode buffer, apply EQ, return processed bytes
    QByteArray processBuffer(const QAudioBuffer &buffer);

signals:
    void processingError(const QString &error);

private:
    // Real-time safe processing - no allocations, no locks, float math
    void processInPlace(float* samples, int numSamples, int numChannels);
    
    // Update filter coefficients (called from UI thread)
    void updateFilterCoefficients();
    
    // RBJ biquad peaking filter coefficient calculation
    void calculatePeakingFilter(Biquad& bq, float freq, float gainDb, float Q, float sampleRate);

private:
    QAudioFormat m_format;
    
    // Lock-free parameter storage
    std::atomic<float> m_bandGains[10];  // Atomic gains in dB
    std::atomic<bool> m_coefficientsDirty{false};  // Flag to update coefficients
    std::atomic<bool> m_enabled{false};

    FilterBank m_filterBank[2];  // Per channel (stereo = 2 channels)
    int m_sampleRate;
    int m_channels;

    // EQ frequency bands (Hz)
    static const float EQ_FREQUENCIES[10];
    static const float EQ_Q_VALUES[10];  // Q factor for each band
};

#endif // CUSTOMAUDIOPROCESSOR_H
