package utils;

class Cooldowns {
	var cds:Map<String, Cd>;

	public function new() {
		cds = new Map<String, Cd>();
		// TODO: Implement pooling
	}

	// Sets a new cooldown, overwriting existing cooldown one if it exists
	public function set(key:String, time:Float, ?cb:() -> Void) {
		var cd = new Cd();
		cd.set(key, time, cb);

		if (cds.exists(key)) {
			// TODO: Return existing cd to pool
		}

		cds.set(key, cd);
	}

	// Resets an existing cooldown with a new time if it exists, creating a new cd otherwise.
	// This will preserve existing cb if a new one is not passed in
	public function reset(key:String, time:Float, overwrite:OverwriteStyle = ALWAYS, ?cb:() -> Void) {
		var cd = cds.get(key);
		if (cd == null) {
			// TODO: Get from pool
			cd = new Cd();
		}

		var overwritten = false;
		time = switch (overwrite) {
			case ALWAYS:
				overwritten = true;
				time;
			case IF_GREATER:
				if (time > cd.remaining) {
					overwritten = true;
					time;
				} else {
					cd.remaining;
				}
			case IF_LESS:
				if (time < cd.remaining) {
					overwritten = true;
					time;
				} else {
					cd.remaining;
				}
		}

		cd.set(key, overwritten ? time : cd.initial, cd.onComplete ?? cb);
		cd.remaining = time;

		cds.set(key, cd);
	}

	// Returns true if the cooldown key exists and is active
	public function has(key:String):Bool {
		return cds.exists(key);
	}

	// Returns the remainder of a cooldown if it exists and is active, zero otherwise
	public function get(key:String):Float {
		if (!has(key)) {
			return 0;
		}

		return cds.get(key).remaining;
	}

	// Internal helper to get Cd objects out of our map. Assumes caller knows if it should
	// exist or not
	private function getCd(key:String):Cd {
		return cds.get(key);
	}

	// Removes a cooldown if it exists
	public function remove(key:String):Bool {
		return cds.remove(key);
	}

	// Returns the progress of the cooldown as a percentage if it exists, zero otherwise
	public function getProgress(key:String):Float {
		if (!has(key)) {
			return 0;
		}

		var cd = getCd(key);
		return (cd.initial - cd.remaining) / cd.initial;
	}

	// returns the remaining time of the cooldown as a percentage if it exists, zero otherwise
	public function getRemaining(key:String):Float {
		if (!has(key)) {
			return 0;
		}

		var cd = getCd(key);
		return 1 - ((cd.initial - cd.remaining) / cd.initial);
	}

	public function update(elapsed:Float) {
		var keys = cds.keys();
		for (key in keys) {
			var cd = getCd(key);
			cd.remaining -= elapsed;
			if (cd.remaining <= 0) {
				if (cd.onComplete != null) {
					cd.onComplete();
				}
				// TODO: Return cd to pool
				// pool.put(cd);
				cds.remove(key);
			}
		}
	}
}

private class Cd {
	public var key:String;
	public var initial:Float;
	public var remaining:Float;
	public var onComplete:() -> Void;

	public function new() {}

	public function set(key:String, time:Float, ?cb:() -> Void) {
		this.key = key;
		initial = time;
		remaining = time;
		onComplete = cb;
	}

	// TODO: For pooling, this is to allow reseting
	public function destroy() {
		key = "";
		initial = 0;
		remaining = 0;
		onComplete = null;
	}
}

enum OverwriteStyle {
	ALWAYS;
	IF_GREATER;
	IF_LESS;
}
