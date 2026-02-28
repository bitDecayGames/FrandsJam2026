package entities;

import flixel.FlxSprite;
import flixel.util.FlxColor;
import events.EventBus;
import events.gen.Event;

class Fish extends FlxSprite {
	public var id:String;
	public var hp:Int = 10;
	public var isLiving:Bool = true;

	public function new(X:Float, Y:Float) {
		super(X, Y);
		makeGraphic(16, 16, FlxColor.GREEN);
	}

	public function hit(playerId:String) {
		hp -= 1;
		if (hp <= 0) {
			isLiving = false;
			EventBus.fire(new FishCaught(id, playerId, x, y));
			QLog.notice('Fish caught at ($x, $y)');
			kill();
		}
	}
}
