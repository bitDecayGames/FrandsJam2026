package entities;

import schema.PlayerState;
import net.NetworkManager;
import flixel.FlxSprite;
import input.InputCalculator;
import input.SimpleController;
import bitdecay.flixel.spacial.Cardinal;
import flixel.FlxG;

class Player extends FlxSprite {
	var speed:Float = 150;
	var playerNum = 0;
	var lastInputDir:Cardinal = E;

	public var hotModeActive:Bool = false;

	var hotModeTimer:Float = 0;

	static inline var FRAME_DOWN = 1;
	static inline var FRAME_RIGHT = 2;
	static inline var FRAME_UP = 3;
	static inline var FRAME_LEFT = 4;

	// Network stuff
	var net:NetworkManager = null;

	public var sessionId:String = "";

	// tracks if this player is controled by the remote client
	public var isRemote:Bool = false;

	public function new(X:Float, Y:Float) {
		// super(X, Y);
		// // This call can be used once https://github.com/HaxeFlixel/flixel/pull/2860 is merged
		// // FlxAsepriteUtil.loadAseAtlasAndTags(this, AssetPaths.player__png, AssetPaths.player__json);
		// Aseprite.loadAllAnimations(this, AssetPaths.player__json);
		// animation.play(anims.right);
		// animation.onFrameChange.add((anim, frame, index) -> {
		// 	if (eventData.exists(index)) {
		// 		// trace('frame $index has data ${eventData.get(index)}');
		// 	}
		// });

		super(X, Y);
		loadGraphic(AssetPaths.playerA__png, true, 48, 48);
		setSize(16, 16);
		offset.set(16, 16);
		animation.frameIndex = FRAME_DOWN;
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

		if (net != null) {
			net.update();
			net.sendMove(x, y);
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
