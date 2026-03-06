package goals;

import managers.GameManager;
import events.gen.Event.FishCaught;
import events.EventBus;
import flixel.text.FlxText.FlxTextAlign;
import ui.font.BitmapText.PressStart;
import flixel.util.FlxColor;
import states.PlayState;

class PersonalFishCountGoal extends Goal {
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

		// TODO: MW need to add to a specific UI group here for sprite sorting
		state.add(text);

		// TODO: MW need to change this to FishCollected probably
		// GameManager.ME.net.onFishCaught.add(onFishCaught);
	}

	private function onFishCaught(playerId:String, fishId:String, fishType:Int) {
		var count = scores.get(playerId);
		if (count == null) {
			count = 0;
		}
		count++;
		scores.set(playerId, count);
		if (count >= targetCount) {
			onComplete();
		}
	}

	public function manuallySetFishCount(playerId:String, count:Int) {
		scores.set(playerId, count);
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
