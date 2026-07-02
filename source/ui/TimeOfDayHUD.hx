package ui;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;

/**
 * Sundial clock at the top-left of the screen plus Day/Night buttons
 * that fast-forward the server clock (noon / midnight).
**/
class TimeOfDayHUD extends FlxSpriteGroup {
	static inline var MARGIN:Int = 4;
	static inline var DIAL_SIZE:Int = 30;
	static inline var BTN_W:Int = 44;
	static inline var BTN_H:Int = 12;

	/** Called with the target hour when a button is clicked */
	public var onSetTime:Float->Void;

	var pointer:FlxSprite;
	var timeText:FlxText;
	var periodText:FlxText;
	var buttons:Array<{x:Float, y:Float, hour:Float}> = [];

	public function new() {
		super();
		scrollFactor.set(0, 0);

		// Sundial face
		var dial = new FlxSprite(MARGIN, MARGIN);
		dial.makeGraphic(DIAL_SIZE, DIAL_SIZE, FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawCircle(dial, DIAL_SIZE / 2, DIAL_SIZE / 2, DIAL_SIZE / 2 - 1, FlxColor.fromRGB(40, 40, 40, 200));
		FlxSpriteUtil.drawCircle(dial, DIAL_SIZE / 2, DIAL_SIZE / 2, DIAL_SIZE / 2 - 1, FlxColor.TRANSPARENT, {color: FlxColor.WHITE, thickness: 1});
		// noon tick at the top, midnight tick at the bottom
		FlxSpriteUtil.drawRect(dial, DIAL_SIZE / 2 - 1, 1, 2, 3, FlxColor.YELLOW);
		FlxSpriteUtil.drawRect(dial, DIAL_SIZE / 2 - 1, DIAL_SIZE - 4, 2, 3, FlxColor.fromRGB(120, 140, 255));
		add(dial);

		// Rotating hand — origin at its base, base pinned to the dial center
		var cx = MARGIN + DIAL_SIZE / 2;
		var cy = MARGIN + DIAL_SIZE / 2;
		pointer = new FlxSprite(cx - 1, cy - 10);
		pointer.makeGraphic(2, 11, FlxColor.WHITE);
		pointer.origin.set(1, 10);
		add(pointer);

		timeText = new FlxText(MARGIN + DIAL_SIZE + 4, MARGIN + 2, 0, "12:00");
		timeText.size = 8;
		add(timeText);

		periodText = new FlxText(MARGIN + DIAL_SIZE + 4, MARGIN + 13, 0, "Noon");
		periodText.size = 8;
		periodText.color = FlxColor.fromRGB(255, 230, 150);
		add(periodText);

		// Fast-forward buttons — 2x2 grid under the dial
		var defs = [
			{label: "Morning", hour: 7.5},
			{label: "Day", hour: 12.0},
			{label: "Evening", hour: 19.0},
			{label: "Night", hour: 0.0}
		];
		for (i in 0...defs.length) {
			var bx = MARGIN + (i % 2) * (BTN_W + 3);
			var by = MARGIN + DIAL_SIZE + 4 + Std.int(i / 2) * (BTN_H + 3);
			makeButton(bx, by, defs[i].label);
			buttons.push({x: bx, y: by, hour: defs[i].hour});
		}

		setHour(12.0);
	}

	function makeButton(bx:Float, by:Float, label:String) {
		var bg = new FlxSprite(bx, by);
		bg.makeGraphic(BTN_W, BTN_H, FlxColor.fromRGB(40, 40, 40, 200));
		add(bg);
		var txt = new FlxText(bx, by + 1, BTN_W, label);
		txt.size = 8;
		txt.alignment = FlxTextAlign.CENTER;
		add(txt);
	}

	override public function update(elapsed:Float) {
		super.update(elapsed);
		if (FlxG.mouse.justPressed && onSetTime != null) {
			var pos = FlxG.mouse.getScreenPosition();
			for (btn in buttons) {
				if (pos.x >= btn.x && pos.x < btn.x + BTN_W && pos.y >= btn.y && pos.y < btn.y + BTN_H) {
					onSetTime(btn.hour);
					break;
				}
			}
			pos.put();
		}
	}

	public function setHour(hour:Float) {
		// noon points straight up, midnight straight down
		pointer.angle = hour * 15 - 180;
		var h = Std.int(hour);
		var m = Std.int((hour - h) * 60);
		timeText.text = (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
		periodText.text = periodName(hour);
	}

	static function periodName(hour:Float):String {
		if (hour < 5 || hour >= 21) {
			return "Night";
		}
		if (hour < 11) {
			return "Morning";
		}
		if (hour < 14) {
			return "Noon";
		}
		if (hour < 17) {
			return "Afternoon";
		}
		return "Evening";
	}
}
