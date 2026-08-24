#!/bin/sh
set -e
cd "$(dirname "$0")/.."
out="$(mktemp -d)/generate-bootmark"
swiftc -O \
  Tools/GenerateBootMarkAsset.swift \
  Signu/DesignSystem/Theme.swift \
  Signu/DesignSystem/Components/SignuArcsMark.swift \
  -o "$out"
"$out"
