package states;

import entities.FishTypes;
import flixel.FlxSprite;
import schema.RoundState;
import managers.GameManager;
import net.NetworkManager;
import flixel.addons.transition.FlxTransitionableState;
import flixel.FlxG;
import flixel.text.FlxText;
import flixel.ui.FlxButton;
import flixel.util.FlxColor;
import ui.MenuBuilder;

using states.FlxStateExt;

class PostRoundState extends FlxTransitionableState {
	var _btnDone:FlxButton;
	var _txtReady:FlxText;
	var _txtOtherPlayers:FlxText;
	var _localReady:Bool = false;

	var _txtTitle:FlxText;

	// Score display
	var _scoreNameTexts:Array<FlxText> = [];
	var _scorePlaceTexts:Array<FlxText> = [];
	var _scoreValueTexts:Array<FlxText> = [];

	static inline var SCORE_LEFT_MARGIN:Int = 40;
	static inline var SCORE_RIGHT_MARGIN:Int = 40;
	static inline var SCORE_START_Y:Int = 100;
	static inline var SCORE_ROW_HEIGHT:Int = 36;
	static inline var FIRST_PLACE_SIZE:Int = 20;
	static inline var OTHER_PLACE_SIZE:Int = 16;
	static inline var FISH_ICON_NATIVE:Int = 32;
	static inline var FISH_ICON_SIZE:Int = 64; // displayed size (2x native)
	static inline var FISH_ICON_PADDING:Int = 8;
	static inline var FISH_LABEL_SIZE:Int = 10;
	static inline var FISH_LABEL_LINE_HEIGHT:Int = 12;
	// total vertical space for one fish icon + two text lines below it
	static inline var FISH_BLOCK_HEIGHT:Int = 64 + 12 + 12 + 6; // icon + length + value + gap

	override public function create():Void {
		super.create();
		bgColor = FlxColor.TRANSPARENT;

		_txtTitle = new FlxText();
		_txtTitle.setPosition(FlxG.width / 2, 20);
		_txtTitle.size = 40;
		_txtTitle.alignment = FlxTextAlign.CENTER;
		_txtTitle.text = "Round Winner!";
		add(_txtTitle);

		// Build the scoreboard
		buildScoreboard();

		// Build weed/worm kill stats at top-left
		buildKillStats();

		// Ready button at the bottom center
		_btnDone = MenuBuilder.createTextButton("Ready", clickReady);
		_btnDone.setPosition(FlxG.width / 2 - _btnDone.width / 2, FlxG.height - _btnDone.height - 40);
		_btnDone.updateHitbox();
		add(_btnDone);

		_txtReady = new FlxText();
		_txtReady.size = 24;
		_txtReady.alignment = FlxTextAlign.CENTER;
		_txtReady.color = FlxColor.LIME;
		_txtReady.text = "READY";
		_txtReady.setPosition(FlxG.width / 2 - _txtReady.width / 2, _btnDone.y);
		_txtReady.visible = false;
		add(_txtReady);

		_txtOtherPlayers = new FlxText();
		_txtOtherPlayers.size = 10;
		_txtOtherPlayers.alignment = FlxTextAlign.RIGHT;
		_txtOtherPlayers.text = "";
		add(_txtOtherPlayers);

		GameManager.ME.setStatus(RoundState.STATUS_POST_ROUND);
	}

	private function buildScoreboard():Void {
		var gm = GameManager.ME;
		var roundNum = gm.getCurrentRoundNumber();

		// Gather all player scores (local + remote)
		var entries:Array<{sessionId:String, name:String, score:Int}> = [];

		// Local player
		var localName = gm.names.get(gm.mySessionId);
		if (localName == null || localName == "") {
			localName = "You";
		}
		var localScore = gm.scores.exists(gm.mySessionId) ? gm.scores.get(gm.mySessionId) : 0;
		entries.push({sessionId: gm.mySessionId, name: localName, score: localScore});

		// Remote players
		for (sessionId in gm.sessions) {
			if (sessionId == gm.mySessionId) {
				continue;
			}
			var name = gm.names.get(sessionId);
			if (name == null || name == "") {
				name = "???";
			}
			var score = gm.scores.exists(sessionId) ? gm.scores.get(sessionId) : 0;
			entries.push({sessionId: sessionId, name: name, score: score});
		}

		// Sort descending by score (highest first)
		entries.sort((a, b) -> b.score - a.score);

		// Determine the top score for first-place sizing
		var topScore = if (entries.length > 0) entries[0].score else 0;

		// Assign place labels (handling ties) and render rows + fish details
		var currentPlace = 1;
		var currentY = SCORE_START_Y;
		for (i in 0...entries.length) {
			if (i > 0 && entries[i].score < entries[i - 1].score) {
				currentPlace = i + 1;
			}

			var isFirst = entries[i].score == topScore;
			var fontSize = isFirst ? FIRST_PLACE_SIZE : OTHER_PLACE_SIZE;

			// Place label (1st, 2nd, 3rd, etc.) — left side
			var placeText = new FlxText();
			placeText.size = fontSize;
			placeText.alignment = FlxTextAlign.LEFT;
			placeText.text = ordinal(currentPlace);
			placeText.setPosition(SCORE_LEFT_MARGIN, currentY);
			if (isFirst) {
				placeText.color = FlxColor.YELLOW;
			}
			add(placeText);
			_scorePlaceTexts.push(placeText);

			// Name — next to the place label
			var nameText = new FlxText();
			nameText.size = fontSize;
			nameText.alignment = FlxTextAlign.LEFT;
			nameText.text = entries[i].name;
			nameText.setPosition(SCORE_LEFT_MARGIN + 50, currentY);
			if (isFirst) {
				nameText.color = FlxColor.YELLOW;
			}
			add(nameText);
			_scoreNameTexts.push(nameText);

			// Score — right side
			var scoreText = new FlxText();
			scoreText.size = fontSize;
			scoreText.alignment = FlxTextAlign.RIGHT;
			scoreText.text = formatMoney(entries[i].score);
			scoreText.setPosition(FlxG.width - SCORE_RIGHT_MARGIN - scoreText.width, currentY);
			if (isFirst) {
				scoreText.color = FlxColor.YELLOW;
			}
			add(scoreText);
			_scoreValueTexts.push(scoreText);

			currentY += SCORE_ROW_HEIGHT;

			// Fish icons for this player — left to right, icon on top, length + value below
			var fishEntries = gm.getSoldFish(roundNum, entries[i].sessionId);
			if (fishEntries.length > 0) {
				var fishX = SCORE_LEFT_MARGIN + 50;
				for (fish in fishEntries) {
					// Fish sprite
					var fishSprite = new FlxSprite();
					fishSprite.loadGraphic(AssetPaths.fish__png, true, FISH_ICON_NATIVE, FISH_ICON_NATIVE);
					fishSprite.animation.add("show", [fish.fishType]);
					fishSprite.animation.play("show");
					fishSprite.scale.set(FISH_ICON_SIZE / FISH_ICON_NATIVE, FISH_ICON_SIZE / FISH_ICON_NATIVE);
					fishSprite.updateHitbox();
					fishSprite.setPosition(fishX, currentY);
					add(fishSprite);

					// Length label below icon
					var lenText = new FlxText();
					lenText.size = FISH_LABEL_SIZE;
					lenText.color = FlxColor.fromRGB(180, 180, 180);
					lenText.text = Std.string(fish.lengthCm) + "cm";
					lenText.setPosition(fishX + FISH_ICON_SIZE / 2 - lenText.width / 2, currentY + FISH_ICON_SIZE + 1);
					add(lenText);

					// Value label below length
					var valText = new FlxText();
					valText.size = FISH_LABEL_SIZE;
					valText.color = FlxColor.fromRGB(180, 180, 180);
					valText.text = formatMoney(fish.value);
					valText.setPosition(fishX + FISH_ICON_SIZE / 2 - valText.width / 2, currentY + FISH_ICON_SIZE + 1 + FISH_LABEL_LINE_HEIGHT);
					add(valText);

					fishX += FISH_ICON_SIZE + FISH_ICON_PADDING;
				}
				currentY += FISH_BLOCK_HEIGHT;
			}
		}
	}

	private function buildKillStats():Void {
		var gm = GameManager.ME;
		var roundNum = gm.getCurrentRoundNumber();

		// Gather all session IDs
		var allSessions = [gm.mySessionId];
		for (sessionId in gm.sessions) {
			if (sessionId != gm.mySessionId) {
				allSessions.push(sessionId);
			}
		}

		var statY = 10;

		// Most Weeds
		var bestWeedId:String = null;
		var bestWeedCount = 0;
		for (sid in allSessions) {
			var count = gm.getWeedKills(roundNum, sid);
			if (count > bestWeedCount) {
				bestWeedCount = count;
				bestWeedId = sid;
			}
		}
		if (bestWeedId != null) {
			var name = gm.names.get(bestWeedId);
			if (name == null || name == "") {
				name = bestWeedId == gm.mySessionId ? "You" : "???";
			}
			var weedText = new FlxText();
			weedText.size = 10;
			weedText.color = FlxColor.fromRGB(180, 180, 180);
			weedText.text = 'Weed crusher: $name ($bestWeedCount)';
			weedText.setPosition(10, statY);
			add(weedText);
			statY += 14;
		}

		// Most Worms
		var bestWormId:String = null;
		var bestWormCount = 0;
		for (sid in allSessions) {
			var count = gm.getWormKills(roundNum, sid);
			if (count > bestWormCount) {
				bestWormCount = count;
				bestWormId = sid;
			}
		}
		if (bestWormId != null) {
			var name = gm.names.get(bestWormId);
			if (name == null || name == "") {
				name = bestWormId == gm.mySessionId ? "You" : "???";
			}
			var wormText = new FlxText();
			wormText.size = 10;
			wormText.color = FlxColor.fromRGB(180, 180, 180);
			wormText.text = 'Worm murderer: $name ($bestWormCount)';
			wormText.setPosition(10, statY);
			add(wormText);
		}
	}

	/** Format an integer as $X,XXX */
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

	/** Convert a number to its ordinal string: 1st, 2nd, 3rd, 4th, etc. */
	private static function ordinal(n:Int):String {
		var suffix = if (n % 100 >= 11 && n % 100 <= 13) {
			"th";
		} else {
			switch (n % 10) {
				case 1: "st";
				case 2: "nd";
				case 3: "rd";
				default: "th";
			};
		};
		return Std.string(n) + suffix;
	}

	override public function update(elapsed:Float):Void {
		super.update(elapsed);
		_txtTitle.x = FlxG.width / 2 - _txtTitle.width / 2;
		updateOtherPlayers();
	}

	private function updateOtherPlayers():Void {
		var gm = GameManager.ME;
		var playerLines = new Array<String>();
		for (sessionId in gm.sessions) {
			if (sessionId == gm.mySessionId) {
				continue;
			}
			var name = gm.names.get(sessionId);
			if (name == null || name == "") {
				name = "???";
			}
			var isReady = gm.readyStates.exists(sessionId) && gm.readyStates.get(sessionId);
			if (isReady) {
				playerLines.push(name + " (READY)");
			} else {
				playerLines.push(name);
			}
		}

		var newText = if (playerLines.length > 0) {
			"Other Players:\n" + playerLines.join("\n");
		} else {
			"";
		};

		if (_txtOtherPlayers.text != newText) {
			_txtOtherPlayers.text = newText;
		}
		_txtOtherPlayers.x = FlxG.width - _txtOtherPlayers.width - 10;
		_txtOtherPlayers.y = FlxG.height - _txtOtherPlayers.height - 10;
	}

	function clickReady():Void {
		if (_localReady) {
			return;
		}
		_localReady = true;
		GameManager.ME.net.sendMessage("player_ready", true);

		_btnDone.visible = false;
		_btnDone.active = false;
		_txtReady.visible = true;
		_txtReady.x = FlxG.width / 2 - _txtReady.width / 2;
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
