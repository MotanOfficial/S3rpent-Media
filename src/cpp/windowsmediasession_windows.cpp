#include "windowsmediasession.h"
#include <QDebug>
#include <QImage>
#include <QBuffer>
#include <QByteArray>
#include <QImageReader>
#include <QFileInfo>
#include <QDir>
#include <QStandardPaths>
#include <QFile>
#include <string>

#ifdef Q_OS_WIN
#ifdef _MSC_VER
// C++/WinRT headers (modern approach)
// Include WinRT headers FIRST to get types before windows.h pollutes namespaces
#include <winrt/base.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Media.Playback.h>
#include <winrt/Windows.Media.Core.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.System.h>
#include <chrono>

// Create namespace alias BEFORE including windows.h to avoid conflicts
namespace wr = winrt::Windows;

// Global DispatcherQueue for WinRT operations (initialized once on GUI thread)
static winrt::Windows::System::DispatcherQueue g_dispatcher{ nullptr };
static winrt::Windows::System::DispatcherQueueController g_dispatcherController{ nullptr };

// Now include windows.h and other headers
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <dispatcherqueue.h> // For CreateDispatcherQueueController

// The header dispatcherqueue.h defines DispatcherQueueOptions (not DISPATCHERQUEUE_OPTIONS)
// Constants are defined in the header as well

#include <QWindow>
#include <QQuickWindow>

// Helper struct to store WinRT MediaPlayer (SMTC owner) and SMTC
// CRITICAL: MediaPlayer is used ONLY to get SMTC (works in Qt/Win32)
// MediaPlayer is muted - no silent WAV needed, just use it to host SMTC
struct WinRTData {
    winrt::Windows::Media::Playback::MediaPlayer player{ nullptr };
    winrt::Windows::Media::SystemMediaTransportControls smtc{ nullptr };
    winrt::event_token buttonToken{};

    WinRTData() = default;
    ~WinRTData() {
        if (smtc && buttonToken) {
            try {
                smtc.ButtonPressed(buttonToken);
            } catch (...) {
                // Ignore errors during cleanup
            }
        }
        smtc = nullptr;
        player = nullptr;
    }
};

#endif // _MSC_VER

// These functions are always defined for Windows, but with different implementations
// based on whether we're using MSVC (WinRT) or MinGW (QMediaPlayer fallback)

void WindowsMediaSession::initializeWindowsMediaSession()
{
#ifdef _MSC_VER
    // Don't manually initialize WinRT apartment - Qt already initializes STA
    // MediaPlayer works fine with Qt's STA threading model
    
    // Initialize global DispatcherQueue if not already done
    if (!g_dispatcher) {
        try {
            // Create dispatcher if this thread doesn't already have one
            if (!winrt::Windows::System::DispatcherQueue::GetForCurrentThread()) {
                // Use DispatcherQueueOptions struct (defined in dispatcherqueue.h)
                DispatcherQueueOptions options{};
                options.dwSize = sizeof(DispatcherQueueOptions);
                options.threadType = DQTYPE_THREAD_CURRENT;
                options.apartmentType = DQTAT_COM_STA;
                
                ABI::Windows::System::IDispatcherQueueController* controllerPtr = nullptr;
                winrt::check_hresult(CreateDispatcherQueueController(
                    options,
                    &controllerPtr
                ));
                
                // Store controller globally to keep it alive
                g_dispatcherController = winrt::Windows::System::DispatcherQueueController{ controllerPtr, winrt::take_ownership_from_abi };
            }
            
            g_dispatcher = winrt::Windows::System::DispatcherQueue::GetForCurrentThread();
            if (g_dispatcher) {
                qDebug() << "[WindowsMediaSession] Global DispatcherQueue initialized";
            } else {
                qDebug() << "[WindowsMediaSession] Failed to get DispatcherQueue after creation";
            }
        }
        catch (const winrt::hresult_error& ex) {
            qDebug() << "[WindowsMediaSession] Failed to initialize DispatcherQueue:" << ex.code() << ex.message().c_str();
        }
        catch (...) {
            qDebug() << "[WindowsMediaSession] Unknown error initializing DispatcherQueue";
        }
    }
    
    // Note: We can't get SystemMediaTransportControls here because we don't have a window yet
    // Call initializeWithWindow() after the window is created
    qDebug() << "[WindowsMediaSession] Ready. Call initializeWithWindow() after window creation.";
#else
    // MinGW fallback - use QMediaPlayer approach
    // LIMITATION: Qt 6's QMediaPlayer does NOT automatically integrate with Windows Media Session
    // for keyboard controls. It only exposes metadata from the file, not custom metadata.
    // For full Windows integration (custom metadata + keyboard controls), MSVC compiler is required
    // to use WinRT APIs (SystemMediaTransportControls).
    m_windowsSessionInitialized = true;
    qDebug() << "[WindowsMediaSession] Using QMediaPlayer-based Windows integration (MinGW)";
    qDebug() << "[WindowsMediaSession] WARNING: With MinGW, Windows keyboard controls and custom metadata are NOT available";
    qDebug() << "[WindowsMediaSession] Only file metadata from QMediaPlayer will be visible to Windows";
    qDebug() << "[WindowsMediaSession] To enable full Windows integration, compile with MSVC compiler";
#endif
}

void WindowsMediaSession::cleanupWindowsMediaSession()
{
#ifdef _MSC_VER
    WinRTData* winrtData = reinterpret_cast<WinRTData*>(m_systemControls);
    if (winrtData) {
        qDebug() << "[WindowsMediaSession] Cleaning up MediaPlayer and SMTC";
        try {
            // Remove event handler (in C++/WinRT, you call the same method with the token to remove)
            if (winrtData->smtc && winrtData->buttonToken) {
                winrtData->smtc.ButtonPressed(winrtData->buttonToken);
            }
        }
        catch (...) {
            // Ignore errors during cleanup
        }
        
        winrtData->smtc = nullptr;
        winrtData->player = nullptr;
        delete winrtData;
        m_systemControls = nullptr;
    }
#endif
    
    m_windowsSessionInitialized = false;
    qDebug() << "[WindowsMediaSession] Windows Media Session cleaned up";
}

void WindowsMediaSession::updateWindowsMediaSessionMetadata()
{
    if (!m_windowsSessionInitialized) {
        return;
    }
    
#ifdef _MSC_VER
    WinRTData* winrtData = reinterpret_cast<WinRTData*>(m_systemControls);
    if (!winrtData || !winrtData->smtc) {
        return;
    }
    
    try {
        // Use SMTC from MediaPlayer (MediaPlayer owns the session, works in Qt/Win32)
        auto smtc = winrtData->smtc;
        auto updater = smtc.DisplayUpdater();
        
        // IMPORTANT: Set the type to Music (Windows sometimes ignores metadata without this)
        updater.Type(winrt::Windows::Media::MediaPlaybackType::Music);
        
        // Get music properties
        auto music = updater.MusicProperties();
        
        // Set title
        if (!m_title.isEmpty()) {
            music.Title(winrt::hstring(m_title.toStdWString()));
            qDebug() << "[WindowsMediaSession] Set title:" << m_title;
        }
        
        // Set artist (clean up semicolons - Windows expects comma-separated or single artist)
        if (!m_artist.isEmpty()) {
            QString cleanArtist = m_artist;
            // Replace semicolons with commas for better Windows compatibility
            cleanArtist.replace(";", ",");
            music.Artist(winrt::hstring(cleanArtist.toStdWString()));
            qDebug() << "[WindowsMediaSession] Set artist:" << cleanArtist << "(original:" << m_artist << ")";
        }
        
        // Set album
        if (!m_album.isEmpty()) {
            music.AlbumTitle(winrt::hstring(m_album.toStdWString()));
        }
        
        // Set thumbnail/cover art on the updater
        // Must copy to trusted location and use StorageFile (CreateFromUri doesn't work for local files)
        if (!m_thumbnail.isEmpty()) {
            try {
                QString sourcePath;
                if (m_thumbnail.isLocalFile()) {
                    sourcePath = m_thumbnail.toLocalFile();
                } else if (m_thumbnail.scheme() == "file") {
                    sourcePath = m_thumbnail.toLocalFile();
                }
                
                if (!sourcePath.isEmpty() && QFileInfo::exists(sourcePath)) {
                    // Copy cover to trusted app data location (not TEMP - Windows ignores TEMP)
                    QString coverDir = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation) + "/covers";
                    QDir().mkpath(coverDir);
                    
                    QString coverPath = coverDir + "/current_cover.jpg";
                    QFile::remove(coverPath); // Remove old cover if exists
                    
                    if (QFile::copy(sourcePath, coverPath)) {
                        // Convert to Windows native path format
                        QString nativePath = QDir::toNativeSeparators(coverPath);
                        
                        // Use global DispatcherQueue (initialized once on GUI thread)
                        if (!g_dispatcher) {
                            qDebug() << "[WindowsMediaSession] Global DispatcherQueue not initialized - cannot set thumbnail";
                            return;
                        }
                        
                        // Fire-and-forget async approach (no blocking, no mutex, no .get())
                        // Capture winrtData pointer to access MediaPlayer (must remain valid)
                        WinRTData* winrtDataPtr = winrtData;
                        QString nativePathCopy = nativePath; // Copy for async lambda
                        
                        g_dispatcher.TryEnqueue([=]() mutable {
                            try {
                                auto fileOp = winrt::Windows::Storage::StorageFile::GetFileFromPathAsync(
                                    winrt::hstring(nativePathCopy.toStdWString())
                                );
                                
                                fileOp.Completed([=](auto const& asyncOp, auto) {
                                    try {
                                        auto file = asyncOp.GetResults();
                                        auto thumbnail = winrt::Windows::Storage::Streams::RandomAccessStreamReference::CreateFromFile(file);
                                        
                                        // Get updater from SMTC (winrtData must still be valid)
                                        if (winrtDataPtr && winrtDataPtr->smtc) {
                                            auto smtc = winrtDataPtr->smtc;
                                            auto updater = smtc.DisplayUpdater();
                                            updater.Thumbnail(thumbnail);
                                            updater.Update();
                                            
                                            qDebug() << "[WindowsMediaSession] Thumbnail set successfully from:" << nativePathCopy;
                                        } else {
                                            qDebug() << "[WindowsMediaSession] SMTC no longer valid when thumbnail ready";
                                        }
                                    }
                                    catch (const winrt::hresult_error& ex) {
                                        qDebug() << "[WindowsMediaSession] Failed to apply thumbnail:" << ex.code() << ex.message().c_str();
                                    }
                                    catch (...) {
                                        qDebug() << "[WindowsMediaSession] Unknown error applying thumbnail";
                                    }
                                });
                            }
                            catch (const winrt::hresult_error& ex) {
                                qDebug() << "[WindowsMediaSession] Failed to start thumbnail async operation:" << ex.code() << ex.message().c_str();
                            }
                            catch (...) {
                                qDebug() << "[WindowsMediaSession] Unknown error starting thumbnail async operation";
                            }
                        });
                        
                        qDebug() << "[WindowsMediaSession] Thumbnail update queued (async):" << coverPath;
                    } else {
                        qDebug() << "[WindowsMediaSession] Failed to copy thumbnail to trusted location";
                    }
                } else {
                    qDebug() << "[WindowsMediaSession] Thumbnail source file not found:" << sourcePath;
                }
            }
            catch (const winrt::hresult_error& ex) {
                qDebug() << "[WindowsMediaSession] Failed to set thumbnail:" << ex.code() << ex.message().c_str();
            }
            catch (...) {
                qDebug() << "[WindowsMediaSession] Unknown error setting thumbnail";
            }
        }
        
        // Update the display (must be called AFTER setting all properties including thumbnail)
        updater.Update();
        
        qDebug() << "[WindowsMediaSession] Metadata updated:" << m_title << "-" << m_artist;
    }
    catch (winrt::hresult_error const& ex) {
        qDebug() << "[WindowsMediaSession] Failed to update metadata:" << ex.code() << ex.message().c_str();
    }
    catch (...) {
        qDebug() << "[WindowsMediaSession] Unknown error updating metadata";
    }
#else
    // MinGW fallback - metadata is handled by QMediaPlayer
    // Custom metadata won't be available, but file metadata will be
    qDebug() << "[WindowsMediaSession] Metadata update (MinGW - using QMediaPlayer):" << m_title << "-" << m_artist;
#endif
}

void WindowsMediaSession::updateWindowsMediaSessionPlaybackState()
{
    if (!m_windowsSessionInitialized) {
        return;
    }
    
#ifdef _MSC_VER
    WinRTData* winrtData = reinterpret_cast<WinRTData*>(m_systemControls);
    if (!winrtData || !winrtData->smtc) {
        return;
    }
    
    try {
        // CRITICAL: Keep MediaPlayer in Playing state to prevent session from disappearing
        // When paused, Windows hides the session if MediaPlayer is paused
        // Solution: Keep MediaPlayer playing (muted) and only set SMTC status to Paused
        // This keeps the session visible while showing correct playback state
        if (m_playbackStatus == 1) {
            // Playing - ensure MediaPlayer is in Playing state
            winrtData->player.Play();
        } else {
            // Paused or Stopped - keep MediaPlayer playing (muted) to keep session visible
            // Only the SMTC status will reflect the actual paused state
            if (winrtData->player.CurrentState() != winrt::Windows::Media::Playback::MediaPlayerState::Playing) {
                winrtData->player.Play();
            }
        }
        
        // Update SMTC status to reflect actual playback state
        // MediaPlayer stays playing (muted) but SMTC shows correct state
        auto smtc = winrtData->smtc;
        wr::Media::MediaPlaybackStatus status;
        if (m_playbackStatus == 1) {
            status = wr::Media::MediaPlaybackStatus::Playing;
        } else if (m_playbackStatus == 2) {
            status = wr::Media::MediaPlaybackStatus::Paused;
        } else {
            status = wr::Media::MediaPlaybackStatus::Stopped;
        }
        
        smtc.PlaybackStatus(status);
        qDebug() << "[WindowsMediaSession] Playback status updated:" << m_playbackStatus << "(MediaPlayer stays playing to keep session visible)";
    }
    catch (winrt::hresult_error const& ex) {
        qDebug() << "[WindowsMediaSession] Failed to update playback status:" << ex.code() << ex.message().c_str();
    }
    catch (...) {
        qDebug() << "[WindowsMediaSession] Unknown error updating playback status";
    }
#else
    // MinGW fallback - playback state is handled by QMediaPlayer
    // The session player's state should sync automatically
#endif
}

void WindowsMediaSession::updateWindowsMediaSessionTimeline()
{
    if (!m_windowsSessionInitialized) {
        return;
    }
    
#ifdef _MSC_VER
    WinRTData* winrtData = reinterpret_cast<WinRTData*>(m_systemControls);
    if (!winrtData || !winrtData->smtc) {
        return;
    }
    
    try {
        // CRITICAL: When using SMTC directly, you MUST update timeline properties yourself
        // This is the working method that provides full timeline control
        auto smtc = winrtData->smtc;
        
        winrt::Windows::Media::SystemMediaTransportControlsTimelineProperties timeline{};
        timeline.Position(std::chrono::milliseconds(m_position));
        timeline.MinSeekTime(std::chrono::milliseconds(0));
        timeline.MaxSeekTime(std::chrono::milliseconds(m_duration));
        
        smtc.UpdateTimelineProperties(timeline);
        
        qDebug() << "[WindowsMediaSession] Timeline updated:" << m_position << "/" << m_duration << "ms";
    }
    catch (winrt::hresult_error const& ex) {
        qDebug() << "[WindowsMediaSession] Failed to update timeline:" << ex.code() << ex.message().c_str();
    }
    catch (...) {
        qDebug() << "[WindowsMediaSession] Unknown error updating timeline";
    }
#else
    // MinGW fallback - timeline is handled by QMediaPlayer
#endif
}

void WindowsMediaSession::initializeWithWindow(QObject* window)
{
#ifdef _MSC_VER
    // CRITICAL: Check if MediaPlayer already exists (not just the flag)
    // MediaPlayer must be created ONCE and NEVER replaced during playback
    WinRTData* existingData = reinterpret_cast<WinRTData*>(m_systemControls);
    if (existingData && existingData->player && existingData->smtc) {
        qDebug() << "[WindowsMediaSession] MediaPlayer and SMTC already exist - skipping initialization";
        return;
    }
    
    if (m_windowsSessionInitialized) {
        qDebug() << "[WindowsMediaSession] WARNING: Flag says initialized but MediaPlayer doesn't exist - this should never happen!";
        m_windowsSessionInitialized = false;
    }
    
    Q_UNUSED(window); // MediaPlayer doesn't need HWND - it works automatically in Qt/Win32
    
    // Allocate WinRT data structure
    WinRTData* winrtData = new WinRTData();
    m_systemControls = winrtData;
    
    try {
        // CRITICAL: Create MediaPlayer to get SMTC (this works reliably in Qt/Win32)
        // MediaPlayer is muted - no silent WAV needed, just use it to host SMTC
        winrtData->player = winrt::Windows::Media::Playback::MediaPlayer();
        winrtData->player.Volume(0.0); // Mute - we don't want audio from this player
        winrtData->player.CommandManager().IsEnabled(true); // Enable media keys
        
        // CRITICAL: Windows does NOT activate a media session unless MediaPlayer has a Source
        // Create an empty in-memory stream (no audio, no disk access, no CPU overhead)
        // This is required for SMTC to actually work (metadata, controls, timeline)
        auto emptyStream = winrt::Windows::Storage::Streams::InMemoryRandomAccessStream();
        winrtData->player.Source(
            winrt::Windows::Media::Core::MediaSource::CreateFromStream(emptyStream, L"audio/wav")
        );
        
        // CRITICAL: Windows ignores metadata unless MediaPlayer is in Playing state
        // Call Play() at least once to activate the session (Volume is 0, so no sound)
        // Then immediately pause to prevent wallpaper pausing (like Spotify does)
        winrtData->player.Play();
        winrtData->player.Pause();
        
        // Get SMTC from MediaPlayer (this works in Qt/Win32, unlike GetForCurrentView)
        winrtData->smtc = winrtData->player.SystemMediaTransportControls();
        
        if (!winrtData->smtc) {
            qDebug() << "[WindowsMediaSession] Failed to get SystemMediaTransportControls from MediaPlayer";
            delete winrtData;
            m_systemControls = nullptr;
            return;
        }
        
        // Enable controls
        auto smtc = winrtData->smtc;
        smtc.IsEnabled(true);
        smtc.IsPlayEnabled(true);
        smtc.IsPauseEnabled(true);
        smtc.IsStopEnabled(true);
        smtc.IsNextEnabled(true);
        smtc.IsPreviousEnabled(true);
        
        // CRITICAL: Disable FastForward/Rewind to prevent Windows from polling position
        // If FF/RW are enabled, Windows assumes timeline support and polls position constantly
        smtc.IsFastForwardEnabled(false);
        smtc.IsRewindEnabled(false);
        
        // Register event handler for media key presses
        winrtData->buttonToken = smtc.ButtonPressed(
            [this](auto const&, winrt::Windows::Media::SystemMediaTransportControlsButtonPressedEventArgs const& e)
            {
                switch (e.Button()) {
                    case winrt::Windows::Media::SystemMediaTransportControlsButton::Play:
                        qDebug() << "[WindowsMediaSession] Play button pressed";
                        emit playRequested();
                        break;
                    case winrt::Windows::Media::SystemMediaTransportControlsButton::Pause:
                        qDebug() << "[WindowsMediaSession] Pause button pressed";
                        emit pauseRequested();
                        break;
                    case winrt::Windows::Media::SystemMediaTransportControlsButton::Stop:
                        qDebug() << "[WindowsMediaSession] Stop button pressed";
                        emit stopRequested();
                        break;
                    case winrt::Windows::Media::SystemMediaTransportControlsButton::Next:
                        qDebug() << "[WindowsMediaSession] Next button pressed";
                        emit nextRequested();
                        break;
                    case winrt::Windows::Media::SystemMediaTransportControlsButton::Previous:
                        qDebug() << "[WindowsMediaSession] Previous button pressed";
                        emit previousRequested();
                        break;
                    // DO NOT handle FastForward or Rewind - this prevents Windows from polling position
                    case winrt::Windows::Media::SystemMediaTransportControlsButton::FastForward:
                    case winrt::Windows::Media::SystemMediaTransportControlsButton::Rewind:
                        // Ignore - we don't support timeline seeking
                        break;
                    default:
                        break;
                }
            });
        
        m_windowsSessionInitialized = true;
        qDebug() << "[WindowsMediaSession] MediaPlayer initialized - SMTC ready (works in Qt/Win32)";
        
        // CRITICAL: Update metadata and playback state AFTER Play() was called
        // Windows ignores metadata unless MediaPlayer has transitioned to Playing state at least once
        // Order matters - metadata first, then playback state
        if (!m_title.isEmpty() || !m_artist.isEmpty()) {
            updateWindowsMediaSessionMetadata();
        }
        updateWindowsMediaSessionPlaybackState();
    }
    catch (const winrt::hresult_error& e) {
        qDebug() << "[WindowsMediaSession] WinRT error:" << e.code() << e.message().c_str();
        delete winrtData;
        m_systemControls = nullptr;
        m_windowsSessionInitialized = false;
    }
    catch (...) {
        qDebug() << "[WindowsMediaSession] Unknown error initializing MediaPlayer";
        delete winrtData;
        m_systemControls = nullptr;
        m_windowsSessionInitialized = false;
    }
#else
    Q_UNUSED(window);
    qDebug() << "[WindowsMediaSession] initializeWithWindow() called but not using MSVC - WinRT not available";
#endif
}

#endif // Q_OS_WIN
