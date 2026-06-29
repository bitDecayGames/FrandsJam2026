package entities;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.util.FlxColor;
import todo.TODO;

/**
 * A dog that chases the closest player. Server-driven (Tier 2).
 * Client creates this from dog_spawn messages and updates position
 * from dog_update messages.
**/
class Dog extends FlxSprite {
	public var dogId:Int = 0;

	// Interpolation target from server
	var targetX:Float = 0;
	var targetY:Float = 0;
	var serverVelX:Float = 0;
	var serverVelY:Float = 0;

	static inline var INTERP_SPEED:Float = 200;

	public function new(id:Int, startX:Float, startY:Float) {
		super(startX, startY);
		dogId = id;
		targetX = startX;
		targetY = startY;

		// Placeholder graphic — 12x12 brown square
		makeGraphic(12, 12, FlxColor.fromRGB(139, 90, 43));
		centerOffsets();

		TODO.sfx("dog_bark");
	}

	public function serverUpdate(sx:Float, sy:Float, vx:Float, vy:Float) {
		targetX = sx;
		targetY = sy;
		serverVelX = vx;
		serverVelY = vy;
	}

	override public function update(elapsed:Float) {
		// Interpolate toward server position
		var dx = targetX - x;
		var dy = targetY - y;
		var dist = Math.sqrt(dx * dx + dy * dy);

		if (dist > 100) {
			// Way off — snap
			setPosition(targetX, targetY);
			velocity.set(serverVelX, serverVelY);
		} else if (dist > 1) {
			var speed = Math.min(dist * 8, INTERP_SPEED);
			velocity.x = (dx / dist) * speed;
			velocity.y = (dy / dist) * speed;
		} else {
			velocity.set(serverVelX, serverVelY);
		}

		super.update(elapsed);
	}
}
