#!/bin/bash
# ==========================
# TrueNAS SCALE Media Server Setup with Gluetun VPN
# Full media stack with secrets
# ==========================

TARGET_UID=950
TARGET_GID=950
TRUENAS_USER=truenas_admin
USER_ID=$TARGET_UID
GROUP_ID=$TARGET_GID

echo "Target UID:GID = $TARGET_UID:$TARGET_GID ($TRUENAS_USER)"

# --------------------------
# 1. Prompt for pool name
# --------------------------
read -p "Enter your TrueNAS pool name: " POOL

MEDIA="/mnt/$POOL/media"
APPDATA="/mnt/$POOL/appdata"
COMPOSE="$APPDATA/compose"
CONFIG="$APPDATA/config"
GLUETUN_CONFIG="$CONFIG/gluetun"
GLUETUN_SECRETS="$GLUETUN_CONFIG/secrets"

# --------------------------
# 2. Ask if old config should be deleted
# --------------------------
read -p "Do you want to delete ALL old app config data and start fresh? (y/N): " WIPE
if [[ "$WIPE" =~ ^[Yy]$ ]]; then
  echo "Wiping old config data..."
  rm -rf "$CONFIG"
  mkdir -p "$CONFIG"
else
  echo "Preserving existing config data."
  mkdir -p "$CONFIG"
fi

# --------------------------
# 3. Create datasets if missing
# --------------------------
zfs list "$POOL/media" &>/dev/null || zfs create "$POOL/media"
zfs list "$POOL/appdata" &>/dev/null || zfs create "$POOL/appdata"

# --------------------------
# 4. Create media subfolders
# --------------------------
MEDIA_SUBS=("movies" "tv" "music" "downloads" "downloads/complete" "downloads/incomplete")
for folder in "${MEDIA_SUBS[@]}"; do
    mkdir -p "$MEDIA/$folder"
done

# --------------------------
# 5. Create appdata config folders
# --------------------------
CONFIG_FOLDERS=("radarr" "sonarr" "jellyfin" "prowlarr" "jellyseerr" "gluetun" "qbittorrent" "tailscale")
for folder in "${CONFIG_FOLDERS[@]}"; do
    mkdir -p "$CONFIG/$folder"
done
mkdir -p "$COMPOSE"

# --------------------------
# 6. Set ownership and permissions
# --------------------------
chown -R "$USER_ID:$GROUP_ID" "$MEDIA" "$APPDATA"
chmod -R 775 "$MEDIA" "$APPDATA"

# --------------------------
# 7. VPN selection
# --------------------------
echo "Choose VPN type:"
select vpn_type in "OpenVPN" "WireGuard"; do
  case $REPLY in
    1)
      VPN_TYPE="openvpn"
      read -p "Enter VPN provider (e.g., privado, pia, mullvad): " VPN_PROVIDER
      read -p "Enter VPN username: " VPN_USER
      read -s -p "Enter VPN password: " VPN_PASS
      echo
      mkdir -p "$GLUETUN_SECRETS"
      echo -e "$VPN_USER\n$VPN_PASS" > "$GLUETUN_SECRETS/auth.conf"
      chmod 600 "$GLUETUN_SECRETS/auth.conf"
      break
      ;;
    2)
      VPN_TYPE="wireguard"
      mkdir -p "$GLUETUN_SECRETS"
      echo "Paste your WireGuard .conf contents (end with CTRL+D):"
      cat > "$GLUETUN_SECRETS/wg0.conf"

      # Extract keys automatically
      grep -i '^PrivateKey' "$GLUETUN_SECRETS/wg0.conf" | awk -F'=' '{gsub(/ /,"",$2); print $2}' > "$GLUETUN_SECRETS/wireguard_private_key"
      grep -i '^Address' "$GLUETUN_SECRETS/wg0.conf" | awk -F'=' '{gsub(/ /,"",$2); print $2}' > "$GLUETUN_SECRETS/wireguard_addresses"
      grep -i '^PresharedKey' "$GLUETUN_SECRETS/wg0.conf" | awk -F'=' '{gsub(/ /,"",$2); print $2}' > "$GLUETUN_SECRETS/wireguard_preshared_key"
      chmod 600 "$GLUETUN_SECRETS"/*
      break
      ;;
    *)
      echo "Invalid option. Enter 1 or 2."
      ;;
  esac
done

# --------------------------
# 8. Tailscale auth key
# --------------------------
read -p "Paste your Tailscale reusable auth key: " TS_AUTHKEY

# --------------------------
# 9. Create .env file
# --------------------------
ENV_FILE="$COMPOSE/.env"
cat > "$ENV_FILE" <<EOL
PUID=$TARGET_UID
PGID=$TARGET_GID
TZ=America/Toronto
VPN_TYPE=$VPN_TYPE
VPN_PROVIDER=${VPN_PROVIDER:-}
TS_AUTHKEY=$TS_AUTHKEY
EOL
chmod 640 "$ENV_FILE"

# --------------------------
# 10. Create docker-compose.yml
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
    network_mode: "bridge"
    environment:
      - PUID=\${PUID}
      - PGID=\${PGID}
      - TZ=\${TZ}
      - VPN_TYPE=\${VPN_TYPE}
EOL

if [ "$VPN_TYPE" = "openvpn" ]; then
cat >> "$COMPOSE_FILE" <<EOL
      - VPN_SERVICE_PROVIDER=\${VPN_PROVIDER}
      - OPENVPN_USER_SECRETFILE=/run/secrets/auth.conf
      - OPENVPN_PASSWORD_SECRETFILE=/run/secrets/auth.conf
EOL
elif [ "$VPN_TYPE" = "wireguard" ]; then
cat >> "$COMPOSE_FILE" <<EOL
      - VPN_SERVICE_PROVIDER=custom
      - WIREGUARD_CONF_SECRETFILE=/run/secrets/wg0.conf
      - WIREGUARD_PRIVATE_KEY_SECRETFILE=/run/secrets/wireguard_private_key
      - WIREGUARD_PRESHARED_KEY_SECRETFILE=/run/secrets/wireguard_preshared_key
      - WIREGUARD_ADDRESSES_SECRETFILE=/run/secrets/wireguard_addresses
EOL
fi

cat >> "$COMPOSE_FILE" <<EOL
    volumes:
      - $GLUETUN_SECRETS:/run/secrets:ro
    restart: unless-stopped

  qbittorrent:
    image: linuxserver/qbittorrent
    container_name: qbittorrent
    network_mode: service:gluetun
    depends_on:
      - gluetun
    environment:
      - PUID=\${PUID}
      - PGID=\${PGID}
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
      - PUID=\${PUID}
      - PGID=\${PGID}
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
      - PUID=\${PUID}
      - PGID=\${PGID}
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
      - PUID=\${PUID}
      - PGID=\${PGID}
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
      - PUID=\${PUID}
      - PGID=\${PGID}
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
      - PUID=\${PUID}
      - PGID=\${PGID}
    volumes:
      - $CONFIG/jellyseerr:/config
    ports:
      - 5055:5055
    restart: unless-stopped

  tailscale:
    image: tailscale/tailscale:latest
    container_name: tailscale
    network_mode: "host"
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    volumes:
      - $CONFIG/tailscale:/var/lib/tailscale
    restart: unless-stopped
    command: tailscaled

networks:
  app_net:
    driver: bridge
EOL

chmod 644 "$COMPOSE_FILE"

# --------------------------
# 11. Start containers
# --------------------------
docker compose -f "$COMPOSE_FILE" up -d

echo "=== Setup complete ==="
