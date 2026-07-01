#!/usr/bin/env bash
# Watch for edits and auto-rebuild a single-player local game window.
# No Colyseus server needed. Usage: ./bin/watch_solo.sh

SIGNAL=".rebuild"
PLAYER_BUILD="lime build hl -Dplay_solo -Ddb"
PLAYER_PID=""

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

build_and_launch() {
    echo -e "\033[36m[watch]\033[0m building local single-player..."
    $PLAYER_BUILD 2>&1 | tee -a build.log | tail -5
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        echo -e "\033[31m[watch]\033[0m build failed!"
        return
    fi

    # rename ssl.hdll to prevent longjmp crash
    if [[ -f export/hl/bin/ssl.hdll ]]; then
        mv export/hl/bin/ssl.hdll export/hl/bin/ssl.hdll.bak
    fi

    echo -e "\033[36m[watch]\033[0m launching game..."
    (cd export/hl/bin && LD_LIBRARY_PATH="$(pwd):$LD_LIBRARY_PATH" ./MyApplication) > >(tee game_solo.log | sed -u 's/^/\x1b[32m[game]\x1b[0m /') 2>&1 &
    PLAYER_PID=$!

    # position window
    sleep 1
    if command -v xdotool &>/dev/null && command -v xrandr &>/dev/null; then
        local res=$(xrandr --query | grep ' connected primary' | grep -oP '\d+x\d+\+\d+\+\d+' | head -1)
        local mon_w=$(echo "$res" | cut -dx -f1)
        local mon_h=$(echo "$res" | cut -d+ -f1 | cut -dx -f2)
        local mon_x=$(echo "$res" | cut -d+ -f2)
        local mon_y=$(echo "$res" | cut -d+ -f3)
        local start_x=$(( mon_x + (mon_w - 640) / 2 ))
        local start_y=$(( mon_y + (mon_h - 480) / 2 ))
        local wid=$(xdotool search --pid "$PLAYER_PID" 2>/dev/null | head -1)
        [[ -n "$wid" ]] && xdotool windowmove "$wid" "$start_x" "$start_y"
    fi

    echo -e "\033[32m[watch]\033[0m game running (pid $PLAYER_PID)"
    echo "$PLAYER_PID" > .pid_player
}

cleanup() {
    echo -e "\n\033[33m[watch]\033[0m shutting down..."
    kill_pid "$PLAYER_PID" "game"
    kill "$SCREENSHOT_PID" 2>/dev/null
    PLAYER_PID=""
    exit 0
}
trap cleanup SIGINT SIGTERM

echo -e "\033[36m[watch]\033[0m single-player local watcher"
echo -e "\033[36m[watch]\033[0m press Ctrl+C to stop\n"

echo -e "\033[35m[watch]\033[0m initial build at $(date +%H:%M:%S)"
build_and_launch

echo -e "\033[36m[watch]\033[0m waiting for rebuild signal...\n"

SCREENSHOT=".screenshot"
SCREENSHOT_DIR="screenshots"
mkdir -p "$SCREENSHOT_DIR"

# Screenshot listener
(
    touch "$SCREENSHOT"
    while true; do
        inotifywait -qq -e close_write -e modify "$SCREENSHOT" 2>/dev/null
        ppid=$(cat .pid_player 2>/dev/null)
        if [[ -n "$ppid" ]] && kill -0 "$ppid" 2>/dev/null; then
            ts=$(date +%H%M%S)
            player_wid=$(xdotool search --pid "$ppid" 2>/dev/null | head -1)
            [[ -n "$player_wid" ]] && import -window "$player_wid" "$SCREENSHOT_DIR/solo_${ts}.png" 2>/dev/null
            echo -e "\033[36m[watch]\033[0m screenshot saved to $SCREENSHOT_DIR/solo_${ts}.png"
        else
            echo -e "\033[33m[watch]\033[0m screenshot: no running game window found"
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
    kill_pid "$PLAYER_PID" "game"
    PLAYER_PID=""
    build_and_launch
    echo -e "\033[36m[watch]\033[0m waiting for next rebuild signal...\n"
done
