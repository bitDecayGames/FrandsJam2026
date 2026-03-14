package;

import schema.GameState.P_Input;
import math.Vector;
import schema.PlayerState;

/**
 * Deterministic movement simulation — identical on client (prediction) and server (authority).
 * tickPlayer() mutates the PlayerState in place.
**/
class Simulation {
	public static inline var FIXED_STEP:Float = 1 / 20.0; // must match GameRoom.fixedTimeStep

	var collision:CollisionMap;

	public function new(collision:CollisionMap) {
		this.collision = collision;
	}

	/**
	 * Advance one player by one fixed step given a batch of inputs for that step.
	 * Last input in the batch wins for direction (client sends one input per frame;
	 * server may accumulate several between ticks).
	**/
	public function tickPlayer(p:PlayerState, inputs:Array<P_Input>, elapsed:Float = 0):Void {
		if (inputs == null || inputs.length == 0) {
			return;
		}
		var vx:Float = 0;
		var vy:Float = 0;
		var lastSeq = p.lastProcessedSeq;
		p.actionIntent = PlayerState.ACTION_IDLE;
		for (input in inputs) {
			lastSeq = input.seq;
			if (input.dir == -1) {
				// no input direction provided
				continue;
			}
			var inDir = Vector.fromAngle(input.dir);
			vx = inDir.x * p.speed;
			vy = inDir.y * p.speed;
			p.actionIntent = PlayerState.ACTION_RUN;
		}
		var res = collision.resolveAABB(p.x, p.y, p.width, p.height, vx * elapsed, vy * elapsed);
		p.x = res.x;
		p.y = res.y;
		p.velocityX = if (res.hitX) 0 else vx;
		p.velocityY = if (res.hitY) 0 else vy;
		p.lastProcessedSeq = lastSeq;

		updatePlayerState(p);
	}

	function updatePlayerState(p:PlayerState) {
		if (p.actionIntent == PlayerState.ACTION_RUN) {
			if (p.velocityX != 0 && p.velocityY != 0) {
				p.actionState = PlayerState.ACTION_RUN;
			} else {
				p.actionState = PlayerState.ACTION_IDLE;
			}
		} else {
			p.actionState = PlayerState.ACTION_IDLE;
		}
	}

	/**
	 * Picks `count` random walkable tile positions (not water, not shallow, not solid).
	 * Returns pixel positions at tile centers.
	 */
	public function getRandomSpawnPoints(count:Int):Array<Vector> {
		return [
			for (i in 0...count) {
				new Vector(20 + i * 30, 20 + i * 30);
			}
		];

		// TODO: Implement real spawn logic
		// var layer = waterGrid;
		// var cols = layer.cWid;
		// var rows = layer.cHei;
		// var gridSize = layer.gridSize;

		// // build candidate list of walkable tiles
		// var candidates = new Array<Int>();
		// for (cy in 0...rows) {
		// 	for (cx in 0...cols) {
		// 		// skip water tiles
		// 		if (layer.getInt(cx, cy) == 1) {
		// 			continue;
		// 		}
		// 		var tileX = cx * gridSize + gridSize / 2;
		// 		var tileY = cy * gridSize + gridSize / 2;
		// 		// skip shallow and solid tiles
		// 		if (terrainLayer.isShallowAt(tileX, tileY)) {
		// 			continue;
		// 		}
		// 		if (terrainLayer.isSolidAt(tileX, tileY)) {
		// 			continue;
		// 		}
		// 		candidates.push(cx + cy * cols);
		// 	}
		// }

		// if (candidates.length == 0) {
		// 	QLog.error("Level: no walkable tiles found for spawn points, falling back to LDTK spawn");
		// 	return [FlxPoint.get(spawnPoint.x, spawnPoint.y)];
		// }

		// var results = new Array<FlxPoint>();
		// for (_ in 0...count) {
		// 	if (candidates.length == 0) {
		// 		break;
		// 	}
		// 	var idx = FlxG.random.int(0, candidates.length - 1);
		// 	var linearIdx = candidates[idx];
		// 	// remove to avoid duplicates
		// 	candidates[idx] = candidates[candidates.length - 1];
		// 	candidates.pop();

		// 	var cx = linearIdx % cols;
		// 	var cy = Std.int(linearIdx / cols);
		// 	results.push(FlxPoint.get(cx * gridSize + gridSize / 2, cy * gridSize + gridSize / 2));
		// }

		// return results;
	}
}
