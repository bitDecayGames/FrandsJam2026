package goals;

import states.PlayState;
import managers.GameManager;
import net.NetworkManager;

class TimedGoal extends Goal {
	private var secondsToFinish:Float = 0;

	override public function new(secondsToFinish:Float = 90) {
		super();
		this.secondsToFinish = secondsToFinish;
	}

	override function initialize(state:PlayState) {
		super.initialize(state);

		// Timer sync is now server-originated; all clients just receive it.
		// The goal still ticks locally for the HUD (via base Goal.update).

		#if !local
		// Listen for server round_time_up to complete the goal
		GameManager.ME.net.onRoundTimeUp.add(onRoundTimeUp);
		#end
	}

	#if !local
	private function onRoundTimeUp() {
		this.onComplete();
		runTimeSec = secondsToFinish;
		paused = true;
	}

	override function destroy() {
		GameManager.ME.net.onRoundTimeUp.remove(onRoundTimeUp);
		super.destroy();
	}
	#end

	override public function update(delta:Float) {
		super.update(delta);

		// In local mode, the goal self-completes when time is up
		#if local
		if (runTimeSec > secondsToFinish) {
			this.onComplete();
			runTimeSec = secondsToFinish;
			paused = true;
		}
		#end
	}
}
