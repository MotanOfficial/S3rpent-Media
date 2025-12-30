.pragma library

/**
 * ImageNavigationUtils.js
 * Utility functions for image navigation and directory management
 */

/**
 * Load images from the directory containing the given image URL
 * @param {url} imageUrl - The URL of the current image
 * @param {function} getImagesInDirectory - Function to get images from directory (from ColorUtils)
 * @returns {Object} Object with directoryImages array and currentImageIndex
 */
function loadDirectoryImages(imageUrl, getImagesInDirectory) {
    if (!imageUrl || imageUrl === "" || !getImagesInDirectory) {
        return { directoryImages: [imageUrl], currentImageIndex: 0 }
    }
    
    const images = getImagesInDirectory(imageUrl)
    if (images && images.length > 0) {
        // Find current image index
        // Normalize URLs by decoding URL-encoded characters for comparison
        // This handles URL encoding differences (e.g., %20 vs space, %E2%80%93 vs special chars)
        function normalizeUrl(url) {
            var urlStr = url.toString()
            // Decode URL-encoded characters
            try {
                urlStr = decodeURIComponent(urlStr.replace(/^file:\/\//, ''))
            } catch (e) {
                // If decoding fails, try without the file:// prefix
                urlStr = urlStr.replace(/^file:\/\//, '')
            }
            // Normalize path separators and make case-insensitive for Windows
            return urlStr.replace(/\\/g, '/').toLowerCase()
        }
        
        const currentPath = normalizeUrl(imageUrl)
        let currentIndex = 0
        
        for (let i = 0; i < images.length; i++) {
            const imagePath = normalizeUrl(images[i])
            
            // Compare normalized paths
            if (imagePath === currentPath) {
                currentIndex = i
                break
            }
        }
        return { directoryImages: images, currentImageIndex: currentIndex }
    } else {
        return { directoryImages: [imageUrl], currentImageIndex: 0 }
    }
}

/**
 * Calculate the next image index with wrap-around
 * @param {number} currentIndex - Current image index
 * @param {number} totalImages - Total number of images
 * @returns {number} Next image index
 */
function getNextImageIndex(currentIndex, totalImages) {
    if (totalImages === 0) return 0
    return (currentIndex + 1) % totalImages
}

/**
 * Calculate the previous image index with wrap-around
 * @param {number} currentIndex - Current image index
 * @param {number} totalImages - Total number of images
 * @returns {number} Previous image index
 */
function getPreviousImageIndex(currentIndex, totalImages) {
    if (totalImages === 0) return 0
    return (currentIndex - 1 + totalImages) % totalImages
}

/**
 * Calculate navigation index with bounds checking and wrap-around
 * @param {number} index - Desired index
 * @param {number} totalImages - Total number of images
 * @returns {number} Valid image index (wrapped if needed)
 */
function getValidImageIndex(index, totalImages) {
    if (totalImages === 0) return 0
    // Wrap around navigation
    if (index < 0) return totalImages - 1
    if (index >= totalImages) return 0
    return index
}

