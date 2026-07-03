#include "ffmpegsubtitleextractor.h"
#include <QDebug>
#include <QFileInfo>
#include <QRegularExpression>
#include <QDateTime>

#ifdef HAS_FFMPEG_LIBS
extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libavutil/time.h>
#include <libavutil/opt.h>
}
#endif

FFmpegSubtitleExtractor::FFmpegSubtitleExtractor(QObject *parent)
    : QObject(parent)
#ifdef HAS_FFMPEG_LIBS
    , m_formatContext(nullptr)
#endif
    , m_fileOpen(false)
{
}

FFmpegSubtitleExtractor::~FFmpegSubtitleExtractor()
{
#ifdef HAS_FFMPEG_LIBS
    closeFile();
#endif
}

bool FFmpegSubtitleExtractor::isAvailable()
{
#ifdef HAS_FFMPEG_LIBS
    return true;
#else
    return false;
#endif
}

#ifdef HAS_FFMPEG_LIBS

bool FFmpegSubtitleExtractor::openFile(const QString &filePath)
{
    if (m_fileOpen) {
        closeFile();
    }
    
    QByteArray pathBytes = filePath.toUtf8();
    const char *path = pathBytes.constData();
    
    AVDictionary *opts = nullptr;
    av_dict_set(&opts, "probesize", "32768", 0);
    av_dict_set(&opts, "analyzeduration", "0", 0);
    
    int ret = avformat_open_input(&m_formatContext, path, nullptr, &opts);
    av_dict_free(&opts);
    
    if (ret < 0) {
        char errbuf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(ret, errbuf, AV_ERROR_MAX_STRING_SIZE);
        qWarning() << "[FFmpegSubtitleExtractor] Failed to open file:" << filePath << "Error:" << errbuf;
        return false;
    }
    
    ret = avformat_find_stream_info(m_formatContext, nullptr);
    if (ret < 0) {
        qWarning() << "[FFmpegSubtitleExtractor] Failed to find stream info";
        closeFile();
        return false;
    }
    
    m_fileOpen = true;
    return true;
}

void FFmpegSubtitleExtractor::closeFile()
{
    for (auto it = m_codecContexts.begin(); it != m_codecContexts.end(); ++it) {
        avcodec_free_context(&it.value());
    }
    m_codecContexts.clear();
    
    if (m_formatContext) {
        avformat_close_input(&m_formatContext);
        m_formatContext = nullptr;
    }
    
    m_fileOpen = false;
}

int FFmpegSubtitleExtractor::findSubtitleStream(int streamIndex)
{
    if (!m_formatContext || !m_fileOpen) {
        return -1;
    }
    
    for (unsigned int i = 0; i < m_formatContext->nb_streams; i++) {
        if (m_formatContext->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_SUBTITLE) {
            if (static_cast<int>(i) == streamIndex) {
                return static_cast<int>(i);
            }
        }
    }
    
    return -1;
}

qint64 FFmpegSubtitleExtractor::timestampToMs(int64_t pts, const void *timeBasePtr) const
{
    const AVRational *timeBase = static_cast<const AVRational*>(timeBasePtr);
    if (!timeBase || timeBase->num == 0 || timeBase->den == 0) {
        return 0;
    }
    
    int64_t seconds = pts * timeBase->num / timeBase->den;
    int64_t ms = (seconds * 1000) + ((pts * timeBase->num * 1000) / timeBase->den - seconds * 1000);
    return ms;
}

#endif // HAS_FFMPEG_LIBS

QString FFmpegSubtitleExtractor::subtitlePacketToText(const void *subPtr) const
{
#ifdef HAS_FFMPEG_LIBS
    const AVSubtitle *sub = static_cast<const AVSubtitle*>(subPtr);
    QString text;
    
    for (unsigned int i = 0; i < sub->num_rects; i++) {
        AVSubtitleRect *rect = sub->rects[i];
        if (rect->type == SUBTITLE_TEXT) {
            if (!text.isEmpty()) {
                text += "\n";
            }
            text += QString::fromUtf8(rect->text);
        } else if (rect->type == SUBTITLE_ASS) {
            if (!text.isEmpty()) {
                text += "\n";
            }
            QString assText = QString::fromUtf8(rect->ass);
            QString dialogueLine = assText.trimmed();
            if (dialogueLine.startsWith("Dialogue:")) {
                dialogueLine = dialogueLine.mid(9).trimmed();
            }
            
            QString dialogueText;
            
            int commaPos = -1;
            bool found8thComma = false;
            for (int i = 0; i < 8; i++) {
                commaPos = dialogueLine.indexOf(',', commaPos + 1);
                if (commaPos == -1) {
                    found8thComma = false;
                    break;
                }
                if (i == 7) {
                    found8thComma = true;
                }
            }
            
            if (found8thComma && commaPos >= 0 && commaPos < dialogueLine.length() - 1) {
                dialogueText = dialogueLine.mid(commaPos + 1).trimmed();
            } else {
                commaPos = -1;
                bool found9thComma = false;
                for (int i = 0; i < 9; i++) {
                    commaPos = dialogueLine.indexOf(',', commaPos + 1);
                    if (commaPos == -1) {
                        found9thComma = false;
                        break;
                    }
                    if (i == 8) {
                        found9thComma = true;
                    }
                }
                
                if (found9thComma && commaPos >= 0 && commaPos < dialogueLine.length() - 1) {
                    dialogueText = dialogueLine.mid(commaPos + 1).trimmed();
                } else {
                    QStringList parts = dialogueLine.split(',');
                    if (parts.size() > 0) {
                        dialogueText = parts.last().trimmed();
                    }
                }
            }
            
            if (dialogueText.isEmpty()) {
                dialogueText = assText;
            }
            
            dialogueText.remove(QRegularExpression(R"(\{[^}]*\})"));
            dialogueText.replace("\\N", "\n");
            dialogueText.replace("\\n", "\n");
            text += dialogueText;
        }
    }
    
    return text;
#else
    Q_UNUSED(subPtr)
    return QString();
#endif
}

#ifdef HAS_FFMPEG_LIBS

bool FFmpegSubtitleExtractor::readSubtitlePackets(int streamIndex, QList<SubtitleEntry> &entries)
{
    if (!m_formatContext || !m_fileOpen) {
        return false;
    }
    
    AVStream *stream = m_formatContext->streams[streamIndex];
    if (!stream) {
        return false;
    }
    
    const AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
    if (!codec) {
        qWarning() << "[FFmpegSubtitleExtractor] Codec not found for stream" << streamIndex;
        return false;
    }
    
    AVCodecContext *codecContext = avcodec_alloc_context3(codec);
    if (!codecContext) {
        qWarning() << "[FFmpegSubtitleExtractor] Failed to allocate codec context";
        return false;
    }
    
    int ret = avcodec_parameters_to_context(codecContext, stream->codecpar);
    if (ret < 0) {
        avcodec_free_context(&codecContext);
        return false;
    }
    
    ret = avcodec_open2(codecContext, codec, nullptr);
    if (ret < 0) {
        avcodec_free_context(&codecContext);
        return false;
    }
    
    m_codecContexts[streamIndex] = codecContext;
    
    AVPacket *packet = av_packet_alloc();
    AVSubtitle *subtitle = new AVSubtitle();
    
    int packetCount = 0;
    int subtitleCount = 0;
    int totalPacketsRead = 0;
    qint64 startTime = QDateTime::currentMSecsSinceEpoch();
    
    while (av_read_frame(m_formatContext, packet) >= 0) {
        totalPacketsRead++;
        
        if (totalPacketsRead % 10000 == 0) {
            qint64 elapsed = QDateTime::currentMSecsSinceEpoch() - startTime;
            qDebug() << "[FFmpegSubtitleExtractor] Progress: Read" << totalPacketsRead << "packets, found" << subtitleCount << "subtitles (" << elapsed << "ms elapsed)";
        }
        
        if (packet->stream_index == streamIndex) {
            packetCount++;
            int got_subtitle = 0;
            
            ret = avcodec_decode_subtitle2(codecContext, subtitle, &got_subtitle, packet);
            if (ret < 0) {
                av_packet_unref(packet);
                continue;
            }
            
            if (got_subtitle) {
                subtitleCount++;
                SubtitleEntry entry;
                
                int64_t basePts = (packet->pts != AV_NOPTS_VALUE) ? packet->pts : 
                                  ((subtitle->pts != AV_NOPTS_VALUE) ? subtitle->pts : AV_NOPTS_VALUE);
                
                if (basePts != AV_NOPTS_VALUE) {
                    entry.startTime = timestampToMs(basePts, &stream->time_base);
                    
                    if (subtitle->start_display_time != AV_NOPTS_VALUE && subtitle->start_display_time > 0) {
                        entry.startTime += subtitle->start_display_time;
                    }
                    
                    entry.endTime = entry.startTime;
                    if (subtitle->end_display_time != AV_NOPTS_VALUE && subtitle->end_display_time > 0) {
                        entry.endTime += subtitle->end_display_time;
                    } else {
                        entry.endTime = entry.startTime + 3000;
                    }
                } else {
                    if (packet->dts != AV_NOPTS_VALUE) {
                        entry.startTime = timestampToMs(packet->dts, &stream->time_base);
                        entry.endTime = entry.startTime + 3000;
                    } else {
                        qWarning() << "[FFmpegSubtitleExtractor] Skipping subtitle with no valid timestamp";
                        avsubtitle_free(subtitle);
                        av_packet_unref(packet);
                        continue;
                    }
                }
                
                if (subtitleCount <= 3) {
                    qDebug() << "[FFmpegSubtitleExtractor] Subtitle" << subtitleCount << ":" << entry.startTime << "-" << entry.endTime << "ms:" << entry.text.left(30);
                }
                
                entry.text = subtitlePacketToText(subtitle);
                
                if (!entry.text.isEmpty()) {
                    entries.append(entry);
                }
                
                avsubtitle_free(subtitle);
            }
        }
        
        av_packet_unref(packet);
    }
    
    qint64 elapsed = QDateTime::currentMSecsSinceEpoch() - startTime;
    qDebug() << "[FFmpegSubtitleExtractor] Extraction complete: Read" << totalPacketsRead << "total packets," << packetCount << "subtitle packets, decoded" << subtitleCount << "subtitles in" << elapsed << "ms";
    
    av_packet_free(&packet);
    delete subtitle;
    
    return true;
}

#endif // HAS_FFMPEG_LIBS

bool FFmpegSubtitleExtractor::extractSubtitles(const QString &filePath, int streamIndex, QList<SubtitleEntry> &entries)
{
#ifdef HAS_FFMPEG_LIBS
    entries.clear();
    
    if (!openFile(filePath)) {
        return false;
    }
    
    int subtitleStreamIndex = findSubtitleStream(streamIndex);
    if (subtitleStreamIndex < 0) {
        qWarning() << "[FFmpegSubtitleExtractor] Subtitle stream" << streamIndex << "not found";
        closeFile();
        return false;
    }
    
    AVStream *stream = m_formatContext->streams[subtitleStreamIndex];
    if (stream && stream->duration > 0) {
        int64_t seekPos = av_rescale_q(0, AVRational{1, AV_TIME_BASE}, stream->time_base);
        int ret = av_seek_frame(m_formatContext, subtitleStreamIndex, seekPos, AVSEEK_FLAG_BACKWARD);
        if (ret < 0) {
            qWarning() << "[FFmpegSubtitleExtractor] Failed to seek to subtitle stream start";
        }
    }
    
    bool success = readSubtitlePackets(subtitleStreamIndex, entries);
    
    closeFile();
    
    if (success) {
        qDebug() << "[FFmpegSubtitleExtractor] Extracted" << entries.size() << "subtitle entries from stream" << streamIndex;
    }
    
    return success;
#else
    // FFmpeg libraries not available - return empty
    Q_UNUSED(filePath)
    Q_UNUSED(streamIndex)
    Q_UNUSED(entries)
    return false;
#endif
}

bool FFmpegSubtitleExtractor::extractSubtitlesIncremental(const QString &filePath, int streamIndex, SubtitleCallback callback)
{
#ifdef HAS_FFMPEG_LIBS
    if (!openFile(filePath)) {
        return false;
    }
    
    int subtitleStreamIndex = findSubtitleStream(streamIndex);
    if (subtitleStreamIndex < 0) {
        qWarning() << "[FFmpegSubtitleExtractor] Subtitle stream" << streamIndex << "not found";
        closeFile();
        return false;
    }
    
    AVStream *stream = m_formatContext->streams[subtitleStreamIndex];
    if (stream && stream->duration > 0) {
        int64_t seekPos = av_rescale_q(0, AVRational{1, AV_TIME_BASE}, stream->time_base);
        int ret = av_seek_frame(m_formatContext, subtitleStreamIndex, seekPos, AVSEEK_FLAG_BACKWARD);
        if (ret < 0) {
            qWarning() << "[FFmpegSubtitleExtractor] Failed to seek to subtitle stream start";
        }
    }
    
    if (!m_formatContext || !m_fileOpen) {
        closeFile();
        return false;
    }
    
    if (!stream) {
        closeFile();
        return false;
    }
    
    const AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
    if (!codec) {
        qWarning() << "[FFmpegSubtitleExtractor] Codec not found for stream" << subtitleStreamIndex;
        closeFile();
        return false;
    }
    
    AVCodecContext *codecContext = avcodec_alloc_context3(codec);
    if (!codecContext) {
        qWarning() << "[FFmpegSubtitleExtractor] Failed to allocate codec context";
        closeFile();
        return false;
    }
    
    int ret = avcodec_parameters_to_context(codecContext, stream->codecpar);
    if (ret < 0) {
        avcodec_free_context(&codecContext);
        closeFile();
        return false;
    }
    
    ret = avcodec_open2(codecContext, codec, nullptr);
    if (ret < 0) {
        avcodec_free_context(&codecContext);
        closeFile();
        return false;
    }
    
    AVPacket *packet = av_packet_alloc();
    AVSubtitle *subtitle = new AVSubtitle();
    
    int subtitleCount = 0;
    
    while (av_read_frame(m_formatContext, packet) >= 0) {
        if (packet->stream_index == subtitleStreamIndex) {
            int got_subtitle = 0;
            
            ret = avcodec_decode_subtitle2(codecContext, subtitle, &got_subtitle, packet);
            if (ret < 0) {
                av_packet_unref(packet);
                continue;
            }
            
            if (got_subtitle) {
                subtitleCount++;
                SubtitleEntry entry;
                
                int64_t basePts = (packet->pts != AV_NOPTS_VALUE) ? packet->pts : 
                                  ((subtitle->pts != AV_NOPTS_VALUE) ? subtitle->pts : AV_NOPTS_VALUE);
                
                if (basePts != AV_NOPTS_VALUE) {
                    entry.startTime = timestampToMs(basePts, &stream->time_base);
                    
                    if (subtitle->start_display_time != AV_NOPTS_VALUE && subtitle->start_display_time > 0) {
                        entry.startTime += subtitle->start_display_time;
                    }
                    
                    entry.endTime = entry.startTime;
                    if (subtitle->end_display_time != AV_NOPTS_VALUE && subtitle->end_display_time > 0) {
                        entry.endTime += subtitle->end_display_time;
                    } else {
                        entry.endTime = entry.startTime + 3000;
                    }
                } else {
                    if (packet->dts != AV_NOPTS_VALUE) {
                        entry.startTime = timestampToMs(packet->dts, &stream->time_base);
                        entry.endTime = entry.startTime + 3000;
                    } else {
                        avsubtitle_free(subtitle);
                        av_packet_unref(packet);
                        continue;
                    }
                }
                
                entry.text = subtitlePacketToText(subtitle);
                
                if (!entry.text.isEmpty()) {
                    callback(entry);
                }
                
                avsubtitle_free(subtitle);
            }
        }
        
        av_packet_unref(packet);
    }
    
    av_packet_free(&packet);
    delete subtitle;
    avcodec_free_context(&codecContext);
    
    closeFile();
    
    qDebug() << "[FFmpegSubtitleExtractor] Incremental extraction complete: emitted" << subtitleCount << "subtitles";
    return true;
#else
    Q_UNUSED(filePath)
    Q_UNUSED(streamIndex)
    Q_UNUSED(callback)
    return false;
#endif
}

bool FFmpegSubtitleExtractor::extractSubtitleInfo(const QString &filePath, QList<QMap<QString, QVariant>> &tracks)
{
#ifdef HAS_FFMPEG_LIBS
    tracks.clear();
    
    if (!openFile(filePath)) {
        return false;
    }
    
    int trackIndex = 0;
    for (unsigned int i = 0; i < m_formatContext->nb_streams; i++) {
        AVStream *stream = m_formatContext->streams[i];
        if (stream->codecpar->codec_type == AVMEDIA_TYPE_SUBTITLE) {
            QMap<QString, QVariant> trackInfo;
            trackInfo["index"] = trackIndex;
            trackInfo["ffmpegIndex"] = static_cast<int>(i);
            
            // Get codec name
            const AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
            if (codec) {
                trackInfo["codec"] = QString(codec->name);
            } else {
                trackInfo["codec"] = "unknown";
            }
            
            // Get language if available
            AVDictionaryEntry *lang = av_dict_get(stream->metadata, "language", nullptr, 0);
            if (lang) {
                trackInfo["language"] = QString(lang->value);
            }
            
            tracks.append(trackInfo);
            trackIndex++;
        }
    }
    
    closeFile();
    
    qDebug() << "[FFmpegSubtitleExtractor] Found" << tracks.size() << "subtitle tracks";
    
    return true;
#else
    Q_UNUSED(filePath)
    Q_UNUSED(tracks)
    return false;
#endif
}

