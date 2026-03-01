package entities;

import flixel.FlxSprite;

class Rock extends FlxSprite {
	var waterLayer:ldtk.Layer_IntGrid;
	var onAddToWorld:(Float, Float) -> Void;
	var onWaterSplash:(Float, Float) -> Void;

	public function new(x:Float, y:Float, ?waterLayer:ldtk.Layer_IntGrid, ?onAddToWorld:(Float, Float) -> Void, ?onWaterSplash:(Float, Float) -> Void) {
		super(x, y);
		this.waterLayer = waterLayer;
		this.onAddToWorld = onAddToWorld;
		this.onWaterSplash = onWaterSplash;
		loadGraphic(AssetPaths.rock__png);
	}

	public function resolveThrow(landX:Float, landY:Float) {
		if (waterLayer == null)
			return;
		var grid = waterLayer.gridSize;
		var tileX = Std.int(landX / grid);
		var tileY = Std.int(landY / grid);
		if (waterLayer.getInt(tileX, tileY) == 1) {
			if (onWaterSplash != null)
				onWaterSplash(landX, landY);
		} else {
			if (onAddToWorld != null)
				onAddToWorld(landX, landY);
		}
	}
}
