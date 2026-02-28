package managers;

import schema.RoundState;
import net.NetworkManager;
import managers.FishManager.FishDb;
import rounds.Round;
import states.VictoryState;
import states.PlayState;
import flixel.FlxG;

class GameManager {
	public static var ME:GameManager;

	public var fish:FishManager;
	public var net:NetworkManager;

	private var round:RoundManager;
	private var totalRounds:Int = -1;
	private var currentRoundNumber:Int = -1;

	private var rounds:Array<Round>;

	public function new(rounds:Array<Round>) {
		ME = this;
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
		this.totalRounds = rounds.length;
		currentRoundNumber = 0;

		fish = new FishManager(new FishDb());

		net = new NetworkManager();
	}

	public function start() {
		if (currentRoundNumber == 1) {
			net.sendMessage("round_update", {
				status: RoundState.STATUS_LOBBY,
				currentRound: currentRoundNumber,
				totalRounds: totalRounds,
			});
		}
		setCurrentRound(new RoundManager(rounds[currentRoundNumber]));
	}

	private function setCurrentRound(round:RoundManager) {
		if (this.round != null) {
			this.round.completed.remove(this.checkRound);
		}
		this.round = round;
		this.round.completed.add(this.checkRound);

		net.sendMessage("round_update", {
			status: RoundState.STATUS_PRE_ROUND,
			currentRound: currentRoundNumber,
		});

		FlxG.switchState(() -> new PlayState(round));
	}

	private function checkRound() {
		if (round.isComplete()) {
			net.sendMessage("round_update", {
				status: RoundState.STATUS_POST_ROUND,
			});
			round.completed.remove(this.checkRound);
			currentRoundNumber += 1;
			if (currentRoundNumber >= totalRounds) {
				net.sendMessage("round_update", {
					status: RoundState.STATUS_END_GAME,
				});
				FlxG.switchState(() -> new VictoryState());
				currentRoundNumber = 0;
			} else {
				// gets called multiple times, but the trick is that currentRoundNumber changes between calling this start function
				start();
			}
		}
	}
}
