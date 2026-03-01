package entities;

import net.NetworkManager;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.math.FlxPoint;
import flixel.group.FlxGroup.FlxTypedGroup;
import levels.ldtk.Level;

class FishSpawner extends FlxTypedGroup<WaterFish> {
	static inline var SEPARATION_DIST:Float = 20;

	var nextFishID:Int = 1;

	public var fishMap = new Map<String, WaterFish>();

	var net:NetworkManager;

	var catchCallback:(String, String) -> Void;

	public function new(onCatch:(String, String) -> Void) {
		super();
		catchCallback = onCatch;
	}

	public function setNet(net:NetworkManager) {
		this.net = net;
	}

	override public function update(elapsed:Float) {
		super.update(elapsed);

		// Keep fish spread out — if two get too close, one flees
		var members = this.members;
		for (i in 0...members.length) {
			var a = members[i];
			if (a == null || !a.alive)
				continue;
			for (j in (i + 1)...members.length) {
				var b = members[j];
				if (b == null || !b.alive)
					continue;
				var dx = a.x - b.x;
				var dy = a.y - b.y;
				if (dx * dx + dy * dy < SEPARATION_DIST * SEPARATION_DIST) {
					a.fleeFrom(b.x, b.y);
					b.fleeFrom(a.x, a.y);
				}
			}
		}
	}

	public function spawn(level:Level) {
		var layer = level.fishSpawnerLayer;
		var w = layer.cWid;
		var h = layer.cHei;
		var grid = layer.gridSize;
		var visited = new Array<Bool>();
		visited.resize(w * h);
		for (i in 0...visited.length) {
			visited[i] = false;
		}

		// Collect FishSpawner entities keyed by their grid index
		var spawnerCounts = new Map<Int, Int>();
		for (spawner in level.raw.l_Objects.all_FishSpawner) {
			var idx = spawner.cx + spawner.cy * w;
			spawnerCounts.set(idx, spawner.f_numFish);
		}

		// Flood-fill to find connected groups of value-1 tiles in the FishSpawner IntGrid
		for (sy in 0...h) {
			for (sx in 0...w) {
				var startIdx = sx + sy * w;
				if (visited[startIdx] || layer.getInt(sx, sy) != 1)
					continue;

				var body = new Array<Int>();
				var stack = [startIdx];
				while (stack.length > 0) {
					var idx = stack.pop();
					if (idx < 0 || idx >= w * h || visited[idx])
						continue;
					var cx = idx % w;
					var cy = Std.int(idx / w);
					if (layer.getInt(cx, cy) != 1)
						continue;
					visited[idx] = true;
					body.push(idx);
					if (cx > 0)
						stack.push(idx - 1);
					if (cx < w - 1)
						stack.push(idx + 1);
					if (cy > 0)
						stack.push(idx - w);
					if (cy < h - 1)
						stack.push(idx + w);
				}

				// Find the FishSpawner entity in this body to get numFish
				var numFish = 0;
				for (idx in body) {
					if (spawnerCounts.exists(idx)) {
						numFish = spawnerCounts.get(idx);
						break;
					}
				}

				if (numFish <= 0)
					continue;

				// Build shared water tile pixel positions for this body
				var waterTiles = new Array<FlxPoint>();
				for (idx in body) {
					var cx = idx % w;
					var cy = Std.int(idx / w);
					waterTiles.push(FlxPoint.weak(cx * grid + 2, cy * grid + 2));
				}

				for (_ in 0...numFish) {
					var fid = '${nextFishID++}';
					var tile = waterTiles[FlxG.random.int(0, waterTiles.length - 1)];
					if (net != null) {
						var data:Dynamic = {id: fid, x: tile.x, y: tile.y};
						QLog.notice('sending fish_spawn message: $data');
						net.sendMessage("fish_spawn", data);
					}
					var fish = new WaterFish(fid, tile.x, tile.y, waterTiles);
					fishMap.set(fid, fish);
					fish.onCatch = catchCallback;
					add(fish);
				}
			}
		}
	}

	public function scareFish(splashX:Float, splashY:Float, radius:Float = 80) {
		for (fish in members) {
			if (fish == null || !fish.alive)
				continue;
			var dx = fish.x - splashX;
			var dy = fish.y - splashY;
			if (dx * dx + dy * dy < radius * radius) {
				fish.scare(splashX, splashY);
			}
		}
	}

	public function setBobbers(bobbers:Map<String, FlxSprite>) {
		for (fish in members) {
			if (fish == null || !fish.alive)
				continue;
			fish.bobbers = bobbers;
		}
	}

	public function clearAll() {
		for (f in this) {
			f.destroy();
		}
		clear();
	}
}
