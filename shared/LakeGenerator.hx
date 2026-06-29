package;

/**
 * Procedural lake generator with smooth organic shapes and dual-ring autotiling.
 *
 * Generates three concentric zones — land, shallow water, deep water — and assigns
 * the correct tile ID from the 13-tile autotile set for each transition ring.
 *
 * Usage:
 *   var lake = LakeGenerator.generate({
 *       width: 30, height: 22,
 *       centerX: 15, centerY: 11,
 *       radiusX: 10, radiusY: 7,
 *       seed: 42, shallowWidth: 3
 *   });
 *   // lake.tiles[y][x] = tile ID (-1 for land)
 *   // lake.zones[y][x] = 0 (land), 1 (shallow), 2 (deep)
 **/
class LakeGenerator {
	// === OUTER SHORE (land → shallow) ===
	public static inline var OUTER_NW_CONVEX = 27;
	public static inline var OUTER_N_EDGE = 28;
	public static inline var OUTER_NE_CONVEX = 29;
	public static inline var OUTER_NW_CONCAVE = 25;
	public static inline var OUTER_NE_CONCAVE = 26;
	public static inline var OUTER_W_EDGE = 47;
	public static inline var OUTER_FILL = 48;
	public static inline var OUTER_E_EDGE = 49;
	public static inline var OUTER_SW_CONCAVE = 45;
	public static inline var OUTER_SE_CONCAVE = 46;
	public static inline var OUTER_SW_CONVEX = 67;
	public static inline var OUTER_S_EDGE = 68;
	public static inline var OUTER_SE_CONVEX = 69;

	// === INNER SHORE (shallow → deep) ===
	public static inline var INNER_NW_CONVEX = 20;
	public static inline var INNER_NE_CONVEX = 21;
	public static inline var INNER_NW_CONCAVE = 22;
	public static inline var INNER_N_EDGE = 23;
	public static inline var INNER_NE_CONCAVE = 24;
	public static inline var INNER_SW_CONVEX = 40;
	public static inline var INNER_SE_CONVEX = 41;
	public static inline var INNER_W_EDGE = 42;
	public static inline var INNER_FILL = 43;
	public static inline var INNER_E_EDGE = 44;
	public static inline var INNER_SW_CONCAVE = 62;
	public static inline var INNER_S_EDGE = 63;
	public static inline var INNER_SE_CONCAVE = 64;

	public static inline var GRASS_TILE = 3;
	public static inline var TILE_SIZE = 16;

	/**
	 * Generate a complete lobby level: grass background with a centered lake.
	 * Returns a LevelResult with a flat tile grid (grass for land, water tiles for lake),
	 * plus a spawn point on walkable land.
	 **/
	public static function generateLevel(widthTiles:Int, heightTiles:Int, seed:Int):LevelResult {
		// Lake centered in the level, sized proportional to level
		var cx = widthTiles / 2.0;
		var cy = heightTiles / 2.0;
		var rx = widthTiles * 0.32;
		var ry = heightTiles * 0.30;

		var lake = generate({
			width: widthTiles, height: heightTiles,
			centerX: cx, centerY: cy,
			radiusX: rx, radiusY: ry,
			seed: seed, shallowWidth: 3
		});

		// Fill land cells with grass
		var tiles = lake.tiles;
		for (i in 0...widthTiles * heightTiles) {
			if (tiles[i] < 0) {
				tiles[i] = GRASS_TILE;
			}
		}

		// Pick spawn point: walkable land tile near top-left area
		var spawnX:Float = 3 * TILE_SIZE + TILE_SIZE / 2;
		var spawnY:Float = 3 * TILE_SIZE + TILE_SIZE / 2;
		for (y in 2...heightTiles - 2) {
			for (x in 2...widthTiles - 2) {
				if (lake.zones[y * widthTiles + x] == 0) {
					spawnX = x * TILE_SIZE + TILE_SIZE / 2;
					spawnY = y * TILE_SIZE + TILE_SIZE / 2;
					// Found a walkable tile — use it
					break;
				}
			}
			if (spawnX != 3 * TILE_SIZE + TILE_SIZE / 2) { break; }
		}

		return {
			tiles: tiles,
			zones: lake.zones,
			width: widthTiles,
			height: heightTiles,
			spawnX: spawnX,
			spawnY: spawnY,
			seed: seed
		};
	}

	public static function generate(params:LakeParams):LakeResult {
		var w = params.width;
		var h = params.height;
		var cx = params.centerX;
		var cy = params.centerY;
		var rx = params.radiusX;
		var ry = params.radiusY;
		var seed = params.seed;
		var shallowWidth = params.shallowWidth;

		// 1) Noise-perturbed ellipse → water mask
		var noise1 = smoothNoise(w, h, 5, seed);
		var noise2 = smoothNoise(w, h, 3, seed + 7);

		var water = alloc2DBool(w, h);
		for (y in 0...h) {
			for (x in 0...w) {
				var dx = (x - cx) / rx;
				var dy = (y - cy) / ry;
				var dist = Math.sqrt(dx * dx + dy * dy);
				var n = noise1[y * w + x] * 0.25 + noise2[y * w + x] * 0.15;
				water[y * w + x] = dist < 1.0 + n;
			}
		}

		// 2) CA smoothing
		for (_ in 0...4) {
			water = caSmooth(water, w, h, 5, 4);
		}

		// 3) Erode for deep zone
		var deep = water.copy();
		for (_ in 0...shallowWidth) {
			deep = erode(deep, w, h);
		}
		for (_ in 0...2) {
			deep = caSmooth(deep, w, h, 5, 4);
		}

		// Build zone map
		var zones = new haxe.ds.Vector<Int>(w * h);
		for (i in 0...w * h) {
			zones[i] = if (deep[i]) 2 else if (water[i]) 1 else 0;
		}

		// 4) Clean zones
		cleanZones(zones, w, h);

		// 5) Autotile — three passes

		var tiles = new haxe.ds.Vector<Int>(w * h);
		for (i in 0...w * h) {
			tiles[i] = -1;
		}

		// Pass A1: concave corner tiles (22/24/62/64) on shallow cells with 2+ cardinal deep neighbors
		for (y in 0...h) {
			for (x in 0...w) {
				if (zones[y * w + x] != 1) { continue; }
				var nDeep = getZ(zones, x, y - 1, w, h) >= 2;
				var sDeep = getZ(zones, x, y + 1, w, h) >= 2;
				var wDeep = getZ(zones, x - 1, y, w, h) >= 2;
				var eDeep = getZ(zones, x + 1, y, w, h) >= 2;

				if (sDeep && eDeep) { tiles[y * w + x] = INNER_NW_CONCAVE; }
				else if (sDeep && wDeep) { tiles[y * w + x] = INNER_NE_CONCAVE; }
				else if (nDeep && eDeep) { tiles[y * w + x] = INNER_SW_CONCAVE; }
				else if (nDeep && wDeep) { tiles[y * w + x] = INNER_SE_CONCAVE; }
			}
		}

		// Build padded zone map: concave corners count as zone 2 for deep-side autotiling
		var padded = new haxe.ds.Vector<Int>(w * h);
		for (i in 0...w * h) {
			padded[i] = zones[i];
		}
		for (y in 0...h) {
			for (x in 0...w) {
				var t = tiles[y * w + x];
				if (t == INNER_NW_CONCAVE || t == INNER_NE_CONCAVE
					|| t == INNER_SW_CONCAVE || t == INNER_SE_CONCAVE) {
					padded[y * w + x] = 2;
				}
			}
		}

		// Pass A2: tile 103 on shallow cells adjacent to deep (but not concave corners, not outer boundary)
		for (y in 0...h) {
			for (x in 0...w) {
				if (zones[y * w + x] != 1) { continue; }
				if (tiles[y * w + x] != -1) { continue; }
				var adjLand = false;
				for (d in DIRS8) {
					if (getZ(zones, x + d.dx, y + d.dy, w, h) < 1) { adjLand = true; break; }
				}
				if (adjLand) { continue; }
				var nearInner = false;
				for (d in DIRS8) {
					if (getZ(padded, x + d.dx, y + d.dy, w, h) >= 2) { nearInner = true; break; }
				}
				if (nearInner) { tiles[y * w + x] = 103; }
			}
		}

		// Pass B: outer shore (land→shallow) + interior shallow fill
		for (y in 0...h) {
			for (x in 0...w) {
				if (zones[y * w + x] < 1 || tiles[y * w + x] != -1) { continue; }
				var onOuter = false;
				for (d in DIRS8) {
					if (getZ(zones, x + d.dx, y + d.dy, w, h) < 1) { onOuter = true; break; }
				}
				if (onOuter) {
					tiles[y * w + x] = classifyTile(zones, x, y, w, h, 1, false);
				} else if (zones[y * w + x] == 1) {
					tiles[y * w + x] = OUTER_FILL;
				}
			}
		}

		// Pass C: inner shore deep-side — uses PADDED zones so concave corners count as inside
		for (y in 0...h) {
			for (x in 0...w) {
				if (zones[y * w + x] < 2) { continue; }
				var onInner = false;
				for (d in DIRS8) {
					if (getZ(padded, x + d.dx, y + d.dy, w, h) < 2) { onInner = true; break; }
				}
				if (onInner) {
					tiles[y * w + x] = classifyTile(padded, x, y, w, h, 2, true);
				} else {
					tiles[y * w + x] = INNER_FILL;
				}
			}
		}

		// Pass D: restore convex corners adjacent to concave corners
		// The padding in pass C turned these into edges, but they fill the "bend"
		for (y in 0...h) {
			for (x in 0...w) {
				if (zones[y * w + x] < 2) { continue; }
				var orig = classifyTile(zones, x, y, w, h, 2, true);
				if (orig == INNER_NW_CONVEX || orig == INNER_NE_CONVEX
					|| orig == INNER_SW_CONVEX || orig == INNER_SE_CONVEX) {
					tiles[y * w + x] = orig;
				}
			}
		}

		return {tiles: tiles, zones: zones, width: w, height: h};
	}

	// ── Helpers ──

	static var DIRS8:Array<{dx:Int, dy:Int}> = [
		{dx: 0, dy: -1}, {dx: 0, dy: 1}, {dx: -1, dy: 0}, {dx: 1, dy: 0},
		{dx: -1, dy: -1}, {dx: 1, dy: -1}, {dx: -1, dy: 1}, {dx: 1, dy: 1}
	];

	static function getZ(zones:haxe.ds.Vector<Int>, x:Int, y:Int, w:Int, h:Int):Int {
		if (x < 0 || x >= w || y < 0 || y >= h) {
			return 0;
		}
		return zones[y * w + x];
	}

	static function classifyTile(zones:haxe.ds.Vector<Int>, x:Int, y:Int, w:Int, h:Int, level:Int, inner:Bool):Int {
		var n = getZ(zones, x, y - 1, w, h) >= level;
		var s = getZ(zones, x, y + 1, w, h) >= level;
		var ww = getZ(zones, x - 1, y, w, h) >= level;
		var e = getZ(zones, x + 1, y, w, h) >= level;
		var nw = getZ(zones, x - 1, y - 1, w, h) >= level;
		var ne = getZ(zones, x + 1, y - 1, w, h) >= level;
		var sw = getZ(zones, x - 1, y + 1, w, h) >= level;
		var se = getZ(zones, x + 1, y + 1, w, h) >= level;

		var role:TileRole = FILL;

		if (n && s && ww && e) {
			// Inner shore: concave corners are on the shallow side (pass A1).
			// Deep side diagonal-only cells stay FILL — the shallow-side concave
			// corner tile provides the visual transition at those diagonals.
			if (!inner) {
				if (!nw) { role = NW_CONCAVE; }
				else if (!ne) { role = NE_CONCAVE; }
				else if (!sw) { role = SW_CONCAVE; }
				else if (!se) { role = SE_CONCAVE; }
			}
		} else if (!n && !ww) { role = NW_CONVEX; }
		else if (!n && !e) { role = NE_CONVEX; }
		else if (!s && !ww) { role = SW_CONVEX; }
		else if (!s && !e) { role = SE_CONVEX; }
		else if (!n) { role = N_EDGE; }
		else if (!s) { role = S_EDGE; }
		else if (!ww) { role = W_EDGE; }
		else if (!e) { role = E_EDGE; }

		return if (inner) innerTile(role) else outerTile(role);
	}

	static function outerTile(role:TileRole):Int {
		return switch (role) {
			case NW_CONVEX: OUTER_NW_CONVEX;
			case N_EDGE: OUTER_N_EDGE;
			case NE_CONVEX: OUTER_NE_CONVEX;
			case NW_CONCAVE: OUTER_NW_CONCAVE;
			case NE_CONCAVE: OUTER_NE_CONCAVE;
			case W_EDGE: OUTER_W_EDGE;
			case FILL: OUTER_FILL;
			case E_EDGE: OUTER_E_EDGE;
			case SW_CONCAVE: OUTER_SW_CONCAVE;
			case SE_CONCAVE: OUTER_SE_CONCAVE;
			case SW_CONVEX: OUTER_SW_CONVEX;
			case S_EDGE: OUTER_S_EDGE;
			case SE_CONVEX: OUTER_SE_CONVEX;
		};
	}

	static function innerTile(role:TileRole):Int {
		return switch (role) {
			case NW_CONVEX: INNER_NW_CONVEX;
			case NE_CONVEX: INNER_NE_CONVEX;
			case NW_CONCAVE: INNER_NW_CONCAVE;
			case N_EDGE: INNER_N_EDGE;
			case NE_CONCAVE: INNER_NE_CONCAVE;
			case SW_CONVEX: INNER_SW_CONVEX;
			case SE_CONVEX: INNER_SE_CONVEX;
			case W_EDGE: INNER_W_EDGE;
			case FILL: INNER_FILL;
			case E_EDGE: INNER_E_EDGE;
			case SW_CONCAVE: INNER_SW_CONCAVE;
			case S_EDGE: INNER_S_EDGE;
			case SE_CONCAVE: INNER_SE_CONCAVE;
		};
	}

	// ── Noise ──

	static function hashFloat(x:Int, y:Int, seed:Int):Float {
		var h:Int = (x * 374761393 + y * 668265263 + seed * 1274126177);
		h = ((h >> 16) ^ h) * 0x45d9f3b;
		h = ((h >> 16) ^ h) * 0x45d9f3b;
		h = (h >> 16) ^ h;
		return (h & 0xFFFF) / 65536.0;
	}

	static function smoothNoise(w:Int, h:Int, scale:Int, seed:Int):haxe.ds.Vector<Float> {
		var gw = Std.int(w / scale) + 2;
		var gh = Std.int(h / scale) + 2;
		var grid = new haxe.ds.Vector<Float>(gw * gh);
		for (gy in 0...gh) {
			for (gx in 0...gw) {
				grid[gy * gw + gx] = hashFloat(gx, gy, seed);
			}
		}

		var result = new haxe.ds.Vector<Float>(w * h);
		var minV:Float = 1.0;
		var maxV:Float = 0.0;

		for (y in 0...h) {
			for (x in 0...w) {
				var fx:Float = x / scale;
				var fy:Float = y / scale;
				var ix = Std.int(fx);
				var iy = Std.int(fy);
				var tx = fx - ix;
				var ty = fy - iy;
				tx = tx * tx * (3 - 2 * tx);
				ty = ty * ty * (3 - 2 * ty);
				var n00 = grid[iy * gw + ix];
				var n10 = grid[iy * gw + ix + 1];
				var n01 = grid[(iy + 1) * gw + ix];
				var n11 = grid[(iy + 1) * gw + ix + 1];
				var v = n00 * (1 - tx) * (1 - ty) + n10 * tx * (1 - ty) + n01 * (1 - tx) * ty + n11 * tx * ty;
				result[y * w + x] = v;
				if (v < minV) { minV = v; }
				if (v > maxV) { maxV = v; }
			}
		}

		var rng = if (maxV > minV) maxV - minV else 1.0;
		for (i in 0...w * h) {
			result[i] = (result[i] - minV) / rng * 2 - 1;
		}
		return result;
	}

	// ── Cellular Automata ──

	static function alloc2DBool(w:Int, h:Int):haxe.ds.Vector<Bool> {
		var v = new haxe.ds.Vector<Bool>(w * h);
		for (i in 0...w * h) {
			v[i] = false;
		}
		return v;
	}

	static function caSmooth(grid:haxe.ds.Vector<Bool>, w:Int, h:Int, birth:Int, survive:Int):haxe.ds.Vector<Bool> {
		var out = alloc2DBool(w, h);
		for (y in 0...h) {
			for (x in 0...w) {
				var count = 0;
				for (dy in -1...2) {
					for (dx in -1...2) {
						if (dx == 0 && dy == 0) { continue; }
						var nx = x + dx;
						var ny = y + dy;
						if (nx >= 0 && nx < w && ny >= 0 && ny < h && grid[ny * w + nx]) {
							count++;
						}
					}
				}
				var alive = grid[y * w + x];
				out[y * w + x] = count >= (if (alive) survive else birth);
			}
		}
		return out;
	}

	static function erode(grid:haxe.ds.Vector<Bool>, w:Int, h:Int):haxe.ds.Vector<Bool> {
		var out = alloc2DBool(w, h);
		for (y in 0...h) {
			for (x in 0...w) {
				if (!grid[y * w + x]) { continue; }
				if (x <= 0 || y <= 0 || x >= w - 1 || y >= h - 1) { continue; }
				if (grid[(y - 1) * w + x] && grid[(y + 1) * w + x] && grid[y * w + x - 1] && grid[y * w + x + 1]) {
					out[y * w + x] = true;
				}
			}
		}
		return out;
	}

	static function cleanZones(zones:haxe.ds.Vector<Int>, w:Int, h:Int):Void {
		var changed = true;
		while (changed) {
			changed = false;
			for (y in 0...h) {
				for (x in 0...w) {
					var z = zones[y * w + x];
					if (z == 0) { continue; }
					var count = 0;
					for (d in [{dx: 0, dy: -1}, {dx: 0, dy: 1}, {dx: -1, dy: 0}, {dx: 1, dy: 0}]) {
						if (getZ(zones, x + d.dx, y + d.dy, w, h) >= z) {
							count++;
						}
					}
					if (count < 2) {
						zones[y * w + x] = z - 1;
						changed = true;
					}
				}
			}
		}

		// Remove diagonal-only connections (checkerboard)
		changed = true;
		while (changed) {
			changed = false;
			for (y in 0...h) {
				for (x in 0...w) {
					var z = zones[y * w + x];
					if (z == 0) { continue; }
					var bad = false;
					for (dxy in [{dx: -1, dy: -1}, {dx: 1, dy: -1}, {dx: -1, dy: 1}, {dx: 1, dy: 1}]) {
						if (getZ(zones, x + dxy.dx, y + dxy.dy, w, h) < z) { continue; }
						var c1 = getZ(zones, x, y + dxy.dy, w, h);
						var c2 = getZ(zones, x + dxy.dx, y, w, h);
						if (c1 < z && c2 < z) {
							bad = true;
							break;
						}
					}
					if (bad) {
						zones[y * w + x] = z - 1;
						changed = true;
					}
				}
			}
		}
	}
}

typedef LakeParams = {
	width:Int,
	height:Int,
	centerX:Float,
	centerY:Float,
	radiusX:Float,
	radiusY:Float,
	seed:Int,
	shallowWidth:Int,
};

typedef LakeResult = {
	tiles:haxe.ds.Vector<Int>,
	zones:haxe.ds.Vector<Int>,
	width:Int,
	height:Int,
};

typedef LevelResult = {
	tiles:haxe.ds.Vector<Int>,
	zones:haxe.ds.Vector<Int>,
	width:Int,
	height:Int,
	spawnX:Float,
	spawnY:Float,
	seed:Int,
};

enum TileRole {
	NW_CONVEX;
	N_EDGE;
	NE_CONVEX;
	NW_CONCAVE;
	NE_CONCAVE;
	W_EDGE;
	FILL;
	E_EDGE;
	SW_CONCAVE;
	SE_CONCAVE;
	SW_CONVEX;
	S_EDGE;
	SE_CONVEX;
}
