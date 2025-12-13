#include "colorutils.h"

#include <QFileInfo>
#include <QFile>
#include <QTextStream>
#include <QStringConverter>
#include <QImage>
#include <QImageReader>
#include <QHash>
#include <QMediaMetaData>
#include <QMediaPlayer>
#include <QAudioOutput>
#include <QTemporaryFile>
#include <QDir>
#include <QEventLoop>
#include <QTimer>
#include <QAudioDecoder>
#include <QAudioBuffer>
#include <QDebug>
#include <algorithm>
#include <QtMath>
#include <QVector>
#include <QRandomGenerator>
#include <cmath>
#include <limits>
#include <QProcess>
#include <QDateTime>
#include <QStandardPaths>
#include <QSettings>
#include <QCoreApplication>
#include <QGuiApplication>
#include <QClipboard>
#include <QDesktopServices>
#include <QImageReader>
#include <QQmlEngine>
#include <QQuickImageProvider>
#include <QProcess>
#include <QStandardPaths>
#include <QLinearGradient>
#include <QGradient>
#include <QVariantMap>
#include <QtMath>
#ifdef Q_OS_WIN
#include <windows.h>
#include <psapi.h>
#endif

#ifdef Q_OS_WIN
#include <windows.h>
#include <shlobj.h>
#include <shellapi.h>
#endif

namespace {
constexpr int kSampleSize = 96;
constexpr auto kFallbackColor = "#060606";
}

ColorUtils::ColorUtils(QObject *parent)
    : QObject(parent)
{
}

QColor ColorUtils::dominantColor(const QUrl &sourceUrl) const
{
    const QString localPath = sourceUrl.isLocalFile()
            ? sourceUrl.toLocalFile()
            : sourceUrl.toString(QUrl::PreferLocalFile);

    if (localPath.isEmpty() || !QFileInfo::exists(localPath))
        return QColor(kFallbackColor);

    QImageReader reader(localPath);
    reader.setAutoTransform(true);
    
    // Downscale to ~50x50 for faster computation
    QSize size = reader.size();
    if (!size.isValid()) {
        size = QSize(50, 50);
    } else {
        size.scale(50, 50, Qt::KeepAspectRatio);
    }
    reader.setScaledSize(size);

    QImage image = reader.read();
    if (image.isNull())
        return QColor(kFallbackColor);

    image = image.convertToFormat(QImage::Format_RGBA8888);
    const int width = image.width();
    const int height = image.height();

    // Step 1: Collect RGB points (skip transparent pixels)
    struct RGBPoint {
        double r, g, b;
    };
    QVector<RGBPoint> points;
    points.reserve(width * height);

    for (int y = 0; y < height; ++y) {
        const uchar *line = image.constScanLine(y);
        for (int x = 0; x < width; ++x) {
            const uchar *pixel = line + x * 4;
            const uchar alpha = pixel[3];
            if (alpha < 128) // Skip semi-transparent pixels
                continue;

            RGBPoint pt;
            // Format_RGBA8888 stores pixels as R, G, B, A
            pt.r = pixel[0];
            pt.g = pixel[1];
            pt.b = pixel[2];
            points.append(pt);
        }
    }

    if (points.isEmpty())
        return QColor(kFallbackColor);

    // Step 2: K-Means clustering (k=5)
    const int k = 5;
    const int maxIterations = 20;
    
    struct Cluster {
        double r, g, b;
        int count;
    };
    
    QVector<Cluster> centroids(k);
    QVector<int> assignments(points.size());
    
    // Initialize centroids randomly from the points
    QRandomGenerator *rng = QRandomGenerator::global();
    for (int i = 0; i < k; ++i) {
        int idx = rng->bounded(points.size());
        centroids[i].r = points[idx].r;
        centroids[i].g = points[idx].g;
        centroids[i].b = points[idx].b;
        centroids[i].count = 0;
    }

    // K-Means iterations
    for (int iter = 0; iter < maxIterations; ++iter) {
        // Assign each point to nearest centroid
        for (int i = 0; i < points.size(); ++i) {
            double minDist = std::numeric_limits<double>::max();
            int bestCluster = 0;
            
            for (int j = 0; j < k; ++j) {
                double dr = points[i].r - centroids[j].r;
                double dg = points[i].g - centroids[j].g;
                double db = points[i].b - centroids[j].b;
                double dist = dr * dr + dg * dg + db * db;
                
                if (dist < minDist) {
                    minDist = dist;
                    bestCluster = j;
                }
            }
            assignments[i] = bestCluster;
        }

        // Update centroids
        QVector<Cluster> newCentroids(k);
        for (int j = 0; j < k; ++j) {
            newCentroids[j].r = 0;
            newCentroids[j].g = 0;
            newCentroids[j].b = 0;
            newCentroids[j].count = 0;
        }

        for (int i = 0; i < points.size(); ++i) {
            int cluster = assignments[i];
            newCentroids[cluster].r += points[i].r;
            newCentroids[cluster].g += points[i].g;
            newCentroids[cluster].b += points[i].b;
            newCentroids[cluster].count++;
        }

        // Check for convergence
        bool converged = true;
        for (int j = 0; j < k; ++j) {
            if (newCentroids[j].count > 0) {
                newCentroids[j].r /= newCentroids[j].count;
                newCentroids[j].g /= newCentroids[j].count;
                newCentroids[j].b /= newCentroids[j].count;
                
                // Check if centroid moved significantly
                double dr = newCentroids[j].r - centroids[j].r;
                double dg = newCentroids[j].g - centroids[j].g;
                double db = newCentroids[j].b - centroids[j].b;
                if (dr * dr + dg * dg + db * db > 1.0) {
                    converged = false;
                }
            }
            centroids[j] = newCentroids[j];
        }

        if (converged)
            break;
    }

    // Step 3: Pick the cluster with the most pixels, but skip very dark colors (black)
    int bestCluster = -1;
    int maxCount = 0;
    
    // First pass: find the largest non-black cluster
    for (int j = 0; j < k; ++j) {
        if (centroids[j].count > maxCount) {
            // Check if this cluster is not too dark (skip near-black colors)
            const int r = static_cast<int>(centroids[j].r);
            const int g = static_cast<int>(centroids[j].g);
            const int b = static_cast<int>(centroids[j].b);
            const int maxRGB = qMax(qMax(r, g), b);
            
            // Skip very dark colors (brightness < 30)
            if (maxRGB >= 30) {
                maxCount = centroids[j].count;
                bestCluster = j;
            }
        }
    }
    
    // If all clusters are too dark, pick the largest one anyway
    if (bestCluster == -1) {
        maxCount = 0;
        for (int j = 0; j < k; ++j) {
            if (centroids[j].count > maxCount) {
                maxCount = centroids[j].count;
                bestCluster = j;
            }
        }
    }

    if (bestCluster == -1 || maxCount == 0)
        return QColor(kFallbackColor);

    const Cluster &best = centroids[bestCluster];
    int r = qBound(0, static_cast<int>(best.r), 255);
    int g = qBound(0, static_cast<int>(best.g), 255);
    int b = qBound(0, static_cast<int>(best.b), 255);

    // Ensure the color isn't too dark or too light for good visibility
    const int maxRGB = qMax(qMax(r, g), b);
    const int minRGB = qMin(qMin(r, g), b);
    
    // If too dark, brighten it
    if (maxRGB < 50) {
        const double factor = 50.0 / maxRGB;
        r = qBound(0, static_cast<int>(r * factor), 255);
        g = qBound(0, static_cast<int>(g * factor), 255);
        b = qBound(0, static_cast<int>(b * factor), 255);
    }
    
    // If too light, darken it slightly
    if (minRGB > 240) {
        const double factor = 240.0 / minRGB;
        r = qBound(0, static_cast<int>(r * factor), 255);
        g = qBound(0, static_cast<int>(g * factor), 255);
        b = qBound(0, static_cast<int>(b * factor), 255);
    }

    return QColor(r, g, b);
}

QVariantList ColorUtils::extractPaletteColors(const QUrl &sourceUrl, int count) const
{
    QVariantList result;
    
    const QString localPath = sourceUrl.isLocalFile()
            ? sourceUrl.toLocalFile()
            : sourceUrl.toString(QUrl::PreferLocalFile);

    if (localPath.isEmpty() || !QFileInfo::exists(localPath))
        return result;

    QImageReader reader(localPath);
    reader.setAutoTransform(true);
    
    // Downscale to ~80x80 for faster computation (smaller = faster, still enough for color extraction)
    QSize size = reader.size();
    if (!size.isValid()) {
        size = QSize(80, 80);
    } else {
        size.scale(80, 80, Qt::KeepAspectRatio);
    }
    reader.setScaledSize(size);

    QImage image = reader.read();
    if (image.isNull())
        return result;

    image = image.convertToFormat(QImage::Format_RGBA8888);
    const int width = image.width();
    const int height = image.height();

    // Step 1: Collect RGB points (skip transparent pixels)
    struct RGBPoint {
        double r, g, b;
    };
    QVector<RGBPoint> points;
    points.reserve(width * height);

    for (int y = 0; y < height; ++y) {
        const uchar *line = image.constScanLine(y);
        for (int x = 0; x < width; ++x) {
            const uchar *pixel = line + x * 4;
            const uchar alpha = pixel[3];
            if (alpha < 128) // Skip semi-transparent pixels
                continue;

            RGBPoint pt;
            pt.r = pixel[0];
            pt.g = pixel[1];
            pt.b = pixel[2];
            points.append(pt);
        }
    }

    if (points.isEmpty())
        return result;

    // Step 2: K-Means clustering with specified count
    const int k = qBound(2, count, 10); // Limit between 2 and 10 colors
    const int maxIterations = 12; // Reduced from 20 for faster processing (still converges well)
    
    struct Cluster {
        double r, g, b;
        int count;
    };
    
    QVector<Cluster> centroids(k);
    QVector<int> assignments(points.size());
    
    // Initialize centroids using k-means++ for better diversity
    // First centroid: random point
    QRandomGenerator *rng = QRandomGenerator::global();
    int firstIdx = rng->bounded(points.size());
    centroids[0].r = points[firstIdx].r;
    centroids[0].g = points[firstIdx].g;
    centroids[0].b = points[firstIdx].b;
    centroids[0].count = 0;
    
    // Subsequent centroids: choose points far from existing centroids
    for (int i = 1; i < k; ++i) {
        QVector<double> distances(points.size());
        double sumDistSq = 0.0;
        
        for (int p = 0; p < points.size(); ++p) {
            double minDist = std::numeric_limits<double>::max();
            // Find minimum distance to any existing centroid
            for (int j = 0; j < i; ++j) {
                double dr = points[p].r - centroids[j].r;
                double dg = points[p].g - centroids[j].g;
                double db = points[p].b - centroids[j].b;
                double dist = dr * dr + dg * dg + db * db;
                if (dist < minDist) {
                    minDist = dist;
                }
            }
            distances[p] = minDist;
            sumDistSq += minDist;
        }
        
        // Choose point with probability proportional to distance squared
        double target = rng->bounded(sumDistSq);
        double cumsum = 0.0;
        int chosenIdx = 0;
        for (int p = 0; p < points.size(); ++p) {
            cumsum += distances[p];
            if (cumsum >= target) {
                chosenIdx = p;
                break;
            }
        }
        
        centroids[i].r = points[chosenIdx].r;
        centroids[i].g = points[chosenIdx].g;
        centroids[i].b = points[chosenIdx].b;
        centroids[i].count = 0;
    }

    // K-Means iterations
    for (int iter = 0; iter < maxIterations; ++iter) {
        // Assign each point to nearest centroid
        for (int i = 0; i < points.size(); ++i) {
            double minDist = std::numeric_limits<double>::max();
            int bestCluster = 0;
            
            for (int j = 0; j < k; ++j) {
                double dr = points[i].r - centroids[j].r;
                double dg = points[i].g - centroids[j].g;
                double db = points[i].b - centroids[j].b;
                double dist = dr * dr + dg * dg + db * db;
                
                if (dist < minDist) {
                    minDist = dist;
                    bestCluster = j;
                }
            }
            assignments[i] = bestCluster;
        }

        // Update centroids
        QVector<Cluster> newCentroids(k);
        for (int j = 0; j < k; ++j) {
            newCentroids[j].r = 0;
            newCentroids[j].g = 0;
            newCentroids[j].b = 0;
            newCentroids[j].count = 0;
        }

        for (int i = 0; i < points.size(); ++i) {
            int cluster = assignments[i];
            newCentroids[cluster].r += points[i].r;
            newCentroids[cluster].g += points[i].g;
            newCentroids[cluster].b += points[i].b;
            newCentroids[cluster].count++;
        }

        // Check for convergence
        bool converged = true;
        for (int j = 0; j < k; ++j) {
            if (newCentroids[j].count > 0) {
                newCentroids[j].r /= newCentroids[j].count;
                newCentroids[j].g /= newCentroids[j].count;
                newCentroids[j].b /= newCentroids[j].count;
                
                // Check if centroid moved significantly
                double dr = newCentroids[j].r - centroids[j].r;
                double dg = newCentroids[j].g - centroids[j].g;
                double db = newCentroids[j].b - centroids[j].b;
                if (dr * dr + dg * dg + db * db > 1.0) {
                    converged = false;
                }
            }
            centroids[j] = newCentroids[j];
        }

        if (converged)
            break;
    }

    // Step 3: Sort clusters by count (most common first) and filter out very dark and very light colors
    QVector<QPair<int, Cluster>> sortedClusters;
    for (int j = 0; j < k; ++j) {
        if (centroids[j].count > 0) {
            // Filter out very dark and very light colors
            const int r = static_cast<int>(centroids[j].r);
            const int g = static_cast<int>(centroids[j].g);
            const int b = static_cast<int>(centroids[j].b);
            const int maxRGB = qMax(qMax(r, g), b);
            const int minRGB = qMin(qMin(r, g), b);
            
            // Only include colors that aren't too dark (brightness >= 60) and aren't too light/white (brightness < 240)
            if (maxRGB >= 60 && maxRGB < 240) {
                // Also check saturation - exclude very desaturated colors (grays/whites)
                const int saturation = maxRGB > 0 ? ((maxRGB - minRGB) * 100 / maxRGB) : 0;
                if (saturation >= 10) {  // At least 10% saturation to avoid grays
                    sortedClusters.append(qMakePair(centroids[j].count, centroids[j]));
                }
            }
        }
    }
    
    // Sort by count (descending)
    std::sort(sortedClusters.begin(), sortedClusters.end(),
              [](const QPair<int, Cluster> &a, const QPair<int, Cluster> &b) {
                  return a.first > b.first;
              });
    
    // Convert to QColor list, ensuring colors aren't too dark or too light
    for (const auto &pair : sortedClusters) {
        const Cluster &cluster = pair.second;
        int r = qBound(0, static_cast<int>(cluster.r), 255);
        int g = qBound(0, static_cast<int>(cluster.g), 255);
        int b = qBound(0, static_cast<int>(cluster.b), 255);
        
        // Ensure the color isn't too dark or too light for good visibility
        const int maxRGB = qMax(qMax(r, g), b);
        const int minRGB = qMin(qMin(r, g), b);
        
        // If too dark, brighten it (minimum brightness of 80 for gradient colors)
        if (maxRGB < 80) {
            const double factor = 80.0 / qMax(maxRGB, 1);
            r = qBound(0, static_cast<int>(r * factor), 255);
            g = qBound(0, static_cast<int>(g * factor), 255);
            b = qBound(0, static_cast<int>(b * factor), 255);
        }
        
        // If too light, darken it slightly
        if (minRGB > 240) {
            const double factor = 240.0 / minRGB;
            r = qBound(0, static_cast<int>(r * factor), 255);
            g = qBound(0, static_cast<int>(g * factor), 255);
            b = qBound(0, static_cast<int>(b * factor), 255);
        }
        
        result.append(QColor(r, g, b));
    }
    
    // Post-process: Ensure colors are diverse (not too similar)
    // If colors are too close, adjust them to be more distinct
    if (result.size() >= 2) {
        const double minColorDistance = 40.0 * 40.0; // Minimum squared distance between colors
        
        for (int i = 1; i < result.size(); ++i) {
            QColor current = result[i].value<QColor>();
            
            // Check distance to all previous colors
            for (int j = 0; j < i; ++j) {
                QColor prev = result[j].value<QColor>();
                double dr = current.red() - prev.red();
                double dg = current.green() - prev.green();
                double db = current.blue() - prev.blue();
                double distSq = dr * dr + dg * dg + db * db;
                
                if (distSq < minColorDistance) {
                    // Shift this color away from the previous one
                    // Move in a random direction in color space
                    double angle = rng->bounded(360.0) * M_PI / 180.0;
                    double shift = sqrt(minColorDistance) - sqrt(distSq);
                    
                    int newR = qBound(0, static_cast<int>(current.red() + shift * cos(angle)), 255);
                    int newG = qBound(0, static_cast<int>(current.green() + shift * sin(angle)), 255);
                    int newB = qBound(0, static_cast<int>(current.blue() + shift * cos(angle + M_PI/3)), 255);
                    
                    current = QColor(newR, newG, newB);
                    result[i] = current;  // Update the QVariantList
                    break;
                }
            }
        }
    }
    
    // If we have fewer colors than requested, pad with diverse variations
    while (result.size() < count && result.size() > 0) {
        QColor last = result.last().value<QColor>();
        // Create a variation with hue shift
        QColor variation = last.toHsl();
        int h = (variation.hue() + 30) % 360;
        variation.setHsl(h, qBound(0, variation.saturation() + 20, 255), 
                        qBound(0, variation.lightness() + (rng->bounded(2) ? 20 : -20), 255));
        result.append(variation.toRgb());
    }
    
    return result;
}

QVariantList ColorUtils::createGradientStops(const QVariantList &colors) const
{
    QVariantList stops;
    
    if (colors.isEmpty()) {
        return stops;
    }
    
    int numColors = colors.size();
    if (numColors == 0) {
        return stops;
    }
    
    // Create gradient stops from colors
    // Start with transparency
    QVariantMap startStop;
    startStop["position"] = 0.0;
    startStop["color"] = QColor(255, 255, 255, 0);
    stops.append(startStop);
    
    // Add each color as a stop, evenly distributed
    for (int i = 0; i < numColors; i++) {
        QVariant colorVar = colors[i];
        if (!colorVar.isValid()) {
            continue;
        }
        
        QColor color = colorVar.value<QColor>();
        if (!color.isValid()) {
            continue;
        }
        
        // Position from 0.1 to 0.9
        qreal position = 0.1 + (i / qMax(1.0, (numColors - 1.0))) * 0.8;
        
        // Vary opacity for depth - stronger in the middle
        qreal alpha = 0.15 + qSin((i / qMax(1.0, (numColors - 1.0))) * M_PI) * 0.1;
        
        QVariantMap stop;
        stop["position"] = position;
        QColor stopColor = color;
        stopColor.setAlphaF(alpha);
        stop["color"] = stopColor;
        stops.append(stop);
    }
    
    // End with transparency
    QVariantMap endStop;
    endStop["position"] = 1.0;
    endStop["color"] = QColor(255, 255, 255, 0);
    stops.append(endStop);
    
    return stops;
}

QUrl ColorUtils::extractCoverArt(const QUrl &audioUrl) const
{
    const QString localPath = audioUrl.isLocalFile()
            ? audioUrl.toLocalFile()
            : audioUrl.toString(QUrl::PreferLocalFile);

    if (localPath.isEmpty() || !QFileInfo::exists(localPath))
        return QUrl();

    // Use QMediaPlayer to load metadata
    QMediaPlayer player;
    QAudioOutput audioOutput;
    player.setAudioOutput(&audioOutput);
    player.setSource(QUrl::fromLocalFile(localPath));

    // Helper function to scale and save image
    auto scaleAndSave = [](const QImage &image, const QString &tempPath) -> QUrl {
        if (image.isNull()) return QUrl();
        
        // Scale down to max 400x400 for faster loading (cover art doesn't need full resolution)
        const int maxSize = 400;
        QImage scaledImage = image;
        if (image.width() > maxSize || image.height() > maxSize) {
            scaledImage = image.scaled(maxSize, maxSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        }
        
        QTemporaryFile tempFile(tempPath);
        if (tempFile.open()) {
            // Use JPEG with quality 85 for faster saving and smaller file size
            scaledImage.save(&tempFile, "JPEG", 85);
            tempFile.setAutoRemove(false);
            return QUrl::fromLocalFile(tempFile.fileName());
        }
        return QUrl();
    };
    
    // Check metadata immediately (might be available right away)
    QMediaMetaData initialMeta = player.metaData();
    QVariant coverArt = initialMeta.value(QMediaMetaData::CoverArtImage);
    if (coverArt.isValid() && coverArt.canConvert<QImage>()) {
        QImage coverImage = coverArt.value<QImage>();
        QUrl result = scaleAndSave(coverImage, QDir::tempPath() + "/cover_art_XXXXXX.jpg");
        if (!result.isEmpty()) {
            return result;
        }
    }
    
    // Try thumbnail immediately
    QVariant thumbnail = initialMeta.value(QMediaMetaData::ThumbnailImage);
    if (thumbnail.isValid() && thumbnail.canConvert<QImage>()) {
        QImage thumbImage = thumbnail.value<QImage>();
        QUrl result = scaleAndSave(thumbImage, QDir::tempPath() + "/cover_art_XXXXXX.jpg");
        if (!result.isEmpty()) {
            return result;
        }
    }
    
    // If not available immediately, wait indefinitely for metadata
    // This ensures we get the cover art even if it takes longer to load
    QEventLoop loop;
    QObject::connect(&player, &QMediaPlayer::metaDataChanged, &loop, &QEventLoop::quit);
    // Also connect to error signal to avoid infinite wait on errors
    QObject::connect(&player, &QMediaPlayer::errorOccurred, &loop, &QEventLoop::quit);
    loop.exec();

    // Helper function to scale and save image (reuse from above)
    auto scaleAndSave2 = [](const QImage &image, const QString &tempPath) -> QUrl {
        if (image.isNull()) return QUrl();
        
        // Scale down to max 600x600 for faster loading
        const int maxSize = 600;
        QImage scaledImage = image;
        if (image.width() > maxSize || image.height() > maxSize) {
            scaledImage = image.scaled(maxSize, maxSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        }
        
        QTemporaryFile tempFile(tempPath);
        if (tempFile.open()) {
            // Use JPEG with quality 85 for faster saving and smaller file size
            scaledImage.save(&tempFile, "JPEG", 85);
            tempFile.setAutoRemove(false);
            return QUrl::fromLocalFile(tempFile.fileName());
        }
        return QUrl();
    };
    
    // Try to get cover art from metadata after waiting
    QMediaMetaData finalMeta = player.metaData();
    QVariant coverArt2 = finalMeta.value(QMediaMetaData::CoverArtImage);
    if (coverArt2.isValid() && coverArt2.canConvert<QImage>()) {
        QImage coverImage = coverArt2.value<QImage>();
        QUrl result = scaleAndSave2(coverImage, QDir::tempPath() + "/cover_art_XXXXXX.jpg");
        if (!result.isEmpty()) {
            return result;
        }
    }

    // Try ThumbnailImage as fallback
    QVariant thumbnail2 = finalMeta.value(QMediaMetaData::ThumbnailImage);
    if (thumbnail2.isValid() && thumbnail2.canConvert<QImage>()) {
        QImage thumbImage = thumbnail2.value<QImage>();
        QUrl result = scaleAndSave2(thumbImage, QDir::tempPath() + "/cover_art_XXXXXX.jpg");
        if (!result.isEmpty()) {
            return result;
        }
    }

    return QUrl();
}

QUrl ColorUtils::saveCoverArtImage(const QVariant &imageVariant) const
{
    if (!imageVariant.isValid() || !imageVariant.canConvert<QImage>()) {
        return QUrl();
    }
    
    QImage coverImage = imageVariant.value<QImage>();
    if (coverImage.isNull()) {
        return QUrl();
    }
    
    // Save to temporary file
    QTemporaryFile tempFile(QDir::tempPath() + "/cover_art_XXXXXX.png");
    if (tempFile.open()) {
        coverImage.save(&tempFile, "PNG");
        tempFile.setAutoRemove(false); // Keep file until app closes
        return QUrl::fromLocalFile(tempFile.fileName());
    }
    
    return QUrl();
}

QVariantMap ColorUtils::getAudioFormatInfo(const QUrl &audioUrl, qint64 durationMs) const
{
    QVariantMap result;
    result["sampleRate"] = 0;
    result["bitrate"] = 0;
    
    const QString localPath = audioUrl.isLocalFile()
            ? audioUrl.toLocalFile()
            : audioUrl.toString(QUrl::PreferLocalFile);

    if (localPath.isEmpty() || !QFileInfo::exists(localPath))
        return result;

    // 1. Estimate bitrate from file size and duration (in milliseconds)
    if (durationMs > 0) {
        const qint64 fileBytes = QFileInfo(localPath).size();
        const double seconds = durationMs / 1000.0;
        if (fileBytes > 0 && seconds > 0.0) {
            const double bits = static_cast<double>(fileBytes) * 8.0;
            const int bitRate = static_cast<int>(bits / seconds);
            if (bitRate > 0) {
                result["bitrate"] = bitRate;
                qDebug() << "[AudioFormat] Calculated bitrate:" << bitRate << "bps from file size:" << fileBytes << "bytes, duration:" << durationMs << "ms";
            }
        } else {
            qDebug() << "[AudioFormat] Cannot calculate bitrate - fileBytes:" << fileBytes << "seconds:" << seconds;
        }
    } else {
        qDebug() << "[AudioFormat] Cannot calculate bitrate - durationMs is 0 or invalid:" << durationMs;
    }

    // 2. Decode a tiny chunk using QAudioDecoder to inspect the PCM format (for sample rate)
    // This works independently of duration, so we always try to get sample rate
    {
        QAudioDecoder decoder;
        decoder.setSource(QUrl::fromLocalFile(localPath));

        QEventLoop loop;
        bool sampleRateFound = false;
        QObject::connect(&decoder, &QAudioDecoder::bufferReady, [&]() {
            const QAudioBuffer buffer = decoder.read();
            if (buffer.format().isValid()) {
                const int rate = buffer.format().sampleRate();
                if (rate > 0) {
                    result["sampleRate"] = rate;
                    sampleRateFound = true;
                    qDebug() << "[AudioFormat] Extracted sample rate:" << rate << "Hz from audio buffer";
                    decoder.stop();
                    loop.quit();
                }
            }
        });
        QObject::connect(&decoder, &QAudioDecoder::finished, [&]() {
            if (!sampleRateFound) {
                qDebug() << "[AudioFormat] Decoder finished but sample rate not found";
                loop.quit();
            }
        });
        // Check for errors periodically instead of connecting to error signal
        // (error is both a signal and a function, causing ambiguity)
        QTimer errorCheckTimer;
        errorCheckTimer.setSingleShot(false);
        errorCheckTimer.setInterval(100);
        QObject::connect(&errorCheckTimer, &QTimer::timeout, [&]() {
            if (decoder.error() != QAudioDecoder::NoError) {
                qDebug() << "[AudioFormat] Decoder error:" << decoder.error() << decoder.errorString();
                loop.quit();
            }
        });
        errorCheckTimer.start();

        decoder.start();
        QTimer::singleShot(2000, &loop, &QEventLoop::quit);
        loop.exec();
        if (errorCheckTimer.isActive()) {
            errorCheckTimer.stop();
        }
        decoder.stop();
        
        if (!sampleRateFound && result["sampleRate"].toInt() == 0) {
            qDebug() << "[AudioFormat] Failed to extract sample rate from audio decoder";
        }
    }

    return result;
}

bool ColorUtils::isFFmpegAvailable() const
{
    // Try both "ffmpeg" and "ffmpeg.exe" for Windows compatibility
    QStringList commands = QStringList() << "ffmpeg" << "ffmpeg.exe";
    
    for (const QString &command : commands) {
        QProcess process;
        process.start(command, QStringList() << "-version");
        if (process.waitForFinished(3000)) {
            if (process.exitCode() == 0) {
                qDebug() << "[VideoFix] FFmpeg found:" << command;
                return true;
            }
        }
    }
    
    qDebug() << "[VideoFix] FFmpeg not found in PATH";
    return false;
}

QUrl ColorUtils::fixVideoFile(const QUrl &videoUrl) const
{
    if (!isFFmpegAvailable()) {
        qDebug() << "[VideoFix] FFmpeg is not available. Please install FFmpeg to fix videos.";
        return QUrl();
    }

    const QString localPath = videoUrl.isLocalFile()
            ? videoUrl.toLocalFile()
            : videoUrl.toString(QUrl::PreferLocalFile);

    if (localPath.isEmpty() || !QFileInfo::exists(localPath))
        return QUrl();

    // Create a fixed version in temp directory
    QFileInfo fileInfo(localPath);
    QString baseName = fileInfo.completeBaseName();
    QString tempDir = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
    QString tempPath = tempDir + "/s3rp3nt_fixed_" + baseName + "_" + QString::number(QDateTime::currentMSecsSinceEpoch()) + ".mp4";
    
    qDebug() << "[VideoFix] Starting video fix process...";
    qDebug() << "[VideoFix] Input:" << localPath;
    qDebug() << "[VideoFix] Output:" << tempPath;
    
    // Use FFmpeg to fix the video with aggressive timestamp correction:
    // Strategy: Use setpts filter to completely rebuild timestamps from scratch
    // This forces FFmpeg to regenerate all timing information
    QString program = "ffmpeg";
    #ifdef Q_OS_WIN
    program = "ffmpeg.exe";
    #endif
    QStringList arguments;
    arguments << "-fflags" << "+genpts+igndts+discardcorrupt"  // Aggressive timestamp handling
              << "-err_detect" << "ignore_err"                 // Ignore errors
              << "-i" << localPath
              << "-c:v" << "libx264"                            // Re-encode video
              << "-preset" << "veryfast"                        // Faster encoding
              << "-crf" << "23"                                 // Good quality
              << "-vf" << "setpts=PTS-STARTPTS"                 // Reset timestamps from 0
              << "-af" << "asetpts=PTS-STARTPTS"                // Reset audio timestamps from 0
              << "-c:a" << "aac"                                // Re-encode audio
              << "-ar" << "44100"                                // Normalize to 44.1kHz
              << "-b:a" << "128k"                                // Better audio bitrate
              << "-vsync" << "cfr"                               // Constant frame rate
              << "-r" << "30"                                    // Force 30fps (matches source)
              << "-avoid_negative_ts" << "make_zero"            // Handle negative timestamps
              << "-map" << "0"                                   // Map all streams
              << "-y"                                            // Overwrite output
              << "-loglevel" << "error"                         // Only show errors
              << tempPath;

    QProcess process;
    process.setProcessChannelMode(QProcess::MergedChannels);
    process.start(program, arguments);
    
    // Wait for completion with timeout (60 seconds for longer videos)
    if (!process.waitForFinished(60000)) {
        qDebug() << "[VideoFix] FFmpeg process timed out";
        process.kill();
        return QUrl();
    }

    if (process.exitCode() != 0) {
        qDebug() << "[VideoFix] FFmpeg failed with exit code:" << process.exitCode();
        QString errorOutput = process.readAllStandardError();
        if (!errorOutput.isEmpty()) {
            qDebug() << "[VideoFix] FFmpeg error:" << errorOutput;
        }
        return QUrl();
    }

    if (QFileInfo::exists(tempPath)) {
        qDebug() << "[VideoFix] Successfully fixed video. Saved to:" << tempPath;
        return QUrl::fromLocalFile(tempPath);
    }

    qDebug() << "[VideoFix] Fixed video file not found after processing";
    return QUrl();
}

QString ColorUtils::readTextFile(const QUrl &fileUrl) const
{
    const QString localPath = fileUrl.isLocalFile()
            ? fileUrl.toLocalFile()
            : fileUrl.toString(QUrl::PreferLocalFile);

    if (localPath.isEmpty() || !QFileInfo::exists(localPath))
        return QString();

    QFile file(localPath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return QString();

    QTextStream in(&file);
    in.setEncoding(QStringConverter::Utf8);
    QString content = in.readAll();
    file.close();

    return content;
}

bool ColorUtils::writeTextFile(const QUrl &fileUrl, const QString &content) const
{
    const QString localPath = fileUrl.isLocalFile()
            ? fileUrl.toLocalFile()
            : fileUrl.toString(QUrl::PreferLocalFile);

    if (localPath.isEmpty())
        return false;

    QFile file(localPath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text))
        return false;

    QTextStream out(&file);
    out.setEncoding(QStringConverter::Utf8);
    out << content;
    file.close();

    qDebug() << "[TextViewer] Saved file:" << localPath;
    return true;
}

QVariantList ColorUtils::getImagesInDirectory(const QUrl &fileUrl) const
{
    QVariantList result;
    
    const QString localPath = fileUrl.isLocalFile()
            ? fileUrl.toLocalFile()
            : fileUrl.toString(QUrl::PreferLocalFile);

    if (localPath.isEmpty())
        return result;

    QFileInfo fileInfo(localPath);
    QDir dir = fileInfo.absoluteDir();
    
    if (!dir.exists())
        return result;

    // Image extensions to look for
    QStringList imageExtensions;
    imageExtensions << "*.jpg" << "*.jpeg" << "*.png" << "*.gif" << "*.bmp" 
                    << "*.webp" << "*.svg" << "*.ico" << "*.tiff" << "*.tif"
                    << "*.JPG" << "*.JPEG" << "*.PNG" << "*.GIF" << "*.BMP"
                    << "*.WEBP" << "*.SVG" << "*.ICO" << "*.TIFF" << "*.TIF";

    // Get all image files in the directory (unsorted, we'll sort manually)
    QFileInfoList files = dir.entryInfoList(imageExtensions, QDir::Files);
    
    // Sort by modification time descending (newest first)
    std::sort(files.begin(), files.end(), [](const QFileInfo &a, const QFileInfo &b) {
        return a.lastModified() > b.lastModified();
    });
    
    for (const QFileInfo &fi : files) {
        result.append(QUrl::fromLocalFile(fi.absoluteFilePath()));
    }

    return result;
}

QString ColorUtils::getAppPath() const
{
    return QCoreApplication::applicationFilePath();
}

void ColorUtils::openDefaultAppsSettings() const
{
#ifdef Q_OS_WIN
    // Open Windows Settings > Default Apps using ShellExecute for URI protocols
    ShellExecuteW(NULL, L"open", L"ms-settings:defaultapps", NULL, NULL, SW_SHOWNORMAL);
#elif defined(Q_OS_MACOS)
    // On macOS, open System Preferences
    QDesktopServices::openUrl(QUrl("x-apple.systempreferences:"));
#else
    // On Linux, try to open system settings
    QDesktopServices::openUrl(QUrl("settings://"));
#endif
}

bool ColorUtils::registerAsDefaultImageViewer() const
{
#ifdef Q_OS_WIN
    QString appPath = QCoreApplication::applicationFilePath().replace("/", "\\");
    
    // appName MUST match the executable name for Windows to find it
    QString appName = QFileInfo(appPath).baseName();  // e.g. "apps3rp3nt_media"
    QString friendlyName = "S3rp3nt Media Viewer";
    
    // Define all supported file types organized by category
    QStringList imageExtensions = {
        ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp", ".ico", ".tiff", ".tif", ".svg"
    };
    
    QStringList videoExtensions = {
        ".mp4", ".avi", ".mov", ".mkv", ".webm", ".m4v", ".flv", ".wmv", ".mpg", ".mpeg", ".3gp"
    };
    
    QStringList audioExtensions = {
        ".mp3", ".wav", ".flac", ".ogg", ".aac", ".m4a", ".wma", ".opus", ".mp2", ".mp1", ".amr"
    };
    
    QStringList documentExtensions = {
        ".pdf", ".txt", ".log", ".nfo", ".csv", ".diff", ".patch",
        ".md", ".markdown", ".mdown", ".mkd", ".mkdn"
    };
    
    QStringList codeExtensions = {
        // Web
        ".html", ".htm", ".css", ".scss", ".sass", ".less", 
        ".js", ".jsx", ".ts", ".tsx", ".vue", ".svelte", ".json",
        // C/C++/Qt
        ".c", ".cpp", ".cc", ".cxx", ".h", ".hpp", ".hxx", 
        ".qml", ".qrc", ".pro", ".pri", ".ui",
        // Python
        ".py", ".pyw", ".pyx", ".pxd", ".pyi",
        // Java/Kotlin
        ".java", ".kt", ".kts", ".gradle",
        // Other languages
        ".rs", ".go", ".rb", ".php", ".swift", ".cs", ".fs", ".scala",
        ".lua", ".pl", ".r", ".dart", ".sh", ".bat", ".ps1", ".sql",
        // Config
        ".ini", ".cfg", ".conf", ".env", ".yaml", ".yml", ".toml", ".xml", ".properties"
    };
    
    // Create ProgIDs for each category
    QString imageProgId = appName + ".Image";
    QString videoProgId = appName + ".Video";
    QString audioProgId = appName + ".Audio";
    QString documentProgId = appName + ".Document";
    QString codeProgId = appName + ".Code";
    
    // 1. Register all ProgIDs (defines what the app does when opening files)
    QSettings classes("HKEY_CURRENT_USER\\Software\\Classes", QSettings::NativeFormat);
    QString cmdLine = QString("\"%1\" \"%2\"").arg(appPath, "%1");
    
    classes.setValue(imageProgId + "/shell/open/command/.", cmdLine);
    classes.setValue(videoProgId + "/shell/open/command/.", cmdLine);
    classes.setValue(audioProgId + "/shell/open/command/.", cmdLine);
    classes.setValue(documentProgId + "/shell/open/command/.", cmdLine);
    classes.setValue(codeProgId + "/shell/open/command/.", cmdLine);
    classes.sync();
    
    // 2. Register Capabilities (path must match RegisteredApplications entry)
    QSettings caps("HKEY_CURRENT_USER\\Software\\" + appName + "\\Capabilities", QSettings::NativeFormat);
    caps.setValue("ApplicationName", friendlyName);
    caps.setValue("ApplicationDescription", "S3rp3nt Media Viewer - A modern viewer for images, videos, audio, and documents");
    
    // Register file associations by category
    for (const QString &ext : imageExtensions) {
        caps.setValue("FileAssociations/" + ext, imageProgId);
    }
    for (const QString &ext : videoExtensions) {
        caps.setValue("FileAssociations/" + ext, videoProgId);
    }
    for (const QString &ext : audioExtensions) {
        caps.setValue("FileAssociations/" + ext, audioProgId);
    }
    for (const QString &ext : documentExtensions) {
        caps.setValue("FileAssociations/" + ext, documentProgId);
    }
    for (const QString &ext : codeExtensions) {
        caps.setValue("FileAssociations/" + ext, codeProgId);
    }
    caps.sync();
    
    // 3. Register in RegisteredApplications (key name must match appName exactly)
    QSettings regApps("HKEY_CURRENT_USER\\Software\\RegisteredApplications", QSettings::NativeFormat);
    regApps.setValue(appName, "Software\\" + appName + "\\Capabilities");
    regApps.sync();
    
    // 4. Notify the shell of the changes
    SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
    
    int totalExtensions = imageExtensions.size() + videoExtensions.size() + 
                          audioExtensions.size() + documentExtensions.size() + 
                          codeExtensions.size();
    
    qDebug() << "[FileAssoc] Registered" << totalExtensions << "file extensions";
    qDebug() << "[FileAssoc] App name:" << appName;
    qDebug() << "[FileAssoc] Executable:" << appPath;
    
    // 5. Open Windows 11 Settings app with app-specific query parameter
    // On Windows 11, LaunchAdvancedAssociationUI() is deprecated for Win32 apps.
    // The official way is to use ms-settings:defaultapps URI with registeredAppUser parameter.
    // Since we register in HKCU (per-user), we use registeredAppUser.
    QString settingsUri = QString("ms-settings:defaultapps?registeredAppUser=%1").arg(appName);
    std::wstring uriW = settingsUri.toStdWString();
    
    qDebug() << "[FileAssoc] Opening Windows Settings:" << settingsUri;
    ShellExecuteW(nullptr, L"open", uriW.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
    
    return true;
#else
    qDebug() << "[FileAssoc] Default app registration not implemented for this platform";
    return false;
#endif
}

void ColorUtils::clearImageCache() const
{
    // Qt doesn't provide a direct API to clear the image cache,
    // but we can try to reduce memory pressure by:
    // 1. Setting a lower allocation limit temporarily
    // 2. This forces Qt to release some cached images
    
    // Reduce image allocation limit to force cache clearing
    int oldLimit = QImageReader::allocationLimit();
    QImageReader::setAllocationLimit(0);  // Disable allocation temporarily
    
    // Force Qt to process events and release memory
    QCoreApplication::processEvents();
    
    QImageReader::setAllocationLimit(oldLimit);  // Restore
    
    // Note: Qt's internal image cache is managed by QML engine
    // and there's no direct way to clear it, but reducing allocation
    // limit can help force some cleanup
}

qreal ColorUtils::getMemoryUsage() const
{
#ifdef Q_OS_WIN
    PROCESS_MEMORY_COUNTERS_EX pmc;
    if (GetProcessMemoryInfo(GetCurrentProcess(), (PROCESS_MEMORY_COUNTERS*)&pmc, sizeof(pmc))) {
        // Return memory usage in MB
        return pmc.WorkingSetSize / (1024.0 * 1024.0);
    }
#endif
    // Fallback for other platforms
    return 0.0;
}

void ColorUtils::copyToClipboard(const QString &text) const
{
    QClipboard *clipboard = QGuiApplication::clipboard();
    if (clipboard) {
        clipboard->setText(text);
    }
}

