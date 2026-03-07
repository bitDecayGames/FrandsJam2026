package levels.ldtk;

import entities.CameraTransition;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxRect;
import flixel.math.FlxPoint;
import Ldtk;
import Ldtk.LdtkProject;

using levels.ldtk.LdtkUtils;
using FmodEnums;

/**
 * The middle layer between LDTK project and game code. This class
 * should do all of the major parsing of project data into flixel
 * types and basic game objects.
**/
class Level {
	public static var project = new LdtkProject();

	/**
	 * The raw level from the project. Available to get any needed
	 * one-off values out of the level for special use-cases
	**/
	public var raw:Ldtk.Ldtk_Level;

	public var songEvent:String = "";

	public var terrainLayer:BDTilemap;
	public var waterGrid:WaterGrid;
	public var spawnPoint:FlxPoint = FlxPoint.get();
	public var tileColliders:FlxTypedGroup<FlxSprite>;
	public var shallowTileColliders:FlxTypedGroup<FlxSprite>;

	public var camZones:Map<String, FlxRect>;
	public var camTransitions:Array<CameraTransition>;

	public function new(nameOrIID:String) {
		raw = project.getLevel(nameOrIID);

		if (raw.f_Song != null) {
			songEvent = raw.f_Song.path();
		}

		terrainLayer = new BDTilemap();
		terrainLayer.loadLdtk(raw.l_Terrain);

		shallowTileColliders = new FlxTypedGroup<FlxSprite>();
		tileColliders = loadTileHitboxes(raw.l_Terrain);

		waterGrid = buildWaterGrid(raw.l_Terrain);

		if (raw.l_Objects.all_Spawn.length == 0) {
			throw('no spawn found in level ${nameOrIID}');
		}

		var sp = raw.l_Objects.all_Spawn[0];
		spawnPoint.set(sp.pixelX, sp.pixelY);

		var test:Ldtk.Entity_Spawn = null;

		parseCameraZones(raw.l_Objects.all_CameraZone);
		parseCameraTransitions(raw.l_Objects.all_CameraTransition);
	}

	function buildWaterGrid(terrainLdtk:ldtk.Layer_Tiles):WaterGrid {
		var w = terrainLdtk.cWid;
		var h = terrainLdtk.cHei;
		var grid = new WaterGrid(w, h, terrainLdtk.gridSize);
		for (row in 0...h) {
			for (col in 0...w) {
				if (terrainLayer.isSwimmableAt(col, row)) {
					grid.setWater(col, row);
				}
			}
		}
		return grid;
	}

	function loadTileHitboxes(terrainLdtk:ldtk.Layer_Tiles):FlxTypedGroup<FlxSprite> {
		var group = new FlxTypedGroup<FlxSprite>();

		var jsonText:String = null;
		try {
			jsonText = openfl.Assets.getText("assets/data/tile-hitboxes.json");
		} catch (e) {
			return group;
		}

		if (jsonText == null) {
			return group;
		}

		var data:Dynamic = null;
		try {
			data = haxe.Json.parse(jsonText);
		} catch (e) {
			return group;
		}

		var tiles:Dynamic = Reflect.field(data, "tiles");
		if (tiles == null) {
			return group;
		}

		// Build set of tile IDs with custom hitboxes and tell BDTilemap
		var customIds = new Map<Int, Bool>();
		for (key in Reflect.fields(tiles)) {
			customIds.set(Std.parseInt(key), true);
		}
		terrainLayer.setCustomHitboxTileIds(customIds);

		// Iterate placed tiles and create collision strips from polygon scanlines
		var gs = terrainLdtk.gridSize;
		for (cy in 0...terrainLdtk.cHei) {
			for (cx in 0...terrainLdtk.cWid) {
				if (!terrainLdtk.hasAnyTileAt(cx, cy)) {
					continue;
				}

				var tileId = terrainLdtk.getTileStackAt(cx, cy)[0].tileId;
				var tileIdStr = Std.string(tileId);
				var tileData:Dynamic = Reflect.field(tiles, tileIdStr);
				if (tileData == null) {
					continue;
				}

				var polygon:Array<Dynamic> = Reflect.field(tileData, "polygon");
				if (polygon == null || polygon.length < 3) {
					continue;
				}

				// Parse polygon vertices
				var verts = new Array<{x:Float, y:Float}>();
				for (vertex in polygon) {
					var vArr:Array<Dynamic> = cast vertex;
					verts.push({x: (cast vArr[0] : Float), y: (cast vArr[1] : Float)});
				}

				// Scanline rasterize the polygon into horizontal strips
				var strips = scanlinePolygon(verts, gs);

				// Create collider sprites for each merged strip
				var isShallow = terrainLayer.isShallowTile(tileId);
				var targetGroup = isShallow ? shallowTileColliders : group;
				var worldX:Float = cx * gs;
				var worldY:Float = cy * gs;
				for (strip in strips) {
					var collider = new FlxSprite(worldX + strip.x, worldY + strip.y);
					collider.makeGraphic(strip.w, strip.h, 0x00000000);
					collider.immovable = true;
					#if debug
					collider.debugBoundingBoxColor = isShallow ? 0xFF4A9EFF : 0xFFFF00FF;
					#end
					targetGroup.add(collider);
				}
			}
		}

		return group;
	}

	static function scanlinePolygon(verts:Array<{x:Float, y:Float}>, gs:Int):Array<{
		x:Int,
		y:Int,
		w:Int,
		h:Int
	}> {
		var n = verts.length;
		var strips = new Array<{
			x:Int,
			y:Int,
			w:Int,
			h:Int
		}>();

		// For each pixel row, find the min/max x intersection with the polygon
		var curX0 = -1;
		var curX1 = -1;
		var curY0 = -1;

		for (row in 0...gs) {
			var scanY = row + 0.5;
			var rowMinX:Float = gs;
			var rowMaxX:Float = 0;
			var hit = false;

			// Test each edge for intersection with this scanline
			for (i in 0...n) {
				var j = (i + 1) % n;
				var y0 = verts[i].y;
				var y1 = verts[j].y;

				// Skip horizontal edges or edges that don't cross this scanline
				if ((y0 <= scanY && y1 <= scanY) || (y0 > scanY && y1 > scanY)) {
					continue;
				}

				// Compute x intersection
				var t = (scanY - y0) / (y1 - y0);
				var ix = verts[i].x + t * (verts[j].x - verts[i].x);

				if (ix < rowMinX) {
					rowMinX = ix;
				}
				if (ix > rowMaxX) {
					rowMaxX = ix;
				}
				hit = true;
			}

			if (!hit) {
				// Flush current strip
				if (curX0 >= 0) {
					strips.push({
						x: curX0,
						y: curY0,
						w: curX1 - curX0,
						h: row - curY0
					});
					curX0 = -1;
				}
				continue;
			}

			var x0 = Std.int(Math.max(0, Math.floor(rowMinX)));
			var x1 = Std.int(Math.min(gs, Math.ceil(rowMaxX)));
			if (x1 <= x0) {
				if (curX0 >= 0) {
					strips.push({
						x: curX0,
						y: curY0,
						w: curX1 - curX0,
						h: row - curY0
					});
					curX0 = -1;
				}
				continue;
			}

			// Merge with current strip if same x bounds
			if (x0 == curX0 && x1 == curX1) {
				continue; // strip grows by extending to next row
			}

			// Flush previous strip and start new one
			if (curX0 >= 0) {
				strips.push({
					x: curX0,
					y: curY0,
					w: curX1 - curX0,
					h: row - curY0
				});
			}
			curX0 = x0;
			curX1 = x1;
			curY0 = row;
		}

		// Flush final strip
		if (curX0 >= 0) {
			strips.push({
				x: curX0,
				y: curY0,
				w: curX1 - curX0,
				h: gs - curY0
			});
		}

		return strips;
	}

	/**
	 * Picks `count` random walkable tile positions (not water, not shallow, not solid).
	 * Returns pixel positions at tile centers.
	 */
	public function getRandomSpawnPoints(count:Int):Array<FlxPoint> {
		var layer = waterGrid;
		var cols = layer.cWid;
		var rows = layer.cHei;
		var gridSize = layer.gridSize;

		// build candidate list of walkable tiles
		var candidates = new Array<Int>();
		for (cy in 0...rows) {
			for (cx in 0...cols) {
				// skip water tiles
				if (layer.getInt(cx, cy) == 1) {
					continue;
				}
				var tileX = cx * gridSize + gridSize / 2;
				var tileY = cy * gridSize + gridSize / 2;
				// skip shallow and solid tiles
				if (terrainLayer.isShallowAt(tileX, tileY)) {
					continue;
				}
				if (terrainLayer.isSolidAt(tileX, tileY)) {
					continue;
				}
				candidates.push(cx + cy * cols);
			}
		}

		if (candidates.length == 0) {
			QLog.error("Level: no walkable tiles found for spawn points, falling back to LDTK spawn");
			return [FlxPoint.get(spawnPoint.x, spawnPoint.y)];
		}

		var results = new Array<FlxPoint>();
		for (_ in 0...count) {
			if (candidates.length == 0) {
				break;
			}
			var idx = FlxG.random.int(0, candidates.length - 1);
			var linearIdx = candidates[idx];
			// remove to avoid duplicates
			candidates[idx] = candidates[candidates.length - 1];
			candidates.pop();

			var cx = linearIdx % cols;
			var cy = Std.int(linearIdx / cols);
			results.push(FlxPoint.get(cx * gridSize + gridSize / 2, cy * gridSize + gridSize / 2));
		}

		return results;
	}

	function parseCameraZones(zoneDefs:Array<Ldtk.Entity_CameraZone>) {
		camZones = new Map<String, FlxRect>();
		for (z in zoneDefs) {
			camZones.set(z.iid, FlxRect.get(z.pixelX, z.pixelY, z.width, z.height));
		}
	}

	function parseCameraTransitions(areaDefs:Array<Ldtk.Entity_CameraTransition>) {
		camTransitions = new Array<CameraTransition>();
		for (def in areaDefs) {
			var transArea = FlxRect.get(def.pixelX, def.pixelY, def.width, def.height);
			var camTrigger = new CameraTransition(transArea);
			for (i in 0...def.f_Directions.length) {
				camTrigger.addGuideTrigger(def.f_Directions[i].toCardinal(), camZones.get(def.f_Zones[i].entityIid));
			}
			camTransitions.push(camTrigger);
		}
	}
}
