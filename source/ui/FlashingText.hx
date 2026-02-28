package ui;

import flixel.FlxG;
import flixel.text.FlxText;

class FlashingText extends FlxText {
	var flashRate:Float;
	var duration:Float;
	var elapsed:Float = 0;
	var flashing:Bool = false;

	public function new(text:String, flashRate:Float, duration:Float, size:Int = 32) {
		super(0, 0, FlxG.width, text, size);
		this.flashRate = flashRate;
		this.duration = duration;
		alignment = CENTER;
		screenCenter();
		scrollFactor.set(0, 0);
		visible = false;
	}

	public function start() {
		flashing = true;
		elapsed = 0;
		visible = true;
	}

	public function isFlashing():Bool {
		return flashing;
	}

	override public function update(delta:Float) {
		super.update(delta);

		if (!flashing)
			return;

		elapsed += delta;

		if (elapsed >= duration) {
			flashing = false;
			visible = false;
			return;
		}

		visible = (Math.floor(elapsed / flashRate) % 2 == 0);
	}
}
