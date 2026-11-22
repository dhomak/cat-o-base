#!/usr/bin/env bash
# Pet-o-Base installer / updater. Run as root INSIDE a Debian 12/13 container or VM.
#   ./install.sh                     install, or update an existing install (data is kept)
#   CATOBASE_PORT=8080 ./install.sh  use a different port
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME=cat-o-base
APP_DIR=/opt/$NAME
DATA_DIR="${CATOBASE_DATA:-/var/lib/$NAME}"
PORT="${CATOBASE_PORT:-8000}"
SVC_USER=catobase

[[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }

echo "==> Checking network"
if ! getent hosts deb.debian.org >/dev/null; then
  echo "!! Can't resolve deb.debian.org. Check the container's DNS setting."; exit 1
fi
if ! ip route | grep -q '^default'; then
  echo "!! No default route. Set a Gateway on the container's network device (Proxmox: CT > Network > net0)."; exit 1
fi

echo "==> Installing packages"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 python3-venv ca-certificates >/dev/null

# --- migrate a pre-rename "catdb" install, if present -------------------------
if [[ -d /var/lib/catdb && ! -e "$DATA_DIR" && -z "${CATOBASE_DATA:-}" ]]; then
  echo "==> Migrating old catdb install"
  systemctl disable --now catdb 2>/dev/null || true
  mv /var/lib/catdb "$DATA_DIR"
  rm -f /etc/systemd/system/catdb.service
  rm -rf /opt/catdb
  id catdb &>/dev/null && userdel catdb 2>/dev/null || true
fi

echo "==> Creating user and folders"
id "$SVC_USER" &>/dev/null || useradd --system --home-dir "$DATA_DIR" --shell /usr/sbin/nologin "$SVC_USER"
mkdir -p "$APP_DIR" "$DATA_DIR/media"
rm -rf "$APP_DIR/templates" "$APP_DIR/static"
cp -r "$SRC/app.py" "$SRC/requirements.txt" "$SRC/templates" "$SRC/static" "$APP_DIR/"
chown -R "$SVC_USER:$SVC_USER" "$DATA_DIR"

echo "==> Setting up Python environment"
[[ -d "$APP_DIR/venv" ]] || python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install -q --upgrade pip
"$APP_DIR/venv/bin/pip" install -q -r "$APP_DIR/requirements.txt"

echo "==> Installing service"
cat >/etc/systemd/system/$NAME.service <<EOF
[Unit]
Description=Pet-o-Base
After=network-online.target
Wants=network-online.target

[Service]
User=$SVC_USER
Group=$SVC_USER
WorkingDirectory=$APP_DIR
Environment=CATOBASE_DATA=$DATA_DIR
ExecStart=$APP_DIR/venv/bin/gunicorn -w 2 -b 0.0.0.0:$PORT --timeout 300 app:app
Restart=on-failure
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable -q $NAME
systemctl restart $NAME
sleep 2
if systemctl is-active --quiet $NAME; then
  echo "==> Pet-o-Base is running: http://$(hostname -I | awk '{print $1}'):$PORT"
else
  echo "!! Service failed to start:"; journalctl -u $NAME -n 30 --no-pager; exit 1
fi
