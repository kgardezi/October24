# Idea Board

A self-hosted whiteboard for network diagrams: routers, switches, firewalls, WAN
circuits and the links between them. It feels like tldraw (infinite canvas, bottom
toolbar, floating style panel) and has network-specific parts built in.

It runs in two modes from the same `index.html`:

| | **Team server** (Docker) | **Personal** (just the file) |
|---|---|---|
| How | `docker compose up -d --build`, or `sudo ./install.sh` without Docker | open `index.html`, or put it on any web server |
| Boards stored | on the server (`/data` volume) | in each person's browser |
| Team boards | ✅ everyone can open and edit them **live together** | — |
| Private boards | ✅ each person's own, listed only for them | ✅ |
| Live cursors, shared laser pointer, who's online | ✅ | — |
| Internet needed | no | no |

The app switches to team mode by itself when the Idea Board server serves it.

---

## Team server: set-up (Linux + Docker)

```bash
# copy this folder to the server, then:
cd idea-board
docker compose up -d --build
# open  http://<server-name-or-ip>:8080
```

- The first person to open it creates the first **team board**, which contains the sample network.
- Everyone types their name once. It's remembered on their computer, and the avatar at
  the top left lets them change it.
- **Boards button** (the four squares next to the menu):
  - **+ Team board**: everyone on the server can open it and edit it live.
  - **+ Private board**: listed only for you. Owners can switch a board between team
    and private with the share/lock button.
- Stop: `docker compose down`. Update: copy the new files, then `docker compose up -d --build`.
- Logs: `docker compose logs -f`.

**Air-gapped server:** the build only needs the `node:22-alpine` image (no npm packages).
If the server has no internet, build on a machine that does, then copy the image across:

```bash
docker compose build && docker save idea-board:latest | gzip > idea-board-image.tgz
# on the server:
gunzip -c idea-board-image.tgz | docker load && docker compose up -d
```

**HTTPS / a friendly URL:** put it behind your nginx using `nginx-reverse-proxy.conf`.
The WebSocket headers in that file are required for live editing.

### Without Docker (Node.js service)

This needs Node.js 18 or newer on the server (`node --version`). No npm packages and no internet access are needed.

- **RHEL/Rocky/Alma:** `sudo dnf install nodejs`, or `sudo dnf module install nodejs:20`.
- **Ubuntu 24.04 / Debian 12:** `sudo apt install nodejs`.
- **Offline server:** copy the "Linux x64" tarball from nodejs.org onto it, extract it to `/opt`, and
  link `bin/node` to `/usr/bin/node`.

Then, from the unzipped folder:

```bash
sudo ./install.sh                 # install or update, http://<server>:8080
sudo ./install.sh --port 9090     # another port
sudo ./install.sh --uninstall     # remove the service; boards are kept
```

The script:
- installs the app to `/opt/idea-board`
- keeps boards in `/var/lib/idea-board`
- runs the server as an unprivileged `ideaboard` user, as a systemd service that starts on boot and restarts if it crashes
- opens the port in firewalld/ufw
- checks that the server answers

To update, unzip the new version and run `sudo ./install.sh` again; your boards are never touched.
Logs: `journalctl -u idea-board -f`.
`deploy/idea-board.service` is the same service file, for manual set-up.

Just trying it out? Run `node server/server.js` in the unzipped folder (boards go to `server/data`).

### Backups

Everything is inside the `/data` volume (Docker) or `/var/lib/idea-board` (install.sh):

- `index.json`: the list of boards, with owner, team/private, last edited time and who edited it.
- `boards/<id>.json`: one file per board, with its pages, shapes and pictures.
- Deleted boards are renamed `…deleted-<time>.json` rather than removed, so they can be recovered.

```bash
docker compose cp idea-board:/data ./ideaboard-backup-$(date +%F)     # Docker
sudo tar czf ideaboard-$(date +%F).tgz -C /var/lib idea-board          # Node.js service (install.sh)
```

Restore a board file by copying it back into `boards/` (keep its entry in `index.json`) and restarting.

### Capacity

The server is a single small Node.js process. In testing, **30 users drawing on the same board at
once** (600 shapes, 17,400 live updates and 17,400 cursor moves) were all delivered in 2.6 s, with the
server using about 60 MB of memory and 2% CPU. Boards are kept in memory only while someone has them open.

### Security

This mode is meant for a **trusted internal network**. There are no passwords: people are
identified by the name they type.

- Private boards are hidden from other people's lists, but anyone who types the same name, or
  knows a board's ID, could open it. Don't put secrets on the board.
- Only the owner can delete a board or change its sharing, and the server keeps a backup copy
  of anything deleted.
- If you later need real logins, AD/LDAP sign-in can be added to the server.

### How live editing works

- Every change is sent item by item: move a device and only that device is sent. If two people
  change the same item at the same moment, the last change wins.
- **Undo only undoes your own changes.** It never removes something a teammate did.
- If the connection drops, the dot next to your avatar turns red. You can keep working, and your
  changes are sent automatically when it reconnects.
- Your zoom and scroll position is yours alone; it isn't forced on others.

---

## Features

- Infinite canvas: pan (wheel, Space-drag, H), zoom (Ctrl + wheel, pinch), dot grid, snap to grid
- Network library: router, L3 switch, switch, firewall, load balancer, server, ISE/NAC,
  AP, WLC, NTE/CPE, endpoint, IP phone; Internet / MPLS / cloud; zones (site frames)
- **Links attach to devices** and follow them when you move them. A link can be straight,
  curved (drag its middle handle) or elbowed.
- Link types: Ethernet, single-mode fibre (yellow), multimode fibre (orange), 802.1Q trunk,
  port-channel/vPC, WAN circuit, VPN, OOB management
- Each link can carry a label (e.g. `CCT-10023 · 1G`) plus **A-end and B-end port labels** (e.g. `Te1/1/1`, `Eth1/49`)
- **Rack view**: any device can be drawn as a 1U chassis bar instead of an icon.
  - The layer/role (SF, AS, CL, …) is written large on the right side of the bar.
  - The hostname can optionally go inside the bar ("Name inside").
- Device hostname, a free-text info block (mgmt IP, model, code version), and a
  **role badge** (CL / DL / AG / ML / AS / SF / MX / WAN / DMZ)
- Zones act like frames: moving a zone moves the devices inside it
- Shapes can have hand-drawn (tldraw-style) or clean outlines
- Pencil with smooth, pressure-sensitive strokes (P), eraser (E), arrows
- **Four fonts** for each item: Hand-drawn, Sans, Serif, Mono
- **Pictures**: paste a screenshot (Ctrl+V), drag an image file in, or press I.
  - Draw on a picture or point at it with the laser.
  - Lock it (Ctrl+Shift+L) so it doesn't move.
- **Laser pointer (K)**, the same as tldraw's. The trail fades 1.2 s after you stop, and on a team
  board everyone sees it.
- **Pages**: numbered pages with optional names ("Page 1 · Mexico"); PageUp / PageDown switch pages
- Alignment guides, tool lock (Q), align/distribute, duplicate (Ctrl D or Alt-drag), copy/paste, undo/redo
- Save and open `.ideaboard.json` files; export PNG or SVG (only the selection, if something is selected)
- Light and dark themes. Press `?` in the app for all keyboard shortcuts.

## Personal mode: where data lives

When `index.html` is opened directly or from a plain web server, every board is saved in that
browser's `localStorage` on that computer. Clearing the browser's site data removes the boards.
Use **Menu → Save to file** for backups; the files are plain JSON.

## Customising

The app is all in `index.html`:
- `DEVICES`: device types. Icons are SVG paths drawn on a 48×48 grid.
- `LINKS`: link-type presets (colour, dash, width).
- `ROLES`: role badge names and colours.
- `COLORS`: the palette (light and dark values).

The server is `server/server.js`: about 330 lines of plain Node.js with no dependencies.

## Licences

Idea Board: MIT.

The canvas font is a Latin-only subset of **Shantell Sans Informal**, the hand-drawn font tldraw
uses. It is embedded in `index.html` and licensed under the SIL Open Font License 1.1; see
`FONT-LICENSE.txt`. The Sans, Serif and Mono options use fonts already installed on each computer.
