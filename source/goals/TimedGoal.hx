package goals;

import states.PlayState;
import managers.GameManager;

class TimedGoal extends Goal {
	private var secondsToFinish:Float = 0;

	override public function new(secondsToFinish:Float = 90) {
		super();
		this.secondsToFinish = secondsToFinish;
	}

	override function initialize(state:PlayState) {
		super.initialize(state);
		GameManager.ME.net.onRoundTimeUp.add(onRoundTimeUp);
	}

	private function onRoundTimeUp() {
		this.onComplete();
		runTimeSec = secondsToFinish;
		paused = true;
	}

	override function destroy() {
		GameManager.ME.net.onRoundTimeUp.remove(onRoundTimeUp);
		super.destroy();
	}

	override public function update(delta:Float) {
		super.update(delta);
	}
}
