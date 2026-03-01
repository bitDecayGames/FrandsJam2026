package goals;

import managers.GameManager;
import managers.GameManager.SoldFishEntry;
import flixel.text.FlxText.FlxTextAlign;
import ui.font.BitmapText.PressStart;
import flixel.util.FlxColor;
import states.PlayState;

class PersonalFishSoldGoal extends Goal {
	private var text:PressStart;
	private var targetCount:Int;

	override public function new(targetCount:Int = 3) {
		super();
		this.targetCount = targetCount;
	}

	override function initialize(state:PlayState) {
		super.initialize(state);
		this.text = new PressStart(100, 100, "Hello World");
		this.text.color = FlxColor.RED;
		this.text.alignment = FlxTextAlign.CENTER;
		state.add(text);

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

	override public function update(delta:Float) {
		super.update(delta);
		if (text != null) {
			countRemaining();
		}
	}

	public function countRemaining() {
		var s = "";
		for (k => value in scores) {
			s += '${k}:${value}\n';
		}
		text.text = s;
	}
}
