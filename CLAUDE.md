# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FrandsJam is a HaxeFlixel game built with Haxe, OpenFL/Lime, and FMOD audio. It uses LDTK for level design, integrates with Newgrounds for medals/leaderboards, and reports analytics via Bitlytics/InfluxDB.

## Build & Development Commands

```bash
./bin/init_deps.sh          # Install dependencies from haxelib.deps
lime build html5             # Production build
lime build html5 -debug      # Debug build
lime build hl -debug         # HashLink debug build (preferred for local testing)
./bin/format.sh              # Format Haxe code
./bin/export_ase.sh          # Export Aseprite files to atlases
./bin/generate_events.sh     # Regenerate Event.hx from types.json
./bin/setup_hooks.sh         # Install git hooks
```

**Never run `haxelib set flixel` as part of build commands.** The user manages their flixel version manually.

**Do not run `./bin/run_debug.sh`** — it starts a long-running HTTP server. The user will run this themselves. Use `lime build hl -debug` to compile only.

`./bin/run_llm_debug.sh` builds with the LLM debug bridge and serves on port 8080. Use this to test the game via Playwright. See [LLM Debug Bridge docs](docs/llm-debug-bridge.md) for the full `window.__debug` API.

## Architecture

### Game States (source/states/)
FlxTransitionableState subclasses form the game flow: SplashScreenState → MainMenuState → PlayState → VictoryState/FailState. CreditsState and AchievementsState are accessible from menus.

### Event System (source/events/)
Publish-subscribe bus for game events. Events are **code-generated** from `assets/data/events/types.json` into `source/events/gen/Event.hx`. Use `EventBus.fire()` to emit and `EventBus.subscribe()` to listen. MetricReducer auto-tracks COUNT/MIN/MAX/SUM metrics. EventDerivers transform events into derived events.

### Level System (source/levels/ldtk/)
Levels defined in `assets/world.ldtk` using LDTK editor. Level.hx loads levels and extracts spawn points, terrain, camera zones, and transitions. LdtkTilemap handles rendering.

### Input (source/input/)
SimpleController provides unified keyboard/gamepad/touch input via a Button enum (UP, DOWN, LEFT, RIGHT, A, B, START, SELECT). InputCalculator derives cardinal directions.

### Achievements (source/achievements/)
Achievements registered in `Achievements.initAchievements()` with event-based conditions. Persisted via Storage.hx and synced to Newgrounds medals.

### Audio (FMOD)
FmodConstants.hx is auto-generated from the FMOD Studio project in `fmod/`. Use `FmodManager.PlaySong()` / `PlaySoundOneShot()` / `StopSong()`. Constants are in FmodSongs and FmodSFX.

### Player (source/entities/Player.hx)
Player extends FlxSprite (48x48 graphic, 16x16 hitbox). Takes an `FlxState` reference in its constructor so it can add/remove its own child sprites (reticle, power bar, cast bobber) from the scene. Movement speed is 100px/s (150 in hot mode). Uses `InputCalculator.getInputCardinal()` for input and tracks `lastInputDir` for facing direction. Has a `frozen` flag that suppresses movement during cast charging, catch animation, and retrieve (unfreezes only when the bobber is destroyed after reaching the player). Supports multiple skins (Q/E to cycle). Skin loading parses Aseprite JSON atlas (`loadSkin()`) and auto-detects one-shot animations by prefix (`cast_`, `throw_`, `catch_`).

### Fishing Cast System (source/entities/Player.hx)
Cast mechanic uses a `CastState` enum (IDLE → CHARGING → CAST_ANIM → CASTING → LANDED → CATCH_ANIM → RETURNING). Press A (Z key) to start charging — a power bar pulses below the player. Press A again to launch a bobber toward the reticle at a distance proportional to power (max 96px / 6 tiles). Press A or move to retract the bobber at any point (mid-flight, landed). The `CastState` enum is defined at module level in Player.hx.

The bobber launches on frame 3 of the 5-frame cast animation (CAST_LAUNCH_FRAME) using a parabolic arc at 150px/s. The arc uses `updateCastArc()` with formula `arcHeight * 4 * t * (1-t)`. CAST_ANIM clamps the bobber at the target if it arrives during the animation. The same check in CASTING transitions to LANDED.

**Retrieve:** `Player.catchFish(hasFish)` transitions to CATCH_ANIM. The `retractHasFish` flag controls retrieve style: with a fish, the bobber/fish arcs back via `updateCastArc()` at 188px/s; without a fish, straight-line velocity at 188px/s. On catch, the bobber sprite swaps to `fish.png` showing the caught fish frame (`caughtFishSpriteIndex`). CATCH_ANIM → RETURNING keeps `frozen = true`; player unfreezes only when the bobber is destroyed after reaching them. Movement animation is suppressed during CAST_ANIM, CATCH_ANIM, and RETURNING to prevent moonwalking.

**Fish delivery callback:** `onFishDelivered` fires when the bobber/fish reaches the player. PlayState wires this to add the fish to inventory (or spawn a GroundFish if inventory is full). The callback is set before `catchFish()` and nulled after firing.

**Fishing line:** Drawn pixel-by-pixel each frame from rod tip to bobber center. Rod tip positions (`getRodTipPos()`) vary per cast direction and per animation frame. Left/right casts use cubic Bezier curves with downward sag; up/down use Bresenham line drawing.

**Rod tip positions:** Manually calibrated per direction per frame. The CATCH_ANIM/RETURNING branch has 3 frames per direction (frame 0 = cast position, frame 1 = mid-retract, frame 2 = final resting position).

### Fish System (source/entities/)
**FishSpawner** (`FishSpawner.hx`) is a `FlxTypedGroup<WaterFish>` that flood-fills the FishSpawner IntGrid layer to find water bodies, then spawns `WaterFish` into each body. Each FishSpawner LDTK entity has a `numFish` field controlling how many fish spawn in that body. FishSpawner handles separation — when two fish are closer than `SEPARATION_DIST` (20px), **both** flee from each other (not just one). Passes bobber references through to fish via `setBobber()`. Takes an `onCatch` callback in its constructor, wired to each fish at spawn time.

**WaterFish** (`WaterFish.hx`) owns its own bobber-awareness logic using center-to-center distance (`x + width/2, y + height/2`). Each fish has a nullable `bobber` reference and an `onCatch` callback. `checkBobber()` is called when `bobber != null || attracted` — this handles the case where the bobber is retracted while a fish is swimming toward it. Distance thresholds: attract within 32px, catch within 4px. When a fish is attracted and the bobber becomes null (retracted), the fish flees in the opposite direction via `fleeFrom()` then resumes normal wandering. `fleeFrom()` returns immediately if the fish is attracted to a bobber (attraction overrides separation). Flee picks the farthest water tile in the away direction and immediately sets velocity (no pause). Fish fade in over 1 second when spawning/respawning. After being caught, fish respawn at a random water tile after 3 seconds. Fish use `fishShadow.png` sprite with `centerOffsets()` for proper hitbox alignment.

**GroundFish** (`GroundFish.hx`) — fish that land on the ground when the player's inventory is full. Arcs from the player's head position to a random non-water landing spot. Uses `fish.png` spritesheet (32x32 frames, 5 fish types). Has a `FISH_SIZES` lookup table with actual pixel dimensions per frame: `[8,8], [9,9], [12,12], [13,14], [15,16]` (top-left aligned within the 32x32 cell). Origin is set to the center of the actual fish content for proper rotation. While landing (`landing = true`), the fish arcs through the air and can't be picked up. After landing, it flops (sine-wave rotation) and can be picked up by walking over it.

**GroundFishGroup** (`GroundFishGroup.hx`) manages ground fish spawning and pickup. `addFish()` picks a random landing spot 16-32px away, trying up to 20 times to avoid water tiles (checked via the LDTK FishSpawner IntGrid layer). Prevents pickup during landing arc.

**PlayState wiring:** PlayState creates the spawner with an `onFishCaught` callback that sets `player.onFishDelivered` before calling `player.catchFish(true)`. The delivery callback adds fish to inventory; if full, spawns a GroundFish at the player's head (x+8, y-2) using the caught fish's sprite frame (`player.caughtFishSpriteIndex`). Each frame calls `fishSpawner.setBobber(player.isBobberLanded() ? player.castBobber : null)`, `rockGroup.checkPickup(player)`, and `groundFishGroup.checkPickup(player)`.

### Rock Throwing (source/entities/Player.hx, source/entities/Rock.hx)
Press B to throw a rock from inventory toward the reticle (max 96px). The rock arcs via parabolic flight (`arcHeight * 4 * t * (1-t)`, max height = min(dist*0.5, 64)) at 200px/s. Player is frozen during the throw animation. The rock launches on frame 6 of the throw animation. `makeRock` factory is set by PlayState to create rocks that know about the spawner layer. After landing, `resolveThrow()` is called on the rock.

### Inventory (source/entities/Inventory.hx)
Simple array-based inventory with `MAX_SLOTS = 4`. Supports `add()`, `remove()`, `has()`, `isFull()`, `count()`. Items are the `InventoryItem` enum: `Rock`, `Fish`. Fires `onChange` signal on add/remove. InventoryHUD displays current inventory state.

### Networking (source/net/NetworkManager.hx)
Colyseus-based multiplayer. `NetworkManager` manages client connection, room joining, and message passing. Signals: `onJoined`, `onPlayerAdded`, `onPlayerChanged`, `onPlayerRemoved`, `onFishAdded`, `onFishMove`. `IS_HOST` determines whether this client spawns fish/rocks. The `sendMessage()` method has an optional `mute` parameter to suppress per-frame logging (used by `sendMove()`). In `-Dlocal` mode, all methods early-return as no-ops and `IS_HOST` defaults to `true`.

**HARD RULE: never modify the Colyseus library.** The vendored Colyseus SDK under `.haxelib/colyseus/` (and the global haxelib copy) must remain byte-identical to official upstream (`github.com/colyseus/colyseus-haxe`) — no patches, no local hacks, not even "small" ones. `Callbacks.enableMainLoopProcessing()` is genuine upstream code, not a custom addition. Any thread-safety, marshaling, or behavior fix belongs in **our** code (`NetworkManager.hx`), never inside the SDK. If a fix seems to require editing Colyseus, find another way.

**Thread marshaling:** On HashLink (`sys`), Colyseus runs its websocket on a background thread (`Connection.hx` spawns it), so every callback — `joinOrCreate`, `room.onMessage`, and schema listeners — fires off the main thread. Touching HaxeFlixel/render state from that thread crashes HL (`longjmp causes uninitialized stack frame`, then a segfault). NetworkManager hops every callback back to the main thread: schema changes via upstream `enableMainLoopProcessing()` (queues + `haxe.MainLoop.add`), and our own callbacks via `runOnMain()` (wraps `haxe.MainLoop.runInMainThread` on sys, runs inline on html5). All `room.onMessage` registrations go through the `onMsg()` wrapper, never `room.onMessage` directly. Lime pumps the main thread's event loop each frame (`NativeApplication.updateTimer` → `Thread.current().events.progress()`), which is what drains these. The `bin/watch_net.sh` workflow also renames `ssl.hdll` → `ssl.hdll.bak` to dodge a separate SSL-related longjmp on `ws://` connections.

PlayState manages remote players (`remotePlayers` map) and remote fish (`remoteFish` map). Remote players are `Player` instances with `isRemote = true` that skip input processing and are driven by network events.

### Round/Game Management (source/managers/)
**GameManager** (`GameManager.hx`) — singleton (`ME`) that holds the `NetworkManager`, `FishManager`, and orchestrates rounds. Constructed with an array of `Round` definitions. Calls `net.sendMessage("round_update", ...)` at round transitions (lobby, pre-round, post-round, end-game).

**RoundManager** (`RoundManager.hx`) — manages a single round's goals. Signals completion when all goals (or any goal, depending on `allGoalsRequired`) are met. `initialize(state)` is called after PlayState creates to set up round-specific behavior.

**Round status sync (read before touching round/lobby transitions).** The authoritative round status lives in the server's `RoundState` schema (`lobby` → `active` → `post_round` → … → `end_game`). Flow: only the **host** drives transitions; `GameManager.setStatus()` sets local `roundStatus` and (if host) sends a `round_update` message; the server applies it and broadcasts the schema; **every** client's `round` schema listener calls `GameManager.sync()` which sets local `roundStatus` and calls `switchStateBasedOnStatus()` (which `FlxG.switchState`s to LobbyState/PlayState/etc).

Server-side `round_update` semantics (`server/hxsrc/GameRoom.hx`) — critical and non-obvious:
- The server builds a **brand-new `RoundState` object for every `round_update`** (so the schema `round` ref changes and the client `round` listener fires every time), copying current values then overriding only the fields present in the message.
- It only changes `status` **and resets every player's `ready` flag to false** when the message includes a non-null `status`.
- `totalRounds` and `currentRound` are **sticky** server-side — once set they persist across messages that omit them.

Consequences that bit us (don't regress these):
- **Send exactly ONE `round_update` per transition.** Two messages = two schema mutations; if the first is tagged with the old status (e.g. `lobby`) while the host has already advanced itself to `active` locally, `sync()` drags the host backward → infinite `lobby ⇄ active` oscillation that kicks players back to character select.
- `GameManager.init()` (only ever called from `playersReady()`, host + lobby) sets up round data **locally and must NOT broadcast** — `setStatus()` carries `totalRounds` so the single status-transition message propagates metadata. (Earlier bug: `init()` broadcast `status:lobby`/metadata, producing the duplicate mutation above.)
- Known remaining smell (not yet hit since the double-send was removed): `LobbyState.create()` schedules `FlxTimer.wait(2, () -> setStatus(LOBBY))`; that timer is global and can fire after you've left the lobby. If oscillation ever reappears, guard this so it only broadcasts while actually in the lobby.

### Analytics & Storage (source/helpers/)
Analytics.hx reports events to Bitlytics. Storage.hx handles local persistence for achievements and metrics.

## Local Multiplayer Testing

**Server** (Node.js Colyseus, `server/`): build with `cd server && haxe server.hxml`, run with `node dist/server.js` (listens on `ws://localhost:2567`). It's a long-running process — start it once in the background; do not block on it.

**Client builds** connect to that server with `play` + `forcelocal`:
- `lime build hl -Dplay -Dforcelocal` — a player you control.
- add `-Dbot` for the auto-walking second window, `-Ddb` for in-game debug buttons.

**`bin/watch_net.sh`** is the all-in-one harness: starts the server, builds a player window + a bot window, and rebuilds/relaunches on the `.rebuild` signal file. To pick up source changes you must trigger a rebuild (e.g. `touch .rebuild`) — it watches `.rebuild`, not the source tree.

Two HashLink gotchas this harness handles (and why):
- **`ssl.hdll` longjmp:** the script renames `export/hl/bin/ssl.hdll` → `ssl.hdll.bak` before launching. Merely *loading* `ssl.hdll` causes a `longjmp causes uninitialized stack frame` crash on `ws://` (non-TLS) connections. Local builds don't need SSL, so removing the lib avoids it. A fresh `lime build` regenerates `ssl.hdll`, so re-rename after rebuilding if you launch the binary manually.
- **Stale-binary copy bug (fixed):** the script copies the build into `export/hl/bin_player` / `bin_bot` and launches from there. `cp -r src dest` *nests* into `dest/` when `dest` already exists, so it used to launch a stale top-level binary forever (symptom: your fix "doesn't take" and the crash/behavior is identical every run — check the trace **line numbers** against your working tree to detect this). The script now `rm -rf`s the dest first and checks `${PIPESTATUS[0]}` (not `$?`, which was reading `tail`'s exit) so failed builds abort instead of relaunching stale binaries.

**Running a client by hand** (what the harness does): `cd export/hl/bin && rm -f ssl.hdll && LD_LIBRARY_PATH="$(pwd):$LD_LIBRARY_PATH" DISPLAY=:0 ./MyApplication`. There is a real X display (`:0`) on the dev machine, so windowed HL builds run directly.

**Testing etiquette:** the bot window should ONLY walk left/right — do **not** inject input (xdotool, etc.) to puppeteer the ready/round flow. Gameplay-flow changes (round transitions, ready) can be compile-verified and traced against logs, but runtime-verifying them requires the human to drive two windows; ask them to test rather than automating input.

**Agent testing workflow:** See [docs/dev-loop.md](docs/dev-loop.md) for the full development iteration loop. Summary: edit code → `touch .rebuild` → wait ~15s → `tail` log files (`colyseus.log`, `game_player.log`, `game_bot.log`, `build.log`) → `touch .screenshot` for visual checks → iterate. Do NOT run headless HL instances.

**Build verification — MANDATORY after every `.rebuild`:**
After triggering a rebuild, you MUST check `build.log` for compilation errors BEFORE doing anything else. Do not check screenshots, do not check game logs, do not report results until you have confirmed the build succeeded. The verification steps are:
1. Check `build.log` for `build failed`, `error`, `Unknown identifier`, `has no field`, `Type not found` — if ANY appear, the build failed and you must fix the errors first
2. Check build timestamps (`BUILD:` in game logs, `SERVER BUILD:` in colyseus.log) — confirms binaries are fresh
3. Only THEN proceed to check game behavior via logs/screenshots

Server build output is tee'd to `build.log` with `[server-build]` prefix (haxe produces no stdout on success, only on error). Macros: `Macros.getBuildTimestamp()` in client (`source/misc/Macros.hx`), `BuildInfo.timestamp()` in server (`server/hxsrc/Main.hx`).

**IMPORTANT: There is NO Docker file sync issue.** If the build timestamp hasn't changed, the cause is ALWAYS a compilation error — check `build.log` for errors. Do NOT blame Docker file sync, do NOT use `cp/mv` workarounds. The files are always in sync. If the binary didn't update, the build failed.

## Code Generation Pipelines

**Events:** Edit `assets/data/events/types.json` → run `./bin/generate_events.sh` → generates `source/events/gen/Event.hx`

**Aseprite sprites:** Place `.ase`/`.aseprite` in `art/` → pre-commit hook auto-exports to `assets/aseprite/` as JSON atlases

**FMOD:** Edit FMOD project in `fmod/` → export generates `FmodConstants.hx`

## Global Imports

`source/import.hx` provides project-wide imports: FMOD manager/constants, QuickLog (QLog), DebugSuite (DS), and bitdecay flixel extensions.

## Compile Flags

- `#if debug` / `#if FLX_DEBUG` — debug-only code
- `SKIP_SPLASH` — skip splash screen, go to main menu
- `maingame` — skip all menus, go straight to PlayState (e.g. `lime build hl -debug -Dmaingame`)
- `API_KEY` — analytics token for production
- `dev_analytics` — dev mode analytics
- `llm_bridge` — enable LLM debug bridge (`window.__debug` API for Playwright introspection)
- `local` — legacy offline mode flag. Routes `Configure.getServerURL()` to `"local"` which creates an in-process `LocalRoom` instead of connecting to Colyseus. No `#if local` guards in game code — the `LocalRoom`/`GameLogic` embedded server handles everything through the same code path as multiplayer.
- `play` — start directly in `LobbyState` (real networked multiplayer: connect → character select → ready → round). This is the flag for testing multiplayer. Without it the game boots to `SplashScreenState`.
- `play_solo` — start in `LobbyState` with the in-process `LocalRoom` (single-player: no Colyseus server needed). Lobby shows "Single Player" title, auto-picks skin and readies immediately. Used by `watch_solo.sh`.
- `forcelocal` — point the networked client at the **local** Colyseus dev server: `Configure` hardcodes `ws://localhost:2567`, overriding `config.json` and the `SERVER_URL`/`SERVER_PORT`/`SERVER_PROTOCOL` env/defines. NOT the same as `local` (which removes networking entirely). `forcelocal` is still a real client — use it with `play` to test against a local server. The `#if forcelocal` branches in `Configure.hx` come *before* `#elseif sys`, so they correctly win on native builds.
- `db` — enables in-game debug buttons/tools in `PlayState` (spawn rock/pepper/waders, etc.). Used by `watch_net.sh`. Only touches `PlayState`, nothing network-related.
- `bot` — makes the local `Player` ignore input and just walk left/right on a timer (`Player.hx`, `#if bot`). Used for the second window in `watch_net.sh`. The bot does NOT auto-play (no casting/throwing/readying) — when testing, the bot window should ONLY walk left/right.
- `rocks` — debug flag: fills player inventory with `MAX_SLOTS` rocks at construction time

## Conventions

- Format with `./bin/format.sh` (haxe-formatter)
- Logging: `QLog.notice()`, `QLog.warning()`, `QLog.error()`
- Reference assets via the `AssetPaths` auto-generated class
- Game window: 640x480, 60 FPS
- Tile size: 16x16 pixels
- Entity-specific logic (sprites, state machines, input) belongs in the entity class, not PlayState or group managers. Entities receive an `FlxState` reference to manage their own child sprites. Group classes (spawners, etc.) should only handle spawning, iteration, and data pass-through — behavioral decisions belong in the entity. Use callbacks or events to notify other systems (e.g., fish catch → player state change).
- When positioning sprites, always position by center point using `offset` (i.e. `offset.set(-width/2, -height/2)` or `centerOffsets()`), not by top-left corner origin. The x/y passed in should represent the sprite's center.
- When making sprites visible, set their position before setting `visible = true` to avoid a one-frame flash at the previous location
- Use `FlxPoint.get()`/`.put()` for pooled points; call `.put()` when done to return to pool
- Always use curly braces `{}` around single-line `if`/`else`/`for`/`while` bodies, even when not required by the language
- Use casual language in code comments — say "butt" not "backside", keep it fun

## Key Sprite Assets
- `assets/aseprite/characters/playerA.json` (and playerB-H) — player skins, 48x48 frames, Aseprite JSON atlas with frame tags for animations
- `assets/aseprite/characters/fishShadow.png` — water fish silhouette sprite
- `assets/aseprite/fish.png` — caught/ground fish spritesheet, 32x32 frames (3 columns x 2 rows), 5 fish types of varying sizes within the cells
- `assets/aseprite/bobber.png` — fishing bobber sprite
- `assets/aseprite/aimingTarget.png` — reticle/aiming target, 8x8 frames, 4-frame animation

## Git Hooks

Pre-commit hook auto-exports changed Aseprite files and runs the formatter on staged files.

## Deployment

- Push to master auto-deploys HTML5 to itch.io web-dev channel
- GitHub releases trigger production deploy
- Required secrets: BUTLER_API_KEY, ANALYTICS_TOKEN
