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
#include <QPointer>
#include <QTranslator>
#include <QLocale>
#include <QStandardPaths>
#include <QDir>
#include <QSettings>
#include <QCoreApplication>
#include <QFile>
#include <optional>

#include "colorutils.h"
#include "wmfvideoplayer.h"
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
    // Set style before creating QApplication (Qt recommendation)
    // Note: High DPI scaling is automatically enabled in Qt 6.10.1+
    QQuickStyle::setStyle("Basic");
    
    QApplication app(argc, argv);
    
    // Initialize application
    initApplication(app);
    
    // Load application language setting
    QSettings settings;
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
    
    // Create debug console
    QObject *debugConsole = createDebugConsole(engine, rootObject);
    
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
