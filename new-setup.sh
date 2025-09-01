#!/bin/bash

# ==========================
# TrueNAS SCALE Media Server Setup (Final Version)
# Includes: Radarr, Sonarr, Jellyfin, Prowlarr, Jellyseerr
#           + Gluetun + qBittorrent (VPN)
#           + Tailscale (Remote Access)
# ==========================

# 0. Prompt for pool name
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

# 1. Create datasets if missing
echo "=== Creating datasets if missing ==="
zfs list "$POOL/media" &>/dev/null || zfs create "$POOL/media"
zfs list "$POOL/appdata" &>/dev/null || zfs create "$POOL/appdata"

# 2. Create media subfolders
echo "=== Creating media subfolders ==="
for folder in "${MEDIA_SUBS[@]}"; do
    FULL_PATH="$MEDIA/$folder"
    mkdir -p "$FULL_PATH"
    echo "Created or exists: $FULL_PATH"
done

# 3. Create appdata config folders
echo "=== Creating appdata config folders ==="
for folder in "${CONFIG_FOLDERS[@]}"; do
    mkdir -p "$CONFIG/$folder"
done
mkdir -p "$COMPOSE"

# 4. Set ownership and permissions
echo "=== Setting ownership to UID:$USER_ID GID:$GROUP_ID ==="
chown -R $USER_ID:$GROUP_ID "$MEDIA"
chown -R $USER_ID:$GROUP_ID "$APPDATA"
chmod -R 775 "$MEDIA"

# 5. Ask for VPN method
echo "Choose VPN type:"
select vpn_type in "OpenVPN" "WireGuard"; do
  case $REPLY in
    1)
      VPN_TYPE="openvpn"
      read -p "Enter your VPN provider (e.g. privado, pia, mullvad): " VPN_PROVIDER
      read -p "Enter your VPN username: " VPN_USER
      read -s -p "Enter your VPN password: " VPN_PASS
      echo
      break
      ;;
    2)
      VPN_TYPE="wireguard"
      mkdir -p "$CONFIG/gluetun"
      WG_CONF="$CONFIG/gluetun/wireguard.conf"
      echo "Paste your full WireGuard .conf file contents (end with CTRL+D):"
      cat > "$WG_CONF"
      echo "WireGuard config saved to $WG_CONF"
      VPN_PROVIDER="custom"
      VPN_USER=""
      VPN_PASS=""
      break
      ;;
    *)
      echo "Invalid option. Please enter 1 or 2."
      ;;
  esac
done

# 6. Ask for Tailscale auth key
echo ""
echo "To enable remote access with Tailscale, you need a reusable auth key."
echo "Go to https://login.tailscale.com/admin/settings/keys to generate a key."
read -p "Paste your Tailscale reusable auth key here: " TS_AUTHKEY

# 7. Create .env file
ENV_FILE="$COMPOSE/.env"
if [ -f "$ENV_FILE" ]; then
    echo "Backing up existing .env file"
    cp "$ENV_FILE" "$ENV_FILE.bak.$(date +%F-%T)" 2>/dev/null || sudo cp "$ENV_FILE" "$ENV_FILE.bak.$(date +%F-%T)"
fi

cat <<EOL | tee "$ENV_FILE" >/dev/null || sudo tee "$ENV_FILE" >/dev/null
PUID=$USER_ID
PGID=$GROUP_ID
TZ=$TZ
VPN_TYPE=$VPN_TYPE
VPN_PROVIDER=$VPN_PROVIDER
VPN_USER=$VPN_USER
VPN_PASS=$VPN_PASS
TS_AUTHKEY=$TS_AUTHKEY
EOL

echo "Created .env file at $ENV_FILE"

# 8. Backup old docker-compose.yml if exists
COMPOSE_FILE="$COMPOSE/docker-compose.yml"
if [ -f "$COMPOSE_FILE" ]; then
    echo "Backing up existing docker-compose.yml"
    cp "$COMPOSE_FILE" "$COMPOSE_FILE.bak.$(date +%F-%T)" 2>/dev/null || sudo cp "$COMPOSE_FILE" "$COMPOSE_FILE.bak.$(date +%F-%T)"
fi

# 9. Generate docker-compose.yml
echo "=== Generating docker-compose.yml ==="
cat <<EOL | tee "$COMPOSE_FILE" >/dev/null || sudo tee "$COMPOSE_FILE" >/dev/null
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
      - vpn_net
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
      - vpn_net
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
      - vpn_net
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
EOL

if [ "$VPN_TYPE" = "wireguard" ]; then
cat <<EOL | tee -a "$COMPOSE_FILE" >/dev/null || sudo tee -a "$COMPOSE_FILE" >/dev/null
      - $CONFIG/gluetun/wireguard.conf:/gluetun/wireguard.conf
EOL
fi

cat <<EOL | tee -a "$COMPOSE_FILE" >/dev/null || sudo tee -a "$COMPOSE_FILE" >/dev/null
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
    ports:
      - "8080:8080"
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

# 10. Stop and remove old containers
echo "=== Stopping and removing old containers ==="
docker compose -f "$COMPOSE_FILE" down 2>/dev/null || sudo docker compose -f "$COMPOSE_FILE" down
docker ps -a | grep -E 'radarr|sonarr|jellyfin|prowlarr|jellyseerr|qbittorrent|gluetun|tailscale' | awk '{print $1}' | xargs -r docker rm -f

# 11. Bring up containers
echo "=== Bringing up containers with new UID/GID ==="
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --remove-orphans 2>/dev/null || \
sudo docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --remove-orphans

# 12. Instructions
echo "=== Setup complete ==="
echo ""
echo "Access your applications:"
echo "  - Radarr:      http://<LAN_IP>:7878"
echo "  - Sonarr:      http://<LAN_IP>:8989"
echo "  - Jellyfin:    http://<LAN_IP>:8096"
echo "  - Prowlarr:    http://<LAN_IP>:9696"
echo "  - Jellyseerr:  http://<LAN_IP>:5055"
echo "  - qBittorrent: http://<LAN_IP>:8080 (through VPN)"
echo ""
echo "Tailscale is running in host mode. Use your Tailscale IP for remote access."
