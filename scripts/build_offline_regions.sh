#!/bin/bash

# ==============================================================================
# Regional Map Data Builder
# ------------------------------------------------------------------------------
# This script automates the process of:
# 1. Downloading OSM PBF data from Geofabrik.
# 2. Building Valhalla routing tiles (.tar) and configuration (.json).
# 3. Generating MBTiles vector tiles using tilemaker.
# ==============================================================================

set -e # Exit on error

# Configuration
STATES=("gujarat" "maharashtra" "rajasthan" "karnataka")
BASE_URL="https://download.geofabrik.de/asia/india/"

# Output directories
RAW_DIR="data/raw"
TILE_DIR_ROOT="data/valhalla_tiles"
OUTPUT_DIR="assets/offline_data"

# Create necessary directories
mkdir -p "$RAW_DIR" "$TILE_DIR_ROOT" "$OUTPUT_DIR/maps" "$OUTPUT_DIR/routing" "$OUTPUT_DIR/config"

echo "🚀 Starting regional data build for ${#STATES[@]} states..."

for state in "${STATES[@]}"
do
   echo ""
   echo "============================================================"
   echo "🔹 Processing State: $(echo "$state" | tr '[:lower:]' '[:upper:]')"
   echo "============================================================"

   PBF_FILE="${RAW_DIR}/${state}-latest.osm.pbf"
   MBTILES_OUT="${OUTPUT_DIR}/maps/${state}.mbtiles"
   TAR_OUT="${OUTPUT_DIR}/routing/${state}.tar"
   JSON_OUT="${OUTPUT_DIR}/config/${state}.json"
   TEMP_TILE_DIR="${TILE_DIR_ROOT}/${state}"

   # 1. Download OSM Data (if not already present)
   if [ ! -f "$PBF_FILE" ]; then
       echo "📥 Downloading $PBF_FILE..."
       curl -L -o "$PBF_FILE" "${BASE_URL}${state}-latest.osm.pbf"
   else
       echo "✅ OSM PBF already exists, skipping download."
   fi

   # 2. Valhalla Build (Routing Engine Data)
   # We generate a separate config for each state to keep them isolated.
   echo "🛣️ Building Valhalla Tiles..."
   
   mkdir -p "$TEMP_TILE_DIR"
   
   # Step 2a: Generate Valhalla Configuration
   # We specify the tile directory and the target tar extract location.
   valhalla_build_config --mjolnir-tile-dir "$(pwd)/$TEMP_TILE_DIR" \
                         --mjolnir-tile-extract "$(pwd)/$TAR_OUT" \
                         --mjolnir-timezone "" \
                         --mjolnir-admin "" > "$JSON_OUT"
   
   # Step 2b: Build the graph tiles
   valhalla_build_tiles -c "$JSON_OUT" "$PBF_FILE"
   
   # Step 2c: Pack the tiles into an extract (.tar) for the app to use
   valhalla_build_extract -c "$JSON_OUT" -o "$TAR_OUT"

   # 3. MBTiles Build (Vector Visuals)
   # Uses tilemaker to convert OSM to Vector Tiles.
   echo "🗺️ Generating MBTiles via tilemaker..."
   if command -v tilemaker >/dev/null 2>&1; then
       tilemaker --input "$PBF_FILE" --output "$MBTILES_OUT"
   else
       echo "⚠️ tilemaker not found! Skipping MBTiles generation."
   fi

   echo "✅ COMPLETED: $state"
done

echo ""
echo "🎉 ALL DONE!"
echo "------------------------------------------------------------"
echo "Outputs generated in $OUTPUT_DIR:"
echo "  - Maps (.mbtiles): $OUTPUT_DIR/maps/"
echo "  - Routing (.tar):  $OUTPUT_DIR/routing/"
echo "  - Configs (.json): $OUTPUT_DIR/config/"
echo "------------------------------------------------------------"
