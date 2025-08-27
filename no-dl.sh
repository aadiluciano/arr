#!/bin/bash

set -e

echo "=== TrueNAS Scale Media Server Setup (Safe Version) ==="

# Prompt for pool
read -rp "Enter your TrueNAS pool name (e.g., pool1): " POOL

# Base paths
MEDIA="/mnt/$POOL/media"
APPDATA="/mnt/$POOL/appdata"
CONFIG_DIR="$APPDATA/config"
COMPOSE_DIR="$APPDATA/compose"

# Media sub-datasets
MEDIA_SUBS=("movies" "tv" "music" "downloads" "downloads/complete" "downloads/incomplete")

# Apps
CONFIG_APPS=("jellyfin" "sonarr" "radarr" "prowlar" "jellyseerr")
PORTS=(8096 8989 7878 9696 5055)

# UID/GID for Docker
USER_ID=1000
GROUP_ID=1000

echo "=== Creating media dataset and sub-datasets ==="
if ! zfs list "$POOL/media" &> /dev/null; then
    zfs create "$POOL/media"
    echo "Created dataset $POOL/media"
fi

for sub in "${MEDIA_SUBS[@]}"; do
    zfs create -p "$POOL/media/$sub" 2>/dev/null || echo "Dataset $POOL/media/$sub already exists, skipping"
done

# Set top-level media ownership (do NOT recurse)
chown $USER_ID:$GROUP_ID "$MEDIA"

echo "=== Creating appdata dataset and sub-datasets ==="
if ! zfs list "$POOL/appdata" &> /dev/null; then
    zfs create "$POOL/appdata"
fi
zfs create -p "$POOL/appdata/config"
zfs create "$POOL/appdata/compose"

# Set ownership recursively for appdata (safe)
chown -R $USER_ID:$GROUP_ID "$APPDATA"

# Create per-app config folders
echo "=== Creating per-app config folders ==="
for app in "${CONFIG_APPS[@]}"; do
    APP_CONFIG="$CONFIG_DIR/$app"
    if [ ! -d "$APP_CONFIG" ]; then
        mkdir -p "$APP_CONFIG"
        chown -R $USER_ID:$GROUP_ID "$APP_CONFIG"
        echo "Created config folder: $APP_CONFIG"
    else
        echo "Config folder $APP_CONFIG already exists, skipping"
    fi
done

# Generate .env file
ENV_FILE="$COMPOSE_DIR/.env"
echo "=== Generating .env file at $ENV_FILE ==="
cat > "$ENV_FILE" <<EOL
# Pool and base paths
POOL=$POOL
APPDATA=$APPDATA
MEDIA=$MEDIA

# App config paths
CONFIG_DIR=$CONFIG_DIR
COMPOSE_DIR=$COMPOSE_DIR

# Media paths
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

# Generate docker-compose.yml
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"
echo "=== Generating docker-compose.yml at $COMPOSE_FILE ==="
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

echo "=== Docker containers ready. Run manually if you wish: ==="
echo "cd $COMPOSE_DIR && docker compose --env-file .env up -d"

echo "=== Setup complete! ==="
echo "Media datasets are intact. Appdata and config folders are ready. Docker compose file generated."
