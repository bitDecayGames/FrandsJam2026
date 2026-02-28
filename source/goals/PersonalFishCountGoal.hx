package goals;

import events.gen.Event.FishCaught;
import events.EventBus;
import flixel.FlxSprite;
import flixel.text.FlxText.FlxTextBorderStyle;
import flixel.text.FlxText.FlxTextAlign;
import ui.font.BitmapText.PressStart;
import flixel.util.FlxColor;
import states.PlayState;
import flixel.FlxG;

class PersonalFishCountGoal extends Goal {
	private var text:PressStart;
	private var targetCount:Int;
	private var currentCounts:Map<String, Int> = new Map<String, Int>();

	override public function new(targetCount:Int = 3) {
		super();
		this.targetCount = targetCount;
		currentCounts.set("me", 0);
	}

	override function initialize(state:PlayState) {
		super.initialize(state);
		this.text = new PressStart(100, 100, "Hello World");
		this.text.color = FlxColor.RED;
		this.text.alignment = FlxTextAlign.CENTER;
		// TODO: MW need to add to a specific UI group here for sprite sorting
		state.add(text);

		EventBus.subscribe(FishCaught, (event) -> {
			var count = currentCounts.get("me") + 1;
			currentCounts.set("me", count);
			if (count >= targetCount) {
				onComplete();
			}
		});
	}

	override public function update(delta:Float) {
		super.update(delta);
		if (text != null) {
			countRemaining();
		}
	}

	public function countRemaining() {
		var s = "";
		for (k => value in currentCounts) {
			s += '${k}:${value}\n';
		}
		text.text = s;
	}
}
