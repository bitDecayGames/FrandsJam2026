package net;

import schema.FishState;
import schema.PlayerState;
import schema.RoundState;

/**
 * In-process game server for single-player / local mode.
 * Runs the same GameLogic as the Colyseus server, but with direct
 * function calls instead of websocket messages.
**/
class LocalRoom {
	var logic:GameLogic;
	var net:NetworkManager;
	var sessionId:String;

	public function new(net:NetworkManager) {
		this.net = net;
		sessionId = "local_player";

		logic = new GameLogic();

		// Wire broadcast/send — dispatch directly to NetworkManager signals
		logic.broadcast = (topic, data) -> dispatchMessage(topic, data);
		logic.sendToClient = (_, topic, data) -> dispatchMessage(topic, data);

		// Wire schema-like callbacks for fish/bush additions
		logic.onFishAdded = (id, fish) -> net.onFishAdded.dispatch(id, fish);
		logic.onFishRemoved = (id) -> {};
		logic.onBushAdded = (id, x, y) -> net.onBushAdded.dispatch(x, y);
		logic.onBushRemoved = (id) -> {};
		logic.onPlayerAdded = (id, ps) -> {};
		logic.onPlayerRemoved = (id) -> {};
		logic.onRoundChanged = (round) -> net.onRoundUpdate.dispatch(round);

		// Build collision map from level data (client-side asset loading)
		var hitboxJson = openfl.Assets.getText("assets/data/tile-hitboxes.json");
		var ldtkProject = new levels.ldtk.Ldtk();
		var raw = ldtkProject.all_worlds.Default.all_levels.Level_0;
		var col = CollisionMap.fromLevel(raw, hitboxJson);
		logic.init(col, raw);

		// Simulate join
		logic.addPlayer(sessionId);

		// Tell NetworkManager we've "connected"
		net.mySessionId = sessionId;
		net.onJoined.dispatch(sessionId);
	}

	/** Called each frame */
	public function update(elapsed:Float) {
		logic.update(elapsed * 1000);
	}

	/** Route a client message through GameLogic */
	public function sendMessage(topic:String, data:Dynamic) {
		logic.handleMessage(sessionId, topic, data);
	}

	public function getSimulation():Simulation {
		return logic.simulation;
	}

	public function getCollision():CollisionMap {
		return logic.collision;
	}

	public function getPlayerState():PlayerState {
		return logic.players.get(sessionId);
	}

	/** Dispatch a "server" message to the local client's NetworkManager signals */
	function dispatchMessage(topic:String, data:Dynamic) {
		switch (topic) {
			case "cast_start":
				// single player — no remote players to notify
			case "cast_line":
				// single player — no remote players to notify
			case "fish_caught":
				net.onFishCaught.dispatch(data.sessionId, data.fishId, data.fishType);
			case "line_pulled":
				// single player — no remote players to notify
			case "rock_splash":
				// handled locally
			case "throw_rock":
				// single player — no remote players to notify
			case "fish_sold":
				// single player — no remote players to notify
			case "weed_burst":
				// single player — no remote players to notify
			case "world_items":
				net.onWorldItems.dispatch(data);
			case "item_pickup":
				// single player — no remote players to notify
			case "bush_rustle":
				// single player — handled locally
			case "bush_ignite":
				// single player — handled locally
			case "weed_ignite":
				// single player — handled locally
			case "worm_killed":
				// single player — handled locally
			case "player_drown":
				// single player — handled locally
			case "hot_pepper":
				// single player — handled locally
			case "spawn_locations":
				net.onSpawnLocations.dispatch(data);
			case "timer_sync":
				net.onTimerSync.dispatch(data.runTimeSec, data.totalSec);
			case "round_time_up":
				net.onRoundTimeUp.dispatch();
			case "ground_fish_spawn":
				net.onGroundFishSpawn.dispatch(data);
			case "ground_fish_pickup":
				net.onGroundFishPickup.dispatch(data.x, data.y);
			case "cloud_sync":
				entities.CloudShadow.windAngle = data.angle;
				net.onCloudSync.dispatch(data);
			case "seagull_spawn":
				net.onSeagullSpawn.dispatch(data);
			case "seagull_poop":
				net.onSeagullPoop.dispatch(data);
			case "seagull_despawn":
				net.onSeagullDespawn.dispatch(data);
			case "worm_spawn":
				net.onWormSpawn.dispatch(data);
			case "players_ready":
				net.onPlayersReady.dispatch();
		}
	}
}
