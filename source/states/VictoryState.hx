package states;

import entities.FishTypes;
import flixel.FlxSprite;
import managers.GameManager;
import flixel.addons.transition.FlxTransitionableState;
import flixel.FlxG;
import flixel.text.FlxText;
import flixel.ui.FlxButton;
import flixel.util.FlxColor;
import haxefmod.flixel.FmodFlxUtilities;
import todo.TODO;
import ui.MenuBuilder;

using states.FlxStateExt;

class VictoryState extends FlxTransitionableState {
	var _btnDone:FlxButton;
	var _txtTitle:FlxText;

	static inline var LEFT_MARGIN:Int = 40;
	static inline var START_Y:Int = 90;
	static inline var ROUND_HEADER_SIZE:Int = 14;
	static inline var FISH_ICON_NATIVE:Int = 32;
	static inline var FISH_ICON_SIZE:Int = 48;
	static inline var FISH_ICON_STEP:Int = 36;
	static inline var FISH_LABEL_SIZE:Int = 12;
	static inline var FISH_LABEL_LINE_HEIGHT:Int = 10;
	static inline var FISH_BLOCK_HEIGHT:Int = 48 + 10 + 10 + 6;
	static inline var ROUND_SECTION_GAP:Int = 10;

	override public function create():Void {
		super.create();
		TODO.sfx("victory_music");
		bgColor = 0xff73efe8; // turquoise from title screen

		// var gm = GameManager.ME;

		// Find the overall winner (highest total score)
		// var winnerSessionId = gm.mySessionId;
		// var winnerScore = gm.scores.exists(gm.mySessionId) ? gm.scores.get(gm.mySessionId) : 0;
		// for (sessionId in gm.sessions) {
		// 	var score = gm.scores.exists(sessionId) ? gm.scores.get(sessionId) : 0;
		// 	if (score > winnerScore) {
		// 		winnerScore = score;
		// 		winnerSessionId = sessionId;
		// 	}
		// }
		// var winnerName = gm.names.get(winnerSessionId);
		// if (winnerName == null || winnerName == "") {
		// 	winnerName = winnerSessionId == gm.mySessionId ? "You" : "???";
		// }

		// _txtTitle = new FlxText();
		// _txtTitle.setFormat(Main.menuFont, 36, FlxColor.RED, FlxTextAlign.CENTER);
		// _txtTitle.text = winnerName + " wins!";
		// _txtTitle.setPosition(FlxG.width / 2 - _txtTitle.width / 2, 20);
		// add(_txtTitle);

		// var totalText = new FlxText();
		// totalText.setFormat(Main.menuFont, 16, 0xff2b4e95, FlxTextAlign.CENTER);
		// totalText.text = formatMoney(winnerScore) + " total";
		// totalText.setPosition(FlxG.width / 2 - totalText.width / 2, 62);
		// add(totalText);

		// Fish per round
		// var currentY = START_Y;
		// var totalRounds = gm.soldFish.length;
		// for (roundNum in 0...totalRounds) {
		// 	var fishEntries = gm.getSoldFish(roundNum, winnerSessionId);

		// 	var roundLabel = new FlxText();
		// 	roundLabel.setFormat(Main.menuFont, ROUND_HEADER_SIZE, 0xff2b4e95);
		// 	roundLabel.text = "Round " + (roundNum + 1);
		// 	roundLabel.setPosition(LEFT_MARGIN, currentY);
		// 	add(roundLabel);
		// 	currentY += ROUND_HEADER_SIZE + 4;

		// 	if (fishEntries.length == 0) {
		// 		var noneText = new FlxText();
		// 		noneText.setFormat(Main.menuFont, FISH_LABEL_SIZE, 0xff2b4e95);
		// 		noneText.text = "No fish sold";
		// 		noneText.setPosition(LEFT_MARGIN + 10, currentY);
		// 		add(noneText);
		// 		currentY += FISH_LABEL_SIZE + ROUND_SECTION_GAP;
		// 	} else {
		// 		var fishX = LEFT_MARGIN + 10;
		// 		var iconY = currentY + FISH_LABEL_LINE_HEIGHT * 2;
		// 		// for (fish in fishEntries) {
		// 		// 	// Length label
		// 		// 	var lenText = new FlxText();
		// 		// 	lenText.setFormat(Main.menuFont, FISH_LABEL_SIZE, 0xff2b4e95);
		// 		// 	lenText.text = Std.string(fish.lengthCm) + "cm";
		// 		// 	lenText.setPosition(fishX + FISH_ICON_SIZE / 2 - lenText.width / 2, currentY);
		// 		// 	add(lenText);

		// 		// 	// Value label
		// 		// 	var valText = new FlxText();
		// 		// 	valText.setFormat(Main.menuFont, FISH_LABEL_SIZE, 0xff2b4e95);
		// 		// 	valText.text = formatMoney(fish.value);
		// 		// 	valText.setPosition(fishX + FISH_ICON_SIZE / 2 - valText.width / 2, currentY + FISH_LABEL_LINE_HEIGHT);
		// 		// 	add(valText);

		// 		// 	// Fish sprite
		// 		// 	var fishSprite = new FlxSprite();
		// 		// 	fishSprite.loadGraphic(AssetPaths.fish__png, true, FISH_ICON_NATIVE, FISH_ICON_NATIVE);
		// 		// 	fishSprite.animation.add("show", [fish.fishType]);
		// 		// 	fishSprite.animation.play("show");
		// 		// 	fishSprite.scale.set(FISH_ICON_SIZE / FISH_ICON_NATIVE, FISH_ICON_SIZE / FISH_ICON_NATIVE);
		// 		// 	fishSprite.updateHitbox();
		// 		// 	fishSprite.setPosition(fishX + FISH_ICON_SIZE / 2, iconY);
		// 		// 	add(fishSprite);

		// 		// 	fishX += FISH_ICON_STEP;
		// 		// }
		// 		currentY += FISH_BLOCK_HEIGHT + ROUND_SECTION_GAP;
		// 	}
		// }

		_btnDone = MenuBuilder.createTextButton("Main Menu", clickMainMenu);
		_btnDone.setPosition(FlxG.width / 2 - _btnDone.width / 2, FlxG.height - _btnDone.height - 20);
		_btnDone.updateHitbox();
		add(_btnDone);
	}

	override public function update(elapsed:Float):Void {
		super.update(elapsed);
		_txtTitle.x = FlxG.width / 2 - _txtTitle.width / 2;
	}

	private static function formatMoney(amount:Int):String {
		var negative = amount < 0;
		var abs = negative ? -amount : amount;
		var str = Std.string(abs);
		var result = "";
		var count = 0;
		var i = str.length - 1;
		while (i >= 0) {
			if (count > 0 && count % 3 == 0) {
				result = "," + result;
			}
			result = str.charAt(i) + result;
			count++;
			i--;
		}
		return (negative ? "-$" : "$") + result;
	}

	function clickMainMenu():Void {
		FlxFmod.switchState(MainMenuState.new);
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
