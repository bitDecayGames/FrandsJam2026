package goals;

import flixel.FlxBasic;
import states.PlayState;
import flixel.util.FlxSignal;

class Goal extends FlxBasic {
	public var runTimeSec:Float = 0;
	public var paused:Bool = false;
	public var completed:FlxSignal = new FlxSignal();

	private var complete:Bool = false;
	private var scores:Map<String, Int> = new Map<String, Int>();

	public function initialize(state:PlayState) {
		scores = new Map<String, Int>();
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

	public function result():Array<Result> {
		var r:Array<Result> = [];
		for (k => value in scores) {
			r.push(new Result(k, value));
		}
		r.sort((a, b) -> (a.score - b.score));
		return r;
	}
}

class Result {
	public var playerId:String;
	public var score:Int;

	public function new(playerId:String, score:Int) {
		this.playerId = playerId;
		this.score = score;
	}
}
