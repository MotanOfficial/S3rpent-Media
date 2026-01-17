#include "ffmpegsubtitleextractor.h"
#include <QDebug>
#include <QFileInfo>
#include <QRegularExpression>
#include <QDateTime>

#ifdef HAS_FFMPEG_LIBS
// FFmpeg headers
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
    
    // Open input file with minimal probing (faster for large files!)
    AVDictionary *opts = nullptr;
    av_dict_set(&opts, "probesize", "32768", 0);  // Minimal probe size
    av_dict_set(&opts, "analyzeduration", "0", 0); // Don't analyze duration (we already know stream index)
    
    int ret = avformat_open_input(&m_formatContext, path, nullptr, &opts);
    av_dict_free(&opts);
    
    if (ret < 0) {
        char errbuf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(ret, errbuf, AV_ERROR_MAX_STRING_SIZE);
        qWarning() << "[FFmpegSubtitleExtractor] Failed to open file:" << filePath << "Error:" << errbuf;
        return false;
    }
    
    // Read minimal stream information (faster - we already know the stream index from ffprobe)
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
    // Close codec contexts
    for (auto it = m_codecContexts.begin(); it != m_codecContexts.end(); ++it) {
        avcodec_free_context(&it.value());
    }
    m_codecContexts.clear();
    
    // Close format context
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
    
    // Find subtitle stream by absolute index
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
    
    // Convert PTS to milliseconds
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
            // Extract text from ASS format (remove style tags)
            // ASS format: "Dialogue: Marked, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"
            // OR just: "Marked, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"
            // The text field (10th field, index 9) can contain commas, so we can't use lastIndexOf!
            
            // Remove "Dialogue:" prefix if present
            QString dialogueLine = assText.trimmed();
            if (dialogueLine.startsWith("Dialogue:")) {
                dialogueLine = dialogueLine.mid(9).trimmed(); // Remove "Dialogue:" (9 chars)
            }
            
            // Split by comma - ASS format has exactly 10 fields (or 9 if Effect is missing)
            // IMPORTANT: The text field can contain commas, so we can't just split and take last!
            // Format: "Marked, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"
            // OR: "Marked, Start, End, Style, Name, MarginL, MarginR, MarginV, Text" (9 fields, no Effect)
            // FFmpeg typically outputs 9 fields (no Effect field)
            
            // The key insight: we need to find the Nth comma where N is the number of fields before text
            // For 9-field format: find 8th comma (fields 0-7, then text at field 8)
            // For 10-field format: find 9th comma (fields 0-8, then text at field 9)
            // We can't rely on total comma count because text itself may contain commas!
            
            QString dialogueText;
            
            // Try 9-field format first (most common from FFmpeg)
            // Find the 8th comma and take everything after it
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
                // Successfully found 8th comma - this is 9-field format
                dialogueText = dialogueLine.mid(commaPos + 1).trimmed();
            } else {
                // Try 10-field format (with Effect field)
                // Find the 9th comma and take everything after it
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
                    // Successfully found 9th comma - this is 10-field format
                    dialogueText = dialogueLine.mid(commaPos + 1).trimmed();
                } else {
                    // Fallback: try to extract from last field (won't work if text has commas, but better than nothing)
                    QStringList parts = dialogueLine.split(',');
                    if (parts.size() > 0) {
                        dialogueText = parts.last().trimmed();
                    }
                }
            }
            
            if (dialogueText.isEmpty()) {
                // Last resort: use as-is
                dialogueText = assText;
            }
            
            // Remove ASS style tags like {\an8}, {\b1}, etc.
            dialogueText.remove(QRegularExpression(R"(\{[^}]*\})"));
            // Convert ASS newline codes to actual newlines
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
    
    // Get codec
    const AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
    if (!codec) {
        qWarning() << "[FFmpegSubtitleExtractor] Codec not found for stream" << streamIndex;
        return false;
    }
    
    // Allocate codec context
    AVCodecContext *codecContext = avcodec_alloc_context3(codec);
    if (!codecContext) {
        qWarning() << "[FFmpegSubtitleExtractor] Failed to allocate codec context";
        return false;
    }
    
    // Copy codec parameters
    int ret = avcodec_parameters_to_context(codecContext, stream->codecpar);
    if (ret < 0) {
        avcodec_free_context(&codecContext);
        return false;
    }
    
    // Open codec
    ret = avcodec_open2(codecContext, codec, nullptr);
    if (ret < 0) {
        avcodec_free_context(&codecContext);
        return false;
    }
    
    m_codecContexts[streamIndex] = codecContext;
    
    // Allocate packet and subtitle
    AVPacket *packet = av_packet_alloc();
    AVSubtitle *subtitle = new AVSubtitle();
    
    int packetCount = 0;
    int subtitleCount = 0;
    int totalPacketsRead = 0;
    qint64 startTime = QDateTime::currentMSecsSinceEpoch();
    
    // Read packets - only read packets from the subtitle stream
    while (av_read_frame(m_formatContext, packet) >= 0) {
        totalPacketsRead++;
        
        // Progress reporting every 10000 packets
        if (totalPacketsRead % 10000 == 0) {
            qint64 elapsed = QDateTime::currentMSecsSinceEpoch() - startTime;
            qDebug() << "[FFmpegSubtitleExtractor] Progress: Read" << totalPacketsRead << "packets, found" << subtitleCount << "subtitles (" << elapsed << "ms elapsed)";
        }
        
        if (packet->stream_index == streamIndex) {
            packetCount++;
            int got_subtitle = 0;
            
            // Decode subtitle packet
            ret = avcodec_decode_subtitle2(codecContext, subtitle, &got_subtitle, packet);
            if (ret < 0) {
                av_packet_unref(packet);
                continue;
            }
            
            if (got_subtitle) {
                subtitleCount++;
                SubtitleEntry entry;
                
                // For subtitles, use packet PTS as base time (more reliable than subtitle->pts)
                // subtitle->pts might be AV_NOPTS_VALUE, so use packet->pts instead
                int64_t basePts = (packet->pts != AV_NOPTS_VALUE) ? packet->pts : 
                                  ((subtitle->pts != AV_NOPTS_VALUE) ? subtitle->pts : AV_NOPTS_VALUE);
                
                if (basePts != AV_NOPTS_VALUE) {
                    // Convert base PTS to milliseconds using stream time_base
                    entry.startTime = timestampToMs(basePts, &stream->time_base);
                    
                    // start_display_time and end_display_time are in milliseconds (not AV_TIME_BASE units!)
                    // They are relative to the PTS
                    if (subtitle->start_display_time != AV_NOPTS_VALUE && subtitle->start_display_time > 0) {
                        entry.startTime += subtitle->start_display_time;
                    }
                    
                    // Calculate end time: start + duration
                    entry.endTime = entry.startTime;
                    if (subtitle->end_display_time != AV_NOPTS_VALUE && subtitle->end_display_time > 0) {
                        entry.endTime += subtitle->end_display_time;
                    } else {
                        // Default duration if not specified (3 seconds)
                        entry.endTime = entry.startTime + 3000;
                    }
                } else {
                    // Fallback: use packet DTS if PTS is not available
                    if (packet->dts != AV_NOPTS_VALUE) {
                        entry.startTime = timestampToMs(packet->dts, &stream->time_base);
                        entry.endTime = entry.startTime + 3000; // Default 3 second duration
                    } else {
                        // No valid timestamp - skip this entry
                        qWarning() << "[FFmpegSubtitleExtractor] Skipping subtitle with no valid timestamp";
                        avsubtitle_free(subtitle);
                        av_packet_unref(packet);
                        continue;
                    }
                }
                
                // Debug: log first few entries to verify timestamps
                if (subtitleCount <= 3) {
                    qDebug() << "[FFmpegSubtitleExtractor] Subtitle" << subtitleCount << ":" << entry.startTime << "-" << entry.endTime << "ms:" << entry.text.left(30);
                }
                
                // Convert subtitle to text
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
    qDebug() << "[FFmpegSubtitleExtractor] ✅ Extraction complete: Read" << totalPacketsRead << "total packets," << packetCount << "subtitle packets, decoded" << subtitleCount << "subtitles in" << elapsed << "ms";
    
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
    
    // Find the subtitle stream
    int subtitleStreamIndex = findSubtitleStream(streamIndex);
    if (subtitleStreamIndex < 0) {
        qWarning() << "[FFmpegSubtitleExtractor] Subtitle stream" << streamIndex << "not found";
        closeFile();
        return false;
    }
    
    // Use container index to seek directly to subtitle packets (FAST!)
    // This is the key difference from CLI - we can seek directly!
    AVStream *stream = m_formatContext->streams[subtitleStreamIndex];
    if (stream && stream->duration > 0) {
        // Seek to beginning of subtitle stream
        int64_t seekPos = av_rescale_q(0, AVRational{1, AV_TIME_BASE}, stream->time_base);
        int ret = av_seek_frame(m_formatContext, subtitleStreamIndex, seekPos, AVSEEK_FLAG_BACKWARD);
        if (ret < 0) {
            qWarning() << "[FFmpegSubtitleExtractor] Failed to seek to subtitle stream start";
        }
    }
    
    // Read all subtitle packets
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
    
    // Find the subtitle stream
    int subtitleStreamIndex = findSubtitleStream(streamIndex);
    if (subtitleStreamIndex < 0) {
        qWarning() << "[FFmpegSubtitleExtractor] Subtitle stream" << streamIndex << "not found";
        closeFile();
        return false;
    }
    
    // Use container index to seek directly to subtitle packets (FAST!)
    AVStream *stream = m_formatContext->streams[subtitleStreamIndex];
    if (stream && stream->duration > 0) {
        // Seek to beginning of subtitle stream
        int64_t seekPos = av_rescale_q(0, AVRational{1, AV_TIME_BASE}, stream->time_base);
        int ret = av_seek_frame(m_formatContext, subtitleStreamIndex, seekPos, AVSEEK_FLAG_BACKWARD);
        if (ret < 0) {
            qWarning() << "[FFmpegSubtitleExtractor] Failed to seek to subtitle stream start";
        }
    }
    
    // Read packets and call callback for each subtitle as it's found
    if (!m_formatContext || !m_fileOpen) {
        closeFile();
        return false;
    }
    
    if (!stream) {
        closeFile();
        return false;
    }
    
    // Get codec
    const AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
    if (!codec) {
        qWarning() << "[FFmpegSubtitleExtractor] Codec not found for stream" << subtitleStreamIndex;
        closeFile();
        return false;
    }
    
    // Allocate codec context
    AVCodecContext *codecContext = avcodec_alloc_context3(codec);
    if (!codecContext) {
        qWarning() << "[FFmpegSubtitleExtractor] Failed to allocate codec context";
        closeFile();
        return false;
    }
    
    // Copy codec parameters
    int ret = avcodec_parameters_to_context(codecContext, stream->codecpar);
    if (ret < 0) {
        avcodec_free_context(&codecContext);
        closeFile();
        return false;
    }
    
    // Open codec
    ret = avcodec_open2(codecContext, codec, nullptr);
    if (ret < 0) {
        avcodec_free_context(&codecContext);
        closeFile();
        return false;
    }
    
    // Allocate packet and subtitle
    AVPacket *packet = av_packet_alloc();
    AVSubtitle *subtitle = new AVSubtitle();
    
    int subtitleCount = 0;
    
    // Read packets and emit each subtitle immediately via callback
    while (av_read_frame(m_formatContext, packet) >= 0) {
        if (packet->stream_index == subtitleStreamIndex) {
            int got_subtitle = 0;
            
            // Decode subtitle packet
            ret = avcodec_decode_subtitle2(codecContext, subtitle, &got_subtitle, packet);
            if (ret < 0) {
                av_packet_unref(packet);
                continue;
            }
            
            if (got_subtitle) {
                subtitleCount++;
                SubtitleEntry entry;
                
                // For subtitles, use packet PTS as base time
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
                
                // Convert subtitle to text
                entry.text = subtitlePacketToText(subtitle);
                
                if (!entry.text.isEmpty()) {
                    // Call callback immediately with this subtitle
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
    
    qDebug() << "[FFmpegSubtitleExtractor] ✅ Incremental extraction complete: emitted" << subtitleCount << "subtitles";
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

