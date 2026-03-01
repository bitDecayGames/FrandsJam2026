package managers;

import schema.RoundState;
import rounds.Round;
import states.PlayState;
import flixel.util.FlxSignal;

class RoundManager {
	public static var ME:RoundManager;

	public var completed:FlxSignal = new FlxSignal();

	private var complete:Bool = false;
	private var round:Round;

	public function new(round:Round) {
		ME = this;
		setRound(round);
	}

	public function initialize(state:PlayState) {
		// do stuff here on initialization of the play state if you need to
		round.initialize(state);
	}

	public function setRound(round:Round) {
		if (this.round != null) {
			for (goal in this.round.goals) {
				goal.completed.remove(this.checkForCompletion);
			}
		}
		for (goal in round.goals) {
			goal.completed.add(this.checkForCompletion);
		}
		this.round = round;
	}

	private function checkForCompletion() {
		if (complete) {
			return;
		}
		if (round.allGoalsRequired) {
			for (goal in round.goals) {
				if (!goal.isComplete()) {
					return;
				}
			}
			onComplete();
		} else {
			for (goal in round.goals) {
				if (goal.isComplete()) {
					onComplete();
					return;
				}
			}
		}
	}

	public function isComplete():Bool {
		return complete;
	}

	private function onComplete() {
		if (!complete) {
			complete = true;
			completed.dispatch();
		}
	}
}
