#!/bin/bash

# -----------------------------
# TrueNAS Media Server Setup
# -----------------------------

# Prompt for pool name
read -p "Enter your TrueNAS pool name: " POOL

# Paths
MEDIA="/mnt/$POOL/media"
APPDATA="/mnt/$POOL/appdata"
COMPOSE="$APPDATA/compose"

# UID/GID for Docker apps
USER_ID=1000
GROUP_ID=1000

# Media subfolders
MEDIA_SUBS=("movies" "tv" "music" "downloads" "downloads/complete" "downloads/incomplete")

# Appdata config folders
CONFIG_FOLDERS=("radarr" "sonarr" "jellyfin" "prowlarr" "jellyseerr")

echo "=== Creating datasets if missing ==="
zfs list "$POOL/media" &>/dev/null || zfs create "$POOL/media"
zfs list "$POOL/appdata" &>/dev/null || zfs create "$POOL/appdata"

echo "=== Creating media subfolders ==="
for folder in "${MEDIA_SUBS[@]}"; do
    FULL_PATH="$MEDIA/$folder"
    if [ ! -d "$FULL_PATH" ]; then
        mkdir -p "$FULL_PATH"
        echo "Created $FULL_PATH"
    else
        echo "Folder $FULL_PATH already exists, skipping"
    fi
done

echo "=== Creating appdata config folders ==="
for folder in "${CONFIG_FOLDERS[@]}"; do
    mkdir -p "$APPDATA/config/$folder"
done

# Compose folder
mkdir -p "$COMPOSE"

echo "=== Setting ownership to UID:$USER_ID GID:$GROUP_ID ==="
chown -R $USER_ID:$GROUP_ID "$MEDIA"
chown -R $USER_ID:$GROUP_ID "$APPDATA"

echo "=== Generating docker-compose.yml ==="
cat > "$COMPOSE/docker-compose.yml" <<EOL
services:
  radarr:
    image: linuxserver/radarr:latest
    container_name: radarr
    environment:
      - PUID=$USER_ID
      - PGID=$GROUP_ID
      - TZ=America/Toronto
    volumes:
      - $MEDIA/movies:/movies
      - $APPDATA/config/radarr:/config
    ports:
      - 7878:7878
    restart: unless-stopped

  sonarr:
    image: linuxserver/sonarr:latest
    container_name: sonarr
    environment:
      - PUID=$USER_ID
      - PGID=$GROUP_ID
      - TZ=America/Toronto
    volumes:
      - $MEDIA/tv:/tv
      - $MEDIA/downloads:/downloads
      - $APPDATA/config/sonarr:/config
    ports:
      - 8989:8989
    restart: unless-stopped

  jellyfin:
    image: linuxserver/jellyfin:latest
    container_name: jellyfin
    environment:
      - PUID=$USER_ID
      - PGID=$GROUP_ID
      - TZ=America/Toronto
    volumes:
      - $MEDIA:/media
      - $APPDATA/config/jellyfin:/config
    ports:
      - 8096:8096
    restart: unless-stopped

  prowlarr:
    image: linuxserver/prowlarr:latest
    container_name: prowlarr
    environment:
      - PUID=$USER_ID
      - PGID=$GROUP_ID
      - TZ=America/Toronto
    volumes:
      - $APPDATA/config/prowlarr:/config
    ports:
      - 9696:9696
    restart: unless-stopped

  jellyseerr:
    image: fallenbagel/jellyseerr:latest
    container_name: jellyseerr
    environment:
      - PUID=$USER_ID
      - PGID=$GROUP_ID
      - TZ=America/Toronto
    volumes:
      - $APPDATA/config/jellyseerr:/config
    ports:
      - 5055:5055
    restart: unless-stopped
EOL

echo "=== Setup complete ==="
echo "Docker Compose file saved to $COMPOSE/docker-compose.yml"
echo "You can now run:"
echo "cd $COMPOSE && docker compose up -d --remove-orphans"
