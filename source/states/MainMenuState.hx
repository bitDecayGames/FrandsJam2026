package states;

import bitdecay.flixel.graphics.AsepriteMacros;
import bitdecay.flixel.graphics.Aseprite;
import haxefmod.FlxFmod;
import ui.MenuBuilder;
import com.bitdecay.analytics.Bitlytics;
import bitdecay.flixel.transitions.SwirlTransition;
import bitdecay.flixel.transitions.TransitionDirection;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.addons.transition.FlxTransitionableState;
import flixel.ui.FlxButton;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import flixel.util.FlxSpriteUtil;
import haxefmod.flixel.FmodFlxUtilities;
import input.SimpleController;
import states.AchievementsState;
import managers.GameManager;

using states.FlxStateExt;

class MainMenuState extends FlxTransitionableState {
	public static var anims = AsepriteMacros.tagNames("assets/aseprite/title.json");

	var singlePlayerButton:FlxButton;
	var multiplayerButton:FlxButton;
	var handleInput = true;

	public function new() {
		super();
	}

	override public function create():Void {
		super.create();
		bgColor = FlxColor.TRANSPARENT;
		FlxG.camera.pixelPerfectRender = true;

		var bgImage = new FlxSprite();
		Aseprite.loadAllAnimations(bgImage, AssetPaths.title__json);
		bgImage.animation.play(anims.all_frames);
		bgImage.scale.set(camera.width / bgImage.width, camera.height / bgImage.height);
		bgImage.screenCenter();
		add(bgImage);

		// Single player runs an embedded server; multiplayer connects to a remote host
		singlePlayerButton = MenuBuilder.createTextButton("Single Player", clickSinglePlayer, MenuSelect, MenuHover);
		singlePlayerButton.screenCenter(X);
		singlePlayerButton.y = FlxG.height * .6;
		add(singlePlayerButton);

		multiplayerButton = MenuBuilder.createTextButton("Multiplayer", clickMultiplayer, MenuSelect, MenuHover);
		multiplayerButton.screenCenter(X);
		multiplayerButton.y = singlePlayerButton.y + singlePlayerButton.height + 12;
		add(multiplayerButton);

		var creditsButton = MenuBuilder.createTextButton("Credits", clickCredits, MenuSelect, MenuHover);
		creditsButton.setPosition(10, FlxG.height - creditsButton.height - 10);
		add(creditsButton);

		// FmodManager.PlaySong(FmodSongs.LetsGo);

		// we will handle transitions manually
		transOut = null;
	}

	override public function update(elapsed:Float):Void {
		super.update(elapsed);

		if (FlxG.keys.pressed.D && FlxG.keys.justPressed.M) {
			// Keys D.M. for Disable Metrics
			Bitlytics.Instance().EndSession(false);
			FmodManager.PlaySoundOneShot(FmodSFX.MenuSelect);
			trace("---------- Bitlytics Stopped ----------");
		}

		if (handleInput && SimpleController.just_pressed(START)) {
			handleInput = false;
			FlxSpriteUtil.flicker(singlePlayerButton, 0, 0.25);
			new FlxTimer().start(1, (t) -> {
				clickSinglePlayer();
			});
		}
	}

	function clickSinglePlayer():Void {
		GameManager.soloMode = true;
		startGame();
	}

	function clickMultiplayer():Void {
		GameManager.soloMode = false;
		startGame();
	}

	function startGame():Void {
		FmodManager.StopSong();
		FlxG.switchState(() -> new LobbyState());
	}

	// If we want to add a way to go to credits from main menu, call this
	function clickCredits():Void {
		FlxFmod.switchState(CreditsState.new);
	}

	// If we want to add a way to go to achievements from main menu, call this
	function clickAchievements():Void {
		FlxFmod.switchState(AchievementsState.new);
	}

	override public function onFocusLost() {
		super.onFocusLost();
		this.handleFocusLost();
	}

	override public function onFocus() {
		super.onFocus();
		this.handleFocus();
	}
}
