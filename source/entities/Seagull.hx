package entities;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.group.FlxGroup;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;
import levels.ldtk.BDTilemap;
import todo.TODO;

class Seagull extends FlxSprite {
	static inline var SPEED_MIN:Float = 40;
	static inline var SPEED_MAX:Float = 70;
	static inline var MARGIN:Float = 32;
	static inline var SOAR_MIN:Float = 0.8;
	static inline var SOAR_MAX:Float = 2.0;
	static inline var FLAP_MIN:Float = 1.5;
	static inline var FLAP_MAX:Float = 4.0;
	static inline var DRIFT_SPEED:Float = 10;
	static inline var DRIFT_MIN:Float = 0.5;
	static inline var DRIFT_MAX:Float = 1.5;

	// Shadow projection: birds at y=0 get this offset, scaling up for higher birds
	static inline var SHADOW_BASE_OFFSET:Float = 80;
	static inline var SHADOW_ALPHA:Float = 0.18;

	static inline var POOP_MIN:Float = 8.0;
	static inline var POOP_MAX:Float = 16.0;

	var goingRight:Bool;
	var stateTimer:Float;
	var soaring:Bool = false;
	var driftTimer:Float;
	var poopTimer:Float;

	var shadow:FlxSprite;
	var parentState:FlxState;
	var groundGroup:FlxGroup;
	var terrain:BDTilemap;
	var fishSpawner:FishSpawner;

	public function new(goingRight:Bool, state:FlxState, groundGroup:FlxGroup, terrain:BDTilemap, fishSpawner:FishSpawner) {
		super();
		this.goingRight = goingRight;
		this.parentState = state;
		this.groundGroup = groundGroup;
		this.terrain = terrain;
		this.fishSpawner = fishSpawner;
		loadGraphic(AssetPaths.seagull__png, true, 24, 24);
		animation.add("fly", [1, 2, 3, 4], 8, true);
		animation.add("soar", [0], 1, false);
		animation.play("fly");
		flipX = goingRight;
		scrollFactor.set(0, 0);

		shadow = new FlxSprite();
		shadow.makeGraphic(10, 4, FlxColor.TRANSPARENT);
		FlxSpriteUtil.drawEllipse(shadow, 0, 0, 10, 4, FlxColor.BLACK);
		shadow.alpha = SHADOW_ALPHA;
		shadow.scrollFactor.set(0, 0);

		var speed = FlxG.random.float(SPEED_MIN, SPEED_MAX);
		velocity.x = goingRight ? speed : -speed;

		stateTimer = FlxG.random.float(FLAP_MIN, FLAP_MAX);
		driftTimer = FlxG.random.float(DRIFT_MIN, DRIFT_MAX);
		poopTimer = FlxG.random.float(POOP_MIN, POOP_MAX);
		spawnAtEdge();
	}

	function spawnAtEdge() {
		if (goingRight) {
			x = -width - MARGIN;
		} else {
			x = FlxG.width + MARGIN;
		}
		y = FlxG.random.float(-8, FlxG.height - 8);
	}

	override public function update(elapsed:Float) {
		super.update(elapsed);

		stateTimer -= elapsed;
		if (stateTimer <= 0) {
			if (soaring) {
				soaring = false;
				animation.play("fly");
				stateTimer = FlxG.random.float(FLAP_MIN, FLAP_MAX);
			} else {
				soaring = true;
				animation.play("soar");
				stateTimer = FlxG.random.float(SOAR_MIN, SOAR_MAX);
			}
		}

		driftTimer -= elapsed;
		if (driftTimer <= 0) {
			driftTimer = FlxG.random.float(DRIFT_MIN, DRIFT_MAX);
			velocity.y = FlxG.random.float(-1, 1) * DRIFT_SPEED;
		}

		poopTimer -= elapsed;
		if (poopTimer <= 0) {
			poopTimer = FlxG.random.float(POOP_MIN, POOP_MAX);
			doPoop();
		}

		if ((goingRight && x > FlxG.width + MARGIN) || (!goingRight && x < -width - MARGIN)) {
			kill();
		}
	}

	function doPoop() {
		TODO.sfx("seagull_poop");
		var altitude = Math.max(0, (FlxG.height - 8 - y) / (FlxG.height));
		var shadowOffsetY = SHADOW_BASE_OFFSET + altitude * 40;
		var worldX = FlxG.camera.scroll.x + x + width / 2;
		var worldY = FlxG.camera.scroll.y + y + height / 2;
		var fallDist = shadowOffsetY - height / 2;
		parentState.add(new SeagullPoop(worldX, worldY, fallDist, velocity.x, parentState, groundGroup, terrain, fishSpawner));
	}

	override public function draw() {
		if (alive && shadow != null) {
			// Project shadow downward — higher birds (lower y) cast shadows further below
			var altitude = Math.max(0, (FlxG.height - 8 - y) / (FlxG.height));
			var offsetY = SHADOW_BASE_OFFSET + altitude * 40;
			shadow.x = x + width / 2 - shadow.width / 2;
			shadow.y = y + offsetY;
			shadow.alpha = SHADOW_ALPHA * (1 - altitude * 0.4);
			shadow.draw();
		}
		super.draw();
	}

	override public function destroy() {
		if (shadow != null) {
			shadow.destroy();
			shadow = null;
		}
		super.destroy();
	}
}
