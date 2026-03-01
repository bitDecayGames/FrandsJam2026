package entities;

import flixel.FlxSprite;

class Rock extends FlxSprite {
	public var big:Bool;
	var waterLayer:ldtk.Layer_IntGrid;
	var onAddToWorld:(Float, Float, Bool) -> Void;
	var onWaterSplash:(Float, Float, Bool) -> Void;

	public function new(x:Float, y:Float, big:Bool = false, ?waterLayer:ldtk.Layer_IntGrid, ?onAddToWorld:(Float, Float, Bool) -> Void,
			?onWaterSplash:(Float, Float, Bool) -> Void) {
		super(x, y);
		this.big = big;
		this.waterLayer = waterLayer;
		this.onAddToWorld = onAddToWorld;
		this.onWaterSplash = onWaterSplash;
		loadGraphic(big ? AssetPaths.bigRock__png : AssetPaths.rock__png);
	}

	public function resolveThrow(landX:Float, landY:Float) {
		if (waterLayer == null)
			return;
		var grid = waterLayer.gridSize;
		var tileX = Std.int(landX / grid);
		var tileY = Std.int(landY / grid);
		if (waterLayer.getInt(tileX, tileY) == 1) {
			if (onWaterSplash != null)
				onWaterSplash(landX, landY, big);
		} else {
			if (onAddToWorld != null)
				onAddToWorld(landX, landY, big);
		}
	}
}
