#!/bin/sh
set -e
cd "$(dirname "$0")/.."
out="$(mktemp -d)/generate-wordmark"
swiftc -O \
  Tools/GenerateWordmarkAsset.swift \
  Signu/DesignSystem/Theme.swift \
  Signu/DesignSystem/Typography.swift \
  Signu/DesignSystem/Components/SignuWordmark.swift \
  -o "$out"
"$out"
