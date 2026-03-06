package ui;

import managers.GameManager;
import flixel.FlxG;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;

class ScoreHUD extends FlxSpriteGroup {
	var text:FlxText;

	// Match InventoryHUD constants so we sit flush below it
	static inline var MARGIN:Int = 4;
	static inline var SLOT_SIZE:Int = 16;

	public function new() {
		super();
		scrollFactor.set(0, 0);

		text = new FlxText(0, MARGIN + SLOT_SIZE + 2, 0, "$0");
		text.size = 20;
		text.color = FlxColor.WHITE;
		text.alignment = FlxTextAlign.RIGHT;
		add(text);
	}

	override public function update(elapsed:Float) {
		super.update(elapsed);
		// var gm = GameManager.ME;
		// var score = gm.scores.exists(gm.mySessionId) ? gm.scores.get(gm.mySessionId) : 0;
		// text.text = formatMoney(score);
		// Right-align to match inventory
		text.x = FlxG.width - MARGIN - text.width;
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
}
