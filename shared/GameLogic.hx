package;

import schema.GameState;
import schema.GameState.P_Input;
import schema.BushState;
import schema.FishState;
import schema.PlayerState;
import schema.RoundState;

/**
 * Pure game simulation logic — no Colyseus, no Flixel, no platform imports.
 * Runs identically on the Node.js server (via GameRoom) and embedded in the
 * HL client (via LocalRoom). Uses callbacks for I/O.
**/
class GameLogic {
	// Callbacks — set by the host (GameRoom or LocalRoom)
	public var broadcast:(topic:String, data:Dynamic) -> Void;
	public var sendToClient:(clientId:String, topic:String, data:Dynamic) -> Void;
	public var onBushAdded:(x:Float, y:Float) -> Void;
	public var onFishAdded:(id:String, fish:FishState) -> Void;

	public var state:Dynamic;
	public var simulation:Simulation;

	// Fish AI data
	var waterBodies:Array<Array<{x:Float, y:Float}>>;
	var bobberPositions:Map<String, {x:Float, y:Float}>;
	var hotModePlayers:Map<String, Bool>;
	var wadersPlayers:Map<String, Bool>;
	var bushRects:Array<{x:Float, y:Float, w:Float, h:Float}>;
	var nextFishID:Int;

	// Worm spawning data
	var wormTimer:Float;
	var nextWormId:Int;

	// Round timer
	public var roundTimerSec:Float;
	public var roundDurationSec:Float;
	var timerSyncCooldown:Float;
	public var gameplayStarted:Bool;

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
	public var windAngle:Float;
	public var clouds:Array<{id:Int, x:Float, y:Float, velX:Float, velY:Float, scale:Float}>;

	// World data caches
	public var cachedWorldItems:Dynamic;
	public var cachedSpawnLocations:Dynamic;

	// LDTK raw data for spawn point lookup
	var ldtkRaw:Dynamic;

	static var FISH_SPEED:Float = 20;
	static var FISH_ATTRACT_SPEED:Float = 40;
	static var FISH_ARRIVE_DIST:Float = 2;
	static var FISH_ATTRACT_DIST:Float = 32;
	static var FISH_CATCH_DIST:Float = 4;
	static var FISH_SEPARATION_DIST:Float = 20;
	static var NUM_FISH_TYPES:Int = 12;

	public function new() {
		// defaults — overridden by init()
		broadcast = (_, _) -> {};
		sendToClient = (_, _, _) -> {};
		onBushAdded = (_, _) -> {};
		onFishAdded = (_, _) -> {};
	}

	/**
	 * Initialize game state from level data.
	 * @param collision — the collision map built from LDTK
	 * @param raw — the raw LDTK level data (Dynamic) for spawn point / fish spawner lookup
	 */
	public function init(collision:CollisionMap, raw:Dynamic) {
		state = new GameState();
		state.collision = collision;
		state.inputQueue = new Map();
		simulation = new Simulation(collision);
		ldtkRaw = raw;

		waterBodies = [];
		bobberPositions = new Map();
		hotModePlayers = new Map();
		wadersPlayers = new Map();
		bushRects = [];
		nextFishID = 1;

		wormTimer = 999;
		nextWormId = 1;

		roundTimerSec = 0;
		roundDurationSec = 90;
		timerSyncCooldown = 5.0;
		gameplayStarted = false;

		seagulls = [];
		nextSeagullId = 1;
		seagullSpawnTimer = 999;

		windAngle = Math.random() * Math.PI * 2;
		var worldW = collision.cols * collision.tileSize;
		var worldH = collision.rows * collision.tileSize;
		clouds = [];
		for (i in 0...5) {
			var s = 1.0 + Math.random() * 2.0;
			var speed = 8 + Math.random() * 8;
			var dx = Math.cos(windAngle) * speed;
			var dy = Math.sin(windAngle) * speed;
			var cx = Math.random() * worldW;
			var cy = Math.random() * worldH;
			clouds.push({id: i, x: cx, y: cy, velX: dx, velY: dy, scale: s});
		}
	}

	// --- Player lifecycle ---

	public function addPlayer(sessionId:String) {
		MapHelper.set(state.players,sessionId, new PlayerState());
		state.inputQueue.set(sessionId, []);
		var ps = MapHelper.get(state.players,sessionId);
		ps.speed = 100;
		ps.width = 16;
		ps.height = 8;
	}

	public function removePlayer(sessionId:String) {
		MapHelper.delete(state.players,sessionId);
		state.inputQueue.remove(sessionId);
		bobberPositions.remove(sessionId);
		hotModePlayers.remove(sessionId);
		wadersPlayers.remove(sessionId);
	}

	// --- Message handling ---

	public function handleMessage(clientId:String, topic:String, data:Dynamic) {
		switch (topic) {
			case "player_input":
				if (!MapHelper.has(state.players,clientId)) { return; }
				if (!state.inputQueue.exists(clientId)) {
					state.inputQueue.set(clientId, []);
				}
				if (data == null) { return; }
				for (input in (data : Array<P_Input>)) {
					state.inputQueue.get(clientId).push(input);
				}

			case "start_gameplay":
				if (!gameplayStarted) {
					resetRoundState();
					spawnWorldItems();
					gameplayStarted = true;
					roundTimerSec = 0;
				}
				if (cachedWorldItems != null) {
					sendToClient(clientId, "world_items", cachedWorldItems);
				}
				if (cachedSpawnLocations != null) {
					sendToClient(clientId, "spawn_locations", cachedSpawnLocations);
				}
				sendToClient(clientId, "timer_sync", {runTimeSec: roundTimerSec, totalSec: roundDurationSec});
				sendToClient(clientId, "cloud_sync", {angle: windAngle, clouds: clouds});
				for (gull in seagulls) {
					sendToClient(clientId, "seagull_spawn", {
						id: gull.id, x: gull.x, y: gull.y,
						velX: gull.velX, velY: gull.velY, altitude: gull.altitude
					});
				}

			case "cast_start":
				broadcast("cast_start", {sessionId: clientId, dir: data.dir});
			case "cast_release":
				broadcast("cast_line", {sessionId: clientId, x: data.targetX, y: data.targetY, dir: data.dir});
			case "cast_retract" | "cast_cancel":
				// no-op — frozen managed client-side

			case "ground_fish_drop":
				var px:Float = data.playerX;
				var py:Float = data.playerY;
				var angle = Math.random() * Math.PI * 2;
				var dist = 16 + Math.random() * 16;
				broadcast("ground_fish_spawn", {
					startX: px, startY: py,
					landX: px + Math.cos(angle) * dist,
					landY: py + Math.sin(angle) * dist,
					fishType: data.fishType, lengthCm: data.lengthCm
				});
			case "ground_fish_pickup":
				broadcast("ground_fish_pickup", data);

			case "player_name_changed":
				var ps = MapHelper.get(state.players,clientId);
				if (ps != null) { ps.name = data.name; }

			case "bobber_landed":
				bobberPositions.set(clientId, {x: data.x, y: data.y});
			case "bobber_retracted":
				bobberPositions.remove(clientId);

			case "throw_rock":
				broadcast("throw_rock", {sessionId: clientId, targetX: data.targetX, targetY: data.targetY, big: data.big, dir: data.dir});
			case "rock_splash":
				broadcast("rock_splash", {x: data.x, y: data.y, big: data.big});
				scareFish(data.x, data.y);

			case "skin_changed":
				var ps = MapHelper.get(state.players,clientId);
				if (ps != null) { ps.skinIndex = data.skinIndex; }
			case "score_update":
				var ps = MapHelper.get(state.players,clientId);
				if (ps != null) { ps.score = data.score; }

			case "item_pickup":
				if (data.itemType == "waders") {
					wadersPlayers.set(clientId, true);
				} else if (data.itemType == "waders_remove") {
					wadersPlayers.remove(clientId);
				}
				broadcast("item_pickup", {sessionId: clientId, itemType: data.itemType, index: data.index});

			case "weed_burst":
				broadcast("weed_burst", {sessionId: clientId, index: data.index});
			case "player_drown":
				broadcast("player_drown", {sessionId: clientId, x: data.x, y: data.y});
			case "bush_rustle":
				broadcast("bush_rustle", {index: data.index, dirX: data.dirX, dirY: data.dirY});
			case "bush_ignite":
				broadcast("bush_ignite", {index: data.index});
			case "bush_dead":
				var idx:Int = data.index;
				if (idx >= 0 && idx < bushRects.length) {
					bushRects[idx] = {x: 0.0, y: 0.0, w: 0.0, h: 0.0};
					simulation.entityRects = bushRects;
				}
			case "weed_ignite":
				broadcast("weed_ignite", {index: data.index});
			case "worm_killed":
				broadcast("worm_killed", {sessionId: clientId, id: data.id});

			case "hot_pepper":
				var isStart:Bool = data.isStart;
				hotModePlayers.set(clientId, isStart);
				var ps = MapHelper.get(state.players,clientId);
				if (ps != null) { ps.speed = isStart ? 150 : 100; }
				broadcast("hot_pepper", {sessionId: clientId, isStart: isStart});

			case "debug_end_round":
				if (gameplayStarted) {
					broadcast("round_time_up", {});
					gameplayStarted = false;
					if (state.round.status == RoundState.STATUS_ACTIVE) {
						var newData = new RoundState();
						newData.status = RoundState.STATUS_POST_ROUND;
						newData.currentRound = state.round.currentRound;
						newData.totalRounds = state.round.totalRounds;
						state.round = newData;
						for (sId => pp in state.players) {
							pp.ready = false;
						}
					}
				}

			case "fish_sold":
				broadcast("fish_sold", {sessionId: clientId, fishType: data.fishType, lengthCm: data.lengthCm, value: data.value});
			case "cast_line":
				broadcast("cast_line", {sessionId: clientId, x: data.x, y: data.y, dir: data.dir});
			case "line_pulled":
				broadcast("line_pulled", {sessionId: clientId});

			case "round_update":
				if (data == null) { return; }
				var newStatus = data.status != null ? data.status : state.round.status;
				var newRound = data.currentRound != null ? (data.currentRound : Int) : state.round.currentRound;
				var newTotal = data.totalRounds != null ? (data.totalRounds : Int) : state.round.totalRounds;
				if (newStatus == state.round.status && newRound == state.round.currentRound && newTotal == state.round.totalRounds) {
					return;
				}
				var newData = new RoundState();
				newData.status = newStatus;
				newData.currentRound = newRound;
				newData.totalRounds = newTotal;
				if (data.status != null) {
					for (sId => pp in state.players) {
						pp.ready = false;
					}
				}
				state.round = newData;

			case "player_ready":
				if (state.round.status != RoundState.STATUS_LOBBY
					&& state.round.status != RoundState.STATUS_PRE_ROUND
					&& state.round.status != RoundState.STATUS_POST_ROUND) {
					return;
				}
				var ps = MapHelper.get(state.players,clientId);
				if (ps != null) { ps.ready = true; }
				var ready = true;
				for (sId => pp in state.players) {
					if (!pp.ready) { ready = false; break; }
				}
				if (ready) {
					broadcast("players_ready", true);
					for (sId => pp in state.players) {
						pp.ready = false;
					}
				}
		}
	}

	// --- Tick ---

	public function update(deltaMs:Float) {
		var elapsed = deltaMs / 1000.0;
		var fixedStep = Simulation.FIXED_STEP;
		// accumulate time — but for simplicity just tick once per call with elapsed
		fixedTick(elapsed);
	}

	function fixedTick(t:Float) {
		for (id => p in state.players) {
			var queue = state.inputQueue.get(id);
			if (queue == null || queue.length == 0) {
				p.velocityX = 0;
				p.velocityY = 0;
				continue;
			}
			var isHot = hotModePlayers.exists(id) && hotModePlayers.get(id);
			var hasWaders = wadersPlayers.exists(id) && wadersPlayers.get(id);
			var blockFlags = if (isHot || hasWaders) CollisionMap.FLAG_SOLID else 0;
			for (inp in queue) {
				simulation.tickPlayer(p, [inp], inp.elapsed, blockFlags);
			}
			queue.splice(0, queue.length);
		}

		updateFish(t);
		updateSeagulls(t);
		updateWorms(t);

		if (gameplayStarted) {
			roundTimerSec += t;
			timerSyncCooldown -= t;
			if (timerSyncCooldown <= 0) {
				timerSyncCooldown = 5.0;
				broadcast("timer_sync", {runTimeSec: roundTimerSec, totalSec: roundDurationSec});
			}
			if (roundTimerSec >= roundDurationSec) {
				broadcast("round_time_up", {});
				gameplayStarted = false;
				if (state.round.status == RoundState.STATUS_ACTIVE) {
					var newData = new RoundState();
					newData.status = RoundState.STATUS_POST_ROUND;
					newData.currentRound = state.round.currentRound;
					newData.totalRounds = state.round.totalRounds;
					state.round = newData;
					for (sId => pp in state.players) {
						pp.ready = false;
					}
				}
			}
		}
	}

	// --- Round lifecycle ---

	public function resetRoundState() {
		var fishIds:Array<String> = [];
		for (id => _ in state.fish) { fishIds.push(id); }
		for (id in fishIds) { MapHelper.delete(state.fish,id); }
		nextFishID = 1;
		spawnFish();

		var bushIds:Array<String> = [];
		for (id => _ in state.bushes) { bushIds.push(id); }
		for (id in bushIds) { MapHelper.delete(state.bushes,id); }

		seagulls = [];
		seagullSpawnTimer = 3.0;
		wormTimer = 3.0;
		timerSyncCooldown = 5.0;
		bobberPositions = new Map();

		windAngle = Math.random() * Math.PI * 2;
		var worldW = state.collision.cols * state.collision.tileSize;
		var worldH = state.collision.rows * state.collision.tileSize;
		clouds = [];
		for (i in 0...5) {
			var s = 1.0 + Math.random() * 2.0;
			var speed = 8 + Math.random() * 8;
			var dx = Math.cos(windAngle) * speed;
			var dy = Math.sin(windAngle) * speed;
			var cx = Math.random() * worldW;
			var cy = Math.random() * worldH;
			clouds.push({id: i, x: cx, y: cy, velX: dx, velY: dy, scale: s});
		}

		cachedWorldItems = null;
		cachedSpawnLocations = null;

		for (_ => p in state.players) {
			p.score = 0;
			p.ready = false;
		}
	}

	// --- World spawning ---

	public function spawnWorldItems() {
		var col = state.collision;
		var w = col.cols;
		var h = col.rows;
		var grid = col.tileSize;

		var grassTiles = new Array<{cx:Int, cy:Int}>();
		var walkableTiles = new Array<{cx:Int, cy:Int}>();
		for (row in 0...h) {
			for (c in 0...w) {
				if (col.isGrassAt(c, row)) { grassTiles.push({cx: c, cy: row}); }
				if (col.isWalkableAt(c, row)) { walkableTiles.push({cx: c, cy: row}); }
			}
		}

		// Bushes
		var bushPositions = new Array<{x:Float, y:Float}>();
		for (_ in 0...5) {
			if (grassTiles.length == 0) { break; }
			var idx = Std.int(Math.random() * grassTiles.length);
			var tile = grassTiles[idx];
			bushPositions.push({x: tile.cx * grid + Math.random() * (grid - 8), y: tile.cy * grid + Math.random() * (grid - 8)});
		}
		bushRects = [];
		for (i in 0...bushPositions.length) {
			var bp = bushPositions[i];
			MapHelper.set(state.bushes,Std.string(i), new BushState(bp.x, bp.y));
			bushRects.push({x: bp.x + 2, y: bp.y + 2, w: 10.0, h: 2.0});
			onBushAdded(bp.x, bp.y);
		}
		simulation.entityRects = bushRects;

		// Weeds
		var weedPositions = new Array<{x:Float, y:Float}>();
		for (_ in 0...20) {
			if (walkableTiles.length == 0) { break; }
			var idx = Std.int(Math.random() * walkableTiles.length);
			var tile = walkableTiles[idx];
			weedPositions.push({x: tile.cx * grid + Math.random() * (grid - 8), y: tile.cy * grid + Math.random() * (grid - 8)});
		}

		// Rocks
		var numRocks = 3 + Std.int(Math.random() * 6);
		var rockPositions = new Array<{x:Float, y:Float, big:Bool}>();
		var hasBigRock = false;
		for (_ in 0...numRocks) {
			if (walkableTiles.length == 0) { break; }
			var idx = Std.int(Math.random() * walkableTiles.length);
			var tile = walkableTiles[idx];
			var big = Math.random() < 0.2;
			if (big) { hasBigRock = true; }
			rockPositions.push({x: tile.cx * grid + Math.random() * (grid - 8), y: tile.cy * grid + Math.random() * (grid - 8), big: big});
		}
		if (!hasBigRock && rockPositions.length > 0) { rockPositions[0].big = true; }

		// Waders
		var wadersX:Null<Float> = null;
		var wadersY:Null<Float> = null;
		if (walkableTiles.length > 0) {
			var idx = Std.int(Math.random() * walkableTiles.length);
			var tile = walkableTiles[idx];
			wadersX = tile.cx * grid + grid / 2.0;
			wadersY = tile.cy * grid + grid / 2.0;
		}

		// Pepper
		var pepperX:Null<Float> = null;
		var pepperY:Null<Float> = null;
		if (walkableTiles.length > 0) {
			var idx = Std.int(Math.random() * walkableTiles.length);
			var tile = walkableTiles[idx];
			pepperX = tile.cx * grid + grid / 2.0;
			pepperY = tile.cy * grid + grid / 2.0;
		}

		var worldData:Dynamic = {rocks: rockPositions, weeds: weedPositions};
		if (wadersX != null && wadersY != null) { worldData.wadersX = wadersX; worldData.wadersY = wadersY; }
		if (pepperX != null && pepperY != null) { worldData.pepperX = pepperX; worldData.pepperY = pepperY; }
		cachedWorldItems = worldData;

		// Spawn locations
		var rawObjects:Dynamic = Reflect.getProperty(ldtkRaw, "l_Objects");
		var allSpawn:Array<Dynamic> = Reflect.getProperty(rawObjects, "all_Spawn");
		var sx:Float = 48.0;
		var sy:Float = 48.0;
		if (allSpawn != null && allSpawn.length > 0) {
			sx = allSpawn[0].pixelX;
			sy = allSpawn[0].pixelY;
		}
		var spawnData:Dynamic = {};
		for (sId => _ in state.players) {
			Reflect.setField(spawnData, sId, {x: sx, y: sy});
			var ps = MapHelper.get(state.players,sId);
			if (ps != null) { ps.x = sx; ps.y = sy; }
		}
		cachedSpawnLocations = spawnData;
	}

	// --- Fish ---

	public function spawnFish() {
		var col = state.collision;
		var w = col.cols;
		var h = col.rows;
		var grid = col.tileSize;

		var visited = new Array<Bool>();
		visited.resize(w * h);
		for (i in 0...visited.length) { visited[i] = false; }

		var spawnerCounts = new Map<Int, Int>();
		var rawObjects:Dynamic = Reflect.getProperty(ldtkRaw, "l_Objects");
		var allFishSpawner:Array<Dynamic> = Reflect.getProperty(rawObjects, "all_FishSpawner");
		if (allFishSpawner != null) {
			for (spawner in allFishSpawner) {
				var cx:Int = spawner.cx;
				var cy:Int = spawner.cy;
				spawnerCounts.set(cx + cy * w, spawner.f_numFish);
			}
		}

		var bodyIndex = 0;
		for (sy in 0...h) {
			for (sx in 0...w) {
				var startIdx = sx + sy * w;
				if (visited[startIdx] || !col.isSwimmableAt(sx, sy)) { continue; }

				var body = new Array<Int>();
				var stack = [startIdx];
				while (stack.length > 0) {
					var idx = stack.pop();
					if (idx < 0 || idx >= w * h || visited[idx]) { continue; }
					var cx = idx % w;
					var cy = Std.int(idx / w);
					if (!col.isSwimmableAt(cx, cy)) { continue; }
					visited[idx] = true;
					body.push(idx);
					if (cx > 0) { stack.push(idx - 1); }
					if (cx < w - 1) { stack.push(idx + 1); }
					if (cy > 0) { stack.push(idx - w); }
					if (cy < h - 1) { stack.push(idx + w); }
				}

				var numFish = 0;
				for (idx in body) {
					if (spawnerCounts.exists(idx)) { numFish = spawnerCounts.get(idx); break; }
				}
				if (numFish <= 0) { continue; }

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
					MapHelper.set(state.fish,fid, fish);
					onFishAdded(fid, fish);
				}
				bodyIndex++;
			}
		}
	}

	var fishTraceCounter:Int = 0;

	function updateFish(t:Float) {
		fishTraceCounter++;
		var fishIds = new Array<String>();
		var fishStates = new Array<FishState>();
		for (id => fish in state.fish) {
			fishIds.push(id);
			fishStates.push(fish);
		}

		for (i in 0...fishIds.length) {
			var fish = fishStates[i];
			var fid = fishIds[i];

			if (fish.scaredTimer > 0) {
				fish.scaredTimer -= t;
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

			if (!fish.alive) {
				if (fish.respawnTimer > 0) {
					fish.respawnTimer -= t;
					if (fish.respawnTimer <= 0) {
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

			if (fish.pauseTimer > 0) {
				fish.pauseTimer -= t;
				continue;
			}

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
				fish.alive = false;
				fish.velX = 0;
				fish.velY = 0;
				fish.attracted = false;
				fish.respawnTimer = 3.0;
				broadcast("fish_caught", {sessionId: closestSid, fishId: fid, fishType: fish.fishType});
				continue;
			}

			if (hasBobbers && closestDist < FISH_ATTRACT_DIST) {
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

			fish.retargetTimer -= t;
			if (fish.retargetTimer <= 0) { pickFishTarget(fish); }

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

		// Separation
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

	function pickFishTarget(fish:FishState) {
		var bodyTiles = waterBodies[fish.bodyIndex];
		if (bodyTiles == null || bodyTiles.length == 0) { return; }
		var tileIdx = Std.int(Math.random() * bodyTiles.length);
		var tile = bodyTiles[tileIdx];
		fish.targetX = tile.x + Math.random() * 12;
		fish.targetY = tile.y + Math.random() * 12;
		fish.retargetTimer = 2.0 + Math.random();
	}

	function fleeFromFish(fish:FishState, fromX:Float, fromY:Float) {
		if (fish.attracted) { return; }
		var awayX = fish.x - fromX;
		var awayY = fish.y - fromY;
		var len = Math.sqrt(awayX * awayX + awayY * awayY);
		if (len < 0.01) { awayX = Math.random() * 2 - 1; awayY = Math.random() * 2 - 1; len = Math.sqrt(awayX * awayX + awayY * awayY); }
		awayX /= len;
		awayY /= len;

		var bodyTiles = waterBodies[fish.bodyIndex];
		if (bodyTiles == null || bodyTiles.length == 0) { return; }
		var bestDot:Float = -999999;
		var bestTile:{x:Float, y:Float} = null;
		for (tile in bodyTiles) {
			var dx = tile.x - fish.x;
			var dy = tile.y - fish.y;
			var dot = dx * awayX + dy * awayY;
			if (dot > bestDot) { bestDot = dot; bestTile = tile; }
		}
		if (bestTile != null) {
			fish.targetX = bestTile.x + Math.random() * 12;
			fish.targetY = bestTile.y + Math.random() * 12;
			fish.retargetTimer = 2.0 + Math.random();
			var fdx = fish.targetX - fish.x;
			var fdy = fish.targetY - fish.y;
			var fdist = Math.sqrt(fdx * fdx + fdy * fdy);
			if (fdist > 0.1) { fish.velX = (fdx / fdist) * FISH_SPEED; fish.velY = (fdy / fdist) * FISH_SPEED; }
		}
		fish.pauseTimer = 0;
	}

	function scareFish(splashX:Float, splashY:Float, radius:Float = 80) {
		for (id => fish in state.fish) {
			if (!fish.alive) { continue; }
			var dx = fish.x - splashX;
			var dy = fish.y - splashY;
			if (dx * dx + dy * dy < radius * radius) {
				fish.scaredTimer = 0.5;
				fish.attracted = false;
				var len = Math.sqrt(dx * dx + dy * dy);
				if (len > 0.01) { fish.velX = (dx / len) * FISH_SPEED * 1.5; fish.velY = (dy / len) * FISH_SPEED * 1.5; }
			}
		}
	}

	// --- Seagulls ---

	function updateSeagulls(t:Float) {
		var col = state.collision;
		var worldWidth:Float = col.cols * col.tileSize;
		var worldHeight:Float = col.rows * col.tileSize;

		seagullSpawnTimer -= t;
		if (seagullSpawnTimer <= 0) {
			seagullSpawnTimer = 2.0 + Math.random() * 4.0;
			var goingRight = Math.random() > 0.5;
			var speed = 40 + Math.random() * 30;
			var spawnX:Float = goingRight ? -32.0 : worldWidth + 32;
			var spawnY:Float = -80 + Math.random() * (worldHeight * 0.5 + 80);
			var alt:Float = Math.random() * 40;
			var sid = nextSeagullId++;
			var gull = {
				id: sid, x: spawnX, y: spawnY,
				velX: goingRight ? speed : -speed, velY: 0.0,
				goingRight: goingRight, poopTimer: 8.0 + Math.random() * 8.0,
				altitude: alt, driftTimer: 0.5 + Math.random() * 1.0, driftVelY: 0.0
			};
			seagulls.push(gull);
			broadcast("seagull_spawn", {id: sid, x: spawnX, y: spawnY, velX: gull.velX, velY: gull.velY, altitude: alt});
		}

		var i = seagulls.length - 1;
		while (i >= 0) {
			var gull = seagulls[i];
			gull.driftTimer -= t;
			if (gull.driftTimer <= 0) {
				gull.driftTimer = 0.5 + Math.random() * 1.0;
				gull.driftVelY = (Math.random() * 2 - 1) * 10;
			}
			gull.velY = gull.driftVelY;
			gull.x += gull.velX * t;
			gull.y += gull.velY * t;

			gull.poopTimer -= t;
			if (gull.poopTimer <= 0) {
				gull.poopTimer = 8.0 + Math.random() * 8.0;
				var altFactor = Math.max(0, Math.min(1, (worldHeight - gull.y) / worldHeight));
				var shadowOffsetY = 80 + altFactor * 40;
				var landX = gull.x + 12;
				var landY = gull.y + shadowOffsetY;
				var tileX = Std.int(landX / col.tileSize);
				var tileY = Std.int(landY / col.tileSize);
				var hitWater = col.isSwimmableAt(tileX, tileY);
				if (hitWater) { scareFish(landX, landY, 30); }
				broadcast("seagull_poop", {id: gull.id, x: gull.x + 12, y: gull.y + 12, fallDist: shadowOffsetY - 12, birdVelX: gull.velX, hitWater: hitWater});
			}

			if ((gull.goingRight && gull.x > worldWidth + 100) || (!gull.goingRight && gull.x < -100)) {
				broadcast("seagull_despawn", {id: gull.id});
				seagulls.splice(i, 1);
			}
			i--;
		}
	}

	// --- Worms ---

	function updateWorms(t:Float) {
		wormTimer -= t;
		if (wormTimer > 0) { return; }
		wormTimer = 2.5 + Math.random() * 2.0;

		var col = state.collision;
		var w = col.cols;
		var h = col.rows;
		var grid = col.tileSize;

		for (_ in 0...50) {
			var cx = Std.int(Math.random() * w);
			var cy = Std.int(Math.random() * h);
			if (!col.isDirtAt(cx, cy)) { continue; }

			var srcX = cx * grid + Math.random() * grid;
			var srcY = cy * grid + Math.random() * grid;
			var dir = if (Math.random() > 0.5) 1 else -1;
			var dist = 2 + Std.int(Math.random() * 3);
			var destCx = cx + dir * dist;
			if (destCx < 0 || destCx >= w) { continue; }
			if (!col.isDirtAt(destCx, cy)) { continue; }

			var pathOk = true;
			var stepDir = if (dir > 0) 1 else -1;
			var step = cx + stepDir;
			while (step != destCx) {
				if (!col.isDirtAt(step, cy)) { pathOk = false; break; }
				step += stepDir;
			}
			if (!pathOk) { continue; }

			broadcast("worm_spawn", {id: nextWormId++, srcX: srcX, srcY: srcY, destX: destCx * grid + Math.random() * grid, destY: cy * grid + Math.random() * grid});
			break;
		}
	}
}
