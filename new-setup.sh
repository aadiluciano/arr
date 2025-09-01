#!/bin/bash

# ==========================
# TrueNAS SCALE Media Server Setup
# OpenVPN or WireGuard support
# Automatically cleans previous Gluetun configs
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
GLUETUN_CONFIG="$CONFIG/gluetun"
GLUETUN_AUTH="$GLUETUN_CONFIG/auth"

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
# 3. Clean previous Gluetun files
# --------------------------
echo "=== Cleaning old Gluetun files ==="
rm -rf "$GLUETUN_CONFIG"
mkdir -p "$GLUETUN_CONFIG/auth"

# --------------------------
# 4. Create datasets if missing
# --------------------------
echo "=== Creating datasets if missing ==="
zfs list "$POOL/media" &>/dev/null || zfs create "$POOL/media"
zfs list "$POOL/appdata" &>/dev/null || zfs create "$POOL/appdata"

# --------------------------
# 5. Create media subfolders
# --------------------------
MEDIA_SUBS=("movies" "tv" "music" "downloads" "downloads/complete" "downloads/incomplete")
echo "=== Creating media subfolders ==="
for folder in "${MEDIA_SUBS[@]}"; do
    mkdir -p "$MEDIA/$folder"
done

# --------------------------
# 6. Create appdata config folders
# --------------------------
CONFIG_FOLDERS=("radarr" "sonarr" "jellyfin" "prowlarr" "jellyseerr" "gluetun" "qbittorrent" "tailscale")
echo "=== Creating appdata config folders ==="
for folder in "${CONFIG_FOLDERS[@]}"; do
    mkdir -p "$CONFIG/$folder"
done
mkdir -p "$COMPOSE"

# --------------------------
# 7. Set ownership and permissions
# --------------------------
echo "=== Setting ownership to UID:$TARGET_UID GID:$TARGET_GID ==="
chown -R $TARGET_UID:$TARGET_GID "$MEDIA"
chown -R $TARGET_UID:$TARGET_GID "$APPDATA"
chmod -R 775 "$MEDIA"
chmod -R 775 "$APPDATA"

# --------------------------
# 8. Choose VPN type
# --------------------------
echo "Choose VPN type:"
select vpn_type in "OpenVPN" "WireGuard"; do
    case $REPLY in
        1)
            VPN_TYPE="openvpn"
            read -p "Enter VPN provider (e.g., privado, pia, mullvad): " VPN_PROVIDER
            echo "Paste your OpenVPN .ovpn contents (end with CTRL+D):"
            cat > "$GLUETUN_CONFIG/custom.ovpn"
            chmod 600 "$GLUETUN_CONFIG/custom.ovpn"
            echo "Enter VPN username:"
            read VPN_USER
            read -s -p "Enter VPN password: " VPN_PASS
            echo
            echo "$VPN_USER
$VPN_PASS" > "$GLUETUN_AUTH/openvpn-credentials.txt"
            chmod 600 "$GLUETUN_AUTH/openvpn-credentials.txt"
            break
            ;;
        2)
            VPN_TYPE="wireguard"
            echo "Paste your WireGuard .conf contents (end with CTRL+D):"
            cat > "$GLUETUN_CONFIG/wireguard.conf"
            chmod 600 "$GLUETUN_CONFIG/wireguard.conf"
            VPN_PROVIDER="custom"
            VPN_USER=""
            VPN_PASS=""
            break
            ;;
        *)
            echo "Invalid option. Enter 1 or 2."
            ;;
    esac
done

# --------------------------
# 9. Tailscale auth key
# --------------------------
echo "To enable Tailscale remote access, provide your reusable auth key:"
read -p "TS Auth Key: " TS_AUTHKEY

# --------------------------
# 10. Create .env
# --------------------------
ENV_FILE="$COMPOSE/.env"
cat > "$ENV_FILE" <<EOL
PUID=$TARGET_UID
PGID=$TARGET_GID
TZ=America/Toronto
VPN_TYPE=$VPN_TYPE
VPN_SERVICE_PROVIDER=$VPN_PROVIDER
OPENVPN_USER=$VPN_USER
OPENVPN_PASSWORD=$VPN_PASS
TS_AUTHKEY=$TS_AUTHKEY
EOL
chmod 640 "$ENV_FILE"

# --------------------------
# 11. Docker Compose
# --------------------------
COMPOSE_FILE="$COMPOSE/docker-compose.yml"
cat > "$COMPOSE_FILE" <<EOL
version: '3.9'

services:
  gluetun:
    image: qmcgaw/gluetun
    container_name: gluetun
    cap_add:
      - NET_ADMIN
    volumes:
      - $GLUETUN_CONFIG:/gluetun
EOL

# Add VPN-specific mount
if [ "$VPN_TYPE" = "openvpn" ]; then
cat >> "$COMPOSE_FILE" <<EOL
      - $GLUETUN_CONFIG/custom.ovpn:/gluetun/custom.ovpn
      - $GLUETUN_AUTH/openvpn-credentials.txt:/gluetun/auth/openvpn-credentials.txt
EOL
elif [ "$VPN_TYPE" = "wireguard" ]; then
cat >> "$COMPOSE_FILE" <<EOL
      - $GLUETUN_CONFIG/wireguard.conf:/gluetun/wireguard.conf
EOL
fi

cat >> "$COMPOSE_FILE" <<EOL
    environment:
      - PUID=$TARGET_UID
      - PGID=$TARGET_GID
      - TZ=America/Toronto
      - VPN_TYPE=$VPN_TYPE
      - VPN_SERVICE_PROVIDER=$VPN_PROVIDER
      - OPENVPN_USER=$VPN_USER
      - OPENVPN_PASSWORD=$VPN_PASS
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

chmod 644 "$COMPOSE_FILE"

# --------------------------
# 12. Start containers
# --------------------------
docker compose -f "$COMPOSE_FILE" up -d

echo "=== Setup complete ==="
