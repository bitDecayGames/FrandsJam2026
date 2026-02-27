# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FrandsJam is a HaxeFlixel game built with Haxe, OpenFL/Lime, and FMOD audio. It uses LDTK for level design, integrates with Newgrounds for medals/leaderboards, and reports analytics via Bitlytics/InfluxDB.

## Build & Development Commands

```bash
./bin/init_deps.sh          # Install dependencies from haxelib.deps
lime build html5             # Production build
lime build html5 -debug      # Debug build
./bin/format.sh              # Format Haxe code
./bin/export_ase.sh          # Export Aseprite files to atlases
./bin/generate_events.sh     # Regenerate Event.hx from types.json
./bin/setup_hooks.sh         # Install git hooks
```

**Do not run `./bin/run_debug.sh`** — it starts a long-running HTTP server. The user will run this themselves. Use `lime build html5 -debug` to compile only.

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

## Git Hooks

Pre-commit hook auto-exports changed Aseprite files and runs the formatter on staged files.

## Deployment

- Push to master auto-deploys HTML5 to itch.io web-dev channel
- GitHub releases trigger production deploy
- Required secrets: BUTLER_API_KEY, ANALYTICS_TOKEN
