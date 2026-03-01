package net;

import config.Configure;
import flixel.util.FlxSignal;
import io.colyseus.Client;
import io.colyseus.Room;
import io.colyseus.serializer.schema.Callbacks;
import schema.GameState;
import schema.PlayerState;
import schema.FishState;
import schema.RoundState;

typedef SessionIdSignal = FlxTypedSignal<String->Void>;
typedef PlayerUpdateData = {state:PlayerState, ?prevX:Float, ?prevY:Float};
typedef PlayerStateSignal = FlxTypedSignal<(String, PlayerUpdateData) -> Void>;
typedef FishStateSignal = FlxTypedSignal<String->FishState->Void>;

class NetworkManager {
	public static var IS_HOST:Bool = #if local true #else false #end;

	var client:Client;
	var room:Room<GameState>;

	public var mySessionId:String = "";

	public var onJoined:SessionIdSignal = new SessionIdSignal();
	public var onPlayerAdded:PlayerStateSignal = new PlayerStateSignal();
	public var onPlayerChanged:PlayerStateSignal = new PlayerStateSignal();
	public var onPlayerRemoved:SessionIdSignal = new SessionIdSignal();
	public var onFishMove:FishStateSignal = new FishStateSignal();
	public var onFishAdded = new FishStateSignal();
	public var onRockSplash = new FlxTypedSignal<Float->Float->Void>();

	public static inline var roomName:String = "game_room";

	public function new() {}

	public function connect(host:String, port:Int) {
		#if local return; #end
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

			onJoined.dispatch(mySessionId);

			var cb = Callbacks.get(room);

			cb.listen("hostSessionId", (val:String, prev:String) -> {
				IS_HOST = val == mySessionId;
				trace('[NetMan] host changed ${prev} -> ${val}. IS_HOST: ${IS_HOST}');
			});

			cb.listen("round", (round:RoundState) -> {
				trace('RoundState: ${round}');
			});

			cb.onAdd(room.state, "fish", (fish:FishState, id:String) -> {
				trace('NetworkManager: fish added ${id}');
				onFishAdded.dispatch(id, fish);

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
				onPlayerAdded.dispatch(sessionId, {state: player});

				cb.listen(player, "x", (_, prevX:Float) -> {
					trace('NetMan: (sesh: ${sessionId} x: ${prevX} -> ${player.x}');
					onPlayerChanged.dispatch(sessionId, {state: player, prevX: prevX});
				});
				cb.listen(player, "y", (_, prevY:Float) -> {
					trace('NetMan: (sesh: ${sessionId} y: ${prevY} -> ${player.y}');
					onPlayerChanged.dispatch(sessionId, {state: player, prevY: prevY});
				});
			});

			cb.onRemove(room.state, "players", (player:PlayerState, sessionId:String) -> {
				trace('NetworkManager: player removed $sessionId');
				if (sessionId == mySessionId) {
					return;
				}
				onPlayerRemoved.dispatch(sessionId);
			});

			room.onMessage("cast_line", (message) -> {
				trace('[NetMan] cast_line => ${message.x}, ${message.y}');
			});

			room.onMessage("rock_splash", (message:Dynamic) -> {
				var sx:Float = message.x;
				var sy:Float = message.y;
				trace('[NetMan] rock_splash => $sx, $sy');
				onRockSplash.dispatch(sx, sy);
			});
		});
	}

	public function sendMove(x:Float, y:Float) {
		#if local return; #end
		sendMessage("move", {x: x, y: y}, true);
	}

	public function sendMessage(topic:String, msg:Dynamic, mute:Bool = false) {
		#if local return; #end
		if (room == null) {
			if (!mute) {
				QLog.notice('[NetMan]: !!Skipping message on topic "$topic"');
			}
			return;
		}
		if (!mute) {
			QLog.notice('[NetMan]: Sending message on topic "$topic"');
		}
		room.send(topic, msg);
	}

	public function update() {
		#if sys
		// colyseus-hx polls internally via the connection thread; no manual recv needed
		#end
	}
}
