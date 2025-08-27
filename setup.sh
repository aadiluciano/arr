#!/bin/bash

# ==========================
# TrueNAS SCALE Media Server Setup
# ==========================

# Prompt for pool name
read -p "Enter your TrueNAS pool name: " POOL

# Paths
MEDIA="/mnt/$POOL/media"
APPDATA="/mnt/$POOL/appdata"
COMPOSE="$APPDATA/compose"
CONFIG="$APPDATA/config"

# Detect current user UID/GID
USER_ID=$(id -u)
GROUP_ID=$(id -g)

echo "Detected UID=$USER_ID and GID=$GROUP_ID for current user"

# Timezone
TZ="America/Toronto"

# Media subfolders
MEDIA_SUBS=("movies" "tv" "music" "downloads" "downloads/complete" "downloads/incomplete")

# Appdata config folders
CONFIG_FOLDERS=("radarr" "sonarr" "jellyfin" "prowlarr" "jellyseerr")

# --------------------------
# 1. Create datasets if missing
# --------------------------
echo "=== Creating datasets if missing ==="
zfs list "$POOL/media" &>/dev/null || zfs create "$POOL/media"
zfs list "$POOL/appdata" &>/dev/null || zfs create "$POOL/appdata"

# --------------------------
# 2. Create media subfolders
# --------------------------
echo "=== Creating media subfolders ==="
for folder in "${MEDIA_SUBS[@]}"; do
    FULL_PATH="$MEDIA/$folder"
    mkdir -p "$FULL_PATH"
    echo "Created or exists: $FULL_PATH"
done

# --------------------------
# 3. Create appdata config folders
# --------------------------
echo "=== Creating appdata config folders ==="
for folder in "${CONFIG_FOLDERS[@]}"; do
    mkdir -p "$CONFIG/$folder"
done
mkdir -p "$COMPOSE"

# --------------------------
# 4. Set ownership and permissions
# --------------------------
echo "=== Setting ownership to UID:$USER_ID GID:$GROUP_ID ==="
chown -R $USER_ID:$GROUP_ID "$MEDIA"
chown -R $USER_ID:$GROUP_ID "$APPDATA"

# Ensure media folders are writable
chmod -R 775 "$MEDIA"

# --------------------------
# 5. Create .env file
# --------------------------
ENV_FILE="$COMPOSE/.env"
if [ -f "$ENV_FILE" ]; then
    echo "Backing up existing .env file"
    cp "$ENV_FILE" "$ENV_FILE.bak.$(date +%F-%T)"
fi

cat > "$ENV_FILE" <<EOL
PUID=$USER_ID
PGID=$GROUP_ID
TZ=$TZ
EOL

echo "Created .env file at $ENV_FILE"

# --------------------------
# 6. Backup old docker-compose.yml if exists
# --------------------------
COMPOSE_FILE="$COMPOSE/docker-compose.yml"
if [ -f "$COMPOSE_FILE" ]; then
    echo "Backing up existing docker-compose.yml"
    cp "$COMPOSE_FILE" "$COMPOSE_FILE.bak.$(date +%F-%T)"
fi

# --------------------------
# 7. Generate docker-compose.yml
# --------------------------
echo "=== Generating docker-compose.yml ==="
cat > "$COMPOSE_FILE" <<EOL
version: '3.9'

services:
  radarr:
    image: linuxserver/radarr:latest
    container_name: radarr
    env_file:
      - .env
    volumes:
      - $MEDIA/movies:/movies
      - $CONFIG/radarr:/config
    ports:
      - 7878:7878
    restart: unless-stopped

  sonarr:
    image: linuxserver/sonarr:latest
    container_name: sonarr
    env_file:
      - .env
    volumes:
      - $MEDIA/tv:/tv
      - $MEDIA/downloads:/downloads
      - $CONFIG/sonarr:/config
    ports:
      - 8989:8989
    restart: unless-stopped

  jellyfin:
    image: linuxserver/jellyfin:latest
    container_name: jellyfin
    env_file:
      - .env
    volumes:
      - $MEDIA:/media
      - $CONFIG/jellyfin:/config
    ports:
      - 8096:8096
    restart: unless-stopped

  prowlarr:
    image: linuxserver/prowlarr:latest
    container_name: prowlarr
    env_file:
      - .env
    volumes:
      - $CONFIG/prowlarr:/config
    ports:
      - 9696:9696
    restart: unless-stopped

  jellyseerr:
    image: fallenbagel/jellyseerr:latest
    container_name: jellyseerr
    env_file:
      - .env
    volumes:
      - $CONFIG/jellyseerr:/config
    ports:
      - 5055:5055
    restart: unless-stopped
EOL

# --------------------------
# 8. Stop and remove old containers
# --------------------------
echo "=== Stopping and removing old containers ==="
docker compose -f "$COMPOSE_FILE" down
docker ps -a | grep -E 'radarr|sonarr|jellyfin|prowlarr|jellyseerr' | awk '{print $1}' | xargs -r docker rm -f

# --------------------------
# 9. Bring up containers
# --------------------------
echo "=== Bringing up containers with new UID/GID ==="
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --remove-orphans

# --------------------------
# 10. Instructions
# --------------------------
echo "=== Setup complete ==="
echo "Verify UID/GID inside Radarr:"
echo "docker exec -it radarr id  (should show uid=$USER_ID gid=$GROUP_ID)"
echo ""
echo "You can now add root folders:"
echo "  /movies  -> Radarr"
echo "  /tv      -> Sonarr"
echo "These folders are already created with correct permissions."
