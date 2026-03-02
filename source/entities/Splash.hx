package entities;

import flixel.FlxSprite;
import todo.TODO;

class Splash extends FlxSprite {
	public function new(cx:Float, cy:Float, big:Bool = false) {
		super(cx, cy);
		loadGraphic(AssetPaths.splash__png, true, 16, 32);
		// Align bottom-center of splash on the impact point
		x -= frameWidth / 2;
		y -= frameHeight;
		if (big) {
			TODO.sfx("splash_big");
			animation.add("splash", [7, 8, 9, 10, 11, 12, 13, 14, 15, 16], 10, false);
		} else {
			TODO.sfx("splash_small");
			animation.add("splash", [0, 1, 2, 3, 4, 5, 6], 10, false);
		}
		animation.finishCallback = (_) -> kill();
		animation.play("splash");
	}
}
