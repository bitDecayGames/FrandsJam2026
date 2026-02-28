package entities;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.math.FlxPoint;
import flixel.util.FlxColor;

class GroundFish extends FlxSprite {
	var flopTimer:Float = 0;

	// Actual pixel sizes of each fish frame within the 32x32 cell (top-left aligned)
	static var FISH_SIZES:Array<Array<Int>> = [
		[8, 8], // fish 0
		[9, 9], // fish 1
		[12, 12], // fish 2
		[13, 14], // fish 3
		[15, 16], // fish 4
	];

	// Arc flight
	var arcStart:FlxPoint;
	var arcEnd:FlxPoint;
	var arcFlightTime:Float = 0;
	var arcElapsed:Float = 0;

	public var landing:Bool = false;

	public function new(startX:Float, startY:Float, landX:Float, landY:Float, fishFrame:Int = 0) {
		super(startX, startY);
		loadGraphic("assets/aseprite/fish.png", true, 32, 32);
		animation.add("fish", [fishFrame]);
		animation.play("fish");

		var size = FISH_SIZES[fishFrame];
		origin.set(size[0] / 2, size[1] / 2);

		arcStart = FlxPoint.get(startX, startY);
		arcEnd = FlxPoint.get(landX, landY);
		var dx = landX - startX;
		var dy = landY - startY;
		var dist = Math.sqrt(dx * dx + dy * dy);
		arcFlightTime = if (dist > 0) dist / 120 else 0.01;
		arcElapsed = 0;
		landing = true;
	}

	override public function update(elapsed:Float) {
		if (landing) {
			arcElapsed += elapsed;
			var t = Math.min(1.0, arcElapsed / arcFlightTime);

			var gx = arcStart.x + (arcEnd.x - arcStart.x) * t;
			var gy = arcStart.y + (arcEnd.y - arcStart.y) * t;

			var dx = arcEnd.x - arcStart.x;
			var dy = arcEnd.y - arcStart.y;
			var dist = Math.sqrt(dx * dx + dy * dy);
			var arcHeight = Math.min(dist * 0.5, 32);
			var arcOffset = arcHeight * 4 * t * (1 - t);

			setPosition(gx, gy - arcOffset);
			angle = FlxG.random.float(-15, 15);

			if (t >= 1.0) {
				landing = false;
				setPosition(arcEnd.x, arcEnd.y);
				arcStart.put();
				arcStart = null;
				arcEnd.put();
				arcEnd = null;
			}
		} else {
			super.update(elapsed);
			flopTimer += elapsed * 8;
			angle = Math.sin(flopTimer) * 30;
		}
	}

	override function destroy() {
		if (arcStart != null) {
			arcStart.put();
			arcStart = null;
		}
		if (arcEnd != null) {
			arcEnd.put();
			arcEnd = null;
		}
		super.destroy();
	}
}
