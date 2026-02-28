package goals;

import events.gen.Event.FishCaught;
import events.EventBus;
import flixel.text.FlxText.FlxTextAlign;
import ui.font.BitmapText.PressStart;
import flixel.util.FlxColor;
import states.PlayState;

class GroupFishCountGoal extends Goal {
	private var text:PressStart;
	private var targetCount:Int;
	private var sum:Int = 0;

	override public function new(targetCount:Int = 10) {
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
		EventBus.subscribe(FishCaught, (event) -> {
			var count = scores.get(event.ownerId);
			if (count == null) {
				count = 0;
			}
			count++;
			scores.set(event.ownerId, count);

			sum++;
			if (sum >= targetCount) {
				onComplete();
			}
		});
	}

	public function manuallySetFishCount(playerId:String, count:Int) {
		scores.set(playerId, count);
		if (count >= targetCount) {
			onComplete();
		}
		sum = 0;
		for (k => v in scores) {
			sum += v;
		}
	}

	override public function update(delta:Float) {
		super.update(delta);
		if (text != null) {
			countRemaining();
		}
	}

	public function countRemaining() {
		text.text = '${targetCount - sum}';
	}
}
