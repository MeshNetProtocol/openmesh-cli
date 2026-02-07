#!/bin/bash
# Flatten gomobile-generated framework layout for iOS, without leaving backup bundles.

set -eu

FRAMEWORK_DIR="${1:-}"
if [ -z "$FRAMEWORK_DIR" ]; then
    echo "Usage: $0 <framework_directory>"
    exit 1
fi

if [ ! -d "$FRAMEWORK_DIR/Versions/A" ]; then
    echo "Skip flatten (Versions/A not found): $FRAMEWORK_DIR"
    exit 0
fi

echo "Flatten framework layout: $FRAMEWORK_DIR"

TMP_DIR="$(mktemp -d "${FRAMEWORK_DIR}.flatten.XXXXXX")"
cp -R "$FRAMEWORK_DIR/Versions/A/"* "$TMP_DIR/"

# iOS framework root should contain Info.plist (shallow layout for App Store validation).
if [ -f "$TMP_DIR/Resources/Info.plist" ]; then
    cp -f "$TMP_DIR/Resources/Info.plist" "$TMP_DIR/Info.plist"
fi

rm -rf "$FRAMEWORK_DIR"
mv "$TMP_DIR" "$FRAMEWORK_DIR"

echo "Flatten done: $FRAMEWORK_DIR"
