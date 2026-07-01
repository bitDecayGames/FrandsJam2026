#!/usr/bin/env bash
# Watch for Claude Code edits and auto-rebuild + relaunch the game.
# Usage: ./bin/watch_rebuild.sh

SIGNAL=".rebuild"
BUILD_CMD="lime test hl -Dplay -Ddb"
GAME_PID=""

kill_game() {
    if [[ -n "$GAME_PID" ]] && kill -0 "$GAME_PID" 2>/dev/null; then
        echo -e "\033[33m[watch]\033[0m killing previous instance (pgid $GAME_PID)"
        # kill the whole process group (lime + game binary)
        kill -- -"$GAME_PID" 2>/dev/null
        for i in {1..30}; do
            kill -0 "$GAME_PID" 2>/dev/null || break
            sleep 0.1
        done
        if kill -0 "$GAME_PID" 2>/dev/null; then
            echo -e "\033[31m[watch]\033[0m force killing (pgid $GAME_PID)"
            kill -9 -- -"$GAME_PID" 2>/dev/null
            sleep 0.2
        fi
        wait "$GAME_PID" 2>/dev/null
        GAME_PID=""
    fi
}

cleanup() {
    echo -e "\n\033[33m[watch]\033[0m shutting down..."
    kill_game
    exit 0
}
trap cleanup SIGINT SIGTERM

echo -e "\033[36m[watch]\033[0m waiting for rebuild signal (touch $SIGNAL)"
echo -e "\033[36m[watch]\033[0m press Ctrl+C to stop\n"

echo -e "\033[35m[watch]\033[0m initial build at $(date +%H:%M:%S)"
echo -e "\033[36m[watch]\033[0m building..."
setsid $BUILD_CMD &
GAME_PID=$!
echo -e "\033[32m[watch]\033[0m launched (pgid $GAME_PID)\n"

while true; do
    inotifywait -qq -e close_write -e modify -e create "$SIGNAL" 2>/dev/null &
    WAIT_PID=$!

    [[ ! -f "$SIGNAL" ]] && touch "$SIGNAL"

    wait "$WAIT_PID" 2>/dev/null || continue

    echo -e "\n\033[35m[watch]\033[0m rebuild triggered at $(date +%H:%M:%S)"

    kill_game

    echo -e "\033[36m[watch]\033[0m building..."
    setsid $BUILD_CMD &
    GAME_PID=$!
    echo -e "\033[32m[watch]\033[0m launched (pgid $GAME_PID)"

    echo -e "\033[36m[watch]\033[0m waiting for next rebuild signal...\n"
done
