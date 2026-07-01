# Local Server (Embedded Pattern 2) Plan

## Goal
Single code path for online and offline play. No `#if local` guards.

## Architecture

### shared/GameLogic.hx
- Extracted from server/hxsrc/GameRoom.hx
- Pure Haxe — no Colyseus, no sys, no JS imports
- All game simulation: fish AI, seagulls, worms, clouds, spawning, round timer, bush rects
- Uses callback interfaces for I/O:
  - `broadcast: (topic:String, data:Dynamic) -> Void`
  - `sendToClient: (clientId:String, topic:String, data:Dynamic) -> Void`
- `onMessage(clientId, topic, data)` — process incoming message
- `addPlayer(id)` / `removePlayer(id)` — player lifecycle
- `update(deltaMs)` — tick simulation

### server/hxsrc/GameRoom.hx (thin wrapper)
- Creates GameLogic, wires broadcast/send to Colyseus room.broadcast/client.send
- Routes onMessage to GameLogic.onMessage
- onJoin/onLeave call GameLogic.addPlayer/removePlayer

### source/net/LocalRoom.hx (in-process loopback)
- Creates GameLogic with broadcast/send that dispatch directly to NetworkManager signals
- sendMessage routes through GameLogic.onMessage inline
- Simulates join on connect, schema changes fire immediately
- Ticked each frame via PlayState or NetworkManager.update()

### source/net/NetworkManager.hx
- connect() either connects to Colyseus OR creates LocalRoom
- sendMessage() either sends via room.send OR calls localRoom.onMessage
- All signals work identically in both modes
- Remove ALL #if local guards
