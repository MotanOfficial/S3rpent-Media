#ifndef COLORUTILS_H
#define COLORUTILS_H

#include <QObject>
#include <QColor>
#include <QUrl>
#include <QVariantMap>

class ColorUtils : public QObject
{
    Q_OBJECT
public:
    explicit ColorUtils(QObject *parent = nullptr);

    Q_INVOKABLE QColor dominantColor(const QUrl &sourceUrl) const;
    Q_INVOKABLE QUrl extractCoverArt(const QUrl &audioUrl) const;
    Q_INVOKABLE QUrl saveCoverArtImage(const QVariant &imageVariant) const;
    Q_INVOKABLE QVariantMap getAudioFormatInfo(const QUrl &audioUrl, qint64 durationMs) const;
    Q_INVOKABLE QUrl fixVideoFile(const QUrl &videoUrl) const;
    Q_INVOKABLE bool isFFmpegAvailable() const;
    Q_INVOKABLE QString readTextFile(const QUrl &fileUrl) const;
};

#endif // COLORUTILS_H

