package entities;

import flixel.FlxSprite;

enum WormState {
	EMERGING;
	CRAWLING;
	DIGGING;
}

class Worm extends FlxSprite {
	static inline var CRAWL_SPEED:Float = 20;
	static inline var FRAME_W:Int = 32;
	static inline var FRAME_H:Int = 8;
	static inline var SHEET_COLS:Int = 7;
	static inline var NUM_CELLS:Int = 42;

	static var cellHitboxes:Array<{x:Int, y:Int, w:Int, h:Int}>;

	var state:WormState = EMERGING;

	// Graphic top-left position (moves smoothly, independent of hitbox)
	var gx:Float;
	var gy:Float;
	var destGX:Float;
	var destGY:Float;

	public function new(srcX:Float, srcY:Float, destX:Float, destY:Float) {
		super(srcX, srcY);

		loadGraphic(AssetPaths.worm__png, true, FRAME_W, FRAME_H);

		if (cellHitboxes == null) {
			computeHitboxes();
		}

		gx = srcX;
		gy = srcY;
		destGX = destX;
		destGY = destY;

		// Spritesheet is 7 columns (224/32). Aseprite frames 11-12 reuse cells,
		// so grid indices don't match Aseprite frame numbers after that point.
		animation.add("emerge", [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 9, 8, 11, 12, 13, 14, 15, 16, 17, 18], 10, false);
		animation.add("crawl", [19, 21], 10, true);
		animation.add("dig", [23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41], 10, false);

		flipX = destX < srcX;
		animation.play("emerge");
		applyFrameHitbox();
	}

	function computeHitboxes() {
		cellHitboxes = [];
		var bmp = pixels;
		for (cell in 0...NUM_CELLS) {
			var baseX = (cell % SHEET_COLS) * FRAME_W;
			var baseY = Std.int(cell / SHEET_COLS) * FRAME_H;
			var minX = FRAME_W;
			var minY = FRAME_H;
			var maxX = -1;
			var maxY = -1;
			for (py in 0...FRAME_H) {
				for (px in 0...FRAME_W) {
					var pixel = bmp.getPixel32(baseX + px, baseY + py);
					if ((pixel >> 24) & 0xFF > 0) {
						if (px < minX) {
							minX = px;
						}
						if (px > maxX) {
							maxX = px;
						}
						if (py < minY) {
							minY = py;
						}
						if (py > maxY) {
							maxY = py;
						}
					}
				}
			}
			if (maxX >= 0) {
				cellHitboxes.push({x: minX, y: minY, w: maxX - minX + 1, h: maxY - minY + 1});
			} else {
				cellHitboxes.push({x: 0, y: 0, w: 1, h: 1});
			}
		}
	}

	function applyFrameHitbox() {
		var frameIdx = animation.frameIndex;
		if (frameIdx < 0 || frameIdx >= cellHitboxes.length) {
			return;
		}
		var hb = cellHitboxes[frameIdx];
		if (flipX) {
			offset.set(FRAME_W - hb.x - hb.w, hb.y);
		} else {
			offset.set(hb.x, hb.y);
		}
		setSize(hb.w, hb.h);
		x = gx + offset.x;
		y = gy + offset.y;
	}

	override public function update(elapsed:Float) {
		super.update(elapsed);

		switch (state) {
			case EMERGING:
				if (animation.finished) {
					state = CRAWLING;
					animation.play("crawl");
				}
			case CRAWLING:
				var dx = destGX - gx;
				var dy = destGY - gy;
				var dist = Math.sqrt(dx * dx + dy * dy);
				if (dist < 2) {
					gx = destGX;
					gy = destGY;
					state = DIGGING;
					animation.play("dig");
				} else {
					gx += (dx / dist) * CRAWL_SPEED * elapsed;
					gy += (dy / dist) * CRAWL_SPEED * elapsed;
				}
			case DIGGING:
				if (animation.finished) {
					kill();
				}
		}

		applyFrameHitbox();
	}
}
