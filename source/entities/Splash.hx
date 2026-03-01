package entities;

import flixel.FlxSprite;

class Splash extends FlxSprite {
	public function new(cx:Float, cy:Float) {
		super(cx, cy);
		loadGraphic(AssetPaths.splash__png, true, 16, 32);
		// Align bottom-center of splash on the impact point
		x -= frameWidth / 2;
		y -= frameHeight;
		animation.add("splash", [0, 1, 2, 3, 4, 5, 6], 10, false);
		animation.finishCallback = (_) -> kill();
		animation.play("splash");
	}
}
