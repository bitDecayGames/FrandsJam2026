package ui;

import entities.Player;
import flixel.group.FlxSpriteGroup;
import ui.font.BitmapText.PressStart;

class ScoreHUD extends FlxSpriteGroup {
	var player:Player;
	var text:PressStart;

	public function new(player:Player) {
		super();
		this.player = player;
		scrollFactor.set(0, 0);

		text = new PressStart(4, 4, 'Score: ${player.score}');
		add(text);
	}

	override public function update(elapsed:Float) {
		super.update(elapsed);
		text.text = 'Score: ${player.score}';
	}
}
