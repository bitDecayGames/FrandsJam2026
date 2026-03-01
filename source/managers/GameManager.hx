package managers;

import schema.PlayerState;
import goals.PersonalFishCountGoal;
import goals.PersonalFishSoldGoal;
import goals.TimedGoal;
import goals.KeypressGoal;
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
import states.LobbyState;
import flixel.FlxG;

typedef SoldFishEntry = {
	fishType:Int,
	lengthCm:Int,
	value:Int
};

class GameManager {
	public static var ME:GameManager;

	public var fish:FishManager;
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

	public function new() {
		ME = this;
		fish = new FishManager(new FishDb());
		net = new NetworkManager();
		net.onJoined.add(onPlayerJoined);
		net.onPlayerAdded.add(onPlayerAdded);
		net.onPlayerRemoved.add(onPlayerRemoved);
		net.onRoundUpdate.add(sync);
		net.onPlayersReady.add(playersReady);
		net.onPlayerNameChanged.add(playerNameChanged);
		net.onSkinChanged.add(onSkinChanged);
		net.onPlayerReadyChanged.add(onPlayerReadyChanged);
		net.onScoreChanged.add(onScoreChanged);
		net.onFishSold.add(onFishSold);
		net.onWormKilled.add(recordWormKill);
		net.onHostChanged.add(onHostChange);
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
		GameManager.ME.net.sendMessage("round_update", {
			status: roundStatus,
			currentRound: currentRoundNumber,
			totalRounds: totalRounds,
		});
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

	private function onPlayerAdded(sessionId:String, data:PlayerUpdateData) {
		if (sessionId == mySessionId) {
			return;
		}

		trace('GameMan: new session added: $sessionId');
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
		var nextStatus:String;
		var nextRoundNumber:Int = currentRoundNumber;
		switch (roundStatus) {
			case RoundState.STATUS_LOBBY:
				if (NetworkManager.IS_HOST) {
					init([
						new Round([new TimedGoal(), new PersonalFishSoldGoal(3), new KeypressGoal()]),
						new Round([new TimedGoal(), new PersonalFishSoldGoal(3), new KeypressGoal()]),
						new Round([new TimedGoal(), new PersonalFishSoldGoal(3), new KeypressGoal()]),
					]);
					// needs to force this back to 0
					nextRoundNumber = currentRoundNumber;
				}
				nextStatus = RoundState.STATUS_PRE_ROUND;
			case RoundState.STATUS_PRE_ROUND:
				nextStatus = RoundState.STATUS_ACTIVE;
			case RoundState.STATUS_ACTIVE:
				nextStatus = RoundState.STATUS_POST_ROUND;
			case RoundState.STATUS_POST_ROUND:
				nextRoundNumber = currentRoundNumber + 1;
				if (nextRoundNumber >= totalRounds) {
					setStatus(RoundState.STATUS_END_GAME, nextRoundNumber);
					endGame();
					return;
				}
				nextStatus = RoundState.STATUS_PRE_ROUND;
			case RoundState.STATUS_END_GAME:
				nextStatus = RoundState.STATUS_LOBBY;
			case RoundState.STATUS_INACTIVE:
				nextStatus = RoundState.STATUS_LOBBY;
			default:
				throw 'invalid round status: ${roundStatus}';
		}
		trace('players ready: ${roundStatus} -> ${nextStatus}');
		var wasLobby = roundStatus == RoundState.STATUS_LOBBY;
		setStatus(nextStatus, nextRoundNumber);
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
				GameManager.ME.net.sendMessage("round_update", {
					status: roundStatus,
					currentRound: currentRound,
				});
			} else {
				trace('set status: ${roundStatus} -> ${status}');
				GameManager.ME.net.sendMessage("round_update", {
					status: roundStatus,
				});
			}
		}
	}

	private function switchStateBasedOnStatus() {
		trace('switch state based on status ${roundStatus}');
		switch (roundStatus) {
			case RoundState.STATUS_LOBBY:
				FlxG.switchState(() -> new LobbyState());
			case RoundState.STATUS_PRE_ROUND:
				trace('scooby doo 1');
				FlxG.switchState(() -> {
					trace('scooby doo 2');
					return new PreRoundState();
				});
			case RoundState.STATUS_ACTIVE:
				FlxG.switchState(() -> new PlayState(round));
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
