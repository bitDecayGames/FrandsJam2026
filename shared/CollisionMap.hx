package;

import Ldtk.Enum_TileTags;
import haxe.ds.Vector;

private typedef Vec2 = {x:Float, y:Float};
// Minimum Translation Vector to resolve overlap
private typedef MTV = {nx:Float, ny:Float, depth:Float};
typedef Result = {x:Float, y:Float, hitX:Bool, hitY:Bool};

/**
 * Pure-Haxe collision map derived from an LDTK level — no Flixel required.
 * Works on both client and server. Build it via `CollisionMap.fromLevel()`.
**/
class CollisionMap {
	// cellFlags bit masks
	static inline var FLAG_SOLID = 1;
	static inline var FLAG_SHALLOW = 2;
	static inline var FLAG_SWIMMABLE = 4;
	static inline var FLAG_HAS_POLYGON = 8;

	public var cols(default, null):Int;
	public var rows(default, null):Int;
	public var tileSize(default, null):Int;

	var cellFlags:Vector<Int>;
	var cellTileIds:Vector<Int>;
	var tilePolygons:Map<Int, Array<Vec2>>;

	function new(cols:Int, rows:Int, tileSize:Int) {
		this.cols = cols;
		this.rows = rows;
		this.tileSize = tileSize;
		var n = cols * rows;
		cellFlags = new Vector(n);
		cellTileIds = new Vector(n);
		tilePolygons = new Map();
		for (i in 0...n) {
			cellFlags[i] = 0;
			cellTileIds[i] = -1;
		}
	}

	/**
	 * Build a CollisionMap from a raw LDTK level plus the tile-hitboxes.json text.
	 * Pass the JSON text in from the caller so the caller can use the right
	 * platform API (#if server / #else) to load the file.
	**/
	public static function fromLevel(raw:Ldtk.Ldtk_Level, hitboxJson:String):CollisionMap {
		var layer = raw.l_Terrain;
		var gs = layer.gridSize;
		var map = new CollisionMap(layer.cWid, layer.cHei, gs);

		// Parse custom tile polygons from hitboxes JSON
		if (hitboxJson != null) {
			try {
				var data:Dynamic = haxe.Json.parse(hitboxJson);
				var tiles:Dynamic = Reflect.field(data, "tiles");
				if (tiles != null) {
					for (key in Reflect.fields(tiles)) {
						var tileId = Std.parseInt(key);
						if (tileId == null) {
							continue;
						}
						var tileData:Dynamic = Reflect.field(tiles, key);
						var polygon:Array<Dynamic> = Reflect.field(tileData, "polygon");
						if (polygon == null || polygon.length < 3) {
							continue;
						}
						var verts:Array<Vec2> = [];
						for (v in polygon) {
							var arr:Array<Dynamic> = cast v;
							verts.push({x: (cast arr[0] : Float), y: (cast arr[1] : Float)});
						}
						map.tilePolygons.set(tileId, verts);
					}
				}
			} catch (e) {}
		}

		// Grab the tileset so we can call getAllTags — same trick as LdtkTilemap.hx
		@:privateAccess
		var tileset:ldtk.Tileset = layer.untypedTileset;
		var taggedTileset:{getAllTags:(Int) -> Array<Enum_TileTags>} = cast tileset;

		// Populate per-cell flag and tileId data
		for (row in 0...layer.cHei) {
			for (col in 0...layer.cWid) {
				var idx = row * layer.cWid + col;
				if (!layer.hasAnyTileAt(col, row)) {
					continue;
				}
				var tileId = layer.getTileStackAt(col, row)[0].tileId;
				map.cellTileIds[idx] = tileId;
				var tags = taggedTileset.getAllTags(tileId);
				var flags = 0;
				for (tag in tags) {
					switch (tag) {
						case SOLID:
							flags |= FLAG_SOLID;
						case SHALLOW:
							flags |= FLAG_SHALLOW;
						case SWIMMABLE:
							flags |= FLAG_SWIMMABLE;
						case _:
					}
				}
				if (map.tilePolygons.exists(tileId)) {
					flags |= FLAG_HAS_POLYGON;
				}
				map.cellFlags[idx] = flags;
			}
		}

		return map;
	}

	inline function cellIdx(col:Int, row:Int):Int {
		return row * cols + col;
	}

	/** Returns true if the world-space point is inside a SOLID tile. **/
	public function isSolidAt(wx:Float, wy:Float):Bool {
		var col = Std.int(wx / tileSize);
		var row = Std.int(wy / tileSize);
		if (col < 0 || col >= cols || row < 0 || row >= rows) {
			return false;
		}
		return (cellFlags[cellIdx(col, row)] & FLAG_SOLID) != 0;
	}

	/** Returns true if the world-space point is inside a SHALLOW tile. **/
	public function isShallowAt(wx:Float, wy:Float):Bool {
		var col = Std.int(wx / tileSize);
		var row = Std.int(wy / tileSize);
		if (col < 0 || col >= cols || row < 0 || row >= rows) {
			return false;
		}
		return (cellFlags[cellIdx(col, row)] & FLAG_SHALLOW) != 0;
	}

	/** Returns true if the given grid cell is SWIMMABLE. **/
	public function isSwimmableAt(col:Int, row:Int):Bool {
		if (col < 0 || col >= cols || row < 0 || row >= rows) {
			return false;
		}
		return (cellFlags[cellIdx(col, row)] & FLAG_SWIMMABLE) != 0;
	}

	/** Returns true if there is any tile placed at the given grid cell. **/
	public function hasAnyTileAt(col:Int, row:Int):Bool {
		if (col < 0 || col >= cols || row < 0 || row >= rows) {
			return false;
		}
		return cellTileIds[cellIdx(col, row)] >= 0;
	}

	/**
	 * Axis-separated AABB sweep against all solid tiles.
	 *
	 * Applies dx, resolves X overlaps, then applies dy and resolves Y overlaps.
	 * Plain solid tiles use AABB-vs-AABB push. Custom polygon tiles use SAT and
	 * push the entity out along the minimum translation vector.
	 *
	 * Returns the corrected position plus hitX/hitY flags.
	**/
	public function resolveAABB(x:Float, y:Float, w:Float, h:Float, dx:Float, dy:Float):Result {
		var hitX = false;
		var hitY = false;
		var ts = tileSize;

		// --- X pass: apply dx, then push out of any solid tiles ---
		x += dx;

		var colMin = Math.floor(x / ts);
		var colMax = Math.floor((x + w - 0.001) / ts);
		var rowMin = Math.floor(y / ts);
		var rowMax = Math.floor((y + h - 0.001) / ts);

		for (row in rowMin...rowMax + 1) {
			for (col in colMin...colMax + 1) {
				if (col < 0 || col >= cols || row < 0 || row >= rows) {
					continue;
				}
				var fi = cellIdx(col, row);
				if ((cellFlags[fi] & FLAG_SOLID) == 0) {
					continue;
				}
				var tx:Float = col * ts;
				var ty:Float = row * ts;

				if ((cellFlags[fi] & FLAG_HAS_POLYGON) != 0) {
					var mtv = satAABBvsPoly(x, y, w, h, tx, ty, tilePolygons.get(cellTileIds[fi]));
					if (mtv != null) {
						x += mtv.nx * mtv.depth;
						y += mtv.ny * mtv.depth;
						if (Math.abs(mtv.nx) > 0.001) {
							hitX = true;
						}
						if (Math.abs(mtv.ny) > 0.001) {
							hitY = true;
						}
					}
				} else {
					if (aabbOverlap(x, y, w, h, tx, ty, ts, ts)) {
						if (dx > 0) {
							x = tx - w;
						} else if (dx < 0) {
							x = tx + ts;
						}
						hitX = true;
					}
				}
			}
		}

		// --- Y pass: apply dy, then push out of any solid tiles ---
		y += dy;

		colMin = Math.floor(x / ts);
		colMax = Math.floor((x + w - 0.001) / ts);
		rowMin = Math.floor(y / ts);
		rowMax = Math.floor((y + h - 0.001) / ts);

		for (row in rowMin...rowMax + 1) {
			for (col in colMin...colMax + 1) {
				if (col < 0 || col >= cols || row < 0 || row >= rows) {
					continue;
				}
				var fi = cellIdx(col, row);
				if ((cellFlags[fi] & FLAG_SOLID) == 0) {
					continue;
				}
				var tx:Float = col * ts;
				var ty:Float = row * ts;

				if ((cellFlags[fi] & FLAG_HAS_POLYGON) != 0) {
					var mtv = satAABBvsPoly(x, y, w, h, tx, ty, tilePolygons.get(cellTileIds[fi]));
					if (mtv != null) {
						x += mtv.nx * mtv.depth;
						y += mtv.ny * mtv.depth;
						if (Math.abs(mtv.nx) > 0.001) {
							hitX = true;
						}
						if (Math.abs(mtv.ny) > 0.001) {
							hitY = true;
						}
					}
				} else {
					if (aabbOverlap(x, y, w, h, tx, ty, ts, ts)) {
						if (dy > 0) {
							y = ty - h;
						} else if (dy < 0) {
							y = ty + ts;
						}
						hitY = true;
					}
				}
			}
		}

		return {
			x: x,
			y: y,
			hitX: hitX,
			hitY: hitY
		};
	}

	static inline function aabbOverlap(ax:Float, ay:Float, aw:Float, ah:Float, bx:Float, by:Float, bw:Float, bh:Float):Bool {
		return ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by;
	}

	/**
	 * SAT check between an AABB and a convex polygon tile.
	 * `localPoly` is in tile-local space (0 to tileSize); `tx/ty` is the tile's world origin.
	 * Returns an MTV pointing away from the tile toward the AABB, or null if no overlap.
	**/
	static function satAABBvsPoly(ax:Float, ay:Float, aw:Float, ah:Float, tx:Float, ty:Float, localPoly:Array<Vec2>):Null<MTV> {
		// Build world-space polygons
		var aabbVerts:Array<Vec2> = [
			{x: ax, y: ay},
			{x: ax + aw, y: ay},
			{x: ax + aw, y: ay + ah},
			{x: ax, y: ay + ah}
		];
		var tileVerts:Array<Vec2> = [for (v in localPoly) {x: tx + v.x, y: ty + v.y}];

		// Axes: AABB normals (x and y axes) + each edge normal of the tile polygon
		var axes:Array<Vec2> = [{x: 1.0, y: 0.0}, {x: 0.0, y: 1.0}];
		var n = tileVerts.length;
		for (i in 0...n) {
			var j = (i + 1) % n;
			var ex = tileVerts[j].x - tileVerts[i].x;
			var ey = tileVerts[j].y - tileVerts[i].y;
			var len = Math.sqrt(ex * ex + ey * ey);
			if (len < 0.0001) {
				continue;
			}
			// left-hand normal of the edge
			axes.push({x: -ey / len, y: ex / len});
		}

		var minDepth = Math.POSITIVE_INFINITY;
		var mtvNx = 0.0;
		var mtvNy = 0.0;

		for (axis in axes) {
			// Project AABB
			var aMin = Math.POSITIVE_INFINITY;
			var aMax = Math.NEGATIVE_INFINITY;
			for (v in aabbVerts) {
				var p = v.x * axis.x + v.y * axis.y;
				if (p < aMin) {
					aMin = p;
				}
				if (p > aMax) {
					aMax = p;
				}
			}
			// Project tile polygon
			var bMin = Math.POSITIVE_INFINITY;
			var bMax = Math.NEGATIVE_INFINITY;
			for (v in tileVerts) {
				var p = v.x * axis.x + v.y * axis.y;
				if (p < bMin) {
					bMin = p;
				}
				if (p > bMax) {
					bMax = p;
				}
			}
			var overlap = Math.min(aMax, bMax) - Math.max(aMin, bMin);
			if (overlap <= 0) {
				// separating axis found — no collision
				return null;
			}
			if (overlap < minDepth) {
				minDepth = overlap;
				mtvNx = axis.x;
				mtvNy = axis.y;
			}
		}

		// Orient MTV to point from tile center toward AABB center (so it pushes AABB away)
		var acx = ax + aw * 0.5;
		var acy = ay + ah * 0.5;
		var tcx = 0.0;
		var tcy = 0.0;
		for (v in tileVerts) {
			tcx += v.x;
			tcy += v.y;
		}
		tcx /= tileVerts.length;
		tcy /= tileVerts.length;
		if ((acx - tcx) * mtvNx + (acy - tcy) * mtvNy < 0) {
			mtvNx = -mtvNx;
			mtvNy = -mtvNy;
		}

		return {nx: mtvNx, ny: mtvNy, depth: minDepth};
	}
}
