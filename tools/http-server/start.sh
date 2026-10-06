#!/bin/sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FILES_DIR="$SCRIPT_DIR/files"

mkdir -p "$FILES_DIR"

for size in 1 10 100 1000; do
    file="$FILES_DIR/${size}mb.bin"
    if [ ! -f "$file" ]; then
        echo "Creating ${size}mb.bin..."
        dd if=/dev/urandom of="$file" bs=1M count="$size" 2>/dev/null
    fi
done

exec python3 "$SCRIPT_DIR/server.py" "$@"
