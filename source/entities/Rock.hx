package entities;

import flixel.FlxSprite;

class Rock extends FlxSprite {
	var waterLayer:ldtk.Layer_IntGrid;
	var onAddToWorld:(Float, Float) -> Void;

	public function new(x:Float, y:Float, ?waterLayer:ldtk.Layer_IntGrid, ?onAddToWorld:(Float, Float) -> Void) {
		super(x, y);
		this.waterLayer = waterLayer;
		this.onAddToWorld = onAddToWorld;
		loadGraphic(AssetPaths.rock__png);
	}

	public function resolveThrow(landX:Float, landY:Float) {
		if (waterLayer == null || onAddToWorld == null)
			return;
		var grid = waterLayer.gridSize;
		var tileX = Std.int(landX / grid);
		var tileY = Std.int(landY / grid);
		if (waterLayer.getInt(tileX, tileY) != 1) {
			onAddToWorld(landX, landY);
		}
	}
}
