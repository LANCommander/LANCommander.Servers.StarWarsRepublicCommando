---
sidebar_label: Docker
---

# Star Wars: Republic Commando Docker Container

This Docker container runs a Star Wars: Republic Commando dedicated server. It is built on the WINE image and runs the Unreal Engine 2 server, `UCC.exe server`, from SWRCFix. The container doesn't download the game, so you provide the files.

## Quick Start

```yaml
services:
  republiccommando:
    image: lancommander/starwarsrepubliccommando:latest
    container_name: republiccommando

    ports:
      - 7777:7777/udp
      - 11138:11138/udp

    volumes:
      - "/data/Servers/Star Wars - Republic Commando/Deathmatch:/config"

    environment:
      RC_SERVER_NAME: "My Republic Commando Server"
      RC_GAME_TYPE: "deathmatch"
      RC_MAP: "DM_Canyon"
      RC_ADMIN_PASSWORD: "changeme"

    user: root
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

    restart: unless-stopped
```

Copy the game's `GameData` folder (with `System/UCC.exe` from SWRCFix, `System/MPGame.u` and `Maps/`) into `Server/` before the first start. You can instead set `RC_ARCHIVE_URL` to a zip of that folder.

## How It Starts

1. `PostInitialization/10-InitializeWinePrefix.ps1` (from the WINE image) creates the Wine prefix in `/config/wineprefix`.
2. `PostInitialization/20-InstallRepublicCommando.ps1` checks for `Server/System/UCC.exe`. If it's missing and `RC_ARCHIVE_URL` is set, the hook downloads the archive (or reads a `file://` path in place), extracts the folder that holds `System/MPGame.u` and `System/UCC.exe` without `Movies/`, `Help/` and `Manual.pdf`, and remounts the overlay.
3. `PostInitialization/30-ConfigureRepublicCommando.ps1` copies `System/System.ini` to `System/Server.ini` (`RC_INI`) if it doesn't exist yet. It does this through `Merged/`, so the file lands in `Overlay/System/`. It then writes the non-empty `RC_*` settings, the map rotation and `AdvertiseServer` into it.
4. `START_EXE` (`/usr/local/bin/rc-server`) runs `UCC.exe server <RC_MAP>?game=<class> ini=Server.ini log=server.log` from `System/` under Wine, on a pseudo-terminal so its console reaches `docker logs`.

A successful start ends with:

```
Game class is 'DMGame'
...
TcpNetDriver on port 7777
...
Spawning: IpDrv.UdpBeacon
Spawning: IpDrv.MasterServerUplink
...
Exiting LoadMap
```

## Configuration Options

### Ports

- **7777/udp**: Game (`RC_PORT`)
- **11138/udp**: GameSpy query. Fixed; it doesn't follow the game port. Answers `\status\` and GameSpy QR2 queries with the name, map, game type, version (`gamever 2226`), player count and limits. The in-game LAN browser finds servers through it.
- **8777/udp**: UdpBeacon. Bound, but silent with the stock `[IpDrv.UdpBeacon] DoBeacon=False`; not needed.

### Environment Variables

See the [README](../README.md#environment-variables) for the full table.

### Server ini

`Overlay/System/Server.ini` is yours to edit. Only the keys that have a non-empty `RC_*` variable are rewritten on start. Delete the file to regenerate it from `System.ini`.

- `GoalScore` and `TimeLimit` are per game class (`[MPGame.DMGame]`, `[MPGame.TDGame]`, `[MPGame.CTFGame]`, `[MPGame.ASGame]`); `RC_GOAL_SCORE`/`RC_TIME_LIMIT` go to the class being started. The team games also have `FriendlyFireScale`, `RoundTime`, `NumRounds`, `MaxTeamSize` and `bPermanentDeath`; `bBalanceTeams` is `globalconfig` in `[MPGame.TDGame]`.
- Passwords are in `[Engine.AccessControl]` (`AdminPassword`, `GamePassword`), max players in `[Engine.GameInfo]` (`MaxPlayers`, `MaxSpectators`). They are never put on the command line.
- Map rotation: `Maps=` / `Maps+=` lines and `MapNum` in the game type's map list (`[MPGame.MapListDeathMatch]` etc.). Entries may carry URL options, as in the stock `[MPGame.MapListMixedDeathMatch]` example, e.g. `DM_Hangar?Game=MPGame.TDGame?GoalScore=40` to switch game type. With `MapNum=0` the next map is `Maps[1]`, so start on the first entry. `RC_MAPS` rewrites the list and resets `MapNum` on every start; without it the list is left as it is.
- `[IpDrv.MasterServerUplink] AdvertiseServer`: `1` LAN, `2` also the master server. `RC_MASTER_SERVER_UPLINK` sets it.

UCC saves its config to the server ini, so values such as `MapNum` change there after a map change. The `Save/` ini copies the game client layers over `System.ini` don't apply to the server.

### Hooks

| Hook | When |
|------|------|
| `PreInstallRepublicCommando` / `PostInstallRepublicCommando` | Around the game file check/download |
| `PreInitializeWinePrefix` / `PostInitializeWinePrefix` | Around Wine prefix creation (WINE image) |

Put `.ps1` scripts in `config/Scripts/Hooks/<HookName>/`.

## Troubleshooting

- **`System/UCC.exe not found`**: the game has no `UCC.exe`; install SWRCFix into `System/`. `Server/` must contain the GameData folder itself (`Server/System/UCC.exe`), not a folder that contains it.
- **`Commandlet server not found`** when running UCC by hand: happens when the `ini=` file doesn't exist. Run it with an existing ini (the launcher uses `Server.ini`, which the configure hook creates).
- **No output in `docker logs`**: this UCC writes its console only to a terminal, and `server.log` stays empty while the server runs. The launcher runs it under `script(1)` and strips the terminal escape codes; if you replace `START_EXE`, keep that.
- **Server not in the LAN browser**: the browser finds servers by UDP broadcast to 11138, so the container needs its own LAN address (macvlan/ipvlan) or host networking. Joining by IP works through port mapping.
- **Settings ignored**: they go into `RC_INI`, not `System.ini` or the `Save/` copies. Check `Overlay/System/Server.ini`.
- **The time limit never ends on an empty server**: the game clock only runs once players are in, so the map rotation doesn't advance on an idle server.
- **`Map ... is not installed; left out of the rotation`**: the map isn't in `Maps/` as `<name>.ctm`. Names are case-insensitive; the `.ctm` extension is optional.
- **`docker stop` takes 10 seconds**: UCC ignores SIGTERM, so Docker kills it after the timeout.
