import schema.GameState;
import PInput.P_Input;
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
	var lobbySimulation:Simulation;
	var gameSimulation:Simulation;
	var elapsedTime:Float;

	// Fish AI data
	var waterBodies:Array<Array<{x:Float, y:Float}>>; // water tile positions per body
	var bobberPositions:Map<String, {x:Float, y:Float}>; // sessionId -> bobber pos
	var hotModePlayers:Map<String, Bool>; // sessionId -> on fire
	var wadersPlayers:Map<String, Bool>; // sessionId -> has waders
	var bushRects:Array<{x:Float, y:Float, w:Float, h:Float}>; // bush collision rects
	var nextFishID:Int;
	var ldtkRaw:Dynamic; // cached level data for flood-fill

	// Dog AI data — states: "chasing", "waiting", "seeking", "fleeing"
	var dogs:Array<{
		id:Int, x:Float, y:Float, velX:Float, velY:Float,
		targetSession:String, state:String, fleeTimer:Float,
		fishTargetX:Float, fishTargetY:Float, waitTimer:Float
	}>;
	var nextDogId:Int;
	var dogSpawnTimer:Float;
	var dogUpdateTimer:Float;
	static var DOG_SPEED:Float = 50;
	static var DOG_SEEK_SPEED:Float = 40;
	static var DOG_FLEE_SPEED:Float = 80;
	static var DOG_CATCH_DIST:Float = 10;
	static var DOG_FISH_PICKUP_DIST:Float = 6;
	static var DOG_UPDATE_RATE:Float = 0.15;
	static var DOG_FLEE_DURATION:Float = 5.0;
	static var DOG_WAIT_TIMEOUT:Float = 2.0;
	static var DOG_ITEM_DROP_RADIUS:Float = 36.0;

	// Cached world data for late joiners
	var cachedWorldItems:Dynamic;
	var cachedSpawnLocations:Dynamic;

	// Worm spawning data
	var wormTimer:Float;
	var nextWormId:Int;

	// Round timer (server-authoritative)
	var roundTimerSec:Float;
	var roundDurationSec:Float;
	var timerSyncCooldown:Float;
	var gameplayStarted:Bool;

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
	var windAngle:Float;
	var clouds:Array<{id:Int, x:Float, y:Float, velX:Float, velY:Float, scale:Float}>;

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

		// Build collision maps for both levels
		var hitboxJson = sys.io.File.getContent("../assets/data/tile-hitboxes.json");
		var ldtkProject = new LdtkProject();

		var lobbyRaw = ldtkProject.getLevel("Lobby");
		var lobbyCol = CollisionMap.fromLevel(lobbyRaw, hitboxJson);
		lobbySimulation = new Simulation(lobbyCol);

		var raw = ldtkProject.getLevel("Level_0");
		ldtkRaw = raw;
		state.collision = CollisionMap.fromLevel(raw, hitboxJson);
		gameSimulation = new Simulation(state.collision);

		// Start in lobby simulation
		simulation = lobbySimulation;
		state.inputQueue = new Map();

		// Initialize fish AI data
		waterBodies = [];
		bobberPositions = new Map();
		hotModePlayers = new Map();
		wadersPlayers = new Map();
		bushRects = [];
		nextFishID = 1;

		// Initialize worm data
		wormTimer = 999; // don't spawn until a client requests via "start_gameplay"
		nextWormId = 1;

		dogs = [];
		nextDogId = 1;
		dogSpawnTimer = 10.0;
		dogUpdateTimer = 0;

		// Initialize round timer
		roundTimerSec = 0;
		roundDurationSec = 90;
		timerSyncCooldown = 5.0;
		gameplayStarted = false;

		// Initialize seagull data
		seagulls = [];
		nextSeagullId = 1;
		seagullSpawnTimer = 999; // don't spawn until a client requests via "start_gameplay"

		// Pick wind angle and spawn clouds — sent to each client on join
		windAngle = Math.random() * Math.PI * 2;
		var worldW = state.collision.cols * state.collision.tileSize;
		var worldH = state.collision.rows * state.collision.tileSize;
		clouds = [];
		for (i in 0...5) {
			var s = 1.0 + Math.random() * 2.0;
			var speed = 8 + Math.random() * 8;
			var dx = Math.cos(windAngle) * speed;
			var dy = Math.sin(windAngle) * speed;
			// scatter across world
			var cx = Math.random() * worldW;
			var cy = Math.random() * worldH;
			clouds.push({id: i, x: cx, y: cy, velX: dx, velY: dy, scale: s});
		}

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

		// Client tells server its spawn position (lobby uses client-side collision map)
		onMessage("set_position", (client:Client, data:Dynamic) -> {
			var ps = state.players.get(client.sessionId);
			if (ps != null) {
				ps.x = data.x;
				ps.y = data.y;
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

		// Client signals PlayState is loaded — start spawning creatures and world items
		onMessage("start_gameplay", (client:Client, _) -> {
			if (!gameplayStarted) {
				// Switch to game-level collision map
				simulation = gameSimulation;
				// New round (or first round): reset and respawn everything
				resetRoundState();
				spawnWorldItems();
				gameplayStarted = true;
				roundTimerSec = 0;
			}
			// Send cached data to this specific client
			if (cachedWorldItems != null) {
				client.send("world_items", cachedWorldItems);
			}
			if (cachedSpawnLocations != null) {
				client.send("spawn_locations", cachedSpawnLocations);
			}
			client.send("timer_sync", {runTimeSec: roundTimerSec, totalSec: roundDurationSec});
			// Always send clouds and existing seagulls
			client.send("cloud_sync", {angle: windAngle, clouds: clouds});
			for (gull in seagulls) {
				client.send("seagull_spawn", {id: gull.id, x: gull.x, y: gull.y, velX: gull.velX, velY: gull.velY, altitude: gull.altitude});
			}
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
			var requestedSkin:Int = data.skinIndex;
			// Enforce one skin per player — reject if taken by someone else
			var taken = false;
			for (sId => p in state.players) {
				if (sId != client.sessionId && p.skinIndex == requestedSkin) {
					taken = true;
					break;
				}
			}
			if (taken) {
				// Find first available skin and assign that instead
				var numSkins = 8; // Player.SKINS.length
				for (i in 0...numSkins) {
					var inUse = false;
					for (sId => p in state.players) {
						if (sId != client.sessionId && p.skinIndex == i) { inUse = true; break; }
					}
					if (!inUse) { requestedSkin = i; break; }
				}
			}
			trace('${client.sessionId}: skin_changed -> ${requestedSkin}');
			var player:PlayerState = state.players.get(client.sessionId);
			if (player != null) {
				player.skinIndex = requestedSkin;
			}
			// Always tell the requesting client what skin they got (may differ from request)
			client.send("skin_assigned", {skinIndex: requestedSkin});
		});

		// sent when a player's score changes
		onMessage("score_update", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "score_update" message: score=${data.score}');
			var player:PlayerState = state.players.get(client.sessionId);
			if (player != null) {
				player.score = data.score;
			}
		});

		// sent when a player picks up a world item (rock, waders, pepper)
		onMessage("item_pickup", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "item_pickup": itemType=${data.itemType} index=${data.index}');
			if (data.itemType == "waders") {
				wadersPlayers.set(client.sessionId, true);
			} else if (data.itemType == "waders_remove") {
				wadersPlayers.remove(client.sessionId);
			}
			broadcast("item_pickup", {sessionId: client.sessionId, itemType: data.itemType, index: data.index}, {except: client});
		});

		// sent when a player bursts a weed
		// Tier 2: server validates weed burst and broadcasts to ALL (including sender for score)
		onMessage("weed_burst", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "weed_burst": index=${data.index}');
			broadcast("weed_burst", {sessionId: client.sessionId, index: data.index});
		});

		// sent when a hot player drowns in water
		onMessage("player_drown", (client:Client, data:Dynamic) -> {
			broadcast("player_drown", {sessionId: client.sessionId, x: data.x, y: data.y}, {except: client});
		});

		// bush_rustle removed — Tier 1 cosmetic, handled client-side only

		// sent when a hot player ignites a bush
		onMessage("bush_ignite", (client:Client, data:Dynamic) -> {
			broadcast("bush_ignite", {index: data.index}, {except: client});
		});

		// sent when a bush finishes burning and despawns — remove its collision rect
		onMessage("bush_dead", (client:Client, data:Dynamic) -> {
			var idx:Int = data.index;
			if (idx >= 0 && idx < bushRects.length) {
				bushRects[idx] = {x: 0.0, y: 0.0, w: 0.0, h: 0.0};
				simulation.entityRects = bushRects;
			}
		});

		// sent when a hot player ignites a weed
		onMessage("weed_ignite", (client:Client, data:Dynamic) -> {
			broadcast("weed_ignite", {index: data.index}, {except: client});
		});

		// sent when a player kills a worm
		onMessage("worm_killed", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "worm_killed" id=${data.id}');
			broadcast("worm_killed", {sessionId: client.sessionId, id: data.id}, {except: client});
		});

		// sent when a player activates or deactivates hot pepper mode
		onMessage("hot_pepper", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "hot_pepper": isStart=${data.isStart}');
			var isStart:Bool = data.isStart;
			hotModePlayers.set(client.sessionId, isStart);
			var ps = state.players.get(client.sessionId);
			if (ps != null) {
				ps.speed = isStart ? 150 : 100;
			}
			broadcast("hot_pepper", {sessionId: client.sessionId, isStart: isStart}, {except: client});
		});

		// timer_sync is now server-originated (see fixedTick); no client relay needed

		// debug: force end the current round
		onMessage("dog_item_drop", (client:Client, data:Dynamic) -> {
			var px:Float = data.playerX;
			var py:Float = data.playerY;
			var dogId:Int = data.dogId;
			var items:Array<Dynamic> = data.items;
			var firstFishX:Float = 0;
			var firstFishY:Float = 0;
			var hasFish = false;
			if (items != null) {
				var count = items.length;
				for (j in 0...count) {
					var angle = (j / count) * Math.PI * 2 + Math.random() * 0.3;
					var dist = DOG_ITEM_DROP_RADIUS + Math.random() * 12;
					var landX = px + Math.cos(angle) * dist;
					var landY = py + Math.sin(angle) * dist;
					broadcast("dog_item_landed", {
						startX: px, startY: py,
						landX: landX, landY: landY,
						itemType: items[j].type,
						itemData: items[j].data
					});
					if (!hasFish && items[j].type == "fish") {
						firstFishX = landX;
						firstFishY = landY;
						hasFish = true;
					}
				}
			}
			for (dog in dogs) {
				if (dog.id == dogId) {
					if (hasFish) {
						dog.state = "seeking";
						dog.fishTargetX = firstFishX;
						dog.fishTargetY = firstFishY;
					} else {
						startDogFleeServer(dog);
					}
					break;
				}
			}
		});

		onMessage("dog_no_fish", (client:Client, data:Dynamic) -> {
			var dogId:Int = data.dogId;
			for (dog in dogs) {
				if (dog.id == dogId) {
					startDogFleeServer(dog);
					break;
				}
			}
		});

		onMessage("debug_spawn_dog", (client:Client, _) -> {
			trace('${client.sessionId}: debug_spawn_dog');
			var worldW = state.collision.cols * state.collision.tileSize;
			var worldH = state.collision.rows * state.collision.tileSize;
			var edge = Std.int(Math.random() * 4);
			var sx:Float = switch (edge) { case 0: -16; case 1: worldW + 16; default: Math.random() * worldW; };
			var sy:Float = switch (edge) { case 2: -16; case 3: worldH + 16; default: Math.random() * worldH; };
			var did = nextDogId++;
			dogs.push({id: did, x: sx, y: sy, velX: 0, velY: 0, targetSession: null, state: "chasing", fleeTimer: 0, fishTargetX: 0, fishTargetY: 0, waitTimer: 0});
			broadcast("dog_spawn", {id: did, x: sx, y: sy});
		});

		onMessage("debug_end_round", (client:Client, _) -> {
			trace('${client.sessionId}: debug_end_round');
			if (gameplayStarted) {
				broadcast("round_time_up", {});
				gameplayStarted = false;
				// Also transition server round status so ready-up flow works
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

		// fish_caught relay removed — server detects catches directly in updateFish

		// sent when a player pulls in their line
		onMessage("line_pulled", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "line_pulled" message');
			broadcast("line_pulled", {sessionId: client.sessionId});
		});

		onMessage("round_update", (client:Client, data:Dynamic) -> {
			if (data == null) { return; }
			// Ignore duplicate status transitions from multiple clients
			var newStatus = data.status != null ? data.status : state.round.status;
			var newRound = data.currentRound != null ? (data.currentRound : Int) : state.round.currentRound;
			var newTotal = data.totalRounds != null ? (data.totalRounds : Int) : state.round.totalRounds;
			if (newStatus == state.round.status && newRound == state.round.currentRound && newTotal == state.round.totalRounds) {
				return; // no change
			}
			trace('${client.sessionId}: round_update ${state.round.status} -> ${newStatus}');
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

			// Disconnect room if no players remain
			if (state.players.size <= 0) {
				disconnect();
				return;
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
		// Set player hitbox dimensions and spawn position
		var ps = state.players.get(client.sessionId);
		ps.speed = 100;
		ps.width = 16;
		ps.height = 8;
		// Initial position — client sends set_position with lobby spawn shortly after
		var rawObjects:Dynamic = Reflect.getProperty(ldtkRaw, "l_Objects");
		var allSpawn:Array<Dynamic> = Reflect.getProperty(rawObjects, "all_Spawn");
		if (allSpawn != null && allSpawn.length > 0) {
			ps.x = allSpawn[0].pixelX;
			ps.y = allSpawn[0].pixelY;
		}


		// Cloud sync is requested by client after PlayState loads
		// (can't send on join — onMsg handlers aren't registered yet)

		return null;
	}

	override public function onLeave(client:Client, ?code:CloseCode):EitherType<Void, Promise<Dynamic>> {
		trace('player left: ${client.sessionId}');
		trace('successful clear: ${state.players.delete(client.sessionId)}');
		state.inputQueue.remove(client.sessionId);

		// Remove player tracking
		bobberPositions.remove(client.sessionId);
		hotModePlayers.remove(client.sessionId);
		wadersPlayers.remove(client.sessionId);

		// Disconnect room when empty
		if (state.players.size <= 0) {
			trace('disconnect room: ${roomId}:${roomName}');
			disconnect();
		}

		return null;
	}

	/** Reset all transient round state so a fresh round starts clean. */
	function resetRoundState() {
		// Clear fish schema and respawn
		var fishIds:Array<String> = [];
		for (id => _ in state.fish) { fishIds.push(id); }
		trace('resetRoundState: clearing ${fishIds.length} fish');
		for (id in fishIds) { state.fish.delete(id); }
		nextFishID = 1;
		spawnFish();

		// Clear bushes schema
		var bushIds:Array<String> = [];
		for (id => _ in state.bushes) { bushIds.push(id); }
		for (id in bushIds) { state.bushes.delete(id); }

		// Clear seagulls
		seagulls = [];

		// Reset spawn timers
		seagullSpawnTimer = 3.0;
		wormTimer = 3.0;
		timerSyncCooldown = 5.0;

		// Reset bobber tracking
		bobberPositions = new Map();

		// New wind and clouds
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

		// Clear cached world data
		cachedWorldItems = null;
		cachedSpawnLocations = null;

		// Reset player scores
		for (_ => p in state.players) {
			p.score = 0;
			p.ready = false;
		}

		trace('resetRoundState: cleared fish, bushes, seagulls, clouds, scores');
	}

	/** Server picks all world item positions and broadcasts them to all clients.
	    Called once from the first start_gameplay message. */
	function spawnWorldItems() {
		var col = state.collision;
		var w = col.cols;
		var h = col.rows;
		var grid = col.tileSize;

		// Collect grass tiles (no flags, has a tile) and walkable tiles (not solid/shallow/swimmable)
		var grassTiles = new Array<{cx:Int, cy:Int}>();
		var walkableTiles = new Array<{cx:Int, cy:Int}>();
		for (row in 0...h) {
			for (c in 0...w) {
				if (col.isGrassAt(c, row)) {
					grassTiles.push({cx: c, cy: row});
				}
				if (col.isWalkableAt(c, row)) {
					walkableTiles.push({cx: c, cy: row});
				}
			}
		}
		trace('spawnWorldItems: grassTiles=${grassTiles.length} walkableTiles=${walkableTiles.length}');

		// --- Bushes: 5 on grass tiles ---
		var bushPositions = new Array<{x:Float, y:Float}>();
		for (_ in 0...5) {
			if (grassTiles.length == 0) { break; }
			var idx = Std.int(Math.random() * grassTiles.length);
			var tile = grassTiles[idx];
			var bx = tile.cx * grid + Math.random() * (grid - 8);
			var by = tile.cy * grid + Math.random() * (grid - 8);
			bushPositions.push({x: bx, y: by});
		}
		// Store bushes in schema so late joiners get them via onAdd
		// Build server-side collision rects (matching client Bush hitbox: 14x6, offset 9,20)
		bushRects = [];
		for (i in 0...bushPositions.length) {
			var bp = bushPositions[i];
			state.bushes.set(Std.string(i), new BushState(bp.x, bp.y));
			bushRects.push({x: bp.x + 2, y: bp.y + 2, w: 10.0, h: 2.0});
		}
		simulation.entityRects = bushRects;
		trace('spawnWorldItems: placed ${bushPositions.length} bushes');

		// --- Weeds: 20 on walkable tiles (grass or dirt) ---
		var weedPositions = new Array<{x:Float, y:Float}>();
		for (_ in 0...20) {
			if (walkableTiles.length == 0) { break; }
			var idx = Std.int(Math.random() * walkableTiles.length);
			var tile = walkableTiles[idx];
			var wx = tile.cx * grid + Math.random() * (grid - 8);
			var wy = tile.cy * grid + Math.random() * (grid - 8);
			weedPositions.push({x: wx, y: wy});
		}

		// --- Rocks: 3-8 on walkable tiles ---
		var numRocks = 3 + Std.int(Math.random() * 6);
		var rockPositions = new Array<{x:Float, y:Float, big:Bool}>();
		var hasBigRock = false;
		for (_ in 0...numRocks) {
			if (walkableTiles.length == 0) { break; }
			var idx = Std.int(Math.random() * walkableTiles.length);
			var tile = walkableTiles[idx];
			var rx = tile.cx * grid + Math.random() * (grid - 8);
			var ry = tile.cy * grid + Math.random() * (grid - 8);
			var big = Math.random() < 0.2;
			if (big) { hasBigRock = true; }
			rockPositions.push({x: rx, y: ry, big: big});
		}
		// guarantee at least one big rock
		if (!hasBigRock && rockPositions.length > 0) {
			rockPositions[0].big = true;
		}

		// --- Waders: 1 on a walkable tile ---
		var wadersX:Null<Float> = null;
		var wadersY:Null<Float> = null;
		if (walkableTiles.length > 0) {
			var idx = Std.int(Math.random() * walkableTiles.length);
			var tile = walkableTiles[idx];
			wadersX = tile.cx * grid + grid / 2.0;
			wadersY = tile.cy * grid + grid / 2.0;
		}

		// --- Pepper: 1 on a walkable tile ---
		var pepperX:Null<Float> = null;
		var pepperY:Null<Float> = null;
		if (walkableTiles.length > 0) {
			var idx = Std.int(Math.random() * walkableTiles.length);
			var tile = walkableTiles[idx];
			pepperX = tile.cx * grid + grid / 2.0;
			pepperY = tile.cy * grid + grid / 2.0;
		}

		// Build and cache world_items payload
		var worldData:Dynamic = {
			rocks: rockPositions,
			weeds: weedPositions,
		};
		if (wadersX != null && wadersY != null) {
			worldData.wadersX = wadersX;
			worldData.wadersY = wadersY;
		}
		if (pepperX != null && pepperY != null) {
			worldData.pepperX = pepperX;
			worldData.pepperY = pepperY;
		}
		cachedWorldItems = worldData;
		trace('spawnWorldItems: cached world_items (${rockPositions.length} rocks, ${weedPositions.length} weeds)');

		// --- Spawn locations: use LDTK spawn point for all players ---
		var rawObjects:Dynamic = Reflect.getProperty(ldtkRaw, "l_Objects");
		var allSpawn:Array<Dynamic> = Reflect.getProperty(rawObjects, "all_Spawn");
		var sx:Float = 48.0;
		var sy:Float = 48.0;
		if (allSpawn != null && allSpawn.length > 0) {
			sx = allSpawn[0].pixelX;
			sy = allSpawn[0].pixelY;
		}

		var spawnData:Dynamic = {};
		var playerIndex = 0;
		for (sId => _ in state.players) {
			Reflect.setField(spawnData, sId, {x: sx, y: sy});
			// set server-side PlayerState position so simulation starts correctly
			var ps = state.players.get(sId);
			if (ps != null) {
				ps.x = sx;
				ps.y = sy;
			}
			playerIndex++;
		}
		cachedSpawnLocations = spawnData;
		trace('spawnWorldItems: cached spawn_locations at (${sx}, ${sy}) for $playerIndex players');
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

			// Fish shadow is 16x16; use center for distance checks
			var fcx = fish.x + 8;
			var fcy = fish.y + 8;
			for (sid => bpos in bobberPositions) {
				hasBobbers = true;
				var dx = bpos.x - fcx;
				var dy = bpos.y - fcy;
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
				// Attract toward closest bobber — use center-to-center
				fish.attracted = true;
				fish.pauseTimer = 0;
				var dx = closestBX - fcx;
				var dy = closestBY - fcy;
				var aDist = Math.sqrt(dx * dx + dy * dy);
				if (aDist > 0.1) {
					fish.velX = (dx / aDist) * FISH_ATTRACT_SPEED;
					fish.velY = (dy / aDist) * FISH_ATTRACT_SPEED;
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

	/** Spawn worms on valid ground tiles at regular intervals. */
	function updateWorms(t:Float) {
		wormTimer -= t;
		if (wormTimer > 0) {
			return;
		}
		wormTimer = 2.5 + Math.random() * 2.0;

		var col = state.collision;
		var w = col.cols;
		var h = col.rows;
		var grid = col.tileSize;

		// try to find a valid dirt spawn point
		for (_ in 0...50) {
			var cx = Std.int(Math.random() * w);
			var cy = Std.int(Math.random() * h);
			if (!col.isDirtAt(cx, cy)) {
				continue;
			}

			var srcX = cx * grid + Math.random() * grid;
			var srcY = cy * grid + Math.random() * grid;

			// pick destination 2-4 tiles left or right, must also be dirt
			var dir = if (Math.random() > 0.5) 1 else -1;
			var dist = 2 + Std.int(Math.random() * 3);
			var destCx = cx + dir * dist;
			var destCy = cy;
			if (destCx < 0 || destCx >= w || destCy < 0 || destCy >= h) {
				continue;
			}
			if (!col.isDirtAt(destCx, destCy)) {
				continue;
			}

			// verify path is all dirt
			var pathOk = true;
			var stepDir = if (dir > 0) 1 else -1;
			var step = cx + stepDir;
			while (step != destCx) {
				if (!col.isDirtAt(step, cy)) {
					pathOk = false;
					break;
				}
				step += stepDir;
			}
			if (!pathOk) {
				continue;
			}

			var destX = destCx * grid + Math.random() * grid;
			var destY = destCy * grid + Math.random() * grid;

			broadcast("worm_spawn", {id: nextWormId++, srcX: srcX, srcY: srcY, destX: destX, destY: destY});
			break;
		}
	}

	function updateDogs(t:Float) {
		if (!gameplayStarted) { return; }

		dogUpdateTimer -= t;
		var shouldBroadcast = dogUpdateTimer <= 0;
		if (shouldBroadcast) { dogUpdateTimer = DOG_UPDATE_RATE; }

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
					dog.waitTimer -= t;
					dog.velX = 0; dog.velY = 0;
					if (dog.waitTimer <= 0) { startDogFleeServer(dog); }
				case "seeking":
					var dx = dog.fishTargetX - dog.x;
					var dy = dog.fishTargetY - dog.y;
					var dist = Math.sqrt(dx * dx + dy * dy);
					if (dist <= DOG_FISH_PICKUP_DIST) {
						broadcast("dog_ate_fish", {id: dog.id, x: dog.fishTargetX, y: dog.fishTargetY});
						startDogFleeServer(dog);
					} else {
						dog.velX = (dx / dist) * DOG_SEEK_SPEED;
						dog.velY = (dy / dist) * DOG_SEEK_SPEED;
						dog.x += dog.velX * t;
						dog.y += dog.velY * t;
					}
					if (shouldBroadcast) {
						broadcast("dog_update", {id: dog.id, x: dog.x, y: dog.y, velX: dog.velX, velY: dog.velY});
					}
				default: // chasing
					var closestDist = 1e20;
					var closestSid:String = null;
					var closestX:Float = dog.x;
					var closestY:Float = dog.y;
					for (sid => p in state.players) {
						var dx = p.x - dog.x;
						var dy = p.y - dog.y;
						var dist = Math.sqrt(dx * dx + dy * dy);
						if (dist < closestDist) { closestDist = dist; closestSid = sid; closestX = p.x; closestY = p.y; }
					}
					if (closestDist > DOG_CATCH_DIST) {
						var dx = closestX - dog.x;
						var dy = closestY - dog.y;
						dog.velX = (dx / closestDist) * DOG_SPEED;
						dog.velY = (dy / closestDist) * DOG_SPEED;
						dog.x += dog.velX * t;
						dog.y += dog.velY * t;
					}
					if (closestDist <= DOG_CATCH_DIST && closestSid != null) {
						broadcast("dog_caught", {id: dog.id, sessionId: closestSid});
						dog.state = "waiting";
						dog.waitTimer = 2.0;
						dog.velX = 0; dog.velY = 0;
					}
					if (shouldBroadcast) {
						broadcast("dog_update", {id: dog.id, x: dog.x, y: dog.y, velX: dog.velX, velY: dog.velY});
					}
			}
			i--;
		}
	}

	function startDogFleeServer(dog:Dynamic) {
		dog.state = "fleeing";
		dog.fleeTimer = 5.0;
		var fleeLen = Math.sqrt(dog.velX * dog.velX + dog.velY * dog.velY);
		if (fleeLen > 0.1) {
			dog.velX = (-dog.velX / fleeLen) * DOG_FLEE_SPEED;
			dog.velY = (-dog.velY / fleeLen) * DOG_FLEE_SPEED;
		} else {
			var worldW = state.collision.cols * state.collision.tileSize;
			dog.velX = if (dog.x < worldW / 2) -DOG_FLEE_SPEED else DOG_FLEE_SPEED;
			dog.velY = 0;
		}
		broadcast("dog_update", {id: dog.id, x: dog.x, y: dog.y, velX: dog.velX, velY: dog.velY});
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
			// Hot mode or waders: allow walking into shallow water (only block SOLID)
			var isHot = hotModePlayers.exists(id) && hotModePlayers.get(id);
			var hasWaders = wadersPlayers.exists(id) && wadersPlayers.get(id);
			var blockFlags = if (isHot || hasWaders) CollisionMap.FLAG_SOLID else 0;
			for (inp in queue) {
				simulation.tickPlayer(p, [inp], inp.elapsed, blockFlags);
			}
			queue.splice(0, queue.length);
		}

		// Update server-side fish AI
		updateFish(t);

		// Update server-side seagulls
		updateSeagulls(t);

		// Update server-side worms
		updateWorms(t);

		// Update server-side dogs
		updateDogs(t);

		// Tick round timer and broadcast syncs
		if (gameplayStarted) {
			roundTimerSec += t;
			timerSyncCooldown -= t;
			if (timerSyncCooldown <= 0) {
				timerSyncCooldown = 5.0;
				broadcast("timer_sync", {runTimeSec: roundTimerSec, totalSec: roundDurationSec});
			}
			if (roundTimerSec >= roundDurationSec) {
				broadcast("round_time_up", {});
				gameplayStarted = false; // stop ticking
				// Transition server round status so ready-up flow works
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
}
