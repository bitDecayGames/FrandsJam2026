package debug;

#if llm_bridge
import flixel.FlxG;
import flixel.FlxBasic;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.group.FlxGroup;
import flixel.tile.FlxBaseTilemap;
import flixel.tile.FlxTilemap;
import flixel.util.FlxDirectionFlags;
import events.EventBus;
import events.IEvent;
import haxe.Json;

class LLMDebugBridge {
	static var _eventLog:Array<Dynamic> = [];
	static var _remainingSteps:Int = 0;
	static var _frameCount:Int = 0;
	static inline var MAX_EVENT_LOG:Int = 200;

	static var _heldButtons:Map<String, Bool> = new Map();
	static var _prevHeldButtons:Map<String, Bool> = new Map();
	static var _lastStepButtons:Map<String, Bool> = new Map();
	static var _pendingReleases:Array<String> = [];
	static var _releaseAfterSteps:Int = 0;
	static var _walkTarget:{
		x:Float,
		y:Float,
		thresh:Float,
		active:Bool,
		framesUsed:Int
	} = {
		x: 0,
		y: 0,
		thresh: 2,
		active: false,
		framesUsed: 0
	};

	static var VALID_BUTTONS:Array<String> = ["UP", "DOWN", "LEFT", "RIGHT", "A", "B", "START", "BACK"];

	public static function init() {
		EventBus.subscribeAll(onEvent);

		untyped js.Browser.window.__debug = {
			getState: function() {
				return _getState();
			},
			getSprites: function() {
				return _getSprites();
			},
			getPlayer: function() {
				return _getPlayer();
			},
			getTilemap: function() {
				return _getTilemap();
			},
			getCamera: function() {
				return _getCamera();
			},
			getEventLog: function(?count:Int) {
				return _getEventLog(count);
			},
			pause: function() {
				return _pause();
			},
			resume: function() {
				return _resume();
			},
			stepFrames: function(n:Int) {
				return _stepFrames(n);
			},
			setTimeScale: function(f:Float) {
				return _setTimeScale(f);
			},
			pressButton: function(name:String) {
				return _pressButton(name);
			},
			releaseButton: function(name:String) {
				return _releaseButton(name);
			},
			releaseAll: function() {
				return _releaseAll();
			},
			teleportPlayer: function(x:Float, y:Float) {
				return _teleportPlayer(x, y);
			},
			tapButton: function(name:String, ?holdFrames:Int) {
				return _tapButton(name, holdFrames);
			},
			walkTo: function(x:Float, y:Float, ?threshold:Float) {
				return _walkTo(x, y, threshold);
			}
		};

		trace("LLMDebugBridge initialized");
	}

	public static function onUpdate() {
		_frameCount++;
		if (_remainingSteps > 0) {
			// Rotate input state only on frames where the game actually steps,
			// so just_pressed/just_released reflect real transitions
			_prevHeldButtons = _lastStepButtons.copy();
			_lastStepButtons = _heldButtons.copy();
			FlxG.vcr.stepRequested = true;
			_remainingSteps--;

			// Handle tapButton: release after hold frames expire
			if (_releaseAfterSteps > 0) {
				_releaseAfterSteps--;
				if (_releaseAfterSteps <= 0) {
					for (btn in _pendingReleases) {
						_heldButtons.set(btn, false);
					}
					_pendingReleases = [];
					// Step one more frame to process the release
					_remainingSteps++;
				}
			}

			// Handle walkTo: check if player arrived
			if (_walkTarget.active) {
				_walkTarget.framesUsed++;
				var player = findPlayer(FlxG.state, 0);
				if (player != null) {
					var p:FlxObject = cast player;
					var dx = _walkTarget.x - p.x;
					var dy = _walkTarget.y - p.y;
					var dist = Math.sqrt(dx * dx + dy * dy);
					if (dist <= _walkTarget.thresh) {
						// Arrived — stop moving
						_releaseAll();
						p.velocity.set(0, 0);
						_walkTarget.active = false;
						_remainingSteps = 0;
					}
				}
			}
		}
	}

	static function onEvent(e:IEvent) {
		var obj:Dynamic = {};
		obj.id = e.id;
		obj.type = e.type;

		var fields = Reflect.fields(e);
		for (field in fields) {
			if (field == "id" || field == "type" || field == "reducers")
				continue;
			var value:Dynamic = Reflect.field(e, field);
			if (Std.isOfType(value, Float)) {
				Reflect.setField(obj, field, roundFloat(value));
			} else {
				Reflect.setField(obj, field, value);
			}
		}

		_eventLog.push(obj);
		if (_eventLog.length > MAX_EVENT_LOG) {
			_eventLog.shift();
		}
	}

	// Public query methods for SimpleController integration
	public static function isPressed(button:String):Bool {
		return _heldButtons.exists(button) && _heldButtons.get(button);
	}

	public static function isJustPressed(button:String):Bool {
		var curr = _heldButtons.exists(button) && _heldButtons.get(button);
		var prev = _prevHeldButtons.exists(button) && _prevHeldButtons.get(button);
		return curr && !prev;
	}

	public static function isJustReleased(button:String):Bool {
		var curr = _heldButtons.exists(button) && _heldButtons.get(button);
		var prev = _prevHeldButtons.exists(button) && _prevHeldButtons.get(button);
		return !curr && prev;
	}

	static function _pressButton(name:String):String {
		var upper = name.toUpperCase();
		if (VALID_BUTTONS.indexOf(upper) == -1) {
			return Json.stringify({error: "Invalid button: " + name + ". Valid: " + VALID_BUTTONS.join(", ")});
		}
		_heldButtons.set(upper, true);
		return Json.stringify({held: getHeldList()});
	}

	static function _releaseButton(name:String):String {
		var upper = name.toUpperCase();
		if (VALID_BUTTONS.indexOf(upper) == -1) {
			return Json.stringify({error: "Invalid button: " + name + ". Valid: " + VALID_BUTTONS.join(", ")});
		}
		_heldButtons.set(upper, false);
		return Json.stringify({held: getHeldList()});
	}

	static function _releaseAll():String {
		for (btn in VALID_BUTTONS) {
			_heldButtons.set(btn, false);
		}
		return Json.stringify({held: getHeldList()});
	}

	static function getHeldList():Array<String> {
		var list:Array<String> = [];
		for (btn in VALID_BUTTONS) {
			if (_heldButtons.exists(btn) && _heldButtons.get(btn)) {
				list.push(btn);
			}
		}
		return list;
	}

	static function _getState():String {
		var state = FlxG.state;
		var stateName = Type.getClassName(Type.getClass(state));
		var subStateName:String = null;
		if (state.subState != null) {
			subStateName = Type.getClassName(Type.getClass(state.subState));
		}
		return Json.stringify({
			stateName: stateName,
			subState: subStateName,
			gameWidth: FlxG.width,
			gameHeight: FlxG.height,
			elapsed: roundFloat(FlxG.elapsed),
			paused: FlxG.vcr.paused,
			timeScale: roundFloat(FlxG.timeScale),
			frameCount: _frameCount
		});
	}

	static function _getSprites():String {
		var result:Array<Dynamic> = [];
		if (FlxG.state != null) {
			walkGroup(FlxG.state, result, 0);
		}
		return Json.stringify(result);
	}

	static function _getPlayer():String {
		var player = findPlayer(FlxG.state, 0);
		if (player == null) {
			return Json.stringify({error: "Player not found"});
		}
		var p:entities.Player = cast player;
		return Json.stringify({
			x: roundFloat(p.x),
			y: roundFloat(p.y),
			width: roundFloat(p.width),
			height: roundFloat(p.height),
			velocityX: roundFloat(p.velocity.x),
			velocityY: roundFloat(p.velocity.y),
			animName: p.animation.curAnim != null ? p.animation.curAnim.name : null,
			animFrame: p.animation.curAnim != null ? p.animation.curAnim.curFrame : 0,
			facing: Std.string(p.facing),
			alive: p.alive,
			speed: roundFloat(@:privateAccess p.speed)
		});
	}

	static function _getTilemap():String {
		var tilemap = findTilemap(FlxG.state, 0);
		if (tilemap == null) {
			return Json.stringify({error: "Tilemap not found"});
		}

		// FlxBaseTilemap inherits from FlxTilemap in practice (via LdtkTilemap),
		// so cast directly to access tileWidth/tileHeight
		var tm:FlxTilemap = cast tilemap;
		var tw = tm.tileWidth;
		var th = tm.tileHeight;

		@:privateAccess var data = tilemap._data;
		@:privateAccess var tileObjects = tilemap._tileObjects;

		var grid = new StringBuf();
		for (row in 0...tilemap.heightInTiles) {
			if (row > 0)
				grid.add("\n");
			for (col in 0...tilemap.widthInTiles) {
				var idx = row * tilemap.widthInTiles + col;
				if (idx >= data.length) {
					grid.add(".");
					continue;
				}
				var tileIdx = data[idx];
				if (tileIdx < 0 || tileIdx >= tileObjects.length) {
					grid.add(".");
					continue;
				}
				var tile = tileObjects[tileIdx];
				if (tile == null) {
					grid.add(".");
					continue;
				}
				var col2 = tile.allowCollisions;
				if (col2 == FlxDirectionFlags.NONE) {
					grid.add(".");
				} else if (col2 == FlxDirectionFlags.ANY) {
					grid.add("#");
				} else if (col2 == FlxDirectionFlags.UP || col2 == FlxDirectionFlags.CEILING) {
					grid.add("^");
				} else {
					grid.add("?");
				}
			}
		}

		return Json.stringify({
			widthInTiles: tilemap.widthInTiles,
			heightInTiles: tilemap.heightInTiles,
			tileWidth: tw,
			tileHeight: th,
			x: roundFloat(tilemap.x),
			y: roundFloat(tilemap.y),
			collisionGrid: grid.toString()
		});
	}

	static function _getCamera():String {
		var cam = FlxG.camera;
		return Json.stringify({
			scrollX: roundFloat(cam.scroll.x),
			scrollY: roundFloat(cam.scroll.y),
			zoom: roundFloat(cam.zoom),
			width: cam.width,
			height: cam.height,
			minScrollX: cam.minScrollX,
			maxScrollX: cam.maxScrollX,
			minScrollY: cam.minScrollY,
			maxScrollY: cam.maxScrollY
		});
	}

	static function _getEventLog(?count:Int):String {
		var n = count != null ? count : 50;
		if (n > MAX_EVENT_LOG)
			n = MAX_EVENT_LOG;
		var start = _eventLog.length > n ? _eventLog.length - n : 0;
		return Json.stringify(_eventLog.slice(start));
	}

	static function _pause():String {
		FlxG.vcr.pause();
		return Json.stringify({paused: true});
	}

	static function _resume():String {
		FlxG.vcr.resume();
		_remainingSteps = 0;
		return Json.stringify({paused: false});
	}

	static function _stepFrames(n:Int):String {
		FlxG.vcr.pause();
		_remainingSteps = n - 1;
		FlxG.vcr.stepRequested = true;
		return Json.stringify({stepping: n, paused: true});
	}

	static function _setTimeScale(f:Float):String {
		FlxG.timeScale = f;
		return Json.stringify({timeScale: f});
	}

	static function _tapButton(name:String, ?holdFrames:Int):String {
		var hold = holdFrames != null ? holdFrames : 1;
		var upper = name.toUpperCase();
		if (VALID_BUTTONS.indexOf(upper) == -1) {
			return Json.stringify({error: "Invalid button: " + name + ". Valid: " + VALID_BUTTONS.join(", ")});
		}
		// Press, step for hold duration, release, step 1 to process release
		_heldButtons.set(upper, true);
		_stepFrames(hold);
		// Queue the release after the hold frames complete
		_pendingReleases.push(upper);
		_releaseAfterSteps = hold;
		return Json.stringify({tapped: upper, holdFrames: hold});
	}

	static function _walkTo(x:Float, y:Float, ?threshold:Float):String {
		var thresh = threshold != null ? threshold : 2.0;
		var player = findPlayer(FlxG.state, 0);
		if (player == null) {
			return Json.stringify({error: "Player not found"});
		}
		var p:FlxObject = cast player;
		var dx = x - p.x;
		var dy = y - p.y;
		var dist = Math.sqrt(dx * dx + dy * dy);

		if (dist <= thresh) {
			return Json.stringify({
				arrived: true,
				x: roundFloat(p.x),
				y: roundFloat(p.y),
				framesUsed: 0
			});
		}

		// Calculate how many frames we need at player speed (~150px/sec, ~2.5px/frame)
		var maxFrames = Math.ceil(dist / 2.0) + 10; // generous estimate with padding

		// Set direction buttons
		_releaseAll();
		if (dx > thresh)
			_heldButtons.set("RIGHT", true);
		if (dx < -thresh)
			_heldButtons.set("LEFT", true);
		if (dy > thresh)
			_heldButtons.set("DOWN", true);
		if (dy < -thresh)
			_heldButtons.set("UP", true);

		_stepFrames(maxFrames);
		_walkTarget = {
			x: x,
			y: y,
			thresh: thresh,
			active: true,
			framesUsed: 0
		};
		return Json.stringify({
			walking: true,
			targetX: roundFloat(x),
			targetY: roundFloat(y),
			maxFrames: maxFrames
		});
	}

	static function _teleportPlayer(x:Float, y:Float):String {
		var player = findPlayer(FlxG.state, 0);
		if (player == null) {
			return Json.stringify({error: "Player not found"});
		}
		var p:FlxObject = cast player;
		p.x = x;
		p.y = y;
		p.velocity.set(0, 0);
		return Json.stringify({x: roundFloat(x), y: roundFloat(y)});
	}

	static function walkGroup(group:FlxTypedGroup<FlxBasic>, result:Array<Dynamic>, depth:Int) {
		if (depth > 10 || group == null)
			return;
		for (member in group.members) {
			if (member == null)
				continue;
			var info:Dynamic = {};
			info.type = Type.getClassName(Type.getClass(member));
			@:privateAccess info.flixelType = Std.string(member.flixelType);

			if (Std.isOfType(member, FlxObject)) {
				var obj:FlxObject = cast member;
				info.x = roundFloat(obj.x);
				info.y = roundFloat(obj.y);
				info.width = roundFloat(obj.width);
				info.height = roundFloat(obj.height);
				info.velocityX = roundFloat(obj.velocity.x);
				info.velocityY = roundFloat(obj.velocity.y);
				info.visible = obj.visible;
				info.alive = obj.alive;
			}

			if (Std.isOfType(member, FlxSprite)) {
				var spr:FlxSprite = cast member;
				info.animName = spr.animation.curAnim != null ? spr.animation.curAnim.name : null;
				info.animFrame = spr.animation.curAnim != null ? spr.animation.curAnim.curFrame : 0;
			}

			if (Std.isOfType(member, FlxGroup)) {
				var sub:FlxGroup = cast member;
				var children:Array<Dynamic> = [];
				walkGroup(sub, children, depth + 1);
				info.children = children;
			}

			result.push(info);
		}
	}

	static function findPlayer(group:FlxTypedGroup<FlxBasic>, depth:Int):FlxBasic {
		if (depth > 10 || group == null)
			return null;
		for (member in group.members) {
			if (member == null)
				continue;
			if (Std.isOfType(member, entities.Player)) {
				return member;
			}
			if (Std.isOfType(member, FlxGroup)) {
				var found = findPlayer(cast member, depth + 1);
				if (found != null)
					return found;
			}
		}
		return null;
	}

	static function findTilemap(group:FlxTypedGroup<FlxBasic>, depth:Int):FlxBaseTilemap<FlxObject> {
		if (depth > 10 || group == null)
			return null;
		for (member in group.members) {
			if (member == null)
				continue;
			if (Std.isOfType(member, FlxBaseTilemap)) {
				return cast member;
			}
			if (Std.isOfType(member, FlxGroup)) {
				var found = findTilemap(cast member, depth + 1);
				if (found != null)
					return found;
			}
		}
		return null;
	}

	static inline function roundFloat(v:Float):Float {
		return Math.round(v * 100) / 100;
	}
}
#else
class LLMDebugBridge {
	public static function init() {}

	public static function onUpdate() {}
}
#end
