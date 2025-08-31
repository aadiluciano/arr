# arr
arr-srack
TrueNAS SCALE Media Server Setup — All-in-One Guide

1. Pre-requisites

   TrueNAS SCALE installed and running

   VPN credentials (OpenVPN or WireGuard conf)

   Reusable Tailscale auth key (https://login.tailscale.com/admin/settings/keys)

2. Load the .sh file onto your system.

wget URL to RAW .sh script

3. Run the .sh Script
system.

bash setup_media_server.sh

4. Follow the prompts:

   Enter pool name

   Select VPN type (OpenVPN or WireGuard)

   Enter VPN credentials or paste WireGuard conf

   Paste your Tailscale reusable auth key

The script will create the file structure, set ownership/permissions, generate .env and docker-compose.yml, and start all containers.

5. Verify Containers Are Running

docker compose -f /mnt/<POOL>/appdata/compose/docker-compose.yml ps

Expected apps/services:

Container (Description)
radarr (Movie manager)
sonarr (TV manager)
jellyfin (Media server)
prowlarr (Indexer manager)
jellyseerr (Media request system)
gluetun (VPN container)
qbittorrent (Torrent client) (VPN-protected)
tailscale (Remote access service)

6. Verify Matching UID/GID for All Apps

for app in radarr sonarr jellyfin prowlarr jellyseerr qbittorrent gluetun tailscale; do
  echo "Checking $app:"
  docker exec -it $app id
done

7. Set up qBittorrent WebUI Credentials

	a.	Open qBittorrent WebUI http://<LAN_IP>:8080
	b.	Navigate to Tools → Options → Web UI
	c.	Set:
	•	Username
	•	Password
	•	Enable authentication
	d.	Save settings.

8. Verify VPN Routing

Verify Gluetun VPN Routing
a.	Enter Gluetun container:
docker exec -it gluetun sh
b.	Check public IP:
curl ifconfig.me

Should not be your LAN IP — confirms torrent traffic is routed through VPN.

Verify qBittorrent VPN Routing
	•	Open WebUI → Settings → Connection → External IP check
	•	Should show VPN IP, not your local IP
	•	Optional: test torrent download to confirm VPN routing

9. Check App Access on LAN

App (URL)
Radarr (http://<LAN_IP>:7878)
Sonarr (http://<LAN_IP>:8989)
Jellyfin (http://<LAN_IP>:8096)
Prowlarr (http://<LAN_IP>:9696)
Jellyseerr (http://<LAN_IP>:5055)
qBittorrent (http://<LAN_IP>:8080) (behind VPN)

10. Tailscale Remote Access

a. Find your Tailscale IP:

docker exec -it tailscale tailscale ip

b. Access apps remotely using Tailscale IP:

App (URL)
Radarr (http://<TAILSCALE_IP>:7878)
Sonarr (http://<TAILSCALE_IP>:8989)
Jellyfin (http://<TAILSCALE_IP>:8096)
Prowlarr (http://<TAILSCALE_IP>:9696)
Jellyseerr (http://<TAILSCALE_IP>:5055)
qBittorrent (http://<TAILSCALE_IP>:8080)

11. Link Apps to qBittorrent

	a.	In Radarr/Sonarr, Settings → Download Clients → Add qBittorrent
	b.	Enter:
	•	Host/IP: qbittorrent (if using Docker network) or LAN IP
	•	Port: 8080
	•	Username/Password: credentials set in Step 5
	c.	Click Test → should succeed

12. Link Prowlarr to Radarr and Sonarr, and Configure Trackers

	a.	Open Prowlarr WebUI → Settings → Apps/Indexers
	b.	Add Radarr:
	•	Host/IP: radarr (Docker network) or LAN IP
	•	Port: 7878
	•	API Key: copied from Radarr → Settings → General → Security
	c.	Add Sonarr:
	•	Host/IP: sonarr (Docker network) or LAN IP
	•	Port: 8989
	•	API Key: copied from Sonarr → Settings → General → Security
	d.	Configure Trackers/Indexers:
	•	Go to Indexers → Add Indexer
	•	Add your preferred torrent or usenet indexers (public or private)
	•	Test each indexer → Ensure status shows OK
	e.	Save changes → Prowlarr will now automatically manage indexers for Radarr and Sonarr

13. Link Jellyseerr to Radarr and Sonarr

	a.	Open Jellyseerr WebUI → Settings → Movie & TV → Connectors
	b.	Add Radarr:
	•	Host/IP: radarr (Docker network) or LAN IP
	•	Port: 7878
	•	API Key: copied from Radarr Settings → General → Security
	c.	Add Sonarr:
	•	Host/IP: sonarr (Docker network) or LAN IP
	•	Port: 8989
	•	API Key: copied from Sonarr Settings → General → Security
	d.	Save changes → Test connections
