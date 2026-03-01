package entities;

import managers.GameManager;
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

	public var bobbers:Map<String, FlxSprite> = new Map();
	public var onCatch:(fishId:String, catcherSessionId:String) -> Void;

	var respawnTimer:Float = 0;
	var fadeInTimer:Float = 0;
	var scaredTimer:Float = 0;

	public function new(id:String, x:Float, y:Float, waterTiles:Array<FlxPoint> = null, isRemote = false) {
		super(x, y);
		fishId = id;
		if (waterTiles != null) {
			this.waterTiles = waterTiles;
		}
		this.isRemote = isRemote;
		if (isRemote) {
			GameManager.ME.net.onFishMove.add(handleChange);
		}
		loadGraphic("assets/aseprite/characters/fishShadow.png");
		centerOffsets();
		alpha = 0;
		fadeInTimer = 1.0;
		pickTarget();
	}

	private function handleChange(id:String, state:FishState):Void {
		if (fishId != id) {
			return;
		}

		setPosition(state.x, state.y);
		if (!visible) {
			alpha = 0;
			fadeInTimer = 1.0;
			visible = true;
		}
	}

	function pickTarget() {
		if (isRemote) {
			return;
		}

		if (target != null) {
			target.put();
		}

		var tile = waterTiles[FlxG.random.int(0, waterTiles.length - 1)];
		target = FlxPoint.get(tile.x + FlxG.random.float(0, 12), tile.y + FlxG.random.float(0, 12));
		retargetTimer = FlxG.random.float(2, 3);
	}

	public function fleeFrom(otherX:Float, otherY:Float) {
		if (attracted)
			return;
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

			var fdx = target.x - x;
			var fdy = target.y - y;
			var fdist = Math.sqrt(fdx * fdx + fdy * fdy);
			if (fdist > 0.1) {
				velocity.set((fdx / fdist) * SPEED, (fdy / fdist) * SPEED);
			}
		}

		pauseTimer = 0;
	}

	override public function update(elapsed:Float) {
		if (fadeInTimer > 0) {
			fadeInTimer -= elapsed;
			alpha = Math.min(1.0, 1.0 - fadeInTimer);
		}

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

		super.update(elapsed);

		if (scaredTimer > 0) {
			scaredTimer -= elapsed;
			alpha = Math.max(0, scaredTimer / 0.5);
			if (scaredTimer <= 0) {
				alive = false;
				visible = false;
				velocity.set(0, 0);
				respawnTimer = 5.5;
			}
			return;
		}

		if (!Lambda.empty(bobbers) || attracted) {
			checkBobber();
		}

		if (!alive)
			return;

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

		GameManager.ME.net.sendMessage("fish_move", {id: fishId, x: x, y: y}, true);
	}

	function checkBobber() {
		var closestDist = Math.POSITIVE_INFINITY;
		var closestBobber:FlxSprite = null;
		var closestSid:String = null;

		for (sid => bobb in bobbers) {
			if (bobb == null)
				continue;
			var dx = (bobb.x + bobb.width / 2) - (x + width / 2);
			var dy = (bobb.y + bobb.height / 2) - (y + height / 2);
			var dist = Math.sqrt(dx * dx + dy * dy);
			if (dist < closestDist) {
				closestDist = dist;
				closestBobber = bobb;
				closestSid = sid;
			}
		}

		if (closestBobber == null || closestDist > ATTRACT_DIST) {
			if (attracted) {
				attracted = false;
				fleeFrom(x + velocity.x, y + velocity.y);
			}
			return;
		}

		if (closestDist < CATCH_DIST) {
			alive = false;
			visible = false;
			velocity.set(0, 0);
			attracted = false;
			respawnTimer = 3.0;
			if (onCatch != null)
				onCatch(fishId, closestSid);
			return;
		}

		// attract toward closest bobber
		attracted = true;
		pauseTimer = 0;
		var dx = (closestBobber.x + closestBobber.width / 2) - (x + width / 2);
		var dy = (closestBobber.y + closestBobber.height / 2) - (y + height / 2);
		if (closestDist > 0.1)
			velocity.set((dx / closestDist) * ATTRACT_SPEED, (dy / closestDist) * ATTRACT_SPEED);
	}

	public function scare(fromX:Float, fromY:Float) {
		attracted = false;
		fleeFrom(fromX, fromY);
		velocity.scale(1.5);
		scaredTimer = 0.5;
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
		bobbers = null;
		onCatch = null;
		super.destroy();
	}
}
