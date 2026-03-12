package net;

import schema.Constants.RoomName;
import io.colyseus.error.HttpException;
import io.colyseus.serializer.schema.Schema;
import managers.GameManager;
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
import schema.meta.CharSelectState;
import schema.meta.CharSelectState.PlayerLobbyState;

typedef SessionIdSignal = FlxTypedSignal<String->Void>; // clientId
typedef PlayerLobbyData = {sessionId:String, name:String, skinIndex:Int};
typedef PlayerJoinLobbySignal = FlxTypedSignal<(String, PlayerLobbyData) -> Void>;
typedef PlayerUpdateData = {state:PlayerState, ?prevX:Float, ?prevY:Float};
typedef PlayerStateSignal = FlxTypedSignal<(String, PlayerUpdateData) -> Void>; // clientId, playerData
typedef FishStateSignal = FlxTypedSignal<String->FishState->Void>; // fishId, fishState
typedef RoundStateSignal = FlxTypedSignal<RoundState->Void>;
typedef PlayersReadySignal = FlxTypedSignal<Void->Void>;
typedef HostSignal = FlxTypedSignal<Bool->Bool->Void>; // cur, prev
typedef RockThrowSignal = FlxTypedSignal<(String, FlxPoint, Bool, String) -> Void>; // sessionId, targetX, targetY, big, dir

class NetworkManager {
	public static var ME(get, null):NetworkManager;
	public static var IS_HOST:Bool = #if local true #else false #end;

	public var client:Client;

	// The current room that the network is connected to. Can be of various types
	var room:Room<Dynamic>;

	// Separate handle for the Colyseus LobbyRoom so it doesn't clobber `room`
	var lobbyRoomConn:Room<Schema>;

	public var mySessionId:String = "";

	public var onJoined:SessionIdSignal = new SessionIdSignal();

	public var onPlayerJoinLobby = new PlayerJoinLobbySignal();

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
	public var onHotPepper = new FlxTypedSignal<String->Bool->Void>(); // sessionId, isStart
	public var onKicked = new FlxTypedSignal<Void->Void>();
	public var onTimerSync = new FlxTypedSignal<Float->Float->Void>(); // runTimeSec, totalSec

	/** Fired whenever the Colyseus LobbyRoom sends an updated list of available rooms. */
	public var onRoomsUpdated = new FlxTypedSignal<Array<Dynamic>->Void>();

	public static inline var lobbyRoom:String = "lobby";
	public static inline var queueRoom:String = "queue";
	public static inline var roomName:String = "game_room";

	@:allow(managers.GameManager)
	private function new() {
		#if !local
		connect(Configure.getServerURL(), Configure.getServerPort());
		#end
	}

	public static function get_ME():NetworkManager {
		if (ME == null) {
			ME = new NetworkManager();
		}
		return ME;
	}

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
			client.getLatency((e, l) -> {
				QLog.notice('Latency Check: ${l}ms');
			});
		}
	}

	public function joinLobby(onSuccess:Room<Schema>->Void, onErr:HttpException->Void) {
		#if local
		// No server in local mode — dispatch an empty list so the UI can show "create a room"
		onRoomsUpdated.dispatch([]);
		return;
		#end
		client.joinOrCreate(lobbyRoom, cast {
			filter: {
				name: RoomName.CHAR_SELECT
			}
		}, Schema, (err, lobby:Room<Schema>) -> {
			if (err != null) {
				QLog.error('NetworkManager: failed to join lobby room — $err');
				onErr(err);
				return;
			}

			lobbyRoomConn = lobby;
			onSuccess(lobby);
		});
	}

	/** Join an existing room by its ID (e.g. from the lobby room listing). */
	public function joinSpecificRoom(roomId:String, onSuccess:Room<CharSelectState>->Void, onFail:HttpException->Void) {
		#if local
		onSuccess(null);
		return;
		#end
		if (lobbyRoomConn != null) {
			lobbyRoomConn.leave(true);
			lobbyRoomConn = null;
		}
		client.joinById(roomId, new Map<String, Dynamic>(), CharSelectState, (err, match:Room<CharSelectState>) -> {
			if (err != null) {
				QLog.error('joinSpecificRoom failed — $err');
				onFail(err);
				return;
			}
			// setupCharSelect(match);
			onSuccess(match);
		});
	}

	public function joinQueue(onCharSelect:Room<CharSelectState>->Void, onFail:HttpException->Void) {
		#if local
		onCharSelect(null);
		return;
		#end
		if (lobbyRoomConn != null) {
			lobbyRoomConn.leave(true);
			lobbyRoomConn = null;
		}
		client.joinOrCreate(RoomName.QUEUE, new Map<String, Dynamic>(), Schema, (err, queue) -> {
			if (err != null) {
				trace('NetworkManager: failed to join room — $err');
				onFail(err);
				return;
			}

			queue.onMessage("clients", function(count:Int) {
				trace("Players in your group: " + Std.string(count));
			});

			queue.onMessage("seat", function(reservation:Dynamic) {
				// Optionally confirm the reservation to the queue
				// lobby.send("confirm");

				// Join the match room with the reservation
				client.consumeSeatReservation(reservation, CharSelectState, function(err, match:Room<CharSelectState>) {
					if (err != null) {
						trace("error joining character select: " + err);
						onFail(err);
						return;
					}
					trace('Joined match ${match.roomId} as ${match.sessionId}');
					onCharSelect(match);
					// setupCharSelect(match);
				});
			});
		});
	}

	public function createPublicRoom(onSuccess:Room<CharSelectState>->Void, onFail:HttpException->Void) {
		#if local
		onSuccess(null);
		return;
		#end
		if (lobbyRoomConn != null) {
			lobbyRoomConn.leave(true);
			lobbyRoomConn = null;
		}
		client.create(RoomName.CHAR_SELECT, new Map<String, Dynamic>(), CharSelectState, (err, match:Room<CharSelectState>) -> {
			if (err != null) {
				QLog.error('createPublicRoom failed — $err');
				onFail(err);
				return;
			}
			onSuccess(match);
		});
	}

	public function createPrivateRoom(onSuccess:Room<CharSelectState>->Void, onFail:HttpException->Void) {
		#if local
		onSuccess(null);
		return;
		#end
		if (lobbyRoomConn != null) {
			lobbyRoomConn.leave(true);
			lobbyRoomConn = null;
		}
		client.create(RoomName.CHAR_SELECT_PRIVATE, new Map<String, Dynamic>(), CharSelectState, (err, match:Room<CharSelectState>) -> {
			if (err != null) {
				QLog.error('createPrivateRoom failed — $err');
				onFail(err);
				return;
			}
			onSuccess(match);
		});
	}

	function setupGameRoom(room:Room<GameState>) {
		this.room = room;
	}

	public function sendKick(targetSessionId:String) {
		sendMessage("kick", {targetSessionId: targetSessionId});
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

	public function sendTimerSync(runTimeSec:Float, totalSec:Float) {
		sendMessage("timer_sync", {runTimeSec: runTimeSec, totalSec: totalSec});
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

	public function sendHotPepper(isStart:Bool) {
		sendMessage("hot_pepper", {isStart: isStart});
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

	public function sendInputs(inputs:Array<schema.GameState.P_Input>) {
		#if local return; #end
		sendMessage(schema.GameState.MSG_P_INPUT, inputs, true);
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
