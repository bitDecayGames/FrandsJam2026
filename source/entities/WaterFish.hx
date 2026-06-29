package entities;

import managers.GameManager;
import schema.FishState;
import net.NetworkManager;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.math.FlxPoint;
import flixel.util.FlxColor;
import flixel.text.FlxText;
import todo.TODO;

class WaterFish extends FlxSprite {
	var waterTiles:Array<FlxPoint> = [];
	var target:FlxPoint;
	var retargetTimer:Float;
	var pauseTimer:Float = 0;

	public var isRemote = false;

	var net:NetworkManager = null;

	public var fishId = "";
	public var fishType:Int = 0;

	// In local mode, holds a direct reference to the GameLogic's FishState
	// so we can read position each frame without schema signals
	public var serverFishState:FishState = null;

	static inline var SPEED:Float = 20;
	static inline var ATTRACT_SPEED:Float = 40;
	static inline var ARRIVE_DIST:Float = 2;
	static inline var ATTRACT_DIST:Float = 32; // 2 tiles
	static inline var CATCH_DIST:Float = 4;

	var attracted:Bool = false;

	public var bobbers:Map<String, FlxSprite> = new Map();
	public var onCatch:(fishId:String, catcherSessionId:String, fishType:Int) -> Void;

	var respawnTimer:Float = 0;
	var fadeInTimer:Float = 0;
	var scaredTimer:Float = 0;

	#if db
	var stateLabel:FlxText;
	var scareCircle:FlxSprite;
	public var showScareRadius:Bool = false;
	static inline var ROCKET_SCARE_RADIUS:Int = 40;
	#end

	public function new(id:String, x:Float, y:Float, waterTiles:Array<FlxPoint> = null, isRemote = false, fishType:Int = 0) {
		super(x, y);
		fishId = id;
		this.fishType = fishType;
		if (waterTiles != null) {
			this.waterTiles = waterTiles;
		}
		this.isRemote = isRemote;
		if (isRemote) {
			GameManager.ME.net.onFishMove.add(handleChange);
			GameManager.ME.net.onFishDespawn.add(handleDespawn);
		}
		loadGraphic("assets/aseprite/characters/fishShadow.png");
		centerOffsets();

		#if db
		stateLabel = new FlxText(0, 0, 80, "", 8);
		stateLabel.color = FlxColor.WHITE;
		stateLabel.alignment = flixel.text.FlxTextAlign.CENTER;
		#end
		if (isRemote) {
			// server-driven fish start visible — server controls alive state
			alpha = 1;
			fadeInTimer = 0;
		} else {
			alpha = 0;
			fadeInTimer = 1.0;
		}
		pickTarget();
	}

	private function handleDespawn(id:String, respawnTime:Float):Void {
		if (fishId != id || !alive) {
			return;
		}
		alive = false;
		visible = false;
		velocity.set(0, 0);
		respawnTimer = respawnTime;
	}

	private function handleChange(id:String, state:FishState):Void {
		if (fishId != id) {
			return;
		}

		// Handle alive state from server
		if (!state.alive) {
			if (alive) {
				// Start fade-out instead of instant vanish
				alive = false;
				velocity.set(0, 0);
				if (scaredTimer <= 0) {
					scaredTimer = 0.5; // fade out over 0.5s
				}
			}
			return;
		}

		// Fish is alive on server
		if (!alive) {
			// Fish just respawned — revive and fade in
			alive = true;
			visible = true;
			alpha = 0;
			fadeInTimer = 1.0;
		}

		setPosition(state.x, state.y);
	}

	#if db
	function updateStateLabel() {
		if (stateLabel == null) { return; }
		var state = if (serverFishState != null) {
			switch (serverFishState.aiState) {
				case FishState.STATE_ATTRACTED: "attracted";
				case FishState.STATE_SCARED: "scared";
				case FishState.STATE_FEARED: "feared";
				case FishState.STATE_SPAWNING: "spawning";
				case FishState.STATE_DEAD: "dead";
				case FishState.STATE_BAIT_ROAMING: "bait_roaming";
				default: "roaming";
			};
		} else {
			"unknown";
		};
		stateLabel.text = state;
		stateLabel.setPosition(x - 20, y + height + 1);
		stateLabel.alpha = alpha;
		stateLabel.visible = visible;
	}

	override public function draw() {
		super.draw();
		if (stateLabel != null && visible) {
			stateLabel.draw();
		}
		if (showScareRadius && visible && alive) {
			if (scareCircle == null) {
				var diam = ROCKET_SCARE_RADIUS * 2;
				scareCircle = new FlxSprite();
				scareCircle.makeGraphic(diam, diam, 0x00000000);
				for (angle in 0...360) {
					var rad = angle * Math.PI / 180;
					for (r in [ROCKET_SCARE_RADIUS - 1, ROCKET_SCARE_RADIUS - 2]) {
						var px = Std.int(ROCKET_SCARE_RADIUS + Math.cos(rad) * r);
						var py = Std.int(ROCKET_SCARE_RADIUS + Math.sin(rad) * r);
						if (px >= 0 && px < diam && py >= 0 && py < diam) {
							scareCircle.pixels.setPixel32(px, py, 0x66FFAA00);
						}
					}
				}
				scareCircle.dirty = true;
			}
			scareCircle.setPosition(x - ROCKET_SCARE_RADIUS + width / 2, y - ROCKET_SCARE_RADIUS + height / 2);
			scareCircle.draw();
		}
	}

	#end

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
		if (attracted) {
			return;
		}
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
			if (target != null) {
				target.put();
			}
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
		if (fadeInTimer > 0 && scaredTimer <= 0) {
			fadeInTimer -= elapsed;
			alpha = Math.min(1.0, 1.0 - fadeInTimer);
		}

		if (isRemote) {
			// In local mode, read position directly from GameLogic's FishState
			if (serverFishState != null) {
				if (!serverFishState.alive && alive) {
					alive = false;
					// Start fade-out instead of instant vanish
					if (scaredTimer <= 0) {
						scaredTimer = 0.5;
					}
				} else if (serverFishState.alive && !alive && scaredTimer <= 0) {
					alive = true;
					visible = true;
					alpha = 0;
					fadeInTimer = 1.0;
				}
				if (alive) {
					setPosition(serverFishState.x, serverFishState.y);
				}
			}
			// Handle fade-out for remote fish
			if (scaredTimer > 0) {
				scaredTimer -= elapsed;
				alpha = Math.max(0, scaredTimer / 0.5);
				if (scaredTimer <= 0) {
					visible = false;
				}
			}
			#if db
			updateStateLabel();
			#end
			super.update(elapsed);
			return;
		}

		// Fade out when scared (runs even if alive=false from server)
		if (scaredTimer > 0) {
			scaredTimer -= elapsed;
			alpha = Math.max(0, scaredTimer / 0.5);
			super.update(elapsed);
			if (scaredTimer <= 0) {
				alive = false;
				visible = false;
				velocity.set(0, 0);
				respawnTimer = 5.5;
				GameManager.ME.net.sendMessage("fish_despawn", {id: fishId, respawnTime: 5.5});
			}
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

		if (!Lambda.empty(bobbers) || attracted) {
			checkBobber();
		}

		if (!alive) {
			return;
		}

		GameManager.ME.net.sendMessage("fish_move", {id: fishId, x: x, y: y}, true);

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
	}

	function checkBobber() {
		var closestDist = Math.POSITIVE_INFINITY;
		var closestBobber:FlxSprite = null;
		var closestSid:String = null;

		for (sid => bobb in bobbers) {
			if (bobb == null) {
				continue;
			}
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
			if (onCatch != null) {
				onCatch(fishId, closestSid, fishType);
			}
			return;
		}

		// attract toward closest bobber
		if (!attracted) {
			attracted = true;
		}
		pauseTimer = 0;
		var dx = (closestBobber.x + closestBobber.width / 2) - (x + width / 2);
		var dy = (closestBobber.y + closestBobber.height / 2) - (y + height / 2);
		if (closestDist > 0.1) {
			velocity.set((dx / closestDist) * ATTRACT_SPEED, (dy / closestDist) * ATTRACT_SPEED);
		}
	}

	public function scare(fromX:Float, fromY:Float) {
		TODO.sfx("fish_scared");
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
		if (isRemote) {
			GameManager.ME.net.onFishMove.remove(handleChange);
			GameManager.ME.net.onFishDespawn.remove(handleDespawn);
		}
		if (target != null) {
			target.put();
			target = null;
		}
		#if db
		if (stateLabel != null) { stateLabel.destroy(); stateLabel = null; }
		#end
		waterTiles = null;
		bobbers = null;
		onCatch = null;
		super.destroy();
	}
}
