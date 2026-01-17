#include <QFileInfo>
#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QUrl>
#include <QLoggingCategory>
#include <QDebug>
#include <QIcon>
#include <QQuickStyle>
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
#include <QFile>
#include <QFontDatabase>
#include <QFont>
#include <optional>
#include <QtGui/rhi/qrhi.h>

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
#include "subtitleformatter.h"
#include "mediaplayerwrapper.h"
#include "embeddedsubtitleextractor.h"
#include <oclero/qlementine/icons/QlementineIcons.hpp>

// Constants
namespace {
    constexpr int MAX_DIAGNOSTIC_PROPERTIES = 20;
    const QStringList ICON_PATHS = {":/icon.png", ":/icon.ico"};
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
        qmlRegisterType<WMFVideoPlayer>("s3rp3nt_media", 1, 0, "WMFVideoPlayer");
#ifdef HAS_LIBMPV
        if (MPVVideoPlayer::isAvailable()) {
            qmlRegisterType<MPVVideoPlayer>("s3rp3nt_media", 1, 0, "MPVVideoPlayer");
            // TEMPORARILY DISABLED: Register mpv widget container for QML embedding (mpc-qt style)
            // This uses QOpenGLWidget internally, which is the ONLY approach that works in Qt 6
            // qmlRegisterType<MPVQmlItem>("s3rp3nt_media", 1, 0, "MPVVideoWidget");
            // QQuickFramebufferObject approach (minimal, clean implementation following strict rules)
            qmlRegisterType<MPVVideoItem>("s3rp3nt_media", 1, 0, "MPVVideoItem");
        }
        // Register D3D11-based mpv renderer
        /*
        if (MPVVideoPlayerD3D11::isAvailable()) {
            qmlRegisterType<MPVVideoPlayerD3D11>("s3rp3nt_media", 1, 0, "MPVVideoPlayerD3D11");
            qmlRegisterType<MPVVideoItemD3D11>("s3rp3nt_media", 1, 0, "MPVVideoItemD3D11");
        }
        */
#endif
#ifdef HAS_LIBVLC
        qmlRegisterType<VLCVideoPlayer>("s3rp3nt_media", 1, 0, "VLCVideoPlayer");
        qmlRegisterType<VLCVideoItem>("s3rp3nt_media", 1, 0, "VLCVideoItem");
#endif
        qmlRegisterType<FFmpegVideoPlayer>("s3rp3nt_media", 1, 0, "FFmpegVideoPlayer");
        qmlRegisterType<FFmpegVideoRenderer>("s3rp3nt_media", 1, 0, "FFmpegVideoRenderer");
        qmlRegisterType<LRCLibClient>("s3rp3nt_media", 1, 0, "LRCLibClient");
        qmlRegisterType<LyricsTranslationClient>("s3rp3nt_media", 1, 0, "LyricsTranslationClient");
        qmlRegisterType<AudioVisualizer>("s3rp3nt_media", 1, 0, "AudioVisualizer");
        qmlRegisterType<AudioEqualizer>("s3rp3nt_media", 1, 0, "AudioEqualizer");
        qmlRegisterType<CustomAudioPlayer>("s3rp3nt_media", 1, 0, "CustomAudioPlayer");
        qmlRegisterType<DiscordRPC>("s3rp3nt_media", 1, 0, "DiscordRPC");
        qmlRegisterType<SingleInstanceManager>("s3rp3nt_media", 1, 0, "SingleInstanceManager");
        qmlRegisterType<WindowsMediaSession>("s3rp3nt_media", 1, 0, "WindowsMediaSession");
        qmlRegisterType<CoverArtClient>("s3rp3nt_media", 1, 0, "CoverArtClient");
        qmlRegisterType<LastFMClient>("s3rp3nt_media", 1, 0, "LastFMClient");
        qmlRegisterType<WindowFrameHelper>("s3rp3nt_media", 1, 0, "WindowFrameHelper");
        qmlRegisterType<SubtitleFormatter>("s3rp3nt_media", 1, 0, "SubtitleFormatter");
        qmlRegisterType<MediaPlayerWrapper>("s3rp3nt_media", 1, 0, "MediaPlayerWrapper");
        qmlRegisterType<EmbeddedSubtitleExtractor>("s3rp3nt_media", 1, 0, "EmbeddedSubtitleExtractor");
        
        // Register singletons (Qt 6 approach - no .qmldir needed)
        qmlRegisterSingletonInstance("s3rp3nt_media", 1, 0, "ColorUtils", &colorUtils);
        qmlRegisterSingletonInstance("s3rp3nt_media", 1, 0, "InstanceManager", &instanceManager);
    }
    
    // Extract file paths from command line arguments (supports multiple files)
    QList<QUrl> extractFilePaths(const QStringList &args)
    {
        QList<QUrl> fileUrls;
        for (int i = 1; i < args.size(); ++i) {
            QFileInfo file(args.at(i));
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
    app.setOrganizationName("s3rp3nt");
    app.setOrganizationDomain("s3rp3nt.media");
    app.setApplicationName("s3rp3nt_media");
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
    
    QString translationFile = QString("s3rp3nt_media_%1").arg(languageCode);
    
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

// Initialize fonts - load custom fonts from resources
void initFonts(QApplication &app)
{
    QFontDatabase fontDb;
    
    // List of font files to load
    // Note: qt_add_resources creates aliases with full path, so use resources/fonts/ prefix
    QStringList fontFiles = {
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
    
    QStringList loadedFontFamilies;
    
    // Load each font file - try resources first, then file system
    for (const QString &fontPath : fontFiles) {
        int fontId = -1;
        
        // Try loading from resources first
        fontId = fontDb.addApplicationFont(fontPath);
        
        // If that fails, try loading from file system (for development)
        if (fontId == -1) {
            QString appDir = QCoreApplication::applicationDirPath();
            QString fileName = QFileInfo(fontPath).fileName();
            QString fileSystemPath = appDir + "/" + fileName;
            
            // Also try in resources/fonts relative to app dir
            if (!QFile::exists(fileSystemPath)) {
                fileSystemPath = appDir + "/resources/fonts/" + fileName;
            }
            
            // Also try in source directory (for development)
            if (!QFile::exists(fileSystemPath)) {
                QString sourcePath = QCoreApplication::applicationDirPath() + "/../../resources/fonts/" + fileName;
                if (QFile::exists(sourcePath)) {
                    fileSystemPath = sourcePath;
                }
            }
            
            if (QFile::exists(fileSystemPath)) {
                fontId = fontDb.addApplicationFont(fileSystemPath);
                if (fontId != -1) {
                    qDebug() << "[Fonts] Loaded font from file system:" << fileSystemPath;
                }
            }
        }
        
        if (fontId != -1) {
            QStringList fontFamilies = fontDb.applicationFontFamilies(fontId);
            if (!fontFamilies.isEmpty()) {
                loadedFontFamilies.append(fontFamilies);
                qDebug() << "[Fonts] Loaded font:" << fontFamilies.first() << "from" << fontPath;
            } else {
                qWarning() << "[Fonts] Failed to get font family from:" << fontPath;
            }
        } else {
            qWarning() << "[Fonts] Failed to load font from:" << fontPath;
        }
    }
    
    // Set Goodly as the default application font (use regular weight)
    if (!loadedFontFamilies.isEmpty()) {
        // Find "Goodly" family (should be the same for all weights)
        QString goodlyFamily;
        for (const QString &family : loadedFontFamilies) {
            if (family.contains("Goodly", Qt::CaseInsensitive)) {
                goodlyFamily = family;
                break;
            }
        }
        
        if (!goodlyFamily.isEmpty()) {
            QFont defaultFont(goodlyFamily);
            defaultFont.setStyleHint(QFont::SansSerif);
            app.setFont(defaultFont);
            qDebug() << "[Fonts] Set default application font to:" << goodlyFamily;
        } else {
            qWarning() << "[Fonts] Could not find Goodly font family in loaded fonts";
        }
    } else {
        qWarning() << "[Fonts] No fonts were loaded successfully";
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
    debugComponent.loadFromModule("s3rp3nt_media", "DebugConsole");
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
    
    engine.loadFromModule("s3rp3nt_media", "Main");
    
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
    // CRITICAL: We need to read settings to determine renderer mode, but QSettings needs
    // the organization/application name to be set first. However, we need to set the
    // graphics API before QApplication is created. So we:
    // 1. Set organization/application name manually for QSettings
    // 2. Read the setting
    // 3. Set graphics API based on setting
    // 4. Create QApplication
    // 5. Call initApplication() (which will set the same org/app name, but that's fine)
    
    // Set organization/application name for QSettings (must be before reading settings)
    QCoreApplication::setOrganizationName("s3rp3nt");
    QCoreApplication::setOrganizationDomain("s3rp3nt.media");
    QCoreApplication::setApplicationName("s3rp3nt_media");
    
    // Check settings to determine which renderer mode to use
    QSettings settings;
    settings.beginGroup("video");
    QString mpvRendererMode = settings.value("mpvRendererMode", "opengl").toString();
    qDebug() << "[Main] Reading mpvRendererMode from settings:" << mpvRendererMode;
    qDebug() << "[Main] All video settings keys:" << settings.allKeys();
    settings.endGroup();
    
    // Check if debug console is enabled
    settings.beginGroup("debug");
    bool debugConsoleEnabled = settings.value("consoleEnabled", false).toBool();
    settings.endGroup();
    qDebug() << "[Main] Debug console enabled:" << debugConsoleEnabled;
    
    // Only force OpenGL if OpenGL renderer mode is selected
    // D3D11 mode will use Qt's default backend selection (D3D11 on Windows)
    if (mpvRendererMode == "opengl") {
        // Use OpenGL backend for mpv OpenGL renderer (official API, works on all platforms)
        // mpv's OpenGL renderer is the official, stable API
        // Qt 6 will use ANGLE on Windows (OpenGL ES via D3D11) for compatibility
        
        // 1. Force OpenGL backend (REQUIRED for mpv OpenGL renderer)
        qputenv("QSG_RHI_BACKEND", "opengl");
        
        // 2. Set Qt Quick to use OpenGL (mpv requires OpenGL context)
        QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
        
        qDebug() << "[Main] OpenGL renderer mode selected - forcing OpenGL backend";
    } else {
        // D3D11 mode - let Qt use default backend (D3D11 on Windows)
        // Don't set QSG_RHI_BACKEND - let Qt use its default (D3D11 on Windows)
        qDebug() << "[Main] D3D11 renderer mode selected - using default Qt backend (D3D11 on Windows)";
    }
    
    // Set style before creating QApplication (Qt recommendation)
    // Note: High DPI scaling is automatically enabled in Qt 6.10.1+
    QQuickStyle::setStyle("Basic");
    
    QApplication app(argc, argv);
    
    // Initialize application (sets same org/app name, which is fine - just ensures consistency)
    initApplication(app);
    
    // Verify desktop OpenGL backend is being used (critical diagnostic)
    // Note: Can't check RHI before window is shown, so we'll verify later
    if (mpvRendererMode == "opengl") {
        qDebug() << "[RHI] Desktop OpenGL backend configured for mpv OpenGL renderer (NOT ANGLE/OpenGLES2)";
    } else {
        qDebug() << "[RHI] D3D11 backend will be used (Qt default on Windows)";
    }
    
    // Load application language setting (reuse settings object from above)
    settings.beginGroup("app");
    QString appLanguage = settings.value("language", "en").toString();
    settings.endGroup();
    
    // Load translation
    QTranslator *appTranslator = loadTranslation(app, appLanguage);
    
    // Create single instance manager and color utils (needed for singleton registration)
    // Note: This creates the tray icon, but icon may not be set yet
    SingleInstanceManager instanceManager;
    
    // Initialize icons (must be after QApplication is created)
    initIcons(app);
    
    // Initialize fonts (must be after QApplication is created)
    initFonts(app);
    
    // Update tray icon now that app icon is set
    instanceManager.updateTrayIcon();
    
    // Initialize logging
    initLogging();
    
    ColorUtils colorUtils;
    
    // Get file paths from command line (supports multiple files)
    const QStringList args = app.arguments();
    QList<QUrl> fileUrls = extractFilePaths(args);
    
    // If not primary instance, try to activate existing one
    if (!instanceManager.isPrimaryInstance()) {
        // Send first file path if available
        QString pathToSend = fileUrls.isEmpty() ? QStringLiteral("") : fileUrls.first().toLocalFile();
        if (instanceManager.tryActivateExistingInstance(pathToSend)) {
            return 0;
        }
    }
    
    // Create engine
    QQmlApplicationEngine engine;
    
    // Register QML types and singletons (singletons must be registered before loading QML)
    // Note: Singletons eliminate the need for context properties
    registerQmlTypes(engine, colorUtils, instanceManager);
    
    // Load main window
    QObject *rootObject = loadMainWindow(engine);
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
        } else {
            qWarning() << "[RHI] No RHI available yet (window may not be shown)";
        }
    }
    
    // Create debug console only if enabled in settings
    QObject *debugConsole = nullptr;
    if (debugConsoleEnabled) {
        debugConsole = createDebugConsole(engine, rootObject);
    } else {
        qDebug() << "[Main] Debug console is disabled in settings - skipping creation";
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
    qDebug() << "[Main] WindowFrameHelper installed as native event filter";
#endif
    
    // Run diagnostics (only in DEBUG builds)
#ifdef DEBUG
    if (debugConsole) {
        runDiagnostics(rootObject, debugConsole);
    }
#endif
    
    // Add main window to pool
    windowManager.addMainWindow(rootObject);
    
    // Set debug console reference in main window
    if (debugConsole && rootObject) {
        rootObject->setProperty("debugConsole", QVariant::fromValue(debugConsole));
        // Note: QML function signature is logToDebugConsole(QVariant, QVariant)
        QMetaObject::invokeMethod(rootObject, "logToDebugConsole", 
            Qt::QueuedConnection,
            Q_ARG(QVariant, QVariant("[Main] Debug console connected from C++")), 
            Q_ARG(QVariant, QVariant("info")));
    }
    
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
    
    return app.exec();
}
