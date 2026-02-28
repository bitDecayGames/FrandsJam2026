package rounds;

import states.PlayState;
import goals.Goal;

class Round {
	public var name:String;
	public var goals:Array<Goal> = [];
	public var allGoalsRequired:Bool = false;

	public function new(goals:Array<Goal>, name:String = "Hello World", allGoalsRequired:Bool = false) {
		this.goals = goals;
		this.name = name;
		this.allGoalsRequired = allGoalsRequired;
	}

	public function initialize(state:PlayState) {
		// do stuff here if you need to
		for (goal in goals) {
			goal.initialize(state);
		}
	}
}
