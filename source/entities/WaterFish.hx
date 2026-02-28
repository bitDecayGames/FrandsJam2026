package entities;

import schema.FishState;
import net.NetworkManager;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.math.FlxPoint;
import flixel.util.FlxColor;

class WaterFish extends FlxSprite {
	var waterTiles:Array<FlxPoint> = [];
	var target:FlxPoint;
	var retargetTimer:Float;
	var pauseTimer:Float = 0;

	public var isRemote = false;

	var net:NetworkManager = null;

	public var fishId = "";

	static inline var SPEED:Float = 20;
	static inline var ATTRACT_SPEED:Float = 40;
	static inline var ARRIVE_DIST:Float = 2;
	static inline var ATTRACT_DIST:Float = 32; // 2 tiles
	static inline var CATCH_DIST:Float = 4;

	var attracted:Bool = false;

	public var bobber:FlxSprite;
	public var onCatch:() -> Void;

	var respawnTimer:Float = 0;
	var fadeInTimer:Float = 0;

	public function new(x:Float, y:Float, waterTiles:Array<FlxPoint> = null, isRemote = false) {
		super(x, y);
		if (waterTiles != null) {
			this.waterTiles = waterTiles;
		}
		this.isRemote = isRemote;
		loadGraphic("assets/aseprite/characters/fishShadow.png");
		centerOffsets();
		alpha = 0;
		fadeInTimer = 1.0;
		pickTarget();
	}

	public function setNetwork(net:NetworkManager, id:String) {
		this.net = net;
		net.onFishMove.add(handleChange);
		fishId = id;
	}

	private function handleChange(id:String, state:FishState):Void {
		if (fishId != id) {
			return;
		}

		setPosition(state.x, state.y);
	}

	function pickTarget() {
		if (target != null) {
			target.put();
		}

		var tile = waterTiles[FlxG.random.int(0, waterTiles.length - 1)];
		target = FlxPoint.get(tile.x + FlxG.random.float(0, 12), tile.y + FlxG.random.float(0, 12));
		retargetTimer = FlxG.random.float(2, 3);
	}

	public function fleeFrom(otherX:Float, otherY:Float) {
		var awayX = x - otherX;
		var awayY = y - otherY;
		var len = Math.sqrt(awayX * awayX + awayY * awayY);
		if (len < 0.01) {
			awayX = FlxG.random.float(-1, 1);
			awayY = FlxG.random.float(-1, 1);
			len = Math.sqrt(awayX * awayX + awayY * awayY);
		}
		awayX /= len;
		awayY /= len;

		// Pick the farthest water tile in the away direction
		var bestDot:Float = -999999;
		var bestTile:FlxPoint = null;
		for (tile in waterTiles) {
			var dx = tile.x - x;
			var dy = tile.y - y;
			var dot = dx * awayX + dy * awayY;
			if (dot > bestDot) {
				bestDot = dot;
				bestTile = tile;
			}
		}

		if (bestTile != null) {
			if (target != null)
				target.put();
			target = FlxPoint.get(bestTile.x + FlxG.random.float(0, 12), bestTile.y + FlxG.random.float(0, 12));
			retargetTimer = FlxG.random.float(2, 3);
		}

		velocity.set(0, 0);
		pauseTimer = FlxG.random.float(0.5, 1.0);
	}

	override public function update(elapsed:Float) {
		if (isRemote) {
			// TODO: drive animations but network controls main stuff
			super.update(elapsed);
			return;
		}

		if (!alive) {
			respawnTimer -= elapsed;
			if (respawnTimer <= 0) {
				respawn();
			}
			return;
		}

		if (fadeInTimer > 0) {
			fadeInTimer -= elapsed;
			alpha = Math.min(1.0, 1.0 - fadeInTimer);
		}

		super.update(elapsed);

		if (bobber != null) {
			checkBobber();
		}

		if (attracted) {
			return;
		}

		if (pauseTimer > 0) {
			pauseTimer -= elapsed;
			return;
		}

		retargetTimer -= elapsed;
		if (retargetTimer <= 0) {
			pickTarget();
		}

		var dx = target.x - x;
		var dy = target.y - y;
		var dist = Math.sqrt(dx * dx + dy * dy);

		if (dist < ARRIVE_DIST) {
			velocity.set(0, 0);
			pauseTimer = FlxG.random.float(1, 3);
			pickTarget();
		} else {
			velocity.set((dx / dist) * SPEED, (dy / dist) * SPEED);
		}

		if (net != null) {
			net.update();
			net.sendMove(x, y);
		}
	}

	function checkBobber() {
		if (bobber == null) {
			if (attracted) {
				attracted = false;
				fleeFrom(x + velocity.x, y + velocity.y);
			}
			return;
		}

		var bx = bobber.x + bobber.width / 2;
		var by = bobber.y + bobber.height / 2;
		var fx = x + width / 2;
		var fy = y + height / 2;
		var dx = bx - fx;
		var dy = by - fy;
		var dist = Math.sqrt(dx * dx + dy * dy);

		if (dist < CATCH_DIST) {
			alive = false;
			visible = false;
			velocity.set(0, 0);
			attracted = false;
			respawnTimer = 3.0;
			if (onCatch != null) {
				onCatch();
			}
			return;
		} else if (dist < ATTRACT_DIST) {
			attracted = true;
			pauseTimer = 0;
			if (dist > 0.1) {
				velocity.set((dx / dist) * ATTRACT_SPEED, (dy / dist) * ATTRACT_SPEED);
			}
		} else if (attracted) {
			stopAttract();
		}
	}

	function stopAttract() {
		attracted = false;
		pickTarget();
	}

	function respawn() {
		var tile = waterTiles[FlxG.random.int(0, waterTiles.length - 1)];
		setPosition(tile.x + FlxG.random.float(0, 12), tile.y + FlxG.random.float(0, 12));
		velocity.set(0, 0);
		alpha = 0;
		fadeInTimer = 1.0;
		visible = true;
		revive();
		pickTarget();
	}

	override function destroy() {
		if (target != null) {
			target.put();
			target = null;
		}
		// Don't put waterTiles points — they're shared across fish in the same body
		waterTiles = null;
		bobber = null;
		onCatch = null;
		super.destroy();
	}
}
