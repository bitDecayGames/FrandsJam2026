package entities;

import flixel.FlxSprite;
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

	static inline var FRAME_DOWN = 1;
	static inline var FRAME_RIGHT = 2;
	static inline var FRAME_UP = 3;
	static inline var FRAME_LEFT = 4;

	public function new(X:Float, Y:Float) {
		super(X, Y);
		loadGraphic(AssetPaths.playerA__png, true, 48, 48);
		setSize(16, 16);
		offset.set(16, 16);
		animation.frameIndex = FRAME_DOWN;
	}

	override public function update(delta:Float) {
		super.update(delta);

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

		if (SimpleController.just_pressed(Button.A, playerNum)) {
			color = color ^ 0xFFFFFF;
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
