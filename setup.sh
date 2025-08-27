version: "3.9"

services:
  radarr:
    image: linuxserver/radarr:latest
    container_name: radarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/Toronto
    volumes:
      - /mnt/pool1/media/movies:/movies
      - /mnt/pool1/appdata/config/radarr:/config
    ports:
      - 7878:7878
    restart: unless-stopped

  sonarr:
    image: linuxserver/sonarr:latest
    container_name: sonarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/Toronto
    volumes:
      - /mnt/pool1/media/tv:/tv
      - /mnt/pool1/media/downloads:/downloads
      - /mnt/pool1/appdata/config/sonarr:/config
    ports:
      - 8989:8989
    restart: unless-stopped

  jellyfin:
    image: linuxserver/jellyfin:latest
    container_name: jellyfin
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/Toronto
    volumes:
      - /mnt/pool1/media:/media
      - /mnt/pool1/appdata/config/jellyfin:/config
    ports:
      - 8096:8096
    restart: unless-stopped

  radarr-prowler:
    image: linuxserver/prowlarr:latest
    container_name: prowlarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/Toronto
    volumes:
      - /mnt/pool1/appdata/config/prowlarr:/config
    ports:
      - 9696:9696
    restart: unless-stopped

  jellyseer:
    image: fallenbagel/jellyseerr:latest
    container_name: jellyseerr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/Toronto
    volumes:
      - /mnt/pool1/appdata/config/jellyseerr:/config
    ports:
      - 5055:5055
    restart: unless-stopped
