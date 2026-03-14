package rooms;

import js.lib.Error;
import transition.PlayerInitData;
import schema.GameState;
import schema.GameState.P_Input;
import schema.PlayerState;
import schema.RoundState;
import haxe.Json;
import colyseus.server.Client;
import colyseus.server.Room.RoomOf;
import colyseus.server.Room.CloseCode;
import haxe.extern.EitherType;
import js.lib.Promise;

class GameRoom extends RoomOf<GameState, Dynamic> {
	static var fixedTimeStep:Float = 1 / 20.0;

	var elapsedTime:Float;
	var tick:Int;

	var simulation:Simulation;

	var pendingReservations:Map<String, PlayerState>;

	var currentLevel:String;

	public function new() {
		super();
		elapsedTime = 0;
		tick = 0;
		currentLevel = "unknown";
	}

	override public function onCreate(options:Dynamic):Void {
		trace('start room: ${roomId}:${roomName}');
		maxClients = 6;
		setState(new GameState(options.levelID));
		simulation = new Simulation(state.collision);

		currentLevel = options.levelID;

		pendingReservations = new Map<String, PlayerState>();

		trace('expected players:');
		var pData:Array<PlayerInitData> = options.players;
		var spawnPoints = simulation.getRandomSpawnPoints(pData.length);

		for (i in 0...pData.length) {
			var data = pData[i];
			var spawn = spawnPoints[i];
			var pState = new PlayerState();
			pState.x = spawn.x;
			pState.y = spawn.y;
			pState.name = data.name;
			pState.skinIndex = data.skin;
			trace('  - ${data.sessionID}');
			pendingReservations.set(data.sessionID, pState);
		}

		this.setSimulationInterval(this.update);

		// this.clock.setInterval(() => {
		//   this.game.check_fish(this.state);
		// }, 3000);

		configureMessages();
	}

	private function configureMessages() {
		// sent when a player moves
		onMessage(GameState.MSG_P_INPUT, (client:Client, data:Array<P_Input>) -> {
			if (!state.players.has(client.sessionId)) {
				trace('input received from unknown player ${client.sessionId}, dropping.');
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

		// // sent when a client spawns a fish
		// onMessage("fish_spawn", (client:Client, data:Dynamic) -> {
		// 	trace('${client.sessionId}: sent "fish_spawn" message: ${Json.stringify(data)}');
		// 	state.fish.set(data.id, new FishState(data.x, data.y, data.fishType != null ? Std.int(data.fishType) : 0));
		// });

		// // sent when a player throws a rock
		// onMessage("throw_rock", (client:Client, data:Dynamic) -> {
		// 	trace('${client.sessionId}: sent "throw_rock": targetX=${data.targetX} targetY=${data.targetY} big=${data.big} dir=${data.dir}');
		// 	broadcast("throw_rock", {
		// 		sessionId: client.sessionId,
		// 		targetX: data.targetX,
		// 		targetY: data.targetY,
		// 		big: data.big,
		// 		dir: data.dir
		// 	}, {except: client});
		// });

		// // sent when a rock lands in water
		// onMessage("rock_splash", (client:Client, data:Dynamic) -> {
		// 	trace('${client.sessionId}: sent "rock_splash": x=${data.x} y=${data.y} big=${data.big}');
		// 	broadcast("rock_splash", {x: data.x, y: data.y, big: data.big}, {except: client});
		// });

		// // sent when a fish moves
		// onMessage("fish_move", (client:Client, data:Dynamic) -> {
		// 	var fish:FishState = state.fish.get(data.id);
		// 	if (fish != null) {
		// 		fish.x = data.x;
		// 		fish.y = data.y;
		// 	}
		// });

		// // sent by the host when a scared fish finishes fading and despawns
		// onMessage("fish_despawn", (client:Client, data:Dynamic) -> {
		// 	trace('${client.sessionId}: sent "fish_despawn": id=${data.id} respawnTime=${data.respawnTime}');
		// 	broadcast("fish_despawn", {id: data.id, respawnTime: data.respawnTime}, {except: client});
		// });

		// // sent when a player's score changes
		// onMessage("score_update", (client:Client, data:Dynamic) -> {
		// 	trace('${client.sessionId}: sent "score_update" message: score=${data.score}');
		// 	var player:PlayerState = state.players.get(client.sessionId);
		// 	if (player != null) {
		// 		player.score = data.score;
		// 	}
		// });

		// // sent by the host to broadcast all world item positions
		// onMessage("world_items", (client:Client, data:Dynamic) -> {
		// 	if (client.sessionId != state.hostSessionId) {
		// 		return;
		// 	}
		// 	trace('${client.sessionId}: sent "world_items"');
		// 	broadcast("world_items", data, {except: client});
		// });

		// // sent when a player picks up a world item (rock, waders, pepper)
		// onMessage("item_pickup", (client:Client, data:Dynamic) -> {
		// 	trace('${client.sessionId}: sent "item_pickup": itemType=${data.itemType} index=${data.index}');
		// 	broadcast("item_pickup", {sessionId: client.sessionId, itemType: data.itemType, index: data.index}, {except: client});
		// });

		// // sent when a player bursts a weed
		// onMessage("weed_burst", (client:Client, data:Dynamic) -> {
		// 	trace('${client.sessionId}: sent "weed_burst": index=${data.index}');
		// 	broadcast("weed_burst", {sessionId: client.sessionId, index: data.index}, {except: client});
		// });

		// // sent when a player walks into a bush
		// onMessage("bush_rustle", (client:Client, data:Dynamic) -> {
		// 	trace('${client.sessionId}: sent "bush_rustle": index=${data.index}');
		// 	broadcast("bush_rustle", {index: data.index, dirX: data.dirX, dirY: data.dirY}, {except: client});
		// });

		// // sent when a player kills a worm
		// onMessage("worm_killed", (client:Client, data:Dynamic) -> {
		// 	trace('${client.sessionId}: sent "worm_killed"');
		// 	broadcast("worm_killed", {sessionId: client.sessionId}, {except: client});
		// });

		// // sent when a player activates or deactivates hot pepper mode
		// onMessage("hot_pepper", (client:Client, data:Dynamic) -> {
		// 	trace('${client.sessionId}: sent "hot_pepper": isStart=${data.isStart}');
		// 	broadcast("hot_pepper", {sessionId: client.sessionId, isStart: data.isStart}, {except: client});
		// });

		// // host periodically broadcasts the timer state so non-host clients can sync
		// onMessage("timer_sync", (client:Client, data:Dynamic) -> {
		// 	trace('${client.sessionId}: sent "timer_sync": runTimeSec=${data.runTimeSec} totalSec=${data.totalSec}');
		// 	broadcast("timer_sync", {runTimeSec: data.runTimeSec, totalSec: data.totalSec}, {except: client});
		// });

		// // sent when a player sells a fish — broadcast to other clients so they can track it
		// onMessage("fish_sold", (client:Client, data:Dynamic) -> {
		// 	trace('${client.sessionId}: sent "fish_sold" message: fishType=${data.fishType} lengthCm=${data.lengthCm} value=${data.value}');
		// 	broadcast("fish_sold", {
		// 		sessionId: client.sessionId,
		// 		fishType: data.fishType,
		// 		lengthCm: data.lengthCm,
		// 		value: data.value,
		// 	}, {except: client});
		// });

		// // sent when a player casts their line
		// onMessage("cast_line", (client, data) -> {
		// 	trace('${client.sessionId}: sent "cast_line" message: ${Json.stringify(data)}');
		// 	broadcast("cast_line", {
		// 		sessionId: client.sessionId,
		// 		x: data.x,
		// 		y: data.y,
		// 		dir: data.dir
		// 	}, {except: client});
		// });

		// // sent when a player catches a fish; catcherSessionId may differ from client.sessionId
		// // because the host reports catches on behalf of any player whose bobber a fish swam into
		// onMessage("fish_caught", (client:Client, data:Dynamic) -> {
		// 	trace('${client.sessionId}: sent "fish_caught": fishId=${data.fishId} catcher=${data.catcherSessionId} fishType=${data.fishType}');
		// 	broadcast("fish_caught", {sessionId: data.catcherSessionId, fishId: data.fishId, fishType: data.fishType});
		// });

		// // sent when a player pulls in their line
		// onMessage("line_pulled", (client:Client, data:Dynamic) -> {
		// 	trace('${client.sessionId}: sent "line_pulled" message');
		// 	broadcast("line_pulled", {sessionId: client.sessionId});
		// });

		// // sent by the host to assign random spawn positions for all players
		// onMessage("spawn_locations", (client:Client, data:Dynamic) -> {
		// 	if (client.sessionId != state.hostSessionId) {
		// 		return;
		// 	}
		// 	trace('${client.sessionId}: sent "spawn_locations"');
		// 	broadcast("spawn_locations", data, {except: client});
		// });

		// // sent by the host to establish shared world layout (bushes + shop)
		// onMessage("world_setup", (client:Client, data:Dynamic) -> {
		// 	if (client.sessionId != state.hostSessionId) {
		// 		return;
		// 	}
		// 	var bushArray:Array<Dynamic> = data.bushes;
		// 	for (i => bush in bushArray) {
		// 		state.bushes.set(Std.string(i), new BushState(bush.x, bush.y));
		// 	}
		// 	state.shopX = data.shopX;
		// 	state.shopY = data.shopY;
		// 	state.shopReady = true;
		// });

		// onMessage("round_update", (client:Client, data:Dynamic) -> {
		// 	trace('${client.sessionId}: sent "round_update" message: ${Json.stringify(data)}');
		// 	if (data != null) {
		// 		var newData = new RoundState();
		// 		newData.status = state.round.status;
		// 		newData.currentRound = state.round.currentRound;
		// 		newData.totalRounds = state.round.totalRounds;

		// 		if (data.status != null) {
		// 			trace('update round status: ${state.round.status} -> ${data.status}');
		// 			newData.status = data.status;
		// 		}
		// 		if (data.currentRound != null) {
		// 			newData.currentRound = data.currentRound;
		// 		}
		// 		if (data.totalRounds != null) {
		// 			newData.totalRounds = data.totalRounds;
		// 		}
		// 		state.round = newData;
		// 	}
		// });
	}

	override public function onJoin(client:Client, ?options:Dynamic):EitherType<Void, Promise<Dynamic>> {
		// client.sessionId is a fresh ID for this room — look up the player by the
		// char select session ID that was passed as options when reserving the seat
		var charSelectId:String = options != null ? options.sessionId : null;
		var playerState = charSelectId != null ? pendingReservations.get(charSelectId) : null;

		if (playerState == null) {
			trace('unknown player attempted to join, rejecting: ${client.sessionId} (charSelectId=${charSelectId})');
			throw new Error("client ID not allowed in this room");
		}

		// Re-key under the new game room session ID so all subsequent messages work
		pendingReservations.remove(charSelectId);
		state.players.set(client.sessionId, playerState);

		trace('player joined: ${client.sessionId} (was ${charSelectId} in char select)');

		return null;
	}

	override public function onLeave(client:Client, ?code:CloseCode):EitherType<Void, Promise<Dynamic>> {
		trace('player left: ${client.sessionId}');
		trace('successful clear: ${state.players.delete(client.sessionId)}');

		if (state.players.size == 0) {
			// after the last person leaves a room, just close it down
			trace('disconnect room: ${roomId}:${roomName}');
			disconnect();
		}

		return null;
	}

	function update(delta:Float) {
		elapsedTime += delta / 1000;

		while (elapsedTime >= fixedTimeStep) {
			elapsedTime -= fixedTimeStep;
			this.fixedTick(fixedTimeStep);
		}
		// for (id => p in state.players) {
		// 	trace('pPos: )${p.x}, ${p.y})');
		// }
	}

	function fixedTick(t:Float) {
		tick++;

		for (id => p in state.players) {
			var queue = state.inputQueue.get(id);
			if (queue == null || queue.length == 0) {
				continue;
			}
			// Process each input with its original frame delta so the server
			// takes the same small steps as the client — keeps SAT penetration
			// shallow and prevents axis-flip on polygon corner tiles.
			//
			// Budget prevents cheaters from sending many inputs to move farther
			// than one server tick allows. Once budget is exhausted, remaining
			// inputs are called with dt=0 so they still advance lastProcessedSeq
			// — keeps the client's pendingInputs from growing unboundedly.
			var budget = t;
			for (inp in queue) {
				var dt = Math.max(0.0, Math.min(inp.elapsed, budget));
				simulation.tickPlayer(p, [inp], dt);
				budget -= dt;
			}
			queue.splice(0, queue.length);
		}
	}
}
