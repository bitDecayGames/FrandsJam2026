package states;

import config.Configure;
import managers.GameManager;
import flixel.addons.transition.FlxTransitionableState;

using states.FlxStateExt;

class AutoPlayState extends FlxTransitionableState {
	override public function create():Void {
		super.create();
		#if !local
		GameManager.ME.net.connect(Configure.getServerURL(), Configure.getServerPort());
		#end
		GameManager.ME.start();
	}
}
