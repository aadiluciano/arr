#!/bin/bash

# ==========================
# TrueNAS SCALE Media Server Setup (Updated)
# Includes: Radarr, Sonarr, Jellyfin, Prowlarr, Jellyseerr
#           + Gluetun + qBittorrent (VPN)
#           + Tailscale (Remote Access)
# ==========================

# --------------------------
# 0. Prompt for pool name
# --------------------------
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
CONFIG_FOLDERS=("radarr" "sonarr" "jellyfin" "prowlarr" "jellyseerr" "gluetun" "qbittorrent" "tailscale")

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
chmod -R 775 "$MEDIA"

# --------------------------
# 5. VPN Choice
# --------------------------
echo "Which VPN type would you like to use for qBittorrent?"
echo "1) OpenVPN (username/password)"
echo "2) WireGuard (paste full config file)"
read -p "Enter choice [1 or 2]: " VPN_CHOICE

ENV_FILE="$COMPOSE/.env"
if [ -f "$ENV_FILE" ]; then
    echo "Backing up existing .env file"
    cp "$ENV_FILE" "$ENV_FILE.bak.$(date +%F-%T)"
fi

if [ "$VPN_CHOICE" == "1" ]; then
    read -p "Enter your PrivadoVPN username: " VPN_USER
    read -sp "Enter your PrivadoVPN password: " VPN_PASS
    echo
    cat > "$ENV_FILE" <<EOL
PUID=$USER_ID
PGID=$GROUP_ID
TZ=$TZ
VPN_TYPE=openvpn
VPN_SERVICE_PROVIDER=privado
OPENVPN_USER=$VPN_USER
OPENVPN_PASSWORD=$VPN_PASS
TS_AUTHKEY=your_tailscale_authkey
EOL
    WG_MODE="false"
elif [ "$VPN_CHOICE" == "2" ]; then
    echo "Paste the full contents of your Privado WireGuard .conf file below."
    echo "End input with CTRL+D when finished."
    WG_CONF_PATH="$CONFIG/gluetun/wg0.conf"
    cat > "$WG_CONF_PATH"
    cat > "$ENV_FILE" <<EOL
PUID=$USER_ID
PGID=$GROUP_ID
TZ=$TZ
VPN_TYPE=wireguard
VPN_SERVICE_PROVIDER=custom
WIREGUARD_CONFIG_FILE=/gluetun/wg0.conf
TS_AUTHKEY=your_tailscale_authkey
EOL
    WG_MODE="true"
else
    echo "Invalid choice. Exiting."
    exit 1
fi

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
    networks:
      - app_net
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
    networks:
      - app_net
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
    networks:
      - app_net
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
    networks:
      - app_net
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
    networks:
      - app_net
    restart: unless-stopped

  gluetun:
    image: qmcgaw/gluetun
    container_name: gluetun
    cap_add:
      - NET_ADMIN
    env_file:
      - .env
    volumes:
      - $CONFIG/gluetun:/gluetun
    ports:
      - "8080:8080"
      - "6881:6881/tcp"
      - "6881:6881/udp"
    networks:
      - vpn_net
    restart: unless-stopped

  qbittorrent:
    image: linuxserver/qbittorrent
    container_name: qbittorrent
    env_file:
      - .env
    volumes:
      - $MEDIA/downloads:/downloads
      - $CONFIG/qbittorrent:/config
    network_mode: service:gluetun
    depends_on:
      - gluetun
    restart: unless-stopped

  tailscale:
    image: tailscale/tailscale:latest
    container_name: tailscale
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    network_mode: "host"
    env_file:
      - .env
    restart: unless-stopped

networks:
  vpn_net:
    driver: bridge
  app_net:
    driver: bridge
EOL

# --------------------------
# 8. Stop and remove old containers
# --------------------------
echo "=== Stopping and removing old containers ==="
docker compose -f "$COMPOSE_FILE" down
docker ps -a | grep -E 'radarr|sonarr|jellyfin|prowlarr|jellyseerr|qbittorrent|gluetun|tailscale' | awk '{print $1}' | xargs -r docker rm -f

# --------------------------
# 9. Bring up containers
# --------------------------
echo "=== Bringing up containers with new UID/GID ==="
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --remove-orphans

# --------------------------
# 10. Instructions
# --------------------------
echo "=== Setup complete ==="
echo "Verify UID/GID inside containers (example for Radarr):"
echo "docker exec -it radarr id  (should show uid=$USER_ID gid=$GROUP_ID)"
echo ""
echo "qBittorrent WebUI is accessible at http://<server_ip>:8080"
echo "Radarr/Sonarr root folders already mapped:"
echo "  /movies  -> Radarr"
echo "  /tv      -> Sonarr"
echo "Downloads folder already mapped to qBittorrent"
echo ""
echo "Tailscale should now allow remote access to all containers."
