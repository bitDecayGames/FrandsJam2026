package levels.ldtk;

import flixel.util.FlxColor;
import levels.ldtk.Ldtk.Enum_TileTags;
import levels.ldtk.LdtkTilemap.LdtkTile;

/**
 * Bit Decay extension of LdtkTile that knows what to do with the tags and
 * metadata on each tile
**/
class BDTile extends LdtkTile<Enum_TileTags> {
	// var hit:FlxRect;
	public function new(tilemap:BDTilemap, index, width, height) {
		super(cast tilemap, index, width, height, true);

		#if debug
		ignoreDrawDebug = true;
		#end
	}

	override function destroy() {
		super.destroy();
		// Handle any needed cleanup here
	}

	override function setMetaData(metaData:String) {
		super.setMetaData(metaData);
		// Do any parsing of metadata here
	}

	override function setTags(tags:Array<Enum_TileTags>) {
		super.setTags(tags);

		visible = true;
		allowCollisions = NONE;
		#if debug
		ignoreDrawDebug = tags.length == 0;
		#end

		#if debug
		// if (tags.contains(EDITOR_ONLY))
		// {
		//     debugBoundingBoxColor = 0xFFFF00FF;
		// }
		#end

		if (tags.contains(INVISIBLE)) {
			#if debug
			debugBoundingBoxColor = FlxColor.CYAN;
			#else
			visible = false;
			#end
		}

		if (tags.contains(SOLID)) {
			allowCollisions = ANY;
		}

		if (tags.contains(SHALLOW)) {
			allowCollisions = ANY;
		}

		if (tags.contains(ONEWAY)) {
			allowCollisions = UP;
		}
	}

	public function hasCustomHitbox():Bool {
		var tm:BDTilemap = cast tilemap;
		return tm.customHitboxTileIds.exists(index);
	}

	public function applyCustomHitbox():Void {
		if (hasCustomHitbox()) {
			allowCollisions = NONE;
		}
	}
}

/**
 * Bit Decay extension of LdtkTilemap that is comprised of BDTiles to handle
 * game specific parsing of tile tags and metadata
**/
class BDTilemap extends LdtkTilemap<Enum_TileTags> {
	public var customHitboxTileIds:Map<Int, Bool> = new Map();

	public function setCustomHitboxTileIds(ids:Map<Int, Bool>):Void {
		customHitboxTileIds = ids;
		@:privateAccess
		for (tile in _tileObjects) {
			var bdTile:BDTile = cast tile;
			bdTile.applyCustomHitbox();
		}
	}

	public function setShallowCollisions(enabled:Bool):Void {
		@:privateAccess
		for (tile in _tileObjects) {
			var bdTile:BDTile = cast tile;
			if (bdTile.tags != null && bdTile.tags.contains(SHALLOW) && !bdTile.hasCustomHitbox()) {
				bdTile.allowCollisions = enabled ? ANY : NONE;
			}
		}
	}

	public function isShallowTile(tileId:Int):Bool {
		@:privateAccess
		if (tileId >= 0 && tileId < _tileObjects.length) {
			var bdTile:BDTile = cast _tileObjects[tileId];
			return bdTile.tags != null && bdTile.tags.contains(SHALLOW);
		}
		return false;
	}

	public function isFullyInTaggedArea(object:flixel.FlxObject, tags:Array<Enum_TileTags>):Bool {
		var minCol = Std.int((object.x - x) / scaledTileWidth);
		var maxCol = Std.int((object.x + object.width - 1 - x) / scaledTileWidth);
		var minRow = Std.int((object.y - y) / scaledTileHeight);
		var maxRow = Std.int((object.y + object.height - 1 - y) / scaledTileHeight);

		if (minCol < 0 || minRow < 0 || maxCol >= widthInTiles || maxRow >= heightInTiles) {
			return false;
		}

		@:privateAccess
		for (row in minRow...maxRow + 1) {
			for (col in minCol...maxCol + 1) {
				var tileId = _data[row * widthInTiles + col];
				if (tileId < 0 || tileId >= _tileObjects.length) {
					return false;
				}
				var bdTile:BDTile = cast _tileObjects[tileId];
				if (bdTile.tags == null) {
					return false;
				}
				var hasAny = false;
				for (tag in tags) {
					if (bdTile.tags.contains(tag)) {
						hasAny = true;
						break;
					}
				}
				if (!hasAny) {
					return false;
				}
			}
		}
		return true;
	}

	public function isSwimmableAt(col:Int, row:Int):Bool {
		if (col < 0 || col >= widthInTiles || row < 0 || row >= heightInTiles) {
			return false;
		}

		@:privateAccess
		var tileIndex = _data[row * widthInTiles + col];
		if (tileIndex < 0 || tileIndex >= _tileObjects.length) {
			return false;
		}
		var bdTile:BDTile = cast _tileObjects[tileIndex];
		return bdTile.tags != null && bdTile.tags.contains(SWIMMABLE);
	}

	public function isSolidAt(worldX:Float, worldY:Float):Bool {
		var col = Std.int((worldX - x) / scaledTileWidth);
		var row = Std.int((worldY - y) / scaledTileHeight);
		if (col < 0 || col >= widthInTiles || row < 0 || row >= heightInTiles) {
			return false;
		}

		@:privateAccess
		var tileIndex = _data[row * widthInTiles + col];
		if (tileIndex < 0 || tileIndex >= _tileObjects.length) {
			return false;
		}
		var bdTile:BDTile = cast _tileObjects[tileIndex];
		return bdTile.tags != null && bdTile.tags.contains(SOLID);
	}

	public function isShallowAt(worldX:Float, worldY:Float):Bool {
		var col = Std.int((worldX - x) / scaledTileWidth);
		var row = Std.int((worldY - y) / scaledTileHeight);
		if (col < 0 || col >= widthInTiles || row < 0 || row >= heightInTiles) {
			return false;
		}

		@:privateAccess
		var tileIndex = _data[row * widthInTiles + col];
		return isShallowTile(tileIndex);
	}

	public function sampleColorAt(worldX:Float, worldY:Float):FlxColor {
		var col = Std.int((worldX - x) / scaledTileWidth);
		var row = Std.int((worldY - y) / scaledTileHeight);
		if (col < 0 || col >= widthInTiles || row < 0 || row >= heightInTiles) {
			return FlxColor.TRANSPARENT;
		}

		@:privateAccess
		var tileIndex = _data[row * widthInTiles + col];
		if (tileIndex < 0) {
			return FlxColor.TRANSPARENT;
		}

		@:privateAccess
		var tileFrame = _tileObjects[tileIndex].frame;
		if (tileFrame == null || tileFrame.parent == null || tileFrame.parent.bitmap == null) {
			return FlxColor.TRANSPARENT;
		}

		var subX = Std.int((worldX - x) % scaledTileWidth);
		var subY = Std.int((worldY - y) % scaledTileHeight);
		var srcX = Std.int(tileFrame.frame.x) + subX;
		var srcY = Std.int(tileFrame.frame.y) + subY;

		return FlxColor.fromInt(tileFrame.parent.bitmap.getPixel32(srcX, srcY));
	}

	override function createTile(index:Int, width:Float, height:Float):BDTile {
		return new BDTile(this, index, width, height);
	}
}
