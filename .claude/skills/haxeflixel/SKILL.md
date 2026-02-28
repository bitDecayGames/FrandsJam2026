---
name: haxeflixel
description: Look up HaxeFlixel API docs, guides, and demo source code
argument-hint: "[topic or class name]"
allowed-tools: WebFetch, Bash, Read, Grep, Glob
---

# HaxeFlixel Documentation Lookup

Use WebFetch to read HaxeFlixel documentation. It renders these sites well.

## Version Note

The online API docs are for **6.1.0** but this project uses **flixel 6.0.0**. The online docs are fine for general reference but may include newer APIs. If exact version accuracy matters, read the local source instead:

- **Flixel source:** `~/src/flixel/flixel/` (checked out at ~6.0.0)
- **Flixel demos:** `~/src/flixel-demos/` (organized by category: Features/, Games/, etc.)

If these repos aren't cloned yet, clone them:
```bash
[ -d ~/src/flixel ] || git clone https://github.com/HaxeFlixel/flixel.git ~/src/flixel
[ -d ~/src/flixel-demos ] || git clone https://github.com/HaxeFlixel/flixel-demos.git ~/src/flixel-demos
```

For example, to check the exact FlxSprite API at our version:
```bash
# Read a specific class
cat ~/src/flixel/flixel/FlxSprite.hx

# Search for a method across the codebase
grep -rn "function loadGraphic" ~/src/flixel/flixel/
```

## API Documentation (most common use)

The API lives at `https://api.haxeflixel.com/`. URLs follow a predictable pattern:

```
https://api.haxeflixel.com/flixel/FlxSprite.html        # core class
https://api.haxeflixel.com/flixel/FlxG.html             # global helper
https://api.haxeflixel.com/flixel/FlxObject.html        # base object
https://api.haxeflixel.com/flixel/FlxState.html         # game state
https://api.haxeflixel.com/flixel/FlxCamera.html        # camera
```

**URL pattern:** `https://api.haxeflixel.com/{package}/{ClassName}.html`

Common packages:
- `flixel` — core classes (FlxSprite, FlxG, FlxObject, FlxState, FlxCamera, FlxGame, FlxSubState)
- `flixel/group` — FlxGroup, FlxTypedGroup, FlxSpriteGroup
- `flixel/tile` — FlxTilemap, FlxBaseTilemap
- `flixel/math` — FlxPoint, FlxRect, FlxVector, FlxAngle, FlxMath, FlxVelocity
- `flixel/text` — FlxText, FlxBitmapText
- `flixel/ui` — FlxButton, FlxBar
- `flixel/input/keyboard` — FlxKeyboard
- `flixel/input/mouse` — FlxMouse
- `flixel/input/gamepad` — FlxGamepad
- `flixel/sound` — FlxSound
- `flixel/tweens` — FlxTween
- `flixel/tweens/motion` — motion tweens
- `flixel/tweens/misc` — misc tweens
- `flixel/effects` — FlxFlicker, FlxSpriteFilter
- `flixel/effects/particles` — FlxEmitter, FlxParticle
- `flixel/animation` — FlxAnimationController, FlxAnimation
- `flixel/graphics` — FlxGraphic, frames
- `flixel/path` — FlxPath
- `flixel/util` — FlxColor, FlxTimer, FlxSignal, FlxSort, FlxSave, FlxPool
- `flixel/addons/display` — FlxBackdrop, FlxTiledSprite
- `flixel/addons/editors/tiled` — Tiled map support
- `flixel/addons/editors/ogmo` — Ogmo editor support
- `flixel/addons/effects` — FlxTrail, FlxTrailArea, FlxWaveEffect
- `flixel/addons/ui` — FlxUIState, various UI widgets
- `flixel/addons/weapon` — FlxWeapon

When looking up a class, use WebFetch with a prompt like:
> "Return the full API documentation. Include class description, all properties, method signatures with parameters and return types, and any code examples."

If you're unsure of the exact class name or package, fetch the package index:
> `https://api.haxeflixel.com/flixel/` — lists all classes in the flixel package

## Regular Documentation / Guides

The handbook and tutorials are at `https://haxeflixel.com/documentation/`.

Key pages:
- `https://haxeflixel.com/documentation/flxsprite/` — FlxSprite guide
- `https://haxeflixel.com/documentation/flxstate/` — FlxState guide
- `https://haxeflixel.com/documentation/flxgroup/` — FlxGroup guide
- `https://haxeflixel.com/documentation/keyboard/` — Keyboard input
- `https://haxeflixel.com/documentation/mouse/` — Mouse input
- `https://haxeflixel.com/documentation/gamepads/` — Gamepad input
- `https://haxeflixel.com/documentation/cheat-sheet/` — Quick reference
- `https://haxeflixel.com/documentation/debugger/` — Debug tools
- `https://haxeflixel.com/documentation/troubleshooting/` — Common issues

URL pattern for guides: `https://haxeflixel.com/documentation/{topic-slug}/`

## Demo Projects (reference implementations)

All demos are in one repo: `https://github.com/HaxeFlixel/flixel-demos`

The demos repo is pre-cloned at `~/src/flixel-demos/`, organized by category (Features/, Games/, etc.).

```bash
# List demo categories
ls ~/src/flixel-demos/

# Find a specific demo
find ~/src/flixel-demos -maxdepth 2 -type d -name "FlxCamera"

# Search demo code for usage examples
grep -rn "FlxTween" ~/src/flixel-demos/ --include="*.hx" -l
```

To get a description of a specific demo, fetch `https://haxeflixel.com/demos/{DemoName}/`.

## What to look up based on $ARGUMENTS

- If given a class name (e.g., "FlxSprite", "FlxTween"), fetch the API docs for that class
- If given a concept (e.g., "input", "collision", "animation"), fetch the relevant guide page
- If given "demos" or a demo name, look up the demos list or specific demo
- If given a general question, start with the cheat sheet, then drill into API docs as needed
