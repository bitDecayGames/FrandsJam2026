package net;

import schema.GameState.P_Input;
import schema.FishState;

/**
 * In-process game server for single-player / local mode.
 * Runs the same GameLogic as the Colyseus server, but with direct
 * function calls instead of websocket messages.
 * Created by NetworkManager.connect() when in local mode.
**/
class LocalRoom {
	var logic:GameLogic;
	var net:NetworkManager;
	var sessionId:String;

	public function new(net:NetworkManager) {
		this.net = net;
		sessionId = "local_player";

		logic = new GameLogic();

		// Wire broadcast — dispatches directly to NetworkManager signals
		logic.broadcast = (topic, data) -> dispatchMessage(topic, data);
		logic.sendToClient = (_, topic, data) -> dispatchMessage(topic, data);
		logic.onBushAdded = (x, y) -> net.onBushAdded.dispatch(x, y);
		logic.onFishAdded = (id, fish) -> net.onFishAdded.dispatch(id, fish);

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

	/** Called each frame from NetworkManager.update() */
	public function update(elapsed:Float) {
		logic.update(elapsed * 1000); // GameLogic expects ms
	}

	/** Route a client message through GameLogic */
	public function sendMessage(topic:String, data:Dynamic) {
		logic.handleMessage(sessionId, topic, data);
	}

	public function getState():schema.GameState {
		return logic.state;
	}

	/** Dispatch a "server" message to the local client's NetworkManager signals */
	function dispatchMessage(topic:String, data:Dynamic) {
		switch (topic) {
			case "cast_start":
				net.onCastStart.dispatch(data.sessionId, data.dir);
			case "cast_line":
				net.onCastLine.dispatch(data.sessionId, data.x, data.y, data.dir);
			case "fish_caught":
				net.onFishCaught.dispatch(data.sessionId, data.fishId, data.fishType);
			case "line_pulled":
				net.onLinePulled.dispatch(data.sessionId);
			case "fish_despawn":
				net.onFishDespawn.dispatch(data.id, data.respawnTime);
			case "rock_splash":
				net.onRockSplash.dispatch(data.x, data.y, data.big);
			case "throw_rock":
				var dest = flixel.math.FlxPoint.get(data.targetX, data.targetY);
				net.onThrowRock.dispatch(data.sessionId, dest, data.big, data.dir);
				dest.put();
			case "fish_sold":
				net.onFishSold.dispatch(data.sessionId, Std.int(data.fishType), Std.int(data.lengthCm), Std.int(data.value));
			case "weed_burst":
				net.onWeedBurst.dispatch(data.sessionId, Std.int(data.index));
			case "world_items":
				net.onWorldItems.dispatch(data);
			case "item_pickup":
				// In single player, no need to relay to other clients
			case "bush_rustle":
				// In single player, no need to relay
			case "bush_ignite":
				// In single player, no need to relay
			case "weed_ignite":
				// In single player, no need to relay
			case "worm_killed":
				// In single player, no need to relay
			case "player_drown":
				// In single player, no need to relay
			case "hot_pepper":
				// In single player, no need to relay
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
