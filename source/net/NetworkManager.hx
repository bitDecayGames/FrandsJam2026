package net;

import managers.GameManager;
import flixel.math.FlxPoint;
import config.Configure;
import flixel.util.FlxSignal;
import io.colyseus.Client;
import io.colyseus.Room;
import io.colyseus.serializer.schema.Callbacks;
import schema.BushState;
import schema.GameState;
import PInput.P_Input;
import schema.PlayerState;
import schema.FishState;
import schema.RoundState;

typedef SessionIdSignal = FlxTypedSignal<String->Void>; // clientId
typedef PlayerUpdateData = {state:PlayerState, ?prevX:Float, ?prevY:Float};
typedef PlayerStateSignal = FlxTypedSignal<(String, PlayerUpdateData) -> Void>; // clientId, playerData
typedef FishStateSignal = FlxTypedSignal<String->FishState->Void>; // fishId, fishState
typedef RoundStateSignal = FlxTypedSignal<RoundState->Void>;
typedef PlayersReadySignal = FlxTypedSignal<Void->Void>;
typedef RockThrowSignal = FlxTypedSignal<(String, FlxPoint, Bool, String) -> Void>; // sessionId, targetX, targetY, big, dir

class NetworkManager {

	var client:Client;
	var room:Room<GameState>;
	var localRoom:LocalRoom;

	public var mySessionId:String = "";

	public var onJoined:SessionIdSignal = new SessionIdSignal();
	public var onPlayerAdded:PlayerStateSignal = new PlayerStateSignal();
	public var onPlayerChanged:PlayerStateSignal = new PlayerStateSignal();
	public var onPlayerNameChanged = new FlxTypedSignal<String->String->Void>(); // seshId, name
	public var onPlayerRemoved:SessionIdSignal = new SessionIdSignal();
	public var onFishMove:FishStateSignal = new FishStateSignal();
	public var onFishAdded = new FishStateSignal();
	public var onRockSplash = new FlxTypedSignal<Float->Float->Bool->Void>(); // x, y, big

	public var onThrowRock = new RockThrowSignal();
	public var onRoundUpdate = new RoundStateSignal();
	public var onPlayersReady = new PlayersReadySignal();

	public var onBushAdded = new FlxTypedSignal<Float->Float->Void>(); // x, y
	public var onShopPlaced = new FlxTypedSignal<Float->Float->Void>(); // x, y
	public var onSpawnLocations = new FlxTypedSignal<Dynamic->Void>(); // {sessionId: {x, y}, ...}

	public var onCastLine = new FlxTypedSignal<String->Float->Float->String->Void>(); // sessionId, x, y, dir
	public var onFishCaught = new FlxTypedSignal<String->String->Int->Void>(); // sessionId (catcher), fishId, fishType
	public var onFishPocketed = new FlxTypedSignal<String->String->Void>(); // sessionId (catcher), fishId
	public var onFishBanked = new FlxTypedSignal<String->String->Void>(); // sessionId (catcher), fishId
	public var onFishDespawn = new FlxTypedSignal<String->Float->Void>(); // fishId, respawnTime
	public var onLinePulled = new FlxTypedSignal<String->Void>(); // sessionId
	public var onSkinChanged = new FlxTypedSignal<String->Int->Void>(); // sessionId, skinIndex
	public var onPlayerReadyChanged = new FlxTypedSignal<String->Bool->Void>(); // sessionId, ready
	public var onScoreChanged = new FlxTypedSignal<String->Int->Void>(); // sessionId, score
	public var onFishSold = new FlxTypedSignal<String->Int->Int->Int->Void>(); // sessionId, fishType, lengthCm, value
	public var onWeedBurst = new FlxTypedSignal<String->Int->Void>(); // sessionId, index
	public var onWormKilled = new FlxTypedSignal<String->Int->Void>(); // sessionId, wormId
	public var onWorldItems = new FlxTypedSignal<Dynamic->Void>();
	public var onItemPickup = new FlxTypedSignal<String->String->Int->Void>(); // sessionId, itemType, index
	public var onBushIgnite = new FlxTypedSignal<Int->Void>(); // index
	public var onWeedIgnite = new FlxTypedSignal<Int->Void>(); // index
	public var onHotPepper = new FlxTypedSignal<String->Bool->Void>(); // sessionId, isStart
	public var onPlayerDrown = new FlxTypedSignal<String->Float->Float->Void>(); // sessionId, x, y
	public var onCastStart = new FlxTypedSignal<String->String->Void>(); // sessionId, dir
	public var onGroundFishSpawn = new FlxTypedSignal<Dynamic->Void>(); // {startX, startY, landX, landY, fishType, lengthCm}
	public var onGroundFishPickup = new FlxTypedSignal<Float->Float->Void>(); // x, y (approximate match)
	public var onKicked = new FlxTypedSignal<Void->Void>();
	public var onTimerSync = new FlxTypedSignal<Float->Float->Void>(); // runTimeSec, totalSec
	public var onRoundTimeUp = new FlxTypedSignal<Void->Void>();
	public var onLocalPlayerAck = new FlxTypedSignal<PlayerState->Void>();
	public var onCloudSync = new FlxTypedSignal<Dynamic->Void>(); // {angle, clouds}
	public var onWormSpawn = new FlxTypedSignal<Dynamic->Void>(); // {id, srcX, srcY, destX, destY}
	public var onSeagullSpawn = new FlxTypedSignal<Dynamic->Void>(); // {id, x, y, velX, velY, altitude}
	public var onSeagullPoop = new FlxTypedSignal<Dynamic->Void>(); // {id, x, y, fallDist, birdVelX, hitWater}
	public var onSeagullDespawn = new FlxTypedSignal<Dynamic->Void>(); // {id}

	public static inline var roomName:String = "game_room";

	public function new() {}

	public function disconnect() {
		if (localRoom != null) {
			localRoom = null;
			return;
		}
		if (room == null) {
			return;
		}
		room.leave(true);
		room = null;
	}

	public function connect(host:String, port:Int) {
		if (host == "local") {
			// In-process local server — no network needed
			if (localRoom == null) {
				localRoom = new LocalRoom(this);
			}
			return;
		}
		if (host == null || host == "") {
			trace('NetworkManager: no server URL configured, cannot connect');
			return;
		}
		var addr = '${Configure.getServerProtocol()}$host:$port';
		trace('attempting to connect to: ${addr}');
		if (client == null) {
			client = new Client(addr);
		}
		if (room != null) {
			trace('already connected to a room ${room.roomId}, not re-connecting');
			return;
		}
		client.joinOrCreate(roomName, new Map<String, Dynamic>(), GameState, (err, joinedRoom) -> {
			if (err != null) {
				trace('NetworkManager: failed to join room — $err');
				return;
			}

			// The joinOrCreate callback fires from the websocket background thread.
			// Defer all setup to the main thread to avoid crashing HashLink.
			runOnMain(() -> {
			room = joinedRoom;

			mySessionId = room.sessionId;
			trace('NetworkManager: joined room ${roomName} (id: ${room.roomId}) as $mySessionId');
			onJoined.dispatch(mySessionId);

			var cb = Callbacks.get(room);

			cb.listen("round", (round:RoundState, _:RoundState) -> {
				trace('RoundState: ${round}');
				onRoundUpdate.dispatch(round);
			});
			trace('NetworkManager: round listener registered');

			onMsg("players_ready", (message) -> {
				trace('players ready');
				onPlayersReady.dispatch();
			});

			cb.onAdd(room.state, "fish", (fish:FishState, id:String) -> {
				trace('NetworkManager: fish added ${id}');
				onFishAdded.dispatch(id, fish);

				cb.listen(fish, "x", (_, _) -> {
					// trace('NetMan: (fish: ${id} x update');
					onFishMove.dispatch(id, fish);
				});
				cb.listen(fish, "y", (_, _) -> {
					// trace('NetMan: (fish: ${id} y update');
					onFishMove.dispatch(id, fish);
				});
				cb.listen(fish, "alive", (_, _) -> {
					onFishMove.dispatch(id, fish);
				});
			});

			cb.onAdd(room.state, "bushes", (bush:BushState, id:String) -> {
				trace('NetworkManager: bush added ${id} at ${bush.x}, ${bush.y}');
				onBushAdded.dispatch(bush.x, bush.y);
			});

			cb.listen("shopReady", (val:Bool, _:Bool) -> {
				if (val) {
					trace('NetworkManager: shop placed at ${room.state.shopX}, ${room.state.shopY}');
					onShopPlaced.dispatch(room.state.shopX, room.state.shopY);
				}
			});

			cb.onAdd(room.state, "players", (player:PlayerState, sessionId:String) -> {
				playerDebugTrace('NetworkManager: player added $sessionId');
				if (sessionId == mySessionId) {
					cb.listen(player, "lastProcessedSeq", (_, _) -> {
						onLocalPlayerAck.dispatch(player);
					});
					return;
				}
				onPlayerAdded.dispatch(sessionId, {state: player});

				cb.listen(player, "x", (_, prevX:Float) -> {
					playerDebugTrace('NetMan: (sesh: ${sessionId} x: ${prevX} -> ${player.x}');
					onPlayerChanged.dispatch(sessionId, {state: player, prevX: prevX});
				});
				cb.listen(player, "y", (_, prevY:Float) -> {
					playerDebugTrace('NetMan: (sesh: ${sessionId} y: ${prevY} -> ${player.y}');
					onPlayerChanged.dispatch(sessionId, {state: player, prevY: prevY});
				});
				cb.listen(player, "velocityX", (_, prevY:Float) -> {
					playerDebugTrace('NetMan: (sesh: ${sessionId} y: ${prevY} -> ${player.y}');
					onPlayerChanged.dispatch(sessionId, {state: player});
				});
				cb.listen(player, "velocityY", (_, prevY:Float) -> {
					playerDebugTrace('NetMan: (sesh: ${sessionId} y: ${prevY} -> ${player.y}');
					onPlayerChanged.dispatch(sessionId, {state: player});
				});

				cb.listen(player, "name", (_, _) -> {
					playerDebugTrace('NetMan: sesh: ${sessionId} name: ${player.name}');
					onPlayerNameChanged.dispatch(sessionId, player.name);
				});
				cb.listen(player, "skinIndex", (_, _) -> {
					playerDebugTrace('NetMan: sesh: ${sessionId} skinIndex: ${player.skinIndex}');
					onSkinChanged.dispatch(sessionId, player.skinIndex);
				});
				cb.listen(player, "ready", (_, _) -> {
					playerDebugTrace('NetMan: sesh: ${sessionId} ready: ${player.ready}');
					onPlayerReadyChanged.dispatch(sessionId, player.ready);
				});
				cb.listen(player, "score", (_, _) -> {
					playerDebugTrace('NetMan: sesh: ${sessionId} score: ${player.score}');
					onScoreChanged.dispatch(sessionId, player.score);
				});
			});

			cb.onRemove(room.state, "players", (player:PlayerState, sessionId:String) -> {
				playerDebugTrace('NetworkManager: player removed $sessionId');
				if (sessionId == mySessionId) {
					return;
				}
				onPlayerRemoved.dispatch(sessionId);
			});

			onMsg("cast_start", (message:{sessionId:String, dir:String}) -> {
				trace('[NetMan] cast_start => ${message.sessionId} dir:${message.dir}');
				onCastStart.dispatch(message.sessionId, message.dir);
			});

			onMsg("cast_line", (message:{
				sessionId:String,
				x:Float,
				y:Float,
				dir:String
			}) -> {
				trace('[NetMan] cast_line => ${message.sessionId} ${message.x},${message.y} dir:${message.dir}');
				// var x:Float = message.x;
				// var y:Float = message.y;
				onCastLine.dispatch(message.sessionId, message.x, message.y, message.dir);
			});

			onMsg("fish_caught", (message:Dynamic) -> {
				trace('[NetMan] fish_caught => sessionId:${message.sessionId} fishId:${message.fishId} fishType:${message.fishType}');
				var ft:Int = message.fishType != null ? Std.int(message.fishType) : 0;
				onFishCaught.dispatch(message.sessionId, message.fishId, ft);
			});
			onMsg("fish_pocketed", (message) -> {
				trace('[NetMan] fish_pocketed => sessionId:${message.sessionId} fishId:${message.fishId}');
				onFishPocketed.dispatch(message.sessionId, message.fishId);
			});
			onMsg("fish_banked", (message) -> {
				trace('[NetMan] fish_banked => sessionId:${message.sessionId} fishId:${message.fishId}');
				onFishBanked.dispatch(message.sessionId, message.fishId);
			});

			onMsg("line_pulled", (message) -> {
				trace('[NetMan] line_pulled => sessionId:${message.sessionId}');
				onLinePulled.dispatch(message.sessionId);
			});

			onMsg("fish_despawn", (message:{id:String, respawnTime:Float}) -> {
				trace('[NetMan] fish_despawn => fishId:${message.id} respawnTime:${message.respawnTime}');
				onFishDespawn.dispatch(message.id, message.respawnTime);
			});

			onMsg("rock_splash", (message:Dynamic) -> {
				var sx:Float = message.x;
				var sy:Float = message.y;
				var sbig:Bool = message.big;
				trace('[NetMan] rock_splash => $sx, $sy big=$sbig');
				onRockSplash.dispatch(sx, sy, sbig);
			});

			onMsg("throw_rock", (message:Dynamic) -> {
				trace('[NetMan] throw_rock => sessionId:${message.sessionId} target:(${message.targetX},${message.targetY}) big:${message.big} dir:${message.dir}');

				var dest = FlxPoint.get(message.targetX, message.targetY);
				onThrowRock.dispatch(message.sessionId, dest, message.big, message.dir);
				dest.put();
			});

			onMsg("fish_sold", (message:Dynamic) -> {
				trace('[NetMan] fish_sold => sessionId:${message.sessionId} fishType:${message.fishType} lengthCm:${message.lengthCm} value:${message.value}');
				onFishSold.dispatch(message.sessionId, Std.int(message.fishType), Std.int(message.lengthCm), Std.int(message.value));
			});

			onMsg("weed_burst", (message:Dynamic) -> {
				trace('[NetMan] weed_burst => sessionId:${message.sessionId} index:${message.index}');
				onWeedBurst.dispatch(message.sessionId, Std.int(message.index));
			});

			onMsg("world_items", (message:Dynamic) -> {
				trace('[NetMan] world_items received');
				onWorldItems.dispatch(message);
			});

			onMsg("item_pickup", (message:Dynamic) -> {
				trace('[NetMan] item_pickup => sessionId:${message.sessionId} itemType:${message.itemType} index:${message.index}');
				onItemPickup.dispatch(message.sessionId, message.itemType, Std.int(message.index));
			});


			onMsg("bush_ignite", (message:Dynamic) -> {
				onBushIgnite.dispatch(Std.int(message.index));
			});

			onMsg("weed_ignite", (message:Dynamic) -> {
				onWeedIgnite.dispatch(Std.int(message.index));
			});

			onMsg("worm_killed", (message:Dynamic) -> {
				trace('[NetMan] worm_killed => sessionId:${message.sessionId}');
				onWormKilled.dispatch(message.sessionId, Std.int(message.id));
			});

			onMsg("worm_spawn", (message:Dynamic) -> {
				onWormSpawn.dispatch(message);
			});

			onMsg("player_drown", (message:Dynamic) -> {
				onPlayerDrown.dispatch(message.sessionId, message.x, message.y);
			});

			onMsg("hot_pepper", (message:Dynamic) -> {
				trace('[NetMan] hot_pepper => sessionId:${message.sessionId} isStart:${message.isStart}');
				onHotPepper.dispatch(message.sessionId, message.isStart == true);
			});

			onMsg("spawn_locations", (message:Dynamic) -> {
				trace('[NetMan] spawn_locations received');
				onSpawnLocations.dispatch(message);
			});

			onMsg("kicked", (_) -> {
				trace('[NetMan] we got kicked!');
				room.leave(true);
				room = null;
				onKicked.dispatch();
			});

			onMsg("player_kicked", (message:{sessionId:String}) -> {
				trace('[NetMan] player_kicked => ${message.sessionId}');
				onPlayerRemoved.dispatch(message.sessionId);
			});

			onMsg("timer_sync", (message:Dynamic) -> {
				trace('[NetMan] timer_sync received: runTimeSec=${message.runTimeSec} totalSec=${message.totalSec}');
				onTimerSync.dispatch(message.runTimeSec, message.totalSec);
			});

			onMsg("round_time_up", (_) -> {
				trace('[NetMan] round_time_up received');
				onRoundTimeUp.dispatch();
			});

			onMsg("ground_fish_spawn", (message:Dynamic) -> {
				onGroundFishSpawn.dispatch(message);
			});

			onMsg("ground_fish_pickup", (message:Dynamic) -> {
				onGroundFishPickup.dispatch(message.x, message.y);
			});

			onMsg("cloud_sync", (message:Dynamic) -> {
				trace('[NetMan] cloud_sync received: angle=${message.angle}');
				entities.CloudShadow.windAngle = message.angle;
				onCloudSync.dispatch(message);
			});

			onMsg("seagull_spawn", (message:Dynamic) -> {
				onSeagullSpawn.dispatch(message);
			});

			onMsg("seagull_poop", (message:Dynamic) -> {
				onSeagullPoop.dispatch(message);
			});

			onMsg("seagull_despawn", (message:Dynamic) -> {
				onSeagullDespawn.dispatch(message);
			});
			}); // end runInMainThread
		});
	}

	public function isLocal():Bool {
		return localRoom != null;
	}

	public function getLocalSimulation():Simulation {
		return localRoom != null ? localRoom.getSimulation() : null;
	}

	public function getLocalCollision():CollisionMap {
		return localRoom != null ? localRoom.getCollision() : null;
	}

	public function getLocalPlayerState():schema.PlayerState {
		return localRoom != null ? localRoom.getPlayerState() : null;
	}

	public function sendKick(targetSessionId:String) {
		sendMessage("kick", {targetSessionId: targetSessionId});
	}

	// sendTimerSync removed — server now originates timer_sync broadcasts

	public function getState():GameState {
		// LocalRoom doesn't use GameState schema — return null
		if (localRoom != null) { return null; }
		return room != null ? room.state : null;
	}

	// sendFishCaught removed — server detects catches directly

	public function sendFishPocketed(fishId:String, catcherSessionId:String) {
		sendMessage("fish_pocketed", {fishId: fishId, catcherSessionId: catcherSessionId});
	}

	public function sendFishBanked(fishId:String, catcherSessionId:String) {
		sendMessage("fish_banked", {fishId: fishId, catcherSessionId: catcherSessionId});
	}

	public function sendLinePulled() {
		sendMessage("line_pulled", {});
	}

	public function sendItemPickup(itemType:String, index:Int) {
		sendMessage("item_pickup", {itemType: itemType, index: index});
	}

	public function sendHotPepper(isStart:Bool) {
		sendMessage("hot_pepper", {isStart: isStart});
	}

	public function sendWeedBurst(index:Int) {
		sendMessage("weed_burst", {index: index});
	}


	public function sendInput(input:P_Input) {
		sendMessage(GameState.MSG_P_INPUT, [input], true);
	}

	public function sendMove(x:Float, y:Float, velocityX:Float, velocityY:Float) {
		sendMessage("move", {
			x: x,
			y: y,
			velocityX: velocityX,
			velocityY: velocityY
		}, true);
	}

	public function sendMessage(topic:String, msg:Dynamic, mute:Bool = false) {
		if (localRoom != null) {
			localRoom.sendMessage(topic, msg);
			return;
		}
		if (room == null) {
			if (!mute) {
				QLog.notice('[NetMan]: !!Skipping message on topic "$topic": ${msg}');
			}
			return;
		}
		if (!mute) {
			QLog.notice('[NetMan]: Sending message on topic "$topic": ${msg}');
		}
		room.send(topic, msg);
	}

	public function update(elapsed:Float = 0) {
		if (localRoom != null) {
			localRoom.update(elapsed);
		}
		// In networked mode, schema changes are marshaled to the main thread by Colyseus'
		// enableMainLoopProcessing() (upstream Callbacks.get); our own callbacks
		// hop via runOnMain(). Nothing to poll here.
	}

	// Colyseus invokes every callback (joinOrCreate, onMessage, schema listeners)
	// from its websocket background thread. Touching HaxeFlixel / render state off
	// the main thread crashes HashLink with a longjmp or segfault, so we bounce any
	// game-touching work to the main thread first. On non-sys targets (html5) there
	// is no background thread — the callback already runs on the main loop — so we
	// just run inline. Lime pumps the main thread's event loop every frame
	// (NativeApplication.updateTimer -> Thread.current().events.progress).
	inline function runOnMain(f:Void->Void):Void {
		#if sys
		haxe.MainLoop.runInMainThread(f);
		#else
		f();
		#end
	}

	// Wrap room.onMessage so the handler body runs on the main thread. Mirrors
	// Room.onMessage's own Dynamic->Void signature so every call site is unchanged.
	function onMsg(type:Dynamic, handler:Dynamic->Void):Void {
		room.onMessage(type, (m:Dynamic) -> runOnMain(() -> handler(m)));
	}

	private function playerDebugTrace(value:Dynamic, ?params:Array<Dynamic>) {
		#if playerDebugTrace
		trace(value, params);
		#end
	}
}
