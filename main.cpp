#include <QFileInfo>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QUrl>
#include <QVariantMap>
#include <QLoggingCategory>
#include <QDebug>
#include <QIcon>

#include "colorutils.h"
#include "wmfvideoplayer.h"
#include "lrclibclient.h"
#include "audiovisualizer.h"
#include "audioequalizer.h"
#include "customaudioplayer.h"
#include <oclero/qlementine/icons/QlementineIcons.hpp>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    
    // Set application identifiers for QSettings
    app.setOrganizationName("s3rp3nt");
    app.setOrganizationDomain("s3rp3nt.media");
    app.setApplicationName("s3rp3nt_media");
    
    // Initialize qlementine-icons
    oclero::qlementine::icons::initializeIconTheme();
    QIcon::setThemeName("qlementine");
    
    // Disable all verbose FFmpeg and multimedia logging for better performance
    // Suppress FFmpeg messages completely when using WMF
    QLoggingCategory::setFilterRules(
        "qt.multimedia.debug=false\n"
        "qt.multimedia.ffmpeg.*=false\n"
        "qt.multimedia.ffmpeg.mediadataholder=false\n"
        "qt.multimedia.ffmpeg.metadata=false\n"
        "qt.multimedia.ffmpeg.playbackengine=false\n"
        "qt.multimedia.ffmpeg.codecstorage=false\n"
        "qt.multimedia.ffmpeg.streamdecoder=false\n"
        "qt.multimedia.ffmpeg.demuxer=false\n"
        "qt.multimedia.ffmpeg.resampler=false\n"
        "qt.multimedia.ffmpeg.audioDecoder=false\n"
        "qt.multimedia.audiodevice.probes=false\n"
        "qt.multimedia.plugin=false\n"
        "*.aac=false\n"
        "*.ffmpeg=false"
    );
    
    // Also set environment variable to suppress FFmpeg output
    qputenv("QT_LOGGING_RULES", "qt.multimedia.ffmpeg.*=false");

    QQmlApplicationEngine engine;
    ColorUtils colorUtils;
    engine.rootContext()->setContextProperty("ColorUtils", &colorUtils);
    
    // Register WMFVideoPlayer for QML
    qmlRegisterType<WMFVideoPlayer>("s3rp3nt_media", 1, 0, "WMFVideoPlayer");
    
    // Register LRCLibClient for QML
    qmlRegisterType<LRCLibClient>("s3rp3nt_media", 1, 0, "LRCLibClient");
    
    // Register AudioVisualizer for QML
    qmlRegisterType<AudioVisualizer>("s3rp3nt_media", 1, 0, "AudioVisualizer");
    
    // Register AudioEqualizer for QML
    qmlRegisterType<AudioEqualizer>("s3rp3nt_media", 1, 0, "AudioEqualizer");
    
    // Register CustomAudioPlayer for QML
    qmlRegisterType<CustomAudioPlayer>("s3rp3nt_media", 1, 0, "CustomAudioPlayer");
    QVariantMap initialProps;
    const QStringList args = app.arguments();
    if (args.size() > 1) {
        QFileInfo file(args.at(1));
        if (file.exists()) {
            initialProps.insert("initialImage", QUrl::fromLocalFile(file.absoluteFilePath()));
        }
    }

    if (!initialProps.isEmpty()) {
        engine.setInitialProperties(initialProps);
    }
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);
    engine.loadFromModule("s3rp3nt_media", "Main");

    return app.exec();
}
