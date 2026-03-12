package;

import schema.GameState.P_Input;
import math.Vector;
import schema.PlayerState;

/**
 * Deterministic movement simulation — identical on client (prediction) and server (authority).
 * tickPlayer() mutates the PlayerState in place.
**/
class Simulation {
	public static inline var FIXED_STEP:Float = 1 / 20; // must match GameRoom.fixedTimeStep

	var collision:CollisionMap;

	public function new(collision:CollisionMap) {
		this.collision = collision;
	}

	/**
	 * Advance one player by one fixed step given a batch of inputs for that step.
	 * Last input in the batch wins for direction (client sends one input per frame;
	 * server may accumulate several between ticks).
	**/
	public function tickPlayer(p:PlayerState, inputs:Array<P_Input>):Void {
		if (inputs == null || inputs.length == 0) {
			return;
		}
		var vx:Float = 0;
		var vy:Float = 0;
		var lastSeq = p.lastProcessedSeq;
		for (input in inputs) {
			lastSeq = input.seq;
			var inDir = Vector.fromAngle(input.dir);
			switch (input.dir) {
				case 1:
					vx = 0;
					vy = -p.speed; // N
				case 2:
					vx = p.speed;
					vy = 0; // E
				case 3:
					vx = 0;
					vy = p.speed; // S
				case 4:
					vx = -p.speed;
					vy = 0; // W
				default:
					vx = 0;
					vy = 0;
			}
		}
		var res = collision.resolveAABB(p.x, p.y, p.width, p.height, vx * FIXED_STEP, vy * FIXED_STEP);
		p.x = res.x;
		p.y = res.y;
		p.velocityX = if (res.hitX) 0 else vx;
		p.velocityY = if (res.hitY) 0 else vy;
		p.lastProcessedSeq = lastSeq;
	}
}
