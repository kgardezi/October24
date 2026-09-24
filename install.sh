#!/usr/bin/env bash
# =====================================================================
#  Idea Board — install or update the team server as a Linux service
#  (for servers without Docker). Run from the unzipped idea-board folder:
#
#     sudo ./install.sh                 # install or update, port 8080
#     sudo ./install.sh --port 9090     # use another port
#     sudo ./install.sh --uninstall     # remove the service (boards are kept)
#
#  Needs: Linux with systemd, Node.js 18 or newer. No internet access needed.
#  Boards are stored in /var/lib/idea-board — re-running this script to
#  update never touches them.
# =====================================================================
set -euo pipefail

APP_DIR=/opt/idea-board
DATA_DIR=/var/lib/idea-board
SVC=idea-board
SVC_USER=ideaboard
PORT=8080
ACTION=install

while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT="${2:-}"; shift 2 ;;
    --port=*) PORT="${1#*=}"; shift ;;
    --uninstall) ACTION=uninstall; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1  (try --help)"; exit 1 ;;
  esac
done

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m ✗ %s\033[0m\n' "$*"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Please run with sudo:  sudo ./install.sh"
command -v systemctl >/dev/null 2>&1 || die "systemd (systemctl) not found — run 'node server/server.js' manually instead."
[[ "$PORT" =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || die "Invalid port: $PORT"

# ---------------------------------------------------------------- uninstall
if [ "$ACTION" = uninstall ]; then
  say "Removing the $SVC service"
  systemctl disable --now "$SVC" 2>/dev/null || true
  rm -f "/etc/systemd/system/$SVC.service"; systemctl daemon-reload
  rm -rf "$APP_DIR"
  ok "Service and program files removed."
  warn "Your boards are still in $DATA_DIR — delete that folder yourself if you no longer need them."
  exit 0
fi

# ---------------------------------------------------------------- checks
SRC="$(cd "$(dirname "$0")" && pwd)"
for f in index.html server/server.js; do
  [ -f "$SRC/$f" ] || die "Missing $f — run this script from the unzipped idea-board folder."
done

NODE="$(command -v node || true)"
[ -n "$NODE" ] || die "Node.js not found. Install Node.js 18 or newer first (see README: 'Without Docker')."
NODE="$(readlink -f "$NODE")"
NODE_MAJOR="$("$NODE" -p 'process.versions.node.split(".")[0]')"
[ "$NODE_MAJOR" -ge 18 ] || die "Node.js $("$NODE" --version) is too old — version 18 or newer is needed."
ok "Node.js $("$NODE" --version) at $NODE"

UPDATE=no; [ -f "/etc/systemd/system/$SVC.service" ] && UPDATE=yes

# ---------------------------------------------------------------- user & folders
if ! id "$SVC_USER" >/dev/null 2>&1; then
  NOLOGIN="$(command -v nologin || echo /sbin/nologin)"
  useradd --system --home-dir "$DATA_DIR" --shell "$NOLOGIN" "$SVC_USER"
  ok "Created service account '$SVC_USER'"
fi
mkdir -p "$APP_DIR/server" "$DATA_DIR"
chown "$SVC_USER:" "$DATA_DIR"; chmod 750 "$DATA_DIR"

# ---------------------------------------------------------------- program files
say "Copying program files to $APP_DIR"
install -m 644 "$SRC/index.html" "$APP_DIR/index.html"
install -m 644 "$SRC/server/server.js" "$APP_DIR/server/server.js"
for f in FONT-LICENSE.txt README.md; do [ -f "$SRC/$f" ] && install -m 644 "$SRC/$f" "$APP_DIR/$f"; done
chown -R root:root "$APP_DIR"; chmod 755 "$APP_DIR" "$APP_DIR/server"
ok "Program files in place"

# ---------------------------------------------------------------- service
say "Writing /etc/systemd/system/$SVC.service (port $PORT)"
cat > "/etc/systemd/system/$SVC.service" <<UNIT
[Unit]
Description=Idea Board team server
After=network.target

[Service]
Type=simple
User=$SVC_USER
Group=$SVC_USER
WorkingDirectory=$APP_DIR
Environment=PORT=$PORT
Environment=DATA_DIR=$DATA_DIR
ExecStart=$NODE $APP_DIR/server/server.js
Restart=on-failure
RestartSec=3
TimeoutStopSec=10
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
ReadWritePaths=$DATA_DIR

[Install]
WantedBy=multi-user.target
UNIT
# SELinux: make sure the copied files carry normal labels
command -v restorecon >/dev/null 2>&1 && restorecon -R "$APP_DIR" "$DATA_DIR" 2>/dev/null || true

systemctl daemon-reload
systemctl enable "$SVC" >/dev/null 2>&1
if [ "$UPDATE" = yes ]; then systemctl restart "$SVC"; else systemctl start "$SVC"; fi

# ---------------------------------------------------------------- firewall
if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
  firewall-cmd --quiet --permanent --add-port="$PORT/tcp" && firewall-cmd --quiet --reload && ok "firewalld: opened port $PORT/tcp"
elif command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow "$PORT/tcp" >/dev/null && ok "ufw: opened port $PORT/tcp"
else
  warn "No active firewalld/ufw found — make sure port $PORT/tcp is reachable if you use another firewall."
fi

# ---------------------------------------------------------------- health check
say "Checking the server"
HEALTH=""
for i in 1 2 3 4 5 6 7 8 9 10; do
  if command -v curl >/dev/null 2>&1; then HEALTH="$(curl -fs "http://127.0.0.1:$PORT/api/health" || true)"
  elif command -v wget >/dev/null 2>&1; then HEALTH="$(wget -qO- "http://127.0.0.1:$PORT/api/health" || true)"
  else HEALTH="$("$NODE" -e "fetch('http://127.0.0.1:$PORT/api/health').then(r=>r.text()).then(t=>console.log(t)).catch(()=>{})")"; fi
  echo "$HEALTH" | grep -q idea-board && break
  sleep 1
done
if echo "$HEALTH" | grep -q idea-board; then
  ok "Idea Board is running"
else
  systemctl --no-pager status "$SVC" | tail -n 15 || true
  die "The server did not answer on port $PORT — see: journalctl -u $SVC -n 50"
fi

HOSTS="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo
[ "$UPDATE" = yes ] && ok "Updated. Your boards in $DATA_DIR were kept." || ok "Installed."
echo "   Open:     http://${HOSTS:-<server>}:$PORT"
echo "   Logs:     journalctl -u $SVC -f"
echo "   Restart:  sudo systemctl restart $SVC"
echo "   Backup:   sudo tar czf ideaboard-\$(date +%F).tgz -C /var/lib idea-board"
echo "   Update:   unzip the new version and run  sudo ./install.sh  again"
