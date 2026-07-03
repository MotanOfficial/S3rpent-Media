 #include <QFileInfo>
#include <QApplication>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QUrl>
#include <QLoggingCategory>
#include <QDebug>
#include <QIcon>
#include <QQuickStyle>
#include <QTimer>
#ifdef Q_OS_WIN
#include "windowsglobalhotkey.h"
#endif
#include <QQmlComponent>
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QSurfaceFormat>
#include <QOpenGLContext>
#include <QPointer>
#include <QTranslator>
#include <QLocale>
#include <QStandardPaths>
#include <QDir>
#include <QSettings>
#include <QCoreApplication>
#include <QMediaDevices>
#include <QMediaPlayer>
#include <QAudioOutput>
#include <QAudioDecoder>
#include <QFile>
#include <QFontDatabase>
#include <QFont>
#include <optional>
#include <QtGui/rhi/qrhi.h>
#include <QElapsedTimer>

#include "colorutils.h"
#include "wmfvideoplayer.h"
#ifdef HAS_LIBMPV
#include "mpvvideoplayer.h"
// TEMPORARILY DISABLED: #include "mpvqmlitem.h"
#endif
#ifdef HAS_LIBVLC
#include "vlcvideoplayer.h"
#include "vlcvideoitem.h"
#endif
#include "ffmpegvideoplayer.h"
#include "ffmpegvideorenderer.h"
#include "lrclibclient.h"
#include "lyricstranslationclient.h"
#include "audiovisualizer.h"
#include "audioequalizer.h"
#include "customaudioplayer.h"
#include "discordrpc.h"
#include "singleinstancemanager.h"
#include "windowmanager.h"
#include "windowsmediasession.h"
#include "coverartclient.h"
#include "lastfmclient.h"
#include "windowframehelper.h"
#include "musicoverlaypositioner.h"
#include "subtitleformatter.h"
#include "mediaplayerwrapper.h"
#include "embeddedsubtitleextractor.h"
#include "ziparchivereader.h"
#include "externaldraghelper.h"
#include "modelsourceresolver.h"
#include "youtubeplaybackhelper.h"
#ifdef HAS_WEBRTC_P2P
#include "webrtclistentogethermanager.h"
#endif
#include <oclero/qlementine/icons/QlementineIcons.hpp>

// Constants
namespace {
    constexpr int MAX_DIAGNOSTIC_PROPERTIES = 20;
    const QStringList ICON_PATHS = {":/icon.png", ":/icon.ico"};

    // Qt Multimedia loads backends and decoder plugins lazily. Doing a minimal touch once at
    // startup moves that cost off the first real file open (often hundreds of ms on Windows).
    void warmupQtMultimediaAudio()
    {
        (void) QMediaDevices::defaultAudioOutput();
        {
            QMediaPlayer player;
            QAudioOutput audioOut;
            audioOut.setVolume(0.0f);
            player.setAudioOutput(&audioOut);
        }
        QAudioDecoder decoder;
        Q_UNUSED(decoder);
    }

    // Startup timer for tracking initialization phases
    class StartupTimer {
    public:
        void start() {
            m_timer.start();
            m_lastTime = 0;
            logPoint("Startup began");
        }

        void logPoint(const QString &phase) {
            const qint64 elapsed = m_timer.elapsed();
            const qint64 sinceLast = elapsed - m_lastTime;
            m_lastTime = elapsed;
            qDebug() << QString("[Startup] %1 took %2 ms (total: %3 ms)").arg(phase).arg(sinceLast).arg(elapsed);
        }

        void logToDebugConsole(QObject *debugConsole, const QString &phase) {
            if (!debugConsole) return;
            const qint64 elapsed = m_timer.elapsed();
            const qint64 sinceLast = elapsed - m_lastTime;
            m_lastTime = elapsed;
            const QString message = QString("[Startup] %1 took %2 ms (total: %3 ms)").arg(phase).arg(sinceLast).arg(elapsed);
            QMetaObject::invokeMethod(debugConsole, "addLog",
                Qt::QueuedConnection,
                Q_ARG(QString, message),
                Q_ARG(QString, "info"));
        }

        qint64 elapsed() const {
            return m_timer.elapsed();
        }

    private:
        QElapsedTimer m_timer;
        qint64 m_lastTime = 0;
    };
}

// Helper function to activate a window
inline void activateWindow(QQuickWindow *window)
{
    if (window) {
        window->show();
        window->raise();
        window->requestActivate();
    }
}

// Helper function to get QQuickWindow from QObject
inline QQuickWindow *getQuickWindow(QObject *obj)
{
    return qobject_cast<QQuickWindow*>(obj);
}

namespace {
    // Register all QML types and singletons
    void registerQmlTypes(QQmlApplicationEngine &engine, ColorUtils &colorUtils, SingleInstanceManager &instanceManager)
    {
        // Register types
        qmlRegisterType<WMFVideoPlayer>("s3rpent_media", 1, 0, "WMFVideoPlayer");
#ifdef HAS_LIBMPV
        // Always register MPV QML types when compiled in. QML type resolution happens
        // at load time, before runtime availability checks, so conditional registration
        // causes "is not a type" errors even if usage is guarded in QML.
        qmlRegisterType<MPVVideoPlayer>("s3rpent_media", 1, 0, "MPVVideoPlayer");
        // TEMPORARILY DISABLED: Register mpv widget container for QML embedding (mpc-qt style)
        // This uses QOpenGLWidget internally, which is the ONLY approach that works in Qt 6
        // qmlRegisterType<MPVQmlItem>("s3rpent_media", 1, 0, "MPVVideoWidget");
        // QQuickFramebufferObject approach (minimal, clean implementation following strict rules)
        qmlRegisterType<MPVVideoItem>("s3rpent_media", 1, 0, "MPVVideoItem");
        // Register D3D11-based mpv renderer
        /*
        if (MPVVideoPlayerD3D11::isAvailable()) {
            qmlRegisterType<MPVVideoPlayerD3D11>("s3rpent_media", 1, 0, "MPVVideoPlayerD3D11");
            qmlRegisterType<MPVVideoItemD3D11>("s3rpent_media", 1, 0, "MPVVideoItemD3D11");
        }
        */
#else
        // Keep QML loading even when libmpv is not compiled/found.
        // Without these placeholders, any reference to MPV types fails at QML load time
        // with "... is not a type", even if the MPV backend is not used.
        qmlRegisterTypeNotAvailable("s3rpent_media", 1, 0, "MPVVideoPlayer",
                                    QStringLiteral("libmpv support is not available in this build."));
        qmlRegisterTypeNotAvailable("s3rpent_media", 1, 0, "MPVVideoItem",
                                    QStringLiteral("libmpv support is not available in this build."));
        qmlRegisterTypeNotAvailable("s3rpent_media", 1, 0, "MPVVideoPlayerD3D11",
                                    QStringLiteral("libmpv support is not available in this build."));
        qmlRegisterTypeNotAvailable("s3rpent_media", 1, 0, "MPVVideoItemD3D11",
                                    QStringLiteral("libmpv support is not available in this build."));
#endif
#ifdef HAS_LIBVLC
        qmlRegisterType<VLCVideoPlayer>("s3rpent_media", 1, 0, "VLCVideoPlayer");
        qmlRegisterType<VLCVideoItem>("s3rpent_media", 1, 0, "VLCVideoItem");
#endif
        qmlRegisterType<FFmpegVideoPlayer>("s3rpent_media", 1, 0, "FFmpegVideoPlayer");
        qmlRegisterType<FFmpegVideoRenderer>("s3rpent_media", 1, 0, "FFmpegVideoRenderer");
        qmlRegisterType<LRCLibClient>("s3rpent_media", 1, 0, "LRCLibClient");
        qmlRegisterType<LyricsTranslationClient>("s3rpent_media", 1, 0, "LyricsTranslationClient");
        qmlRegisterType<AudioVisualizer>("s3rpent_media", 1, 0, "AudioVisualizer");
        qmlRegisterType<AudioEqualizer>("s3rpent_media", 1, 0, "AudioEqualizer");
        qmlRegisterType<CustomAudioPlayer>("s3rpent_media", 1, 0, "CustomAudioPlayer");
        qmlRegisterType<DiscordRPC>("s3rpent_media", 1, 0, "DiscordRPC");
        qmlRegisterType<SingleInstanceManager>("s3rpent_media", 1, 0, "SingleInstanceManager");
        qmlRegisterType<WindowsMediaSession>("s3rpent_media", 1, 0, "WindowsMediaSession");
        qmlRegisterType<CoverArtClient>("s3rpent_media", 1, 0, "CoverArtClient");
        qmlRegisterType<LastFMClient>("s3rpent_media", 1, 0, "LastFMClient");
        qmlRegisterType<WindowFrameHelper>("s3rpent_media", 1, 0, "WindowFrameHelper");
        qmlRegisterType<SubtitleFormatter>("s3rpent_media", 1, 0, "SubtitleFormatter");
        qmlRegisterType<MediaPlayerWrapper>("s3rpent_media", 1, 0, "MediaPlayerWrapper");
        qmlRegisterType<EmbeddedSubtitleExtractor>("s3rpent_media", 1, 0, "EmbeddedSubtitleExtractor");
        qmlRegisterType<ZipArchiveReader>("s3rpent_media", 1, 0, "ZipArchiveReader");
        qmlRegisterType<ExternalDragHelper>("s3rpent_media", 1, 0, "ExternalDragHelper");
        qmlRegisterType<ModelSourceResolver>("s3rpent_media", 1, 0, "ModelSourceResolver");
        
        // Register WebRTC Listen Together Manager (conditional on libdatachannel availability)
#ifdef HAS_WEBRTC_P2P
        qmlRegisterType<WebRTCListenTogetherManager>("s3rpent_media", 1, 0, "WebRTCListenTogetherManager");
#else
        qmlRegisterTypeNotAvailable("s3rpent_media", 1, 0, "WebRTCListenTogetherManager",
                                    QStringLiteral("WebRTC P2P support is not available in this build."));
#endif
        
        // Register singletons (Qt 6 approach - no .qmldir needed)
        qmlRegisterSingletonInstance("s3rpent_media", 1, 0, "ColorUtils", &colorUtils);
        qmlRegisterSingletonInstance("s3rpent_media", 1, 0, "InstanceManager", &instanceManager);
    }
    
    // Extract file paths from command line arguments (supports multiple files)
    QList<QUrl> extractFilePaths(const QStringList &args)
    {
        static const QStringList kIgnoredArgs = {
            QStringLiteral("--allow-multiple-instances"),
            QStringLiteral("--multi-instance"),
            QStringLiteral("--debug"),
        };
        QList<QUrl> fileUrls;
        for (int i = 1; i < args.size(); ++i) {
            const QString &arg = args.at(i);
            if (kIgnoredArgs.contains(arg) || arg.startsWith(QLatin1Char('-')))
                continue;
            QFileInfo file(arg);
            if (file.exists() && file.isFile()) {
                fileUrls.append(QUrl::fromLocalFile(file.absoluteFilePath()));
            } else if (!file.exists()) {
                qWarning() << "File does not exist:" << args.at(i);
            } else {
                qWarning() << "Not a file:" << args.at(i);
            }
        }
        return fileUrls;
    }
}

// Initialize application settings
void initApplication(QApplication &app)
{
    app.setOrganizationName("s3rpent");
    app.setOrganizationDomain("s3rpent.media");
    app.setApplicationName("s3rpent_media");
#ifdef S3RPENT_APP_VERSION
    app.setApplicationVersion(QStringLiteral(S3RPENT_APP_VERSION));
#else
    app.setApplicationVersion(QStringLiteral("0.1"));
#endif
    app.setQuitOnLastWindowClosed(false);
}

// Load translation based on language code
QTranslator* loadTranslation(QApplication &app, const QString &languageCode)
{
    // English is the default, no translation needed
    if (languageCode == "en" || languageCode.isEmpty()) {
        return nullptr;
    }
    
    QTranslator *translator = new QTranslator(&app);
    
    QString translationFile = QString("s3rpent_media_%1").arg(languageCode);
    
    // Try to load from resources (qt_add_translations adds them to :/i18n by default)
    if (translator->load(translationFile, ":/i18n")) {
        app.installTranslator(translator);
        qDebug() << "[Translation] Loaded translation from resources:" << translationFile;
        return translator;
    }
    
    // Try alternative resource path
    if (translator->load(translationFile, ":/translations")) {
        app.installTranslator(translator);
        qDebug() << "[Translation] Loaded translation from resources (alt path):" << translationFile;
        return translator;
    }
    
    // Try to load from application directory
    QString appDir = QCoreApplication::applicationDirPath();
    if (translator->load(translationFile, appDir + "/translations")) {
        app.installTranslator(translator);
        qDebug() << "[Translation] Loaded translation from app dir:" << translationFile;
        return translator;
    }
    
    qWarning() << "[Translation] Failed to load translation:" << translationFile;
    delete translator;
    return nullptr;
}

// Initialize icons
void initIcons(QApplication &app)
{
    oclero::qlementine::icons::initializeIconTheme();
    QIcon::setThemeName("qlementine");
    
    // Try loading from application directory first (most reliable)
    QString appDir = QCoreApplication::applicationDirPath();
    QString iconPath = appDir + "/icon.ico";
    if (QFile::exists(iconPath)) {
        QIcon appIcon(iconPath);
        if (!appIcon.isNull() && !appIcon.availableSizes().isEmpty()) {
            app.setWindowIcon(appIcon);
            return;
        }
    }
    iconPath = appDir + "/icon.png";
    if (QFile::exists(iconPath)) {
        QIcon appIcon(iconPath);
        if (!appIcon.isNull() && !appIcon.availableSizes().isEmpty()) {
            app.setWindowIcon(appIcon);
            return;
        }
    }
    
    // Fallback to Qt resources
    for (const QString &iconPath : ICON_PATHS) {
        QIcon appIcon(iconPath);
        if (!appIcon.isNull() && !appIcon.availableSizes().isEmpty()) {
            app.setWindowIcon(appIcon);
            break;
        }
    }
}

namespace {
int addFontFromResources(const QString &resourcePath, QStringList *loadedFamilies = nullptr)
{
    int fontId = QFontDatabase::addApplicationFont(resourcePath);
    if (fontId == -1) {
        qWarning() << "[Fonts] Failed to load font from:" << resourcePath;
        return -1;
    }
    if (loadedFamilies) {
        *loadedFamilies += QFontDatabase::applicationFontFamilies(fontId);
    }
    return fontId;
}
}

// Initialize fonts - load all custom fonts from resources.
void initFonts(QApplication &app)
{
    QStringList loadedFamilies;
    const QStringList allFonts = {
        ":/fonts/resources/fonts/goodly-regular.otf",
        ":/fonts/resources/fonts/goodly-bold.otf",
        ":/fonts/resources/fonts/goodly-semibold.otf",
        ":/fonts/resources/fonts/goodly-medium.otf",
        ":/fonts/resources/fonts/goodly-light.otf",
        ":/fonts/resources/fonts/goodly-extralight.otf",
        ":/fonts/resources/fonts/ut-hp-font.otf",
        ":/fonts/resources/fonts/DTM-Mono.otf",
        ":/fonts/resources/fonts/DTM-Sans.otf",
        ":/fonts/resources/fonts/Mars_Needs_Cunnilingus.ttf"
    };

    for (const QString &fontPath : allFonts) {
        addFontFromResources(fontPath, &loadedFamilies);
    }

    QString goodlyFamily;
    for (const QString &family : loadedFamilies) {
        if (family.contains("Goodly", Qt::CaseInsensitive)) {
            goodlyFamily = family;
            break;
        }
    }
    if (!goodlyFamily.isEmpty()) {
        QFont defaultFont(goodlyFamily);
        defaultFont.setStyleHint(QFont::SansSerif);
        app.setFont(defaultFont);
    }
}


// Initialize logging filters
void initLogging()
{
    // Only use setFilterRules - qputenv would overwrite it
    static const QString filterRules = 
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
        "*.ffmpeg=false";
    QLoggingCategory::setFilterRules(filterRules);
}

// Diagnostic function (only in DEBUG builds)
#ifdef DEBUG
void runDiagnostics(QObject *rootObject, QObject *debugConsole)
{
    if (!rootObject) {
        return;
    }
    
    auto logToDebug = [debugConsole](const QString &message, const QString &type = "info") {
        if (debugConsole) {
            QMetaObject::invokeMethod(debugConsole, "addLog", 
                Qt::QueuedConnection,
                Q_ARG(QString, message), 
                Q_ARG(QString, type));
        }
    };
    
    qDebug() << "[C++] DIAGNOSTIC: Root object type:" << rootObject->metaObject()->className();
    logToDebug(QString("[C++] DIAGNOSTIC: Root object type: %1").arg(rootObject->metaObject()->className()));
    
    QQuickWindow *quickWin = getQuickWindow(rootObject);
    qDebug() << "[C++] DIAGNOSTIC: Is QQuickWindow:" << (quickWin != nullptr);
    
    int propIndex = rootObject->metaObject()->indexOfProperty("currentImage");
    qDebug() << "[C++] DIAGNOSTIC: currentImage property index:" << propIndex;
    logToDebug(QString("[C++] DIAGNOSTIC: currentImage property index: %1").arg(propIndex), 
               propIndex >= 0 ? "info" : "error");
    
    if (propIndex >= 0) {
        QMetaProperty prop = rootObject->metaObject()->property(propIndex);
        qDebug() << "[C++] DIAGNOSTIC: currentImage property name:" << prop.name();
        qDebug() << "[C++] DIAGNOSTIC: currentImage property type:" << prop.typeName();
        qDebug() << "[C++] DIAGNOSTIC: currentImage is writable:" << prop.isWritable();
        logToDebug(QString("[C++] DIAGNOSTIC: currentImage property found - name: %1, writable: %2")
            .arg(prop.name()).arg(prop.isWritable() ? "yes" : "no"));
    } else {
        qWarning() << "[C++] ERROR: currentImage property NOT FOUND on root object!";
        logToDebug("[C++] ERROR: currentImage property NOT FOUND on root object!", "error");
        
        qDebug() << "[C++] Available properties on root object:";
        const QMetaObject *meta = rootObject->metaObject();
        for (int i = 0; i < meta->propertyCount() && i < MAX_DIAGNOSTIC_PROPERTIES; ++i) {
            QMetaProperty prop = meta->property(i);
            qDebug() << "  -" << prop.name() << "(" << prop.typeName() << ")";
            logToDebug(QString("[C++] Property: %1 (%2)").arg(prop.name()).arg(prop.typeName()));
        }
    }
}
#endif

namespace {
    // Helper to log component errors
    void logComponentErrors(const QQmlComponent &component, const QString &context)
    {
        for (const auto &error : component.errors()) {
            qWarning() << context << "Error:" << error;
        }
    }
}

// Create debug console window
QObject* createDebugConsole(QQmlApplicationEngine &engine, QObject *rootObject)
{
    QQmlComponent debugComponent(&engine);
    debugComponent.loadFromModule("s3rpent_media", "DebugConsole");
    if (!debugComponent.isReady()) {
        qWarning() << "Debug console component not ready";
        logComponentErrors(debugComponent, "  ");
        return nullptr;
    }
    
    // Create with root context as parent for automatic cleanup
    QObject *debugWindow = debugComponent.create(engine.rootContext());
    if (!debugWindow) {
        qWarning() << "Failed to create debug console window";
        logComponentErrors(debugComponent, "  ");
        return nullptr;
    }
    
    debugWindow->setProperty("mainWindow", QVariant::fromValue(rootObject));
    
    QQuickWindow *quickDebugWindow = getQuickWindow(debugWindow);
    if (quickDebugWindow) {
        quickDebugWindow->show();
        quickDebugWindow->raise();
        quickDebugWindow->setProperty("isMainWindow", false);
    }
    
    return debugWindow;
}

// Load main window from QML
QObject* loadMainWindow(QQmlApplicationEngine &engine)
{
    // Use context property instead of initial properties for static flag
    engine.rootContext()->setContextProperty("isMainWindow", true);
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        QCoreApplication::instance(),
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);
    
    engine.loadFromModule("s3rpent_media", "Main");
    
    if (engine.rootObjects().isEmpty()) {
        qCritical() << "Failed to load main window - check QML errors above";
        return nullptr;
    }
    
    return engine.rootObjects().first();
}

// Connect instance manager signals
void connectInstanceSignals(SingleInstanceManager &instanceManager, 
                            WindowManager &windowManager, 
                            QObject *rootObject)
{
    QObject::connect(&instanceManager, &SingleInstanceManager::fileOpenRequested, 
                     [&windowManager](const QString &filePath) {
        QQuickWindow *newWindow = windowManager.createNewWindow(QUrl::fromLocalFile(filePath));
        if (newWindow) {
            activateWindow(newWindow);
        }
    });
    
    // Use QPointer for safety in case rootObject is deleted
    QPointer<QObject> safeRootObject(rootObject);
    QObject::connect(&instanceManager, &SingleInstanceManager::showRequested, 
                     [safeRootObject]() {
        if (!safeRootObject) {
            return;
        }
        QQuickWindow *window = getQuickWindow(safeRootObject);
        if (window) {
            activateWindow(window);
        }
    });
}

int main(int argc, char *argv[])
{
    // Startup timing - begin tracking before any initialization
    StartupTimer startupTimer;
    startupTimer.start();

    // CRITICAL: We need to read settings to determine renderer mode, but QSettings needs
    // the organization/application name to be set first. However, we need to set the
    // graphics API before QApplication is created. So we:
    // 1. Set organization/application name manually for QSettings
    // 2. Read the setting
    // 3. Set graphics API based on setting
    // 4. Create QApplication
    // 5. Call initApplication() (which will set the same org/app name, but that's fine)
    
    // Set organization/application name for QSettings (must be before reading settings)
    QCoreApplication::setOrganizationName("s3rpent");
    QCoreApplication::setOrganizationDomain("s3rpent.media");
    QCoreApplication::setApplicationName("s3rpent_media");
    
    startupTimer.logPoint("Pre-app setup (settings, graphics backend selection)");

    // Check settings to determine which Qt scenegraph backend to use.
    // Default behavior:
    // - Direct3D11 for normal app startup on Windows
    // - OpenGL only when libmpv backend is selected (libmpv renderer requires it)
    QSettings settings;
    settings.beginGroup("video");
    const QString videoBackend = settings.value("videoBackend", "mediaplayer").toString();
    QString mpvRendererMode = settings.value("mpvRendererMode", "opengl").toString();
    const bool forceOpenGLForMpv = (videoBackend == "libmpv");
    settings.endGroup();
    
    // Check if debug console is enabled
    settings.beginGroup("debug");
    bool debugConsoleEnabled = settings.value("consoleEnabled", false).toBool();
    settings.endGroup();
    
    // Select Qt graphics backend:
    // - libmpv backend => force OpenGL
    // - all other backends => use Direct3D11 by default on Windows
    if (forceOpenGLForMpv) {
        // Use OpenGL backend for libmpv renderer.
        qputenv("QSG_RHI_BACKEND", "opengl");
        QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
    } else {
        // Explicitly select D3D11 so startup defaults to DirectX for non-mpv backends.
        qputenv("QSG_RHI_BACKEND", "d3d11");
        QQuickWindow::setGraphicsApi(QSGRendererInterface::Direct3D11);
    }
    
    // Set style before creating QApplication (Qt recommendation)
    // Note: High DPI scaling is automatically enabled in Qt 6.10.1+
    QQuickStyle::setStyle("Basic");

    // Fractional monitor scale (125%/150%): reduce two-lane jitter vs PassThrough.
    // Must be set before QGuiApplication / QApplication is constructed.
    QGuiApplication::setHighDpiScaleFactorRoundingPolicy(
        Qt::HighDpiScaleFactorRoundingPolicy::Round);

    QApplication app(argc, argv);
    startupTimer.logPoint("QApplication creation");

    // Initialize application (sets same org/app name, which is fine - just ensures consistency)
    initApplication(app);

    // Defer multimedia warmup to background to improve perceived startup time.
    // FFmpeg/Qt Multimedia initialization takes ~800ms which blocks window appearance.
    // By deferring it, the window shows immediately and media backends init in background.
    QTimer::singleShot(0, &app, [&startupTimer]() {
        warmupQtMultimediaAudio();
        startupTimer.logPoint("Background multimedia warmup");
    });
    startupTimer.logPoint("Application init (warmup deferred)");
    
    // Verify configured backend intent (actual RHI is checked after window is created)
    
    // Load application language setting (reuse settings object from above)
    settings.beginGroup("app");
    QString appLanguage = settings.value("language", "en").toString();
    settings.endGroup();
    
    // Load translation
    QTranslator *appTranslator = loadTranslation(app, appLanguage);
    Q_UNUSED(appTranslator);
    
    const QStringList args = app.arguments();
    const bool allowMultipleInstances = args.contains(QStringLiteral("--allow-multiple-instances"))
        || args.contains(QStringLiteral("--multi-instance"));

    // Create single instance manager and color utils (needed for singleton registration)
    SingleInstanceManager instanceManager(allowMultipleInstances);
    
    // Initialize icons (must be after QApplication is created)
    initIcons(app);
    
    // Initialize fonts before QML engine loads so startup UI resolves families correctly.
    initFonts(app);

    // Initialize logging
    initLogging();

    startupTimer.logPoint("Icons, fonts, and logging init");
    
    ColorUtils colorUtils;
    
    // Get file paths from command line (supports multiple files)
    QList<QUrl> fileUrls = extractFilePaths(args);
    
    // If not primary instance, try to activate existing one
    if (!allowMultipleInstances && !instanceManager.isPrimaryInstance()) {
        // Send first file path if available
        QString pathToSend = fileUrls.isEmpty() ? QStringLiteral("") : fileUrls.first().toLocalFile();
        if (instanceManager.tryActivateExistingInstance(pathToSend)) {
            return 0;
        }
    }
    
    // Create engine
    QQmlApplicationEngine engine;
    startupTimer.logPoint("QML Engine creation");

    MusicOverlayPositioner musicOverlayPositioner(&app);
    engine.rootContext()->setContextProperty(QStringLiteral("MusicOverlayPositioning"), &musicOverlayPositioner);

    YouTubePlaybackHelper youtubePlaybackHelper;
    engine.rootContext()->setContextProperty(QStringLiteral("YouTubePlayback"), &youtubePlaybackHelper);

    // Expose whether YouTube dialog shortcut is enabled (debug builds only)
#ifdef ENABLE_YOUTUBE_DIALOG
    engine.rootContext()->setContextProperty(QStringLiteral("youtubeDialogEnabled"), QVariant(true));
#else
    engine.rootContext()->setContextProperty(QStringLiteral("youtubeDialogEnabled"), QVariant(false));
#endif

    // Expose whether libmpv is available (debug builds only)
#ifdef HAS_LIBMPV
    engine.rootContext()->setContextProperty(QStringLiteral("libmpvAvailable"), QVariant(true));
#else
    engine.rootContext()->setContextProperty(QStringLiteral("libmpvAvailable"), QVariant(false));
#endif

#ifdef HAS_WEBRTC_P2P
    engine.rootContext()->setContextProperty(QStringLiteral("webrtcP2PAvailable"), QVariant(true));
#else
    engine.rootContext()->setContextProperty(QStringLiteral("webrtcP2PAvailable"), QVariant(false));
#endif

    // Register QML types and singletons (singletons must be registered before loading QML)
    // Note: Singletons eliminate the need for context properties
    registerQmlTypes(engine, colorUtils, instanceManager);
    startupTimer.logPoint("QML type registration");

#ifdef Q_OS_WIN
    auto *globalHotkey = new WindowsGlobalHotkey(&app);
    engine.rootContext()->setContextProperty(QStringLiteral("overlayHotkey"), globalHotkey);
#endif
    
    // Load main window with detailed timing
    startupTimer.logPoint("Before QML load");
    QObject *rootObject = loadMainWindow(engine);
    startupTimer.logPoint("QML module loading (Main.qml parse + component creation)");
    if (!rootObject) {
        qCritical() << "Failed to create root object";
        return -1;
    }
    
    // Verify RHI backend after window is created
    // Note: QRhi::OpenGLES2 is used for both desktop OpenGL and OpenGL ES
    // The actual GL context type is determined by QSG_RHI_BACKEND and setGraphicsApi()
    QQuickWindow *window = qobject_cast<QQuickWindow*>(rootObject);
    if (window) {
        QRhi *rhi = window->rhi();
        if (rhi) {
            qDebug() << "[RHI] Backend:" << rhi->backend() << "(OpenGLES2 enum used for both desktop GL and ES)";
            if (rhi->backend() != QRhi::OpenGLES2) {
                qWarning() << "[RHI] WARNING: Backend is not OpenGLES2 - mpv OpenGL renderer requires OpenGL backend!";
            } else {
                qDebug() << "[RHI] ✓ OpenGL backend active (check GL logs to verify desktop GL vs ANGLE)";
            }
        }
        startupTimer.logPoint("Window created + RHI verification");
    }
    
    // Create debug console only if enabled in settings
    QObject *debugConsole = nullptr;
    if (debugConsoleEnabled) {
        debugConsole = createDebugConsole(engine, rootObject);
        startupTimer.logToDebugConsole(debugConsole, "Debug console creation");
    }
    
    // Create WindowManager (parented to app for automatic cleanup)
    WindowManager windowManager(&app);
    windowManager.setEngine(&engine);
    windowManager.setColorUtils(&colorUtils);
    windowManager.setInstanceManager(&instanceManager);
    if (debugConsole) {
        windowManager.setDebugConsole(debugConsole);
    }
    
    // Create WindowFrameHelper for frameless window support (Windows only)
#ifdef Q_OS_WIN
    WindowFrameHelper *frameHelper = new WindowFrameHelper(&app);
    app.installNativeEventFilter(frameHelper);
    QObject::connect(frameHelper, &WindowFrameHelper::accentColorizationChanged, rootObject, [rootObject]() {
        if (!rootObject->property("windowsAccentColorEnabled").toBool())
            return;
        QMetaObject::invokeMethod(rootObject, "updateAccentColor", Qt::QueuedConnection);
    });
#endif
    
    // Run diagnostics (only in DEBUG builds)
#ifdef DEBUG
    if (debugConsole) {
        runDiagnostics(rootObject, debugConsole);
    }
#endif
    
    // Add main window to pool
    windowManager.addMainWindow(rootObject);
    startupTimer.logToDebugConsole(debugConsole, "Window manager init");

    // Calculate total startup time
    const qint64 totalStartupTime = startupTimer.elapsed();
    const QString totalTimeMsg = QString("[Startup] Total startup time: %1 ms").arg(totalStartupTime);
    qDebug() << totalTimeMsg;

    // Set debug console reference in main window
    if (debugConsole && rootObject) {
        rootObject->setProperty("debugConsole", QVariant::fromValue(debugConsole));
        // Note: QML function signature is logToDebugConsole(QVariant, QVariant)
        QMetaObject::invokeMethod(rootObject, "logToDebugConsole", 
            Qt::QueuedConnection,
            Q_ARG(QVariant, QVariant("[Main] Debug console connected from C++")), 
            Q_ARG(QVariant, QVariant("info")));
        // Also log the total startup time to debug console
        QMetaObject::invokeMethod(rootObject, "logToDebugConsole",
            Qt::QueuedConnection,
            Q_ARG(QVariant, QVariant(totalTimeMsg)),
            Q_ARG(QVariant, QVariant("info")));
    }

    // High-impact startup deferral: initialize tray icon after first event-loop turn.
    QTimer::singleShot(0, &instanceManager, [&instanceManager]() {
        instanceManager.initializeSystemTray();
        instanceManager.updateTrayIcon();
    });

    // If files were provided on command line, load them
    if (!fileUrls.isEmpty()) {
        // Load first file in main window
        QUrl firstFileUrl = fileUrls.first();
        
        // Show and activate main window
        activateWindow(getQuickWindow(rootObject));
        
        // Set currentImage - trust QML type system
        rootObject->setProperty("currentImage", firstFileUrl);
        
        // Open remaining files in separate windows
        for (int i = 1; i < fileUrls.size(); ++i) {
            QQuickWindow *newWindow = windowManager.createNewWindow(fileUrls.at(i));
            if (newWindow) {
                activateWindow(newWindow);
            }
        }
    }
    
    // Connect instance manager signals
    connectInstanceSignals(instanceManager, windowManager, rootObject);

#ifdef Q_OS_WIN
    QTimer::singleShot(100, &app, [globalHotkey, rootObject]() {
        globalHotkey->registerOverlayToggleHotkey(rootObject);
    });
#endif

    return app.exec();
}
