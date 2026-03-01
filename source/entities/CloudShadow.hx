package entities;

import flixel.FlxG;
import flixel.FlxSprite;

class CloudShadow extends FlxSprite {
	static inline var SPEED_MIN:Float = 8;
	static inline var SPEED_MAX:Float = 16;
	static inline var SHADOW_ALPHA:Float = 0.12;

	// Margin beyond screen edge before respawning
	static inline var MARGIN:Float = 64;

	// Shared wind direction — call randomizeWind() once at the start of each round
	public static var windAngle:Float = 0;

	public static function randomizeWind() {
		windAngle = FlxG.random.float(0, 2 * Math.PI);
	}

	public function new() {
		super();
		loadGraphic(AssetPaths.cloudShadow__png);
		var s = FlxG.random.float(1, 3);
		scale.set(s, s);
		updateHitbox();
		alpha = SHADOW_ALPHA;
		scrollFactor.set(0, 0);
		setVelocityFromWind();
		// Scatter across the full traversal path so some start on-screen
		spawnScattered();
	}

	function setVelocityFromWind() {
		var speed = FlxG.random.float(SPEED_MIN, SPEED_MAX);
		velocity.x = Math.cos(windAngle) * speed;
		velocity.y = Math.sin(windAngle) * speed;
	}

	/** Place at a random point along the full wind axis (upwind edge to downwind edge). **/
	function spawnScattered() {
		// Random t from 0 (upwind edge) to 1 (downwind edge)
		placeAlongWindAxis(FlxG.random.float(0, 1));
	}

	/** Place at the upwind edge so it drifts across the full screen. **/
	function spawnAtEdge() {
		placeAlongWindAxis(0);
	}

	function placeAlongWindAxis(t:Float) {
		var screenW = FlxG.width;
		var screenH = FlxG.height;
		var dx = Math.cos(windAngle);
		var dy = Math.sin(windAngle);

		// Upwind origin: the edge the shadow enters from
		var startX:Float, startY:Float;
		if (dx > 0)
			startX = -width - MARGIN;
		else
			startX = screenW + MARGIN;
		if (dy > 0)
			startY = -height - MARGIN;
		else
			startY = screenH + MARGIN;

		// Downwind destination: the edge the shadow exits at
		var endX:Float, endY:Float;
		if (dx > 0)
			endX = screenW + MARGIN;
		else
			endX = -width - MARGIN;
		if (dy > 0)
			endY = screenH + MARGIN;
		else
			endY = -height - MARGIN;

		// Interpolate along wind axis, randomize perpendicular offset
		x = startX + (endX - startX) * t;
		y = startY + (endY - startY) * t;

		// Add random perpendicular spread so they aren't all in a line
		var perpX = -dy;
		var perpY = dx;
		var spread = FlxG.random.float(-0.5, 0.5) * Math.max(screenW, screenH);
		x += perpX * spread;
		y += perpY * spread;
	}

	override public function update(elapsed:Float) {
		super.update(elapsed);

		if (x < -width - MARGIN || x > FlxG.width + MARGIN || y < -height - MARGIN || y > FlxG.height + MARGIN) {
			setVelocityFromWind();
			spawnAtEdge();
		}
	}
}
