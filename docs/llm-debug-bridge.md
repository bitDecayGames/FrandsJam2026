# LLM Debug Bridge

A debug module that exposes game introspection and control via `window.__debug` in the browser, designed for use with Playwright MCP tools (browser_evaluate, browser_take_screenshot, etc.).

## Quick Start

1. The user starts the debug server:
   ```bash
   ./bin/run_llm_debug.sh
   ```
2. Navigate Playwright to the game:
   ```
   browser_navigate → http://localhost:8080
   ```
3. Call debug functions via browser_evaluate:
   ```
   browser_evaluate → () => window.__debug.getState()
   ```

All functions return JSON strings. Parse with `JSON.parse()` on the JS side if needed.

To start the debug server, run `./bin/run_llm_debug.sh` in the background.

## Build Details

The bridge is gated behind the `llm_bridge` compiler flag. It is not included in normal debug builds. The wrapper script passes `-Dplay -Dllm_bridge` to skip menus and enable the bridge.

To build manually without serving:
```bash
lime build html5 -Dplay -Dllm_bridge
```

## API Reference

### Introspection

#### `getState()`
Returns current game state info.
```json
{"stateName": "states.PlayState", "subState": null, "gameWidth": 640, "gameHeight": 480, "elapsed": 0.02, "paused": false, "timeScale": 1}
```

#### `getPlayer()`
Returns the first `entities.Player` found in the scene graph.
```json
{"x": 120, "y": 176, "width": 16, "height": 16, "velocityX": 0, "velocityY": 0, "animName": "right", "animFrame": 3, "facing": "R", "alive": true, "speed": 150}
```
Returns `{"error": "Player not found"}` if no player exists.

#### `getSprites()`
Recursive scene graph walk (max depth 10). Returns an array of sprite info objects.
```json
[
  {"type": "flixel.group.FlxTypedGroup", "flixelType": "2", "children": [
    {"type": "levels.ldtk.BDTilemap", "flixelType": "3", "x": 0, "y": 0, "width": 1280, "height": 480, "visible": true, "alive": true}
  ]},
  {"type": "entities.Player", "flixelType": "1", "x": 120, "y": 176, "width": 16, "height": 16, "velocityX": 0, "velocityY": 0, "visible": true, "alive": true, "animName": "right", "animFrame": 3}
]
```

#### `getTilemap()`
Returns the first tilemap's collision grid as ASCII art. `.` = empty, `#` = solid, `^` = one-way (up), `?` = other.
```json
{"widthInTiles": 80, "heightInTiles": 30, "tileWidth": 16, "tileHeight": 16, "x": 0, "y": 0, "collisionGrid": "....###.....####\n............^...\n............^^^^"}
```

#### `getCamera()`
Returns camera position and scroll bounds.
```json
{"scrollX": -64, "scrollY": 0, "zoom": 1, "width": 640, "height": 480, "minScrollX": 0, "maxScrollX": 576, "minScrollY": 0, "maxScrollY": 480}
```

#### `getEventLog(count?)`
Returns the last N events from a ring buffer (default 50, max 200).
```json
[{"id": 1, "type": "player_spawn", "posX": 120, "posY": 176}]
```

### Control

#### `pause()`
Pauses the game loop. Returns `{"paused": true}`.

#### `resume()`
Resumes the game loop. Returns `{"paused": false}`.

#### `stepFrames(n)`
Pauses the game and advances exactly N frames, then stays paused. Returns `{"stepping": 5, "paused": true}`.

#### `setTimeScale(f)`
Sets the game time scale (1.0 = normal, 2.0 = double speed, 0.5 = half). Returns `{"timeScale": 2}`.

## Source

- Bridge implementation: `source/debug/LLMDebugBridge.hx`
- Init call: `source/Main.hx` in `configureDebug()`
- Frame update hook: `source/plugins/GlobalDebugPlugin.hx`
