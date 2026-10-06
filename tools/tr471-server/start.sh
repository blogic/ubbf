#!/bin/sh
set -e

REPO_URL="https://github.com/BroadbandForum/obudpst.git"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
BUILD_DIR="$SRC_DIR/build"
BINARY="$BUILD_DIR/udpst"

if [ ! -d "$SRC_DIR" ]; then
    git clone "$REPO_URL" "$SRC_DIR"
fi

if [ ! -x "$BINARY" ]; then
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    cmake ..
    make
fi

if [ ! -x "$BINARY" ]; then
    echo "Build failed: $BINARY not found"
    exit 1
fi

exec "$BINARY" -s "$@"
