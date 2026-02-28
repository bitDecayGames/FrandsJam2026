package net;

import config.Configure;
import flixel.util.FlxSignal;
import io.colyseus.Client;
import io.colyseus.Room;
import io.colyseus.serializer.schema.Callbacks;
import schema.GameState;
import schema.PlayerState;
import schema.FishState;

class NetworkManager {
	var client:Client;
	var room:Room<GameState>;

	public var mySessionId:String = "";

	public var onJoined:(sessionId:String) -> Void;
	public var onPlayerAdded:(sessionId:String, player:PlayerState) -> Void;
	public var onPlayerChanged:(sessionId:String, player:PlayerState) -> Void;
	public var onPlayerRemoved:(sessionId:String) -> Void;

	public var onPCh = new FlxTypedSignal<(String, PlayerState) -> Void>();

	public var onFishMove = new FlxTypedSignal<(String, FishState) -> Void>();

	public static inline var roomName:String = "game_room";

	public function new() {}

	public function connect(host:String, port:Int) {
		var addr = '${Configure.getServerProtocol()}$host:$port';
		trace('attempting to connect to: ${addr}');
		client = new Client(addr);
		client.joinOrCreate(roomName, new Map<String, Dynamic>(), GameState, (err, joinedRoom) -> {
			if (err != null) {
				trace('NetworkManager: failed to join room — $err');
				return;
			}

			room = joinedRoom;
			mySessionId = room.sessionId;
			trace('NetworkManager: joined room ${roomName} (id: ${room.roomId}) as $mySessionId');

			if (onJoined != null) {
				onJoined(mySessionId);
			}

			var cb = Callbacks.get(room);

			cb.onAdd(room.state, "fish", (fish:FishState, id:String) -> {
				trace('NetworkManager: fish added ${id}');

				cb.listen(fish, "x", (_, _) -> {
					trace('NetMan: (fish: ${id} x update');
					onFishMove.dispatch(id, fish);
				});
				cb.listen(fish, "y", (_, _) -> {
					trace('NetMan: (fish: ${id} y update');
					onFishMove.dispatch(id, fish);
				});
			});

			cb.onAdd(room.state, "players", (player:PlayerState, sessionId:String) -> {
				trace('NetworkManager: player added $sessionId');
				if (sessionId == mySessionId) {
					return;
				}
				if (onPlayerAdded != null) {
					onPlayerAdded(sessionId, player);
				}
				cb.listen(player, "x", (_, _) -> {
					trace('NetMan: (sesh: ${sessionId} x update');
					onPCh.dispatch(sessionId, player);
					if (onPlayerChanged != null) {
						onPlayerChanged(sessionId, player);
					}
				});
				cb.listen(player, "y", (_, _) -> {
					trace('NetMan: (sesh: ${sessionId} y update');
					onPCh.dispatch(sessionId, player);
					if (onPlayerChanged != null) {
						onPlayerChanged(sessionId, player);
					}
				});
			});

			cb.onRemove(room.state, "players", (player:PlayerState, sessionId:String) -> {
				trace('NetworkManager: player removed $sessionId');
				if (sessionId == mySessionId) {
					return;
				}
				if (onPlayerRemoved != null) {
					onPlayerRemoved(sessionId);
				}
			});

			room.onMessage("cast_line", (message) -> {
				trace('[NetMan] cast_line => ${message.x}, ${message.y}');
			});
		});
	}

	public function sendMove(x:Float, y:Float) {
		if (room == null) {
			return;
		}
		room.send("move", {x: x, y: y});
	}

	public function setMessage(topic:String, msg:Dynamic) {
		if (room == null) {
			return;
		}
		room.send(topic, msg);
	}

	public function update() {
		#if sys
		// colyseus-hx polls internally via the connection thread; no manual recv needed
		#end
	}
}
