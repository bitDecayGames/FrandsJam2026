package entities;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;

class Weed extends FlxSprite {
	var parentState:FlxState;

	public function new(cx:Float, cy:Float, state:FlxState) {
		super(cx, cy);
		parentState = state;
		loadGraphic(AssetPaths.weed__png);
		x -= width / 2;
		y -= height / 2;
		var gfxH = frameHeight;
		setSize(frameWidth, 1);
		offset.set(0, gfxH - 1);
	}

	public function burst() {
		var cx = x - offset.x + frameWidth / 2;
		var cy = y - offset.y + frameHeight / 2;
		for (_ in 0...12) {
			parentState.add(new LeafParticle(cx + FlxG.random.float(-3, 3), cy + FlxG.random.float(-3, 3)));
		}
		kill();
	}
}
