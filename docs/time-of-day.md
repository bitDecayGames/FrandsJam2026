# Time of Day & Night Lighting

Server-authoritative day/night cycle with an environment color-grade shader, a
top-left sundial HUD, and a night lighting model (player candle + item guide
glows). Files:

- `shared/GameLogic.hx` — authoritative clock, fast-forward, night gating
- `source/shaders/TimeOfDayShader.hx` — color grade + light field (camera filter)
- `source/ui/TimeOfDayHUD.hx` — sundial, digital time, period label, fast-forward buttons
- `source/states/PlayState.hx` — client clock advance, candle/glow driving, UI camera
- `source/entities/CloudShadow.hx` — night fade factor

## Server clock (GameLogic)

- `timeOfDayHour:Float` — hours `0..24`, starts at **12 (noon)**.
- `TIME_NORMAL_RATE = 0` — **time stands still**; the clock only moves when a
  fast-forward is requested. (Set this back to `24/600` for a passive 10-minute
  day-night cycle.)
- `TIME_FAST_RATE = 6.0` — fast-forward speed (game-hours per real second).
- Client message **`set_time` `{hour}`** puts the clock in fast-forward until it
  reaches the target hour (always moves forward, wraps at 24), then resumes
  normal rate. Sent by the HUD buttons.
- Broadcast **`time_sync` `{hour, rate}`** every 5s and immediately when the
  rate changes (fast-forward start/end). Clients integrate `hour += rate * dt`
  locally between syncs, so drift is bounded.
- `isNight():Bool` → `hour >= 21 || hour < 6`. Used for night gating.

The clock ticks in `fixedTick` regardless of round state. It is NOT reset
between rounds.

## Client sync (PlayState)

`onTimeOfDaySync` stores `todHour`/`todRate`; `update()` advances the hour,
feeds the sundial (`timeHud.setHour`) and the shader (`todShader.applyHour`).

## Color grade shader

`TimeOfDayShader` is applied with `FlxG.camera.filters =
[new openfl.filters.ShaderFilter(shader)]` (works on HL, flixel 6.1.2).
`applyHour()` interpolates piecewise-linear keyframes of
`(tint RGB, darken, desaturate)` across the 24h clock:

| Hour | Look | Tint | Dark | Desat |
|------|------|------|------|-------|
| 0-4.5 | midnight — pitch black | (0.45, 0.55, 1.00) | 0.00 | 0.45 |
| 6.0 | dawn (pink-purple blue hour) | (0.85, 0.70, 0.85) | 0.60 | 0.15 |
| 7.5 | morning — soft clear yellow (~4000K) | (1.00, 0.93, 0.72) | 0.97 | 0 |
| 12-14 | noon — **identity, "no shader"** | (1, 1, 1) | 1.00 | 0 |
| 16.5 | afternoon (~4500K) | (1.00, 0.93, 0.84) | 0.98 | 0 |
| 19.0 | evening sunset — orange-red (~2200K) | (1.00, 0.62, 0.38) | 0.88 | 0 |
| 20.5 | dusk (blue hour) | (0.65, 0.52, 0.85) | 0.42 | 0.25 |
| 22-24 | night — pitch black | (0.45, 0.55, 1.00) | 0.00 | 0.45 |

Morning vs evening are deliberately distinct: morning air is clear → soft
yellow; evening light passes through haze → deep orange-red.

## Night light model

At `darken == 0` the world is fully black; lights are the only way to see.
`uLightStrength` (candle master strength) ramps `(0.7 - dark) / 0.4` clamped
0..1 — lights fade in through dusk, full at night, zero during the day.

Light sources, all in **camera-buffer pixel space** (`openfl_TextureCoordv *
openfl_TextureSize`):

- **Player candle** — `uLightPos`/`uLightRadius`. Radius 120px, **240px while
  hot mode (pepper) is active** (eased between the two at rate 4/s). Steady —
  no flicker; position bound exactly to the player.
- **Guide glows** — 16 slots, each `vec4(x, y, radius, strength)`. Collected
  every frame by `PlayState.collectNightGlows()` (on-screen only, capped at 16):
  - burning bushes: radius 90, strength 1.0 — added FIRST so they never lose a slot
  - remote players in hot mode: radius 240, strength 1.0 (matches the local pepper
    bonfire; eased 0↔240 per player via `remoteGlowR` so it expands/contracts
    instead of popping)
  - rockets in flight: radius 60, strength 2.0 — strengths above 1.0 widen the
    fully-lit core (blend factors are clamped `max(0, 1-glow)` so this is safe)
  - ground rocks (small + big), ground fish, dog-dropped items, power-up box,
    waders/pepper pickups: radius ~22, strength 0.6
  - dogs: radius 28, strength 0.6
- **Night vision goggles** (`NightVision` inventory item, NVG debug button) —
  while held: candle radius is doubled (stacks with pepper → 480) and a grainy
  green overlay covers the screen (`uNightVision`/`uTime` uniforms — amplified
  luminance pushed into green + animated noise, scaled by `uLightStrength` so
  goggles only arm at full night). The overlay is NOT scaled by `uLightStrength`
  in the shader — the client factor owns timing so the green can linger over
  daylight. Eased on/off via `todNvFactor` with a ~0.5s hold of the current look
  before each toggle (night falls → beat of normal dark → green clicks on;
  daylight/removal → beat of green over the lit world → fades off) so it feels
  like the player is flicking them on/off.

**Compositing:** all sources union via a screen blend — `darkness =
candleDark * Π(1 - glowᵢ)`, `light = 1 - darkness` — then one final mix toward
the warm candle color `raw * (1.0, 0.76, 0.42)` (~1900K amber) scaled by
`0.55 + 0.45 * light` so brightness falls toward each rim. Do NOT compose
lights with `max()` or sequential mixes: `max` is not gradient-continuous
(visible ridge where fields cross) and sequential mixes make overlapping
lights darken each other.

### OpenFL gotcha: no array uniforms

OpenFL's `Shader.__processGLData` regex does not parse `uniform vec4 x[16];`
— it registers a single vec4 and silently uploads only the first 4 floats.
That's why the glow slots are **16 unrolled uniforms** `uGlow0..uGlow15`,
set via `Reflect.field(data, 'uGlow$i').value = [...]` in `setGlows()`.

## HUD (TimeOfDayHUD)

Top-left: sundial (rotating hand, noon = up, midnight = down, yellow/blue
ticks), digital `HH:MM`, period label (Night <5, Morning 5-11, Noon 11-14,
Afternoon 14-17, Evening 17-21, Night ≥21). Below: 2x2 fast-forward buttons —
Morning 7:30, Day 12:00, Evening 19:00, Night 0:00 — each sends `set_time`.
Click detection is manual screen-rect hit testing in `update()`.

### UI camera

All screen-space HUD (timer, sundial, inventory, score, debug buttons) is
rendered on a separate transparent `uiCamera`
(`FlxG.cameras.add(uiCamera, false)`) so the color-grade filter never dims it.
The camera is created in `PlayState.create()` **before `loadLevel()`** (the
inventory/score HUDs are constructed inside `loadLevel`). Any new HUD element
must set `cameras = [uiCamera]`.

## Night world behavior

- **Seagulls** — `updateSeagulls` skips the spawn block while `isNight()`;
  birds already flying finish their pass and despawn off-screen naturally.
  Spawning resumes at 6:00.
- **Cloud shadows** — client-side fade: `CloudShadow.visibilityFactor` (0..1)
  scales shadow alpha; PlayState eases it toward 0 at night / 1 during the day
  (~2s fade). Cloud positions keep simulating; only visibility fades.

## Adding a new glow source

Add a loop/branch in `PlayState.collectNightGlows()` calling
`addGlow(worldCenterX, worldCenterY, radius, strength)`. Full-strength (1.0)
sources should be added before the faint ones so the 16-slot cap can't drop
them.
