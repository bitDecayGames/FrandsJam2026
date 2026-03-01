package entities;

import flixel.FlxSprite;
import flixel.util.FlxColor;
import bitdecay.flixel.spacial.Cardinal;

class Footprint extends FlxSprite {
	static inline var DURATION:Float = 2.5;
	static inline var WATER_DURATION:Float = 1.25;

	var elapsed:Float = 0;
	var duration:Float;

	public function new(cx:Float, cy:Float, dir:Cardinal, ?color:FlxColor, inWater:Bool = false) {
		super(cx, cy);

		// Small oval footprint mark
		var isVertical = (dir == N || dir == S);
		var w = isVertical ? 2 : 3;
		var h = isVertical ? 3 : 2;
		if (color == null) {
			color = FlxColor.fromRGB(110, 100, 80);
		}
		var printColor = FlxColor.interpolate(color, FlxColor.BLACK, 0.55);
		makeGraphic(w, h, printColor);
		x -= w / 2;
		y -= h / 2;
		alpha = 0.6;
		duration = inWater ? WATER_DURATION : DURATION;
		allowCollisions = NONE;
	}

	override public function update(dt:Float) {
		super.update(dt);
		elapsed += dt;
		var t = elapsed / duration;
		if (t >= 1) {
			kill();
			return;
		}
		alpha = 0.6 * (1 - t);
	}
}
