#!/bin/bash

# ==========================
# TrueNAS SCALE Media Server Setup (with sudo-safe UID/GID detection)
# ==========================

# 0. Prompt for pool name
read -p "Enter your TrueNAS pool name: " POOL

# Paths
MEDIA="/mnt/$POOL/media"
APPDATA="/mnt/$POOL/appdata"
COMPOSE="$APPDATA/compose"
CONFIG="$APPDATA/config"

# Detect correct UID/GID even if run with sudo
if [ -n "$SUDO_UID" ] && [ -n "$SUDO_GID" ]; then
    USER_ID=$SUDO_UID
    GROUP_ID=$SUDO_GID
else
    USER_ID=$(id -u)
    GROUP_ID=$(id -g)
fi
echo "Using UID=$USER_ID and GID=$GROUP_ID"

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

if [ ! -w "$COMPOSE" ]; then
    echo "⚠️ ERROR: Cannot write to $COMPOSE"
    echo "Fix with: sudo chown -R $(whoami):$(whoami) $APPDATA"
    exit 1
fi

if [ -f "$ENV_FILE" ]; then
    echo "Backing up existing .env file"
    cp "$ENV_FILE" "$ENV_FILE.bak.$(date +%F-%T)"
fi

cat > "$ENV_FILE" <<EOL
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

# 8. Create docker-compose.yml
COMPOSE_FILE="$COMPOSE/docker-compose.yml"

if [ -f "$COMPOSE_FILE" ]; then
    echo "Backing up existing docker-compose.yml"
    cp "$COMPOSE_FILE" "$COMPOSE_FILE.bak.$(date +%F-%T)"
fi

cat > "$COMPOSE_FILE" <<'EOL'
version: "3.8"
services:
  gluetun:
    image: qmcgaw/gluetun
    container_name: gluetun
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
    volumes:
      - ${CONFIG}/gluetun:/gluetun
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
      - VPN_SERVICE_PROVIDER=${VPN_PROVIDER}
      - VPN_TYPE=${VPN_TYPE}
      - OPENVPN_USER=${VPN_USER}
      - OPENVPN_PASSWORD=${VPN_PASS}
      - WIREGUARD_CONFIG_FILE=/gluetun/wireguard.conf
    ports:
      - 8096:8096 # Jellyfin
      - 8080:8080 # qBittorrent
      - 5055:5055 # Prowlarr
      - 8989:8989 # Sonarr
      - 7878:7878 # Radarr
      - 5055:5055 # Jellyseerr
    restart: unless-stopped

  qbittorrent:
    image: linuxserver/qbittorrent
    container_name: qbittorrent
    network_mode: "service:gluetun"
    depends_on:
      - gluetun
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${CONFIG}/qbittorrent:/config
      - ${MEDIA}/downloads:/downloads
    restart: unless-stopped

  radarr:
    image: linuxserver/radarr
    container_name: radarr
    network_mode: "service:gluetun"
    depends_on:
      - gluetun
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${CONFIG}/radarr:/config
      - ${MEDIA}/movies:/movies
      - ${MEDIA}/downloads:/downloads
    restart: unless-stopped

  sonarr:
    image: linuxserver/sonarr
    container_name: sonarr
    network_mode: "service:gluetun"
    depends_on:
      - gluetun
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${CONFIG}/sonarr:/config
      - ${MEDIA}/tv:/tv
      - ${MEDIA}/downloads:/downloads
    restart: unless-stopped

  prowlarr:
    image: linuxserver/prowlarr
    container_name: prowlarr
    network_mode: "service:gluetun"
    depends_on:
      - gluetun
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${CONFIG}/prowlarr:/config
    restart: unless-stopped

  jellyseerr:
    image: fallenbagel/jellyseerr
    container_name: jellyseerr
    network_mode: "service:gluetun"
    depends_on:
      - gluetun
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${CONFIG}/jellyseerr:/app/config
    restart: unless-stopped

  jellyfin:
    image: linuxserver/jellyfin
    container_name: jellyfin
    network_mode: "service:gluetun"
    depends_on:
      - gluetun
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${CONFIG}/jellyfin:/config
      - ${MEDIA}:/media
    restart: unless-stopped

  tailscale:
    image: tailscale/tailscale
    container_name: tailscale
    hostname: truenas-tailscale
    volumes:
      - ${CONFIG}/tailscale:/var/lib/tailscale
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    environment:
      - TS_AUTHKEY=${TS_AUTHKEY}
    restart: unless-stopped
EOL

echo "Created docker-compose.yml at $COMPOSE_FILE"

# 9. Restart containers
echo "=== Restarting containers ==="
docker compose -f "$COMPOSE_FILE" down || true
docker compose -f "$COMPOSE_FILE" up -d
echo "=== Setup complete ==="
