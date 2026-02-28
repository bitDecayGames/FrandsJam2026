package entities;

import managers.GameManager;
import schema.PlayerState;
import net.NetworkManager;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.math.FlxPoint;
import flixel.util.FlxColor;
import flixel.util.FlxSignal;
import input.InputCalculator;
import input.SimpleController;
import bitdecay.flixel.spacial.Cardinal;
import flixel.FlxG;

class Player extends FlxSprite {
	// 0-indexed frame within the cast animation when the bobber launches
	static inline var CAST_LAUNCH_FRAME:Int = 3;
	// 0-indexed frame within the catch animation when the bobber retracts (1 before final)
	static inline var CATCH_RETRACT_FRAME:Int = 1;

	var speed:Float = 150;
	var playerNum = 0;

	public var hotModeActive:Bool = false;

	var hotModeTimer:Float = 0;

	public var lastInputDir:Cardinal = E;

	var frozen:Bool = false;

	public var sessionId:String = "";

	// tracks if this player is controled by the remote client
	public var isRemote:Bool = false;

	// Cast state
	var castState:CastState = IDLE;

	public var castBobber(default, null):FlxSprite;

	var castTarget:FlxPoint;
	var castPower:Float = 0;
	var castPowerDir:Float = 1;
	var castDirSuffix:String = "down";

	// Cast sprites
	var reticle:FlxSprite;
	var powerBarBg:FlxSprite;
	var powerBarFill:FlxSprite;

	// Animation state tracking
	var lastMoving:Bool = false;
	var lastAnimDir:Cardinal = E;

	public var onAnimUpdate = new FlxTypedSignal<(String, Bool) -> Void>();

	var state:FlxState;

	public function new(X:Float, Y:Float, state:FlxState) {
		super(X, Y);
		this.state = state;
		loadGraphic(AssetPaths.playerA__png, true, 48, 48);
		setSize(16, 16);
		offset.set(16, 16);

		animation.add("stand_down", [1]);
		animation.add("run_down", [2, 3, 4, 5, 6, 7, 8, 9], 12, true);
		animation.add("stand_right", [10]);
		animation.add("run_right", [11, 12, 13, 14, 15, 16, 17, 18], 12, true);
		animation.add("stand_up", [19]);
		animation.add("run_up", [20, 21, 22, 23, 24, 25, 26, 23], 12, true);
		animation.add("stand_left", [28]);
		animation.add("run_left", [29, 30, 31, 32, 33, 34, 35, 36], 12, true);
		animation.add("cast_down", [37, 38, 39, 40, 41], 12, false);
		animation.add("cast_right", [43, 44, 45, 46, 47], 12, false);
		animation.add("cast_up", [49, 50, 51, 52, 53], 12, false);
		animation.add("cast_left", [55, 56, 57, 58, 59], 12, false);
		animation.add("catch_down", [88, 89, 90], 12, false);
		animation.add("catch_right", [91, 92, 93], 12, false);
		animation.add("catch_up", [94, 95, 96], 12, false);
		animation.add("catch_left", [97, 98, 99], 12, false);

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
		if (castState == CATCH_ANIM && frameNumber == CATCH_RETRACT_FRAME && castBobber != null) {
			var px = x + 4;
			var py = y + 4;
			var dx = px - castBobber.x;
			var dy = py - castBobber.y;
			var dist = Math.sqrt(dx * dx + dy * dy);
			if (dist > 0) {
				castBobber.velocity.x = (dx / dist) * 500;
				castBobber.velocity.y = (dy / dist) * 500;
			}
		}
	}

	function onAnimFinish(animName:String) {
		if (castState == CAST_ANIM) {
			castState = CASTING;
			frozen = false;
			playMovementAnim(true);
		} else if (castState == CATCH_ANIM) {
			if (castBobber != null) {
				castState = RETURNING;
			} else {
				castState = IDLE;
			}
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
		if (castState != CAST_ANIM && castState != CATCH_ANIM) {
			playMovementAnim();
		}

		updateReticle();
		updateCast(delta);

		GameManager.ME.net.sendMove(x, y);
	}

	function updateReticle() {
		if (reticle == null)
			return;
		var reticleOffset = lastInputDir.asVector();
		reticle.setPosition(last.x + reticleOffset.x * 96 + 4, last.y + reticleOffset.y * 96 + 4);
		reticleOffset.put();
	}

	function launchBobber() {
		var reticleDir = lastInputDir.asVector();
		var castDist = castPower * 96;
		var targetX = x + reticleDir.x * castDist + 4;
		var targetY = y + reticleDir.y * castDist + 4;
		reticleDir.put();

		castTarget = FlxPoint.get(targetX, targetY);

		GameManager.ME.net.setMessage("cast_line", {x: castTarget.x, y: castTarget.y});

		castBobber = new FlxSprite();
		castBobber.makeGraphic(8, 8, FlxColor.RED);
		castBobber.setPosition(x + 4, y + 4);
		var dx = castTarget.x - castBobber.x;
		var dy = castTarget.y - castBobber.y;
		var dist = Math.sqrt(dx * dx + dy * dy);
		if (dist > 0) {
			castBobber.velocity.x = (dx / dist) * 300;
			castBobber.velocity.y = (dy / dist) * 300;
		}
		state.add(castBobber);
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
				// Animation signals handle state transitions.
				// Clamp bobber at target if it arrives during the animation.
				if (castBobber != null && castTarget != null) {
					var dx = castTarget.x - castBobber.x;
					var dy = castTarget.y - castBobber.y;
					var dot = dx * castBobber.velocity.x + dy * castBobber.velocity.y;
					if (dot <= 0) {
						castBobber.setPosition(castTarget.x, castTarget.y);
						castBobber.velocity.set(0, 0);
					}
				}
			case CATCH_ANIM:
				// Bobber retract started by frame event, check for arrival
				if (castBobber != null) {
					var px = x + 4;
					var py = y + 4;
					var dx = px - castBobber.x;
					var dy = py - castBobber.y;
					var dist = Math.sqrt(dx * dx + dy * dy);
					if (dist < 4) {
						state.remove(castBobber);
						castBobber.destroy();
						castBobber = null;
					}
				}
			case CASTING:
				if (castBobber != null && castTarget != null) {
					if (SimpleController.just_pressed(A)) {
						catchFish();
					} else {
						var dx = castTarget.x - castBobber.x;
						var dy = castTarget.y - castBobber.y;
						var dot = dx * castBobber.velocity.x + dy * castBobber.velocity.y;
						if (dot <= 0) {
							castBobber.setPosition(castTarget.x, castTarget.y);
							castBobber.velocity.set(0, 0);
							castState = LANDED;
						}
					}
				}
			case LANDED:
				if (SimpleController.just_pressed(A) || velocity.x != 0 || velocity.y != 0) {
					catchFish();
				}
			case RETURNING:
				if (castBobber != null) {
					var px = x + 4;
					var py = y + 4;
					var dx = px - castBobber.x;
					var dy = py - castBobber.y;
					var dist = Math.sqrt(dx * dx + dy * dy);
					if (dist < 4) {
						state.remove(castBobber);
						castBobber.destroy();
						castBobber = null;
						castState = IDLE;
					} else {
						castBobber.velocity.x = (dx / dist) * 500;
						castBobber.velocity.y = (dy / dist) * 500;
					}
				}
		}
	}

	public function isBobberLanded():Bool {
		return castState == LANDED && castBobber != null;
	}

	public function catchFish() {
		if (castState == LANDED || castState == CASTING) {
			castState = CATCH_ANIM;
			frozen = true;
			if (castTarget != null) {
				castTarget.put();
				castTarget = null;
			}
			if (castBobber != null) {
				castBobber.velocity.set(0, 0);
			}
			sendAnimUpdate("catch_" + castDirSuffix, true);
		}
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

	override function destroy() {
		onAnimUpdate.removeAll();
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
