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
Player extends FlxSprite (48x48 graphic, 16x16 hitbox). Takes an `FlxState` reference in its constructor so it can add/remove its own child sprites (reticle, power bar, cast bobber) from the scene. Movement speed is 150px/s (225 in hot mode). Uses `InputCalculator.getInputCardinal()` for input and tracks `lastInputDir` for facing direction. Has a `frozen` flag that suppresses movement during cast charging.

### Fishing Cast System (source/entities/Player.hx)
Cast mechanic uses a `CastState` enum (IDLE → CHARGING → CASTING → LANDED → RETURNING). Press Z to start charging — a power bar pulses below the player. Press Z again to launch a bobber toward the reticle at a distance proportional to power (max 96px / 6 tiles). Press Z or move to retract the bobber at any point (mid-flight, landed). The bobber flies back to the player at 500px/s before being destroyed. The `CastState` enum is defined at module level in Player.hx.

### Analytics & Storage (source/helpers/)
Analytics.hx reports events to Bitlytics. Storage.hx handles local persistence for achievements and metrics.

## Code Generation Pipelines

**Events:** Edit `assets/data/events/types.json` → run `./bin/generate_events.sh` → generates `source/events/gen/Event.hx`

**Aseprite sprites:** Place `.ase`/`.aseprite` in `art/` → pre-commit hook auto-exports to `assets/aseprite/` as JSON atlases

**FMOD:** Edit FMOD project in `fmod/` → export generates `FmodConstants.hx`

## Global Imports

`source/import.hx` provides project-wide imports: FMOD manager/constants, QuickLog (QLog), DebugSuite (DS), and bitdecay flixel extensions.

## Compile Flags

- `#if debug` / `#if FLX_DEBUG` — debug-only code
- `SKIP_SPLASH` — skip splash screen
- `API_KEY` — analytics token for production
- `dev_analytics` — dev mode analytics
- `llm_bridge` — enable LLM debug bridge (`window.__debug` API for Playwright introspection)

## Conventions

- Format with `./bin/format.sh` (haxe-formatter)
- Logging: `QLog.notice()`, `QLog.warning()`, `QLog.error()`
- Reference assets via the `AssetPaths` auto-generated class
- Game window: 640x480, 60 FPS
- Tile size: 16x16 pixels
- Entity-specific logic (sprites, state machines, input) belongs in the entity class, not PlayState. Entities receive an `FlxState` reference to manage their own child sprites.
- When making sprites visible, set their position before setting `visible = true` to avoid a one-frame flash at the previous location
- Use `FlxPoint.get()`/`.put()` for pooled points; call `.put()` when done to return to pool

## Git Hooks

Pre-commit hook auto-exports changed Aseprite files and runs the formatter on staged files.

## Deployment

- Push to master auto-deploys HTML5 to itch.io web-dev channel
- GitHub releases trigger production deploy
- Required secrets: BUTLER_API_KEY, ANALYTICS_TOKEN
