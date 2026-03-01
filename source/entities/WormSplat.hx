package entities;

import flixel.FlxSprite;
import flixel.util.FlxColor;

class WormSplat extends FlxSprite {
	public function new(wx:Float, wy:Float) {
		super(wx, wy);
		makeGraphic(4, 3, FlxColor.TRANSPARENT);
		var brown:FlxColor = 0xFF6B4226;
		pixels.setPixel32(0, 0, brown);
		pixels.setPixel32(1, 0, brown);
		pixels.setPixel32(1, 1, brown);
		pixels.setPixel32(2, 1, brown);
		pixels.setPixel32(3, 1, brown);
		pixels.setPixel32(2, 2, brown);
		dirty = true;
		x -= 2;
		y -= 1;
		alpha = 0.8;
		allowCollisions = NONE;
	}
}
