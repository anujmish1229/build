#!/usr/bin/env bash
# Makes the personal-use IKEA catalogue and starter Board in catalog-local/, which is gitignored.
# The next scripts/build_device.sh then builds them into your phone's copy of the app.
#   scripts/build_ikea_catalog.sh path/to/IKEA_product_catalog.csv [region]
# Download the CSV from kaggle.com/datasets/ranjithpanicker/ikea-global-product-catalog-and-price-2026.
# The dataset has no licence: never commit the output or put it in a public build.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! xcodebuild -version >/dev/null 2>&1; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

CSV="${1:?Give the path to IKEA_product_catalog.csv}"
REGION="${2:-CA}"
mkdir -p catalog-local
python3 tools/ikea_kaggle_to_catalog.py "$CSV" catalog-local/ikea-global.json

# Lays the starter designs out now, on the Mac, so the first launch on the phone needs no solving.
(cd ios/PoltarKit && \
  LOCAL_CATALOG="$PWD/../../catalog-local/ikea-global.json" \
  LOCAL_STARTER_OUT="$PWD/../../catalog-local/ikea-starter.json" \
  LOCAL_REGION="$REGION" \
  swift test -c release -Xswiftc -enable-testing --filter LocalCatalogTests 2>&1 | grep -E 'error:|✘|Test run with|local catalogue:' || true)

test -s catalog-local/ikea-starter.json
git check-ignore -q catalog-local/ikea-global.json
git check-ignore -q catalog-local/ikea-starter.json
echo "Done. Now run scripts/build_device.sh --install"
