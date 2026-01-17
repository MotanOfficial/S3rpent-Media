#!/usr/bin/env python3
"""
Extract Bad Apple!! frames from video and convert to binary format for shader use.
Requires: ffmpeg, PIL (Pillow)
"""

import subprocess
import os
import sys
from pathlib import Path

# Configuration
VIDEO_FILE = "BadApple.mp4"
OUTPUT_DIR = "badapple_frames"
FRAME_WIDTH = 64
FRAME_HEIGHT = 48
TOTAL_FRAMES = 6572  # Bad Apple!! has 6572 frames at 30 FPS

def check_ffmpeg():
    """Check if FFmpeg is available"""
    try:
        subprocess.run(["ffmpeg", "-version"], capture_output=True, check=True)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False

def extract_frames():
    """Extract frames from video using FFmpeg"""
    print(f"Extracting frames from {VIDEO_FILE}...")
    
    # Create output directory
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    # Extract frames as PNGs (scaled to 64x48)
    cmd = [
        "ffmpeg",
        "-i", VIDEO_FILE,
        "-vf", f"scale={FRAME_WIDTH}:{FRAME_HEIGHT}",
        "-frames:v", str(TOTAL_FRAMES),
        f"{OUTPUT_DIR}/frame_%04d.png"
    ]
    
    try:
        subprocess.run(cmd, check=True, capture_output=True)
        print(f"✓ Extracted frames to {OUTPUT_DIR}/")
        return True
    except subprocess.CalledProcessError as e:
        print(f"✗ FFmpeg error: {e.stderr.decode()}")
        return False

def convert_to_binary():
    """Convert PNG frames to binary format (1 bit per pixel)"""
    try:
        from PIL import Image
    except ImportError:
        print("✗ PIL (Pillow) not installed. Install with: pip install Pillow")
        return False
    
    print("Converting frames to binary format...")
    
    binary_file = "badapple_frames.bin"
    frame_size = (FRAME_WIDTH * FRAME_HEIGHT + 7) // 8  # Bytes per frame (rounded up)
    
    with open(binary_file, "wb") as f:
        for i in range(1, TOTAL_FRAMES + 1):
            frame_path = f"{OUTPUT_DIR}/frame_{i:04d}.png"
            
            if not os.path.exists(frame_path):
                print(f"⚠ Frame {i} not found, skipping...")
                # Write empty frame
                f.write(b'\x00' * frame_size)
                continue
            
            # Load and convert to binary
            img = Image.open(frame_path).convert("L")  # Grayscale
            pixels = img.load()
            
            # Convert to binary: white (>128) = 1, black (<=128) = 0
            frame_bytes = bytearray(frame_size)
            byte_idx = 0
            bit_idx = 0
            
            for y in range(FRAME_HEIGHT):
                for x in range(FRAME_WIDTH):
                    pixel_value = pixels[x, y]
                    if pixel_value > 128:  # White pixel
                        frame_bytes[byte_idx] |= (1 << (7 - bit_idx))
                    
                    bit_idx += 1
                    if bit_idx >= 8:
                        bit_idx = 0
                        byte_idx += 1
            
            f.write(frame_bytes)
            
            if (i % 100) == 0:
                print(f"  Processed {i}/{TOTAL_FRAMES} frames...")
    
    print(f"✓ Created binary file: {binary_file}")
    print(f"  Size: {os.path.getsize(binary_file) / 1024 / 1024:.2f} MB")
    return True

def main():
    if not os.path.exists(VIDEO_FILE):
        print(f"✗ Video file not found: {VIDEO_FILE}")
        return 1
    
    if not check_ffmpeg():
        print("✗ FFmpeg not found. Please install FFmpeg first.")
        return 1
    
    if not extract_frames():
        return 1
    
    if not convert_to_binary():
        return 1
    
    print("\n✓ Frame extraction complete!")
    print(f"  Binary file: badapple_frames.bin")
    print(f"  Frame size: {FRAME_WIDTH}x{FRAME_HEIGHT}")
    print(f"  Total frames: {TOTAL_FRAMES}")
    return 0

if __name__ == "__main__":
    sys.exit(main())

