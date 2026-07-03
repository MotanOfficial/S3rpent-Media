#include "customaudioplayer.h"
#include "audiovisualizer.h"

#include <QDebug>
#include <cstring>

#ifdef HAS_FFMPEG_LIBS

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/channel_layout.h>
#include <libavutil/opt.h>
#include <libswresample/swresample.h>
}

namespace {

constexpr int kFfmpegOutputRate = 44100;
constexpr int kFfmpegOutputChannels = 2;

AVChannelLayout outputChannelLayout()
{
    AVChannelLayout layout{};
    av_channel_layout_default(&layout, kFfmpegOutputChannels);
    return layout;
}

} // namespace

bool CustomAudioPlayer::initFfmpegLocalDecoder(const QString &path)
{
    shutdownFfmpegLocalDecoder();

    if (avformat_open_input(&m_avFmt, path.toUtf8().constData(), nullptr, nullptr) < 0) {
        qWarning() << "[CustomAudioPlayer] FFmpeg: failed to open" << path;
        return false;
    }
    if (avformat_find_stream_info(m_avFmt, nullptr) < 0) {
        qWarning() << "[CustomAudioPlayer] FFmpeg: stream info failed";
        shutdownFfmpegLocalDecoder();
        return false;
    }

    m_avAudioStream = av_find_best_stream(m_avFmt, AVMEDIA_TYPE_AUDIO, -1, -1, nullptr, 0);
    if (m_avAudioStream < 0) {
        qWarning() << "[CustomAudioPlayer] FFmpeg: no audio stream";
        shutdownFfmpegLocalDecoder();
        return false;
    }

    AVStream *stream = m_avFmt->streams[m_avAudioStream];
    const AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
    if (!codec) {
        shutdownFfmpegLocalDecoder();
        return false;
    }

    m_avCodec = avcodec_alloc_context3(codec);
    if (!m_avCodec || avcodec_parameters_to_context(m_avCodec, stream->codecpar) < 0) {
        shutdownFfmpegLocalDecoder();
        return false;
    }
    if (avcodec_open2(m_avCodec, codec, nullptr) < 0) {
        shutdownFfmpegLocalDecoder();
        return false;
    }

    AVChannelLayout outLayout = outputChannelLayout();
    if (swr_alloc_set_opts2(
            &m_swr,
            &outLayout,
            AV_SAMPLE_FMT_S16,
            kFfmpegOutputRate,
            &m_avCodec->ch_layout,
            m_avCodec->sample_fmt,
            m_avCodec->sample_rate,
            0,
            nullptr) < 0
        || swr_init(m_swr) < 0) {
        av_channel_layout_uninit(&outLayout);
        shutdownFfmpegLocalDecoder();
        return false;
    }
    av_channel_layout_uninit(&outLayout);

    m_avPacket = av_packet_alloc();
    m_avFrame = av_frame_alloc();
    if (!m_avPacket || !m_avFrame) {
        shutdownFfmpegLocalDecoder();
        return false;
    }

    m_audioFormat = QAudioFormat();
    m_audioFormat.setSampleRate(kFfmpegOutputRate);
    m_audioFormat.setChannelCount(kFfmpegOutputChannels);
    m_audioFormat.setSampleFormat(QAudioFormat::Int16);

    m_ffmpegActive = true;
    m_ffmpegEof = false;
    m_seekable = true;
    emit seekableChanged();

    if (m_avFmt->duration != AV_NOPTS_VALUE && m_avFmt->duration > 0) {
        const qint64 durMs = (m_avFmt->duration * 1000LL) / AV_TIME_BASE;
        if (durMs > 0) {
            m_duration = durMs;
            m_durationCalculated = true;
            emit durationChanged();
        }
    }

    return true;
}

void CustomAudioPlayer::shutdownFfmpegLocalDecoder()
{
    if (m_ffmpegPumpTimer) {
        m_ffmpegPumpTimer->stop();
    }
    m_ffmpegActive = false;
    m_ffmpegEof = false;
    m_avAudioStream = -1;

    if (m_avPacket) {
        av_packet_free(&m_avPacket);
        m_avPacket = nullptr;
    }
    if (m_avFrame) {
        av_frame_free(&m_avFrame);
        m_avFrame = nullptr;
    }
    if (m_swr) {
        swr_free(&m_swr);
        m_swr = nullptr;
    }
    if (m_avCodec) {
        avcodec_free_context(&m_avCodec);
        m_avCodec = nullptr;
    }
    if (m_avFmt) {
        avformat_close_input(&m_avFmt);
        m_avFmt = nullptr;
    }
}

void CustomAudioPlayer::enqueuePcmBuffer(const QByteArray &pcm, int sampleRate, int channels)
{
    if (pcm.isEmpty() || !m_audioFormat.isValid())
        return;

    QAudioFormat fmt;
    fmt.setSampleRate(sampleRate);
    fmt.setChannelCount(channels);
    fmt.setSampleFormat(QAudioFormat::Int16);

    const int frameCount = pcm.size() / (channels * static_cast<int>(sizeof(qint16)));
    if (frameCount <= 0)
        return;

    QAudioBuffer buffer(frameCount, fmt);
    if (!buffer.isValid())
        return;
    std::memcpy(buffer.data<char>(), pcm.constData(), static_cast<size_t>(pcm.size()));

    if (!m_formatInitialized) {
        if (m_audioSink) {
            m_audioSink->stop();
            m_audioSink->suspend();
            delete m_audioSink;
            m_audioSink = nullptr;
        }
        m_audioSink = new QAudioSink(m_audioFormat, this);
        m_audioSink->setVolume(m_volume);
        m_audioDevice = m_audioSink->start();
        if (!m_audioDevice) {
            return;
        }
        m_formatInitialized = true;
        m_seekable = true;
        emit seekableChanged();
        if (m_playbackState == StoppedState && m_audioSink) {
            m_audioSink->suspend();
        }
    }

    m_totalFrames += frameCount;

    if (m_playbackState == StoppedState) {
        return;
    }

    {
        QMutexLocker locker(&m_writeMutex);
        m_pendingWrites.append(buffer);
    }
    if (m_playbackState == PlayingState && m_writeTimer && !m_writeTimer->isActive()) {
        m_writeTimer->start();
    }
}

void CustomAudioPlayer::pumpFfmpegAudio()
{
    {
        QMutexLocker locker(&m_cleanupMutex);
        if (m_cleaningUp || !m_ffmpegActive || !m_avFmt || !m_avCodec) {
            return;
        }
    }

    if (m_playbackState != PlayingState) {
        return;
    }

    if (m_ffmpegEof) {
        return;
    }

    constexpr int kMaxPacketsPerTick = 12;
    for (int n = 0; n < kMaxPacketsPerTick; ++n) {
        int ret = av_read_frame(m_avFmt, m_avPacket);
        if (ret == AVERROR_EOF) {
            m_ffmpegEof = true;
            return;
        }
        if (ret < 0) {
            return;
        }
        if (m_avPacket->stream_index != m_avAudioStream) {
            av_packet_unref(m_avPacket);
            continue;
        }

        if (avcodec_send_packet(m_avCodec, m_avPacket) < 0) {
            av_packet_unref(m_avPacket);
            continue;
        }
        av_packet_unref(m_avPacket);

        while (true) {
            ret = avcodec_receive_frame(m_avCodec, m_avFrame);
            if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
                break;
            }
            if (ret < 0) {
                break;
            }

            const int outSamples = swr_get_out_samples(m_swr, m_avFrame->nb_samples);
            if (outSamples <= 0) {
                av_frame_unref(m_avFrame);
                continue;
            }

            const int pcmBytes = outSamples * kFfmpegOutputChannels * static_cast<int>(sizeof(qint16));
            QByteArray pcm(pcmBytes, '\0');
            uint8_t *outData = reinterpret_cast<uint8_t *>(pcm.data());
            const int converted = swr_convert(
                m_swr,
                &outData,
                outSamples,
                const_cast<const uint8_t **>(m_avFrame->extended_data),
                m_avFrame->nb_samples);
            av_frame_unref(m_avFrame);

            if (converted <= 0) {
                continue;
            }

            pcm.resize(converted * kFfmpegOutputChannels * static_cast<int>(sizeof(qint16)));
            enqueuePcmBuffer(pcm, kFfmpegOutputRate, kFfmpegOutputChannels);

            {
                QMutexLocker locker(&m_writeMutex);
                if (m_pendingWrites.size() > 48) {
                    return;
                }
            }
        }
    }
}

void CustomAudioPlayer::seekFfmpegLocal(qint64 positionMs)
{
    if (!m_ffmpegActive || !m_avFmt || !m_avCodec || m_avAudioStream < 0) {
        return;
    }

    const qint64 target = qBound(0LL, positionMs, m_duration > 0 ? m_duration : positionMs);

    m_position = target;
    m_basePosition = target;
    m_totalFrames = (target * kFfmpegOutputRate) / 1000;
    if (m_audioFormat.sampleRate() > 0 && m_audioFormat.channelCount() > 0 && m_audioFormat.bytesPerSample() > 0) {
        const qint64 samples = (target * m_audioFormat.sampleRate() * m_audioFormat.channelCount()) / 1000;
        m_bytesWritten = samples * m_audioFormat.bytesPerSample();
    }
    m_playbackStartTime.invalidate();
    emit positionChanged();

    {
        QMutexLocker locker(&m_writeMutex);
        m_pendingWrites.clear();
    }
    m_partialProcessedData.clear();

    if (m_audioSink) {
        m_audioSink->stop();
        m_audioDevice = nullptr;
    }

    AVStream *stream = m_avFmt->streams[m_avAudioStream];
    const int64_t ts = av_rescale_q(target, AVRational{1, 1000}, stream->time_base);
    av_seek_frame(m_avFmt, m_avAudioStream, ts, AVSEEK_FLAG_BACKWARD);
    avcodec_flush_buffers(m_avCodec);
    m_ffmpegEof = false;
    m_seekTargetPosition = 0;

    if (m_seekPreserveState == PlayingState) {
        if (!m_formatInitialized) {
            m_audioSink = new QAudioSink(m_audioFormat, this);
            m_audioSink->setVolume(m_volume);
            m_formatInitialized = true;
            m_seekable = true;
            emit seekableChanged();
        }
        if (m_audioSink) {
            m_audioDevice = m_audioSink->start();
            if (m_audioDevice && m_audioDevice->isOpen()) {
                if (m_positionTimer) {
                    m_positionTimer->start();
                }
                if (m_writeTimer) {
                    m_writeTimer->start();
                }
                if (m_ffmpegPumpTimer && !m_ffmpegPumpTimer->isActive()) {
                    m_ffmpegPumpTimer->start();
                }
                updatePlaybackState(PlayingState);
            }
        }
    } else if (m_seekPreserveState == PausedState) {
        if (m_writeTimer) {
            m_writeTimer->stop();
        }
        if (m_positionTimer) {
            m_positionTimer->stop();
        }
        updatePlaybackState(PausedState);
    }
}

#endif // HAS_FFMPEG_LIBS
