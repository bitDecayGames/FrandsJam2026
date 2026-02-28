package entities;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxRect;
import input.SimpleController;

class FishGroup extends FlxTypedGroup<Fish> {
	static inline var NUM_FISH = 10;

	public function new() {
		super();
	}

	public function spawn(bounds:FlxRect) {
		for (_ in 0...NUM_FISH) {
			var fx = FlxG.random.float(bounds.x, bounds.right - 16);
			var fy = FlxG.random.float(bounds.y, bounds.bottom - 16);
			add(new Fish(fx, fy));
		}
	}

	public function clearAll() {
		for (f in this) {
			f.destroy();
		}
		clear();
	}

	public function handleOverlap(player:FlxSprite) {
		FlxG.overlap(player, this, (p:FlxSprite, f:FlxSprite) -> {
			var fish:Fish = cast f;
			if (SimpleController.just_pressed(Button.A)) {
				fish.hit(cast(player, Player).sessionId);
			}
		});
	}
}
