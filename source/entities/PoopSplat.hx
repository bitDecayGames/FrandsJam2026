package entities;

import flixel.FlxSprite;
import flixel.util.FlxColor;

class PoopSplat extends FlxSprite {
	public function new(wx:Float, wy:Float) {
		super(wx, wy);
		makeGraphic(3, 3, FlxColor.TRANSPARENT);
		// Small irregular splat shape
		pixels.setPixel32(1, 0, FlxColor.WHITE);
		pixels.setPixel32(0, 1, FlxColor.WHITE);
		pixels.setPixel32(1, 1, FlxColor.WHITE);
		pixels.setPixel32(2, 1, FlxColor.WHITE);
		pixels.setPixel32(1, 2, FlxColor.WHITE);
		dirty = true;
		x -= 1;
		y -= 1;
		alpha = 0.85;
		allowCollisions = NONE;
	}
}
