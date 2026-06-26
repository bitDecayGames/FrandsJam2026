# Server Authority Debt Tracker

Things currently decided by the client instead of the server. Each item is a gap in server authority that should eventually be moved server-side.

## Spawn Positions
**Current:** Client computes random spawn points from LDTK level data (`Level.getRandomSpawnPoints`), then sends `set_position` to the server so its PlayerState matches.
**Proper:** Server should compute spawn points from its own collision map/level data and assign them to PlayerState in `onJoin()`. Requires porting the spawn logic to shared code (no Flixel dependency).

## Fish Spawning & AI
**Current:** Host client runs FishSpawner, computes fish positions, sends `fish_spawn`/`fish_move` to server. Server relays to other clients.
**Proper:** Server should own FishSimulation — spawn fish, run wandering AI, detect bobber attraction, handle catches. Clients just render FishState from schema.

## Fish Catch Detection
**Current:** Host client detects fish-bobber overlap and sends `fish_caught`. Server relays.
**Proper:** Server detects catches in its tick loop by checking FishState positions against BobberState positions.

## Cast System (Bobber)
**Current:** Client manages the entire cast state machine locally (IDLE→CHARGING→CASTING→LANDED→RETURNING). Sends `cast_line`/`line_pulled` as relay messages.
**Proper:** Server owns cast state via Simulation.tickPlayer's state machine. Bobber position tracked in server schema. Client sends A button state via P_Input.buttons.

## Rock Throwing
**Current:** Client computes rock trajectory, sends `throw_rock`/`rock_splash` as relay messages.
**Proper:** Server processes B button from P_Input, computes trajectory, updates RockProjectileState, broadcasts splash for cosmetics.

## World Item Spawning
**Current:** Host client spawns rocks, waders, pepper at random positions, sends `world_items` to server for relay.
**Proper:** Server spawns items from level data on room creation. WorldItemState in schema.

## Item Pickup
**Current:** Client detects player-item overlap, picks up item locally, sends `item_pickup` for relay.
**Proper:** Server detects overlap each tick, validates inventory, updates PlayerState.inventory.

## Bush/Weed Interactions
**Current:** Client detects collision, triggers rustle/burst/burn locally, sends relay messages.
**Proper:** Server detects player-bush/weed overlap each tick, updates BushState/WeedState schema.

## Hot Mode (Pepper)
**Current:** Client activates hot mode on pickup, manages timer locally, sends `hot_pepper` for relay.
**Proper:** Server tracks hotMode/hotModeTimer on PlayerState, applies speed multiplier in Simulation.

## Water Drowning
**Current:** Client detects hot player touching water colliders, triggers drown locally.
**Proper:** Server detects water overlap for hot players in tick loop, sets drowned state on PlayerState.

## Inventory
**Current:** Client manages Inventory object locally. Server has no knowledge of what players hold.
**Proper:** Server tracks inventory on PlayerState (encoded string or separate schema). All add/remove goes through server validation.

## Shop/Selling
**Current:** Client detects shop overlap, sells fish locally, sends `fish_sold` for relay.
**Proper:** Client sends `sell_fish` request, server validates proximity + inventory, processes sale, updates score.

## Round Timer
**Current:** Host client runs TimedGoal, sends `timer_sync` periodically. Non-host clients interpolate.
**Proper:** Server owns round timer in RoundState schema. Ticks it in fixedTick. All clients read from schema.

## Score
**Current:** Client updates score locally on fish sale, sends `score_update`.
**Proper:** Server updates PlayerState.score when it processes sales.

---

## What IS Server-Authoritative Now (Phase 1)
- **Player movement**: Server runs Simulation.tickPlayer with collision resolution. Client predicts + reconciles via lastProcessedSeq.
- **Player position**: Server owns x/y/velocityX/velocityY on PlayerState schema.
- **Collision**: Server builds CollisionMap from LDTK + tile-hitboxes.json. Same code runs on client for prediction.
