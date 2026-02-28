package entities;

import schema.PlayerState;
import net.NetworkManager;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.math.FlxPoint;
import flixel.util.FlxColor;
import input.InputCalculator;
import input.SimpleController;
import bitdecay.flixel.spacial.Cardinal;
import flixel.FlxG;

class Player extends FlxSprite {
	// 0-indexed frame within the cast animation when the bobber launches
	static inline var CAST_LAUNCH_FRAME:Int = 3;

	var speed:Float = 150;
	var playerNum = 0;

	public var hotModeActive:Bool = false;

	var hotModeTimer:Float = 0;

	public var lastInputDir:Cardinal = E;

	var frozen:Bool = false;

	// Network stuff
	var net:NetworkManager = null;

	public var sessionId:String = "";

	// tracks if this player is controled by the remote client
	public var isRemote:Bool = false;

	// Cast state
	var castState:CastState = IDLE;
	var castBobber:FlxSprite;
	var castTarget:FlxPoint;
	var castPower:Float = 0;
	var castPowerDir:Float = 1;

	// Cast sprites
	var reticle:FlxSprite;
	var powerBarBg:FlxSprite;
	var powerBarFill:FlxSprite;

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
		animation.play("stand_down");

		animation.onFrameChange.add(onAnimFrameChange);
		animation.onFinish.add(onAnimFinish);

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
	}

	function onAnimFinish(animName:String) {
		if (castState == CAST_ANIM) {
			castState = CASTING;
			frozen = false;
		}
	}

	public function setNetwork(net:NetworkManager, session:String) {
		cleanupNetwork();

		this.net = net;
		net.onPCh.add(handleChange);
		sessionId = session;
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
						moveDir.asVector(velocity).scale(speed * 1.5);
					}
				}
			} else {
				if (inputDir != NONE) {
					inputDir.asVector(velocity).scale(speed);
				} else {
					velocity.set();
				}
			}
		}

		updateAnim();
		updateReticle();
		updateCast(delta);

		if (net != null) {
			net.update();
			net.sendMove(x, y);
		}
	}

	function updateReticle() {
		if (reticle == null)
			return;
		var reticleOffset = lastInputDir.asVector();
		reticle.setPosition(x + reticleOffset.x * 96 + 4, y + reticleOffset.y * 96 + 4);
		reticleOffset.put();
	}

	function launchBobber() {
		var reticleDir = lastInputDir.asVector();
		var castDist = castPower * 96;
		var targetX = x + reticleDir.x * castDist + 4;
		var targetY = y + reticleDir.y * castDist + 4;
		reticleDir.put();

		castTarget = FlxPoint.get(targetX, targetY);

		if (net != null)
			net.setMessage("cast_line", {x: castTarget.x, y: castTarget.y});

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

				if (SimpleController.just_pressed(A)) {
					powerBarBg.visible = false;
					powerBarFill.visible = false;

					if (castPower < 0.05) {
						castState = IDLE;
						frozen = false;
					} else {
						castState = CAST_ANIM;
						var dirSuffix = getDirSuffix();
						animation.play("cast_" + dirSuffix, true);
					}
				}
			case CAST_ANIM:
				// Handled by onAnimFrameChange and onAnimFinish signals
			case CASTING:
				if (castBobber != null && castTarget != null) {
					if (FlxG.keys.justPressed.Z || velocity.x != 0 || velocity.y != 0) {
						castState = RETURNING;
						castTarget.put();
						castTarget = null;
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
					castState = RETURNING;
					castTarget.put();
					castTarget = null;
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

	function getDirSuffix():String {
		return switch (lastInputDir) {
			case N: "up";
			case S: "down";
			case W: "left";
			case E: "right";
			default: "down";
		};
	}

	function updateAnim() {
		// Don't override cast animations
		if (castState == CAST_ANIM)
			return;

		var dirSuffix = getDirSuffix();
		var moving = velocity.x != 0 || velocity.y != 0;
		var animName = (moving ? "run_" : "stand_") + dirSuffix;

		if (animation.name != animName)
			animation.play(animName);
	}

	override function destroy() {
		cleanupNetwork();
		super.destroy();
	}

	private function cleanupNetwork() {
		if (net == null) {
			return;
		}

		this.net.onPCh.remove(handleChange);
	}
}

enum CastState {
	IDLE;
	CHARGING;
	CAST_ANIM;
	CASTING;
	LANDED;
	RETURNING;
}
