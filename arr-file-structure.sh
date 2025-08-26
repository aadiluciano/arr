#!/bin/bash
set -e

# Root path for docker data (directly under pool1)
POOL_ROOT="/mnt/pool1"

# Config datasets for each app
CONFIG_DATASETS=(
  "prowlarr"
  "radarr"
  "sonarr"
  "jellyseerr"
  "recyclarr"
  "bazarr"
  "tdarr"
  "jellyfin"
  "qbittorrent"
  "dozzle"
  "gluetun"
  "traefik"
  "healthchecksio"
  "nzbget"
)

echo "📂 Creating Docker file structure under $POOL_ROOT"

# Create base directories
mkdir -p "$POOL_ROOT/configs"
mkdir -p "$POOL_ROOT/media/movies"
mkdir -p "$POOL_ROOT/media/tv"
mkdir -p "$POOL_ROOT/media/downloads"

# Create config subfolders
for app in "${CONFIG_DATASETS[@]}"; do
  mkdir -p "$POOL_ROOT/configs/$app"
done

# Optional: create tdarr subfolders
mkdir -p "$POOL_ROOT/configs/tdarr/server"
mkdir -p "$POOL_ROOT/configs/tdarr/logs"
mkdir -p "$POOL_ROOT/configs/tdarr/transcode_cache"

# Set permissions (adjust UID/GID if needed)
chown -R 1000:1000 "$POOL_ROOT"
chmod -R 770 "$POOL_ROOT"

echo "✅ File structure created successfully:"
tree -d -L 3 "$POOL_ROOT" || echo "Install 'tree' to view directory structure."
