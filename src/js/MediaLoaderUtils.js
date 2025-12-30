.pragma library

/**
 * MediaLoaderUtils.js
 * Utility functions for loading and unloading media viewers
 */

/**
 * Force reload a loader by setting active to false then true
 * This ensures the component is recreated
 * @param {Object} loader - Loader component
 */
function forceReloadLoader(loader) {
    if (loader) {
        loader.active = false
        loader.active = true
    }
}

/**
 * Unload a loader
 * @param {Object} loader - Loader component
 */
function unloadLoader(loader) {
    if (loader) {
        loader.active = false
    }
}

/**
 * Stop and clear a media player before unloading
 * @param {Object} playerItem - Player component item
 */
function stopAndClearPlayer(playerItem) {
    if (playerItem) {
        if (typeof playerItem.stop === "function") {
            playerItem.stop()
        }
        if (playerItem.source !== undefined) {
            playerItem.source = ""
        }
    }
}

