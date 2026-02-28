package goals;

import flixel.text.FlxText.FlxTextAlign;
import ui.font.BitmapText.PressStart;
import flixel.util.FlxColor;
import states.PlayState;
import flixel.FlxG;

class TimedGoal extends Goal {
	private var text:PressStart;
	private var secondsToFinish:Float = 0;

	override public function new(secondsToFinish:Float = 90) {
		super();
		this.secondsToFinish = secondsToFinish;
	}

	override function initialize(state:PlayState) {
		super.initialize(state);
		this.text = new PressStart(FlxG.width * .5, FlxG.height * .5, "Hello World");
		this.text.color = FlxColor.CYAN;
		this.text.alignment = FlxTextAlign.CENTER;
		// TODO: MW need to add to a specific UI group here for sprite sorting
		state.add(text);
	}

	override public function update(delta:Float) {
		super.update(delta);
		if (runTimeSec > secondsToFinish) {
			this.onComplete();
			runTimeSec = secondsToFinish;
			paused = true;
		}
		if (text != null) {
			secondsRemaining();
		}
	}

	public function secondsRemaining() {
		var secs = secondsToFinish - runTimeSec;
		var minutes = Math.floor(secs / 60);
		secs = Math.floor(secs - (minutes * 60));

		text.text = '${minutes}:${secs < 10 ? "0" : ""}${secs}';
	}
}
