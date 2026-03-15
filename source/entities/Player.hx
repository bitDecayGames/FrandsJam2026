package entities;

import bitdecay.flixel.graphics.Aseprite;
import flixel.graphics.FlxAsepriteUtil;
import managers.GameManager;
import schema.PlayerState;
import net.NetworkManager;
import entities.FishTypes;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.math.FlxPoint;
import flixel.util.FlxColor;
import flixel.util.FlxSignal;
import flixel.util.FlxSpriteUtil;
import input.InputCalculator;
import input.SimpleController;
import bitdecay.flixel.spacial.Cardinal;
import bitdecay.flixel.graphics.AsepriteMacros;
import flixel.FlxG;
import flixel.group.FlxGroup;
import flixel.text.FlxText;
import haxe.io.Path;
import entities.ButtFire;
import entities.FootDust;
import entities.Footprint;
import entities.Inventory;
import entities.Inventory.InventoryItem;
import levels.ldtk.BDTilemap;
import todo.TODO;

class Player extends FlxSprite {
	public static var anims = AsepriteMacros.tagNames("assets/aseprite/characters/playerA.json");
	public static var bobberAnims = AsepriteMacros.tagNames("assets/aseprite/bobber.json");

	// 0-indexed frame within the cast animation when the bobber launches
	static inline var CAST_LAUNCH_FRAME:Int = 3;
	// 0-indexed frame within the catch animation when the bobber retracts (1 before final)
	static inline var CATCH_RETRACT_FRAME:Int = 1;

	static var ONE_SHOT_PREFIXES:Array<String> = ["cast_", "throw_", "catch_"];

	public static var SKINS:Array<String> = [
		"assets/aseprite/characters/playerA.json",
		"assets/aseprite/characters/playerB.json",
		"assets/aseprite/characters/playerC.json",
		"assets/aseprite/characters/playerD.json",
		"assets/aseprite/characters/playerE.json",
		"assets/aseprite/characters/playerF.json",
		"assets/aseprite/characters/playerG.json",
		"assets/aseprite/characters/playerH.json",
	];

	public static var BOBBERS:Array<String> = ["a", "b", "c", "d", "e", "f", "g", "h",];

	public var skinIndex:Int = 0;

	var speed:Float = 100;
	var playerNum = 0;

	public var controlState:String = PlayerState.CONTROL_STATE_IDLE;

	public var hotModeActive:Bool = false;

	var hotModeTimer:Float = 0;
	var fireEmitTimer:Float = 0;

	public var inventory = new Inventory();
	public var score:Int = 0;

	public var lastInputDir:Cardinal = E;

	static inline var SHALLOW_WATER_OFFSET:Float = 8;

	public var frozen:Bool = false;

	public var sessionId:String = "";

	// Cast state
	var castState:CastState = IDLE;

	public var castBobber(default, null):FlxSprite;

	// Holder variable to track fishing rod charge sound
	var fishingRodChargeSound:String = "";

	var castTarget:FlxPoint;
	var castStartPos:FlxPoint;
	var castFlightTime:Float = 0;
	var castElapsed:Float = 0;
	var castPower:Float = 0;
	var castPowerDir:Float = 1;
	var castDirSuffix:String = "down";
	var retractHasFish:Bool = false;

	public var caughtFishSpriteIndex:Int = 0;
	public var caughtFishLengthCm:Int = 0;
	public var onFishDelivered:Null<() -> Void> = null;

	// Cast sprites
	var reticle:FlxSprite;
	var fishingLine:FlxSprite;
	var powerBarBg:FlxSprite;
	var powerBarFill:FlxSprite;

	// Terrain layer for sampling ground colors — set by PlayState
	public var terrainLayer:BDTilemap;

	// Group for ground-level effects (dust, footprints) — set by PlayState
	public var groundEffectsGroup:FlxGroup;

	// Factory for creating thrown rocks — set by PlayState
	public var makeRock:(Float, Float, Bool) -> Rock;

	// Effect callbacks — set by PlayState
	public var onBobberLanded:Null<(Float, Float) -> Void> = null;

	// Throw state
	var throwing:Bool = false;
	var throwingBigRock:Bool = false;
	var rockSprite:Rock;
	var rockTarget:FlxPoint;
	var rockStartPos:FlxPoint;
	var rockFlightTime:Float = 0;
	var rockElapsed:Float = 0;

	// Animation state tracking
	public var isMoving:Bool = false;

	var lastMoving:Bool = false;
	var lastAnimDir:Cardinal = E;

	public var onAnimUpdate = new FlxTypedSignal<(String, Bool) -> Void>();

	var state:FlxState;

	public static function fromState(p:PlayerState, state:FlxState):Player {
		var p = new Player(p.x, p.y, state);
		p.skinIndex = p.skinIndex;
		p.swapSkin();
		return p;
	}

	public function new(X:Float, Y:Float, state:FlxState) {
		super(X, Y);
		this.state = state;
		loadSkin(SKINS[skinIndex]);

		// animation.onFrameChange.add(onAnimFrameChange);
		// animation.onFinish.add(onAnimFinish);

		onAnimUpdate.add((animName, forceRestart) -> {
			animation.play(animName, forceRestart);
		});

		sendAnimUpdate("stand_down");

		reticle = new FlxSprite();
		reticle.loadGraphic(AssetPaths.aimingTarget__png, true, 8, 8);
		reticle.animation.add("idle", [0, 1, 2, 3], 8, true);
		reticle.animation.play("idle");
		state.add(reticle);

		fishingLine = new FlxSprite();
		fishingLine.makeGraphic(200, 200, FlxColor.TRANSPARENT, true);
		fishingLine.visible = false;
		state.add(fishingLine);

		powerBarBg = new FlxSprite();
		powerBarBg.makeGraphic(32, 4, FlxColor.fromRGB(40, 40, 40));
		powerBarBg.visible = false;
		state.add(powerBarBg);

		powerBarFill = new FlxSprite();
		powerBarFill.makeGraphic(32, 4, FlxColor.LIME);
		powerBarFill.visible = false;
		powerBarFill.origin.set(0, 0);
		state.add(powerBarFill);
	}

	function playMovementAnim(force:Bool = false) {
		// TODO: Filler for now
		var inShallowWater = false;

		var moving = isMoving;
		if (!force && moving == lastMoving && lastInputDir == lastAnimDir && !inShallowWater)
			return;

		lastMoving = moving;
		lastAnimDir = lastInputDir;

		var dirSuffix = getDirSuffix();
		var prefix = (inShallowWater || !moving) ? "stand_" : "run_";

		// TODO: Look at the actual PlayerState object to know what our action is
		animation.play(prefix + dirSuffix, false);
	}

	function sendAnimUpdate(animName:String, forceRestart:Bool = false) {
		onAnimUpdate.dispatch(animName, forceRestart);
	}

	public function pickupItem(item:InventoryItem) {
		inventory.add(item);
	}

	public function activateHotMode() {
		hotModeActive = true;
		hotModeTimer = 30.0;
	}

	public function setNetwork(session:String) {
		cleanupNetwork();
		sessionId = session;
	}

	override public function update(delta:Float) {
		super.update(delta);

		switch (controlState) {
			case PlayerState.CONTROL_STATE_IDLE:
				playMovementAnim();
			case PlayerState.CONTROL_STATE_CHARGING:
				animation.play("cast_" + getDirSuffix(), false);
				animation.pause();
			case PlayerState.CONTROL_STATE_CASTING:
				animation.play("cast_" + getDirSuffix(), true);
		}
	}

	function clampToWorldBounds() {
		var bounds = FlxG.worldBounds;
		x = Math.max(bounds.left, Math.min(bounds.right - width, x));
		y = Math.max(bounds.top, Math.min(bounds.bottom - height, y));
	}

	function updateReticle() {
		if (reticle == null)
			return;
		var reticleOffset = lastInputDir.asVector();
		var bounds = FlxG.worldBounds;
		reticle.setPosition(Math.max(bounds.left, Math.min(bounds.right - reticle.width, last.x + reticleOffset.x * 96 + 4)),
			Math.max(bounds.top, Math.min(bounds.bottom - reticle.height, last.y + reticleOffset.y * 96 - 8)));
		reticleOffset.put();
	}

	function loadSkin(jsonPath:String) {
		var jsonText:String = openfl.Assets.getText(jsonPath);
		var json = haxe.Json.parse(jsonText);

		var pngPath = Path.join([Path.directory(jsonPath), json.meta.image]);
		var sheetW:Int = json.meta.size.w;
		var cols:Int = Std.int(sheetW / 48);

		loadGraphic(pngPath, true, 48, 48);
		setSize(16, 8);
		offset.set(16, 28);

		var frames:Array<Dynamic> = json.frames;
		var tags:Array<Dynamic> = json.meta.frameTags;
		for (tag in tags) {
			var name:String = tag.name;
			var from:Int = tag.from;
			var to:Int = tag.to;
			var indices:Array<Int> = [];
			for (i in from...to + 1) {
				var fx:Int = frames[i].frame.x;
				var fy:Int = frames[i].frame.y;
				indices.push(Std.int(fy / 48) * cols + Std.int(fx / 48));
			}
			var loop = true;
			for (p in ONE_SHOT_PREFIXES) {
				if (StringTools.startsWith(name, p)) {
					loop = false;
					break;
				}
			}
			animation.add(name, indices, 12, loop);
		}
	}

	public function swapSkin() {
		var curAnim = animation.curAnim;
		var animName = curAnim != null ? curAnim.name : null;
		var animFrame = curAnim != null ? curAnim.curFrame : 0;
		loadSkin(SKINS[skinIndex]);
		if (animName != null) {
			animation.play(animName, false, false, animFrame);
		}
	}

	function getDirSuffix():String {
		return switch (lastInputDir) {
			case N: "up";
			case S: "down";
			case W: "left";
			case E: "right";
			default: "down";
		};
	}

	override function destroy() {
		onAnimUpdate.removeAll();
		if (rockTarget != null) {
			rockTarget.put();
			rockTarget = null;
		}
		if (rockStartPos != null) {
			rockStartPos.put();
			rockStartPos = null;
		}
		cleanupNetwork();
		super.destroy();
	}

	private function cleanupNetwork() {}
}

enum CastState {
	IDLE;
	CHARGING;
	CAST_ANIM;
	CASTING;
	LANDED;
	CATCH_ANIM;
	RETURNING;
}

class FloatingLabel extends flixel.text.FlxText {
	static inline var DURATION:Float = 1.0;

	var elapsed:Float = 0;

	public function new(cx:Float, cy:Float, text:String, textColor:flixel.util.FlxColor) {
		super(0, 0, 0, text, 8);
		color = textColor;
		setPosition(cx - width / 2, cy);
		velocity.y = -20;
		allowCollisions = NONE;
	}

	override public function update(dt:Float) {
		super.update(dt);
		elapsed += dt;
		var t = elapsed / DURATION;
		if (t >= 1) {
			kill();
			return;
		}
		alpha = 1 - t;
	}
}
