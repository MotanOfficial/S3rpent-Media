#include "ffmpegvideoplayer.h"
#include "ffmpegvideoplayer_p.h"
#include <QDebug>
#include <cmath>
#include <QtGlobal>

using namespace FfVp;

void FFmpegVideoPlayer::avDiagLogFirstAudioWrite(qint64 writtenBytes,
                                                 qint64 sinkProcUs,
                                                 qint64 bufBytes,
                                                 int bytesFree,
                                                 int sinkState)
{
    if (!ffmpegAvDiagEnabled())
        return;
    if (m_avDiagFirstAudioWriteLogged.exchange(true, std::memory_order_acq_rel))
        return;
    qint64 proc = sinkProcUs;
    qint64 buf = bufBytes;
    int freeB = bytesFree;
    int st = sinkState;
    if (proc < 0 && m_audioMutex.tryLock()) {
        if (m_audioSink) {
            proc = m_audioSink->processedUSecs();
            buf = qint64(m_audioSink->bufferSize());
            if (m_audioDevice && m_audioDevice->isOpen())
                freeB = m_audioSink->bytesFree();
            st = int(m_audioSink->state());
        }
        m_audioMutex.unlock();
    }
    const qint64 queuedUs = m_lastQueuedAudioUSecs.load(std::memory_order_acquire);
    qDebug() << "[FFmpeg][AVDiag] First audio write to QIODevice bytes=" << writtenBytes
             << "wallUs=" << avWallMicros()
             << "wallNowSec=" << nowSeconds()
             << "audioBasePts=" << m_audioBasePts
             << "audioBaseWallTime=" << m_audioBaseWallTime
             << "firstAudioPts=" << m_firstAudioPts
             << "processedUSecs_at_write=" << proc
             << "bufferBytes=" << buf
             << "bytesFree=" << freeB
             << "sinkState=" << st
             << "lastQueuedUSecs_est=" << queuedUs
             << "sinkSnapshotInline=" << (sinkProcUs >= 0);
}

void FFmpegVideoPlayer::avDiagLogAudioWriteSeq(qint64 writtenBytes, qint64 procUs, int bytesFree)
{
    if (!ffmpegAvDiagEnabled())
        return;
    const int n = m_avDiagAudioWriteSeq.fetch_add(1, std::memory_order_acq_rel);
    if (n >= 24)
        return;
    qDebug() << "[FFmpeg][AVDiag] audio write seq" << n << "bytes=" << writtenBytes
             << "wallUs=" << avWallMicros() << "procUs=" << procUs << "bytesFree=" << bytesFree;
}

void FFmpegVideoPlayer::avDiagLogPacedFrame(double rawFramePts, double masterClockAbs, double videoClockAbs,
                                            double diff, double avOffsetSec)
{
    if (!ffmpegAvDiagEnabled())
        return;
    const int idx = m_avDiagPacedFrameIndex++;
    if (idx >= 60)
        return;
    qint64 proc = -1;
    qint64 bufBytes = -1;
    int bytesFree = -1;
    if (m_audioMutex.tryLock()) {
        if (m_audioSink) {
            proc = m_audioSink->processedUSecs();
            bufBytes = qint64(m_audioSink->bufferSize());
            if (m_audioDevice && m_audioDevice->isOpen())
                bytesFree = m_audioSink->bytesFree();
        }
        m_audioMutex.unlock();
    }
    const double rawMinusMaster = rawFramePts - masterClockAbs;
    qDebug() << "[FFmpeg][AVDiag] paced frame" << idx << "wallUs=" << avWallMicros()
             << "rawVideoPts=" << rawFramePts
             << "masterAudSec=" << masterClockAbs
             << "videoAlignedSec=" << videoClockAbs
             << "rawVideoPts_minus_masterAud=" << rawMinusMaster
             << "avOffsetSec=" << (std::isnan(avOffsetSec) ? -999.0 : avOffsetSec)
             << "diffPacing=" << diff
             << "processedMicros=" << proc
             << "bufBytes=" << bufBytes
             << "bytesFree=" << bytesFree
             << "queuedEstUs=" << m_lastQueuedAudioUSecs.load();
}

void FFmpegVideoPlayer::avDiagLogFirstVideoDecodeQueued(const char* pathTag)
{
    if (!ffmpegAvDiagEnabled())
        return;
    if (m_avDiagFirstVideoQueuedLogged.exchange(true, std::memory_order_acq_rel))
        return;
    qDebug() << "[FFmpeg][AVDiag] Decode thread queueing first frame to GUI path=" << pathTag
             << "wallUs=" << avWallMicros()
             << "wallDecSec=" << nowSeconds()
             << "m_curVideoStartUs=" << m_curVideoStartUs;
}

void FFmpegVideoPlayer::avDiagLogFirstVideoSink(qint64 startUs, qint64 endUs, const char* pathTag)
{
    if (!ffmpegAvDiagEnabled())
        return;
    if (m_avDiagFirstVideoSinkLogged.exchange(true, std::memory_order_acq_rel))
        return;
    qDebug() << "[FFmpeg][AVDiag] First QVideoSink::setVideoFrame path=" << pathTag
             << "wallUs=" << avWallMicros()
             << "wallNowSec=" << nowSeconds()
             << "startUs=" << startUs << "endUs=" << endUs
             << "startPtsSec=" << (startUs >= 0 ? double(startUs) / 1e6 : -1.0)
             << "audioBasePts=" << m_audioBasePts
             << "audioBaseWallTime=" << m_audioBaseWallTime
             << "firstAudioPts=" << m_firstAudioPts
             << "videoStartPts=" << m_startPts
             << "timingInit=" << m_timingInitialized;
}

void FFmpegVideoPlayer::reanchorAudioMasterIfCriticallyLowBytesFreeLocked(double framePtsSec,
                                                                           int bytesFreeAfterWrite)
{
    if (!m_audioSink || std::isnan(framePtsSec))
        return;
    const int bufSz = m_audioSink->bufferSize();
    if (bufSz < 16384 || bytesFreeAfterWrite < 0 || bytesFreeAfterWrite >= 16384)
        return;
    m_audioProcessedBaseUSecs = m_audioSink->processedUSecs();
    m_audioBaseWallTime = nowSeconds();
    if (ffmpegAvDiagEnabled()) {
        qDebug() << "[FFmpeg][AVDiag] AUDIOReset: low headroom bytesFree=" << bytesFreeAfterWrite
                 << "bufSz=" << bufSz << "baseUSecs=" << m_audioProcessedBaseUSecs;
    }
}
