package managers;

import schema.BushState;
import schema.FishState;
import io.colyseus.serializer.schema.Callbacks;
import schema.GameState;
import io.colyseus.Room;
import schema.PlayerState;
import goals.PersonalFishCountGoal;
import goals.PersonalFishSoldGoal;
import goals.TimedGoal;
import goals.KeypressGoal;
import entities.Player;
import flixel.util.FlxSignal.FlxTypedSignal;
import flixel.util.FlxTimer;
import schema.RoundState;
import net.NetworkManager;
import managers.FishManager.FishDb;
import rounds.Round;
import states.VictoryState;
import states.PlayState;
import states.PostRoundState;
import states.PreRoundState;
import states.CharacterSelectState;
import flixel.FlxG;

typedef SoldFishEntry = {
	fishType:Int,
	lengthCm:Int,
	value:Int
};

class GameManager {
	public var fish:FishManager;

	var colyRoom:Room<GameState>;

	public var net:NetworkManager;

	private var round:RoundManager;
	private var totalRounds:Int = 0;
	private var currentRoundNumber:Int = 0;

	private var rounds:Array<Round>;
	private var roundStatus:String = RoundState.STATUS_INACTIVE;

	public var sessions = new Array<String>();
	public var names = new Map<String, String>();
	public var skins = new Map<String, Int>(); // sessionId -> skinIndex
	public var readyStates = new Map<String, Bool>(); // sessionId -> ready
	public var scores = new Map<String, Int>(); // sessionId -> score
	// soldFish: round -> sessionId -> Array<SoldFishEntry>
	public var soldFish:Array<Map<String, Array<SoldFishEntry>>> = [];
	// weedKills: round -> sessionId -> count
	public var weedKills:Array<Map<String, Int>> = [];
	// wormKills: round -> sessionId -> count
	public var wormKills:Array<Map<String, Int>> = [];
	public var mySessionId = "";
	public var mySkinIndex:Int = -1; // -1 means no skin selected

	/** Fires whenever any player sells a fish (local or remote): sessionId, entry */
	public var onFishSoldLocal = new FlxTypedSignal<String->SoldFishEntry->Void>();

	public function new(room:Room<GameState>) {
		setupCallbacks(room);
		init([
			new Round([new TimedGoal(), new PersonalFishSoldGoal(8), new KeypressGoal()]),
			new Round([new TimedGoal(), new PersonalFishSoldGoal(8), new KeypressGoal()]),
			new Round([new TimedGoal(), new PersonalFishSoldGoal(8), new KeypressGoal()]),
		]);

		fish = new FishManager(new FishDb());
	}

	private function setupCallbacks(room:Room<GameState>) {
		mySessionId = room.sessionId;
		// onJoined.dispatch(mySessionId);

		// onPlayersReady.dispatch();

		room.onStateChange += (newState:GameState) -> {
			trace("NetMan: received state change:");
			trace('  - FishCount: ${newState.fish.length}');
		};

		var cb = Callbacks.get(room);

		// cb.listen("hostSessionId", (val:String, prev:String) -> {
		// 	var prevIsHost = IS_HOST;
		// 	IS_HOST = val == mySessionId;
		// 	trace('[NetMan] host changed ${prev} -> ${val}. IS_HOST: ${IS_HOST}');
		// 	onHostChanged.dispatch(IS_HOST, prevIsHost);
		// });

		// cb.listen("round", (round:RoundState) -> {
		// 	trace('RoundState: ${round}');
		// 	onRoundUpdate.dispatch(round);
		// });

		// cb.onAdd(room.state, "fish", (fish:FishState, id:String) -> {
		// 	trace('NetworkManager: fish added ${id}');
		// 	onFishAdded.dispatch(id, fish);

		// 	cb.listen(fish, "x", (_, _) -> {
		// 		// trace('NetMan: (fish: ${id} x update');
		// 		onFishMove.dispatch(id, fish);
		// 	});
		// 	cb.listen(fish, "y", (_, _) -> {
		// 		// trace('NetMan: (fish: ${id} y update');
		// 		onFishMove.dispatch(id, fish);
		// 	});
		// });

		// cb.onAdd(room.state, "bushes", (bush:BushState, id:String) -> {
		// 	trace('NetworkManager: bush added ${id} at ${bush.x}, ${bush.y}');
		// 	onBushAdded.dispatch(bush.x, bush.y);
		// });

		// cb.listen("shopReady", (val:Bool, _:Bool) -> {
		// 	if (val) {
		// 		trace('NetworkManager: shop placed at ${room.state.shopX}, ${room.state.shopY}');
		// 		onShopPlaced.dispatch(room.state.shopX, room.state.shopY);
		// 	}
		// });

		// cb.onAdd(room.state, "players", (player:PlayerState, sessionId:String) -> {
		// 	playerDebugTrace('NetworkManager: player added $sessionId');
		// 	if (sessionId == mySessionId) {
		// 		return;
		// 	}
		// 	onPlayerAdded.dispatch(sessionId, {state: player});

		// 	cb.onChange(player, () -> {
		// 		playerDebugTrace('NetMan: got onChange for player');
		// 		onPlayerChanged.dispatch(sessionId, {state: player});
		// 	});

		// 	cb.listen(player, "x", (_, prevX:Float) -> {
		// 		playerDebugTrace('NetMan: (sesh: ${sessionId} x: ${prevX} -> ${player.x}');
		// 		onPlayerChanged.dispatch(sessionId, {state: player, prevX: prevX});
		// 	});
		// 	cb.listen(player, "y", (_, prevY:Float) -> {
		// 		playerDebugTrace('NetMan: (sesh: ${sessionId} y: ${prevY} -> ${player.y}');
		// 		onPlayerChanged.dispatch(sessionId, {state: player, prevY: prevY});
		// 	});
		// 	cb.listen(player, "velocityX", (_, prevY:Float) -> {
		// 		playerDebugTrace('NetMan: (sesh: ${sessionId} y: ${prevY} -> ${player.y}');
		// 		onPlayerChanged.dispatch(sessionId, {state: player});
		// 	});
		// 	cb.listen(player, "velocitY", (_, prevY:Float) -> {
		// 		playerDebugTrace('NetMan: (sesh: ${sessionId} y: ${prevY} -> ${player.y}');
		// 		onPlayerChanged.dispatch(sessionId, {state: player});
		// 	});
		// 	cb.listen(player, "skinIndex", (_, _) -> {
		// 		playerDebugTrace('NetMan: sesh: ${sessionId} skinIndex: ${player.skinIndex}');
		// 		onSkinChanged.dispatch(sessionId, player.skinIndex);
		// 	});
		// 	cb.listen(player, "ready", (_, _) -> {
		// 		playerDebugTrace('NetMan: sesh: ${sessionId} ready: ${player.ready}');
		// 		onPlayerReadyChanged.dispatch(sessionId, player.ready);
		// 	});
		// 	cb.listen(player, "score", (_, _) -> {
		// 		playerDebugTrace('NetMan: sesh: ${sessionId} score: ${player.score}');
		// 		onScoreChanged.dispatch(sessionId, player.score);
		// 	});
		// });

		// cb.onRemove(room.state, "players", (player:PlayerState, sessionId:String) -> {
		// 	playerDebugTrace('NetworkManager: player removed $sessionId');
		// 	if (sessionId == mySessionId) {
		// 		return;
		// 	}
		// 	onPlayerRemoved.dispatch(sessionId);
		// });

		// room.onMessage("cast_line", (message:{
		// 	sessionId:String,
		// 	x:Float,
		// 	y:Float,
		// 	dir:String
		// }) -> {
		// 	trace('[NetMan] cast_line => ${message.sessionId} ${message.x},${message.y} dir:${message.dir}');
		// 	// var x:Float = message.x;
		// 	// var y:Float = message.y;
		// 	onCastLine.dispatch(message.sessionId, message.x, message.y, message.dir);
		// });

		// room.onMessage("fish_caught", (message:Dynamic) -> {
		// 	trace('[NetMan] fish_caught => sessionId:${message.sessionId} fishId:${message.fishId} fishType:${message.fishType}');
		// 	var ft:Int = message.fishType != null ? Std.int(message.fishType) : 0;
		// 	onFishCaught.dispatch(message.sessionId, message.fishId, ft);
		// });
		// room.onMessage("fish_pocketed", (message) -> {
		// 	trace('[NetMan] fish_pocketed => sessionId:${message.sessionId} fishId:${message.fishId}');
		// 	onFishPocketed.dispatch(message.sessionId, message.fishId);
		// });
		// room.onMessage("fish_banked", (message) -> {
		// 	trace('[NetMan] fish_banked => sessionId:${message.sessionId} fishId:${message.fishId}');
		// 	onFishBanked.dispatch(message.sessionId, message.fishId);
		// });

		// room.onMessage("line_pulled", (message) -> {
		// 	trace('[NetMan] line_pulled => sessionId:${message.sessionId}');
		// 	onLinePulled.dispatch(message.sessionId);
		// });

		// room.onMessage("fish_despawn", (message:{id:String, respawnTime:Float}) -> {
		// 	trace('[NetMan] fish_despawn => fishId:${message.id} respawnTime:${message.respawnTime}');
		// 	onFishDespawn.dispatch(message.id, message.respawnTime);
		// });

		// room.onMessage("rock_splash", (message:Dynamic) -> {
		// 	var sx:Float = message.x;
		// 	var sy:Float = message.y;
		// 	var sbig:Bool = message.big;
		// 	trace('[NetMan] rock_splash => $sx, $sy big=$sbig');
		// 	onRockSplash.dispatch(sx, sy, sbig);
		// });

		// room.onMessage("throw_rock", (message:Dynamic) -> {
		// 	trace('[NetMan] throw_rock => sessionId:${message.sessionId} target:(${message.targetX},${message.targetY}) big:${message.big} dir:${message.dir}');

		// 	var dest = FlxPoint.get(message.targetX, message.targetY);
		// 	onThrowRock.dispatch(message.sessionId, dest, message.big, message.dir);
		// 	dest.put();
		// });

		// room.onMessage("fish_sold", (message:Dynamic) -> {
		// 	trace('[NetMan] fish_sold => sessionId:${message.sessionId} fishType:${message.fishType} lengthCm:${message.lengthCm} value:${message.value}');
		// 	onFishSold.dispatch(message.sessionId, Std.int(message.fishType), Std.int(message.lengthCm), Std.int(message.value));
		// });

		// room.onMessage("weed_burst", (message:Dynamic) -> {
		// 	trace('[NetMan] weed_burst => sessionId:${message.sessionId} index:${message.index}');
		// 	onWeedBurst.dispatch(message.sessionId, Std.int(message.index));
		// });

		// room.onMessage("world_items", (message:Dynamic) -> {
		// 	trace('[NetMan] world_items received');
		// 	onWorldItems.dispatch(message);
		// });

		// room.onMessage("item_pickup", (message:Dynamic) -> {
		// 	trace('[NetMan] item_pickup => sessionId:${message.sessionId} itemType:${message.itemType} index:${message.index}');
		// 	onItemPickup.dispatch(message.sessionId, message.itemType, Std.int(message.index));
		// });

		// room.onMessage("bush_rustle", (message:Dynamic) -> {
		// 	trace('[NetMan] bush_rustle => index:${message.index} dir:(${message.dirX},${message.dirY})');
		// 	onBushRustle.dispatch(Std.int(message.index), message.dirX, message.dirY);
		// });

		// room.onMessage("worm_killed", (message:Dynamic) -> {
		// 	trace('[NetMan] worm_killed => sessionId:${message.sessionId}');
		// 	onWormKilled.dispatch(message.sessionId);
		// });

		// room.onMessage("hot_pepper", (message:Dynamic) -> {
		// 	trace('[NetMan] hot_pepper => sessionId:${message.sessionId} isStart:${message.isStart}');
		// 	onHotPepper.dispatch(message.sessionId, message.isStart == true);
		// });

		// room.onMessage("spawn_locations", (message:Dynamic) -> {
		// 	trace('[NetMan] spawn_locations received');
		// 	onSpawnLocations.dispatch(message);
		// });

		// room.onMessage("timer_sync", (message:Dynamic) -> {
		// 	trace('[NetMan] timer_sync received: runTimeSec=${message.runTimeSec} totalSec=${message.totalSec}');
		// 	onTimerSync.dispatch(message.runTimeSec, message.totalSec);
		// });
	}

	private function init(rounds:Array<Round>) {
		if (rounds == null) {
			throw "rounds cannot be null";
		}
		if (rounds.length == 0) {
			throw "rounds must be greater than 0";
		}
		for (i in 0...rounds.length) {
			var round = rounds[i];
			if (round == null || round.goals == null || round.goals.length == 0) {
				throw 'rounds[${i}] cannot be empty';
			}
		}
		this.rounds = rounds;
		roundStatus = RoundState.STATUS_LOBBY;
		totalRounds = rounds.length;
		currentRoundNumber = 0;
		setCurrentRound(new RoundManager(rounds[0]));
		colyRoom.send("round_update", {
			status: roundStatus,
			currentRound: currentRoundNumber,
			totalRounds: totalRounds,
		});
	}

	private function handleKicked() {
		sessions = [];
	}

	private function onPlayerJoined(sessionId:String) {
		trace('GameMan: joined as $sessionId');
		mySessionId = sessionId;
	}

	private function playerNameChanged(sessionId:String, name:String) {
		names.set(sessionId, name);
	}

	private function onSkinChanged(sessionId:String, skinIndex:Int) {
		if (skinIndex < 0) {
			skins.remove(sessionId);
		} else {
			skins.set(sessionId, skinIndex);
		}
	}

	private function onPlayerReadyChanged(sessionId:String, ready:Bool) {
		readyStates.set(sessionId, ready);
	}

	private function onScoreChanged(sessionId:String, score:Int) {
		scores.set(sessionId, score);
	}

	private function onFishSold(sessionId:String, fishType:Int, lengthCm:Int, value:Int) {
		recordSoldFish(sessionId, {fishType: fishType, lengthCm: lengthCm, value: value});
	}

	/** Record a sold fish for the current round. */
	public function recordSoldFish(sessionId:String, entry:SoldFishEntry) {
		// Ensure the soldFish array has an entry for the current round
		while (soldFish.length <= currentRoundNumber) {
			soldFish.push(new Map<String, Array<SoldFishEntry>>());
		}
		var roundMap = soldFish[currentRoundNumber];
		if (!roundMap.exists(sessionId)) {
			roundMap.set(sessionId, []);
		}
		roundMap.get(sessionId).push(entry);
		onFishSoldLocal.dispatch(sessionId, entry);
	}

	/** Get sold fish for a specific round and session. */
	public function getSoldFish(roundNum:Int, sessionId:String):Array<SoldFishEntry> {
		if (roundNum < 0 || roundNum >= soldFish.length) {
			return [];
		}
		var roundMap = soldFish[roundNum];
		if (!roundMap.exists(sessionId)) {
			return [];
		}
		return roundMap.get(sessionId);
	}

	/** Record a weed kill for the current round. */
	public function recordWeedKill(sessionId:String) {
		while (weedKills.length <= currentRoundNumber) {
			weedKills.push(new Map<String, Int>());
		}
		var roundMap = weedKills[currentRoundNumber];
		var cur = roundMap.exists(sessionId) ? roundMap.get(sessionId) : 0;
		roundMap.set(sessionId, cur + 1);
	}

	/** Record a worm kill for the current round. */
	public function recordWormKill(sessionId:String) {
		while (wormKills.length <= currentRoundNumber) {
			wormKills.push(new Map<String, Int>());
		}
		var roundMap = wormKills[currentRoundNumber];
		var cur = roundMap.exists(sessionId) ? roundMap.get(sessionId) : 0;
		roundMap.set(sessionId, cur + 1);
	}

	/** Get weed kills for a specific round and session. */
	public function getWeedKills(roundNum:Int, sessionId:String):Int {
		if (roundNum < 0 || roundNum >= weedKills.length) {
			return 0;
		}
		var roundMap = weedKills[roundNum];
		return roundMap.exists(sessionId) ? roundMap.get(sessionId) : 0;
	}

	/** Get worm kills for a specific round and session. */
	public function getWormKills(roundNum:Int, sessionId:String):Int {
		if (roundNum < 0 || roundNum >= wormKills.length) {
			return 0;
		}
		var roundMap = wormKills[roundNum];
		return roundMap.exists(sessionId) ? roundMap.get(sessionId) : 0;
	}

	/** Get the current round number (0-indexed). */
	public function getCurrentRoundNumber():Int {
		return currentRoundNumber;
	}

	public function getFirstAvailableSkinIndex():Int {
		var selectedSkinIdxs = [];
		for (_ => sIdx in skins) {
			selectedSkinIdxs.push(sIdx);
		}

		for (i in 0...Player.SKINS.length) {
			if (!selectedSkinIdxs.contains(i)) {
				return i;
			}
		}

		return -1;
	}

	private function onPlayerJoinLobby(sessionId:String, data:PlayerLobbyData) {
		if (sessionId == mySessionId) {
			return;
		}

		trace('GameMan: new player joined lobby: $sessionId');
		sessions.push(sessionId);
		names.set(sessionId, data.name);
		if (data.skinIndex >= 0) {
			skins.set(sessionId, data.skinIndex);
		}
	}

	private function onPlayerAdded(sessionId:String, data:PlayerUpdateData) {
		if (sessionId == mySessionId) {
			return;
		}

		trace('GameMan: new session added to game: $sessionId');
		sessions.push(sessionId);
		names.set(sessionId, data.state.name);
		if (data.state.skinIndex >= 0) {
			skins.set(sessionId, data.state.skinIndex);
		}
	}

	function onPlayerRemoved(sessionId:String) {
		if (sessionId == mySessionId) {
			return;
		}

		trace('GameMan: session removed: $sessionId');
		sessions.remove(sessionId);
		names.remove(sessionId);
		skins.remove(sessionId);
		readyStates.remove(sessionId);
		scores.remove(sessionId);
	}

	private function onHostChange(isHost:Bool, prevIsHost:Bool) {
		// the host has just been changed to you
		if (isHost && isHost != prevIsHost) {
			// TODO: MW not sure what to do yet...
		}
	}

	private function setCurrentRound(round:RoundManager) {
		if (this.round != null) {
			this.round.completed.remove(this.onRoundDone);
		}
		this.round = round;
		this.round.completed.add(this.onRoundDone);
	}

	private function onRoundDone() {
		FlxG.switchState(() -> new PostRoundState());
	}

	private function playersReady() {
		if (round == null && rounds != null && rounds.length > 0) {
			setCurrentRound(new RoundManager(rounds[0]));
		}
		// var nextStatus:String;
		var nextRoundNumber:Int = currentRoundNumber;
		switch (roundStatus) {
			case RoundState.STATUS_LOBBY:
			case RoundState.STATUS_ACTIVE:
				// nextStatus = RoundState.STATUS_POST_ROUND;
			case RoundState.STATUS_POST_ROUND:
				nextRoundNumber = currentRoundNumber + 1;
				if (nextRoundNumber >= totalRounds) {
					setStatus(RoundState.STATUS_END_GAME, nextRoundNumber);
					endGame();
					return;
				}
			// nextStatus = RoundState.STATUS_ACTIVE;
			case RoundState.STATUS_END_GAME:
				// nextStatus = RoundState.STATUS_LOBBY;
			case RoundState.STATUS_INACTIVE:
				// nextStatus = RoundState.STATUS_LOBBY;
			default:
				throw 'invalid round status: ${roundStatus}';
		}
		// trace('players ready: ${roundStatus} -> ${nextStatus}');
		var wasLobby = roundStatus == RoundState.STATUS_LOBBY;
		// setStatus(nextStatus, nextRoundNumber);
		if (rounds != null && rounds.length > 0) {
			setCurrentRound(new RoundManager(rounds[currentRoundNumber]));
		}
		if (wasLobby) {
			FlxTimer.wait(2, () -> {
				switchStateBasedOnStatus();
			});
		} else {
			switchStateBasedOnStatus();
		}
	}

	public function endGame() {
		trace("end the game");
		net.disconnect();

		reset();

		FlxG.switchState(() -> new VictoryState());
	}

	public function sync(remoteState:RoundState) {
		if (totalRounds != remoteState.totalRounds) {
			trace('sync total rounds: ${totalRounds} -> ${remoteState.totalRounds}');
			totalRounds = remoteState.totalRounds;
		}
		if (currentRoundNumber != remoteState.currentRound || roundStatus != remoteState.status) {
			if (currentRoundNumber >= 0 && currentRoundNumber < totalRounds && currentRoundNumber != remoteState.currentRound) {
				trace('sync current round: ${currentRoundNumber} -> ${remoteState.currentRound}');
				currentRoundNumber = remoteState.currentRound;
				setCurrentRound(new RoundManager(rounds[currentRoundNumber]));
			}
			if (roundStatus != remoteState.status) {
				trace('sync status: ${roundStatus} -> ${remoteState.status}');
			}
			roundStatus = remoteState.status;
			switchStateBasedOnStatus();
		}
	}

	public function setStatus(status:String, ?currentRound:Int = -1) {
		roundStatus = status;
		if (NetworkManager.IS_HOST) {
			if (currentRound >= 0 && currentRound != currentRoundNumber) {
				trace('set status: ${roundStatus} -> ${status} and currentRound: ${currentRoundNumber} -> ${currentRoundNumber}');
				currentRoundNumber = currentRound;
				colyRoom.send("round_update", {
					status: roundStatus,
					currentRound: currentRound,
				});
			} else {
				trace('set status: ${roundStatus} -> ${status}');
				colyRoom.send("round_update", {
					status: roundStatus,
				});
			}
		}
	}

	private function reset() {
		totalRounds = 0;
		currentRoundNumber = 0;

		rounds = [];
		roundStatus = RoundState.STATUS_INACTIVE;

		sessions = [];
		names = new Map<String, String>();
		skins = new Map<String, Int>();
		readyStates = new Map<String, Bool>();
		scores = new Map<String, Int>();
		soldFish = [];
		weedKills = [];
		wormKills = [];
		mySessionId = "";
		mySkinIndex = -1;
	}

	private function switchStateBasedOnStatus() {
		trace('switch state based on status ${roundStatus}');
		switch (roundStatus) {
			case RoundState.STATUS_LOBBY:
				// FlxG.switchState(() -> new CharacterSelectState());
			case RoundState.STATUS_ACTIVE:
				FlxG.switchState(() -> new PlayState(null));
			case RoundState.STATUS_POST_ROUND:
				FlxG.switchState(() -> new PostRoundState());
			case RoundState.STATUS_END_GAME:
				endGame();
			case RoundState.STATUS_INACTIVE:
				trace("round status is inactive...");
			default:
				throw 'invalid round status: ${roundStatus}';
		}
	}
}
