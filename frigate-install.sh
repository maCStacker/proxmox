cat > /root/install-frigate-0152.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

FRIGATE_VERSION="0.15.2"
FRIGATE_IMAGE="ghcr.io/blakeblackshear/frigate:${FRIGATE_VERSION}"
APP_DIR="/opt/frigate"
CFG_DIR="/etc/frigate"
MEDIA_DIR="/var/lib/frigate"

echo "==> Installing prerequisites"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release jq

echo "==> Installing Docker Engine + Compose plugin"
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") $(. /etc/os-release; echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker

echo "==> Creating directories"
mkdir -p "$APP_DIR" "$CFG_DIR" "$MEDIA_DIR"
# 1GB Cache im RAM
grep -q '^tmpfs /tmp/cache ' /etc/fstab || echo 'tmpfs /tmp/cache tmpfs defaults,size=1024m 0 0' >> /etc/fstab
mkdir -p /tmp/cache
mount -a || true

echo "==> Writing minimal Frigate config (/etc/frigate/config.yml)"
cat >"${CFG_DIR}/config.yml" <<'YML'
mqtt:
  enabled: false
go2rtc:
  streams: {}
cameras: {}
YML

echo "==> Writing Docker Compose file"
cat >"${APP_DIR}/compose.yml" <<EOFY
services:
  frigate:
    container_name: frigate
    image: ${FRIGATE_IMAGE}
    privileged: true
    restart: unless-stopped
    shm_size: "512m"
    volumes:
      - ${CFG_DIR}:/config
      - ${MEDIA_DIR}:/media/frigate
      - type: tmpfs
        target: /tmp/cache
        tmpfs:
          size: 1073741824
    devices:
      - /dev/dri:/dev/dri    # Intel iGPU (entfernen, falls nicht vorhanden)
    ports:
      - "5000:5000"          # Web UI
      - "8554:8554"          # RTSP
      - "8555:8555/tcp"      # WebRTC TCP
      - "8555:8555/udp"      # WebRTC UDP
      - "1935:1935"          # RTMP (optional)
    environment:
      - FRIGATE_RTSP_PASSWORD=
EOFY

echo "==> Creating systemd service"
cat >/etc/systemd/system/frigate-docker.service <<EOF
[Unit]
Description=Frigate (Docker Compose)
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${APP_DIR}
ExecStart=/usr/bin/docker compose -f ${APP_DIR}/compose.yml up -d
ExecStop=/usr/bin/docker compose -f ${APP_DIR}/compose.yml down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now frigate-docker

echo "==> Pulling image and starting Frigate ${FRIGATE_VERSION}"
docker pull "${FRIGATE_IMAGE}"
docker compose -f "${APP_DIR}/compose.yml" up -d

echo "==> Done. Aufruf: http://<IP>:5000  (Kameras später in /etc/frigate/config.yml ergänzen)"
EOF

chmod +x /root/install-frigate-0152.sh
/root/install-frigate-0152.sh
