#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
    GAME="$HOME/Library/Application Support/Hytale/install/release/package/game/latest/Client/Hytale.app/Contents/Resources/Data"
    TARGET="$GAME"
fi

swift run uivalidate --catalog "$TARGET" Sources/HytaleUICore/CorpusCatalog.swift
echo "Regenerated CorpusCatalog.swift from $TARGET"
