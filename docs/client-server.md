# Client-Server Collision & Interaction Architecture

## Research Summary

Based on industry sources: Gabriel Gambetta, Gaffer on Games (Glenn Fiedler), Valve Source Engine, Overwatch GDC 2017 (Tim Ford), Unity Netcode, Unreal Engine, Photon, Colyseus community.

---

## Three-Tier Interaction Model

### Tier 1: Cosmetic-Only (No State Change)
**Examples**: Bush rustle, grass sway, footstep particles, water ripples, ambient animations.

**Pattern**: 100% client-side. No server involvement.
- Each client detects overlap locally and plays SFX/animation immediately.
- Remote players' interactions are triggered by the *observing* client based on interpolated positions.
- No network traffic needed.
- Slight visual differences between clients (timing, particle positions) are acceptable because these have zero gameplay impact.

**Source Engine precedent**: "Particles, junk flying around, rocks on the ground, and other stuff that doesn't affect the actual game can be done just client-side."

**Overwatch precedent**: "Predicts everything by default. Teams have to explicitly opt out."

### Tier 2: Stateful Interactions (State Changes, Server-Authoritative)
**Examples**: Bush burns/destroyed, rock breaks, door opens, item pickup, fish caught.

**Pattern**: Client predicts cosmetics, server owns the state transition.

1. **Client detects interaction locally** — plays predicted cosmetic effects (particles, SFX) immediately.
2. **Client sends interaction request to server** (e.g., "player X interacted with bush Y").
3. **Server validates** — checks player proximity, object state, game rules (e.g., "only fire players can burn bushes").
4. **Server mutates state** — marks object as destroyed in authoritative world state.
5. **Server broadcasts state change** — all clients receive the update.
6. **All clients update visuals** — hide/remove object, spawn destruction effects.

**Key implementation details (Unreal Engine multiplayer destructible guide)**:
- Use a centralized manager to track destructible states, not per-object replication.
- Use delta replication (only send changes).
- Never remove from data structures; mark as destroyed and hide visually.
- Late-joining players receive the full state on connect.

### Tier 3: Complex Physics (Server Simulation)
**Examples**: Knocked barrels, ragdolls, flying debris.

**Pattern**: Server runs physics simulation, sends snapshots, clients interpolate.
- Most games avoid client-side prediction for non-player physics objects.
- Not relevant for this game.

---

## SFX/Visual Effects Responsibility

**Rule: The local client always plays cosmetic effects immediately. Never wait for server confirmation.**

- **Overwatch (GDC 2017)**: Uses "deferred contact records" — collision side-effects (particles, SFX) are queued into a singleton component and spawned once per frame, cleanly separating cosmetic effects from authoritative state changes.
- **Glenn Fiedler**: "Predicted weapon firing on the client is purely cosmetic." Play SFX, spawn particles immediately. Server resolves actual gameplay outcome separately.
- **General consensus**: "Playing the local effects first (particles, sound effects) and then applying the gameplay effects when you're actually confirmed" is the standard.

---

## Collision Reconciliation

**Standard pattern (Gabriel Gambetta / Gaffer on Games)**:

1. Client sends input with sequence number.
2. Client applies input locally (prediction).
3. Server processes input, runs collision, sends back authoritative state + last processed sequence.
4. Client receives server state, discards processed inputs, re-applies unprocessed inputs.
5. If result differs from prediction, client corrects (snap or smooth interpolation).

**Static world geometry** (walls, water, rocks): Client and server have identical collision maps from LDTK. They virtually always agree. No special reconciliation needed.

**Dynamic world objects** (bushes, destructibles): Client predicts cosmetic overlap effects. Server is authoritative for state changes. If client predicted a collision with an object that the server says is already destroyed, the server correction causes a visual snap (mitigated by smooth error correction).

---

## Professional Engine Approaches

### Source Engine (Valve)
- Server authoritative for all gameplay-affecting physics
- Client-side only for small cosmetic props
- `prop_physics_multiplayer` with server-solid, server-non-solid, client-only modes
- Temporary entities (unreliable) for visual effects
- Prediction tables for synchronized entity state

### Unreal Engine (Epic)
- Overlap events on server trigger replicated gameplay changes
- `HasAuthority()` guards prevent clients from modifying state directly
- GameState component centralizes world-object tracking
- FastArraySerializer for delta-only replication

### Unity Netcode
- Server-authoritative physics: simulation runs only on server
- Client Rigidbodies are kinematic
- Trigger events fire on both; collision events only on server for networked bodies
- Pattern: `OnCollisionEnter` on server → `Rpc(SendTo.ClientsAndHost)`

### Photon
- Master Client handles all collision (consistent but adds lag), or
- Each owner handles their own collisions (responsive, needs lag compensation)
- For true authority, recommends dedicated server-side "simulation clients"

### Overwatch (Blizzard)
- Predict everything by default, opt out when needed
- Deferred contact records separate cosmetics from state
- Server reconciliation via rollback-and-replay
- 220ms latency cap: beyond that, use dead reckoning

---

## Application to FrandsJam

### Bush Rustle → Tier 1 (Cosmetic)
- Remove `bush_rustle` network message entirely
- Each client detects overlap locally using `FlxG.collide`/`FlxG.overlap`
- Client plays rustle animation and SFX immediately
- For remote players, the observing client triggers rustle based on interpolated positions
- No server involvement

### Bush Ignite/Burn → Tier 2 (Stateful)
- Client plays fire SFX immediately on overlap detection
- Client sends `bush_ignite` to server
- Server validates (player has fire, bush is alive)
- Server marks bush as destroyed, removes entity rect
- Server broadcasts state change to all clients
- All clients hide bush and play burn animation

### Weed Burst → Tier 1 (Cosmetic) + Tier 2 (State)
- Burst animation/SFX: Tier 1, play immediately on client
- Weed removal: Tier 2, server broadcasts removal

### Rock/Waders/Pepper Pickup → Tier 2 (Stateful)
- Client sends pickup request
- Server validates proximity and availability
- Server removes from world, adds to inventory
- Client can play pickup SFX immediately (predicted)

### Fish Catch → Tier 2 (Stateful)
- Server detects catch (bobber proximity to fish)
- Server broadcasts `fish_caught`
- Client plays catch animation/SFX on receipt

### Water/Wall Collision → Static Geometry
- Identical collision maps on client and server
- Both resolve independently, virtually always agree
- No special handling needed

---

## Sources

- [Gabriel Gambetta - Client-Side Prediction and Server Reconciliation](https://www.gabrielgambetta.com/client-side-prediction-server-reconciliation.html)
- [Gabriel Gambetta - Client-Server Game Architecture](https://www.gabrielgambetta.com/client-server-game-architecture.html)
- [Gaffer on Games - Introduction to Networked Physics](https://gafferongames.com/post/introduction_to_networked_physics/)
- [Gaffer on Games - State Synchronization](https://gafferongames.com/post/state_synchronization/)
- [Glenn Fiedler / mas-bandwidth - Choosing the Right Network Model](https://mas-bandwidth.com/choosing-the-right-network-model-for-your-multiplayer-game/)
- [Overwatch Gameplay Architecture and Netcode - GDC 2017](https://www.gdcvault.com/play/1024001/-Overwatch-Gameplay-Architecture-and)
- [Valve Developer Wiki - Physics Entities on Server & Client](https://developer.valvesoftware.com/wiki/Physics_Entities_on_Server_&_Client)
- [Valve Developer Wiki - Source Multiplayer Networking](https://developer.valvesoftware.com/wiki/Source_Multiplayer_Networking)
- [Unity Netcode - Physics](https://docs.unity3d.com/Packages/com.unity.netcode.gameobjects@2.5/manual/advanced-topics/physics.html)
- [Unreal Engine - Networking Overview](https://dev.epicgames.com/documentation/en-us/unreal-engine/networking-overview)
- [Unreal Engine Multiplayer Destructible Guide](https://blog.ahmadz.ai/unreal-engine-multiplayer-static-mesh-destructible-trees-rocks/)
- [Colyseus - Server-Side Collision Detection](https://discuss.colyseus.io/topic/780/detect-collision-in-server-colyseus-solved)
