# Server Authority Debt Tracker

Things currently decided by the client instead of the server. Each item is a gap in server authority that should eventually be moved server-side.

## ✅ RESOLVED — Now Server-Authoritative

### Player Movement
Server runs Simulation.tickPlayer with collision resolution. Client predicts + reconciles via lastProcessedSeq. World bounds clamped server-side.

### Fish Spawning & AI
Server owns all fish AI in GameLogic.updateFish(). States synced via FishState.aiState schema field. Fish spawn, wander, attract, scare, fear, catch, respawn — all server-driven.

### Fish Catch Detection
Server detects fish-bobber proximity in updateFish() and broadcasts fish_caught.

### World Item Spawning
Server spawns rocks, waders, pepper, bushes from LDTK level data in spawnWorldItems(). Broadcasts positions via world_items + schema onAdd signals.

### Water Drowning
Server detects hot player on water tile in fixedTick() and broadcasts player_drown. Client no longer sends drown messages.

### Shallow Water State
Server sets inShallowWater on PlayerState schema after each movement tick.

### Dog AI
Server runs full A* pathfinding, state machine (chasing/waiting/seeking/fleeing), catch detection.

### Rocket System
Server creates projectiles, tracks physics, detects player hits, applies knockback. Client simulates visually only.

### Power-Up Spawning
Server picks random walkable tiles, manages respawn timer.

### Hunger Potion & Fish Bait
Server tracks affected water body, modifies fish attract distance / roaming targets.

### Item Drop Positions
Server validates landing positions are walkable (not water, not off-screen).

### Round Timer
Server owns roundTimerSec, ticks it in fixedTick, broadcasts timer_sync every 5s.

---

## ❌ REMAINING DEBT — Still Client-Authoritative

### Cast System (Bobber)
**Current:** Client manages cast state machine locally (IDLE→CHARGING→CASTING→LANDED→RETURNING). Sends cast_line/line_pulled as relay messages. Bobber position tracked client-side.
**Proper:** Server owns cast state via P_Input.buttons. Bobber position in server schema.

### Rock Throwing
**Current:** Client computes rock trajectory, sends throw_rock. Server relays but doesn't validate trajectory.
**Proper:** Server processes B button from P_Input, computes trajectory, validates target position.

### Item Pickup
**Current:** Client detects player-item overlap, kills sprite locally (prediction), sends item_pickup. Server validates and broadcasts. No rollback if rejected.
**Proper:** Server detects overlap each tick, validates inventory, only then kills item.

### Bush/Weed Interactions
**Current:** Client detects collision via Simulation.hitEntityIndices, triggers rustle/burst/burn, sends messages. Server relays.
**Proper:** Server detects player-bush/weed overlap and manages BushState/WeedState.

### Hot Mode (Pepper)
**Current:** Client activates hot mode on pickup, manages timer locally. Server tracks via hotModePlayers map but doesn't own the timer.
**Proper:** Server tracks hotModeTimer on PlayerState, handles activation/deactivation authoritatively.

### Inventory
**Current:** Client manages Inventory object locally. Server has no knowledge of what players hold (except waders/hot mode flags).
**Proper:** Server tracks inventory on PlayerState schema. All add/remove goes through server validation.

### Shop/Selling
**Current:** Client detects shop overlap, sells fish locally, sends fish_sold for relay.
**Proper:** Server validates proximity + inventory, processes sale, updates score.

### Score
**Current:** Client updates score locally on fish sale, sends score_update.
**Proper:** Server updates PlayerState.score when it processes sales.
