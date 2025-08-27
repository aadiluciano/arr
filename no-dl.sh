#!/bin/bash

# === TrueNAS Scale Media Server Setup Script ===

set -e

echo "=== TrueNAS Scale Media Server Setup ==="

# --- Prompt for pool ---
read -rp "Enter your TrueNAS pool name (e.g., pool1): " POOL

# --- Base paths ---
MEDIA="/mnt/$POOL/media"
APPDATA="/mnt/$POOL/appdata"
CONFIG_DIR="$APPDATA/config"
COMPOSE_DIR="$APPDATA/compose"

# --- Media subdirectories ---
MEDIA_SUBDIRS=("movies" "tv" "music" "downloads/complete" "downloads/incomplete")

# --- Apps ---
CONFIG_APPS=("jellyfin" "sonarr" "radarr" "prowlar" "jellyseerr")
PORTS=(8096 8989 7878 9696 5055)

# --- UID/GID for Docker containers ---
USER_ID=1000
GROUP_ID=1000

echo "Creating media datasets..."

# Create media datasets
for dir in "${MEDIA_SUBDIRS[@]}"; do
    DATASET="$POOL/$(echo $dir | sed 's/\//_/g')"
    if ! zfs list "$DATASET" &> /dev/null; then
        echo "Creating dataset $DATASET"
        zfs create "$DATASET"
    else
        echo "Dataset $DATASET already exists, skipping."
    fi
done

# Create appdata datasets
for dataset in ("appdata" "appdata/config" "appdata/compose"); do
    FULL_DATASET="$POOL/$dataset"
    if ! zfs list "$FULL_DATASET" &> /dev/null; then
        echo "Creating dataset $FULL_DATASET"
        zfs create "$FULL_DATASET"
    else
        echo "Dataset $FULL_DATASET already exists, skipping."
    fi
done

# --- Ensure proper permissions ---
echo "Setting permissions..."
chown -R $USER_ID:$GROUP_ID "$MEDIA"
chown -R $USER_ID:$GROUP_ID "$APPDATA"

# --- Create per-app config subfolders ---
echo "Creating per-app config directories..."
for app in "${CONFIG_APPS[@]}"; do
    APP_CONFIG_DIR="$CONFIG_DIR/$app"
    if [ ! -d "$APP_CONFIG_DIR" ]; then
        mkdir -p "$APP_CONFIG_DIR"
        chown -R $USER_ID:$GROUP_ID "$APP_CONFIG_DIR"
        echo "Created config folder: $APP_CONFIG_DIR"
    else
        echo "Config folder $APP_CONFIG_DIR already exists, skipping."
    fi
done

# --- Generate .env file ---
ENV_FILE="$COMPOSE_DIR/.env"
echo "Generating .env file at $ENV_FILE"

cat > "$ENV_FILE" <<EOL
# Pool and base paths
POOL=$POOL
APPDATA=$APPDATA
MEDIA=$MEDIA

# App-specific config dirs
CONFIG_DIR=$CONFIG_DIR
COMPOSE_DIR=$COMPOSE_DIR

# Media sub-datasets
MOVIES=$MEDIA/movies
TV=$MEDIA/tv
MUSIC=$MEDIA/music
DOWNLOADS=$MEDIA/downloads
COMPLETE=$MEDIA/downloads/complete
INCOMPLETE=$MEDIA/downloads/incomplete

# Ports
JELLYFIN_PORT=8096
SONARR_PORT=8989
RADARR_PORT=7878
PROWLARR_PORT=9696
JELLYSEERR_PORT=5055
EOL

# --- Generate docker-compose.yml ---
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"
echo "Generating docker-compose.yml at $COMPOSE_FILE"

cat > "$COMPOSE_FILE" <<'EOL'
version: "3.8"

services:
  jellyfin:
    image: linuxserver/jellyfin:latest
    container_name: jellyfin
    environment:
      - PUID=${USER_ID}
      - PGID=${GROUP_ID}
      - TZ=America/Toronto
    volumes:
      - ${MOVIES}:/movies
      - ${TV}:/tv
      - ${MUSIC}:/music
      - ${CONFIG_DIR}/jellyfin:/config
    ports:
      - "${JELLYFIN_PORT}:8096"
    restart: unless-stopped

  sonarr:
    image: linuxserver/sonarr:latest
    container_name: sonarr
    environment:
      - PUID=${USER_ID}
      - PGID=${GROUP_ID}
      - TZ=America/Toronto
    volumes:
      - ${TV}:/tv
      - ${DOWNLOADS}:/downloads
      - ${CONFIG_DIR}/sonarr:/config
    ports:
      - "${SONARR_PORT}:8989"
    restart: unless-stopped

  radarr:
    image: linuxserver/radarr:latest
    container_name: radarr
    environment:
      - PUID=${USER_ID}
      - PGID=${GROUP_ID}
      - TZ=America/Toronto
    volumes:
      - ${MOVIES}:/movies
      - ${DOWNLOADS}:/downloads
      - ${CONFIG_DIR}/radarr:/config
    ports:
      - "${RADARR_PORT}:7878"
    restart: unless-stopped

  prowlarr:
    image: linuxserver/prowlarr:latest
    container_name: prowlarr
    environment:
      - PUID=${USER_ID}
      - PGID=${GROUP_ID}
      - TZ=America/Toronto
    volumes:
      - ${CONFIG_DIR}/prowlarr:/config
    ports:
      - "${PROWLARR_PORT}:9696"
    restart: unless-stopped

  jellyseerr:
    image: fallenbagel/jellyseerr:latest
    container_name: jellyseerr
    environment:
      - TZ=America/Toronto
      - LOG_LEVEL=info
    volumes:
      - ${CONFIG_DIR}/jellyseerr:/app/config
    ports:
      - "${JELLYSEERR_PORT}:5055"
    restart: unless-stopped

EOL

# --- Launch Docker stack ---
echo "Launching Docker containers..."
cd "$COMPOSE_DIR"
docker compose --env-file .env up -d

echo "=== Setup Complete ==="
echo "Safe local media apps are running."
echo "All datasets are visible in TrueNAS, app configs are ready, and docker-compose.yml/.env are in place for future expansion."
