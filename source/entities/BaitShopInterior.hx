package entities;

import flixel.FlxObject;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import flixel.tile.FlxTilemap;
import flixel.util.FlxDirectionFlags;

class BaitShopInterior {
	// Positioned well away from the main 640x480 level
	public static inline var INTERIOR_X:Float = 1200;
	public static inline var INTERIOR_Y:Float = 1200;

	static inline var WIDTH_TILES:Int = 12;
	static inline var HEIGHT_TILES:Int = 10;
	static inline var TILE_SIZE:Int = 16;

	// Tile IDs from devTiles.png tileset
	static inline var WALL_TILE:Int = 1;
	static inline var FLOOR_TILE:Int = 5;

	public var tilemap:FlxTilemap;
	public var cameraBounds:FlxRect;
	public var worldBounds:FlxRect;
	public var spawnPoint:FlxPoint;

	public function new() {
		tilemap = new FlxTilemap();
		var tiles = buildLayout();
		tilemap.loadMapFromArray(tiles, WIDTH_TILES, HEIGHT_TILES, "assets/images/devTiles.png", TILE_SIZE, TILE_SIZE);
		tilemap.setPosition(INTERIOR_X, INTERIOR_Y);

		// By default all tiles >= 1 collide. Make floor tiles walkable.
		tilemap.setTileProperties(FLOOR_TILE, FlxDirectionFlags.NONE);

		var pxWidth = WIDTH_TILES * TILE_SIZE;
		var pxHeight = HEIGHT_TILES * TILE_SIZE;

		// Camera bounds sized to viewport so the shop appears centered and locked
		var centerX = INTERIOR_X + pxWidth / 2;
		var centerY = INTERIOR_Y + pxHeight / 2;
		cameraBounds = FlxRect.get(centerX - 320, centerY - 240, 640, 480);

		// World bounds extend below the shop so the player can walk out the exit
		worldBounds = FlxRect.get(INTERIOR_X, INTERIOR_Y, pxWidth, pxHeight + TILE_SIZE * 2);

		// Spawn just north of the exit so it feels like the player walked in
		spawnPoint = FlxPoint.get(INTERIOR_X + pxWidth / 2, INTERIOR_Y + (HEIGHT_TILES - 2) * TILE_SIZE);
	}

	public function isPlayerPastExit(playerY:Float, playerHeight:Float):Bool {
		return playerY + playerHeight > INTERIOR_Y + HEIGHT_TILES * TILE_SIZE;
	}

	function buildLayout():Array<Int> {
		var tiles = new Array<Int>();
		for (row in 0...HEIGHT_TILES) {
			for (col in 0...WIDTH_TILES) {
				if (row == 0 || col == 0 || col == WIDTH_TILES - 1) {
					// Top wall and side walls
					tiles.push(WALL_TILE);
				} else if (row == HEIGHT_TILES - 1) {
					// Bottom wall with exit opening in center (cols 4-7)
					if (col >= 4 && col <= 7) {
						tiles.push(FLOOR_TILE);
					} else {
						tiles.push(WALL_TILE);
					}
				} else {
					tiles.push(FLOOR_TILE);
				}
			}
		}
		return tiles;
	}
}
