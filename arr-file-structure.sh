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
MEDIA_DATASETS=(
"movies" 
"tv" 
"downloads"
)

# Function to create dataset, mount it, and set permissions
create_dataset() {
    local dataset="$1"
    local mountpoint="/mnt/$POOL_ROOT/$dataset"

    if ! zfs list "$POOL_ROOT/$dataset" >/dev/null 2>&1; then
        echo "Creating dataset: $POOL_ROOT/$dataset"
        zfs create "$POOL_ROOT/$dataset"
    else
        echo "Dataset $POOL_ROOT/$dataset already exists, skipping..."
    fi

    # Mount the dataset if not already mounted
    if ! mountpoint -q "$mountpoint"; then
        echo "Mounting $POOL_ROOT/$dataset..."
        zfs mount "$POOL_ROOT/$dataset"
    fi

    # Apply permissions
    if [ -d "$mountpoint" ]; then
        chown root:apps "$mountpoint"
        chmod 770 "$mountpoint"
        echo "✅ Permissions set for $mountpoint -> root:apps, 770"
    else
        echo "⚠️ Warning: $mountpoint does not exist even after mounting."
    fi
}

# Create root datasets
create_dataset "configs"
create_dataset "media"

# Create config subdatasets
for app in "${CONFIG_DATASETS[@]}"; do
    create_dataset "configs/$app"
done

# Create media subdatasets
for folder in "${MEDIA_DATASETS[@]}"; do
    create_dataset "media/$folder"
done

echo "✅ All ZFS datasets created and permissioned successfully"

# Print directory tree under /mnt/$POOL_ROOT
echo "📂 Directory structure under /mnt/$POOL_ROOT:"
find "/mnt/$POOL_ROOT" -type d | sed "s|$PWD|.|" | sed 's|[^/]*/| |g'

echo "🎉 Setup complete!"
