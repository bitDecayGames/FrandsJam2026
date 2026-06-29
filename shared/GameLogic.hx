package;

import PInput.P_Input;
import schema.FishState;
import schema.PlayerState;
import schema.RoundState;

/**
 * Pure game simulation logic — no Colyseus, no Flixel, no platform imports.
 * Uses plain Maps instead of MapSchema so it compiles on all Haxe targets.
 * Runs identically on the Node.js server (via GameRoom) and embedded in the
 * HL client (via LocalRoom). Uses callbacks for I/O.
**/
class GameLogic {
	// Callbacks — set by the host (GameRoom or LocalRoom)
	public var broadcast:(topic:String, data:Dynamic) -> Void;
	public var sendToClient:(clientId:String, topic:String, data:Dynamic) -> Void;
	// Called when players/fish/bushes are added/removed so the host can sync to MapSchema
	public var onPlayerAdded:(id:String, ps:PlayerState) -> Void;
	public var onPlayerRemoved:(id:String) -> Void;
	public var onFishAdded:(id:String, fish:FishState) -> Void;
	public var onFishRemoved:(id:String) -> Void;
	public var onBushAdded:(id:String, x:Float, y:Float) -> Void;
	public var onBushRemoved:(id:String) -> Void;
	public var onRoundChanged:(round:RoundState) -> Void;

	// Game state — plain Maps, no MapSchema
	public var players:Map<String, PlayerState> = new Map();
	public var fish:Map<String, FishState> = new Map();
	public var bushPositions:Map<String, {x:Float, y:Float}> = new Map();
	public var round:RoundState = new RoundState();
	public var inputQueue:Map<String, Array<P_Input>> = new Map();

	public var simulation:Simulation;
	public var collision:CollisionMap;

	// Fish AI data
	var waterBodies:Array<Array<{x:Float, y:Float}>>;
	var bobberPositions:Map<String, {x:Float, y:Float}>;
	var hotModePlayers:Map<String, Bool>;
	var wadersPlayers:Map<String, Bool>;
	public var bushRects:Array<{x:Float, y:Float, w:Float, h:Float}>;
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
		id:Int, x:Float, y:Float, velX:Float, velY:Float,
		goingRight:Bool, poopTimer:Float, altitude:Float,
		driftTimer:Float, driftVelY:Float
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
		broadcast = (_, _) -> {};
		sendToClient = (_, _, _) -> {};
		onPlayerAdded = (_, _) -> {};
		onPlayerRemoved = (_) -> {};
		onFishAdded = (_, _) -> {};
		onFishRemoved = (_) -> {};
		onBushAdded = (_, _, _) -> {};
		onBushRemoved = (_) -> {};
		onRoundChanged = (_) -> {};
	}

	public function init(col:CollisionMap, raw:Dynamic) {
		collision = col;
		simulation = new Simulation(col);
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
		var worldW = col.cols * col.tileSize;
		var worldH = col.rows * col.tileSize;
		clouds = [];
		for (i in 0...5) {
			var s = 1.0 + Math.random() * 2.0;
			var speed = 8 + Math.random() * 8;
			clouds.push({
				id: i,
				x: Math.random() * worldW, y: Math.random() * worldH,
				velX: Math.cos(windAngle) * speed, velY: Math.sin(windAngle) * speed,
				scale: s
			});
		}
	}

	// --- Player lifecycle ---

	public function addPlayer(sessionId:String, ?spawnX:Float, ?spawnY:Float) {
		var ps = new PlayerState();
		ps.speed = 100;
		ps.width = 16;
		ps.height = 8;
		if (spawnX != null) { ps.x = spawnX; }
		if (spawnY != null) { ps.y = spawnY; }
		players.set(sessionId, ps);
		inputQueue.set(sessionId, []);
		onPlayerAdded(sessionId, ps);
	}

	public function removePlayer(sessionId:String) {
		players.remove(sessionId);
		inputQueue.remove(sessionId);
		bobberPositions.remove(sessionId);
		hotModePlayers.remove(sessionId);
		wadersPlayers.remove(sessionId);
		onPlayerRemoved(sessionId);
	}

	// --- Message handling ---

	public function handleMessage(clientId:String, topic:String, data:Dynamic) {
		switch (topic) {
			case "set_position":
				var ps = players.get(clientId);
				if (ps != null) { ps.x = data.x; ps.y = data.y; }

			case "player_input":
				if (!players.exists(clientId)) { return; }
				if (!inputQueue.exists(clientId)) { inputQueue.set(clientId, []); }
				if (data == null) { return; }
				for (input in (data : Array<P_Input>)) {
					inputQueue.get(clientId).push(input);
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
				// no-op

			case "ground_fish_drop":
				var px:Float = data.playerX;
				var py:Float = data.playerY;
				var angle = Math.random() * Math.PI * 2;
				var dist = 16 + Math.random() * 16;
				broadcast("ground_fish_spawn", {
					startX: px, startY: py,
					landX: px + Math.cos(angle) * dist, landY: py + Math.sin(angle) * dist,
					fishType: data.fishType, lengthCm: data.lengthCm
				});
			case "ground_fish_pickup":
				broadcast("ground_fish_pickup", data);

			case "player_name_changed":
				var ps = players.get(clientId);
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
				var ps = players.get(clientId);
				if (ps != null) { ps.skinIndex = data.skinIndex; }
			case "score_update":
				var ps = players.get(clientId);
				if (ps != null) { ps.score = data.score; }

			case "item_pickup":
				if (data.itemType == "waders") { wadersPlayers.set(clientId, true); }
				else if (data.itemType == "waders_remove") { wadersPlayers.remove(clientId); }
				broadcast("item_pickup", {sessionId: clientId, itemType: data.itemType, index: data.index});

			case "weed_burst":
				broadcast("weed_burst", {sessionId: clientId, index: data.index});
			case "player_drown":
				broadcast("player_drown", {sessionId: clientId, x: data.x, y: data.y});
			case "bush_rustle":
				// Tier 1 cosmetic — handled client-side only, no relay needed
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
				var ps = players.get(clientId);
				if (ps != null) { ps.speed = isStart ? 150 : 100; }
				broadcast("hot_pepper", {sessionId: clientId, isStart: isStart});

			case "debug_end_round":
				if (gameplayStarted) {
					broadcast("round_time_up", {});
					gameplayStarted = false;
					if (round.status == RoundState.STATUS_ACTIVE) {
						var newData = new RoundState();
						newData.status = RoundState.STATUS_POST_ROUND;
						newData.currentRound = round.currentRound;
						newData.totalRounds = round.totalRounds;
						round = newData;
						onRoundChanged(round);
						for (sId => pp in players) { pp.ready = false; }
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
				var newStatus = data.status != null ? data.status : round.status;
				var newRound = data.currentRound != null ? Std.int(data.currentRound) : round.currentRound;
				var newTotal = data.totalRounds != null ? Std.int(data.totalRounds) : round.totalRounds;
				if (newStatus == round.status && newRound == round.currentRound && newTotal == round.totalRounds) {
					return;
				}
				var newData = new RoundState();
				newData.status = newStatus;
				newData.currentRound = newRound;
				newData.totalRounds = newTotal;
				if (data.status != null) {
					for (sId => pp in players) { pp.ready = false; }
				}
				round = newData;
				onRoundChanged(round);

			case "player_ready":
				if (round.status != RoundState.STATUS_LOBBY
					&& round.status != RoundState.STATUS_PRE_ROUND
					&& round.status != RoundState.STATUS_POST_ROUND) {
					return;
				}
				var ps = players.get(clientId);
				if (ps != null) { ps.ready = true; }
				var ready = true;
				for (sId => pp in players) {
					if (!pp.ready) { ready = false; break; }
				}
				if (ready) {
					broadcast("players_ready", true);
					for (sId => pp in players) { pp.ready = false; }
				}
		}
	}

	// --- Tick ---

	public function update(deltaMs:Float) {
		fixedTick(deltaMs / 1000.0);
	}

	function fixedTick(t:Float) {
		for (id => p in players) {
			var queue = inputQueue.get(id);
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
				if (round.status == RoundState.STATUS_ACTIVE) {
					var newData = new RoundState();
					newData.status = RoundState.STATUS_POST_ROUND;
					newData.currentRound = round.currentRound;
					newData.totalRounds = round.totalRounds;
					round = newData;
					onRoundChanged(round);
					for (sId => pp in players) { pp.ready = false; }
				}
			}
		}
	}

	// --- Round lifecycle ---

	public function resetRoundState() {
		// Clear and respawn fish
		for (id in [for (k in fish.keys()) k]) {
			fish.remove(id);
			onFishRemoved(id);
		}
		nextFishID = 1;
		spawnFish();

		// Clear bushes
		for (id in [for (k in bushPositions.keys()) k]) {
			bushPositions.remove(id);
			onBushRemoved(id);
		}

		seagulls = [];
		seagullSpawnTimer = 3.0;
		wormTimer = 3.0;
		timerSyncCooldown = 5.0;
		bobberPositions = new Map();

		windAngle = Math.random() * Math.PI * 2;
		var worldW = collision.cols * collision.tileSize;
		var worldH = collision.rows * collision.tileSize;
		clouds = [];
		for (i in 0...5) {
			var s = 1.0 + Math.random() * 2.0;
			var speed = 8 + Math.random() * 8;
			clouds.push({
				id: i,
				x: Math.random() * worldW, y: Math.random() * worldH,
				velX: Math.cos(windAngle) * speed, velY: Math.sin(windAngle) * speed,
				scale: s
			});
		}

		cachedWorldItems = null;
		cachedSpawnLocations = null;
		for (_ => p in players) { p.score = 0; p.ready = false; }
	}

	// --- World spawning ---

	public function spawnWorldItems() {
		var w = collision.cols;
		var h = collision.rows;
		var grid = collision.tileSize;

		var grassTiles = new Array<{cx:Int, cy:Int}>();
		var walkableTiles = new Array<{cx:Int, cy:Int}>();
		for (row in 0...h) {
			for (c in 0...w) {
				if (collision.isGrassAt(c, row)) { grassTiles.push({cx: c, cy: row}); }
				if (collision.isWalkableAt(c, row)) { walkableTiles.push({cx: c, cy: row}); }
			}
		}

		// Bushes
		bushRects = [];
		for (_ in 0...5) {
			if (grassTiles.length == 0) { break; }
			var idx = Std.int(Math.random() * grassTiles.length);
			var tile = grassTiles[idx];
			var bx = tile.cx * grid + Math.random() * (grid - 8);
			var by = tile.cy * grid + Math.random() * (grid - 8);
			var bid = Std.string(Lambda.count(bushPositions));
			bushPositions.set(bid, {x: bx, y: by});
			bushRects.push({x: bx + 2, y: by + 2, w: 10.0, h: 2.0});
			onBushAdded(bid, bx, by);
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
		for (sId => ps in players) {
			Reflect.setField(spawnData, sId, {x: sx, y: sy});
			ps.x = sx;
			ps.y = sy;
		}
		cachedSpawnLocations = spawnData;
	}

	// --- Fish ---

	public function spawnFish() {
		var w = collision.cols;
		var h = collision.rows;
		var grid = collision.tileSize;

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
				if (visited[startIdx] || !collision.isSwimmableAt(sx, sy)) { continue; }

				var body = new Array<Int>();
				var stack = [startIdx];
				while (stack.length > 0) {
					var idx = stack.pop();
					if (idx < 0 || idx >= w * h || visited[idx]) { continue; }
					var cx = idx % w;
					var cy = Std.int(idx / w);
					if (!collision.isSwimmableAt(cx, cy)) { continue; }
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
					bodyTiles.push({x: (idx % w) * grid + 2.0, y: Std.int(idx / w) * grid + 2.0});
				}
				var bIdx = waterBodies.length;
				waterBodies.push(bodyTiles);

				for (_ in 0...numFish) {
					var fid = Std.string(nextFishID++);
					var tileIdx = Std.int(Math.random() * bodyTiles.length);
					var tile = bodyTiles[tileIdx];
					var ftype = Std.int(Math.random() * NUM_FISH_TYPES);
					var f = new FishState(tile.x, tile.y, ftype);
					f.bodyIndex = bIdx;
					fish.set(fid, f);
					onFishAdded(fid, f);
				}
				bodyIndex++;
			}
		}
	}

	function updateFish(t:Float) {
		var fishIds = [for (k in fish.keys()) k];
		var fishStates = [for (f in fish) f];

		for (i in 0...fishIds.length) {
			var f = fishStates[i];
			var fid = fishIds[i];

			if (f.scaredTimer > 0) {
				f.scaredTimer -= t;
				f.x += f.velX * t;
				f.y += f.velY * t;
				if (f.scaredTimer <= 0) {
					f.alive = false; f.velX = 0; f.velY = 0; f.respawnTimer = 5.5;
				}
				continue;
			}

			if (!f.alive) {
				if (f.respawnTimer > 0) {
					f.respawnTimer -= t;
					if (f.respawnTimer <= 0) {
						var bodyTiles = waterBodies[f.bodyIndex];
						if (bodyTiles != null && bodyTiles.length > 0) {
							var tile = bodyTiles[Std.int(Math.random() * bodyTiles.length)];
							f.x = tile.x + Math.random() * 12;
							f.y = tile.y + Math.random() * 12;
							f.velX = 0; f.velY = 0; f.alive = true;
							f.attracted = false; f.pauseTimer = 0;
							f.retargetTimer = Math.random() + 2.0;
							pickFishTarget(f);
						}
					}
				}
				continue;
			}

			if (f.pauseTimer > 0) { f.pauseTimer -= t; continue; }

			// Bobber interaction
			var closestDist = 1e20;
			var closestSid:String = null;
			var closestBX:Float = 0;
			var closestBY:Float = 0;
			var hasBobbers = false;
			// Fish sprite is ~16x8; use center for distance checks
			var fcx = f.x + 8;
			var fcy = f.y + 4;
			for (sid => bpos in bobberPositions) {
				hasBobbers = true;
				var dx = bpos.x - fcx;
				var dy = bpos.y - fcy;
				var dist = Math.sqrt(dx * dx + dy * dy);
				if (dist < closestDist) { closestDist = dist; closestSid = sid; closestBX = bpos.x; closestBY = bpos.y; }
			}

			if (f.attracted && !hasBobbers) { f.attracted = false; fleeFromFish(f, f.x + f.velX, f.y + f.velY); continue; }
			if (f.attracted && closestDist > FISH_ATTRACT_DIST) { f.attracted = false; fleeFromFish(f, closestBX, closestBY); continue; }
			if (hasBobbers && closestDist < FISH_CATCH_DIST) {
				f.alive = false; f.velX = 0; f.velY = 0; f.attracted = false; f.respawnTimer = 3.0;
				broadcast("fish_caught", {sessionId: closestSid, fishId: fid, fishType: f.fishType});
				continue;
			}
			if (hasBobbers && closestDist < FISH_ATTRACT_DIST) {
				f.attracted = true; f.pauseTimer = 0;
				var dx = closestBX - f.x; var dy = closestBY - f.y;
				if (closestDist > 0.1) { f.velX = (dx / closestDist) * FISH_ATTRACT_SPEED; f.velY = (dy / closestDist) * FISH_ATTRACT_SPEED; }
				f.x += f.velX * t; f.y += f.velY * t;
				continue;
			}

			// Wander
			f.retargetTimer -= t;
			if (f.retargetTimer <= 0) { pickFishTarget(f); }
			var dx = f.targetX - f.x; var dy = f.targetY - f.y;
			var dist = Math.sqrt(dx * dx + dy * dy);
			if (dist < FISH_ARRIVE_DIST) {
				f.velX = 0; f.velY = 0; f.pauseTimer = 1.0 + Math.random() * 2.0; pickFishTarget(f);
			} else {
				f.velX = (dx / dist) * FISH_SPEED; f.velY = (dy / dist) * FISH_SPEED;
			}
			f.x += f.velX * t; f.y += f.velY * t;
		}

		// Separation
		for (i in 0...fishStates.length) {
			var a = fishStates[i];
			if (!a.alive) { continue; }
			for (j in (i + 1)...fishStates.length) {
				var b = fishStates[j];
				if (!b.alive) { continue; }
				var dx = a.x - b.x; var dy = a.y - b.y;
				if (dx * dx + dy * dy < FISH_SEPARATION_DIST * FISH_SEPARATION_DIST) {
					fleeFromFish(a, b.x, b.y); fleeFromFish(b, a.x, a.y);
				}
			}
		}
	}

	function pickFishTarget(f:FishState) {
		var bodyTiles = waterBodies[f.bodyIndex];
		if (bodyTiles == null || bodyTiles.length == 0) { return; }
		var tile = bodyTiles[Std.int(Math.random() * bodyTiles.length)];
		f.targetX = tile.x + Math.random() * 12;
		f.targetY = tile.y + Math.random() * 12;
		f.retargetTimer = 2.0 + Math.random();
	}

	function fleeFromFish(f:FishState, fromX:Float, fromY:Float) {
		if (f.attracted) { return; }
		var awayX = f.x - fromX; var awayY = f.y - fromY;
		var len = Math.sqrt(awayX * awayX + awayY * awayY);
		if (len < 0.01) { awayX = Math.random() * 2 - 1; awayY = Math.random() * 2 - 1; len = Math.sqrt(awayX * awayX + awayY * awayY); }
		awayX /= len; awayY /= len;
		var bodyTiles = waterBodies[f.bodyIndex];
		if (bodyTiles == null || bodyTiles.length == 0) { return; }
		var bestDot:Float = -999999; var bestTile:{x:Float, y:Float} = null;
		for (tile in bodyTiles) {
			var dot = (tile.x - f.x) * awayX + (tile.y - f.y) * awayY;
			if (dot > bestDot) { bestDot = dot; bestTile = tile; }
		}
		if (bestTile != null) {
			f.targetX = bestTile.x + Math.random() * 12; f.targetY = bestTile.y + Math.random() * 12;
			f.retargetTimer = 2.0 + Math.random();
			var fdx = f.targetX - f.x; var fdy = f.targetY - f.y;
			var fdist = Math.sqrt(fdx * fdx + fdy * fdy);
			if (fdist > 0.1) { f.velX = (fdx / fdist) * FISH_SPEED; f.velY = (fdy / fdist) * FISH_SPEED; }
		}
		f.pauseTimer = 0;
	}

	function scareFish(splashX:Float, splashY:Float, radius:Float = 80) {
		for (id => f in fish) {
			if (!f.alive) { continue; }
			var dx = f.x - splashX; var dy = f.y - splashY;
			if (dx * dx + dy * dy < radius * radius) {
				f.scaredTimer = 0.5; f.attracted = false;
				var len = Math.sqrt(dx * dx + dy * dy);
				if (len > 0.01) { f.velX = (dx / len) * FISH_SPEED * 1.5; f.velY = (dy / len) * FISH_SPEED * 1.5; }
			}
		}
	}

	// --- Seagulls ---

	function updateSeagulls(t:Float) {
		var worldWidth:Float = collision.cols * collision.tileSize;
		var worldHeight:Float = collision.rows * collision.tileSize;

		seagullSpawnTimer -= t;
		if (seagullSpawnTimer <= 0) {
			seagullSpawnTimer = 2.0 + Math.random() * 4.0;
			var goingRight = Math.random() > 0.5;
			var speed = 40 + Math.random() * 30;
			var spawnX:Float = goingRight ? -32.0 : worldWidth + 32;
			var spawnY:Float = -80 + Math.random() * (worldHeight * 0.5 + 80);
			var alt:Float = Math.random() * 40;
			var sid = nextSeagullId++;
			seagulls.push({
				id: sid, x: spawnX, y: spawnY,
				velX: goingRight ? speed : -speed, velY: 0.0,
				goingRight: goingRight, poopTimer: 8.0 + Math.random() * 8.0,
				altitude: alt, driftTimer: 0.5 + Math.random() * 1.0, driftVelY: 0.0
			});
			broadcast("seagull_spawn", {id: sid, x: spawnX, y: spawnY, velX: (goingRight ? speed : -speed), velY: 0.0, altitude: alt});
		}

		var i = seagulls.length - 1;
		while (i >= 0) {
			var gull = seagulls[i];
			gull.driftTimer -= t;
			if (gull.driftTimer <= 0) { gull.driftTimer = 0.5 + Math.random() * 1.0; gull.driftVelY = (Math.random() * 2 - 1) * 10; }
			gull.velY = gull.driftVelY;
			gull.x += gull.velX * t; gull.y += gull.velY * t;

			gull.poopTimer -= t;
			if (gull.poopTimer <= 0) {
				gull.poopTimer = 8.0 + Math.random() * 8.0;
				var altFactor = Math.max(0, Math.min(1, (worldHeight - gull.y) / worldHeight));
				var shadowOffsetY = 80 + altFactor * 40;
				var landX = gull.x + 12; var landY = gull.y + shadowOffsetY;
				var tileX = Std.int(landX / collision.tileSize); var tileY = Std.int(landY / collision.tileSize);
				var hitWater = collision.isSwimmableAt(tileX, tileY);
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

		var w = collision.cols; var h = collision.rows; var grid = collision.tileSize;
		for (_ in 0...50) {
			var cx = Std.int(Math.random() * w); var cy = Std.int(Math.random() * h);
			if (!collision.isDirtAt(cx, cy)) { continue; }
			var srcX = cx * grid + Math.random() * grid; var srcY = cy * grid + Math.random() * grid;
			var dir = if (Math.random() > 0.5) 1 else -1;
			var dist = 2 + Std.int(Math.random() * 3);
			var destCx = cx + dir * dist;
			if (destCx < 0 || destCx >= w) { continue; }
			if (!collision.isDirtAt(destCx, cy)) { continue; }
			var pathOk = true;
			var step = cx + (if (dir > 0) 1 else -1);
			while (step != destCx) {
				if (!collision.isDirtAt(step, cy)) { pathOk = false; break; }
				step += if (dir > 0) 1 else -1;
			}
			if (!pathOk) { continue; }
			broadcast("worm_spawn", {id: nextWormId++, srcX: srcX, srcY: srcY, destX: destCx * grid + Math.random() * grid, destY: cy * grid + Math.random() * grid});
			break;
		}
	}
}
