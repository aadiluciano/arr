#!/bin/bash

# ==========================
# TrueNAS Media Server Setup
# ==========================

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

# --------------------------
# 1. Create datasets
# --------------------------
echo "=== Creating datasets if missing ==="
zfs list "$POOL/media" &>/dev/null || zfs create "$POOL/media"
zfs list "$POOL/appdata" &>/dev/null || zfs create "$POOL/appdata"

# --------------------------
# 2. Create media folders
# --------------------------
echo "=== Creating media subfolders ==="
for folder in "${MEDIA_SUBS[@]}"; do
    FULL_PATH="$MEDIA/$folder"
    [ -d "$FULL_PATH" ] || mkdir -p "$FULL_PATH"
done

# --------------------------
# 3. Create appdata config folders
# --------------------------
echo "=== Creating appdata config folders ==="
for folder in "${CONFIG_FOLDERS[@]}"; do
    mkdir -p "$APPDATA/config/$folder"
done

mkdir -p "$COMPOSE"

# --------------------------
# 4. Set ownership
# --------------------------
echo "=== Setting ownership to UID:$USER_ID GID:$GROUP_ID ==="
chown -R $USER_ID:$GROUP_ID "$MEDIA"
chown -R $USER_ID:$GROUP_ID "$APPDATA"

# --------------------------
# 5. Backup old docker-compose.yml if exists
# --------------------------
if [ -f "$COMPOSE/docker-compose.yml" ]; then
    echo "Backing up existing docker-compose.yml"
    cp "$COMPOSE/docker-compose.yml" "$COMPOSE/docker-compose.yml.bak.$(date +%F-%T)"
fi

# --------------------------
# 6. Generate docker-compose.yml
# --------------------------
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

# --------------------------
# 7. Stop and remove old containers
# --------------------------
echo "=== Stopping and removing old containers ==="
docker compose -f "$COMPOSE/docker-compose.yml" down
docker ps -a | grep -E 'radarr|sonarr|jellyfin|prowlarr|jellyseerr' | awk '{print $1}' | xargs -r docker rm -f

# --------------------------
# 8. Bring up containers
# --------------------------
echo "=== Bringing up containers with new UID/GID ==="
docker compose -f "$COMPOSE/docker-compose.yml" up -d --remove-orphans

echo "=== Setup complete ==="
echo "Check containers with: docker ps"
echo "Inside Radarr container: docker exec -it radarr id (should show uid=1000 gid=1000)"
