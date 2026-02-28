package entities;

import flixel.FlxSprite;
import flixel.FlxState;
import flixel.math.FlxPoint;
import flixel.util.FlxColor;
import input.InputCalculator;
import input.SimpleController;
import bitdecay.flixel.spacial.Cardinal;
import flixel.FlxG;

class Player extends FlxSprite {
	var speed:Float = 150;
	var playerNum = 0;

	public var hotModeActive:Bool = false;

	var hotModeTimer:Float = 0;

	public var lastInputDir:Cardinal = E;

	var frozen:Bool = false;

	static inline var FRAME_DOWN = 1;
	static inline var FRAME_RIGHT = 2;
	static inline var FRAME_UP = 3;
	static inline var FRAME_LEFT = 4;

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
		animation.frameIndex = FRAME_DOWN;

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

	override public function update(delta:Float) {
		super.update(delta);

		if (frozen) {
			velocity.set();
		} else {
			var inputDir = InputCalculator.getInputCardinal(playerNum);
			if (inputDir != NONE) {
				lastInputDir = inputDir;
				updateFrame(inputDir);
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

		updateReticle();
		updateCast(delta);
	}

	function updateReticle() {
		if (reticle == null)
			return;
		var reticleOffset = lastInputDir.asVector();
		reticle.setPosition(x + reticleOffset.x * 96 + 4, y + reticleOffset.y * 96 + 4);
		reticleOffset.put();
	}

	function updateCast(elapsed:Float) {
		switch (castState) {
			case IDLE:
				if (FlxG.keys.justPressed.Z) {
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

				if (FlxG.keys.justPressed.Z) {
					powerBarBg.visible = false;
					powerBarFill.visible = false;
					frozen = false;

					if (castPower < 0.05) {
						castState = IDLE;
					} else {
						castState = CASTING;
						var reticleDir = lastInputDir.asVector();
						var castDist = castPower * 96;
						var targetX = x + reticleDir.x * castDist + 4;
						var targetY = y + reticleDir.y * castDist + 4;
						reticleDir.put();

						castTarget = FlxPoint.get(targetX, targetY);
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
				}
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
				if (FlxG.keys.justPressed.Z || velocity.x != 0 || velocity.y != 0) {
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

	function updateFrame(dir:Cardinal) {
		switch (dir) {
			case N:
				animation.frameIndex = FRAME_UP;
			case S:
				animation.frameIndex = FRAME_DOWN;
			case W:
				animation.frameIndex = FRAME_LEFT;
			case E:
				animation.frameIndex = FRAME_RIGHT;
			default:
		}
	}
}

enum CastState {
	IDLE;
	CHARGING;
	CASTING;
	LANDED;
	RETURNING;
}
