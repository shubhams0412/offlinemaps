#!/bin/bash

# Configuration
PBF_FILE="india-260329.osm.pbf"
OSRM_FILE="india-260329.osrm"
PROFILE="/usr/local/share/osrm/profiles/car.lua"

echo "🚀 Starting OSRM Data Processing for $PBF_FILE..."

# 1. Extraction (requires significant RAM for India)
echo "📦 Step 1: Extracting PBF to OSRM format..."
docker run --rm -t -v "${PWD}/data:/data" osrm/osrm-backend \
  osrm-extract -p $PROFILE /data/$PBF_FILE

# 2. Partitioning
echo "🗺️ Step 2: Partitioning routing graph..."
docker run --rm -t -v "${PWD}/data:/data" osrm/osrm-backend \
  osrm-partition /data/$OSRM_FILE

# 3. Customization (MLD Algorithm)
echo "🛠️ Step 3: Customizing routing data (Multi-Level Dijkstra)..."
docker run --rm -t -v "${PWD}/data:/data" osrm/osrm-backend \
  osrm-customize /data/$OSRM_FILE

echo "✅ Processing Complete! You can now start the server with: docker-compose up -d"
