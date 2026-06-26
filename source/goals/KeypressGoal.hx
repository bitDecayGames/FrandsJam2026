package goals;

import flixel.text.FlxText.FlxTextAlign;
import ui.font.BitmapText.PressStart;
import flixel.util.FlxColor;
import states.PlayState;
import managers.GameManager;
import flixel.FlxG;

class KeypressGoal extends Goal {
	override public function new() {
		super();
	}

	override function initialize(state:PlayState) {
		super.initialize(state);

		#if !local
		GameManager.ME.net.onRoundTimeUp.add(onRoundTimeUp);
		#end
	}

	#if !local
	private function onRoundTimeUp() {
		this.onComplete();
	}

	override function destroy() {
		GameManager.ME.net.onRoundTimeUp.remove(onRoundTimeUp);
		super.destroy();
	}
	#end

	override public function update(delta:Float) {
		super.update(delta);
		#if local
		if (FlxG.keys.justPressed.O) {
			onComplete();
		}
		#else
		if (FlxG.keys.justPressed.O) {
			GameManager.ME.net.sendMessage("debug_end_round", {});
		}
		#end
	}
}
