package entities;

import flixel.FlxSprite;
import flixel.util.FlxColor;

class GroundFish extends FlxSprite {
	var flopTimer:Float = 0;

	public function new(x:Float, y:Float) {
		super(x, y);
		makeGraphic(4, 2, FlxColor.GREEN);
	}

	override public function update(elapsed:Float) {
		super.update(elapsed);
		flopTimer += elapsed * 8;
		angle = Math.sin(flopTimer) * 30;
	}
}
