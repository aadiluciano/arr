#!/bin/bash
set -e

# Prompt user for pool name
read -p "Enter your pool name (e.g., pool1): " POOL_ROOT

echo "📂 Creating ZFS datasets under /mnt/$POOL_ROOT"

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

# Media subdatasets
MEDIA_DATASETS=("movies" "tv" "downloads")

# Function to apply permissions
set_permissions() {
    local path="/mnt/$POOL_ROOT/$1"
    if [ -d "$path" ]; then
        chown root:apps "$path"
        chmod 770 "$path"
        echo "Permissions set: $path -> root:apps, 770"
    else
        echo "⚠️ Warning: $path does not exist to set permissions."
    fi
}

# Create the root datasets if they don't exist
for ds in "configs" "media"; do
    if ! zfs list "$POOL_ROOT/$ds" >/dev/null 2>&1; then
        echo "Creating dataset: $POOL_ROOT/$ds"
        zfs create "$POOL_ROOT/$ds"
    else
        echo "Dataset $POOL_ROOT/$ds already exists, skipping..."
    fi
done

# Create config subdatasets
for app in "${CONFIG_DATASETS[@]}"; do
    if ! zfs list "$POOL_ROOT/configs/$app" >/dev/null 2>&1; then
        echo "Creating dataset: $POOL_ROOT/configs/$app"
        zfs create "$POOL_ROOT/configs/$app"
    else
        echo "Dataset $POOL_ROOT/configs/$app already exists, skipping..."
    fi
done

# Create media subdatasets
for folder in "${MEDIA_DATASETS[@]}"; do
    if ! zfs list "$POOL_ROOT/media/$folder" >/dev/null 2>&1; then
        echo "Creating dataset: $POOL_ROOT/media/$folder"
        zfs create "$POOL_ROOT/media/$folder"
    else
        echo "Dataset $POOL_ROOT/media/$folder already exists, skipping..."
    fi
done

echo "✅ ZFS datasets for configs and media created successfully"

# Print directory tree using find
echo "📂 Directory structure under /mnt/$POOL_ROOT:"
find "/mnt/$POOL_ROOT" -type d | sed "s|$PWD|.|" | sed 's|[^/]*/| |g'
