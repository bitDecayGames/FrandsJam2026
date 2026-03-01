package managers;

import goals.PersonalFishCountGoal;
import goals.TimedGoal;
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

class GameManager {
	public static var ME:GameManager;

	public var fish:FishManager;
	public var net:NetworkManager;

	private var round:RoundManager;
	private var totalRounds:Int = 0;
	private var currentRoundNumber:Int = 0;

	private var rounds:Array<Round>;
	private var roundStatus:String = RoundState.STATUS_INACTIVE;

	public function new() {
		ME = this;
		fish = new FishManager(new FishDb());
		net = new NetworkManager();
		net.onRoundUpdate.add(sync);
		net.onPlayersReady.add(playersReady);
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
						new Round([new TimedGoal(5), new PersonalFishCountGoal(3)]),
						new Round([new TimedGoal(3), new PersonalFishCountGoal(3)]),
						new Round([new TimedGoal(5), new PersonalFishCountGoal(3)]),
					]);
					nextRoundNumber = currentRoundNumber;
				}
				nextStatus = RoundState.STATUS_PRE_ROUND;
			case RoundState.STATUS_PRE_ROUND:
				nextStatus = RoundState.STATUS_ACTIVE;
			case RoundState.STATUS_ACTIVE:
				nextStatus = RoundState.STATUS_POST_ROUND;
			case RoundState.STATUS_POST_ROUND:
				trace('current round ${currentRoundNumber} -> ${currentRoundNumber + 1} / ${totalRounds}');
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
		setStatus(nextStatus, nextRoundNumber);
		if (rounds != null && rounds.length > 0) {
			setCurrentRound(new RoundManager(rounds[currentRoundNumber]));
		}
		switchStateBasedOnStatus();
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
		if (NetworkManager.IS_HOST) {
			roundStatus = status;
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
				FlxG.switchState(() -> new PreRoundState());
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
