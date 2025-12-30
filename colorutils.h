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
    Q_INVOKABLE QVariantList extractPaletteColors(const QUrl &sourceUrl, int count = 5) const;
    Q_INVOKABLE QVariantList createGradientStops(const QVariantList &colors) const;
    Q_INVOKABLE QUrl extractCoverArt(const QUrl &audioUrl) const;
    Q_INVOKABLE QUrl saveCoverArtImage(const QVariant &imageVariant) const;
    Q_INVOKABLE QVariantMap getAudioFormatInfo(const QUrl &audioUrl, qint64 durationMs) const;
    Q_INVOKABLE qint64 getAudioDuration(const QUrl &audioUrl) const;
    Q_INVOKABLE QUrl fixVideoFile(const QUrl &videoUrl) const;
    Q_INVOKABLE bool isFFmpegAvailable() const;
    Q_INVOKABLE QString readTextFile(const QUrl &fileUrl) const;
    Q_INVOKABLE bool writeTextFile(const QUrl &fileUrl, const QString &content) const;
    Q_INVOKABLE QVariantList getImagesInDirectory(const QUrl &fileUrl) const;
    
    // File association functions
    Q_INVOKABLE bool registerAsDefaultImageViewer() const;
    Q_INVOKABLE void openDefaultAppsSettings() const;
    Q_INVOKABLE QString getAppPath() const;  // Returns executable file path
    Q_INVOKABLE QString getAppDirectory() const;  // Returns directory containing executable
    
    // Memory management
    Q_INVOKABLE void clearImageCache() const;
    Q_INVOKABLE qreal getMemoryUsage() const;
    
    // Clipboard
    Q_INVOKABLE void copyToClipboard(const QString &text) const;
    
    // Bad Apple frame loading
    Q_INVOKABLE bool loadBadAppleFrames(const QUrl &binaryFileUrl) const;
    Q_INVOKABLE QUrl createBadAppleTexture() const;  // Creates texture image and returns URL
    Q_INVOKABLE int getBadAppleFrameCount() const;
    Q_INVOKABLE bool isBadAppleFramesLoaded() const;
};

#endif // COLORUTILS_H

