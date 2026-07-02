package entities;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup;

/**
 * The dropped gravity bomb — pulses and spews swirly particles that
 * spiral into it to sell the suck. Purely cosmetic; the actual pull
 * lives in Simulation.gravityWell.
**/
class GravityBomb extends FlxSprite {
	static inline var EMIT_INTERVAL:Float = 0.05;

	var emitTimer:Float = 0;
	var pulseTime:Float = 0;
	var fxGroup:FlxGroup;

	/** cx/cy are the bomb's center; fxGroup receives the swirl particles. */
	public function new(cx:Float, cy:Float, fxGroup:FlxGroup) {
		super(cx, cy);
		this.fxGroup = fxGroup;
		makeGraphic(12, 12, 0xFF7722CC);
		offset.set(6, 6); // x,y is the bomb's center
	}

	override public function update(elapsed:Float) {
		super.update(elapsed);

		// Pulse so it reads as "actively sucking"
		pulseTime += elapsed;
		var s = 1.0 + 0.25 * Math.sin(pulseTime * 8);
		scale.set(s, s);

		emitTimer -= elapsed;
		while (emitTimer <= 0) {
			emitTimer += EMIT_INTERVAL;
			fxGroup.add(new GravitySwirl(x, y));
		}
	}
}

/** A single particle that spirals inward toward the bomb, then dies. */
class GravitySwirl extends FlxSprite {
	var cx:Float;
	var cy:Float;
	var ang:Float;
	var radius:Float;
	var rotSpeed:Float;
	var inSpeed:Float;

	public function new(cx:Float, cy:Float) {
		super();
		this.cx = cx;
		this.cy = cy;
		ang = FlxG.random.float(0, Math.PI * 2);
		radius = FlxG.random.float(24, 48);
		rotSpeed = FlxG.random.float(3.5, 6.0); // radians/sec
		inSpeed = FlxG.random.float(20, 34); // px/sec inward
		var size = FlxG.random.int(2, 3);
		makeGraphic(size, size, FlxG.random.bool() ? 0xFFB266FF : 0xFF7722CC);
		offset.set(size / 2, size / 2);
		allowCollisions = NONE;
		setPosition(cx + Math.cos(ang) * radius, cy + Math.sin(ang) * radius);
	}

	override public function update(elapsed:Float) {
		super.update(elapsed);
		ang += rotSpeed * elapsed;
		radius -= inSpeed * elapsed;
		if (radius <= 2) {
			kill();
			return;
		}
		// fade as it gets sucked in
		alpha = Math.min(1, radius / 16);
		setPosition(cx + Math.cos(ang) * radius, cy + Math.sin(ang) * radius);
	}
}
