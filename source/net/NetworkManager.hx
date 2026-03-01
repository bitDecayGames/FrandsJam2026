package net;

import flixel.math.FlxPoint;
import config.Configure;
import flixel.util.FlxSignal;
import io.colyseus.Client;
import io.colyseus.Room;
import io.colyseus.serializer.schema.Callbacks;
import schema.BushState;
import schema.GameState;
import schema.PlayerState;
import schema.FishState;
import schema.RoundState;

typedef SessionIdSignal = FlxTypedSignal<String->Void>; // clientId
typedef PlayerUpdateData = {state:PlayerState, ?prevX:Float, ?prevY:Float};
typedef PlayerStateSignal = FlxTypedSignal<(String, PlayerUpdateData) -> Void>; // clientId, playerData
typedef FishStateSignal = FlxTypedSignal<String->FishState->Void>; // fishId, fishState
typedef RoundStateSignal = FlxTypedSignal<RoundState->Void>;
typedef PlayersReadySignal = FlxTypedSignal<Void->Void>;
typedef HostSignal = FlxTypedSignal<Bool->Bool->Void>; // cur, prev
typedef RockThrowSignal = FlxTypedSignal<(String, FlxPoint, Bool, String) -> Void>; // sessionId, targetX, targetY, big, dir

class NetworkManager {
	public static var IS_HOST:Bool = #if local true #else false #end;

	var client:Client;
	var room:Room<GameState>;

	public var mySessionId:String = "";

	public var onJoined:SessionIdSignal = new SessionIdSignal();
	public var onHostChanged:HostSignal = new HostSignal();
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
	public var onWormKilled = new FlxTypedSignal<String->Void>(); // sessionId
	public var onWorldItems = new FlxTypedSignal<Dynamic->Void>();
	public var onItemPickup = new FlxTypedSignal<String->String->Int->Void>(); // sessionId, itemType, index
	public var onBushRustle = new FlxTypedSignal<Int->Float->Float->Void>(); // index, dirX, dirY

	public static inline var roomName:String = "game_room";

	public function new() {}

	public function disconnect() {
		if (room == null) {
			return;
		}
		room.leave(true);
		room = null;
	}

	public function connect(host:String, port:Int) {
		#if local return; #end
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

			room = joinedRoom;

			mySessionId = room.sessionId;
			trace('NetworkManager: joined room ${roomName} (id: ${room.roomId}) as $mySessionId');
			onJoined.dispatch(mySessionId);

			var cb = Callbacks.get(room);

			cb.listen("hostSessionId", (val:String, prev:String) -> {
				var prevIsHost = IS_HOST;
				IS_HOST = val == mySessionId;
				trace('[NetMan] host changed ${prev} -> ${val}. IS_HOST: ${IS_HOST}');
				onHostChanged.dispatch(IS_HOST, prevIsHost);
			});

			cb.listen("round", (round:RoundState) -> {
				trace('RoundState: ${round}');
				onRoundUpdate.dispatch(round);
			});

			room.onMessage("players_ready", (message) -> {
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
				cb.listen(player, "velocitY", (_, prevY:Float) -> {
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

			room.onMessage("cast_line", (message:{
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

			room.onMessage("fish_caught", (message:Dynamic) -> {
				trace('[NetMan] fish_caught => sessionId:${message.sessionId} fishId:${message.fishId} fishType:${message.fishType}');
				var ft:Int = message.fishType != null ? Std.int(message.fishType) : 0;
				onFishCaught.dispatch(message.sessionId, message.fishId, ft);
			});
			room.onMessage("fish_pocketed", (message) -> {
				trace('[NetMan] fish_pocketed => sessionId:${message.sessionId} fishId:${message.fishId}');
				onFishPocketed.dispatch(message.sessionId, message.fishId);
			});
			room.onMessage("fish_banked", (message) -> {
				trace('[NetMan] fish_banked => sessionId:${message.sessionId} fishId:${message.fishId}');
				onFishBanked.dispatch(message.sessionId, message.fishId);
			});

			room.onMessage("line_pulled", (message) -> {
				trace('[NetMan] line_pulled => sessionId:${message.sessionId}');
				onLinePulled.dispatch(message.sessionId);
			});

			room.onMessage("fish_despawn", (message:{id:String, respawnTime:Float}) -> {
				trace('[NetMan] fish_despawn => fishId:${message.id} respawnTime:${message.respawnTime}');
				onFishDespawn.dispatch(message.id, message.respawnTime);
			});

			room.onMessage("rock_splash", (message:Dynamic) -> {
				var sx:Float = message.x;
				var sy:Float = message.y;
				var sbig:Bool = message.big;
				trace('[NetMan] rock_splash => $sx, $sy big=$sbig');
				onRockSplash.dispatch(sx, sy, sbig);
			});

			room.onMessage("throw_rock", (message:Dynamic) -> {
				trace('[NetMan] throw_rock => sessionId:${message.sessionId} target:(${message.targetX},${message.targetY}) big:${message.big} dir:${message.dir}');

				var dest = FlxPoint.get(message.targetX, message.targetY);
				onThrowRock.dispatch(message.sessionId, dest, message.big, message.dir);
				dest.put();
			});

			room.onMessage("fish_sold", (message:Dynamic) -> {
				trace('[NetMan] fish_sold => sessionId:${message.sessionId} fishType:${message.fishType} lengthCm:${message.lengthCm} value:${message.value}');
				onFishSold.dispatch(message.sessionId, Std.int(message.fishType), Std.int(message.lengthCm), Std.int(message.value));
			});

			room.onMessage("weed_burst", (message:Dynamic) -> {
				trace('[NetMan] weed_burst => sessionId:${message.sessionId} index:${message.index}');
				onWeedBurst.dispatch(message.sessionId, Std.int(message.index));
			});

			room.onMessage("world_items", (message:Dynamic) -> {
				trace('[NetMan] world_items received');
				onWorldItems.dispatch(message);
			});

			room.onMessage("item_pickup", (message:Dynamic) -> {
				trace('[NetMan] item_pickup => sessionId:${message.sessionId} itemType:${message.itemType} index:${message.index}');
				onItemPickup.dispatch(message.sessionId, message.itemType, Std.int(message.index));
			});

			room.onMessage("bush_rustle", (message:Dynamic) -> {
				trace('[NetMan] bush_rustle => index:${message.index} dir:(${message.dirX},${message.dirY})');
				onBushRustle.dispatch(Std.int(message.index), message.dirX, message.dirY);
			});

			room.onMessage("worm_killed", (message:Dynamic) -> {
				trace('[NetMan] worm_killed => sessionId:${message.sessionId}');
				onWormKilled.dispatch(message.sessionId);
			});

			room.onMessage("spawn_locations", (message:Dynamic) -> {
				trace('[NetMan] spawn_locations received');
				onSpawnLocations.dispatch(message);
			});
		});
	}

	public function sendWorldSetup(bushPositions:Array<{x:Float, y:Float}>, shopX:Float, shopY:Float) {
		sendMessage("world_setup", {
			bushes: bushPositions,
			shopX: shopX,
			shopY: shopY,
		});
	}

	public function sendSpawnLocations(locations:Dynamic) {
		sendMessage("spawn_locations", locations);
	}

	public function getState():GameState {
		return room != null ? room.state : null;
	}

	public function sendFishCaught(fishId:String, catcherSessionId:String, fishType:Int) {
		sendMessage("fish_caught", {fishId: fishId, catcherSessionId: catcherSessionId, fishType: fishType});
	}

	public function sendFishPocketed(fishId:String, catcherSessionId:String) {
		sendMessage("fish_pocketed", {fishId: fishId, catcherSessionId: catcherSessionId});
	}

	public function sendFishBanked(fishId:String, catcherSessionId:String) {
		sendMessage("fish_banked", {fishId: fishId, catcherSessionId: catcherSessionId});
	}

	public function sendLinePulled() {
		sendMessage("line_pulled", {});
	}

	public function sendWorldItems(data:Dynamic) {
		sendMessage("world_items", data);
	}

	public function sendItemPickup(itemType:String, index:Int) {
		sendMessage("item_pickup", {itemType: itemType, index: index});
	}

	public function sendWeedBurst(index:Int) {
		sendMessage("weed_burst", {index: index});
	}

	public function sendBushRustle(index:Int, dirX:Float, dirY:Float) {
		sendMessage("bush_rustle", {index: index, dirX: dirX, dirY: dirY});
	}

	public function sendMove(x:Float, y:Float, velocityX:Float, velocityY:Float) {
		#if local return; #end
		sendMessage("move", {
			x: x,
			y: y,
			velocityX: velocityX,
			velocityY: velocityY
		}, true);
	}

	public function sendMessage(topic:String, msg:Dynamic, mute:Bool = false) {
		#if local return; #end
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

	public function update() {
		#if sys
		// colyseus-hx polls internally via the connection thread; no manual recv needed
		#end
	}

	private function playerDebugTrace(value:Dynamic, ?params:Array<Dynamic>) {
		#if playerDebugTrace
		trace(value, params);
		#end
	}
}
