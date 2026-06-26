package entities;

import flixel.FlxG;
import flixel.FlxSprite;

class CloudShadow extends FlxSprite {
	static inline var SHADOW_ALPHA:Float = 0.12;
	static inline var MARGIN:Float = 64;

	public static var windAngle:Float = 0;

	public var cloudId:Int = 0;

	public static function randomizeWind() {
		windAngle = FlxG.random.float(0, 2 * Math.PI);
	}

	public function new() {
		super();
		loadGraphic(AssetPaths.cloudShadow__png);
		alpha = SHADOW_ALPHA;
		// world-space — no scrollFactor override, clouds are world objects
	}

	/** Create a cloud from server data. */
	public static function fromServer(data:Dynamic):CloudShadow {
		var c = new CloudShadow();
		c.cloudId = Std.int(data.id);
		c.scale.set(data.scale, data.scale);
		c.updateHitbox();
		c.setPosition(data.x, data.y);
		c.velocity.set(data.velX, data.velY);
		return c;
	}

	override public function update(elapsed:Float) {
		super.update(elapsed);

		// respawn at upwind edge when past world bounds
		var bounds = FlxG.worldBounds;
		if (x < bounds.x - width - MARGIN || x > bounds.right + MARGIN || y < bounds.y - height - MARGIN || y > bounds.bottom + MARGIN) {
			respawnAtEdge();
		}
	}

	function respawnAtEdge() {
		var bounds = FlxG.worldBounds;
		var dx = Math.cos(windAngle);
		var dy = Math.sin(windAngle);

		// place at upwind edge
		if (dx > 0) {
			x = bounds.x - width - MARGIN;
		} else {
			x = bounds.right + MARGIN;
		}
		if (dy > 0) {
			y = bounds.y - height - MARGIN;
		} else {
			y = bounds.bottom + MARGIN;
		}

		// random perpendicular spread
		var perpX = -dy;
		var perpY = dx;
		var spread = (Math.random() - 0.5) * Math.max(bounds.width, bounds.height);
		x += perpX * spread;
		y += perpY * spread;
	}
}
