import schema.GameState;
import schema.GameState.P_Input;
import schema.BushState;
import schema.FishState;
import schema.PlayerState;
import schema.RoundState;
import haxe.Json;
import colyseus.server.Client;
import colyseus.server.Room.RoomOf;
import colyseus.server.Room.CloseCode;
import haxe.extern.EitherType;
import js.lib.Promise;
import Ldtk.LdtkProject;

class GameRoom extends RoomOf<GameState, Dynamic> {
	var simulation:Simulation;
	var elapsedTime:Float;

	// Fish AI data
	var waterBodies:Array<Array<{x:Float, y:Float}>>; // water tile positions per body
	var bobberPositions:Map<String, {x:Float, y:Float}>; // sessionId -> bobber pos
	var nextFishID:Int;
	var ldtkRaw:Dynamic; // cached level data for flood-fill

	// Seagull AI data
	var seagulls:Array<{
		id:Int,
		x:Float,
		y:Float,
		velX:Float,
		velY:Float,
		goingRight:Bool,
		poopTimer:Float,
		altitude:Float,
		driftTimer:Float,
		driftVelY:Float
	}>;
	var nextSeagullId:Int;
	var seagullSpawnTimer:Float;

	static var FISH_SPEED:Float = 20;
	static var FISH_ATTRACT_SPEED:Float = 40;
	static var FISH_ARRIVE_DIST:Float = 2;
	static var FISH_ATTRACT_DIST:Float = 32;
	static var FISH_CATCH_DIST:Float = 4;
	static var FISH_SEPARATION_DIST:Float = 20;
	static var NUM_FISH_TYPES:Int = 12;

	override public function onCreate(options:Dynamic):Void {
		elapsedTime = 0;
		maxClients = 6;
		setState(new GameState());

		// Build collision map from level data
		var hitboxJson = sys.io.File.getContent("../assets/data/tile-hitboxes.json");
		var ldtkProject = new LdtkProject();
		var raw = ldtkProject.getLevel("Level_0");
		ldtkRaw = raw;
		state.collision = CollisionMap.fromLevel(raw, hitboxJson);
		simulation = new Simulation(state.collision);
		state.inputQueue = new Map();

		// Initialize fish AI data
		waterBodies = [];
		bobberPositions = new Map();
		nextFishID = 1;

		// Spawn server-owned fish
		spawnFish();

		// Initialize seagull data
		seagulls = [];
		nextSeagullId = 1;
		seagullSpawnTimer = 3.0;

		// Start fixed-tick simulation loop
		this.setSimulationInterval(this.serverUpdate);

		trace('start room: ${roomId}:${roomName}');

		onMessage("player_input", (client:Client, data:Array<P_Input>) -> {
			if (!state.players.has(client.sessionId)) {
				return;
			}
			if (!state.inputQueue.exists(client.sessionId)) {
				state.inputQueue.set(client.sessionId, []);
			}
			if (data == null) {
				return;
			}
			for (input in (data : Array<P_Input>)) {
				state.inputQueue.get(client.sessionId).push(input);
			}
		});

		// client tells server where it spawned so the server's PlayerState
		// starts at the right position (server doesn't run Flixel spawn logic)
		onMessage("set_position", (client:Client, data:{x:Float, y:Float}) -> {
			var player:PlayerState = state.players.get(client.sessionId);
			if (player != null) {
				player.x = data.x;
				player.y = data.y;
			}
		});

		// --- Cast system: server validates and broadcasts state changes ---
		onMessage("cast_start", (client:Client, data:{dir:String}) -> {
			var player:PlayerState = state.players.get(client.sessionId);
			if (player == null) { return; }
			// frozen managed client-side
			broadcast("cast_start", {sessionId: client.sessionId, dir: data.dir}, {except: client});
		});

		onMessage("cast_release", (client:Client, data:{power:Float, dir:String, targetX:Float, targetY:Float}) -> {
			var player:PlayerState = state.players.get(client.sessionId);
			if (player == null) { return; }
			// server validates and broadcasts — existing cast_line message for backward compat
			broadcast("cast_line", {
				sessionId: client.sessionId,
				x: data.targetX,
				y: data.targetY,
				dir: data.dir
			}, {except: client});
		});

		onMessage("cast_retract", (client:Client, _) -> {
			var player:PlayerState = state.players.get(client.sessionId);
			if (player == null) { return; }
			// frozen managed client-side
			// line_pulled is already handled below for backward compat
		});

		onMessage("cast_cancel", (client:Client, _) -> {
			var player:PlayerState = state.players.get(client.sessionId);
			if (player == null) { return; }
			// frozen managed client-side
		});

		// Ground fish: player inventory full, server computes landing position
		onMessage("ground_fish_drop", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: ground_fish_drop at (${data.playerX}, ${data.playerY})');
			var px:Float = data.playerX;
			var py:Float = data.playerY;
			// compute random landing offset (same logic as GroundFishGroup.addFish)
			var angle = Math.random() * Math.PI * 2;
			var dist = 16 + Math.random() * 16;
			var landX = px + Math.cos(angle) * dist;
			var landY = py + Math.sin(angle) * dist;
			// broadcast to ALL clients (including sender) so everyone uses the same position
			broadcast("ground_fish_spawn", {
				startX: px,
				startY: py,
				landX: landX,
				landY: landY,
				fishType: data.fishType,
				lengthCm: data.lengthCm
			});
		});

		onMessage("ground_fish_pickup", (client:Client, data:Dynamic) -> {
			broadcast("ground_fish_pickup", data, {except: client});
		});

		onMessage("player_name_changed", (client:Client, data:{
			name:String,
		}) -> {
			var player:PlayerState = state.players.get(client.sessionId);
			if (player != null) {
				player.name = data.name;
			}
		});

		// Bobber position messages for server-side fish attraction
		onMessage("bobber_landed", (client:Client, data:{x:Float, y:Float}) -> {
			bobberPositions.set(client.sessionId, {x: data.x, y: data.y});
		});

		onMessage("bobber_retracted", (client:Client, _) -> {
			bobberPositions.remove(client.sessionId);
		});

		// sent when a player throws a rock
		onMessage("throw_rock", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "throw_rock": targetX=${data.targetX} targetY=${data.targetY} big=${data.big} dir=${data.dir}');
			broadcast("throw_rock", {
				sessionId: client.sessionId,
				targetX: data.targetX,
				targetY: data.targetY,
				big: data.big,
				dir: data.dir
			}, {except: client});
		});

		// sent when a rock lands in water — scare fish and broadcast
		onMessage("rock_splash", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "rock_splash": x=${data.x} y=${data.y} big=${data.big}');
			broadcast("rock_splash", {x: data.x, y: data.y, big: data.big}, {except: client});
			scareFish(data.x, data.y);
		});

		// sent when a player changes their skin selection in the lobby
		onMessage("skin_changed", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "skin_changed" message: skinIndex=${data.skinIndex}');
			var player:PlayerState = state.players.get(client.sessionId);
			if (player != null) {
				player.skinIndex = data.skinIndex;
			}
		});

		// sent when a player's score changes
		onMessage("score_update", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "score_update" message: score=${data.score}');
			var player:PlayerState = state.players.get(client.sessionId);
			if (player != null) {
				player.score = data.score;
			}
		});

		// sent by the host to broadcast all world item positions
		onMessage("world_items", (client:Client, data:Dynamic) -> {
			if (client.sessionId != state.hostSessionId) {
				return;
			}
			trace('${client.sessionId}: sent "world_items"');
			broadcast("world_items", data, {except: client});
		});

		// sent when a player picks up a world item (rock, waders, pepper)
		onMessage("item_pickup", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "item_pickup": itemType=${data.itemType} index=${data.index}');
			broadcast("item_pickup", {sessionId: client.sessionId, itemType: data.itemType, index: data.index}, {except: client});
		});

		// sent when a player bursts a weed
		onMessage("weed_burst", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "weed_burst": index=${data.index}');
			broadcast("weed_burst", {sessionId: client.sessionId, index: data.index}, {except: client});
		});

		// sent when a player walks into a bush
		onMessage("bush_rustle", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "bush_rustle": index=${data.index}');
			broadcast("bush_rustle", {index: data.index, dirX: data.dirX, dirY: data.dirY}, {except: client});
		});

		// sent when a player kills a worm
		onMessage("worm_killed", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "worm_killed"');
			broadcast("worm_killed", {sessionId: client.sessionId}, {except: client});
		});

		// sent when a player activates or deactivates hot pepper mode
		onMessage("hot_pepper", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "hot_pepper": isStart=${data.isStart}');
			broadcast("hot_pepper", {sessionId: client.sessionId, isStart: data.isStart}, {except: client});
		});

		// host periodically broadcasts the timer state so non-host clients can sync
		onMessage("timer_sync", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "timer_sync": runTimeSec=${data.runTimeSec} totalSec=${data.totalSec}');
			broadcast("timer_sync", {runTimeSec: data.runTimeSec, totalSec: data.totalSec}, {except: client});
		});

		// sent when a player sells a fish — broadcast to other clients so they can track it
		onMessage("fish_sold", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "fish_sold" message: fishType=${data.fishType} lengthCm=${data.lengthCm} value=${data.value}');
			broadcast("fish_sold", {
				sessionId: client.sessionId,
				fishType: data.fishType,
				lengthCm: data.lengthCm,
				value: data.value,
			}, {except: client});
		});

		// sent when a player casts their line
		onMessage("cast_line", (client, data) -> {
			trace('${client.sessionId}: sent "cast_line" message: ${Json.stringify(data)}');
			broadcast("cast_line", {
				sessionId: client.sessionId,
				x: data.x,
				y: data.y,
				dir: data.dir
			}, {except: client});
		});

		// sent when a player catches a fish; catcherSessionId may differ from client.sessionId
		// because the host reports catches on behalf of any player whose bobber a fish swam into
		onMessage("fish_caught", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "fish_caught": fishId=${data.fishId} catcher=${data.catcherSessionId} fishType=${data.fishType}');
			broadcast("fish_caught", {sessionId: data.catcherSessionId, fishId: data.fishId, fishType: data.fishType});
		});

		// sent when a player pulls in their line
		onMessage("line_pulled", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "line_pulled" message');
			broadcast("line_pulled", {sessionId: client.sessionId});
		});

		// sent by the host to assign random spawn positions for all players
		onMessage("spawn_locations", (client:Client, data:Dynamic) -> {
			if (client.sessionId != state.hostSessionId) {
				return;
			}
			trace('${client.sessionId}: sent "spawn_locations"');
			broadcast("spawn_locations", data, {except: client});
		});

		// sent by the host to establish shared world layout (bushes + shop)
		onMessage("world_setup", (client:Client, data:Dynamic) -> {
			if (client.sessionId != state.hostSessionId) {
				return;
			}
			var bushArray:Array<Dynamic> = data.bushes;
			for (i => bush in bushArray) {
				state.bushes.set(Std.string(i), new BushState(bush.x, bush.y));
			}
			state.shopX = data.shopX;
			state.shopY = data.shopY;
			state.shopReady = true;
		});

		onMessage("round_update", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "round_update" message: ${Json.stringify(data)}');
			if (data != null) {
				var newData = new RoundState();
				newData.status = state.round.status;
				newData.currentRound = state.round.currentRound;
				newData.totalRounds = state.round.totalRounds;

				if (data.status != null) {
					trace('update round status: ${state.round.status} -> ${data.status}');
					newData.status = data.status;

					for (sId => pp in state.players) {
						pp.ready = false;
					}
				}
				if (data.currentRound != null) {
					newData.currentRound = data.currentRound;
				}
				if (data.totalRounds != null) {
					newData.totalRounds = data.totalRounds;
				}
				state.round = newData;
			}
		});

		onMessage("kick", (client:Client, data:{targetSessionId:String}) -> {
			trace('${client.sessionId}: wants to kick ${data.targetSessionId}');
			var target = clients.getById(data.targetSessionId);
			if (target == null) {
				return;
			}

			// Remove the player from state immediately so other clients see it right away.
			// onLeave will also fire after the WebSocket closes but will safely no-op.
			state.players.delete(data.targetSessionId);

			// Rotate host if the kicked player was the host
			if (data.targetSessionId == state.hostSessionId) {
				var remaining = [];
				for (sId => _ in state.players) {
					remaining.push(sId);
				}
				if (remaining.length > 0) {
					state.hostSessionId = remaining[Std.random(remaining.length)];
					trace('host changed ${data.targetSessionId} -> ${state.hostSessionId}');
				} else {
					disconnect();
					return;
				}
			}

			// Tell all remaining clients explicitly so they can update their player lists
			// without relying on the schema patch cycle or background-thread schema callbacks
			broadcast("player_kicked", {sessionId: data.targetSessionId}, {except: target});

			// Notify the kicked client and disconnect them via standard Colyseus method
			target.send("kicked", {});
			target.leave(CloseCode.CONSENTED);
		});

		onMessage("player_ready", (client:Client, _) -> {
			if (state.round.status != RoundState.STATUS_LOBBY
				&& state.round.status != RoundState.STATUS_PRE_ROUND
				&& state.round.status != RoundState.STATUS_POST_ROUND) {
				return;
			}

			var player:PlayerState = state.players.get(client.sessionId);
			if (player != null) {
				player.ready = true;
			}

			var ready = true;
			for (sId => pp in state.players) {
				if (!pp.ready) {
					ready = false;
					break;
				}
			}
			if (ready) {
				broadcast("players_ready", true);
				for (sId => pp in state.players) {
					pp.ready = false;
				}

				if (state.round.status == RoundState.STATUS_LOBBY) {
					// after we all ready up in the lobby, lock the room so no one can join
					lock();
				}
			}
		});
	}

	override public function onJoin(client:Client, ?options:Dynamic):EitherType<Void, Promise<Dynamic>> {
		trace('player joined: ${client.sessionId}');
		state.players.set(client.sessionId, new PlayerState());
		state.inputQueue.set(client.sessionId, []);
		// Set player hitbox dimensions for simulation
		var ps = state.players.get(client.sessionId);
		ps.speed = 100;
		ps.width = 16;
		ps.height = 8;

		// Set host
		if (state.hostSessionId == null || state.hostSessionId == "") {
			state.hostSessionId = client.sessionId;
			trace('host set ${client.sessionId}');
		}

		return null;
	}

	override public function onLeave(client:Client, ?code:CloseCode):EitherType<Void, Promise<Dynamic>> {
		trace('player left: ${client.sessionId}');
		trace('successful clear: ${state.players.delete(client.sessionId)}');
		state.inputQueue.remove(client.sessionId);

		// Remove bobber position for leaving player
		bobberPositions.remove(client.sessionId);

		// Clear/rotate host
		if (client.sessionId == state.hostSessionId) {
			if (state.players.size <= 0) {
				state.hostSessionId = null;
			} else {
				var sIds = [];
				for (sId => _ in state.players) {
					sIds.push(sId);
				}
				var sIdx = Std.random(state.players.size);
				state.hostSessionId = sIds[sIdx];
			};

			trace('host changed ${client.sessionId} -> ${state.hostSessionId}');
			if (state.hostSessionId == null) {
				// after the last person leaves a room, just close it down
				trace('disconnect room: ${roomId}:${roomName}');
				disconnect();
			}
		}

		return null;
	}

	/** Flood-fill the FishSpawner IntGrid layer (value=1 = water) to find water bodies,
	    then spawn fish into each body that has a FishSpawner entity. */
	function spawnFish() {
		// Access the FishSpawner IntGrid layer from the LDTK level
		// Use the CollisionMap to identify water tiles (FLAG_SWIMMABLE)
		var col = state.collision;
		var w = col.cols;
		var h = col.rows;
		var grid = col.tileSize;

		var visited = new Array<Bool>();
		visited.resize(w * h);
		for (i in 0...visited.length) {
			visited[i] = false;
		}

		// Collect FishSpawner entities keyed by their grid index
		var spawnerCounts = new Map<Int, Int>();
		var rawObjects:Dynamic = Reflect.getProperty(ldtkRaw, "l_Objects");
		var allFishSpawner:Array<Dynamic> = Reflect.getProperty(rawObjects, "all_FishSpawner");
		if (allFishSpawner != null) {
			for (spawner in allFishSpawner) {
				var cx:Int = spawner.cx;
				var cy:Int = spawner.cy;
				var idx = cx + cy * w;
				var numFish:Int = spawner.f_numFish;
				spawnerCounts.set(idx, numFish);
			}
		}

		// Count swimmable tiles for debug
		var swimmableCount = 0;
		for (row in 0...h) {
			for (c in 0...w) {
				if (col.isSwimmableAt(c, row)) {
					swimmableCount++;
				}
			}
		}
		trace('spawnFish: found ${Lambda.count(spawnerCounts)} FishSpawner entities, grid ${w}x${h}, swimmable tiles: $swimmableCount');

		// Flood-fill to find connected groups of swimmable tiles
		var bodyIndex = 0;
		for (sy in 0...h) {
			for (sx in 0...w) {
				var startIdx = sx + sy * w;
				if (visited[startIdx] || !col.isSwimmableAt(sx, sy)) {
					continue;
				}

				var body = new Array<Int>();
				var stack = [startIdx];
				while (stack.length > 0) {
					var idx = stack.pop();
					if (idx < 0 || idx >= w * h || visited[idx]) {
						continue;
					}
					var cx = idx % w;
					var cy = Std.int(idx / w);
					if (!col.isSwimmableAt(cx, cy)) {
						continue;
					}
					visited[idx] = true;
					body.push(idx);
					if (cx > 0) { stack.push(idx - 1); }
					if (cx < w - 1) { stack.push(idx + 1); }
					if (cy > 0) { stack.push(idx - w); }
					if (cy < h - 1) { stack.push(idx + w); }
				}

				// Find the FishSpawner entity in this body to get numFish
				var numFish = 0;
				for (idx in body) {
					if (spawnerCounts.exists(idx)) {
						numFish = spawnerCounts.get(idx);
						break;
					}
				}

				if (numFish <= 0) {
					continue;
				}

				// Build shared water tile pixel positions for this body
				var bodyTiles = new Array<{x:Float, y:Float}>();
				for (idx in body) {
					var cx = idx % w;
					var cy = Std.int(idx / w);
					bodyTiles.push({x: cx * grid + 2.0, y: cy * grid + 2.0});
				}

				var bIdx = waterBodies.length;
				waterBodies.push(bodyTiles);

				for (_ in 0...numFish) {
					var fid = Std.string(nextFishID++);
					var tileIdx = Std.int(Math.random() * bodyTiles.length);
					var tile = bodyTiles[tileIdx];
					var ftype = Std.int(Math.random() * NUM_FISH_TYPES);
					var fish = new FishState(tile.x, tile.y, ftype);
					fish.bodyIndex = bIdx;
					state.fish.set(fid, fish);
				}

				bodyIndex++;
			}
		}

		trace('spawnFish: spawned fish in ${bodyIndex} water bodies, total fish: ${nextFishID - 1}');
	}

	var fishTraceCounter:Int;

	/** Update all server-owned fish AI. Called from fixedTick. */
	function updateFish(t:Float) {
		if (fishTraceCounter == null) { fishTraceCounter = 0; }
		fishTraceCounter++;
		// Collect fish IDs and states into arrays for pairwise separation checks
		var fishIds = new Array<String>();
		var fishStates = new Array<FishState>();
		for (id => fish in state.fish) {
			fishIds.push(id);
			fishStates.push(fish);
		}
		if (fishTraceCounter % 100 == 1) {
			for (i in 0...fishIds.length) {
				var f = fishStates[i];
				trace('[FISH] ${fishIds[i]} pos=(${Std.int(f.x)},${Std.int(f.y)}) vel=(${Std.int(f.velX)},${Std.int(f.velY)}) alive=${f.alive} pause=${Std.int(f.pauseTimer * 10) / 10} retarget=${Std.int(f.retargetTimer * 10) / 10}');
			}
		}

		for (i in 0...fishIds.length) {
			var fish = fishStates[i];
			var fid = fishIds[i];

			// Handle scared fish (fading out and fleeing)
			if (fish.scaredTimer > 0) {
				fish.scaredTimer -= t;
				// Move along scare velocity
				fish.x += fish.velX * t;
				fish.y += fish.velY * t;
				if (fish.scaredTimer <= 0) {
					fish.alive = false;
					fish.velX = 0;
					fish.velY = 0;
					fish.respawnTimer = 5.5;
				}
				continue;
			}

			// Handle dead fish waiting to respawn
			if (!fish.alive) {
				if (fish.respawnTimer > 0) {
					fish.respawnTimer -= t;
					if (fish.respawnTimer <= 0) {
						// Respawn at random water tile in this body
						var bodyTiles = waterBodies[fish.bodyIndex];
						if (bodyTiles != null && bodyTiles.length > 0) {
							var tileIdx = Std.int(Math.random() * bodyTiles.length);
							var tile = bodyTiles[tileIdx];
							fish.x = tile.x + Math.random() * 12;
							fish.y = tile.y + Math.random() * 12;
							fish.velX = 0;
							fish.velY = 0;
							fish.alive = true;
							fish.attracted = false;
							fish.pauseTimer = 0;
							fish.retargetTimer = Math.random() + 2.0;
							pickFishTarget(fish);
						}
					}
				}
				continue;
			}

			// Handle paused fish
			if (fish.pauseTimer > 0) {
				fish.pauseTimer -= t;
				continue;
			}

			// Check bobber interactions — attraction and catch
			var closestDist = 1e20;
			var closestSid:String = null;
			var closestBX:Float = 0;
			var closestBY:Float = 0;
			var hasBobbers = false;

			for (sid => bpos in bobberPositions) {
				hasBobbers = true;
				var dx = bpos.x - fish.x;
				var dy = bpos.y - fish.y;
				var dist = Math.sqrt(dx * dx + dy * dy);
				if (dist < closestDist) {
					closestDist = dist;
					closestSid = sid;
					closestBX = bpos.x;
					closestBY = bpos.y;
				}
			}

			// If fish was attracted but bobber is gone (retracted), flee
			if (fish.attracted && !hasBobbers) {
				fish.attracted = false;
				fleeFromFish(fish, fish.x + fish.velX, fish.y + fish.velY);
				continue;
			}
			if (fish.attracted && closestDist > FISH_ATTRACT_DIST) {
				fish.attracted = false;
				fleeFromFish(fish, closestBX, closestBY);
				continue;
			}

			if (hasBobbers && closestDist < FISH_CATCH_DIST) {
				// Fish caught!
				fish.alive = false;
				fish.velX = 0;
				fish.velY = 0;
				fish.attracted = false;
				fish.respawnTimer = 3.0;
				// Broadcast fish_caught to all clients
				broadcast("fish_caught", {sessionId: closestSid, fishId: fid, fishType: fish.fishType});
				continue;
			}

			if (hasBobbers && closestDist < FISH_ATTRACT_DIST) {
				// Attract toward closest bobber
				fish.attracted = true;
				fish.pauseTimer = 0;
				var dx = closestBX - fish.x;
				var dy = closestBY - fish.y;
				if (closestDist > 0.1) {
					fish.velX = (dx / closestDist) * FISH_ATTRACT_SPEED;
					fish.velY = (dy / closestDist) * FISH_ATTRACT_SPEED;
				}
				fish.x += fish.velX * t;
				fish.y += fish.velY * t;
				continue;
			}

			// Normal wandering AI
			fish.retargetTimer -= t;
			if (fish.retargetTimer <= 0) {
				pickFishTarget(fish);
			}

			var dx = fish.targetX - fish.x;
			var dy = fish.targetY - fish.y;
			var dist = Math.sqrt(dx * dx + dy * dy);

			if (dist < FISH_ARRIVE_DIST) {
				fish.velX = 0;
				fish.velY = 0;
				fish.pauseTimer = 1.0 + Math.random() * 2.0;
				pickFishTarget(fish);
			} else {
				fish.velX = (dx / dist) * FISH_SPEED;
				fish.velY = (dy / dist) * FISH_SPEED;
			}

			fish.x += fish.velX * t;
			fish.y += fish.velY * t;
		}

		// Separation: check pairs of alive fish
		for (i in 0...fishStates.length) {
			var a = fishStates[i];
			if (!a.alive) { continue; }
			for (j in (i + 1)...fishStates.length) {
				var b = fishStates[j];
				if (!b.alive) { continue; }
				var dx = a.x - b.x;
				var dy = a.y - b.y;
				if (dx * dx + dy * dy < FISH_SEPARATION_DIST * FISH_SEPARATION_DIST) {
					fleeFromFish(a, b.x, b.y);
					fleeFromFish(b, a.x, a.y);
				}
			}
		}
	}

	/** Pick a new random target tile in this fish's water body. */
	function pickFishTarget(fish:FishState) {
		var bodyTiles = waterBodies[fish.bodyIndex];
		if (bodyTiles == null || bodyTiles.length == 0) {
			return;
		}
		var tileIdx = Std.int(Math.random() * bodyTiles.length);
		var tile = bodyTiles[tileIdx];
		fish.targetX = tile.x + Math.random() * 12;
		fish.targetY = tile.y + Math.random() * 12;
		fish.retargetTimer = 2.0 + Math.random();
	}

	/** Make a fish flee from a position — pick the farthest water tile in the away direction. */
	function fleeFromFish(fish:FishState, fromX:Float, fromY:Float) {
		if (fish.attracted) { return; }

		var awayX = fish.x - fromX;
		var awayY = fish.y - fromY;
		var len = Math.sqrt(awayX * awayX + awayY * awayY);
		if (len < 0.01) {
			awayX = Math.random() * 2 - 1;
			awayY = Math.random() * 2 - 1;
			len = Math.sqrt(awayX * awayX + awayY * awayY);
		}
		awayX /= len;
		awayY /= len;

		// Pick the farthest water tile in the away direction
		var bodyTiles = waterBodies[fish.bodyIndex];
		if (bodyTiles == null || bodyTiles.length == 0) { return; }

		var bestDot:Float = -999999;
		var bestTile:{x:Float, y:Float} = null;
		for (tile in bodyTiles) {
			var dx = tile.x - fish.x;
			var dy = tile.y - fish.y;
			var dot = dx * awayX + dy * awayY;
			if (dot > bestDot) {
				bestDot = dot;
				bestTile = tile;
			}
		}

		if (bestTile != null) {
			fish.targetX = bestTile.x + Math.random() * 12;
			fish.targetY = bestTile.y + Math.random() * 12;
			fish.retargetTimer = 2.0 + Math.random();

			var fdx = fish.targetX - fish.x;
			var fdy = fish.targetY - fish.y;
			var fdist = Math.sqrt(fdx * fdx + fdy * fdy);
			if (fdist > 0.1) {
				fish.velX = (fdx / fdist) * FISH_SPEED;
				fish.velY = (fdy / fdist) * FISH_SPEED;
			}
		}

		fish.pauseTimer = 0;
	}

	/** Scare all fish within radius of a splash point. */
	function scareFish(splashX:Float, splashY:Float, radius:Float = 80) {
		for (id => fish in state.fish) {
			if (!fish.alive) { continue; }
			var dx = fish.x - splashX;
			var dy = fish.y - splashY;
			if (dx * dx + dy * dy < radius * radius) {
				// flee from splash
				fish.scaredTimer = 0.5;
				fish.attracted = false;
				// set velocity away from splash
				var len = Math.sqrt(dx * dx + dy * dy);
				if (len > 0.01) {
					fish.velX = (dx / len) * FISH_SPEED * 1.5;
					fish.velY = (dy / len) * FISH_SPEED * 1.5;
				}
			}
		}
	}

	/** Update server-owned seagulls. Called from fixedTick. */
	function updateSeagulls(t:Float) {
		var col = state.collision;
		var worldWidth:Float = col.cols * col.tileSize;
		var worldHeight:Float = col.rows * col.tileSize;

		// Spawn timer
		seagullSpawnTimer -= t;
		if (seagullSpawnTimer <= 0) {
			seagullSpawnTimer = 2.0 + Math.random() * 4.0;
			var goingRight = Math.random() > 0.5;
			var speed = 40 + Math.random() * 30; // 40-70
			var spawnX:Float = goingRight ? -32.0 : worldWidth + 32;
			// spawn in upper portion so shadows land in playable area
			var spawnY:Float = -80 + Math.random() * (worldHeight * 0.5 + 80);
			var alt:Float = Math.random() * 40;
			var sid = nextSeagullId++;
			var gull = {
				id: sid,
				x: spawnX,
				y: spawnY,
				velX: goingRight ? speed : -speed,
				velY: 0.0,
				goingRight: goingRight,
				poopTimer: 8.0 + Math.random() * 8.0,
				altitude: alt,
				driftTimer: 0.5 + Math.random() * 1.0,
				driftVelY: 0.0
			};
			seagulls.push(gull);
			broadcast("seagull_spawn", {
				id: sid,
				x: spawnX,
				y: spawnY,
				velX: gull.velX,
				velY: gull.velY,
				altitude: alt
			});
		}

		// Update each seagull
		var i = seagulls.length - 1;
		while (i >= 0) {
			var gull = seagulls[i];

			// Drift (vertical wobble)
			gull.driftTimer -= t;
			if (gull.driftTimer <= 0) {
				gull.driftTimer = 0.5 + Math.random() * 1.0;
				gull.driftVelY = (Math.random() * 2 - 1) * 10; // DRIFT_SPEED = 10
			}
			gull.velY = gull.driftVelY;

			// Move
			gull.x += gull.velX * t;
			gull.y += gull.velY * t;

			// Poop timer
			gull.poopTimer -= t;
			if (gull.poopTimer <= 0) {
				gull.poopTimer = 8.0 + Math.random() * 8.0;

				// Compute where poop lands
				// altitude factor: how high the bird is relative to world
				var altFactor = Math.max(0, Math.min(1, (worldHeight - gull.y) / worldHeight));
				var shadowOffsetY = 80 + altFactor * 40; // SHADOW_BASE_OFFSET + altitude*40
				var landX = gull.x + 12; // roughly center of 24px sprite
				var landY = gull.y + shadowOffsetY;

				// Check if landing position is in water
				var tileX = Std.int(landX / col.tileSize);
				var tileY = Std.int(landY / col.tileSize);
				var hitWater = col.isSwimmableAt(tileX, tileY);

				if (hitWater) {
					scareFish(landX, landY, 30);
				}

				broadcast("seagull_poop", {
					id: gull.id,
					x: gull.x + 12,
					y: gull.y + 12,
					fallDist: shadowOffsetY - 12,
					birdVelX: gull.velX,
					hitWater: hitWater
				});
			}

			// Off-screen despawn
			if ((gull.goingRight && gull.x > worldWidth + 100) || (!gull.goingRight && gull.x < -100)) {
				broadcast("seagull_despawn", {id: gull.id});
				seagulls.splice(i, 1);
			}

			i--;
		}
	}

	function serverUpdate(delta:Float) {
		elapsedTime += delta / 1000;
		var fixedStep = Simulation.FIXED_STEP;
		while (elapsedTime >= fixedStep) {
			elapsedTime -= fixedStep;
			fixedTick(fixedStep);
		}
	}

	function fixedTick(t:Float) {
		for (id => p in state.players) {
			var queue = state.inputQueue.get(id);
			if (queue == null || queue.length == 0) {
				p.velocityX = 0;
				p.velocityY = 0;
				continue;
			}
			for (inp in queue) {
				simulation.tickPlayer(p, [inp], inp.elapsed);
			}
			queue.splice(0, queue.length);
		}

		// Update server-side fish AI
		updateFish(t);

		// Update server-side seagulls
		updateSeagulls(t);
	}
}
