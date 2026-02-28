package entities;

import flixel.FlxSprite;
import input.InputCalculator;
import input.SimpleController;
import bitdecay.flixel.graphics.Aseprite;
import bitdecay.flixel.graphics.AsepriteMacros;
import bitdecay.flixel.spacial.Cardinal;
import flixel.FlxG;

class Player extends FlxSprite {
	public static var anims = AsepriteMacros.tagNames("assets/aseprite/characters/player.json");
	public static var layers = AsepriteMacros.layerNames("assets/aseprite/characters/player.json");
	public static var eventData = AsepriteMacros.frameUserData("assets/aseprite/characters/player.json", "Layer 1");

	var speed:Float = 150;
	var playerNum = 0;

	public var hotModeActive:Bool = false;
	var hotModeTimer:Float = 0;
	var lastInputDir:Cardinal = E;

	public function new(X:Float, Y:Float) {
		super(X, Y);
		// This call can be used once https://github.com/HaxeFlixel/flixel/pull/2860 is merged
		// FlxAsepriteUtil.loadAseAtlasAndTags(this, AssetPaths.player__png, AssetPaths.player__json);
		Aseprite.loadAllAnimations(this, AssetPaths.player__json);
		animation.play(anims.right);
		animation.onFrameChange.add((anim, frame, index) -> {
			if (eventData.exists(index)) {
				trace('frame $index has data ${eventData.get(index)}');
			}
		});
	}

	override public function update(delta:Float) {
		super.update(delta);

		var inputDir = InputCalculator.getInputCardinal(playerNum);
		if (inputDir != NONE) {
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
					moveDir.asVector(velocity).scale(speed * 2);
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
}
