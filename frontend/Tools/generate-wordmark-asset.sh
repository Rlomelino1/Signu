#!/bin/sh
# Regenerates Signu/Assets.xcassets/Wordmark.imageset from SignuWordmark.
# Run from the frontend/ directory. See GenerateWordmarkAsset.swift for why
# the launch screen needs a rendered image rather than storyboard views.
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
