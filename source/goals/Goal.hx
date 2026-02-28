package goals;

import flixel.FlxObject;
import states.PlayState;
import flixel.util.FlxSignal;

class Goal extends FlxObject {
	public var runTimeSec:Float = 0;
	public var paused:Bool = false;
	public var completed:FlxSignal = new FlxSignal();

	private var complete:Bool = false;

	public function initialize(state:PlayState) {
		state.add(this);
	}

	override public function update(delta:Float) {
		super.update(delta);
		if (!paused) {
			runTimeSec += delta;
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
