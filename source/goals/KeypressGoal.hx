package goals;

import states.PlayState;
import managers.GameManager;
import flixel.FlxG;

class KeypressGoal extends Goal {
	override public function new() {
		super();
	}

	override function initialize(state:PlayState) {
		super.initialize(state);
		GameManager.ME.net.onRoundTimeUp.add(onRoundTimeUp);
	}

	private function onRoundTimeUp() {
		this.onComplete();
	}

	override function destroy() {
		GameManager.ME.net.onRoundTimeUp.remove(onRoundTimeUp);
		super.destroy();
	}

	override public function update(delta:Float) {
		super.update(delta);
		if (FlxG.keys.justPressed.O) {
			GameManager.ME.net.sendMessage("debug_end_round", {});
		}
	}
}
