#include "customaudioprocessor.h"
#include <QDebug>
#include <QtMath>
#include <QVariant>
#include <QVariantList>
#include <cstring>
#include <algorithm>

// EQ frequency bands: 31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000 Hz
const float CustomAudioProcessor::EQ_FREQUENCIES[10] = {
    31.0f, 62.0f, 125.0f, 250.0f, 500.0f, 1000.0f, 2000.0f, 4000.0f, 8000.0f, 16000.0f
};

// Q factors for each band (bandwidth control)
const float CustomAudioProcessor::EQ_Q_VALUES[10] = {
    1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f, 1.0f
};

CustomAudioProcessor::CustomAudioProcessor(QObject *parent)
    : QObject(parent)
    , m_sampleRate(44100)
    , m_channels(2)
{
    // Initialize atomic gains to 0 dB
    for (int i = 0; i < 10; ++i) {
        m_bandGains[i].store(0.0f);
    }
    
    // Processor is enabled by default - EQ should work immediately
    m_enabled.store(true);
    qDebug() << "[CustomAudioProcessor] Created (enabled by default)";
}

CustomAudioProcessor::~CustomAudioProcessor()
{
}

void CustomAudioProcessor::initialize(const QAudioFormat &format)
{
    m_format = format;
    m_sampleRate = format.sampleRate();
    m_channels = format.channelCount();
    
    // Reset all filters (preserve band gains - they're stored separately)
    for (int ch = 0; ch < 2; ++ch) {
        for (int buf = 0; buf < 2; ++buf) {
            for (int band = 0; band < 10; ++band) {
                m_filterBank[ch].filters[buf][band].reset();
            }
        }
    }
    
    // Ensure processor is enabled after initialization
    m_enabled.store(true);
    
    // Always update filter coefficients after initialization
    // This ensures filters are ready with correct sample rate, preserving any existing EQ settings
    m_coefficientsDirty.store(true);
    updateFilterCoefficients();
    
    // Log current EQ settings for debugging
    bool hasNonZeroGains = false;
    for (int i = 0; i < 10; ++i) {
        if (qAbs(m_bandGains[i].load()) > 0.01f) {
            hasNonZeroGains = true;
            break;
        }
    }
    
    qDebug() << "[CustomAudioProcessor] Initialized with format: sample rate:" << m_sampleRate << "channels:" << m_channels << "enabled:" << m_enabled.load() << "EQ settings preserved:" << hasNonZeroGains;
}

void CustomAudioProcessor::setBandGain(int band, qreal gainDb)
{
    if (band < 0 || band >= 10) {
        qWarning() << "[CustomAudioProcessor] Invalid band index:" << band;
        return;
    }

    // Clamp gain to -12 to +12 dB
    gainDb = qBound(-12.0, gainDb, 12.0);

    float oldGain = m_bandGains[band].load();
    float newGain = static_cast<float>(gainDb);
    
    if (qAbs(oldGain - newGain) > 0.01f) {
        m_bandGains[band].store(newGain);
        m_coefficientsDirty.store(true); // Mark coefficients as dirty
        
        qDebug() << "[CustomAudioProcessor] Band" << band << "gain set to" << newGain << "dB (was" << oldGain << "dB), enabled:" << m_enabled.load() << "sampleRate:" << m_sampleRate;
        
        // Force immediate coefficient update if processor is enabled and format is initialized
        // This ensures coefficients are ready for the next buffer
        if (m_enabled.load() && m_sampleRate > 0) {
            updateFilterCoefficients();
        } else {
            qDebug() << "[CustomAudioProcessor] Not updating coefficients yet - enabled:" << m_enabled.load() << "sampleRate:" << m_sampleRate;
        }
    }
}

qreal CustomAudioProcessor::getBandGain(int band) const
{
    if (band < 0 || band >= 10) {
        return 0.0;
    }
    return m_bandGains[band].load();
}

void CustomAudioProcessor::resetEQ()
{
    bool changed = false;
    for (int i = 0; i < 10; ++i) {
        if (qAbs(m_bandGains[i].load()) > 0.01f) {
            m_bandGains[i].store(0.0f);
            changed = true;
        }
    }

    if (changed) {
        m_coefficientsDirty.store(true); // Mark coefficients as dirty
        qDebug() << "[CustomAudioProcessor] Reset all EQ bands to 0 dB";
        if (m_enabled.load() && m_sampleRate > 0) {
            updateFilterCoefficients();
        }
    }
}

void CustomAudioProcessor::setAllBandGains(const QVariantList &gains)
{
    if (gains.size() != 10) {
        qWarning() << "[CustomAudioProcessor] setAllBandGains: expected 10 gains, got" << gains.size();
        return;
    }
    
    bool changed = false;
    for (int i = 0; i < 10; ++i) {
        bool ok;
        qreal gainDb = gains[i].toReal(&ok);
        if (!ok) {
            qWarning() << "[CustomAudioProcessor] setAllBandGains: invalid gain value at index" << i;
            continue;
        }
        
        // Clamp gain to -12 to +12 dB
        gainDb = qBound(-12.0, gainDb, 12.0);
        
        float oldGain = m_bandGains[i].load();
        float newGain = static_cast<float>(gainDb);
        
        if (qAbs(oldGain - newGain) > 0.01f) {
            m_bandGains[i].store(newGain);
            changed = true;
        }
    }
    
    if (changed) {
        m_coefficientsDirty.store(true);
        qDebug() << "[CustomAudioProcessor] Set all band gains at once";
        if (m_enabled.load() && m_sampleRate > 0) {
            updateFilterCoefficients();
        } else {
            qDebug() << "[CustomAudioProcessor] Not updating coefficients yet - enabled:" << m_enabled.load() << "sampleRate:" << m_sampleRate;
        }
    }
}

void CustomAudioProcessor::setEnabled(bool enabled)
{
    bool oldEnabled = m_enabled.load();
    if (oldEnabled != enabled) {
        m_enabled.store(enabled);
        qDebug() << "[CustomAudioProcessor]" << (enabled ? "Enabled" : "Disabled");
    }
}

QByteArray CustomAudioProcessor::processBuffer(const QAudioBuffer &buffer)
{
    if (!buffer.isValid()) {
        return QByteArray();
    }

    QAudioFormat format = buffer.format();
    int sampleCount = buffer.sampleCount();
    
    if (sampleCount == 0) {
        return QByteArray();
    }

    // Check if processing is needed
    bool needsProcessing = m_enabled.load();
    if (needsProcessing) {
        // Check if any band has non-zero gain
        needsProcessing = false;
        for (int i = 0; i < 10; ++i) {
            float gain = m_bandGains[i].load();
            if (qAbs(gain) > 0.01f) {
                needsProcessing = true;
                static int logCount = 0;
                if (logCount++ < 3) {  // Log first 3 times to avoid spam
                    qDebug() << "[CustomAudioProcessor] Processing needed - band" << i << "has gain" << gain << "dB, enabled:" << m_enabled.load();
                }
                break;
            }
        }
    }

    // Convert input samples to float based on format
    int numSamples = sampleCount / m_channels;
    QVector<float> floatSamples(sampleCount);
    
    QAudioFormat::SampleFormat sampleFormat = format.sampleFormat();
    
    if (sampleFormat == QAudioFormat::Int16) {
        const qint16 *samples = buffer.data<qint16>();
        if (!samples) {
            return QByteArray();
        }
        for (int i = 0; i < sampleCount; ++i) {
            floatSamples[i] = samples[i] / 32768.0f;
        }
    } else if (sampleFormat == QAudioFormat::Int32) {
        const qint32 *samples = buffer.data<qint32>();
        if (!samples) {
            return QByteArray();
        }
        for (int i = 0; i < sampleCount; ++i) {
            floatSamples[i] = samples[i] / 2147483648.0f;  // 2^31
        }
    } else {
        // For other formats (Float, etc.), try to read as float directly
        const float *samples = buffer.data<float>();
        if (samples) {
            for (int i = 0; i < sampleCount; ++i) {
                floatSamples[i] = samples[i];
            }
        } else {
            // Fallback: try Int16
            qWarning() << "[CustomAudioProcessor] Unsupported sample format:" << sampleFormat << ", trying Int16 fallback";
            const qint16 *samples16 = buffer.data<qint16>();
            if (!samples16) {
                return QByteArray();
            }
            for (int i = 0; i < sampleCount; ++i) {
                floatSamples[i] = samples16[i] / 32768.0f;
            }
        }
    }

    // If no processing needed, convert back to Int16 and return
    if (!needsProcessing) {
        QByteArray result;
        result.resize(sampleCount * sizeof(qint16));
        qint16 *outputSamples = reinterpret_cast<qint16*>(result.data());
        
        for (int i = 0; i < sampleCount; ++i) {
            float sample = qBound(-1.0f, floatSamples[i], 1.0f);
            outputSamples[i] = static_cast<qint16>(sample * 32767.0f);
        }
        return result;
    }
    
    static int processLogCount = 0;
    if (processLogCount++ < 3) {  // Log first 3 times to avoid spam
        qDebug() << "[CustomAudioProcessor] Processing buffer with EQ - sampleCount:" << sampleCount << "channels:" << m_channels << "format:" << sampleFormat;
    }

    // Process with EQ
    processInPlace(floatSamples.data(), numSamples, m_channels);

    // Always convert back to Int16 for output (standard format)
    QByteArray result;
    result.resize(sampleCount * sizeof(qint16));
    qint16 *outputSamples = reinterpret_cast<qint16*>(result.data());
    
    for (int i = 0; i < sampleCount; ++i) {
        float sample = qBound(-1.0f, floatSamples[i], 1.0f);
        outputSamples[i] = static_cast<qint16>(sample * 32767.0f);
    }

    return result;
}

void CustomAudioProcessor::processInPlace(float* samples, int numSamples, int numChannels)
{
    // Update coefficients if dirty (UI thread sets flag, audio thread reads it)
    if (m_coefficientsDirty.load()) {
        updateFilterCoefficients();
    }

    // Get active filter bank (lock-free)
    int activeBuf = m_filterBank[0].activeBuffer.load();

    // Process each channel
    for (int ch = 0; ch < numChannels && ch < 2; ++ch) { // Limit to 2 channels for stereo
        Biquad* filters = m_filterBank[ch].filters[activeBuf];

        // Process each sample through all 10 filters in series
        for (int i = 0; i < numSamples; ++i) {
            float sample = samples[i * numChannels + ch];

            for (int band = 0; band < 10; ++band) {
                sample = filters[band].process(sample);
            }
            samples[i * numChannels + ch] = sample;
        }
    }
}

void CustomAudioProcessor::updateFilterCoefficients()
{
    // Only update if coefficients are marked dirty
    if (!m_coefficientsDirty.load()) {
        return;
    }
    
    // If sample rate is not initialized, can't calculate coefficients
    if (m_sampleRate <= 0) {
        qDebug() << "[CustomAudioProcessor] Cannot update coefficients - sample rate not initialized";
        return;
    }

    // Get inactive buffer for writing new coefficients
    int inactiveBuf = 1 - m_filterBank[0].activeBuffer.load();

    qDebug() << "[CustomAudioProcessor] Updating filter coefficients...";
    for (int ch = 0; ch < m_channels && ch < 2; ++ch) {
        for (int band = 0; band < 10; ++band) {
            float gain = m_bandGains[band].load();
            calculatePeakingFilter(m_filterBank[ch].filters[inactiveBuf][band],
                                   EQ_FREQUENCIES[band],
                                   gain,
                                   EQ_Q_VALUES[band],
                                   static_cast<float>(m_sampleRate));
            if (qAbs(gain) > 0.01f) {
                qDebug() << "[CustomAudioProcessor] Band" << band << "(" << EQ_FREQUENCIES[band] << "Hz):" << gain << "dB";
            }
        }
    }

    // Atomically swap to the new coefficients
    for (int ch = 0; ch < m_channels && ch < 2; ++ch) {
        m_filterBank[ch].swap();
    }

    m_coefficientsDirty.store(false); // Reset dirty flag
    qDebug() << "[CustomAudioProcessor] Filter coefficients updated and swapped";
}

void CustomAudioProcessor::calculatePeakingFilter(Biquad& bq, float freq, float gainDb, float Q, float sampleRate)
{
    // RBJ Audio EQ Cookbook - Peaking EQ filter
    // Handle zero gain case (bypass filter)
    if (qAbs(gainDb) < 0.01f) {
        bq.b0 = 1.0f;
        bq.b1 = 0.0f;
        bq.b2 = 0.0f;
        bq.a1 = 0.0f;
        bq.a2 = 0.0f;
        bq.reset();
        return;
    }
    
    float A = qPow(10.0f, gainDb / 40.0f); // Convert dB to linear gain (amplitude)
    float omega = 2.0f * M_PI * freq / sampleRate;
    
    // Clamp omega to valid range
    if (omega <= 0.0f || omega >= M_PI) {
        // Invalid frequency - use bypass
        bq.b0 = 1.0f;
        bq.b1 = 0.0f;
        bq.b2 = 0.0f;
        bq.a1 = 0.0f;
        bq.a2 = 0.0f;
        bq.reset();
        return;
    }
    
    float sin_omega = qSin(omega);
    float cos_omega = qCos(omega);
    float alpha = sin_omega / (2.0f * Q);

    float b0, b1, b2, a0, a1, a2;

    b0 = 1.0f + alpha * A;
    b1 = -2.0f * cos_omega;
    b2 = 1.0f - alpha * A;
    a0 = 1.0f + alpha / A;
    a1 = -2.0f * cos_omega;
    a2 = 1.0f - alpha / A;

    // Normalize coefficients by a0
    if (qAbs(a0) > 1e-10f) {  // Avoid division by zero
        bq.b0 = b0 / a0;
        bq.b1 = b1 / a0;
        bq.b2 = b2 / a0;
        bq.a1 = a1 / a0;
        bq.a2 = a2 / a0;
    } else {
        // Fallback to bypass if a0 is too small
        bq.b0 = 1.0f;
        bq.b1 = 0.0f;
        bq.b2 = 0.0f;
        bq.a1 = 0.0f;
        bq.a2 = 0.0f;
    }
    
    // Reset filter state when updating coefficients
    bq.reset();
    
    // Debug: log filter coefficients for non-zero gains
    if (qAbs(gainDb) > 0.01f) {
        static int logCount = 0;
        if (logCount++ < 3) {
            qDebug() << "[CustomAudioProcessor] Filter" << freq << "Hz:" << "gain=" << gainDb << "dB, b0=" << bq.b0 << "b1=" << bq.b1 << "b2=" << bq.b2 << "a1=" << bq.a1 << "a2=" << bq.a2;
        }
    }
}
