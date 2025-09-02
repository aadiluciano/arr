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

# Detect truenas_admin UID/GID
USER_ID=$(id -u truenas_admin)
GROUP_ID=$(id -g truenas_admin)

# Create required directories
mkdir -p "$MEDIA"
mkdir -p "$COMPOSE"
mkdir -p "$CONFIG"

# ==========================
# Ask about deleting configs
# ==========================
read -p "Do you want to delete ALL old app config data and start fresh? (y/N): " WIPE
if [[ "$WIPE" =~ ^[Yy]$ ]]; then
  echo "Wiping old config data..."
  rm -rf "$CONFIG"
  mkdir -p "$CONFIG"
else
  echo "Preserving existing config data."
fi

# Media preservation
if [ -d "$MEDIA" ]; then
  echo "Media directory already exists — preserving it."
else
  echo "Creating fresh media directory."
  mkdir -p "$MEDIA"
fi

# ==========================
# Permissions
# ==========================
chown -R truenas_admin:truenas_admin "$APPDATA"
chmod -R 755 "$APPDATA"

# ==========================
# Get WireGuard config details
# ==========================
echo "Paste your WireGuard .conf contents (end with CTRL+D):"
WG_CONF=$(</dev/stdin)

# Secrets dir
mkdir -p "$CONFIG/gluetun/secrets"
echo "$WG_CONF" > "$CONFIG/gluetun/secrets/wg0.conf"

# ==========================
# Create .env file
# ==========================
cat > "$COMPOSE/.env" <<EOF
PUID=$USER_ID
PGID=$GROUP_ID
TZ=America/Toronto
EOF

# ==========================
# Create docker-compose.yml
# ==========================
cat > "$COMPOSE/docker-compose.yml" <<EOF
version: "3.9"

services:
  # ==========================
  # VPN base
  # ==========================
  gluetun:
    image: qmcgaw/gluetun
    container_name: gluetun
    cap_add:
      - NET_ADMIN
    networks:
      - app_net
    environment:
      - PUID=\${PUID}
      - PGID=\${PGID}
      - TZ=\${TZ}
      - VPN_TYPE=wireguard
      - VPN_SERVICE_PROVIDER=custom
      - WIREGUARD_CONF_SECRETFILE=/run/secrets/wg0.conf
    volumes:
      - $CONFIG/gluetun/secrets:/run/secrets:ro
    ports:
      - 8080:8080/tcp   # optional Gluetun UI
      - 8081:8081       # qbittorrent
      - 8989:8989       # sonarr
      - 7878:7878       # radarr
      - 9696:9696       # prowlarr
      - 6767:6767       # bazarr
    restart: unless-stopped

  # ==========================
  # Downloads
  # ==========================
  qbittorrent:
    image: linuxserver/qbittorrent
    container_name: qbittorrent
    depends_on:
      - gluetun
    network_mode: "service:gluetun"
    environment:
      - PUID=\${PUID}
      - PGID=\${PGID}
      - TZ=\${TZ}
      - WEBUI_PORT=8081
    volumes:
      - $CONFIG/qbittorrent:/config
      - $MEDIA:/media
    restart: unless-stopped

  # ==========================
  # Media Server
  # ==========================
  jellyfin:
    image: linuxserver/jellyfin
    container_name: jellyfin
    networks:
      - app_net
    environment:
      - PUID=\${PUID}
      - PGID=\${PGID}
      - TZ=\${TZ}
    volumes:
      - $CONFIG/jellyfin:/config
      - $MEDIA:/media
    ports:
      - 8096:8096
    restart: unless-stopped

  # ==========================
  # Media Automation
  # ==========================
  sonarr:
    image: linuxserver/sonarr
    container_name: sonarr
    depends_on:
      - gluetun
    network_mode: "service:gluetun"
    environment:
      - PUID=\${PUID}
      - PGID=\${PGID}
      - TZ=\${TZ}
    volumes:
      - $CONFIG/sonarr:/config
      - $MEDIA:/media
    restart: unless-stopped

  radarr:
    image: linuxserver/radarr
    container_name: radarr
    depends_on:
      - gluetun
    network_mode: "service:gluetun"
    environment:
      - PUID=\${PUID}
      - PGID=\${PGID}
      - TZ=\${TZ}
    volumes:
      - $CONFIG/radarr:/config
      - $MEDIA:/media
    restart: unless-stopped

  prowlarr:
    image: linuxserver/prowlarr
    container_name: prowlarr
    depends_on:
      - gluetun
    network_mode: "service:gluetun"
    environment:
      - PUID=\${PUID}
      - PGID=\${PGID}
      - TZ=\${TZ}
    volumes:
      - $CONFIG/prowlarr:/config
    restart: unless-stopped

  bazarr:
    image: linuxserver/bazarr
    container_name: bazarr
    depends_on:
      - gluetun
    network_mode: "service:gluetun"
    environment:
      - PUID=\${PUID}
      - PGID=\${PGID}
      - TZ=\${TZ}
    volumes:
      - $CONFIG/bazarr:/config
      - $MEDIA:/media
    restart: unless-stopped

  # ==========================
  # Request Manager
  # ==========================
  jellyseerr:
    image: fallenbagel/jellyseerr
    container_name: jellyseerr
    networks:
      - app_net
    environment:
      - PUID=\${PUID}
      - PGID=\${PGID}
      - TZ=\${TZ}
    volumes:
      - $CONFIG/jellyseerr:/app/config
    ports:
      - 5055:5055
    restart: unless-stopped

  # ==========================
  # Remote access (optional)
  # ==========================
  tailscale:
    image: tailscale/tailscale
    container_name: tailscale
    hostname: truenas-tailscale
    networks:
      - app_net
    volumes:
      - $CONFIG/tailscale:/var/lib/tailscale
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    command: tailscaled
    restart: unless-stopped

networks:
  app_net:
    driver: bridge
EOF

# ==========================
# Done
# ==========================
echo "Setup complete."
echo "Navigate to $COMPOSE and run: docker compose up -d"
