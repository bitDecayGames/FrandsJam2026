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

/**
 * Thin Colyseus wrapper around GameLogic.
 * All game simulation lives in shared/GameLogic.hx — this class only
 * handles Colyseus-specific I/O (schema sync, client messaging, room lifecycle).
**/
class GameRoom extends RoomOf<GameState, Dynamic> {
	var logic:GameLogic;
	var elapsedTime:Float;
	var ldtkRaw:Dynamic;

	// Two collision maps — lobby and game level
	var lobbyCollision:CollisionMap;
	var gameCollision:CollisionMap;

	override public function onCreate(options:Dynamic):Void {
		elapsedTime = 0;
		maxClients = 6;
		setState(new GameState());

		// Build collision maps for both levels
		var hitboxJson = sys.io.File.getContent("../assets/data/tile-hitboxes.json");
		var ldtkProject = new LdtkProject();

		var lobbyRaw = ldtkProject.getLevel("Lobby");
		lobbyCollision = CollisionMap.fromLevel(lobbyRaw, hitboxJson);

		var raw = ldtkProject.getLevel("Level_0");
		ldtkRaw = raw;
		gameCollision = CollisionMap.fromLevel(raw, hitboxJson);
		state.collision = gameCollision;

		// Create single GameLogic instance — starts with lobby collision
		logic = new GameLogic();
		logic.init(lobbyCollision, raw);

		// Wire callbacks
		logic.broadcast = (topic:String, data:Dynamic) -> {
			this.broadcast(topic, data);
		};
		logic.sendToClient = (clientId:String, topic:String, data:Dynamic) -> {
			var c = clients.getById(clientId);
			if (c != null) { c.send(topic, data); }
		};
		logic.onPlayerAdded = (id:String, ps:PlayerState) -> {
			state.players.set(id, ps);
		};
		logic.onPlayerRemoved = (id:String) -> {
			state.players.delete(id);
		};
		logic.onFishAdded = (id:String, fish:FishState) -> {
			state.fish.set(id, fish);
		};
		logic.onFishRemoved = (id:String) -> {
			state.fish.delete(id);
		};
		logic.onBushAdded = (id:String, x:Float, y:Float) -> {
			state.bushes.set(id, new BushState(x, y));
		};
		logic.onBushRemoved = (id:String) -> {
			state.bushes.delete(id);
		};
		logic.onRoundChanged = (round:RoundState) -> {
			state.round = round;
		};

		// Start fixed-tick simulation loop
		this.setSimulationInterval(this.serverUpdate);

		trace('start room: ${roomId}:${roomName}');

		// --- Route ALL messages through GameLogic ---
		var handledMessages = [
			"player_input", "cast_start", "cast_release",
			"cast_retract", "cast_cancel", "ground_fish_drop", "ground_fish_pickup",
			"player_name_changed", "bobber_landed", "bobber_retracted",
			"throw_rock", "rock_splash", "skin_changed", "score_update",
			"item_pickup", "weed_burst", "player_drown", "bush_ignite",
			"bush_dead", "weed_ignite", "worm_killed", "hot_pepper",
			"debug_end_round", "debug_spawn_dog", "fish_sold", "cast_line",
			"line_pulled", "round_update", "player_ready", "set_position",
			"dog_item_drop", "dog_no_fish", "fire_rocket",
			"throw_potion", "potion_landed", "throw_bait", "bait_landed"
		];
		for (topic in handledMessages) {
			var capturedTopic = topic;
			onMessage(capturedTopic, (client:Client, data:Dynamic) -> {
				logic.handleMessage(client.sessionId, capturedTopic, data);
			});
		}

		// Special: start_gameplay switches collision to game level
		onMessage("start_gameplay", (client:Client, data:Dynamic) -> {
			if (!logic.gameplayStarted) {
				// Switch to game-level collision map
				logic.collision = gameCollision;
				logic.simulation = new Simulation(gameCollision);
			}
			logic.handleMessage(client.sessionId, "start_gameplay", data);
		});

		// Kick handling (needs Colyseus client reference)
		onMessage("kick", (client:Client, data:{targetSessionId:String}) -> {
			trace('${client.sessionId}: wants to kick ${data.targetSessionId}');
			var target = clients.getById(data.targetSessionId);
			if (target == null) { return; }
			state.players.delete(data.targetSessionId);
			logic.removePlayer(data.targetSessionId);
			if (state.players.size <= 0) {
				disconnect();
				return;
			}
			broadcast("player_kicked", {sessionId: data.targetSessionId}, {except: target});
			target.send("kicked", {});
			target.leave(CloseCode.CONSENTED);
		});
	}

	override public function onJoin(client:Client, ?options:Dynamic):EitherType<Void, Promise<Dynamic>> {
		trace('player joined: ${client.sessionId}');

		// Use LDTK spawn point for initial position
		var rawObjects:Dynamic = Reflect.getProperty(ldtkRaw, "l_Objects");
		var allSpawn:Array<Dynamic> = Reflect.getProperty(rawObjects, "all_Spawn");
		var spawnX:Float = 48;
		var spawnY:Float = 48;
		if (allSpawn != null && allSpawn.length > 0) {
			spawnX = allSpawn[0].pixelX;
			spawnY = allSpawn[0].pixelY;
		}

		logic.addPlayer(client.sessionId, spawnX, spawnY);
		return null;
	}

	override public function onLeave(client:Client, ?code:CloseCode):EitherType<Void, Promise<Dynamic>> {
		trace('player left: ${client.sessionId}');
		logic.removePlayer(client.sessionId);

		if (state.players.size <= 0) {
			trace('disconnect room: ${roomId}:${roomName}');
			disconnect();
		}

		return null;
	}

	function serverUpdate(delta:Float) {
		elapsedTime += delta / 1000;
		var fixedStep = Simulation.FIXED_STEP;
		while (elapsedTime >= fixedStep) {
			elapsedTime -= fixedStep;
			logic.update(fixedStep * 1000);
		}
	}
}
