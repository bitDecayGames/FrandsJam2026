package entities;

import schema.PlayerState;
import net.NetworkManager;
import flixel.FlxSprite;
import input.InputCalculator;
import input.SimpleController;
import bitdecay.flixel.graphics.Aseprite;
import bitdecay.flixel.graphics.AsepriteMacros;

class Player extends FlxSprite {
	public static var anims = AsepriteMacros.tagNames("assets/aseprite/characters/player.json");
	public static var layers = AsepriteMacros.layerNames("assets/aseprite/characters/player.json");
	public static var eventData = AsepriteMacros.frameUserData("assets/aseprite/characters/player.json", "Layer 1");

	var speed:Float = 150;
	var playerNum = 0;

	// Network stuff
	var net:NetworkManager = null;

	public var sessionId:String = "";

	// tracks if this player is controled by the remote client
	public var isRemote:Bool = false;

	public function new(X:Float, Y:Float) {
		super(X, Y);
		// This call can be used once https://github.com/HaxeFlixel/flixel/pull/2860 is merged
		// FlxAsepriteUtil.loadAseAtlasAndTags(this, AssetPaths.player__png, AssetPaths.player__json);
		Aseprite.loadAllAnimations(this, AssetPaths.player__json);
		animation.play(anims.right);
		animation.onFrameChange.add((anim, frame, index) -> {
			if (eventData.exists(index)) {
				// trace('frame $index has data ${eventData.get(index)}');
			}
		});
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

		if (!isRemote) {
			var inputDir = InputCalculator.getInputCardinal(playerNum);
			if (inputDir != NONE) {
				inputDir.asVector(velocity).scale(speed);
			} else {
				velocity.set();
			}

			if (SimpleController.just_pressed(Button.A, playerNum)) {
				color = color ^ 0xFFFFFF;
			}

			if (net != null) {
				net.update();
				net.sendMove(x, y);
			}
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
