#!/usr/bin/env bash
# Watch for Claude Code edits and auto-rebuild two game windows + server.
# Window 1: normal player (you control)
# Window 2: bot that walks left/right
# Usage: ./bin/watch_net.sh

SIGNAL=".rebuild"
SERVER_DIR="server"
PLAYER_BUILD="lime build hl -debug -Dplay -Ddb -Dforcelocal"
BOT_BUILD="lime build hl -Dplay -Ddb -Dforcelocal -Dplayer_name=player2"
GAME_BIN="export/hl/bin/FrandsJam"
SERVER_PID=""
PLAYER_PID=""
BOT_PID=""

kill_pid() {
    local pid=$1
    local name=$2
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        echo -e "\033[33m[watch]\033[0m killing $name (pid $pid)"
        kill "$pid" 2>/dev/null
        for i in {1..20}; do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.1
        done
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null
            sleep 0.1
        fi
        wait "$pid" 2>/dev/null
    fi
}

kill_games() {
    kill_pid "$PLAYER_PID" "player"
    kill_pid "$BOT_PID" "bot"
    PLAYER_PID=""
    BOT_PID=""
}

start_server() {
    # kill old server if running
    if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        echo -e "\033[33m[watch]\033[0m stopping old server (pid $SERVER_PID)"
        kill "$SERVER_PID" 2>/dev/null
        wait "$SERVER_PID" 2>/dev/null
    fi
    echo -e "\033[36m[watch]\033[0m building and starting colyseus server..."
    cd "$SERVER_DIR"
    haxe server.hxml 2>&1 | tee -a ../build.log | sed -u 's/^/\x1b[33m[server-build]\x1b[0m /'
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        echo -e "\033[31m[watch]\033[0m server build failed!"
        cd ..
        return
    fi
    node dist/server.js > >(tee ../colyseus.log | sed -u 's/^/\x1b[33m[server]\x1b[0m /') 2>&1 &
    SERVER_PID=$!
    cd ..
    sleep 1
    echo -e "\033[32m[watch]\033[0m server running (pid $SERVER_PID)"
}

build_and_launch() {
    # rebuild and restart server (schema may have changed)
    start_server

    echo -e "\033[36m[watch]\033[0m building player..."
    $PLAYER_BUILD 2>&1 | tee -a build.log | tail -5
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        echo -e "\033[31m[watch]\033[0m player build failed!"
        return
    fi

    # copy player binary before bot build overwrites it
    # rename ssl.hdll to prevent longjmp crash with ws:// connections
    if [[ -f export/hl/bin/ssl.hdll ]]; then
        mv export/hl/bin/ssl.hdll export/hl/bin/ssl.hdll.bak
    fi
    # rm -rf first: `cp -r src dest` NESTS into dest/ when dest already exists,
    # leaving a stale dest/MyApplication from the first run that we'd then launch.
    rm -rf export/hl/bin_player
    cp -r export/hl/bin export/hl/bin_player 2>/dev/null

    echo -e "\033[36m[watch]\033[0m building bot..."
    $BOT_BUILD 2>&1 | tee -a build.log | tail -5
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        echo -e "\033[31m[watch]\033[0m bot build failed!"
        return
    fi
    rm -rf export/hl/bin_bot
    cp -r export/hl/bin export/hl/bin_bot 2>/dev/null

    echo -e "\033[36m[watch]\033[0m launching player window..."
    (cd export/hl/bin_player && LD_LIBRARY_PATH="$(pwd):$LD_LIBRARY_PATH" ./MyApplication) > >(tee game_player.log | sed -u 's/^/\x1b[32m[player]\x1b[0m /') 2>&1 &
    PLAYER_PID=$!

    sleep 0.5

    echo -e "\033[36m[watch]\033[0m launching bot window..."
    (cd export/hl/bin_bot && LD_LIBRARY_PATH="$(pwd):$LD_LIBRARY_PATH" ./MyApplication) > >(tee game_bot.log | sed -u 's/^/\x1b[34m[bot]\x1b[0m /') 2>&1 &
    BOT_PID=$!

    # position windows side by side in center of primary monitor
    sleep 1
    if command -v xdotool &>/dev/null && command -v xrandr &>/dev/null; then
        # get primary monitor resolution
        local res=$(xrandr --query | grep ' connected primary' | grep -oP '\d+x\d+\+\d+\+\d+' | head -1)
        local mon_w=$(echo "$res" | cut -dx -f1)
        local mon_h=$(echo "$res" | cut -d+ -f1 | cut -dx -f2)
        local mon_x=$(echo "$res" | cut -d+ -f2)
        local mon_y=$(echo "$res" | cut -d+ -f3)
        # game window is 640x480, two windows + 20px gap
        local total_w=$((640 + 20 + 640))
        local start_x=$(( mon_x + (mon_w - total_w) / 2 ))
        local start_y=$(( mon_y + (mon_h - 480) / 2 ))
        local bot_wid=$(xdotool search --pid "$BOT_PID" 2>/dev/null | head -1)
        local player_wid=$(xdotool search --pid "$PLAYER_PID" 2>/dev/null | head -1)
        [[ -n "$bot_wid" ]] && xdotool windowmove "$bot_wid" "$start_x" "$start_y"
        [[ -n "$player_wid" ]] && xdotool windowmove "$player_wid" "$((start_x + 660))" "$start_y"
    fi

    echo -e "\033[32m[watch]\033[0m both windows running (player=$PLAYER_PID bot=$BOT_PID)"
    # write PIDs so screenshot listener can find them
    echo "$PLAYER_PID" > .pid_player
    echo "$BOT_PID" > .pid_bot
}

cleanup() {
    echo -e "\n\033[33m[watch]\033[0m shutting down..."
    kill_games
    kill_pid "$SERVER_PID" "server"
    kill "$SCREENSHOT_PID" 2>/dev/null
    SERVER_PID=""
    exit 0
}
trap cleanup SIGINT SIGTERM

echo -e "\033[36m[watch]\033[0m dual-window network watcher"
echo -e "\033[36m[watch]\033[0m press Ctrl+C to stop\n"

start_server

echo -e "\033[35m[watch]\033[0m initial build at $(date +%H:%M:%S)"
build_and_launch

echo -e "\033[36m[watch]\033[0m waiting for rebuild signal...\n"

SCREENSHOT=".screenshot"
SCREENSHOT_DIR="screenshots"
mkdir -p "$SCREENSHOT_DIR"

# Screenshot listener runs in background, reads PIDs from files
(
    touch "$SCREENSHOT"
    while true; do
        inotifywait -qq -e close_write -e modify "$SCREENSHOT" 2>/dev/null
        ppid=$(cat .pid_player 2>/dev/null)
        bpid=$(cat .pid_bot 2>/dev/null)
        if [[ -n "$ppid" ]] && kill -0 "$ppid" 2>/dev/null; then
            ts=$(date +%H%M%S)
            player_wid=$(xdotool search --pid "$ppid" 2>/dev/null | head -1)
            bot_wid=$(xdotool search --pid "$bpid" 2>/dev/null | head -1)
            [[ -n "$player_wid" ]] && import -window "$player_wid" "$SCREENSHOT_DIR/player_${ts}.png" 2>/dev/null
            [[ -n "$bot_wid" ]] && import -window "$bot_wid" "$SCREENSHOT_DIR/bot_${ts}.png" 2>/dev/null
            echo -e "\033[36m[watch]\033[0m screenshots saved to $SCREENSHOT_DIR/*_${ts}.png"
        else
            echo -e "\033[33m[watch]\033[0m screenshot: no running game windows found"
        fi
    done
) &
SCREENSHOT_PID=$!

while true; do
    inotifywait -qq -e close_write -e modify -e create "$SIGNAL" 2>/dev/null &
    WAIT_PID=$!
    [[ ! -f "$SIGNAL" ]] && touch "$SIGNAL"
    wait "$WAIT_PID" 2>/dev/null || continue

    echo -e "\n\033[35m[watch]\033[0m rebuild triggered at $(date +%H:%M:%S)"
    kill_games
    build_and_launch
    echo -e "\033[36m[watch]\033[0m waiting for next rebuild signal...\n"
done
