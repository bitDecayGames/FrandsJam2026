package;

import schema.GameState;

class Simulation {
	// This should run as deterministically as possible:
	// - fixed timesteps
	// - Have game 'ticks' so that we can correlate inputs well
	public var state:GameState;

	// public var options:GameOptions;

	public function init(state:GameState, options:Dynamic) {
		this.state = state;

		// TODO: Current assumption is that the backing state will be fully configured already.
		// There may be some small work to do here, but the server should have set this up already.
		// The client _may_ need to do some light processing between learning of the GameState and
		// initializing the simulation
	}

	public function update(delta:Float) {
		// accept input
		// move players
		// check overlaps
		//   - resolve collisions
		//   - do item collection / interaction
		//   - fish catch signals
		//
		//
	}
}
