package entities;

import managers.GameManager;
import schema.PlayerState;
import net.NetworkManager;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.math.FlxPoint;
import flixel.util.FlxColor;
import flixel.util.FlxSignal;
import flixel.util.FlxSpriteUtil;
import input.InputCalculator;
import input.SimpleController;
import bitdecay.flixel.spacial.Cardinal;
import bitdecay.flixel.graphics.AsepriteMacros;
import flixel.FlxG;
import haxe.io.Path;
import entities.Inventory;
import entities.Inventory.InventoryItem;

class Player extends FlxSprite {
	public static var anims = AsepriteMacros.tagNames("assets/aseprite/characters/playerA.json");

	// 0-indexed frame within the cast animation when the bobber launches
	static inline var CAST_LAUNCH_FRAME:Int = 3;
	// 0-indexed frame within the catch animation when the bobber retracts (1 before final)
	static inline var CATCH_RETRACT_FRAME:Int = 1;

	static var SKINS:Array<String> = [
		"assets/aseprite/characters/playerA.json",
		"assets/aseprite/characters/playerB.json",
		"assets/aseprite/characters/playerC.json",
		"assets/aseprite/characters/playerF.json",
		"assets/aseprite/characters/playerG.json",
		"assets/aseprite/characters/playerH.json",
	];

	var skinIndex:Int = 0;
	var speed:Float = 100;
	var playerNum = 0;

	public var hotModeActive:Bool = false;

	var hotModeTimer:Float = 0;

	public var inventory = new Inventory();

	public var lastInputDir:Cardinal = E;

	var frozen:Bool = false;

	public var sessionId:String = "";

	// tracks if this player is controled by the remote client
	public var isRemote:Bool = false;

	// Cast state
	var castState:CastState = IDLE;

	public var castBobber(default, null):FlxSprite;

	var castTarget:FlxPoint;
	var castStartPos:FlxPoint;
	var castFlightTime:Float = 0;
	var castElapsed:Float = 0;
	var castPower:Float = 0;
	var castPowerDir:Float = 1;
	var castDirSuffix:String = "down";
	var retractHasFish:Bool = false;
	public var caughtFishFrame:Int = 0;
	public var onFishDelivered:Null<() -> Void> = null;

	// Cast sprites
	var reticle:FlxSprite;
	var fishingLine:FlxSprite;
	var powerBarBg:FlxSprite;
	var powerBarFill:FlxSprite;

	// Factory for creating thrown rocks — set by PlayState
	public var makeRock:(Float, Float) -> Rock;

	// Throw state
	var throwing:Bool = false;
	var rockSprite:Rock;
	var rockTarget:FlxPoint;
	var rockStartPos:FlxPoint;
	var rockFlightTime:Float = 0;
	var rockElapsed:Float = 0;

	// Animation state tracking
	var lastMoving:Bool = false;
	var lastAnimDir:Cardinal = E;

	public var onAnimUpdate = new FlxTypedSignal<(String, Bool) -> Void>();

	var state:FlxState;

	public function new(X:Float, Y:Float, state:FlxState) {
		super(X, Y);
		this.state = state;
		loadSkin(SKINS[skinIndex]);

		animation.onFrameChange.add(onAnimFrameChange);
		animation.onFinish.add(onAnimFinish);

		onAnimUpdate.add((animName, forceRestart) -> {
			animation.play(animName, forceRestart);
		});

		sendAnimUpdate("stand_down");

		reticle = new FlxSprite();
		reticle.loadGraphic(AssetPaths.aimingTarget__png, true, 8, 8);
		reticle.animation.add("idle", [0, 1, 2, 3], 8, true);
		reticle.animation.play("idle");
		state.add(reticle);

		fishingLine = new FlxSprite();
		fishingLine.makeGraphic(200, 200, FlxColor.TRANSPARENT, true);
		fishingLine.visible = false;
		state.add(fishingLine);

		powerBarBg = new FlxSprite();
		powerBarBg.makeGraphic(32, 4, FlxColor.fromRGB(40, 40, 40));
		powerBarBg.visible = false;
		state.add(powerBarBg);

		powerBarFill = new FlxSprite();
		powerBarFill.makeGraphic(32, 4, FlxColor.LIME);
		powerBarFill.visible = false;
		powerBarFill.origin.set(0, 0);
		state.add(powerBarFill);
	}

	function onAnimFrameChange(animName:String, frameNumber:Int, frameIndex:Int) {
		if (castState == CAST_ANIM && castBobber == null && frameNumber == CAST_LAUNCH_FRAME) {
			launchBobber();
		}
		if (throwing && rockSprite == null && frameNumber == 6) {
			launchRock();
		}
		if (castState == CATCH_ANIM && frameNumber == CATCH_RETRACT_FRAME && castBobber != null) {
			if (retractHasFish) {
				// Set up arc retract
				castStartPos = FlxPoint.get(castBobber.x, castBobber.y);
				var retract = getRetractTarget();
				castTarget = FlxPoint.get(retract.x, retract.y);
				retract.put();
				var dx = castTarget.x - castStartPos.x;
				var dy = castTarget.y - castStartPos.y;
				var dist = Math.sqrt(dx * dx + dy * dy);
				castFlightTime = if (dist > 0) dist / 188 else 0.01;
				castElapsed = 0;
				castBobber.velocity.set(0, 0);
			} else {
				var retract = getRetractTarget();
				var px = retract.x;
				var py = retract.y;
				retract.put();
				var dx = px - castBobber.x;
				var dy = py - castBobber.y;
				var dist = Math.sqrt(dx * dx + dy * dy);
				if (dist > 0) {
					castBobber.velocity.x = (dx / dist) * 188;
					castBobber.velocity.y = (dy / dist) * 188;
				}
			}
		}
	}

	function onAnimFinish(animName:String) {
		if (castState == CAST_ANIM) {
			castState = CASTING;
		} else if (castState == CATCH_ANIM) {
			if (castBobber != null) {
				castState = RETURNING;
			} else {
				castState = IDLE;
				frozen = false;
				playMovementAnim(true);
			}
		} else if (throwing) {
			throwing = false;
			frozen = false;
			playMovementAnim(true);
		}
	}

	function playMovementAnim(force:Bool = false) {
		var moving = velocity.x != 0 || velocity.y != 0;
		if (!force && moving == lastMoving && lastInputDir == lastAnimDir)
			return;

		lastMoving = moving;
		lastAnimDir = lastInputDir;

		var dirSuffix = getDirSuffix();
		sendAnimUpdate((moving ? "run_" : "stand_") + dirSuffix);
	}

	function sendAnimUpdate(animName:String, forceRestart:Bool = false) {
		onAnimUpdate.dispatch(animName, forceRestart);
	}

	public function setNetwork(session:String) {
		cleanupNetwork();

		sessionId = session;
		GameManager.ME.net.onPlayerChanged.add(handleChange);
	}

	private function handleChange(sesId:String, state:PlayerState):Void {
		if (sesId != sessionId) {
			return;
		}

		setPosition(state.x, state.y);
	}

	override public function update(delta:Float) {
		super.update(delta);

		if (isRemote) {
			// events drive this one
			return;
		}

		if (FlxG.keys.justPressed.Q) {
			skinIndex = (skinIndex - 1 + SKINS.length) % SKINS.length;
			swapSkin();
		} else if (FlxG.keys.justPressed.E) {
			skinIndex = (skinIndex + 1) % SKINS.length;
			swapSkin();
		}

		if (frozen) {
			velocity.set();
		} else {
			var inputDir = InputCalculator.getInputCardinal(playerNum);
			if (inputDir == N || inputDir == S || inputDir == E || inputDir == W) {
				lastInputDir = inputDir;
			}

			if (FlxG.keys.justPressed.T && !hotModeActive) {
				hotModeActive = true;
				hotModeTimer = 3.0;
			}

			if (hotModeActive) {
				hotModeTimer -= delta;
				if (hotModeTimer <= 0) {
					hotModeActive = false;
					if (inputDir == NONE) {
						velocity.set();
					}
				} else {
					var moveDir = if (inputDir != NONE) inputDir else lastInputDir;
					if (moveDir != NONE) {
						moveDir.asVector(velocity).normalize().scale(speed * 1.5);
					}
				}
			} else {
				if (inputDir != NONE) {
					inputDir.asVector(velocity).normalize().scale(speed);
				} else {
					velocity.set();
				}
			}
		}

		// Only update movement animations when not in a scripted animation
		if (castState != CAST_ANIM && castState != CATCH_ANIM && castState != RETURNING && !throwing) {
			playMovementAnim();
		}

		// Throw rock with B button (requires a rock in inventory)
		if (!throwing && castState == IDLE && SimpleController.just_pressed(B) && inventory.has(Rock)) {
			inventory.remove(Rock);
			throwing = true;
			frozen = true;
			sendAnimUpdate("throw_" + getDirSuffix(), true);
			// Capture reticle target for the rock
			var dir = lastInputDir.asVector();
			var rawX = x + dir.x * 96 + 4;
			var rawY = y + dir.y * 96 + 4;
			var bounds = FlxG.worldBounds;
			rockTarget = FlxPoint.get(Math.max(bounds.left, Math.min(bounds.right, rawX)), Math.max(bounds.top, Math.min(bounds.bottom, rawY)));
			dir.put();
		}

		updateReticle();
		updateCast(delta);
		updateFishingLine();
		updateRock(delta);

		GameManager.ME.net.sendMove(x, y);
	}

	function updateReticle() {
		if (reticle == null)
			return;
		var reticleOffset = lastInputDir.asVector();
		var bounds = FlxG.worldBounds;
		reticle.setPosition(Math.max(bounds.left, Math.min(bounds.right, last.x + reticleOffset.x * 96 + 4)),
			Math.max(bounds.top, Math.min(bounds.bottom, last.y + reticleOffset.y * 96 + 4)));
		reticleOffset.put();
	}

	function getRodTipPos():FlxPoint {
		if (castState == CAST_ANIM || castState == CASTING) {
			var frame = animation.curAnim != null ? animation.curAnim.curFrame : 0;
			if (castState == CAST_ANIM && frame == CAST_LAUNCH_FRAME) {
				return switch (castDirSuffix) {
					case "right": FlxPoint.get(x + 12, y);
					case "left": FlxPoint.get(x + 4, y);
					case "down": FlxPoint.get(x, y + 4);
					case "up": FlxPoint.get(x + 12, y + 4);
					default: null;
				};
			}
			return switch (castDirSuffix) {
				case "down": FlxPoint.get(x + 10, y + 24);
				case "right": FlxPoint.get(x + 30, y + 2);
				case "up": FlxPoint.get(x + 3, y - 4);
				case "left": FlxPoint.get(x - 15, y + 2);
				default: FlxPoint.get(x + 8, y + 8);
			};
		} else if (castState == CATCH_ANIM || castState == RETURNING) {
			var frame = animation.curAnim != null ? animation.curAnim.curFrame : 0;
			return switch (castDirSuffix) {
				case "down":
					if (frame == 0) FlxPoint.get(x + 10, y + 24) else if (frame == 1) FlxPoint.get(x + 1, y + 3) else FlxPoint.get(x + 0, y - 5);
				case "right":
					if (frame == 0) FlxPoint.get(x + 30, y + 2) else if (frame == 1) FlxPoint.get(x + 14, y - 4) else FlxPoint.get(x - 6, y - 6);
				case "up":
					if (frame == 0) FlxPoint.get(x + 3, y - 6) else if (frame == 1) FlxPoint.get(x + 13, y - 8) else FlxPoint.get(x + 19, y - 8);
				case "left":
					if (frame == 0) FlxPoint.get(x - 15, y + 2) else if (frame == 1) FlxPoint.get(x + 1, y - 4) else FlxPoint.get(x + 21, y - 6);
				default: FlxPoint.get(x + 8, y + 8);
			};
		} else {
			return switch (castDirSuffix) {
				case "down": FlxPoint.get(x + 2, y + 10);
				case "right": FlxPoint.get(x + 15, y - 5);
				case "up": FlxPoint.get(x + 11, y - 6);
				case "left": FlxPoint.get(x + 0, y - 5);
				default: FlxPoint.get(x + 8, y + 8);
			};
		}
	}

	function updateFishingLine() {
		if (castBobber == null) {
			fishingLine.visible = false;
			return;
		}

		var tip = getRodTipPos();
		var bobCX = castBobber.x + 4;
		var bobCY = castBobber.y + 4;

		var minX = Math.floor(Math.min(tip.x, bobCX)) - 1;
		var minY = Math.floor(Math.min(tip.y, bobCY)) - 1;
		var w = Math.ceil(Math.abs(tip.x - bobCX)) + 3;
		var h = Math.ceil(Math.abs(tip.y - bobCY)) + 3;
		if (w < 2)
			w = 2;
		if (h < 2)
			h = 2;

		// Add sag room for left/right curves
		var sag = (castDirSuffix == "left" || castDirSuffix == "right") ? 10 : 0;
		var minY2 = minY - 1;
		var h2 = h + sag;

		fishingLine.setPosition(minX, minY2);
		fishingLine.makeGraphic(w, h2, FlxColor.TRANSPARENT, true);

		var lx0 = tip.x - minX;
		var ly0 = tip.y - minY2;
		var lx1 = bobCX - minX;
		var ly1 = bobCY - minY2;

		if (sag > 0) {
			// Cubic Bezier with downward sag — arrives at bobber horizontally
			var c1x = (lx0 + lx1) / 2;
			var c1y = (ly0 + ly1) / 2 + sag;
			var c2x = lx1 - (lx1 - lx0) * 0.15;
			var c2y = ly1;
			var steps = Std.int(Math.max(Math.abs(lx1 - lx0), Math.abs(ly1 - ly0))) * 2 + 10;
			var prevPx = Math.round(lx0);
			var prevPy = Math.round(ly0);
			if (prevPx >= 0 && prevPx < w && prevPy >= 0 && prevPy < h2)
				fishingLine.pixels.setPixel32(prevPx, prevPy, FlxColor.WHITE);
			for (i in 1...steps + 1) {
				var t = i / steps;
				var invT = 1 - t;
				var px = Math.round(invT * invT * invT * lx0 + 3 * invT * invT * t * c1x + 3 * invT * t * t * c2x + t * t * t * lx1);
				var py = Math.round(invT * invT * invT * ly0 + 3 * invT * invT * t * c1y + 3 * invT * t * t * c2y + t * t * t * ly1);
				if (px != prevPx || py != prevPy) {
					if (px >= 0 && px < w && py >= 0 && py < h2)
						fishingLine.pixels.setPixel32(px, py, FlxColor.WHITE);
					prevPx = px;
					prevPy = py;
				}
			}
		} else {
			// Bresenham line for crisp pixels (up/down)
			var x0 = Math.round(lx0);
			var y0 = Math.round(ly0);
			var x1 = Math.round(lx1);
			var y1 = Math.round(ly1);
			var dx = Std.int(Math.abs(x1 - x0));
			var dy = -Std.int(Math.abs(y1 - y0));
			var sx = x0 < x1 ? 1 : -1;
			var sy = y0 < y1 ? 1 : -1;
			var err = dx + dy;
			while (true) {
				if (x0 >= 0 && x0 < w && y0 >= 0 && y0 < h2)
					fishingLine.pixels.setPixel32(x0, y0, FlxColor.WHITE);
				if (x0 == x1 && y0 == y1)
					break;
				var e2 = 2 * err;
				if (e2 >= dy) {
					err += dy;
					x0 += sx;
				}
				if (e2 <= dx) {
					err += dx;
					y0 += sy;
				}
			}
		}
		fishingLine.dirty = true;
		fishingLine.visible = true;
		tip.put();
	}

	function launchRock() {
		rockSprite = if (makeRock != null) makeRock(x + 4, y + 4) else new Rock(x + 4, y + 4);
		rockStartPos = FlxPoint.get(rockSprite.x, rockSprite.y);
		var dx = rockTarget.x - rockStartPos.x;
		var dy = rockTarget.y - rockStartPos.y;
		var dist = Math.sqrt(dx * dx + dy * dy);
		rockFlightTime = if (dist > 0) dist / 200 else 0.01;
		rockElapsed = 0;
		state.add(rockSprite);
	}

	function updateRock(elapsed:Float) {
		if (rockSprite == null)
			return;

		rockElapsed += elapsed;
		var t = Math.min(1.0, rockElapsed / rockFlightTime);

		var groundX = rockStartPos.x + (rockTarget.x - rockStartPos.x) * t;
		var groundY = rockStartPos.y + (rockTarget.y - rockStartPos.y) * t;

		var totalDist = Math.sqrt((rockTarget.x - rockStartPos.x) * (rockTarget.x - rockStartPos.x)
			+ (rockTarget.y - rockStartPos.y) * (rockTarget.y - rockStartPos.y));
		var arcHeight = Math.min(totalDist * 0.5, 64);
		var arcOffset = arcHeight * 4 * t * (1 - t);

		rockSprite.setPosition(groundX, groundY - arcOffset);

		if (t >= 1.0) {
			var landX = rockTarget.x;
			var landY = rockTarget.y;
			var landed = rockSprite;
			state.remove(rockSprite);
			rockSprite = null;
			rockTarget.put();
			rockTarget = null;
			rockStartPos.put();
			rockStartPos = null;
			landed.resolveThrow(landX, landY);
			landed.destroy();
		}
	}

	function launchBobber() {
		var reticleDir = lastInputDir.asVector();
		var castDist = castPower * 96;
		var targetX = x + reticleDir.x * castDist + 4;
		var targetY = y + reticleDir.y * castDist + 4;
		reticleDir.put();

		castTarget = FlxPoint.get(targetX, targetY);

		GameManager.ME.net.sendMessage("cast_line", {x: castTarget.x, y: castTarget.y});

		castBobber = new FlxSprite();
		castBobber.loadGraphic(AssetPaths.bobber__png);
		var tip = getRodTipPos();
		castBobber.setPosition(tip.x, tip.y);
		tip.put();

		castStartPos = FlxPoint.get(castBobber.x, castBobber.y);
		var dx = castTarget.x - castStartPos.x;
		var dy = castTarget.y - castStartPos.y;
		var dist = Math.sqrt(dx * dx + dy * dy);
		castFlightTime = if (dist > 0) dist / 150 else 0.01;
		castElapsed = 0;

		state.add(castBobber);
	}

	/** Updates the bobber position along an arc. Returns true when it has arrived. */
	function updateCastArc(elapsed:Float):Bool {
		if (castBobber == null || castTarget == null || castStartPos == null)
			return false;

		castElapsed += elapsed;
		var t = Math.min(1.0, castElapsed / castFlightTime);

		var groundX = castStartPos.x + (castTarget.x - castStartPos.x) * t;
		var groundY = castStartPos.y + (castTarget.y - castStartPos.y) * t;

		var dx = castTarget.x - castStartPos.x;
		var dy = castTarget.y - castStartPos.y;
		var totalDist = Math.sqrt(dx * dx + dy * dy);
		var arcHeight = Math.min(totalDist * 0.3, 48);
		var arcOffset = arcHeight * 4 * t * (1 - t);

		castBobber.setPosition(groundX, groundY - arcOffset);

		return t >= 1.0;
	}

	function updateCast(elapsed:Float) {
		switch (castState) {
			case IDLE:
				if (SimpleController.just_pressed(A)) {
					castState = CHARGING;
					frozen = true;
					castPower = 0;
					castPowerDir = 1;
					powerBarBg.setPosition(x - 8, y + 20);
					powerBarFill.setPosition(x - 8, y + 20);
					powerBarBg.visible = true;
					powerBarFill.visible = true;
					powerBarFill.scale.x = 0;
				}
			case CHARGING:
				castPower += castPowerDir * elapsed * 2.0;
				if (castPower >= 1) {
					castPower = 1;
					castPowerDir = -1;
				} else if (castPower <= 0) {
					castPower = 0;
					castPowerDir = 1;
				}
				powerBarFill.scale.x = castPower;
				powerBarBg.setPosition(x - 8, y + 20);
				powerBarFill.setPosition(x - 8, y + 20);

				if (SimpleController.just_released(A)) {
					powerBarBg.visible = false;
					powerBarFill.visible = false;

					if (castPower < 0.05) {
						castState = IDLE;
						frozen = false;
					} else {
						castState = CAST_ANIM;
						castDirSuffix = getDirSuffix();
						sendAnimUpdate("cast_" + castDirSuffix, true);
					}
				}
			case CAST_ANIM:
				// Arc the bobber toward the target; clamp if it arrives during the animation.
				if (updateCastArc(elapsed)) {
					castBobber.setPosition(castTarget.x, castTarget.y);
				}
			case CATCH_ANIM:
				// Bobber retract started by frame event, check for arrival
				if (castBobber != null) {
					if (retractHasFish && castTarget != null) {
						if (updateCastArc(elapsed)) {
							state.remove(castBobber);
							castBobber.destroy();
							castBobber = null;
							if (onFishDelivered != null)
								onFishDelivered();
						}
					} else {
						var retract = getRetractTarget();
						var px = retract.x;
						var py = retract.y;
						retract.put();
						var dx = px - castBobber.x;
						var dy = py - castBobber.y;
						var dist = Math.sqrt(dx * dx + dy * dy);
						if (dist < 4) {
							state.remove(castBobber);
							castBobber.destroy();
							castBobber = null;
						}
					}
				}
			case CASTING:
				if (SimpleController.just_pressed(A)) {
					catchFish();
				} else if (updateCastArc(elapsed)) {
					castBobber.setPosition(castTarget.x, castTarget.y);
					if (castStartPos != null) {
						castStartPos.put();
						castStartPos = null;
					}
					frozen = false;
					playMovementAnim(true);
					castState = LANDED;
				}
			case LANDED:
				if (SimpleController.just_pressed(A) || velocity.x != 0 || velocity.y != 0) {
					catchFish();
				}
			case RETURNING:
				if (castBobber != null) {
					if (retractHasFish && castTarget != null) {
						if (updateCastArc(elapsed)) {
							state.remove(castBobber);
							castBobber.destroy();
							castBobber = null;
							castState = IDLE;
							frozen = false;
							playMovementAnim(true);
							if (onFishDelivered != null)
								onFishDelivered();
						}
					} else {
						var retract = getRetractTarget();
						var px = retract.x;
						var py = retract.y;
						retract.put();
						var dx = px - castBobber.x;
						var dy = py - castBobber.y;
						var dist = Math.sqrt(dx * dx + dy * dy);
						if (dist < 4) {
							state.remove(castBobber);
							castBobber.destroy();
							castBobber = null;
							castState = IDLE;
							frozen = false;
							playMovementAnim(true);
						} else {
							castBobber.velocity.x = (dx / dist) * 188;
							castBobber.velocity.y = (dy / dist) * 188;
						}
					}
				}
		}
	}

	public function isBobberLanded():Bool {
		return castState == LANDED && castBobber != null;
	}

	public function catchFish(hasFish:Bool = false) {
		if (castState == LANDED || castState == CASTING) {
			castState = CATCH_ANIM;
			frozen = true;
			retractHasFish = hasFish;
			if (castTarget != null) {
				castTarget.put();
				castTarget = null;
			}
			if (castStartPos != null) {
				castStartPos.put();
				castStartPos = null;
			}
			if (castBobber != null) {
				castBobber.velocity.set(0, 0);
				if (hasFish) {
					caughtFishFrame = FlxG.random.int(0, 4);
					castBobber.loadGraphic("assets/aseprite/fish.png", true, 32, 32);
					castBobber.animation.add("fish", [caughtFishFrame]);
					castBobber.animation.play("fish");
				}
			}
			sendAnimUpdate("catch_" + castDirSuffix, true);
		}
	}

	static var ONE_SHOT_PREFIXES:Array<String> = ["cast_", "throw_", "catch_"];

	function loadSkin(jsonPath:String) {
		var jsonText:String = openfl.Assets.getText(jsonPath);
		var json = haxe.Json.parse(jsonText);

		var pngPath = Path.join([Path.directory(jsonPath), json.meta.image]);
		var sheetW:Int = json.meta.size.w;
		var cols:Int = Std.int(sheetW / 48);

		loadGraphic(pngPath, true, 48, 48);
		setSize(16, 16);
		offset.set(16, 16);

		var frames:Array<Dynamic> = json.frames;
		var tags:Array<Dynamic> = json.meta.frameTags;
		for (tag in tags) {
			var name:String = tag.name;
			var from:Int = tag.from;
			var to:Int = tag.to;
			var indices:Array<Int> = [];
			for (i in from...to + 1) {
				var fx:Int = frames[i].frame.x;
				var fy:Int = frames[i].frame.y;
				indices.push(Std.int(fy / 48) * cols + Std.int(fx / 48));
			}
			var loop = true;
			for (p in ONE_SHOT_PREFIXES) {
				if (StringTools.startsWith(name, p)) {
					loop = false;
					break;
				}
			}
			animation.add(name, indices, 12, loop);
		}
	}

	function swapSkin() {
		var curAnim = animation.curAnim;
		var animName = curAnim != null ? curAnim.name : null;
		var animFrame = curAnim != null ? curAnim.curFrame : 0;
		loadSkin(SKINS[skinIndex]);
		if (animName != null) {
			animation.play(animName, false, false, animFrame);
		}
	}

	public function pickupItem(item:InventoryItem):Bool {
		return inventory.add(item);
	}

	function getDirSuffix():String {
		return switch (lastInputDir) {
			case N: "up";
			case S: "down";
			case W: "left";
			case E: "right";
			default: "down";
		};
	}

	function getRetractTarget():FlxPoint {
		return switch (castDirSuffix) {
			case "right": FlxPoint.get(x + 8, y - 2);
			case "left": FlxPoint.get(x + 8, y - 2);
			case "down": FlxPoint.get(x, y + 4);
			case "up": FlxPoint.get(x + 12, y + 4);
			default: FlxPoint.get(x + 4, y + 4);
		};
	}

	override function destroy() {
		onAnimUpdate.removeAll();
		if (rockTarget != null) {
			rockTarget.put();
			rockTarget = null;
		}
		if (rockStartPos != null) {
			rockStartPos.put();
			rockStartPos = null;
		}
		cleanupNetwork();
		super.destroy();
	}

	private function cleanupNetwork() {
		GameManager.ME.net.onPlayerChanged.remove(handleChange);
	}
}

enum CastState {
	IDLE;
	CHARGING;
	CAST_ANIM;
	CASTING;
	LANDED;
	CATCH_ANIM;
	RETURNING;
}
