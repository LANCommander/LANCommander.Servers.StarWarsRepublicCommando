# syntax=docker/dockerfile:1.7

# Override to build against a locally built base, e.g. lancommander/wine:local
ARG BASE_IMAGE=lancommander/wine:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.title="Star Wars: Republic Commando Game Server" \
      org.opencontainers.image.description="Dedicated server for Star Wars: Republic Commando, running the SWRCFix UCC server under Wine" \
      app.lancommander.server.kind="game" \
      app.lancommander.server.game.title="Star Wars: Republic Commando" \
      app.lancommander.server.external-id.hq="564649b5-39c5-40e1-8276-fd0e98bb0840" \
      app.lancommander.server.external-id.igdb="148" \
      app.lancommander.server.external-id.steam="6000" \
      app.lancommander.server.external-id.gog="1421405135"

# ----------------------------
# Server settings
#   - The game files are not downloadable; put a Republic Commando install (GameData folder, with
#     the SWRCFix UCC.exe in System/) in /config/Server, or set RC_ARCHIVE_URL to a zip of one
#   - RC_INI is created from System/System.ini on first start; the RC_* settings below are written
#     into it on every start (empty settings are left alone)
#   - RC_GAME_TYPE takes deathmatch, teamdeathmatch, ctf, assault or a game class
#   - UCC is a console program and needs no X display, so Xvfb is off
# ----------------------------
ENV RC_ARCHIVE_URL="" \
    RC_MAP="DM_Canyon" \
    RC_GAME_TYPE="deathmatch" \
    RC_MAPS="" \
    RC_PORT="7777" \
    RC_INI="Server.ini" \
    RC_SERVER_NAME="Republic Commando Server" \
    RC_SHORT_NAME="RC Server" \
    RC_ADMIN_NAME="" \
    RC_ADMIN_EMAIL="" \
    RC_MOTD="" \
    RC_MAX_PLAYERS="16" \
    RC_MAX_SPECTATORS="" \
    RC_GAME_PASSWORD="" \
    RC_ADMIN_PASSWORD="" \
    RC_GOAL_SCORE="" \
    RC_TIME_LIMIT="" \
    RC_FRIENDLY_FIRE_SCALE="" \
    RC_ROUND_TIME="" \
    RC_NUM_ROUNDS="" \
    RC_BALANCE_TEAMS="" \
    RC_MASTER_SERVER_UPLINK="false" \
    RC_URL_OPTIONS="" \
    WINE_XVFB="false" \
    START_EXE="/usr/local/bin/rc-server" \
    START_ARGS=""

COPY Scripts/rc-server /usr/local/bin/rc-server
RUN chmod +x /usr/local/bin/rc-server

COPY Hooks/ "${BASE_HOOKS}/"

# 7777/udp: game. 11138/udp: GameSpy query (fixed port; the in-game LAN browser finds servers
# through it). 8777/udp: UdpBeacon, bound but silent (DoBeacon=False in the stock ini).
EXPOSE 7777/udp 11138/udp 8777/udp

WORKDIR /config
ENTRYPOINT ["/usr/local/bin/entrypoint.ps1"]
