package states;

import entities.Player;
import entities.Player.FloatingLabel;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.addons.transition.FlxTransitionableState;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import managers.GameManager;
import schema.RoundState;
import todo.TODO;

using StringTools;
using states.FlxStateExt;

/**
 * Post-round summary: players lined up by total fish value (best on top),
 * unsold fish curving one by one into the shop (black box below everyone),
 * one player at a time from last place to first, green money labels popping
 * as each fish sells and the running totals ticking up. 5s after the last
 * sale, everyone auto-readies and the next round starts.
**/
class RoundSummaryState extends FlxTransitionableState {
	static inline var FISH_FLY_TIME:Float = 0.6; // seconds for each fish to curve into the shop
	static inline var ROW_PAUSE:Float = 0.6; // beat between players
	static inline var DONE_WAIT:Float = 5.0; // wait after everything is sold
	public static inline var PLAYER_X:Float = 130;
	public static inline var FISH_START_X:Float = 190;
	public static inline var FISH_STEP:Float = 40;
	public static inline var MONEY_RIGHT_X:Float = 120; // money text right-aligned here
	static inline var BOX_SIZE:Int = 48;

	var rows:Array<SummaryRow> = [];
	var shopBox:FlxSprite;
	var built:Bool = false;
	var activeRow:Int = -1;
	var pauseTimer:Float = 0;
	var doneTimer:Float = -1;
	var readySent:Bool = false;
	var titleText:FlxText;

	// The fish currently curving into the shop (one at a time)
	var flyingFish:FlxSprite;
	var flyT:Float = 0;
	var flyStartX:Float = 0;
	var flyStartY:Float = 0;

	override public function create():Void {
		super.create();
		bgColor = 0xff73efe8; // turquoise from title screen

		titleText = new FlxText();
		titleText.setFormat(Main.menuFont, 32, 0xff2b4e95, FlxTextAlign.CENTER);
		titleText.text = "Selling the catch...";
		add(titleText);

		// Make sure the server knows the round is over (deduped server-side).
		// If the round ended client-side (goals met), this round_update is what
		// triggers the server to sell fish and broadcast the summary payload.
		GameManager.ME.setStatus(RoundState.STATUS_POST_ROUND);
	}

	override public function update(elapsed:Float):Void {
		super.update(elapsed);
		titleText.x = FlxG.width / 2 - titleText.width / 2;
		titleText.y = 16;

		if (!built) {
			// summary payload may arrive slightly before or after the state switch
			var summary = GameManager.ME.lastRoundSummary;
			if (summary != null) {
				GameManager.ME.lastRoundSummary = null;
				buildRows(summary);
				built = true;
			}
			return;
		}

		if (pauseTimer > 0) {
			pauseTimer -= elapsed;
			return;
		}

		if (activeRow >= 0) {
			processActiveRow(elapsed);
		} else if (doneTimer >= 0) {
			doneTimer -= elapsed;
			if (doneTimer <= 0 && !readySent) {
				readySent = true;
				GameManager.ME.net.sendMessage("player_ready", true);
			}
		}
	}

	function buildRows(summary:Dynamic) {
		var players:Array<Dynamic> = summary.players;
		if (players == null || players.length == 0) {
			// nothing to show — head straight for the next round
			doneTimer = DONE_WAIT;
			return;
		}

		var entries:Array<Dynamic> = players.copy();
		// order by total fish value earned this round: first place at the top
		entries.sort((a, b) -> fishTotal(b) - fishTotal(a));

		var areaTop = 64;
		var areaBottom = FlxG.height - 90; // leave room for the shop box below everyone
		var rowH = Std.int((areaBottom - areaTop) / entries.length);
		if (rowH > 96) { rowH = 96; }
		if (rowH < 52) { rowH = 52; }

		for (i in 0...entries.length) {
			var e = entries[i];
			var centerY = areaTop + i * rowH + rowH / 2;
			rows.push(new SummaryRow(this, e, centerY));
		}

		// The shop everyone's fish curves into — bottom center, below all players.
		// Added last so fish render under it and visibly disappear inside.
		shopBox = new FlxSprite(FlxG.width / 2 - BOX_SIZE / 2, FlxG.height - BOX_SIZE - 12);
		shopBox.makeGraphic(BOX_SIZE, BOX_SIZE, FlxColor.BLACK);
		add(shopBox);

		// start with last place (bottom row)
		activeRow = rows.length - 1;
		pauseTimer = ROW_PAUSE;
	}

	static function fishTotal(e:Dynamic):Int {
		var fish:Array<Dynamic> = e.fish;
		var total = 0;
		if (fish != null) {
			for (f in fish) { total += Std.int(f.value); }
		}
		return total;
	}

	function processActiveRow(elapsed:Float) {
		var row = rows[activeRow];

		if (flyingFish == null) {
			// launch the next fish — rightmost first, the line feeds the shop
			var next:FlxSprite = null;
			var i = row.fishSprites.length;
			while (i-- > 0) {
				var f = row.fishSprites[i];
				if (f != null && f.alive) {
					next = f;
					break;
				}
			}
			if (next == null) {
				// row finished — move up a place, or start the final countdown
				activeRow--;
				if (activeRow >= 0) {
					pauseTimer = ROW_PAUSE;
				} else {
					titleText.text = "Next round soon!";
					doneTimer = DONE_WAIT;
				}
				return;
			}
			flyingFish = next;
			flyT = 0;
			flyStartX = next.x;
			flyStartY = next.y;
		}

		// Quadratic bezier: head out along the row, then swoop down into the shop
		flyT += elapsed / FISH_FLY_TIME;
		var t = flyT > 1 ? 1.0 : flyT;
		var destX = shopBox.x + BOX_SIZE / 2 - 16; // fish sprite is 32x32, top-left positioned
		var destY = shopBox.y + BOX_SIZE / 2 - 16;
		var inv = 1 - t;
		flyingFish.x = inv * inv * flyStartX + 2 * inv * t * destX + t * t * destX;
		flyingFish.y = inv * inv * flyStartY + 2 * inv * t * flyStartY + t * t * destY;
		if (flyT >= 1) {
			sellFish(row, flyingFish);
			flyingFish = null;
		}
	}

	function sellFish(row:SummaryRow, fish:FlxSprite) {
		var value = row.fishValues.get(fish);
		fish.kill();
		row.addMoney(value);

		// green money pop above the shop, floats up + fades (like the red inventory-full text)
		var label = new FloatingLabel(shopBox.x + BOX_SIZE / 2, shopBox.y - 18, "+" + formatMoney(value), 0xFF2FBF4F);
		label.size = 14;
		label.x = shopBox.x + BOX_SIZE / 2 - label.width / 2;
		add(label);
		TODO.sfx("fish_sold");
	}

	public static function formatMoney(amount:Int):String {
		var negative = amount < 0;
		var abs = negative ? -amount : amount;
		return (negative ? "-$" : "$") + Std.string(abs);
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

/** One player's line on the summary screen: money, sprite, and their fish queue. */
class SummaryRow {
	public var centerY:Float;
	public var fishSprites:Array<FlxSprite> = [];
	public var fishValues:Map<FlxSprite, Int> = new Map();

	var moneyText:FlxText;
	var money:Int;

	public function new(state:RoundSummaryState, entry:Dynamic, centerY:Float) {
		this.centerY = centerY;
		money = Std.int(entry.score);

		// static player sprite — first atlas frame of their chosen skin
		var skinIndex:Int = entry.skinIndex != null ? Std.int(entry.skinIndex) : 0;
		if (skinIndex < 0 || skinIndex >= Player.SKINS.length) { skinIndex = 0; }
		var pngPath = Player.SKINS[skinIndex].replace(".json", ".png");
		var playerSprite = new FlxSprite(RoundSummaryState.PLAYER_X, centerY - 24);
		playerSprite.loadGraphic(pngPath, true, 48, 48);
		// frame 0 is an untagged composite reference frame — frame 1 is stand_down
		playerSprite.animation.frameIndex = 1;
		state.add(playerSprite);

		// running money total, left of the player
		moneyText = new FlxText();
		moneyText.setFormat(Main.menuFont, 16, 0xff2b4e95, FlxTextAlign.RIGHT);
		state.add(moneyText);
		refreshMoney();

		// unsold fish in a straight line to the right of the player
		var fish:Array<Dynamic> = entry.fish;
		if (fish != null) {
			for (i in 0...fish.length) {
				var f = fish[i];
				var sprite = new FlxSprite(RoundSummaryState.FISH_START_X + i * RoundSummaryState.FISH_STEP, centerY - 16);
				sprite.loadGraphic(AssetPaths.fish__png, true, 32, 32);
				sprite.animation.add("show", [Std.int(f.fishType)]);
				sprite.animation.play("show");
				state.add(sprite);
				fishSprites.push(sprite);
				fishValues.set(sprite, Std.int(f.value));
			}
		}
	}

	public function addMoney(value:Int) {
		money += value;
		refreshMoney();
	}

	function refreshMoney() {
		moneyText.text = RoundSummaryState.formatMoney(money);
		moneyText.setPosition(RoundSummaryState.MONEY_RIGHT_X - moneyText.width, centerY - moneyText.height / 2);
	}
}
