#ifndef FFMPEGVIDEOPLAYER_P_H
#define FFMPEGVIDEOPLAYER_P_H

#include <QtGlobal>
#include <QCoreApplication>

extern "C" {
#include <libavutil/time.h>
}

namespace FfVp {

inline double nowSeconds()
{
    return av_gettime_relative() / 1000000.0;
}

inline bool ffmpegAvDiagEnabled()
{
    static const bool s = qEnvironmentVariableIsSet("S3_FFMPEG_AV_DIAG");
    return s;
}

inline qint64 avWallMicros()
{
    return qint64(av_gettime_relative());
}

} // namespace FfVp

#endif
