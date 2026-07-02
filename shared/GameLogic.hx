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
	var knockbacks:Map<String, {velX:Float, velY:Float, timer:Float}> = new Map();

	public var simulation:Simulation;
	public var collision:CollisionMap;

	// Fish AI data
	var waterBodies:Array<Array<{x:Float, y:Float}>>;
	var bobberPositions:Map<String, {x:Float, y:Float}>;
	var hotModePlayers:Map<String, Bool>;
	var hotModeTimers:Map<String, Float>;
	var inventories:Map<String, Array<{type:String, ?fishType:Int, ?lengthCm:Int, ?big:Bool, ?debug:Bool}>>;
	static inline var MAX_INVENTORY:Int = 4;
	var wadersPlayers:Map<String, Bool>;
	public var bushRects:Array<{x:Float, y:Float, w:Float, h:Float}>;
	var pickedUpItems:Map<String, Bool>; // tracks which world items have been picked up
	var nextFishID:Int;

	// Worm spawning data
	var wormTimer:Float;
	var nextWormId:Int;

	// Dog AI data — states: "chasing", "waiting", "seeking", "fleeing"
	var dogs:Array<{
		id:Int, x:Float, y:Float, velX:Float, velY:Float,
		targetSession:String, state:String, fleeTimer:Float,
		fishTargetX:Float, fishTargetY:Float, waitTimer:Float,
		path:Array<{x:Float, y:Float}>, pathIndex:Int, pathCooldown:Float
	}>;
	var nextDogId:Int;
	var dogSpawnTimer:Float;
	static var DOG_SPEED:Float = 100;
	static var DOG_SEEK_SPEED:Float = 80;
	static var DOG_FLEE_SPEED:Float = 160;
	static var DOG_CATCH_DIST:Float = 10;
	static var DOG_FISH_PICKUP_DIST:Float = 6;
	static var DOG_SPAWN_INTERVAL_MIN:Float = 15;
	static var DOG_SPAWN_INTERVAL_MAX:Float = 30;
	static var DOG_UPDATE_RATE:Float = 0.15;
	static var DOG_FLEE_DURATION:Float = 5.0;
	static var DOG_WAIT_TIMEOUT:Float = 2.0; // max time to wait for item drop response
	static var DOG_ITEM_DROP_RADIUS:Float = 36.0;
	var dogUpdateTimer:Float;

	// Power-up item box
	var powerUpX:Float;
	var powerUpY:Float;
	var powerUpAlive:Bool;
	var powerUpRespawnTimer:Float;
	static var POWERUP_RESPAWN_DELAY:Float = 5.0;

	// Rockets in flight
	var rockets:Array<{
		id:Int, x:Float, y:Float, dirX:Float, dirY:Float,
		speed:Float, ownerSession:String
	}>;
	var nextRocketId:Int;
	static var ROCKET_INITIAL_SPEED:Float = 40;
	static var ROCKET_ACCELERATION:Float = 300;
	static var ROCKET_MAX_SPEED:Float = 350;
	static var ROCKET_HIT_DIST:Float = 12;

	// Hunger potion
	var hungerTimer:Float;
	var hungerBodyIndex:Int; // which water body is affected (-1 = none)
	static var HUNGER_DURATION:Float = 10.0;
	static var HUNGER_ATTRACT_DIST:Float = 999; // attract from anywhere in body

	// Gravity bomb
	var gravityBombTimer:Float;
	var gravityBombX:Float;
	var gravityBombY:Float;
	static var GRAVITY_BOMB_DURATION:Float = 8.0;

	// Fish bait
	var baitTimer:Float;
	var baitX:Float;
	var baitY:Float;
	var baitRadiusX:Float;
	var baitRadiusY:Float;
	var baitBodyIndex:Int;
	static var BAIT_DURATION:Float = 15.0;
	static var BAIT_RADIUS:Float = 64.0;
	static var BAIT_RADIUS_Y:Float = 44.0; // squashed oval

	// Time of day (hours 0-24), server-authoritative. Noon (12) = neutral colors.
	public var timeOfDayHour:Float;
	var timeTargetHour:Float;
	var timeFastForward:Bool;
	var todSyncCooldown:Float;
	static var TIME_NORMAL_RATE:Float = 0.0; // time stands still — only set_time moves the clock
	static var TIME_FAST_RATE:Float = 6.0; // fast-forward speed, game-hours per second

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
		hotModeTimers = new Map();
		inventories = new Map();
		wadersPlayers = new Map();
		bushRects = [];
		pickedUpItems = new Map();
		nextFishID = 1;

		wormTimer = 999;
		nextWormId = 1;

		dogs = [];
		nextDogId = 1;
		dogSpawnTimer = 10.0; // first dog after 10 seconds
		dogUpdateTimer = 0;

		powerUpAlive = false;
		powerUpRespawnTimer = 3.0; // spawn first power-up after 3 seconds
		powerUpX = 0;
		powerUpY = 0;
		rockets = [];
		nextRocketId = 1;
		hungerTimer = 0;
		hungerBodyIndex = -1;
		gravityBombTimer = 0;
		gravityBombX = 0;
		gravityBombY = 0;
		baitTimer = 0;
		baitX = 0;
		baitY = 0;
		baitRadiusX = BAIT_RADIUS;
		baitRadiusY = BAIT_RADIUS_Y;
		baitBodyIndex = -1;

		roundTimerSec = 0;
		roundDurationSec = 600;
		timerSyncCooldown = 5.0;
		gameplayStarted = false;

		timeOfDayHour = 12.0;
		timeTargetHour = 12.0;
		timeFastForward = false;
		todSyncCooldown = 5.0;

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
		inventories.set(sessionId, []);
		onPlayerAdded(sessionId, ps);
	}

	public function removePlayer(sessionId:String) {
		players.remove(sessionId);
		inputQueue.remove(sessionId);
		bobberPositions.remove(sessionId);
		hotModePlayers.remove(sessionId);
		wadersPlayers.remove(sessionId);
		inventories.remove(sessionId);
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
				var gfWorldW:Float = collision.cols * collision.tileSize;
				var gfWorldH:Float = collision.rows * collision.tileSize;
				var gfLandX = px;
				var gfLandY = py;
				for (_ in 0...20) {
					var angle = Math.random() * Math.PI * 2;
					var dist = 16 + Math.random() * 16;
					var tx = px + Math.cos(angle) * dist;
					var ty = py + Math.sin(angle) * dist;
					if (tx < 8 || tx > gfWorldW - 8 || ty < 8 || ty > gfWorldH - 8) { continue; }
					var col = Std.int(tx / collision.tileSize);
					var row = Std.int(ty / collision.tileSize);
					if (collision.isWalkableAt(col, row)) {
						gfLandX = tx;
						gfLandY = ty;
						break;
					}
				}
				broadcast("ground_fish_spawn", {
					startX: px, startY: py,
					landX: gfLandX, landY: gfLandY,
					fishType: data.fishType, lengthCm: data.lengthCm
				});
			case "ground_fish_pickup":
				broadcast("ground_fish_pickup", {x: data.x, y: data.y, sessionId: clientId});

			case "ground_item_pickup":
				// Server adds the item to inventory
				var itemData:{type:String, ?fishType:Int, ?lengthCm:Int, ?big:Bool, ?debug:Bool} = {type: data.itemType};
				if (data.fishType != null) { itemData.fishType = Std.int(data.fishType); }
				if (data.lengthCm != null) { itemData.lengthCm = Std.int(data.lengthCm); }
				serverAddItem(clientId, itemData);

			case "player_name_changed":
				var ps = players.get(clientId);
				if (ps != null) { ps.name = data.name; }

			case "bobber_landed":
				bobberPositions.set(clientId, {x: data.x, y: data.y});
			case "bobber_retracted":
				bobberPositions.remove(clientId);

			case "throw_rock":
				var isBig:Bool = data.big == true;
				var rockType = if (isBig) "big_rock" else "rock";
				if (!serverHasItem(clientId, rockType)) { return; }
				serverRemoveItem(clientId, rockType);
				broadcast("throw_rock", {sessionId: clientId, targetX: data.targetX, targetY: data.targetY, big: isBig, dir: data.dir});
			case "rock_splash":
				broadcast("rock_splash", {x: data.x, y: data.y, big: data.big});
				scareFish(data.x, data.y);

			case "skin_changed":
				var requestedSkin:Int = data.skinIndex;
				// Enforce one skin per player
				var taken = false;
				for (sId => p in players) {
					if (sId != clientId && p.skinIndex == requestedSkin) { taken = true; break; }
				}
				if (taken) {
					for (i in 0...8) {
						var inUse = false;
						for (sId => p in players) {
							if (sId != clientId && p.skinIndex == i) { inUse = true; break; }
						}
						if (!inUse) { requestedSkin = i; break; }
					}
				}
				var ps = players.get(clientId);
				if (ps != null) { ps.skinIndex = requestedSkin; }
				// Tell the client what skin they actually got
				sendToClient(clientId, "skin_assigned", {skinIndex: requestedSkin});
			case "score_update":
				var ps = players.get(clientId);
				if (ps != null) { ps.score = data.score; }

			case "item_pickup":
				var itemType:String = data.itemType;
				var index:Int = Std.int(data.index);
				var key = '${itemType}_${index}';
				if (pickedUpItems.exists(key)) { return; }
				// Check inventory space (waders_remove is a removal, not a pickup)
				if (itemType != "waders_remove" && itemType != "pepper" && serverInventoryFull(clientId)) { return; }
				pickedUpItems.set(key, true);
				// Add to server inventory + handle side effects
				if (itemType == "rock") {
					serverAddItem(clientId, {type: "rock"});
				} else if (itemType == "big_rock") {
					serverAddItem(clientId, {type: "big_rock"});
				} else if (itemType == "waders") {
					wadersPlayers.set(clientId, true);
					serverAddItem(clientId, {type: "waders"});
				} else if (itemType == "waders_remove") {
					wadersPlayers.remove(clientId);
					serverRemoveItem(clientId, "waders");
				} else if (itemType == "pepper") {
					hotModePlayers.set(clientId, true);
					hotModeTimers.set(clientId, 3.0);
					var ps2 = players.get(clientId);
					if (ps2 != null) { ps2.speed = 150; }
					broadcast("hot_pepper", {sessionId: clientId, isStart: true});
				}
				broadcast("item_pickup", {sessionId: clientId, itemType: itemType, index: index});

			case "weed_burst":
				broadcast("weed_burst", {sessionId: clientId, index: data.index});
			case "player_drown":
				// Server-authoritative — drowning is detected in fixedTick(), not from client messages
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
				var duration:Float = data.duration != null ? data.duration : 3.0;
				hotModePlayers.set(clientId, isStart);
				if (isStart) {
					hotModeTimers.set(clientId, duration);
				} else {
					hotModeTimers.remove(clientId);
				}
				var ps = players.get(clientId);
				if (ps != null) { ps.speed = isStart ? 150 : 100; }
				broadcast("hot_pepper", {sessionId: clientId, isStart: isStart});

			case "dog_item_drop":
				// Server reads items from its own inventory — don't trust client
				var px:Float = data.playerX;
				var py:Float = data.playerY;
				var dogId:Int = data.dogId;
				var items = serverClearInventory(clientId);
				// Also clear waders flag
				wadersPlayers.remove(clientId);
				var firstFishX:Float = 0;
				var firstFishY:Float = 0;
				var hasFish = false;
				if (items != null) {
					var count = items.length;
					var worldW:Float = collision.cols * collision.tileSize;
					var worldH:Float = collision.rows * collision.tileSize;
					for (j in 0...count) {
						// Find a walkable landing spot (not water, not off-screen)
						var landX:Float = px;
						var landY:Float = py;
						var baseAngle = (j / count) * Math.PI * 2;
						for (_ in 0...20) {
							var angle = baseAngle + Math.random() * 0.6 - 0.3;
							var dist = DOG_ITEM_DROP_RADIUS + Math.random() * 12;
							var tx = px + Math.cos(angle) * dist;
							var ty = py + Math.sin(angle) * dist;
							// Clamp to world bounds
							if (tx < 8 || tx > worldW - 8 || ty < 8 || ty > worldH - 8) { continue; }
							var col = Std.int(tx / collision.tileSize);
							var row = Std.int(ty / collision.tileSize);
							if (collision.isWalkableAt(col, row)) {
								landX = tx;
								landY = ty;
								break;
							}
							// Try a different angle on next attempt
							baseAngle += 0.5;
						}
						var item = items[j];
						broadcast("dog_item_landed", {
							startX: px, startY: py,
							landX: landX, landY: landY,
							itemType: item.type,
							itemData: item
						});
						if (!hasFish && item.type == "fish") {
							firstFishX = landX;
							firstFishY = landY;
							hasFish = true;
						}
					}
				}
				// Tell the dog where to go — delay seeking so items have time to land
				for (dog in dogs) {
					if (dog.id == dogId) {
						if (hasFish) {
							dog.fishTargetX = firstFishX;
							dog.fishTargetY = firstFishY;
							// Stay in "waiting" for a moment to let items arc and land,
							// then transition to seeking when waitTimer expires
							dog.state = "waiting";
							dog.waitTimer = 0.5; // brief pause before chasing the fish
						} else {
							startDogFlee(dog);
						}
						break;
					}
				}

			case "dog_no_fish":
				// Player had no fish — dog flees immediately
				var dogId:Int = data.dogId;
				for (dog in dogs) {
					if (dog.id == dogId) {
						startDogFlee(dog);
						break;
					}
				}

			case "debug_spawn_dog":
				var worldW:Float = collision.cols * collision.tileSize;
				var worldH:Float = collision.rows * collision.tileSize;
				spawnDog(worldW, worldH);

			case "throw_potion":
				if (!serverHasItem(clientId, "hunger_potion")) { return; }
				serverRemoveItem(clientId, "hunger_potion");
				broadcast("throw_potion", {sessionId: clientId, targetX: data.targetX, targetY: data.targetY, dir: data.dir});

			case "throw_bait":
				if (!serverHasItem(clientId, "fish_bait")) { return; }
				serverRemoveItem(clientId, "fish_bait");
				broadcast("throw_bait", {sessionId: clientId, targetX: data.targetX, targetY: data.targetY, dir: data.dir});

			case "bait_landed":
				baitX = data.x;
				baitY = data.y;
				// Find which water body the bait landed in
				var baitGrid = collision.tileSize;
				var baitCx = Std.int(baitX / baitGrid);
				var baitCy = Std.int(baitY / baitGrid);
				baitBodyIndex = -1;
				for (bi in 0...waterBodies.length) {
					for (tile in waterBodies[bi]) {
						if (Std.int(tile.x / baitGrid) == baitCx && Std.int(tile.y / baitGrid) == baitCy) {
							baitBodyIndex = bi;
							break;
						}
					}
					if (baitBodyIndex >= 0) { break; }
				}
				if (baitBodyIndex >= 0) {
					baitTimer = BAIT_DURATION;
					broadcast("bait_active", {duration: BAIT_DURATION, x: baitX, y: baitY, radiusX: BAIT_RADIUS, radiusY: BAIT_RADIUS_Y});
				}

			case "potion_landed":
				// Find which water body the potion landed in
				var landX:Float = data.x;
				var landY:Float = data.y;
				var grid = collision.tileSize;
				var landCx = Std.int(landX / grid);
				var landCy = Std.int(landY / grid);
				hungerBodyIndex = -1;
				for (bi in 0...waterBodies.length) {
					for (tile in waterBodies[bi]) {
						var tcx = Std.int(tile.x / grid);
						var tcy = Std.int(tile.y / grid);
						if (tcx == landCx && tcy == landCy) {
							hungerBodyIndex = bi;
							break;
						}
					}
					if (hungerBodyIndex >= 0) { break; }
				}
				if (hungerBodyIndex >= 0) {
					hungerTimer = HUNGER_DURATION;
					broadcast("hunger_active", {duration: HUNGER_DURATION, x: landX, y: landY});
				}

			case "fire_rocket":
				if (!serverHasItem(clientId, "rocket")) { return; }
				serverRemoveItem(clientId, "rocket");
				var p = players.get(clientId);
				if (p != null) {
					var dir:Int = data.dir; // 0=up, 1=right, 2=down, 3=left
					var dx:Float = if (dir == 1) 1 else if (dir == 3) -1 else 0;
					var dy:Float = if (dir == 0) -1 else if (dir == 2) 1 else 0;
					var rid = nextRocketId++;
					// Spawn from visual center of player (hitbox is 16x8 near feet of 48x48 graphic)
					var spawnX = p.x + p.width / 2;
					var spawnY = p.y - 4;
					rockets.push({
						id: rid, x: spawnX, y: spawnY,
						dirX: dx, dirY: dy, speed: ROCKET_INITIAL_SPEED,
						ownerSession: clientId
					});
					broadcast("rocket_fired", {
						id: rid, x: spawnX, y: spawnY,
						dirX: dx, dirY: dy, sessionId: clientId
					});
					// Apply decelerating knockback to shooter
					if (!knockbacks.exists(clientId)) {
						knockbacks.set(clientId, {velX: -dx * 300, velY: -dy * 300, timer: 0.3});
						broadcast("player_knockback", {sessionId: clientId, duration: 0.3});
					}
				}

			case "set_time":
				// Day/Night buttons — fast-forward the clock to the requested hour
				var target:Float = data.hour;
				timeTargetHour = ((target % 24) + 24) % 24;
				timeFastForward = true;
				broadcast("time_sync", {hour: timeOfDayHour, rate: TIME_FAST_RATE});

			case "use_gravity_bomb":
				if (gravityBombTimer > 0) { return; } // one active bomb at a time
				if (!serverHasItem(clientId, "gravity_bomb")) { return; }
				serverRemoveItem(clientId, "gravity_bomb");
				var p = players.get(clientId);
				if (p != null) {
					// Drop the bomb at the player's feet (bottom-center of hitbox)
					gravityBombX = p.x + p.width / 2;
					gravityBombY = p.y + p.height;
					gravityBombTimer = GRAVITY_BOMB_DURATION;
					simulation.gravityWell = {x: gravityBombX, y: gravityBombY};
					broadcast("gravity_bomb_active", {
						x: gravityBombX, y: gravityBombY,
						duration: GRAVITY_BOMB_DURATION, sessionId: clientId
					});
				}

			case "debug_inventory":
				var action:String = data.action;
				var type:String = data.type;
				if (action == "add") {
					// debug-granted items are never consumed on use — only removable via the button
					var item:{type:String, ?fishType:Int, ?lengthCm:Int, ?big:Bool, ?debug:Bool} = {type: type, debug: true};
					if (data.fishType != null) { item.fishType = Std.int(data.fishType); }
					if (data.lengthCm != null) { item.lengthCm = Std.int(data.lengthCm); }
					serverAddItem(clientId, item);
					if (type == "waders") { wadersPlayers.set(clientId, true); }
				} else if (action == "remove") {
					serverRemoveItem(clientId, type, true);
					if (type == "waders") { wadersPlayers.remove(clientId); }
				}

			case "debug_end_round":
				if (gameplayStarted) {
					broadcast("round_time_up", {});
					gameplayStarted = false;
					if (round.status == RoundState.STATUS_ACTIVE) {
						broadcastRoundSummary();
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
				// Round just ended via a client-driven transition — sell fish + send summary
				if (newStatus == RoundState.STATUS_POST_ROUND && round.status == RoundState.STATUS_ACTIVE) {
					broadcastRoundSummary();
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
			// Process knockback — decelerating slide, blocks normal input
			var kb = knockbacks.get(id);
			if (kb != null) {
				var frac = kb.timer > 0 ? kb.timer / 0.3 : 0; // decelerate from full to zero
				p.x += kb.velX * frac * t;
				p.y += kb.velY * frac * t;
				p.velocityX = kb.velX * frac;
				p.velocityY = kb.velY * frac;
				kb.timer -= t;
				if (kb.timer <= 0) { knockbacks.remove(id); }
				// Drain input queue but don't process it
				var queue = inputQueue.get(id);
				if (queue != null) {
					// Update lastProcessedSeq so client reconciliation stays in sync
					for (inp in queue) { p.lastProcessedSeq = inp.seq; }
					queue.splice(0, queue.length);
				}
				continue; // skip normal movement
			}

			var queue = inputQueue.get(id);
			if (queue == null || queue.length == 0) {
				if (gravityBombTimer > 0) {
					// No inputs this tick, but the bomb still sucks — tick with a no-move input
					var idleHot = hotModePlayers.exists(id) && hotModePlayers.get(id);
					var idleWaders = wadersPlayers.exists(id) && wadersPlayers.get(id);
					var idleFlags = if (idleHot || idleWaders) CollisionMap.FLAG_SOLID else 0;
					simulation.tickPlayer(p, [{seq: p.lastProcessedSeq, dir: -1, buttons: 0, elapsed: t}], t, idleFlags);
				} else {
					p.velocityX = 0;
					p.velocityY = 0;
				}
				continue;
			}
			var isHot = hotModePlayers.exists(id) && hotModePlayers.get(id);
			var hasWaders = wadersPlayers.exists(id) && wadersPlayers.get(id);
			var blockFlags = if (isHot || hasWaders) CollisionMap.FLAG_SOLID else 0;
			for (inp in queue) {
				simulation.tickPlayer(p, [inp], inp.elapsed, blockFlags);
			}
			queue.splice(0, queue.length);

			// Clamp player to world bounds
			var worldW:Float = collision.cols * collision.tileSize;
			var worldH:Float = collision.rows * collision.tileSize;
			if (p.x < 0) { p.x = 0; }
			if (p.y < 0) { p.y = 0; }
			if (p.x + p.width > worldW) { p.x = worldW - p.width; }
			if (p.y + p.height > worldH) { p.y = worldH - p.height; }

			// Shallow water: use center point for stable detection (no oscillation at edges)
			if (hasWaders) {
				p.inShallowWater = collision.isShallowAt(p.x + p.width / 2, p.y + p.height / 2);
			} else {
				p.inShallowWater = false;
			}
			p.speed = if (isHot) 150 else if (p.inShallowWater) 50 else 100;

			// Server-authoritative hot mode drown check
			var isHot2 = hotModePlayers.exists(id) && hotModePlayers.get(id);
			if (isHot2) {
				var cx = p.x + p.width / 2;
				var cy = p.y + p.height / 2;
				var pcx = Std.int(cx / collision.tileSize);
				var pcy = Std.int(cy / collision.tileSize);
				var inDeepWater = collision.isSwimmableAt(pcx, pcy);
				var onShallowTile = collision.isShallowAt(cx, cy);
				var hasW = wadersPlayers.exists(id) && wadersPlayers.get(id);
				if (inDeepWater || (onShallowTile && !hasW)) {
					if (hasW) {
						hotModePlayers.set(id, false);
						hotModeTimers.remove(id);
						broadcast("hot_pepper", {sessionId: id, isStart: false});
					} else {
						hotModePlayers.set(id, false);
						hotModeTimers.remove(id);
						broadcast("player_drown", {sessionId: id, x: p.x, y: p.y});
					}
				} else if (p.inShallowWater && hasW) {
					hotModePlayers.set(id, false);
					hotModeTimers.remove(id);
					broadcast("pepper_extinguish", {sessionId: id, x: p.x, y: p.y});
				}
			}
		}

		// Tick hot mode timers (server-authoritative)
		for (pid in [for (k in hotModeTimers.keys()) k]) {
			var timer = hotModeTimers.get(pid);
			timer -= t;
			if (timer <= 0) {
				hotModeTimers.remove(pid);
				hotModePlayers.set(pid, false);
				var ps = players.get(pid);
				if (ps != null) { ps.speed = if (ps.inShallowWater) 50 else 100; }
				broadcast("hot_pepper", {sessionId: pid, isStart: false});
			} else {
				hotModeTimers.set(pid, timer);
			}
		}

		updateFish(t);
		updateSeagulls(t);
		updateWorms(t);
		updateDogs(t);
		updatePowerUp(t);
		updateRockets(t);
		if (hungerTimer > 0) {
			hungerTimer -= t;
			if (hungerTimer <= 0) {
				hungerTimer = 0;
				broadcast("hunger_expired", {});
			}
		}
		if (baitTimer > 0) {
			baitTimer -= t;
			if (baitTimer <= 0) {
				baitTimer = 0;
				broadcast("bait_expired", {});
			}
		}
		if (gravityBombTimer > 0) {
			gravityBombTimer -= t;
			if (gravityBombTimer <= 0) {
				gravityBombTimer = 0;
				simulation.gravityWell = null;
				broadcast("gravity_bomb_expired", {});
			}
		}

		// Advance time of day — fast-forward runs until it hits the target hour
		if (timeFastForward) {
			var remaining = timeTargetHour - timeOfDayHour;
			while (remaining < 0) { remaining += 24; }
			var step = TIME_FAST_RATE * t;
			if (step >= remaining) {
				timeOfDayHour = timeTargetHour;
				timeFastForward = false;
				broadcast("time_sync", {hour: timeOfDayHour, rate: TIME_NORMAL_RATE});
			} else {
				timeOfDayHour = (timeOfDayHour + step) % 24;
			}
		} else {
			timeOfDayHour = (timeOfDayHour + TIME_NORMAL_RATE * t) % 24;
		}
		todSyncCooldown -= t;
		if (todSyncCooldown <= 0) {
			todSyncCooldown = 5.0;
			broadcast("time_sync", {hour: timeOfDayHour, rate: timeFastForward ? TIME_FAST_RATE : TIME_NORMAL_RATE});
		}

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
					broadcastRoundSummary();
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

		// Clear all inventories
		for (pid in inventories.keys()) {
			serverClearInventory(pid);
		}
		wadersPlayers = new Map();

		// Clear dogs and reset spawn timer
		for (d in dogs) {
			broadcast("dog_despawn", {id: d.id});
		}
		dogs = [];
		dogSpawnTimer = 10.0;

		// Clear rockets
		for (r in rockets) {
			broadcast("rocket_despawn", {id: r.id});
		}
		rockets = [];

		// Reset hunger/bait/gravity bomb
		hungerTimer = 0;
		baitTimer = 0;
		if (gravityBombTimer > 0) {
			gravityBombTimer = 0;
			simulation.gravityWell = null;
			broadcast("gravity_bomb_expired", {});
		}
		powerUpAlive = false;
		powerUpRespawnTimer = 3.0;

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
		pickedUpItems = new Map();
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
					pickFishTarget(f); // start moving immediately
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
				f.aiState = FishState.STATE_SCARED;
				if (f.scaredTimer <= 0) {
					f.alive = false; f.velX = 0; f.velY = 0; f.respawnTimer = 5.5;
					f.aiState = FishState.STATE_DEAD;
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
							f.attracted = false; f.pauseTimer = 0; f.rocketFeared = false;
							f.aiState = FishState.STATE_SPAWNING;
							f.retargetTimer = Math.random() + 2.0;
							pickFishTarget(f);
						}
					}
				}
				continue;
			}

			// Bobber interaction — checked before pause so fish always react to lures
			var closestDist = 1e20;
			var closestSid:String = null;
			var closestBX:Float = 0;
			var closestBY:Float = 0;
			var hasBobbers = false;
			var fcx = f.x + 8;
			var fcy = f.y + 8;
			// Is this fish in the hungry water body?
			var fishHungry = hungerTimer > 0 && hungerBodyIndex >= 0 && f.bodyIndex == hungerBodyIndex;
			for (sid => bpos in bobberPositions) {
				// During hunger, only attract to bobbers that are in water (shallow or deep)
				if (fishHungry) {
					var bcx = Std.int(bpos.x / collision.tileSize);
					var bcy = Std.int(bpos.y / collision.tileSize);
					var inWater = collision.isSwimmableAt(bcx, bcy)
						|| collision.isShallowAt(bpos.x, bpos.y);
					if (!inWater) { continue; }
				}
				hasBobbers = true;
				var dx = bpos.x - fcx;
				var dy = bpos.y - fcy;
				var dist = Math.sqrt(dx * dx + dy * dy);
				if (dist < closestDist) { closestDist = dist; closestSid = sid; closestBX = bpos.x; closestBY = bpos.y; }
			}

			if (f.attracted && !hasBobbers) { f.attracted = false; f.aiState = FishState.STATE_ROAMING; fleeFromFish(f, f.x + f.velX, f.y + f.velY); continue; }
			var attractDist = if (fishHungry) HUNGER_ATTRACT_DIST else FISH_ATTRACT_DIST;
			if (f.attracted && closestDist > attractDist) { f.attracted = false; f.aiState = FishState.STATE_ROAMING; fleeFromFish(f, closestBX, closestBY); continue; }
			if (hasBobbers && closestDist < FISH_CATCH_DIST) {
				f.alive = false; f.velX = 0; f.velY = 0; f.attracted = false; f.respawnTimer = 3.0;
				f.aiState = FishState.STATE_DEAD;
				var fishLen = 20 + Std.int(Math.random() * 40);
				var addedToInv = serverAddItem(closestSid, {type: "fish", fishType: f.fishType, lengthCm: fishLen});
				broadcast("fish_caught", {sessionId: closestSid, fishId: fid, fishType: f.fishType, inventoryFull: !addedToInv});
				bobberPositions.remove(closestSid);
				continue;
			}
			if (hasBobbers && closestDist < attractDist) {
				f.attracted = true; f.pauseTimer = 0; f.aiState = FishState.STATE_ATTRACTED;
				var dx = closestBX - fcx; var dy = closestBY - fcy;
				var aDist = Math.sqrt(dx * dx + dy * dy);
				if (aDist > 0.1) { f.velX = (dx / aDist) * FISH_ATTRACT_SPEED; f.velY = (dy / aDist) * FISH_ATTRACT_SPEED; }
				f.x += f.velX * t; f.y += f.velY * t;
				continue;
			}

			// Rocket fear — once triggered, fish flees perpendicular for the full duration
			if (f.rocketFeared) {
				f.retargetTimer -= t;
				// Check if next position is still in the water body
				var nextX = f.x + f.velX * t;
				var nextY = f.y + f.velY * t;
				var grid = collision.tileSize;
				var nextCol = Std.int((nextX + 8) / grid);
				var nextRow = Std.int((nextY + 8) / grid);
				if (collision.isSwimmableAt(nextCol, nextRow) || collision.isShallowAt(nextX + 8, nextY + 8)) {
					f.x = nextX;
					f.y = nextY;
				} else {
					// Hit the shore — stop moving but stay feared until timer runs out
					f.velX = 0;
					f.velY = 0;
				}
				if (f.retargetTimer <= 0) {
					f.rocketFeared = false;
					f.velX = 0;
					f.velY = 0;
					f.pauseTimer = 1.0; // pause before resuming roaming
					f.aiState = FishState.STATE_ROAMING;
				}
				continue;
			}

			// Check if a rocket triggers fear
			for (r in rockets) {
				var rdx = fcx - r.x;
				var rdy = fcy - r.y;
				var rdistSq = rdx * rdx + rdy * rdy;
				if (rdistSq < 40.0 * 40.0 && rdistSq > 0.01) {
					var perpX1 = -r.dirY;
					var perpY1 = r.dirX;
					var dot = perpX1 * rdx + perpY1 * rdy;
					f.velX = if (dot >= 0) perpX1 * FISH_SPEED * 2 else r.dirY * FISH_SPEED * 2;
					f.velY = if (dot >= 0) perpY1 * FISH_SPEED * 2 else -r.dirX * FISH_SPEED * 2;
					f.attracted = false;
					f.pauseTimer = 0;
					f.retargetTimer = 1.0;
					f.rocketFeared = true;
					f.aiState = FishState.STATE_FEARED;
					break;
				}
			}
			if (f.rocketFeared) {
				f.x += f.velX * t;
				f.y += f.velY * t;
				continue;
			}

			if (f.pauseTimer > 0) { f.pauseTimer -= t; continue; }

			// Wander
			var isBaitFish = baitTimer > 0 && baitBodyIndex >= 0 && f.bodyIndex == baitBodyIndex;
			f.aiState = if (isBaitFish) FishState.STATE_BAIT_ROAMING else FishState.STATE_ROAMING;
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
			if (!a.alive || a.aiState == FishState.STATE_BAIT_ROAMING || a.aiState == FishState.STATE_FEARED) { continue; }
			for (j in (i + 1)...fishStates.length) {
				var b = fishStates[j];
				if (!b.alive || b.aiState == FishState.STATE_BAIT_ROAMING || b.aiState == FishState.STATE_FEARED) { continue; }
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

		// When bait is active, fish in the SAME body pick targets within the bait oval
		if (baitTimer > 0 && baitBodyIndex >= 0 && f.bodyIndex == baitBodyIndex) {
			var candidates = new Array<{x:Float, y:Float}>();
			var grid = collision.tileSize;
			// Scan tiles within the bait oval bounds
			var minCol = Std.int((baitX - baitRadiusX) / grid);
			var maxCol = Std.int((baitX + baitRadiusX) / grid);
			var minRow = Std.int((baitY - baitRadiusY) / grid);
			var maxRow = Std.int((baitY + baitRadiusY) / grid);
			if (minCol < 0) { minCol = 0; }
			if (minRow < 0) { minRow = 0; }
			if (maxCol >= collision.cols) { maxCol = collision.cols - 1; }
			if (maxRow >= collision.rows) { maxRow = collision.rows - 1; }
			for (row in minRow...maxRow + 1) {
				for (col in minCol...maxCol + 1) {
					// Allow swimmable OR shallow tiles within the bait oval
					if (!collision.isSwimmableAt(col, row) && !collision.isShallowAt(col * grid + grid / 2.0, row * grid + grid / 2.0)) {
						continue;
					}
					var tx = col * grid + 2.0;
					var ty = row * grid + 2.0;
					var dx = (tx + 6) - baitX;
					var dy = (ty + 6) - baitY;
					if (dx * dx / (baitRadiusX * baitRadiusX) + dy * dy / (baitRadiusY * baitRadiusY) < 1) {
						candidates.push({x: tx, y: ty});
					}
				}
			}
			if (candidates.length > 0) {
				var tile = candidates[Std.int(Math.random() * candidates.length)];
				f.targetX = tile.x + Math.random() * 12;
				f.targetY = tile.y + Math.random() * 12;
				f.retargetTimer = 1.0 + Math.random();
				f.aiState = FishState.STATE_BAIT_ROAMING;
				return;
			}
		}

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
				f.scaredTimer = 0.5; f.attracted = false; f.aiState = FishState.STATE_SCARED;
				var len = Math.sqrt(dx * dx + dy * dy);
				if (len > 0.01) { f.velX = (dx / len) * FISH_SPEED * 1.5; f.velY = (dy / len) * FISH_SPEED * 1.5; }
			}
		}
	}

	// --- Seagulls ---

	/** Night window — birds and clouds stay away until morning. */
	public function isNight():Bool {
		return timeOfDayHour >= 21 || timeOfDayHour < 6;
	}

	function updateSeagulls(t:Float) {
		var worldWidth:Float = collision.cols * collision.tileSize;
		var worldHeight:Float = collision.rows * collision.tileSize;

		// No new birds at night — existing ones just finish flying away
		seagullSpawnTimer -= t;
		if (seagullSpawnTimer <= 0 && !isNight()) {
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

	// --- Dogs ---

	function updateDogs(t:Float) {
		if (!gameplayStarted) { return; }

		var worldW:Float = collision.cols * collision.tileSize;
		var worldH:Float = collision.rows * collision.tileSize;

		// Auto-spawn disabled — use debug button to spawn dogs
		// dogSpawnTimer -= t;
		// if (dogSpawnTimer <= 0) {
		// 	dogSpawnTimer = DOG_SPAWN_INTERVAL_MIN + Math.random() * (DOG_SPAWN_INTERVAL_MAX - DOG_SPAWN_INTERVAL_MIN);
		// 	spawnDog(worldW, worldH);
		// }

		// Periodic position broadcast
		dogUpdateTimer -= t;
		var shouldBroadcast = dogUpdateTimer <= 0;
		if (shouldBroadcast) { dogUpdateTimer = DOG_UPDATE_RATE; }

		// Update each dog
		var i = dogs.length - 1;
		while (i >= 0) {
			var dog = dogs[i];

			switch (dog.state) {
				case "fleeing":
					dog.x += dog.velX * t;
					dog.y += dog.velY * t;
					dog.fleeTimer -= t;
					if (dog.fleeTimer <= 0) {
						broadcast("dog_despawn", {id: dog.id});
						dogs.splice(i, 1);
					} else if (shouldBroadcast) {
						broadcast("dog_update", {id: dog.id, x: dog.x, y: dog.y, velX: dog.velX, velY: dog.velY});
					}

				case "waiting":
					// Waiting for items to land, or for client to send item drop info
					dog.waitTimer -= t;
					dog.velX = 0;
					dog.velY = 0;
					if (dog.waitTimer <= 0) {
						// If a fish target was set, go seek it; otherwise flee
						if (dog.fishTargetX != 0 || dog.fishTargetY != 0) {
							dog.state = "seeking";
							broadcast("dog_update", {id: dog.id, x: dog.x, y: dog.y, velX: 0, velY: 0});
						} else {
							startDogFlee(dog);
						}
					}

				case "seeking":
					// Walk toward the fish using pathfinding
					dog.path = findPath(dog.x, dog.y, dog.fishTargetX, dog.fishTargetY);
					dog.pathIndex = 0;
					var dx = dog.fishTargetX - dog.x;
					var dy = dog.fishTargetY - dog.y;
					var dist = Math.sqrt(dx * dx + dy * dy);
					if (dist <= DOG_FISH_PICKUP_DIST) {
						broadcast("dog_ate_fish", {id: dog.id, x: dog.fishTargetX, y: dog.fishTargetY});
						startDogFlee(dog);
					} else {
						moveDogAlongPath(dog, DOG_SEEK_SPEED, t);
					}
					if (shouldBroadcast) {
						broadcast("dog_update", {id: dog.id, x: dog.x, y: dog.y, velX: dog.velX, velY: dog.velY});
					}

				default: // "chasing"
					var closestDist = 1e20;
					var closestSid:String = null;
					var closestX:Float = dog.x;
					var closestY:Float = dog.y;
					for (sid => p in players) {
						// Target player visual center
						var pcx = p.x + p.width / 2;
						var pcy = p.y - 4;
						var dx = pcx - dog.x;
						var dy = pcy - dog.y;
						var dist = Math.sqrt(dx * dx + dy * dy);
						if (dist < closestDist) {
							closestDist = dist;
							closestSid = sid;
							closestX = pcx;
							closestY = pcy;
						}
					}
					dog.targetSession = closestSid;

					if (closestDist > DOG_CATCH_DIST) {
						// Recompute path every frame for responsive chasing
						dog.path = findPath(dog.x, dog.y, closestX, closestY);
						dog.pathIndex = 0;
						moveDogAlongPath(dog, DOG_SPEED, t);
					}

					if (closestDist <= DOG_CATCH_DIST && closestSid != null) {
						broadcast("dog_caught", {id: dog.id, sessionId: closestSid});
						dog.state = "waiting";
						dog.waitTimer = DOG_WAIT_TIMEOUT;
						dog.velX = 0;
						dog.velY = 0;
						dog.fishTargetX = 0;
						dog.fishTargetY = 0;
					}

					if (shouldBroadcast) {
						broadcast("dog_update", {id: dog.id, x: dog.x, y: dog.y, velX: dog.velX, velY: dog.velY});
					}
			}

			i--;
		}
	}

	function startDogFlee(dog:{id:Int, x:Float, y:Float, velX:Float, velY:Float, targetSession:String, state:String, fleeTimer:Float, fishTargetX:Float, fishTargetY:Float, waitTimer:Float, path:Array<{x:Float, y:Float}>, pathIndex:Int, pathCooldown:Float}) {
		dog.state = "fleeing";
		dog.fleeTimer = DOG_FLEE_DURATION;
		var fleeLen = Math.sqrt(dog.velX * dog.velX + dog.velY * dog.velY);
		if (fleeLen > 0.1) {
			dog.velX = (-dog.velX / fleeLen) * DOG_FLEE_SPEED;
			dog.velY = (-dog.velY / fleeLen) * DOG_FLEE_SPEED;
		} else {
			// No velocity — flee toward nearest world edge
			var worldW:Float = collision.cols * collision.tileSize;
			var distLeft = dog.x;
			var distRight = worldW - dog.x;
			if (distLeft < distRight) {
				dog.velX = -DOG_FLEE_SPEED;
			} else {
				dog.velX = DOG_FLEE_SPEED;
			}
			dog.velY = 0;
		}
		broadcast("dog_update", {id: dog.id, x: dog.x, y: dog.y, velX: dog.velX, velY: dog.velY});
	}

	public function spawnDog(worldW:Float, worldH:Float) {
		// Spawn from a random world edge
		var edge = Std.int(Math.random() * 4);
		var sx:Float = 0;
		var sy:Float = 0;
		switch (edge) {
			case 0: sx = -16; sy = Math.random() * worldH; // left
			case 1: sx = worldW + 16; sy = Math.random() * worldH; // right
			case 2: sx = Math.random() * worldW; sy = -16; // top
			case 3: sx = Math.random() * worldW; sy = worldH + 16; // bottom
		}
		var did = nextDogId++;
		dogs.push({
			id: did, x: sx, y: sy, velX: 0, velY: 0,
			targetSession: null, state: "chasing", fleeTimer: 0,
			fishTargetX: 0, fishTargetY: 0, waitTimer: 0,
			path: [], pathIndex: 0, pathCooldown: 0
		});
		broadcast("dog_spawn", {id: did, x: sx, y: sy});
	}

	function moveDogAlongPath(dog:{x:Float, y:Float, velX:Float, velY:Float, path:Array<{x:Float, y:Float}>, pathIndex:Int}, speed:Float, t:Float) {
		if (dog.path.length == 0 || dog.pathIndex >= dog.path.length) {
			dog.velX = 0;
			dog.velY = 0;
			return;
		}
		var wp = dog.path[dog.pathIndex];
		var dx = wp.x - dog.x;
		var dy = wp.y - dog.y;
		var dist = Math.sqrt(dx * dx + dy * dy);
		if (dist < 4) {
			dog.pathIndex++;
			return;
		}
		dog.velX = (dx / dist) * speed;
		dog.velY = (dy / dist) * speed;
		dog.x += dog.velX * t;
		dog.y += dog.velY * t;
	}

	/** Check if a straight line between two points is clear of obstacles for the dog. */
	function dogLineOfSight(x1:Float, y1:Float, x2:Float, y2:Float):Bool {
		var gs = collision.tileSize;
		var dx = x2 - x1;
		var dy = y2 - y1;
		var dist = Math.sqrt(dx * dx + dy * dy);
		if (dist < 1) { return true; }
		var steps = Math.ceil(dist / (gs * 0.5)); // check every half-tile
		for (i in 1...steps) {
			var t = i / steps;
			var px = x1 + dx * t;
			var py = y1 + dy * t;
			var col = Std.int(px / gs);
			var row = Std.int(py / gs);
			if (!isDogWalkable(col, row)) { return false; }
		}
		return true;
	}

	/** Simplify a path by removing waypoints that can be skipped via line-of-sight. */
	function smoothPath(path:Array<{x:Float, y:Float}>, fromX:Float, fromY:Float):Array<{x:Float, y:Float}> {
		if (path.length <= 1) { return path; }
		var result = new Array<{x:Float, y:Float}>();
		var current = {x: fromX, y: fromY};
		var i = 0;
		while (i < path.length) {
			// Look ahead as far as possible
			var farthest = i;
			for (j in (i + 1)...path.length) {
				if (dogLineOfSight(current.x, current.y, path[j].x, path[j].y)) {
					farthest = j;
				}
			}
			result.push(path[farthest]);
			current = path[farthest];
			i = farthest + 1;
		}
		return result;
	}

	/** A* pathfinding on the collision grid. Returns waypoints in world coords. */
	function findPath(fromX:Float, fromY:Float, toX:Float, toY:Float):Array<{x:Float, y:Float}> {
		// If direct line of sight exists, skip A* entirely
		if (dogLineOfSight(fromX, fromY, toX, toY)) {
			return [{x: toX, y: toY}];
		}

		var gs = collision.tileSize;
		var startCol = Std.int(fromX / gs);
		var startRow = Std.int(fromY / gs);
		var endCol = Std.int(toX / gs);
		var endRow = Std.int(toY / gs);

		// Clamp to grid
		if (startCol < 0) { startCol = 0; } if (startCol >= collision.cols) { startCol = collision.cols - 1; }
		if (startRow < 0) { startRow = 0; } if (startRow >= collision.rows) { startRow = collision.rows - 1; }
		if (endCol < 0) { endCol = 0; } if (endCol >= collision.cols) { endCol = collision.cols - 1; }
		if (endRow < 0) { endRow = 0; } if (endRow >= collision.rows) { endRow = collision.rows - 1; }

		if (startCol == endCol && startRow == endRow) {
			return [{x: toX, y: toY}];
		}

		// Also check if any bush rects block a tile
		var w = collision.cols;

		// A* with cardinal movement only
		var openList = new Array<Int>(); // packed as row * w + col
		var gScore = new haxe.ds.IntMap<Float>();
		var fScore = new haxe.ds.IntMap<Float>();
		var cameFrom = new haxe.ds.IntMap<Int>();

		var startKey = startRow * w + startCol;
		var endKey = endRow * w + endCol;
		openList.push(startKey);
		gScore.set(startKey, 0);
		fScore.set(startKey, heuristic(startCol, startRow, endCol, endRow));

		var maxIter = 2000; // cap to prevent lag on huge maps
		while (openList.length > 0 && maxIter-- > 0) {
			// Find lowest fScore in open list
			var bestIdx = 0;
			var bestF = fScore.exists(openList[0]) ? fScore.get(openList[0]) : 1e20;
			for (oi in 1...openList.length) {
				var f = fScore.exists(openList[oi]) ? fScore.get(openList[oi]) : 1e20;
				if (f < bestF) { bestF = f; bestIdx = oi; }
			}
			var current = openList[bestIdx];
			if (current == endKey) {
				// Reconstruct and smooth path
				var rawPath = reconstructPath(cameFrom, current, w, gs, toX, toY);
				return smoothPath(rawPath, fromX, fromY);
			}
			openList[bestIdx] = openList[openList.length - 1];
			openList.pop();

			var cx = current % w;
			var cy = Std.int(current / w);
			var curG = gScore.exists(current) ? gScore.get(current) : 1e20;

			for (d in [{dx: 0, dy: -1}, {dx: 0, dy: 1}, {dx: -1, dy: 0}, {dx: 1, dy: 0}]) {
				var nx = cx + d.dx;
				var ny = cy + d.dy;
				if (nx < 0 || nx >= collision.cols || ny < 0 || ny >= collision.rows) { continue; }
				// Allow the end tile even if not walkable (dog needs to reach the player)
				var nKey = ny * w + nx;
				if (nKey != endKey && !isDogWalkable(nx, ny)) { continue; }

				var tentG = curG + 1;
				var prevG = gScore.exists(nKey) ? gScore.get(nKey) : 1e20;
				if (tentG < prevG) {
					cameFrom.set(nKey, current);
					gScore.set(nKey, tentG);
					fScore.set(nKey, tentG + heuristic(nx, ny, endCol, endRow));
					// Add to open list if not already there
					var inOpen = false;
					for (o in openList) { if (o == nKey) { inOpen = true; break; } }
					if (!inOpen) { openList.push(nKey); }
				}
			}
		}

		// No path found — fall back to direct movement
		return [{x: toX, y: toY}];
	}

	/** Post-process A* result: smooth the grid-aligned path into direct lines. */
	function postProcessPath(path:Array<{x:Float, y:Float}>, fromX:Float, fromY:Float):Array<{x:Float, y:Float}> {
		return smoothPath(path, fromX, fromY);
	}

	function isDogWalkable(col:Int, row:Int):Bool {
		if (!collision.isWalkableAt(col, row)) { return false; }
		// Also check bush entity rects
		var gs = collision.tileSize;
		var tx = col * gs;
		var ty = row * gs;
		for (b in bushRects) {
			if (b.w <= 0 || b.h <= 0) { continue; }
			if (tx + gs > b.x && tx < b.x + b.w && ty + gs > b.y && ty < b.y + b.h) {
				return false;
			}
		}
		return true;
	}

	static function heuristic(ax:Int, ay:Int, bx:Int, by:Int):Float {
		return Math.abs(ax - bx) + Math.abs(ay - by); // Manhattan distance
	}

	function reconstructPath(cameFrom:haxe.ds.IntMap<Int>, current:Int, w:Int, gs:Int, finalX:Float, finalY:Float):Array<{x:Float, y:Float}> {
		var path = new Array<{x:Float, y:Float}>();
		path.push({x: finalX, y: finalY}); // exact target as final waypoint
		var node = current;
		while (cameFrom.exists(node)) {
			var prev = cameFrom.get(node);
			// Convert grid coords to world center
			var cx = (node % w) * gs + gs / 2.0;
			var cy = Std.int(node / w) * gs + gs / 2.0;
			path.push({x: cx, y: cy});
			node = prev;
		}
		path.reverse();
		return path;
	}

	// ── Power-Up ──

	function updatePowerUp(t:Float) {
		if (!gameplayStarted) { return; }

		if (!powerUpAlive) {
			powerUpRespawnTimer -= t;
			if (powerUpRespawnTimer <= 0) {
				spawnPowerUp();
			}
			return;
		}

		// Check player pickup
		for (id => p in players) {
			var dx = (p.x + p.width / 2) - powerUpX;
			var dy = (p.y + p.height / 2) - powerUpY;
			if (dx * dx + dy * dy < 14 * 14) {
				powerUpAlive = false;
				powerUpRespawnTimer = POWERUP_RESPAWN_DELAY;
				serverAddItem(id, {type: "rocket"});
				broadcast("powerup_pickup", {sessionId: id});
				break;
			}
		}
	}

	function spawnPowerUp() {
		// Pick a random walkable tile
		var grid = collision.tileSize;
		for (_ in 0...100) {
			var cx = Std.int(Math.random() * collision.cols);
			var cy = Std.int(Math.random() * collision.rows);
			if (collision.isWalkableAt(cx, cy)) {
				powerUpX = cx * grid + grid / 2.0;
				powerUpY = cy * grid + grid / 2.0;
				powerUpAlive = true;
				broadcast("powerup_spawn", {x: powerUpX, y: powerUpY});
				return;
			}
		}
	}

	// ── Rockets ──

	function updateRockets(t:Float) {
		var worldW:Float = collision.cols * collision.tileSize;
		var worldH:Float = collision.rows * collision.tileSize;
		var i = rockets.length;
		while (i-- > 0) {
			var r = rockets[i];
			// Accelerate
			r.speed += ROCKET_ACCELERATION * t;
			if (r.speed > ROCKET_MAX_SPEED) { r.speed = ROCKET_MAX_SPEED; }
			r.x += r.dirX * r.speed * t;
			r.y += r.dirY * r.speed * t;

			// Check out of bounds
			if (r.x < -16 || r.x > worldW + 16 || r.y < -16 || r.y > worldH + 16) {
				broadcast("rocket_despawn", {id: r.id});
				rockets.splice(i, 1);
				continue;
			}

			// Check collision with players
			var hit = false;
			for (pid => p in players) {
				if (pid == r.ownerSession) { continue; } // can't hit yourself
				var dx = r.x - (p.x + p.width / 2);
				var dy = r.y - (p.y + p.height / 2);
				if (dx * dx + dy * dy < ROCKET_HIT_DIST * ROCKET_HIT_DIST) {
					broadcast("rocket_hit", {id: r.id, targetSessionId: pid, shooterSessionId: r.ownerSession});
					rockets.splice(i, 1);
					hit = true;
					break;
				}
			}
			if (hit) { continue; }

			// Fish scare is handled inside updateFish() so it takes priority over wander
		}
	}

	// ── Server Inventory ──

	/**
	 * Sell every player's unsold fish and broadcast the post-round summary.
	 * Payload per player: {sessionId, name, skinIndex, score (PRE-sale), fish: [{fishType, lengthCm, value}]}.
	 * The payout is applied to PlayerState.score here (server-authoritative) —
	 * clients only animate the conveyor/counting from this payload.
	**/
	function broadcastRoundSummary() {
		var entries:Array<Dynamic> = [];
		for (id => p in players) {
			var fishList:Array<Dynamic> = [];
			var total = 0;
			var inv = inventories.get(id);
			if (inv != null) {
				var i = 0;
				while (i < inv.length) {
					if (inv[i].type == "fish") {
						var ft = inv[i].fishType != null ? inv[i].fishType : 0;
						var len = inv[i].lengthCm != null ? inv[i].lengthCm : 20;
						var v = FishValue.calculateValue(ft, len);
						fishList.push({fishType: ft, lengthCm: len, value: v});
						total += v;
						inv.splice(i, 1);
					} else {
						i++;
					}
				}
				sendInventoryUpdate(id);
			}
			entries.push({sessionId: id, name: p.name, skinIndex: p.skinIndex, score: p.score, fish: fishList});
			p.score += total;
		}
		broadcast("round_summary", {players: entries});
	}

	function serverAddItem(clientId:String, item:{type:String, ?fishType:Int, ?lengthCm:Int, ?big:Bool, ?debug:Bool}):Bool {
		var inv = inventories.get(clientId);
		if (inv == null) { return false; }
		if (inv.length >= MAX_INVENTORY) { return false; }
		inv.push(item);
		sendInventoryUpdate(clientId);
		return true;
	}

	function serverRemoveItem(clientId:String, type:String, force:Bool = false):Bool {
		var inv = inventories.get(clientId);
		if (inv == null) { return false; }
		for (i in 0...inv.length) {
			if (inv[i].type == type) {
				if (!force && inv[i].debug == true) {
					// debug-granted item — pretend it was consumed so the action still
					// fires, but keep it. Only the debug button (force) removes it.
					return true;
				}
				inv.splice(i, 1);
				sendInventoryUpdate(clientId);
				return true;
			}
		}
		return false;
	}

	function serverHasItem(clientId:String, type:String):Bool {
		var inv = inventories.get(clientId);
		if (inv == null) { return false; }
		for (item in inv) {
			if (item.type == type) { return true; }
		}
		return false;
	}

	function serverInventoryFull(clientId:String):Bool {
		var inv = inventories.get(clientId);
		if (inv == null) { return true; }
		return inv.length >= MAX_INVENTORY;
	}

	function serverClearInventory(clientId:String):Array<{type:String, ?fishType:Int, ?lengthCm:Int, ?big:Bool, ?debug:Bool}> {
		var inv = inventories.get(clientId);
		if (inv == null) { return []; }
		var items = inv.copy();
		inv.splice(0, inv.length);
		sendInventoryUpdate(clientId);
		return items;
	}

	function sendInventoryUpdate(clientId:String) {
		var inv = inventories.get(clientId);
		if (inv == null) { return; }
		sendToClient(clientId, "inventory_update", {items: inv});
	}
}
