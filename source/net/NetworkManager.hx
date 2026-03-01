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
typedef PlayerStateSignal = FlxTypedSignal<String->PlayerState->Void>;
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

	public var onCastLine = new FlxTypedSignal<String->Float->Float->String->Void>(); // sessionId, x, y, dir
	public var onFishCaught = new FlxTypedSignal<String->String->Void>(); // sessionId (catcher), fishId
	public var onLinePulled = new FlxTypedSignal<String->Void>(); // sessionId

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
				onPlayerAdded.dispatch(sessionId, player);

				cb.listen(player, "x", (_, _) -> {
					trace('NetMan: (sesh: ${sessionId} x update');
					onPlayerChanged.dispatch(sessionId, player);
				});
				cb.listen(player, "y", (_, _) -> {
					trace('NetMan: (sesh: ${sessionId} y update');
					onPlayerChanged.dispatch(sessionId, player);
				});
			});

			cb.onRemove(room.state, "players", (player:PlayerState, sessionId:String) -> {
				trace('NetworkManager: player removed $sessionId');
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

			room.onMessage("fish_caught", (message) -> {
				trace('[NetMan] fish_caught => sessionId:${message.sessionId} fishId:${message.fishId}');
				onFishCaught.dispatch(message.sessionId, message.fishId);
			});

			room.onMessage("line_pulled", (message) -> {
				trace('[NetMan] line_pulled => sessionId:${message.sessionId}');
				onLinePulled.dispatch(message.sessionId);
			});
		});
	}

	public function sendFishCaught(fishId:String, catcherSessionId:String) {
		sendMessage("fish_caught", {fishId: fishId, catcherSessionId: catcherSessionId});
	}

	public function sendLinePulled() {
		sendMessage("line_pulled", {});
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
