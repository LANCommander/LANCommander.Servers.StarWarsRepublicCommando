# Star Wars: Republic Commando Server (Docker)

This repository provides a Dockerized **Star Wars: Republic Commando** dedicated server. Republic Commando is a 2005 squad-based first-person shooter by LucasArts, built on Unreal Engine 2. The game shipped without a dedicated server tool; the image runs the `UCC.exe server` from SWRCFix (by Leon0628, swrc-modding.net) under Wine.
The image builds on [`lancommander/wine`](https://github.com/LANCommander/LANCommander.Servers.WINE). It supports file overlaying using OverlayFS.

---

## Features

- Runs `UCC.exe server` headless (no X display, graphics or sound)
- A separate server ini (`System/Server.ini`) is created from the game's `System.ini`, and the common settings are environment variables
- All four game types: Deathmatch, Team Deathmatch, Capture the Flag and Assault, with short names
- Optional map rotation, including per-map game type and options; maps that aren't installed are left out
- Found by the in-game LAN browser (GameSpy query on 11138/udp)
- UCC's console log goes to `docker logs`
- Supports file overlaying using OverlayFS (no file copying required)

## Docker Compose Example

```yaml
services:
  republiccommando:
    image: lancommander/starwarsrepubliccommando:latest
    container_name: republiccommando

    ports:
      - "7777:7777/udp"
      - "11138:11138/udp"

    volumes:
      - ./config:/config

    environment:
      RC_SERVER_NAME: "My Republic Commando Server"
      RC_GAME_TYPE: "deathmatch"
      RC_MAP: "DM_Canyon"
      RC_MAX_PLAYERS: "16"

    user: root
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

    restart: unless-stopped
```

The in-game LAN browser finds servers by broadcast. That needs the container on the LAN itself (macvlan/ipvlan, or `network_mode: host`). With port mapping, clients join by IP.

---

## Game Files

Republic Commando is retail software with no public download. You must provide the game's `GameData` folder (GOG or Steam; the folder with `System/`, `Maps/`, `Textures/` ...) with **SWRCFix** installed into `System/`, since the game itself has no `UCC.exe`. The image was built and tested with the GOG release and SWRCFix 2.9.

- copy that folder's contents (`System/`, `Maps/`, `Textures/` ...) to `config/Server/`, **or**
- set `RC_ARCHIVE_URL` to a zip of it, e.g. a LANCommander archive. It is downloaded (`file://` URLs are read in place) and extracted on first start, if `Server/System/UCC.exe` doesn't exist yet.

The server doesn't need `Movies/`, `Help/` or `Manual.pdf`; an archive install leaves them out (about 1.7 GB remains).

## Directory Layout (Host)

```text
.
└── config/
    ├── Server/            # GameData folder (System/, Maps/, Textures/ ...)
    ├── Overlay/           # Your files, layered on top of Server/ (System/Server.ini lands here)
    ├── Merged/            # Overlayfs merged view (auto-created, the server runs here)
    ├── wineprefix/        # Wine prefix (auto-created)
    └── Scripts/
        └── Hooks/         # PowerShell scripts run at container lifecycle hooks
```

---

## Environment Variables

These are in addition to the [WINE image's variables](https://github.com/LANCommander/LANCommander.Servers.WINE#environment).
The ini settings are written into `RC_INI` on every start. Settings left empty are not touched, so you can set them in the ini instead.

| Variable | Description | Default |
|----------|-------------|---------|
| `RC_MAP` | Start map | `DM_Canyon` |
| `RC_GAME_TYPE` | `deathmatch`, `teamdeathmatch`, `ctf`, `assault` or a game class, see below | `deathmatch` |
| `RC_MAPS` | Map rotation, comma or space separated, written to the game type's map list. Entries may carry URL options (`DM_Hangar?Game=MPGame.TDGame?GoalScore=40`). Start on the first entry. Empty: the list in the ini is left alone | |
| `RC_URL_OPTIONS` | Extra start map URL options | |
| `RC_INI` | Server ini in `System/`, created from `System.ini` if missing | `Server.ini` |
| `RC_PORT` | Game port, `[URL] Port` | `7777` |
| `RC_SERVER_NAME` | `[Engine.GameReplicationInfo] ServerName` | `Republic Commando Server` |
| `RC_SHORT_NAME` | `[Engine.GameReplicationInfo] ShortName` | `RC Server` |
| `RC_ADMIN_NAME` | `[Engine.GameReplicationInfo] AdminName` | |
| `RC_ADMIN_EMAIL` | `[Engine.GameReplicationInfo] AdminEmail` | |
| `RC_MOTD` | `[Engine.GameReplicationInfo] MOTDLine1` | |
| `RC_MAX_PLAYERS` | `[Engine.GameInfo] MaxPlayers` | `16` |
| `RC_MAX_SPECTATORS` | `[Engine.GameInfo] MaxSpectators` | |
| `RC_GAME_PASSWORD` | `[Engine.AccessControl] GamePassword` | |
| `RC_ADMIN_PASSWORD` | `[Engine.AccessControl] AdminPassword` | |
| `RC_GOAL_SCORE` | `GoalScore` (frag/capture limit) of the started game class | |
| `RC_TIME_LIMIT` | `TimeLimit` in minutes of the started game class | |
| `RC_FRIENDLY_FIRE_SCALE` | Team games: `FriendlyFireScale`, 0 to 1 | |
| `RC_ROUND_TIME` | Team games: `RoundTime` in seconds (Assault rounds) | |
| `RC_NUM_ROUNDS` | Team games: `NumRounds` | |
| `RC_BALANCE_TEAMS` | `true`/`false`: `[MPGame.TDGame] bBalanceTeams` (all team games) | |
| `RC_MASTER_SERVER_UPLINK` | `true` sets `AdvertiseServer=2`, which also reports to the master server in SWRCFix's `GameSpyMgr.dll` | `false` |
| `RC_ARCHIVE_URL` | Zip of the GameData folder, used if `Server/System/UCC.exe` is missing | |
| `WINE_XVFB` | UCC needs no display | `false` |
| `START_EXE` | Launcher | `/usr/local/bin/rc-server` |
| `START_ARGS` | Appended to the UCC command line | |

Game types:

| `RC_GAME_TYPE` | Game class | Map list | Maps |
|----------------|------------|----------|------|
| `deathmatch` (`dm`) | `MPGame.DMGame` | `MPGame.MapListDeathMatch` | `DM_*` |
| `teamdeathmatch` (`tdm`) | `MPGame.TDGame` | `MPGame.MapListTeamDeathMatch` | `DM_*` |
| `ctf` | `MPGame.CTFGame` | `MPGame.MapListCaptureTheFlag` | `CTF_*` |
| `assault` (`as`) | `MPGame.ASGame` | `MPGame.MapListAssault` | `CTF_*` |

Stock maps: `DM_Canyon`, `DM_Detention`, `DM_Engine`, `DM_Hangar`, `DM_HangingGarden`, `DM_POW`, `DM_POWSmall`, `DM_Siege`, `DM_Trando`, `DM_Underpass`, `DM_ZeroG`, and `CTF_Detention`, `CTF_Engine`, `CTF_Hangar`, `CTF_HangingGarden`, `CTF_POW`, `CTF_Siege`, `CTF_Trando`, `CTF_Underpass`, `CTF_ZeroG`.

See [Documentation/Docker.md](Documentation/Docker.md) for more detail.

---

## Building

The image is built `FROM lancommander/wine:latest` by default. To build against a local base image:

```bash
docker build --build-arg BASE_IMAGE=lancommander/wine:local -t lancommander/starwarsrepubliccommando:local .
```

---

## License

Star Wars: Republic Commando, SWRCFix and Wine are distributed under their respective licenses.
This repository contains only Docker build logic and helper scripts licensed under MIT.
