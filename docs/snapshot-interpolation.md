# Plan: Fixed Render Delay + Snapshot Interpolation for Remote Players

## Context

The current remote player interpolation uses a **spring-based system** (`updateRemoteInterpolation`) that immediately applies each Colyseus `onChange` to `remoteTargetX/Y` and then chases it with spring physics. This approach is reactive — it can't absorb jitter because it only ever has *one* target position at a time.

The [Victor Zhou io-game tutorial](https://victorzhou.com/blog/build-an-io-game-part-1/#4-client-networking) describes a better approach: **snapshot interpolation with a fixed render delay**.

### The Technique
1. **Server stamps each update** with its cumulative `serverTime` (seconds since room start).
2. **Client buffers snapshots** tagged with `serverTime`.
3. **Client tracks the server-to-client clock offset** on each receive, allowing it to compute the current server time between ticks.
4. **Render 100ms behind** the estimated current server time (`renderTime = currentServerTime - 0.1`).
5. **Linearly interpolate** between the two snapshots bracketing `renderTime`.

Benefits:
- Smooth movement even when server updates arrive irregularly (jitter absorbed by buffer)
- No spring "chasing" artifacts
- Canonical time axis from server prevents drift between clients
- Easy to tune via a single `RENDER_DELAY_SECS` constant

### Clock Sync (simple offset approach)
- Server advances `state.serverTime` by `fixedTimeStep` each tick (50ms)
- When client receives a snapshot: record `serverTimeOffset = serverTime - haxe.Timer.stamp()`
- Between ticks: `currentServerTime = haxe.Timer.stamp() + serverTimeOffset` (advances at 60fps)
- `renderTime = currentServerTime - RENDER_DELAY_SECS`

---

## Files to Modify

### 0. `schema/GameState.hx` + `server/hxsrc/rooms/GameRoom.hx`

**`schema/GameState.hx`** — add the server timestamp field (shared between client and server builds):
```haxe
@:type("float32") public var serverTime:Float;
```
Place after `shopReady`. Initialize to `0.0` (Haxe default is fine).

**`server/hxsrc/rooms/GameRoom.hx`** — advance it each fixed tick in `fixedTick()`:
```haxe
function fixedTick(t:Float) {
    state.serverTime += t;  // add fixedTimeStep (0.05s) each tick
    tick++;
    // ... rest unchanged
}
```
No server-side init needed — `float32` fields default to `0.0` in Colyseus schemas.

---

### 1. `source/entities/Player.hx`

**Add typedef** (module-level, near `CastState`):
```haxe
typedef PlayerSnapshot = {
    time: Float,    // seconds, from GameState.serverTime at the moment of update
    x: Float,
    y: Float,
    velX: Float,
    velY: Float,
}
```

**Replace spring interpolation fields** (lines ~121–133) with:
```haxe
// Snapshot interpolation for remote players
static inline var RENDER_DELAY_SECS:Float = 0.1;   // 100ms behind server time
static inline var MAX_SNAPSHOTS:Int = 20;
static inline var REMOTE_TELEPORT_DIST_SQ:Float = 128 * 128;

var snapshots:Array<PlayerSnapshot> = [];

// Server clock offset: serverTime = haxe.Timer.stamp() + serverTimeOffset
// Updated each time a new snapshot arrives, so currentServerTime advances at 60fps
public var serverTimeOffset:Float = 0.0;
```
Remove: `remoteTargetX`, `remoteTargetY`, `remoteServerVelX`, `remoteServerVelY`, `remoteWasStationary`, `REMOTE_SNAP_DIST_SQ`, `REMOTE_BLEND_RANGE`, `REMOTE_SPRING_K`, `REMOTE_MAX_CORRECTION`.

> **Note:** `serverTimeOffset` is written by PlayState's `bindPlayer` (which has access to `colyRoom.state.serverTime`), and read by `updateRemoteInterpolation`. The local player doesn't use it but it lives on Player since that's where `updateRemoteInterpolation` runs.

**Add `pushSnapshot()` public method** (near `handleChange`):
```haxe
public function pushSnapshot(serverTime:Float, x:Float, y:Float, velX:Float, velY:Float):Void {
    // Update the clock offset so renderTime advances at 60fps between server ticks
    serverTimeOffset = serverTime - haxe.Timer.stamp();

    var snap:PlayerSnapshot = {
        time: serverTime,
        x: x, y: y, velX: velX, velY: velY
    };
    snapshots.push(snap);
    // Trim old snapshots (keep a rolling window)
    while (snapshots.length > MAX_SNAPSHOTS) {
        snapshots.shift();
    }
}
```

**Rewrite `updateRemoteInterpolation()`**:
```haxe
function updateRemoteInterpolation() {
    if (snapshots.length == 0) return;

    // Freeze position during cast/catch animations
    if (castState == CAST_ANIM || castState == CASTING || castState == CATCH_ANIM || castState == RETURNING) {
        velocity.set(0, 0);
        return;
    }

    // Estimate current server time using the offset calibrated on last snapshot receive
    var currentServerTime = haxe.Timer.stamp() + serverTimeOffset;
    var renderTime = currentServerTime - RENDER_DELAY_SECS;

    // Find two snapshots bracketing renderTime
    var before:PlayerSnapshot = snapshots[0];
    var after:PlayerSnapshot = snapshots[snapshots.length - 1];

    for (i in 0...snapshots.length - 1) {
        if (snapshots[i].time <= renderTime && snapshots[i + 1].time >= renderTime) {
            before = snapshots[i];
            after = snapshots[i + 1];
            break;
        }
    }

    // Interpolate (or clamp to oldest/newest)
    var t:Float = 0.0;
    var dt = after.time - before.time;
    if (dt > 0) {
        t = Math.max(0, Math.min(1, (renderTime - before.time) / dt));
    } else {
        t = 1.0; // same timestamp: snap to latest
    }

    var targetX = before.x + (after.x - before.x) * t;
    var targetY = before.y + (after.y - before.y) * t;
    var interpVelX = before.velX + (after.velX - before.velX) * t;
    var interpVelY = before.velY + (after.velY - before.velY) * t;

    // Teleport if way off (e.g., spawn or level load)
    var dx = targetX - x;
    var dy = targetY - y;
    if (dx * dx + dy * dy > REMOTE_TELEPORT_DIST_SQ) {
        setPosition(targetX, targetY);
        velocity.set(0, 0);
    } else {
        setPosition(targetX, targetY);
        velocity.set(interpVelX, interpVelY);
    }

    // Update facing from interpolated velocity (same pattern as handleChange used to do)
    var facingVel = FlxPoint.get(interpVelX, interpVelY);
    if (facingVel.length > 0) {
        lastInputDir = Cardinal.closest(facingVel);
    }
    facingVel.put();
    if (!throwing) {
        playMovementAnim();
    }

    // Trim snapshots older than render window (keep at least 2)
    while (snapshots.length > 2 && snapshots[1].time < renderTime - RENDER_DELAY_SECS) {
        snapshots.shift();
    }
}
```

**Update `initRemote()`** (line ~377): initialize `snapshots = []` there (not `remoteTargetX/Y`).

**Remove dead code**: `handleChange()` method and `cleanupNetwork()` are no longer needed (they were already commented out). Can be removed.

---

### 2. `source/states/PlayState.hx`

**In `bindPlayer()`**, change the remote case (lines ~193–196):
```haxe
// Before (snap):
p.setPosition(serverState.x, serverState.y);

// After (push snapshot with server timestamp):
p.pushSnapshot(colyRoom.state.serverTime, serverState.x, serverState.y,
    serverState.velocityX, serverState.velocityY);
```

---

## What Does NOT Change

- Local player prediction/reconciliation logic is untouched
- `Simulation.hx` and `CollisionMap.hx` are untouched
- No new files needed

---

## Tuning Knobs

| Constant | Location | Purpose |
|---|---|---|
| `RENDER_DELAY_SECS` | `Player.hx` | How far behind to render (0.1 = 100ms typical; increase if network is jittery) |
| `MAX_SNAPSHOTS` | `Player.hx` | Rolling buffer size (20 is plenty for 20Hz server tick) |
| `REMOTE_TELEPORT_DIST_SQ` | `Player.hx` | Distance above which we just snap (handles spawns/teleports) |

---

## Verification

1. Build: `lime build hl -debug -Dmaingame`
2. Run two clients (or use latency simulation) and observe remote player movement
3. Check: remote players should move smoothly even when simulating 50–100ms jitter
4. Check: no spring-chase artifact (position overshooting target)
5. Watch values: `snapshots.length` should stay ~2–5 during normal play; spikes = jitter absorbed
6. Edge case: disconnect/reconnect should teleport (large dist triggers snap path)
