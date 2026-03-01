package goals;

import flixel.text.FlxText.FlxTextAlign;
import ui.font.BitmapText.PressStart;
import flixel.util.FlxColor;
import states.PlayState;
import flixel.FlxG;

class KeypressGoal extends Goal {
	override public function new() {
		super();
	}

	override function initialize(state:PlayState) {
		super.initialize(state);
	}

	override public function update(delta:Float) {
		super.update(delta);
		if (FlxG.keys.justPressed.P) {
			onComplete();
		}
	}
}
