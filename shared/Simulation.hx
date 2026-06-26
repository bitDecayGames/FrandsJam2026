package;

import schema.GameState.P_Input;
import math.Vector;
import schema.PlayerState;

/**
 * Deterministic movement simulation — identical on client (prediction) and server (authority).
 * Only handles movement + collision. Cast/throw/gameplay use server-validated messages.
 * tickPlayer() mutates the PlayerState in place.
**/
class Simulation {
	public static inline var FIXED_STEP:Float = 1 / 20.0; // must match GameRoom.fixedTimeStep

	var collision:CollisionMap;

	public function new(collision:CollisionMap) {
		this.collision = collision;
	}

	/**
	 * Advance one player by processing a batch of inputs.
	 * Only handles movement — direction + collision resolution.
	**/
	public function tickPlayer(p:PlayerState, inputs:Array<P_Input>, elapsed:Float = 0):Void {
		if (inputs == null || inputs.length == 0) {
			return;
		}
		var vx:Float = 0;
		var vy:Float = 0;
		var lastSeq = p.lastProcessedSeq;

		for (input in inputs) {
			lastSeq = input.seq;

			// movement only when not frozen by cast/throw
			if (!p.frozen) {
				if (input.dir != -1) {
					var inDir = Vector.fromAngle(input.dir);
					vx = inDir.x * p.speed;
					vy = inDir.y * p.speed;
					p.facing = dirToFacing(input.dir);
				}
			}
		}

		// block both SOLID and SHALLOW tiles (shallow water acts as a wall)
		var blockFlags = CollisionMap.FLAG_SOLID | CollisionMap.FLAG_SHALLOW;
		var res = collision.resolveAABB(p.x, p.y, p.width, p.height, vx * elapsed, vy * elapsed, blockFlags);
		p.x = res.x;
		p.y = res.y;
		p.velocityX = if (res.hitX) 0 else vx;
		p.velocityY = if (res.hitY) 0 else vy;
		p.lastProcessedSeq = lastSeq;
	}

	/** Convert a 0-359 degree direction to a FACING constant. */
	static function dirToFacing(dir:Int):Int {
		if (dir < 0) {
			return PlayerState.FACING_DOWN;
		}
		if (dir >= 315 || dir < 45) {
			return PlayerState.FACING_UP;
		}
		if (dir >= 45 && dir < 135) {
			return PlayerState.FACING_RIGHT;
		}
		if (dir >= 135 && dir < 225) {
			return PlayerState.FACING_DOWN;
		}
		return PlayerState.FACING_LEFT;
	}

	/**
	 * Picks `count` random walkable tile positions.
	 * TODO: Implement real spawn logic from LDTK data.
	 */
	public function getRandomSpawnPoints(count:Int):Array<Vector> {
		return [for (i in 0...count) new Vector(20 + i * 30, 20 + i * 30)];
	}
}
