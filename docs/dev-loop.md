# Development & Testing Loop

## Overview

The agent develops and tests using the user's host machine as the runtime environment. The user runs `./bin/watch_net.sh` which provides a live game environment with two HashLink windows and a Colyseus server. The agent edits code, triggers rebuilds, and reads log files to verify behavior. Screenshots can be taken for visual verification.

## Setup

The user runs this once in a terminal:
```bash
./bin/watch_net.sh
```

This starts:
- Colyseus server (rebuilt from Haxe on each cycle)
- Player window (`-Dplay -Ddb -Dforcelocal`)
- Bot window (`-Dplay -Dbot -Dforcelocal`)

## Agent Iteration Loop

### 1. Edit code
Make changes to source files (`.hx`), server code, schemas, etc.

### 2. Trigger rebuild
```bash
touch .rebuild
```
The watcher detects this, kills old game windows, rebuilds server + both clients, and relaunches everything.

### 3. Wait for build
Wait ~15-20 seconds for the build to complete and games to launch. The watcher shows build output in the user's terminal.

### 4. Check logs
Read the log files to verify behavior:
```bash
tail -20 game_player.log    # Player client output
tail -20 game_bot.log       # Bot client output
tail -20 colyseus.log       # Colyseus server output
tail -20 build.log          # Build compiler output
```

Useful grep patterns:
```bash
grep "fish\|cast\|spawn" game_player.log | tail -10
grep "ERROR\|error\|SIGNAL" build.log
grep "SIM\|FISH\|tick" colyseus.log | tail -10
```

### 5. Take screenshots (visual verification)
```bash
touch .screenshot
sleep 3
# Then read the PNG files:
ls screenshots/
```

Screenshots are captured via `xdotool` + ImageMagick `import`. Requires both installed on the host. The watcher writes game PIDs to `.pid_player` and `.pid_bot` for the screenshot listener.

### 6. Iterate
Go back to step 1. Fix issues found in logs/screenshots.

## Log Files

All log files are in the project root and gitignored:

| File | Contents |
|------|----------|
| `colyseus.log` | Server output (room creation, messages, fish AI, ticks) |
| `game_player.log` | Player client (network events, fish adds, cast messages) |
| `game_bot.log` | Bot client (same as player, auto-walks left/right) |
| `build.log` | Haxe compiler output for both player and bot builds |

## Key Things to Watch For

### Build failures
Check `build.log` for compile errors. Common issues:
- Field initializers on extern classes (`Must call super()`)
- Missing imports
- Type mismatches between client/server schemas

### Schema mismatches
If you change `schema/*.hx`, the server MUST be rebuilt. The watcher does this automatically. Look for `@colyseus/schema definition mismatch` in client logs.

### Fish spawning
Server logs: `spawnFish: spawned fish in N water bodies, total fish: M`
Client logs: `NetworkManager: fish added N`

### Cast flow
Player logs should show: `cast_start → cast_release → bobber_landed → fish_caught → cast_retract → bobber_retracted`

### Player sync
Both clients should show the other player moving. Check for `SYNC` traces if enabled.

## Important Notes

- **Do NOT run headless HL instances.** The user's watcher provides the real runtime.
- **ssl.hdll is removed** after each build copy. HL crashes on init without this.
- **`IS_HOST` is read from schema directly** in `waitForHostAndSpawn`, not from the deferred `NetworkManager.IS_HOST` flag.
- **Fish are added to `serverFishGroup`** (not `fishSpawner` group) because FlxGroups don't render sprites added after `create()`.
- **`frozen` is client-side only.** The Simulation uses `dir == -1` to detect no movement. No `frozen` field on PlayerState schema.
- **Bot only walks** — no casting, no interactions. The user drives gameplay testing.
