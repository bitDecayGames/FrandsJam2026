package goals;

import managers.GameManager;
import managers.GameManager.SoldFishEntry;
import states.PlayState;

class PersonalFishSoldGoal extends Goal {
	private var targetCount:Int;

	override public function new(targetCount:Int = 3) {
		super();
		this.targetCount = targetCount;
	}

	override function initialize(state:PlayState) {
		super.initialize(state);
		GameManager.ME.onFishSoldLocal.add(onFishSold);
	}

	private function onFishSold(sessionId:String, entry:SoldFishEntry) {
		var count = scores.get(sessionId);
		if (count == null) {
			count = 0;
		}
		count++;
		scores.set(sessionId, count);
		if (count >= targetCount) {
			onComplete();
		}
	}
}
