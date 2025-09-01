#!/bin/bash

# ==========================
# TrueNAS SCALE Media Server Setup
# Auto-fix permissions for UID/GID even under sudo su
# Supports OpenVPN via pasted .ovpn file or WireGuard .conf
# ==========================

# --------------------------
# 0. Target user UID/GID
# --------------------------
TARGET_UID=950
TARGET_GID=950
echo "Target UID:GID = $TARGET_UID:$TARGET_GID"

# --------------------------
# 1. Prompt for pool name
# --------------------------
read -p "Enter your TrueNAS pool name: " POOL

# Paths
MEDIA="/mnt/$POOL/media"
APPDATA="/mnt/$POOL/appdata"
COMPOSE="$APPDATA/compose"
CONFIG="$APPDATA/config"

# --------------------------
# 2. Detect real UID/GID (even under sudo su)
# --------------------------
if [ -n "$SUDO_UID" ] && [ -n "$SUDO_GID" ]; then
    REAL_UID=$SUDO_UID
    REAL_GID=$SUDO_GID
else
    REAL_UID=$(id -u)
    REAL_GID=$(id -g)
fi
echo "Running script as UID:$REAL_UID GID:$REAL_GID"

# --------------------------
# 3. Create datasets if missing
# --------------------------
echo "=== Creating datasets if missing ==="
zfs list "$POOL/media" &>/dev/null || zfs create "$POOL/media"
zfs list "$POOL/appdata" &>/dev/null || zfs create "$POOL/appdata"

# --------------------------
# 4. Create media subfolders
# --------------------------
MEDIA_SUBS=("movies" "tv" "music" "downloads" "downloads/complete" "downloads/incomplete")
echo "=== Creating media subfolders ==="
for folder in "${MEDIA_SUBS[@]}"; do
    mkdir -p "$MEDIA/$folder"
    echo "Created or exists: $MEDIA/$folder"
done

# --------------------------
# 5. Create appdata config folders
# --------------------------
CONFIG_FOLDERS=("radarr" "sonarr" "jellyfin" "prowlarr" "jellyseerr" "gluetun" "qbittorrent" "tailscale")
echo "=== Creating appdata config folders ==="
for folder in "${CONFIG_FOLDERS[@]}"; do
    mkdir -p "$CONFIG/$folder"
done
mkdir -p "$COMPOSE"

# --------------------------
# 6. Set ownership and permissions
# --------------------------
echo "=== Setting ownership to UID:$TARGET_UID GID:$TARGET_GID ==="
chown -R $TARGET_UID:$TARGET_GID "$MEDIA"
chown -R $TARGET_UID:$TARGET_GID "$APPDATA"
chmod -R 775 "$MEDIA"
chmod -R 775 "$APPDATA"

# --------------------------
# 7. Ask for VPN method and config
# --------------------------
echo "Choose VPN type:"
select vpn_type in "OpenVPN" "WireGuard"; do
  case $REPLY in
    1)
      VPN_TYPE="openvpn"
      VPN_PROVIDER="custom"
      mkdir -p "$CONFIG/gluetun"
      OVPN_FILE="$CONFIG/gluetun/custom.ovpn"
      echo "Paste your full OpenVPN .ovpn file contents (end with CTRL+D):"
      cat > "$OVPN_FILE"
      chown $TARGET_UID:$TARGET_GID "$OVPN_FILE"
      chmod 600 "$OVPN_FILE"
      echo "OpenVPN config saved to $OVPN_FILE"
      VPN_USER=""
      VPN_PASS=""
      break
      ;;
    2)
      VPN_TYPE="wireguard"
      VPN_PROVIDER="custom"
      mkdir -p "$CONFIG/gluetun"
      WG_CONF="$CONFIG/gluetun/wireguard.conf"
      echo "Paste your full WireGuard .conf file contents (end with CTRL+D):"
      cat > "$WG_CONF"
      chown $TARGET_UID:$TARGET_GID "$WG_CONF"
      chmod 600 "$WG_CONF"
      echo "WireGuard config saved to $WG_CONF"
      VPN_USER=""
      VPN_PASS=""
      break
      ;;
    *)
      echo "Invalid option. Please enter 1 or 2."
      ;;
  esac
done

# --------------------------
# 8. Ask for Tailscale auth key
# --------------------------
echo ""
echo "To enable remote access with Tailscale, you need a reusable auth key."
echo "Go to https://login.tailscale.com/admin/settings/keys to generate a key."
read -p "Paste your Tailscale reusable auth key here: " TS_AUTHKEY

# --------------------------
# 9. Create .env file
# --------------------------
ENV_FILE="$COMPOSE/.env"
cat > "$ENV_FILE" <<EOL
PUID=$TARGET_UID
PGID=$TARGET_GID
TZ=America/Toronto
VPN_TYPE=$VPN_TYPE
VPN_SERVICE_PROVIDER=$VPN_PROVIDER
VPN_USER=$VPN_USER
VPN_PASS=$VPN_PASS
TS_AUTHKEY=$TS_AUTHKEY
EOL
chown $TARGET_UID:$TARGET_GID "$ENV_FILE"
chmod 640 "$ENV_FILE"
echo "Created .env file at $ENV_FILE"

# --------------------------
# 10. Create docker-compose.yml
# --------------------------
COMPOSE_FILE="$COMPOSE/docker-compose.yml"

cat > "$COMPOSE_FILE" <<EOL
version: '3.9'

services:
  gluetun:
    image: qmcgaw/gluetun:latest
    container_name: gluetun
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    volumes:
      - $CONFIG/gluetun:/gluetun
EOL

if [ "$VPN_TYPE" = "wireguard" ]; then
cat >> "$COMPOSE_FILE" <<EOL
      - $CONFIG/gluetun/wireguard.conf:/gluetun/wireguard.conf
EOL
else
cat >> "$COMPOSE_FILE" <<EOL
      - $CONFIG/gluetun/custom.ovpn:/gluetun/custom.ovpn
EOL
fi

cat >> "$COMPOSE_FILE" <<EOL
    environment:
      - PUID=$TARGET_UID
      - PGID=$TARGET_GID
      - TZ=America/Toronto
      - VPN_TYPE=$VPN_TYPE
      - VPN_SERVICE_PROVIDER=$VPN_PROVIDER
    restart: unless-stopped

  qbittorrent:
    image: linuxserver/qbittorrent
    container_name: qbittorrent
    network_mode: service:gluetun
    depends_on:
      - gluetun
    environment:
      - PUID=$TARGET_UID
      - PGID=$TARGET_GID
    volumes:
      - $CONFIG/qbittorrent:/config
      - $MEDIA/downloads:/downloads
    restart: unless-stopped

  radarr:
    image: linuxserver/radarr
    container_name: radarr
    networks:
      - app_net
    environment:
      - PUID=$TARGET_UID
      - PGID=$TARGET_GID
    volumes:
      - $CONFIG/radarr:/config
      - $MEDIA/movies:/movies
    ports:
      - 7878:7878
    restart: unless-stopped

  sonarr:
    image: linuxserver/sonarr
    container_name: sonarr
    networks:
      - app_net
    environment:
      - PUID=$TARGET_UID
      - PGID=$TARGET_GID
    volumes:
      - $CONFIG/sonarr:/config
      - $MEDIA/tv:/tv
      - $MEDIA/downloads:/downloads
    ports:
      - 8989:8989
    restart: unless-stopped

  jellyfin:
    image: linuxserver/jellyfin
    container_name: jellyfin
    networks:
      - app_net
    environment:
      - PUID=$TARGET_UID
      - PGID=$TARGET_GID
    volumes:
      - $CONFIG/jellyfin:/config
      - $MEDIA:/media
    ports:
      - 8096:8096
    restart: unless-stopped

  prowlarr:
    image: linuxserver/prowlarr
    container_name: prowlarr
    networks:
      - app_net
    environment:
      - PUID=$TARGET_UID
      - PGID=$TARGET_GID
    volumes:
      - $CONFIG/prowlarr:/config
    ports:
      - 9696:9696
    restart: unless-stopped

  jellyseerr:
    image: fallenbagel/jellyseerr
    container_name: jellyseerr
    networks:
      - app_net
    environment:
      - PUID=$TARGET_UID
      - PGID=$TARGET_GID
    volumes:
      - $CONFIG/jellyseerr:/config
    ports:
      - 5055:5055
    restart: unless-stopped

  tailscale:
    image: tailscale/tailscale
    container_name: tailscale
    network_mode: "host"
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    environment:
      - TS_AUTHKEY=$TS_AUTHKEY
    volumes:
      - $CONFIG/tailscale:/var/lib/tailscale
    restart: unless-stopped

networks:
  app_net:
    driver: bridge
EOL

chown $TARGET_UID:$TARGET_GID "$COMPOSE_FILE"
chmod 644 "$COMPOSE_FILE"

# --------------------------
# 11. Start containers
# --------------------------
docker compose -f "$COMPOSE_FILE" up -d

echo "=== Setup complete ==="
echo "All appdata and media folders now owned by UID:$TARGET_UID GID:$TARGET_GID"
