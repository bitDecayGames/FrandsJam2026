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
	static inline var ARRIVE_DIST:Float = 2;

	public function new(x:Float, y:Float, waterTiles:Array<FlxPoint> = null, isRemote = false) {
		super(x, y);
		if (waterTiles != null) {
			this.waterTiles = waterTiles;
		}
		this.isRemote = isRemote;
		makeGraphic(4, 2, FlxColor.BLACK);
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
		super.update(elapsed);

		if (isRemote) {
			// TODO: drive animations but network controls main stuff
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

	override function destroy() {
		if (target != null) {
			target.put();
			target = null;
		}
		// Don't put waterTiles points — they're shared across fish in the same body
		waterTiles = null;
		super.destroy();
	}
}
