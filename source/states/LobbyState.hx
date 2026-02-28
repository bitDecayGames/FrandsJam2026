package states;

import managers.GameManager;
import flixel.addons.transition.FlxTransitionableState;

using states.FlxStateExt;

class LobbyState extends FlxTransitionableState {
	override public function create():Void {
		super.create();
		GameManager.ME.start();
	}
}
