package goals;

import states.PlayState;
import managers.GameManager;
import net.NetworkManager;

class TimedGoal extends Goal {
	private var secondsToFinish:Float = 0;

	static inline var SYNC_INTERVAL:Float = 5.0;

	private var syncCooldown:Float = SYNC_INTERVAL;

	override public function new(secondsToFinish:Float = 90) {
		super();
		this.secondsToFinish = secondsToFinish;
	}

	override function initialize(state:PlayState) {
		super.initialize(state);

		// Non-host goal doesn't tick — PlayState owns timer display for all clients
		if (!NetworkManager.IS_HOST) {
			paused = true;
		}
	}

	override public function update(delta:Float) {
		super.update(delta);

		if (!NetworkManager.IS_HOST) {
			return;
		}

		// Host periodically broadcasts current timer state and fires locally for PlayState HUD
		syncCooldown -= delta;
		if (syncCooldown <= 0) {
			syncCooldown = SYNC_INTERVAL;
			GameManager.ME.net.sendTimerSync(runTimeSec, secondsToFinish);
			GameManager.ME.net.onTimerSync.dispatch(runTimeSec, secondsToFinish);
		}

		if (runTimeSec > secondsToFinish) {
			this.onComplete();
			runTimeSec = secondsToFinish;
			paused = true;
		}
	}
}
