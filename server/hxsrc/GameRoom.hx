import GameState.BushState;
import GameState.FishState;
import haxe.Json;
import colyseus.server.Client;
import colyseus.server.Room.RoomOf;
import colyseus.server.Room.CloseCode;
import GameState.PlayerState;
import GameState.RoundState;
import haxe.extern.EitherType;
import js.lib.Promise;

class GameRoom extends RoomOf<GameState, Dynamic> {
	override public function onCreate(options:Dynamic):Void {
		maxClients = 6;
		setState(new GameState());

		trace('start room: ${roomId}:${roomName}');

		// sent when a player moves
		onMessage("move", (client:Client, data:{
			x:Float,
			y:Float,
			velocityX:Float,
			velocityY:Float
		}) -> {
			var player:PlayerState = state.players.get(client.sessionId);
			if (player != null) {
				player.x = data.x;
				player.y = data.y;
				player.velocityX = data.velocityX;
				player.velocityY = data.velocityY;
			}
		});

		onMessage("player_name_changed", (client:Client, data:{
			name:String,
		}) -> {
			var player:PlayerState = state.players.get(client.sessionId);
			if (player != null) {
				player.name = data.name;
			}
		});

		// sent when a client spawns a fish
		onMessage("fish_spawn", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "fish_spawn" message: ${Json.stringify(data)}');
			state.fish.set(data.id, new FishState(data.x, data.y));
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

		// sent when a rock lands in water
		onMessage("rock_splash", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "rock_splash": x=${data.x} y=${data.y} big=${data.big}');
			broadcast("rock_splash", {x: data.x, y: data.y, big: data.big}, {except: client});
		});

		// sent when a fish moves
		onMessage("fish_move", (client:Client, data:Dynamic) -> {
			var fish:FishState = state.fish.get(data.id);
			if (fish != null) {
				fish.x = data.x;
				fish.y = data.y;
			}
		});

		// sent by the host when a scared fish finishes fading and despawns
		onMessage("fish_despawn", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "fish_despawn": id=${data.id} respawnTime=${data.respawnTime}');
			broadcast("fish_despawn", {id: data.id, respawnTime: data.respawnTime}, {except: client});
		});

		// sent when a player changes their skin selection in the lobby
		onMessage("skin_changed", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "skin_changed" message: skinIndex=${data.skinIndex}');
			var player:PlayerState = state.players.get(client.sessionId);
			if (player != null) {
				player.skinIndex = data.skinIndex;
			}
		});

		// sent when a player's score changes
		onMessage("score_update", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "score_update" message: score=${data.score}');
			var player:PlayerState = state.players.get(client.sessionId);
			if (player != null) {
				player.score = data.score;
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

		// sent by the host to establish shared world layout (bushes + shop)
		onMessage("world_setup", (client:Client, data:Dynamic) -> {
			if (client.sessionId != state.hostSessionId) {
				return;
			}
			var bushArray:Array<Dynamic> = data.bushes;
			for (i => bush in bushArray) {
				state.bushes.set(Std.string(i), new BushState(bush.x, bush.y));
			}
			state.shopX = data.shopX;
			state.shopY = data.shopY;
			state.shopReady = true;
		});

		onMessage("round_update", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "round_update" message: ${Json.stringify(data)}');
			if (data != null) {
				var newData = new RoundState();
				newData.status = state.round.status;
				newData.currentRound = state.round.currentRound;
				newData.totalRounds = state.round.totalRounds;

				if (data.status != null) {
					trace('update round status: ${state.round.status} -> ${data.status}');
					newData.status = data.status;

					for (sId => pp in state.players) {
						pp.ready = false;
					}
				}
				if (data.currentRound != null) {
					newData.currentRound = data.currentRound;
				}
				if (data.totalRounds != null) {
					newData.totalRounds = data.totalRounds;
				}
				state.round = newData;
			}
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
			if (state.hostSessionId == null) {
				// after the last person leaves a room, just close it down
				trace('disconnect room: ${roomId}:${roomName}');
				disconnect();
			}
		}

		return null;
	}
}
