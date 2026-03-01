package entities;

import flixel.FlxSprite;
import flixel.util.FlxColor;

class DebugCircle extends FlxSprite {
	static inline var DURATION:Float = 0.5;

	var elapsed:Float = 0;

	public function new(cx:Float, cy:Float, radiusX:Float, radiusY:Float) {
		super();
		var w = Std.int(radiusX * 2) + 2;
		var h = Std.int(radiusY * 2) + 2;
		makeGraphic(w, h, FlxColor.TRANSPARENT);
		drawEllipseOutline(Std.int(radiusX) + 1, Std.int(radiusY) + 1, radiusX, radiusY, FlxColor.CYAN);
		x = cx - radiusX - 1;
		y = cy - radiusY - 1;
		alpha = 0.8;
		allowCollisions = NONE;
	}

	function drawEllipseOutline(cx:Int, cy:Int, rx:Float, ry:Float, color:FlxColor) {
		var steps = 64;
		for (i in 0...steps) {
			var angle = (i / steps) * 2 * Math.PI;
			var px = Std.int(cx + Math.cos(angle) * rx);
			var py = Std.int(cy + Math.sin(angle) * ry);
			if (px >= 0 && px < frameWidth && py >= 0 && py < frameHeight) {
				pixels.setPixel32(px, py, color);
			}
		}
		dirty = true;
	}

	override public function update(dt:Float) {
		super.update(dt);
		elapsed += dt;
		if (elapsed >= DURATION) {
			kill();
			return;
		}
		alpha = 0.8 * (1 - elapsed / DURATION);
	}
}
