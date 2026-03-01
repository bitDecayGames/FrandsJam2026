import GameState.FishState;
import haxe.Json;
import colyseus.server.Client;
import colyseus.server.Room.RoomOf;
import colyseus.server.Room.CloseCode;
import GameState.PlayerState;
import haxe.extern.EitherType;
import js.lib.Promise;

class GameRoom extends RoomOf<GameState, Dynamic> {
	override public function onCreate(options:Dynamic):Void {
		maxClients = 6;
		setState(new GameState());

		// sent when a player moves
		onMessage("move", (client:Client, data:Dynamic) -> {
			var player:PlayerState = state.players.get(client.sessionId);
			if (player != null) {
				player.x = data.x;
				player.y = data.y;
			}
		});

		// sent when a client spawns a fish
		onMessage("fish_spawn", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "fish_spawn" message: ${Json.stringify(data)}');
			state.fish.set(data.id, new FishState(data.x, data.y));
		});

		// sent when a fish moves
		onMessage("fish_move", (client:Client, data:Dynamic) -> {
			var fish:FishState = state.fish.get(data.id);
			if (fish != null) {
				fish.x = data.x;
				fish.y = data.y;
			}
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

		// sent when a player catches a fish; catcherSessionId may differ from client.sessionId
		// because the host reports catches on behalf of any player whose bobber a fish swam into
		onMessage("fish_caught", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "fish_caught": fishId=${data.fishId} catcher=${data.catcherSessionId}');
			broadcast("fish_caught", {sessionId: data.catcherSessionId, fishId: data.fishId});
		});

		// sent when a player pulls in their line
		onMessage("line_pulled", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "line_pulled" message');
			broadcast("line_pulled", {sessionId: client.sessionId});
		});

		onMessage("round_update", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "round_update" message: ${Json.stringify(data)}');
			if (data != null) {
				if (data.status != null) {
					state.round.status = data.status;
				}
				if (data.currentRound != null) {
					state.round.currentRound = data.currentRound;
				}
				if (data.totalRounds != null) {
					state.round.totalRounds = data.totalRounds;
				}
			}
		});
	}

	override public function onJoin(client:Client, ?options:Dynamic):EitherType<Void, Promise<Dynamic>> {
		trace('player joined: ${client.sessionId}');
		state.players.set(client.sessionId, new PlayerState());

		// Set host
		if (state.hostSessionId == null || state.hostSessionId == "") {
			state.hostSessionId = client.sessionId;
			trace('host set ${client.sessionId}');
		}

		return null;
	}

	override public function onLeave(client:Client, ?code:CloseCode):EitherType<Void, Promise<Dynamic>> {
		trace('player left: ${client.sessionId}');
		trace('successful clear: ${state.players.delete(client.sessionId)}');

		// Clear/rotate host
		if (client.sessionId == state.hostSessionId) {
			if (state.players.size <= 0) {
				state.hostSessionId = null;
			} else {
				var sIds = [];
				for (sId => _ in state.players) {
					sIds.push(sId);
				}
				var sIdx = Std.random(state.players.size);
				state.hostSessionId = sIds[sIdx];
			};

			trace('host changed ${client.sessionId} -> ${state.hostSessionId}');
		}

		return null;
	}
}
