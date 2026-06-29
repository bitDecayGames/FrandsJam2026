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

	public static function cardinalToAngle(dir:Cardinal):Int {
		return switch (dir) {
			case N: 0;
			case NE: 45;
			case E: 90;
			case SE: 135;
			case S: 180;
			case SW: 225;
			case W: 270;
			case NW: 315;
			default: -1;
		};
	}

	var speed:Float = 100;
	var playerNum = 0;

	public var hotModeActive:Bool = false;
	public var drowned:Bool = false;

	var hotModeTimer:Float = 0;
	var fireEmitTimer:Float = 0;
	var botTimer:Float = 0;
	var drownTimer:Float = 0;
	var drownBlinkTimer:Float = 0;
	var drownBlinksLeft:Int = 0;
	var drownReturnX:Float = 0;
	var drownReturnY:Float = 0;

	static inline var DROWN_HIDE_DURATION:Float = 2.0;
	static inline var DROWN_BLINK_RATE:Float = 0.15;
	static inline var DROWN_BLINK_COUNT:Int = 3;

	// Client-side prediction
	public var simulation:Simulation;
	public var playerState:schema.PlayerState;

	var pendingInputs:Array<PInput.P_Input> = [];
	var inputSeq:Int = 0;

	public var inventory = new Inventory();
	public var score:Int = 0;

	public var lastInputDir:Cardinal = E;

	static inline var SHALLOW_WATER_OFFSET:Float = 8;

	public var inShallowWater(default, set):Bool = false;

	function set_inShallowWater(value:Bool):Bool {
		if (value == inShallowWater) {
			return value;
		}
		inShallowWater = value;
		if (inShallowWater) {
			if (hotModeActive && inventory.hasWaders()) {
				hotModeActive = false;

				if (!isRemote) {
					GameManager.ME.net.sendHotPepper(false);
				}

			}
			offset.y -= SHALLOW_WATER_OFFSET;
			clipRect = flixel.math.FlxRect.get(0, 0, 48, 28);
		} else {
			offset.y += SHALLOW_WATER_OFFSET;
			clipRect = null;
			if (animation != null && animation.curAnim != null) {
				playMovementAnim(true);
			}
		}
		return value;
	}

	public var frozen:Bool = false;

	public var sessionId:String = "";

	// tracks if this player is controled by the remote client
	public var isRemote:Bool = false;

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
	var remoteWasStationary:Bool = false;

	// Interpolation targets for smooth remote player movement
	public var remoteTargetX:Float = 0;
	public var remoteTargetY:Float = 0;
	var remoteServerVelX:Float = 0;
	var remoteServerVelY:Float = 0;

	static inline var REMOTE_TELEPORT_DIST_SQ:Float = 128 * 128;
	static inline var REMOTE_SNAP_DIST_SQ:Float = 4 * 4;
	static inline var REMOTE_BLEND_RANGE:Float = 24.0;
	static inline var REMOTE_SPRING_K:Float = 8.0;
	static inline var REMOTE_MAX_CORRECTION:Float = 250.0;

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
	public var makePotion:(Float, Float) -> Rock;
	public var makeBait:(Float, Float) -> Rock;
	var throwingPotion:Bool = false;
	var throwingBait:Bool = false;

	// Effect callbacks — set by PlayState
	public var onBobberLanded:Null<(Float, Float) -> Void> = null;

	// Throw state
	var throwing:Bool = false;
	var throwingBigRock:Bool = false;
	var aimingRock:Bool = false;
	public var knockbackTimer:Float = 0;
	var aimReticleX:Float = 0;
	var aimReticleY:Float = 0;
	var blastRadiusSprite:FlxSprite;
	static inline var AIM_RETICLE_SPEED:Float = 200;
	var rockSprite:Rock;
	var rockTarget:FlxPoint;
	var rockStartPos:FlxPoint;
	var rockFlightTime:Float = 0;
	var rockElapsed:Float = 0;

	// Animation state tracking
	var lastMoving:Bool = false;
	var lastAnimDir:Cardinal = E;

	public var onAnimUpdate = new FlxTypedSignal<(String, Bool) -> Void>();

	var state:FlxState;

	public function new(X:Float, Y:Float, state:FlxState) {
		super(X, Y);
		this.state = state;
		loadSkin(SKINS[skinIndex]);

		animation.onFrameChange.add(onAnimFrameChange);
		animation.onFinish.add(onAnimFinish);

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

	function onAnimFrameChange(animName:String, frameNumber:Int, frameIndex:Int) {
		if (castState == CAST_ANIM && castBobber == null && frameNumber == CAST_LAUNCH_FRAME) {
			if (isRemote) {
				spawnBobberArc(); // castTarget already set by remoteStartCast()
			} else {
				launchBobber();
			}
		}
		if (throwing && rockSprite == null && frameNumber == 6) {
			launchRock();
		}

		// Bug: animName came back as null in a multiplayer test session. This shouldn't happen,
		// but guard against it here just in case.
		if (animName == null) {
			QLog.warn('Player: onAnimFrameChange animName is null');
			return;
		}

		// Footstep effects on foot-plant frames of run animations
		if (drowned) {
			return;
		}
		if (StringTools.startsWith(animName, "run_") && (frameNumber == 2 || frameNumber == 6)) {
			var fx = x + width / 2;
			var fy = y + 4;
			var groundColor:Null<FlxColor> = null;
			if (terrainLayer != null) {
				var sampled = terrainLayer.sampleColorAt(fx, fy);
				if (sampled != FlxColor.TRANSPARENT) {
					groundColor = sampled;
				}
			}
			var effectsTarget:FlxGroup = groundEffectsGroup != null ? groundEffectsGroup : null;
			var groundType:String = null;
			var isBrown = false;
			var isBlue = false;
			if (groundColor != null) {
				var hue = groundColor.hue;
				isBrown = (hue >= 15 && hue <= 55) && groundColor.saturation > 0.15;
				isBlue = groundColor.blue > groundColor.red && groundColor.blue > 80;
				if (isBrown) {
					groundType = "dirt";
				} else if (isBlue) {
					groundType = "water";
				}
			}
			if (isBrown) {
				FmodManager.PlaySoundOneShot(FmodSFX.PlayerStepDirt);
			} else if (isBlue) {
				FmodManager.PlaySoundOneShot(FmodSFX.PlayerStepWater);
			} else {
				FmodManager.PlaySoundOneShot(FmodSFX.PlayerStepGrass);
			}
			if (isBrown || isBlue) {
				var print = new Footprint(fx, fy, lastInputDir, groundColor, isBlue);
				if (effectsTarget != null) {
					effectsTarget.add(print);
				} else {
					state.add(print);
				}
			}
			if (isBrown) {
				for (_ in 0...12) {
					var dust = new FootDust(fx + FlxG.random.float(-3, 3), fy + FlxG.random.float(-1, 1), groundColor, false);
					if (effectsTarget != null) {
						effectsTarget.add(dust);
					} else {
						state.add(dust);
					}
				}
			} else if (isBlue) {
				for (_ in 0...10) {
					var dust = new FootDust(fx + FlxG.random.float(-3, 3), fy + FlxG.random.float(-1, 1), groundColor, true);
					if (effectsTarget != null) {
						effectsTarget.add(dust);
					} else {
						state.add(dust);
					}
				}
			}
		}

		if (castState == CATCH_ANIM && frameNumber == CATCH_RETRACT_FRAME && castBobber != null) {
			if (retractHasFish) {
				// Set up arc retract
				castStartPos = FlxPoint.get(castBobber.x, castBobber.y);
				var retract = getRetractTarget();
				castTarget = FlxPoint.get(retract.x, retract.y);
				retract.put();
				var dx = castTarget.x - castStartPos.x;
				var dy = castTarget.y - castStartPos.y;
				var dist = Math.sqrt(dx * dx + dy * dy);
				castFlightTime = if (dist > 0) dist / 188 else 0.01;
				castElapsed = 0;
				castBobber.velocity.set(0, 0);
			} else {
				var retract = getRetractTarget();
				var px = retract.x;
				var py = retract.y;
				retract.put();
				var dx = px - castBobber.x;
				var dy = py - castBobber.y;
				var dist = Math.sqrt(dx * dx + dy * dy);
				if (dist > 0) {
					castBobber.velocity.x = (dx / dist) * 188;
					castBobber.velocity.y = (dy / dist) * 188;
				}
			}
		}
	}

	function onAnimFinish(animName:String) {
		if (castState == CAST_ANIM) {
			castState = CASTING;
		} else if (castState == CATCH_ANIM) {
			if (castBobber != null) {
				castState = RETURNING;
			} else {
				castState = IDLE;
				frozen = false;
				playMovementAnim(true);
			}
		} else if (throwing) {
			throwing = false;
			frozen = false;
			playMovementAnim(true);
		}
	}

	function playMovementAnim(force:Bool = false) {
		// Determine if player is moving — check different sources depending on mode
		var moving = if (isRemote) {
			remoteServerVelX != 0 || remoteServerVelY != 0;
		} else if (playerState != null) {
			playerState.velocityX != 0 || playerState.velocityY != 0;
		} else {
			velocity.x != 0 || velocity.y != 0;
		};
		if (!force && moving == lastMoving && lastInputDir == lastAnimDir && !inShallowWater)
			return;

		lastMoving = moving;
		lastAnimDir = lastInputDir;

		var dirSuffix = getDirSuffix();
		var prefix = (inShallowWater || !moving) ? "stand_" : "run_";
		sendAnimUpdate(prefix + dirSuffix);
	}

	function sendAnimUpdate(animName:String, forceRestart:Bool = false) {
		onAnimUpdate.dispatch(animName, forceRestart);
	}

	public function setNetwork(session:String) {
		cleanupNetwork();

		sessionId = session;
		remoteTargetX = x;
		remoteTargetY = y;
		GameManager.ME.net.onPlayerChanged.add(handleChange);
	}

	private function handleChange(sesId:String, data:{state:PlayerState, ?prevX:Float, ?prevY:Float}):Void {
		if (sesId != sessionId) {
			return;
		}

		remoteTargetX = data.state.x;
		remoteTargetY = data.state.y;
		remoteServerVelX = data.state.velocityX;
		remoteServerVelY = data.state.velocityY;
		inShallowWater = data.state.inShallowWater;

		// Update facing direction: server velocity is most accurate; fall back to position delta
		if (remoteServerVelX != 0 || remoteServerVelY != 0) {
			var velPt = new FlxPoint(remoteServerVelX, remoteServerVelY);
			lastInputDir = Cardinal.closest(velPt);
		} else {
			var deltaPos = new FlxPoint();
			if (data.prevX != null) {
				deltaPos.x = data.state.x - data.prevX;
			}
			if (data.prevY != null) {
				deltaPos.y = data.state.y - data.prevY;
			}
			if (deltaPos.x != 0 || deltaPos.y != 0) {
				lastInputDir = Cardinal.closest(deltaPos);
			}
		}

		// Once the remote player stops (frozen during catch anim) then starts moving
		// again, their retract is done — clean up any lingering bobber
		if (castBobber != null && (castState == CATCH_ANIM || castState == RETURNING)) {
			var speedSq = data.state.velocityX * data.state.velocityX + data.state.velocityY * data.state.velocityY;
			if (speedSq < 100) { // < ~10px/s  — player is frozen/stationary
				remoteWasStationary = true;
			} else if (remoteWasStationary) { // was stationary, now moving → catch anim done
				state.remove(castBobber);
				castBobber.destroy();
				castBobber = null;
				castState = IDLE;
				playMovementAnim(true);
			}
		}
	}

	// Temp PlayerState for remote simulation — avoids allocation per frame
	var remoteSimState:schema.PlayerState;
	// Entity indices hit during the last simulation tick (for bush rustle etc.)
	public var lastHitEntityIndices:Array<Int> = [];

	function updateRemoteInterpolation() {
		// Freeze during cast/catch animations, same as local player
		if (castState == CAST_ANIM || castState == CASTING || castState == CATCH_ANIM || castState == RETURNING) {
			velocity.set(0, 0);
			return;
		}

		var dx = remoteTargetX - x;
		var dy = remoteTargetY - y;
		var distSq = dx * dx + dy * dy;
		var serverStopped = remoteServerVelX == 0 && remoteServerVelY == 0;

		if (distSq > REMOTE_TELEPORT_DIST_SQ) {
			setPosition(remoteTargetX, remoteTargetY);
			velocity.set(0, 0);
		} else if (serverStopped && distSq <= REMOTE_SNAP_DIST_SQ) {
			setPosition(remoteTargetX, remoteTargetY);
			velocity.set(0, 0);
		} else if (simulation != null) {
			// Use the shared Simulation to move with proper collision
			if (remoteSimState == null) {
				remoteSimState = new schema.PlayerState();
				remoteSimState.width = 16;
				remoteSimState.height = 8;
			}
			remoteSimState.x = x;
			remoteSimState.y = y;

			// Compute interpolation velocity
			var dist = Math.sqrt(distSq);
			var interpVx:Float = 0;
			var interpVy:Float = 0;
			if (dist > 0.5) {
				var corrSpeed = Math.min(dist * REMOTE_SPRING_K, REMOTE_MAX_CORRECTION);
				var corrVx = (dx / dist) * corrSpeed;
				var corrVy = (dy / dist) * corrSpeed;
				if (serverStopped) {
					interpVx = corrVx;
					interpVy = corrVy;
				} else {
					var errorWeight = Math.min(dist / REMOTE_BLEND_RANGE, 1.0);
					interpVx = remoteServerVelX + (corrVx - remoteServerVelX) * errorWeight;
					interpVy = remoteServerVelY + (corrVy - remoteServerVelY) * errorWeight;
				}
			}

			// Compute direction angle from velocity for the simulation input
			remoteSimState.speed = Math.sqrt(interpVx * interpVx + interpVy * interpVy);
			var dirAngle:Int = -1;
			if (remoteSimState.speed > 0.1) {
				dirAngle = Std.int(Math.atan2(interpVy, interpVx) * 180 / Math.PI);
				// atan2 gives -180..180 with 0=right; Simulation expects 0=up
				dirAngle = (dirAngle + 90 + 360) % 360;
			}

			var inp:PInput.P_Input = {seq: 0, dir: dirAngle, buttons: 0, elapsed: FlxG.elapsed};
			simulation.tickPlayer(remoteSimState, [inp], FlxG.elapsed);
			lastHitEntityIndices = simulation.hitEntityIndices;
			setPosition(remoteSimState.x, remoteSimState.y);
			velocity.set(0, 0);
			// Drive animation from simulation velocity
			remoteServerVelX = remoteSimState.velocityX;
			remoteServerVelY = remoteSimState.velocityY;
			if (remoteSimState.velocityX != 0 || remoteSimState.velocityY != 0) {
				var velPt = new flixel.math.FlxPoint(remoteSimState.velocityX, remoteSimState.velocityY);
				lastInputDir = Cardinal.closest(velPt);
			}
		} else {
			// Fallback: no simulation available, use velocity (old behavior)
			var dist = Math.sqrt(distSq);
			if (dist > 0.5) {
				var corrSpeed = Math.min(dist * REMOTE_SPRING_K, REMOTE_MAX_CORRECTION);
				velocity.x = (dx / dist) * corrSpeed;
				velocity.y = (dy / dist) * corrSpeed;
			} else {
				velocity.set(0, 0);
			}
		}

		if (!throwing && knockbackTimer <= 0) {
			playMovementAnim();
		}
	}

	override public function update(delta:Float) {
		super.update(delta);

		// drown recovery — hidden phase blocks everything
		if (drowned) {
			if (drownTimer > 0) {
				drownTimer -= delta;
				// emit smoke at the splash spot
				fireEmitTimer += delta;
				if (fireEmitTimer >= 0.05) {
					fireEmitTimer = 0;
					for (_ in 0...2) {
						var smoke = new ButtFire(drownReturnX + width / 2 + FlxG.random.float(-4, 4), drownReturnY + height / 2 + FlxG.random.float(-2, 2), FlxG.random.float(-0.5, 0.5), -1, true);
						state.add(smoke);
					}
				}
				if (drownTimer <= 0) {
					// respawn at water entry point
					setPosition(drownReturnX, drownReturnY);
					visible = true;
					frozen = false;
					fireEmitTimer = 0;
					drownBlinkTimer = DROWN_BLINK_RATE;
				}
				return;
			}
			// blink phase — player can move, just toggle visibility
			drownBlinkTimer -= delta;
			if (drownBlinkTimer <= 0) {
				drownBlinkTimer = DROWN_BLINK_RATE;
				visible = !visible;
				if (visible) {
					drownBlinksLeft--;
				}
				if (drownBlinksLeft <= 0) {
					visible = true;
					drowned = false;
				}
			}
			// fall through to normal update
		}

		// Run for both local and remote players
		updateCast(delta);
		updateFishingLine();
		updateRock(delta);

		// Hot mode timer and butt fire — run for both local and remote players
		if (hotModeActive) {
			// Only tick the timer for the local player — remote players deactivate via network signal
			if (!isRemote) {
				hotModeTimer -= delta;
				if (hotModeTimer <= 0) {
					hotModeActive = false;
					GameManager.ME.net.sendHotPepper(false);
				}
			}
			if (hotModeActive) {
				fireEmitTimer += delta;
				if (fireEmitTimer >= 0.03) {
					fireEmitTimer = 0;
					// Use the visual sprite center (not hitbox center, which is at the feet)
					var cx = x - offset.x + frameWidth / 2;
					var cy = y - offset.y + frameHeight / 2;
					var dirX:Float = 0;
					var dirY:Float = 0;
					// Offset fire origin to the player's butt. Left/right/up views
					// need cy -= 4 to align with the butt rather than the feet.
					switch (lastInputDir) {
						case N:
							cy += 2;
							dirY = 1;
						case S:
							cy -= 2;
							dirY = -1;
						case W:
							cx += 6;
							dirX = 1;
						case E:
							cx -= 6;
							dirX = -1;
						default:
							cy += 2;
							dirY = 1;
					}
					for (_ in 0...3) {
						var fire = new ButtFire(cx + FlxG.random.float(-2, 2), cy + FlxG.random.float(-1, 1), dirX, dirY);
						var effectsTarget:FlxGroup = groundEffectsGroup != null ? groundEffectsGroup : null;
						if (effectsTarget != null) {
							effectsTarget.add(fire);
						} else {
							state.add(fire);
						}
					}
				}
			}
		} else {
			fireEmitTimer = 0;
		}

		// Tick knockback timer (both local and remote)
		if (knockbackTimer > 0) {
			knockbackTimer -= delta;
		}

		if (isRemote) {
			updateRemoteInterpolation();
			return;
		}

		if (FlxG.keys.justPressed.Q) {
			skinIndex = (skinIndex - 1 + SKINS.length) % SKINS.length;
			swapSkin();
		} else if (FlxG.keys.justPressed.E) {
			skinIndex = (skinIndex + 1) % SKINS.length;
			swapSkin();
		}

		if (FlxG.keys.justPressed.P || FlxG.keys.justPressed.NUMPADTHREE) {
			if (hotModeActive) {
				deactivateHotMode();
			} else {
				activateHotMode(99);
			}
		}

		// Gather input — always, even when frozen (simulation needs continuous seq numbers)
		#if bot
		var inputDir:Cardinal = NONE;
		#else
		var inputDir = InputCalculator.getInputCardinal(playerNum);
		#end
		if (!frozen && (inputDir == N || inputDir == S || inputDir == E || inputDir == W)) {
			lastInputDir = inputDir;
		}

		if (simulation != null && playerState != null) {
			// Server-authoritative mode: send movement input, predict locally
			var moveDir = inputDir;
			// Hot mode: force running in last direction even without input
			if (hotModeActive && moveDir == NONE && lastInputDir != NONE) {
				moveDir = lastInputDir;
			}
			var dirAngle = if (frozen) -1 else cardinalToAngle(moveDir);
			// Hot mode speed boost (1.5x)
			playerState.speed = if (hotModeActive) 150 else 100;
			var inp:PInput.P_Input = {
				seq: ++inputSeq,
				dir: dirAngle,
				buttons: 0,
				elapsed: delta
			};
			GameManager.ME.net.sendInput(inp);
			if (GameManager.ME.net.isLocal()) {
				// Local mode: GameLogic is the authority, just read position after it ticks
				setPosition(playerState.x, playerState.y);
				lastHitEntityIndices = simulation.hitEntityIndices;
			} else {
				// Networked mode: predict locally, reconcile from server later
				pendingInputs.push(inp);
				var blockFlags = if (hotModeActive || inventory.hasWaders()) CollisionMap.FLAG_SOLID else 0;
				simulation.tickPlayer(playerState, [inp], delta, blockFlags);
				lastHitEntityIndices = simulation.hitEntityIndices;
				setPosition(playerState.x, playerState.y);
			}
			velocity.set(0, 0);
		} else if (frozen) {
			velocity.set();
		} else {
			// Local/offline mode: direct velocity (existing behavior)
			var moveSpeed = inShallowWater ? speed * 0.5 : speed;
			if (hotModeActive) {
				var moveDir = if (inputDir != NONE) inputDir else lastInputDir;
				if (moveDir != NONE) {
					moveDir.asVector(velocity).normalize().scale(moveSpeed * 1.5);
				}
			} else {
				if (inputDir != NONE) {
					inputDir.asVector(velocity).normalize().scale(moveSpeed);
				} else {
					velocity.set();
				}
			}
		}

		// Only update movement animations when fully idle (not casting, catching, throwing, or in knockback)
		if (castState == IDLE && !throwing && knockbackTimer <= 0) {
			playMovementAnim();
		}

		// Fire rocket with C key
		if (!frozen && !throwing && castState == IDLE && FlxG.keys.justPressed.C && inventory.has(Rocket)) {
			#if !db inventory.remove(Rocket); #end
			// Convert facing to direction index: 0=up, 1=right, 2=down, 3=left
			var dirIdx = switch (lastInputDir) {
				case N: 0;
				case E: 1;
				case S: 2;
				case W: 3;
				case NE: 1;
				case SE: 1;
				case NW: 3;
				case SW: 3;
				default: 2; // default down
			};
			GameManager.ME.net.sendMessage("fire_rocket", {dir: dirIdx, knockback: true});
			// Server applies knockback; camera shake is client-only cosmetic
			FlxG.camera.shake(0.012, 0.2);
		}

		// Throw hunger potion with B button (priority over rock, same arc)
		if (!frozen && !throwing && castState == IDLE && SimpleController.just_pressed(B) && inventory.has(HungerPotion)) {
			#if !db inventory.remove(HungerPotion); #end
			throwingPotion = true;
			throwingBait = false;
			throwingBigRock = false;
			throwing = true;
			frozen = true;
			sendAnimUpdate("throw_" + getDirSuffix(), true);
			var dir = lastInputDir.asVector();
			var rawX = x + dir.x * 96 + 4;
			var rawY = y + dir.y * 96 - 8;
			var bounds = FlxG.worldBounds;
			rockTarget = FlxPoint.get(Math.max(bounds.left, Math.min(bounds.right, rawX)), Math.max(bounds.top, Math.min(bounds.bottom, rawY)));
			dir.put();
			GameManager.ME.net.sendMessage("throw_potion", {
				targetX: rockTarget.x,
				targetY: rockTarget.y,
				dir: getDirSuffix()
			});
		}

		// Throw fish bait with B button (same arc as rock)
		if (!frozen && !throwing && castState == IDLE && SimpleController.just_pressed(B) && inventory.has(FishBait)) {
			#if !db inventory.remove(FishBait); #end
			throwingBait = true;
			throwingPotion = false;
			throwingBigRock = false;
			throwing = true;
			frozen = true;
			sendAnimUpdate("throw_" + getDirSuffix(), true);
			var dir = lastInputDir.asVector();
			var rawX = x + dir.x * 96 + 4;
			var rawY = y + dir.y * 96 - 8;
			var bounds = FlxG.worldBounds;
			rockTarget = FlxPoint.get(Math.max(bounds.left, Math.min(bounds.right, rawX)), Math.max(bounds.top, Math.min(bounds.bottom, rawY)));
			dir.put();
			GameManager.ME.net.sendMessage("throw_bait", {
				targetX: rockTarget.x,
				targetY: rockTarget.y,
				dir: getDirSuffix()
			});
		}

		// Rock throw: two-phase aiming system
		// Phase 1: Press B to enter aiming mode — player freezes, reticle moves freely
		if (!frozen && !throwing && !aimingRock && castState == IDLE && SimpleController.just_pressed(B) && (inventory.has(BigRock) || inventory.has(Rock))) {
			aimingRock = true;
			frozen = true;
			// Start reticle at current facing position (96px away)
			var dir = lastInputDir.asVector();
			aimReticleX = x + dir.x * 96 + 4;
			aimReticleY = y + dir.y * 96 - 8;
			dir.put();
			if (reticle != null) {
				reticle.scale.set(3, 3);
				reticle.color = 0xFFFF0000; // red
				reticle.setPosition(aimReticleX - reticle.width / 2, aimReticleY - reticle.height / 2);
			}
			// Draw blast radius circle
			var isBig = inventory.has(BigRock);
			var radius = if (isBig) 160 else 80;
			var diam = radius * 2;
			blastRadiusSprite = new FlxSprite();
			blastRadiusSprite.makeGraphic(diam, diam, 0x00000000);
			// Draw circle outline
			var cx = radius;
			var cy = radius;
			for (angle in 0...360) {
				var rad = angle * Math.PI / 180;
				var px = Std.int(cx + Math.cos(rad) * (radius - 1));
				var py = Std.int(cy + Math.sin(rad) * (radius - 1));
				if (px >= 0 && px < diam && py >= 0 && py < diam) {
					blastRadiusSprite.pixels.setPixel32(px, py, 0x44FF0000);
				}
				// thicker line
				var px2 = Std.int(cx + Math.cos(rad) * (radius - 2));
				var py2 = Std.int(cy + Math.sin(rad) * (radius - 2));
				if (px2 >= 0 && px2 < diam && py2 >= 0 && py2 < diam) {
					blastRadiusSprite.pixels.setPixel32(px2, py2, 0x44FF0000);
				}
			}
			blastRadiusSprite.pixels.lock();
			blastRadiusSprite.pixels.unlock();
			blastRadiusSprite.dirty = true;
			blastRadiusSprite.setPosition(aimReticleX - radius, aimReticleY - radius);
			state.add(blastRadiusSprite);
		}

		// Phase 2: While aiming, move reticle with directional input (skip first frame to avoid double-fire)
		else if (aimingRock && !throwing) {
			var aimDx:Float = 0;
			var aimDy:Float = 0;
			if (SimpleController.pressed(LEFT)) { aimDx -= 1; }
			if (SimpleController.pressed(RIGHT)) { aimDx += 1; }
			if (SimpleController.pressed(UP)) { aimDy -= 1; }
			if (SimpleController.pressed(DOWN)) { aimDy += 1; }
			// Normalize diagonal
			if (aimDx != 0 && aimDy != 0) {
				aimDx *= 0.7071;
				aimDy *= 0.7071;
			}
			aimReticleX += aimDx * AIM_RETICLE_SPEED * delta;
			aimReticleY += aimDy * AIM_RETICLE_SPEED * delta;
			// Clamp to world bounds
			var bounds = FlxG.worldBounds;
			aimReticleX = Math.max(bounds.left, Math.min(bounds.right, aimReticleX));
			aimReticleY = Math.max(bounds.top, Math.min(bounds.bottom, aimReticleY));
			// Position reticle and blast radius at aim point
			if (reticle != null) {
				reticle.setPosition(aimReticleX - reticle.width / 2, aimReticleY - reticle.height / 2);
			}
			if (blastRadiusSprite != null) {
				blastRadiusSprite.setPosition(aimReticleX - blastRadiusSprite.width / 2, aimReticleY - blastRadiusSprite.height / 2);
			}

			// Press B again to throw
			if (SimpleController.just_pressed(B)) {
				if (inventory.has(BigRock)) {
					#if !db inventory.remove(BigRock); #end
					throwingBigRock = true;
				} else {
					#if !db inventory.remove(Rock); #end
					throwingBigRock = false;
				}
				throwingPotion = false;
				throwingBait = false;
				throwing = true;
				aimingRock = false;
				// Face toward the target
				var tdx = aimReticleX - x;
				var tdy = aimReticleY - y;
				if (Math.abs(tdx) > Math.abs(tdy)) {
					lastInputDir = if (tdx > 0) Cardinal.E else Cardinal.W;
				} else {
					lastInputDir = if (tdy > 0) Cardinal.S else Cardinal.N;
				}
				sendAnimUpdate("throw_" + getDirSuffix(), true);
				rockTarget = FlxPoint.get(aimReticleX, aimReticleY);
				GameManager.ME.net.sendMessage("throw_rock", {
					targetX: rockTarget.x,
					targetY: rockTarget.y,
					big: throwingBigRock,
					dir: getDirSuffix()
				});
				if (reticle != null) {
					reticle.scale.set(1, 1);
					reticle.color = 0xFFFFFFFF; // reset to white
				}
				if (blastRadiusSprite != null) {
					state.remove(blastRadiusSprite);
					blastRadiusSprite.destroy();
					blastRadiusSprite = null;
				}
			}

			// Press A to cancel aiming
			if (SimpleController.just_pressed(A)) {
				aimingRock = false;
				frozen = false;
				if (reticle != null) {
					reticle.scale.set(1, 1);
					reticle.color = 0xFFFFFFFF;
				}
				if (blastRadiusSprite != null) {
					state.remove(blastRadiusSprite);
					blastRadiusSprite.destroy();
					blastRadiusSprite = null;
				}
			}
		}

		if (!aimingRock) {
			updateReticle();
		}

		clampToWorldBounds();
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

	function getRodTipPos():FlxPoint {
		var wy = inShallowWater ? SHALLOW_WATER_OFFSET : 0.0;
		if (castState == CAST_ANIM || castState == CASTING) {
			var frame = animation.curAnim != null ? animation.curAnim.curFrame : 0;
			if (castState == CAST_ANIM && frame == CAST_LAUNCH_FRAME) {
				return switch (castDirSuffix) {
					case "right": FlxPoint.get(x + 12, y - 12 + wy);
					case "left": FlxPoint.get(x + 2, y - 12 + wy);
					case "down": FlxPoint.get(x, y - 8 + wy);
					case "up": FlxPoint.get(x + 12, y - 8 + wy);
					default: null;
				};
			}
			return switch (castDirSuffix) {
				case "down": FlxPoint.get(x + 10, y + 12 + wy);
				case "right": FlxPoint.get(x + 30, y - 10 + wy);
				case "up": FlxPoint.get(x + 3, y - 16 + wy);
				case "left": FlxPoint.get(x - 15, y - 10 + wy);
				default: FlxPoint.get(x + 8, y - 4 + wy);
			};
		} else if (castState == CATCH_ANIM || castState == RETURNING) {
			var frame = animation.curAnim != null ? animation.curAnim.curFrame : 0;
			return switch (castDirSuffix) {
				case "down":
					if (frame == 0) FlxPoint.get(x + 10,
						y + 12 + wy) else if (frame == 1) FlxPoint.get(x + 8, y - 9 + wy) else FlxPoint.get(x - 1, y - 20 + wy);
				case "right":
					if (frame == 0) FlxPoint.get(x + 30,
						y - 10 + wy) else if (frame == 1) FlxPoint.get(x + 14, y - 16 + wy) else FlxPoint.get(x - 6, y - 18 + wy);
				case "up":
					if (frame == 0) FlxPoint.get(x + 3,
						y - 18 + wy) else if (frame == 1) FlxPoint.get(x + 13, y - 20 + wy) else FlxPoint.get(x + 19, y - 20 + wy);
				case "left":
					if (frame == 0) FlxPoint.get(x - 15,
						y - 10 + wy) else if (frame == 1) FlxPoint.get(x + 1, y - 16 + wy) else FlxPoint.get(x + 21, y - 18 + wy);
				default: FlxPoint.get(x + 8, y - 4 + wy);
			};
		} else {
			return switch (castDirSuffix) {
				case "down": FlxPoint.get(x + 1, y - 13 + wy);
				case "right": FlxPoint.get(x + 15, y - 17 + wy);
				case "up": FlxPoint.get(x + 11, y - 18 + wy);
				case "left": FlxPoint.get(x + 0, y - 17 + wy);
				default: FlxPoint.get(x + 8, y - 4 + wy);
			};
		}
	}

	function updateFishingLine() {
		if (castBobber == null) {
			fishingLine.visible = false;
			return;
		}

		var tip = getRodTipPos();
		var bobCX = castBobber.x + 4;
		var bobCY = castBobber.y + 4;

		var minX = Math.floor(Math.min(tip.x, bobCX)) - 1;
		var minY = Math.floor(Math.min(tip.y, bobCY)) - 1;
		var w = Math.ceil(Math.abs(tip.x - bobCX)) + 3;
		var h = Math.ceil(Math.abs(tip.y - bobCY)) + 3;
		if (w < 2)
			w = 2;
		if (h < 2)
			h = 2;

		// Add sag room for left/right curves
		var sag = (castDirSuffix == "left" || castDirSuffix == "right") ? 10 : 0;
		var minY2 = minY - 1;
		var h2 = h + sag;

		fishingLine.setPosition(minX, minY2);
		fishingLine.makeGraphic(w, h2, FlxColor.TRANSPARENT, true);

		var lx0 = tip.x - minX;
		var ly0 = tip.y - minY2;
		var lx1 = bobCX - minX;
		var ly1 = bobCY - minY2;

		if (sag > 0) {
			// Cubic Bezier with downward sag — arrives at bobber horizontally
			var c1x = (lx0 + lx1) / 2;
			var c1y = (ly0 + ly1) / 2 + sag;
			var c2x = lx1 - (lx1 - lx0) * 0.15;
			var c2y = ly1;
			var steps = Std.int(Math.max(Math.abs(lx1 - lx0), Math.abs(ly1 - ly0))) * 2 + 10;
			var prevPx = Math.round(lx0);
			var prevPy = Math.round(ly0);
			if (prevPx >= 0 && prevPx < w && prevPy >= 0 && prevPy < h2)
				fishingLine.pixels.setPixel32(prevPx, prevPy, FlxColor.WHITE);
			for (i in 1...steps + 1) {
				var t = i / steps;
				var invT = 1 - t;
				var px = Math.round(invT * invT * invT * lx0 + 3 * invT * invT * t * c1x + 3 * invT * t * t * c2x + t * t * t * lx1);
				var py = Math.round(invT * invT * invT * ly0 + 3 * invT * invT * t * c1y + 3 * invT * t * t * c2y + t * t * t * ly1);
				if (px != prevPx || py != prevPy) {
					if (px >= 0 && px < w && py >= 0 && py < h2)
						fishingLine.pixels.setPixel32(px, py, FlxColor.WHITE);
					prevPx = px;
					prevPy = py;
				}
			}
		} else {
			// Bresenham line for crisp pixels (up/down)
			var x0 = Math.round(lx0);
			var y0 = Math.round(ly0);
			var x1 = Math.round(lx1);
			var y1 = Math.round(ly1);
			var dx = Std.int(Math.abs(x1 - x0));
			var dy = -Std.int(Math.abs(y1 - y0));
			var sx = x0 < x1 ? 1 : -1;
			var sy = y0 < y1 ? 1 : -1;
			var err = dx + dy;
			while (true) {
				if (x0 >= 0 && x0 < w && y0 >= 0 && y0 < h2)
					fishingLine.pixels.setPixel32(x0, y0, FlxColor.WHITE);
				if (x0 == x1 && y0 == y1)
					break;
				var e2 = 2 * err;
				if (e2 >= dy) {
					err += dy;
					x0 += sx;
				}
				if (e2 <= dx) {
					err += dx;
					y0 += sy;
				}
			}
		}
		fishingLine.dirty = true;
		fishingLine.visible = true;
		tip.put();
	}

	function launchRock() {
		TODO.sfx("rock_throw");
		var rockWy = inShallowWater ? SHALLOW_WATER_OFFSET : 0.0;
		rockSprite = if (throwingBait && makeBait != null) {
			makeBait(x + 4, y - 8 + rockWy);
		} else if (throwingPotion && makePotion != null) {
			makePotion(x + 4, y - 8 + rockWy);
		} else if (makeRock != null) {
			makeRock(x + 4, y - 8 + rockWy, throwingBigRock);
		} else {
			new Rock(x + 4, y - 8 + rockWy, throwingBigRock);
		};
		rockStartPos = FlxPoint.get(rockSprite.x, rockSprite.y);
		var dx = rockTarget.x - rockStartPos.x;
		var dy = rockTarget.y - rockStartPos.y;
		var dist = Math.sqrt(dx * dx + dy * dy);
		rockFlightTime = if (dist > 0) dist / 200 else 0.01;
		rockElapsed = 0;
		state.add(rockSprite);
	}

	public function remoteThrowRock(targetX:Float, targetY:Float, big:Bool, dir:String) {
		throwingBigRock = big;
		lastInputDir = switch (dir) {
			case "up": N;
			case "down": S;
			case "left": W;
			case "right": E;
			default: S;
		};
		if (rockTarget != null) {
			rockTarget.put();
		}
		rockTarget = FlxPoint.get(targetX, targetY);
		throwing = true;
		sendAnimUpdate("throw_" + dir, true);
	}

	function updateRock(elapsed:Float) {
		if (rockSprite == null)
			return;

		rockElapsed += elapsed;
		var t = Math.min(1.0, rockElapsed / rockFlightTime);

		var groundX = rockStartPos.x + (rockTarget.x - rockStartPos.x) * t;
		var groundY = rockStartPos.y + (rockTarget.y - rockStartPos.y) * t;

		var totalDist = Math.sqrt((rockTarget.x - rockStartPos.x) * (rockTarget.x - rockStartPos.x)
			+ (rockTarget.y - rockStartPos.y) * (rockTarget.y - rockStartPos.y));
		var arcHeight = Math.min(totalDist * 0.5, 64);
		var arcOffset = arcHeight * 4 * t * (1 - t);

		rockSprite.setPosition(groundX, groundY - arcOffset);

		if (t >= 1.0) {
			var landX = rockTarget.x;
			var landY = rockTarget.y;
			var landed = rockSprite;
			state.remove(rockSprite);
			rockSprite = null;
			rockTarget.put();
			rockTarget = null;
			rockStartPos.put();
			rockStartPos = null;
			landed.resolveThrow(landX, landY);
			landed.destroy();
		}
	}

	function spawnBobberArc() {
		castBobber = new FlxSprite();
		Aseprite.loadAllAnimations(castBobber, AssetPaths.bobber__json);
		castBobber.animation.play(BOBBERS[skinIndex]);
		var tip = getRodTipPos();
		castBobber.setPosition(tip.x, tip.y);
		tip.put();
		castStartPos = FlxPoint.get(castBobber.x, castBobber.y);
		var dx = castTarget.x - castStartPos.x;
		var dy = castTarget.y - castStartPos.y;
		var dist = Math.sqrt(dx * dx + dy * dy);
		castFlightTime = if (dist > 0) dist / 150 else 0.01;
		castElapsed = 0;
		state.add(castBobber);
	}

	function launchBobber() {
		var reticleDir = lastInputDir.asVector();
		var castDist = castPower * 96;
		var targetX = x + reticleDir.x * castDist + 4;
		var targetY = y + reticleDir.y * castDist - 8;
		reticleDir.put();
		castTarget = FlxPoint.get(targetX, targetY);
		// tell server the cast details — server validates and broadcasts to other clients
		GameManager.ME.net.sendMessage("cast_release", {power: castPower, dir: getDirSuffix(), targetX: castTarget.x, targetY: castTarget.y});
		FmodManager.PlaySoundOneShot(FmodSFX.FishingRodCast);
		spawnBobberArc();
	}

	/** Updates the bobber position along an arc. Returns true when it has arrived. */
	function updateCastArc(elapsed:Float):Bool {
		if (castBobber == null || castTarget == null || castStartPos == null)
			return false;

		castElapsed += elapsed;
		var t = Math.min(1.0, castElapsed / castFlightTime);

		var groundX = castStartPos.x + (castTarget.x - castStartPos.x) * t;
		var groundY = castStartPos.y + (castTarget.y - castStartPos.y) * t;

		var dx = castTarget.x - castStartPos.x;
		var dy = castTarget.y - castStartPos.y;
		var totalDist = Math.sqrt(dx * dx + dy * dy);
		var arcHeight = Math.min(totalDist * 0.3, 48);
		var arcOffset = arcHeight * 4 * t * (1 - t);

		castBobber.setPosition(groundX, groundY - arcOffset);

		return t >= 1.0;
	}

	function startCast() {
		castState = CAST_ANIM;
		castDirSuffix = getDirSuffix();
		sendAnimUpdate("cast_" + castDirSuffix, true);
	}

	public function remoteStartCharge(dir:String) {
		castDirSuffix = dir;
		lastInputDir = switch (dir) {
			case "up": N;
			case "down": S;
			case "left": W;
			case "right": E;
			default: S;
		};
		castState = CHARGING;
		frozen = true;
		sendAnimUpdate("cast_" + castDirSuffix, false);
		if (animation.curAnim != null) {
			animation.curAnim.pause();
		}
	}

	public function remoteStartCast(targetX:Float, targetY:Float, dir:String) {
		// Clean up any bobber still retracting from a previous catch
		if (castBobber != null) {
			state.remove(castBobber);
			castBobber.destroy();
			castBobber = null;
		}
		castDirSuffix = dir;
		lastInputDir = switch (dir) {
			case "up": N;
			case "down": S;
			case "left": W;
			case "right": E;
			default: S;
		};
		if (castTarget != null) {
			castTarget.put();
		}
		castTarget = FlxPoint.get(targetX, targetY);
		castState = CAST_ANIM;
		sendAnimUpdate("cast_" + castDirSuffix, true);
	}
	function updateCast(elapsed:Float) {
		if (!isRemote) {
			switch (castState) {
				// --- START: Local player handling
				case IDLE:
					if (frozen) { /* skip input while frozen (e.g. typing) */ }
					else if (SimpleController.just_pressed(A)) {
						castState = CHARGING;
						frozen = true;
						castDirSuffix = getDirSuffix();
						sendAnimUpdate("cast_" + castDirSuffix, false);
						if (animation.curAnim != null) {
							animation.curAnim.pause();
						}
						castPower = 0;
						castPowerDir = 1;
						var barWy = inShallowWater ? SHALLOW_WATER_OFFSET : 0.0;
						powerBarBg.setPosition(x - 8, y + 8 + barWy);
						powerBarFill.setPosition(x - 8, y + 8 + barWy);
						powerBarBg.visible = true;
						powerBarFill.visible = true;
						powerBarFill.scale.x = 0;
						// tell server we started charging
						GameManager.ME.net.sendMessage("cast_start", {dir: castDirSuffix});
					}
				case CHARGING:
					castPower += castPowerDir * elapsed * 2.0;
					if (castPower >= 1) {
						castPower = 1;
						castPowerDir = -1;
					} else if (castPower <= 0) {
						castPower = 0;
						castPowerDir = 1;
					}
					powerBarFill.scale.x = castPower;
					var barWy = inShallowWater ? SHALLOW_WATER_OFFSET : 0.0;
					powerBarBg.setPosition(x - 8, y + 8 + barWy);
					powerBarFill.setPosition(x - 8, y + 8 + barWy);

					if (SimpleController.just_released(A)) {
						powerBarBg.visible = false;
						powerBarFill.visible = false;

						if (castPower < 0.05) {
							castState = IDLE;
							frozen = false;
							playMovementAnim(true);
							GameManager.ME.net.sendMessage("cast_cancel", {});
						} else {
							startCast();
						}
					}
				case CASTING:
					if (SimpleController.just_pressed(A)) {
						catchFish();
					}
				case LANDED:
					if (SimpleController.just_pressed(A)
						|| SimpleController.pressed(UP) || SimpleController.pressed(DOWN)
						|| SimpleController.pressed(LEFT) || SimpleController.pressed(RIGHT)) {
						catchFish();
					}
				default:
					// nothing to do
			}
		}

		// --- START: Used for both local and remote players
		switch (castState) {
			case CASTING:
				// Arc advances and lands for both local and remote players
				if (updateCastArc(elapsed)) {
					castBobber.setPosition(castTarget.x, castTarget.y);
					if (castStartPos != null) {
						castStartPos.put();
						castStartPos = null;
					}
					castState = LANDED;
					frozen = true;
					playMovementAnim(true);
					TODO.sfx("bobber_land");
					if (onBobberLanded != null) {
						var mid = castBobber.getMidpoint();
						onBobberLanded(mid.x, mid.y);
						mid.put();
					}
					// Tell server where the bobber landed so fish AI can detect it
					if (!isRemote) {
						var mid = castBobber.getMidpoint();
						GameManager.ME.net.sendMessage("bobber_landed", {x: mid.x, y: mid.y});
						mid.put();
					}
				}
			case CAST_ANIM:
				// TODO: We can
				// Arc the bobber toward the target; clamp if it arrives during the animation.
				if (updateCastArc(elapsed)) {
					castBobber.setPosition(castTarget.x, castTarget.y);
				}
			case CATCH_ANIM:
				// Bobber retract started by frame event, check for arrival
				if (castBobber != null) {
					if (retractHasFish && castTarget != null) {
						if (updateCastArc(elapsed)) {
							state.remove(castBobber);
							castBobber.destroy();
							castBobber = null;
							if (onFishDelivered != null)
								onFishDelivered();
						}
					} else {
						var retract = getRetractTarget();
						var px = retract.x;
						var py = retract.y;
						retract.put();
						var dx = px - castBobber.x;
						var dy = py - castBobber.y;
						var dist = Math.sqrt(dx * dx + dy * dy);
						if (dist < 4) {
							state.remove(castBobber);
							castBobber.destroy();
							castBobber = null;
						}
					}
				}
			case RETURNING:
				if (castBobber != null) {
					if (retractHasFish && castTarget != null) {
						if (updateCastArc(elapsed)) {
							state.remove(castBobber);
							castBobber.destroy();
							castBobber = null;
							castState = IDLE;
							frozen = false;
							playMovementAnim(true);
							if (onFishDelivered != null)
								onFishDelivered();
						}
					} else {
						var retract = getRetractTarget();
						var px = retract.x;
						var py = retract.y;
						retract.put();
						var dx = px - castBobber.x;
						var dy = py - castBobber.y;
						var dist = Math.sqrt(dx * dx + dy * dy);
						if (dist < 4) {
							state.remove(castBobber);
							castBobber.destroy();
							castBobber = null;
							castState = IDLE;
							frozen = false;
							playMovementAnim(true);
						} else {
							castBobber.velocity.x = (dx / dist) * 188;
							castBobber.velocity.y = (dy / dist) * 188;
						}
					}
				}
			default:
				// nothing to do
		}
	}

	public function clearPendingInputs() {
		pendingInputs = [];
	}

	public function isCasting():Bool {
		return castState != IDLE;
	}

	public function isBobberLanded():Bool {
		return castState == LANDED && castBobber != null;
	}

	public function catchFish(hasFish:Bool = false, catcherId:String = null, fishId:String = null, fishType:Int = 0) {
		if (castState == LANDED || castState == CASTING) {
			if (!isRemote) {
				if (!hasFish) {
					GameManager.ME.net.sendLinePulled();
				}
				// Tell server to unfreeze player and clear bobber position
				GameManager.ME.net.sendMessage("cast_retract", {});
				GameManager.ME.net.sendMessage("bobber_retracted", {});
			}
			if (hasFish) {
				TODO.sfx("fish_caught");
			} else {
				TODO.sfx("reel_in");
			}
			castState = CATCH_ANIM;
			if (isRemote) {
				remoteWasStationary = false;
			}
			frozen = true;
			retractHasFish = hasFish;
			if (castTarget != null) {
				castTarget.put();
				castTarget = null;
			}
			if (castStartPos != null) {
				castStartPos.put();
				castStartPos = null;
			}
			if (castBobber != null) {
				castBobber.velocity.set(0, 0);
				if (hasFish) {
					caughtFishSpriteIndex = fishType;
					caughtFishLengthCm = FishTypes.randomLength(fishType);
					castBobber.loadGraphic("assets/aseprite/fish.png", true, 32, 32);
					castBobber.animation.add("fish", [caughtFishSpriteIndex]);
					castBobber.animation.play("fish");
				}
			}
			sendAnimUpdate("catch_" + castDirSuffix, true);
		}
	}

	static var ONE_SHOT_PREFIXES:Array<String> = ["cast_", "throw_", "catch_"];

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

	public function activateHotMode(duration:Float = 3.0) {
		if (!hotModeActive) {
			hotModeActive = true;
			hotModeTimer = duration;
			TODO.sfx("hot_mode_activate");

			if (!isRemote) {
				GameManager.ME.net.sendHotPepper(true);
			}

		}
	}

	public function deactivateHotMode() {
		if (hotModeActive) {
			hotModeActive = false;

			if (!isRemote) {
				GameManager.ME.net.sendHotPepper(false);
			}

		}
	}

	public function drown(?drownX:Float, ?drownY:Float) {
		if (drowned) {
			return;
		}
		drowned = true;
		drownReturnX = drownX != null ? drownX : x;
		drownReturnY = drownY != null ? drownY : y;
		deactivateHotMode();
		frozen = true;
		visible = false;
		velocity.set();
		drownTimer = DROWN_HIDE_DURATION;
		drownBlinksLeft = DROWN_BLINK_COUNT;
		drownBlinkTimer = 0;
		FmodManager.PlaySoundOneShot(FmodSFX.RockSplash);
	}

	public function pickupItem(item:InventoryItem):Bool {
		var added = inventory.add(item);
		if (added) {
			FmodManager.PlaySoundOneShot(FmodSFX.ItemCollect);
		}
		return added;
	}

	function getDirSuffix():String {
		return switch (lastInputDir) {
			case N, NE, NW: "up";
			case S, SE, SW: "down";
			case W: "left";
			case E: "right";
			default: "down";
		};
	}

	function getRetractTarget():FlxPoint {
		var wy = inShallowWater ? SHALLOW_WATER_OFFSET : 0.0;
		return switch (castDirSuffix) {
			case "right": FlxPoint.get(x + 8, y - 14 + wy);
			case "left": FlxPoint.get(x + 8, y - 14 + wy);
			case "down": FlxPoint.get(x, y - 8 + wy);
			case "up": FlxPoint.get(x + 12, y - 8 + wy);
			default: FlxPoint.get(x + 4, y - 8 + wy);
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

	public function cancelAllActions() {
		// Cancel casting and clean up bobber
		if (castBobber != null) {
			state.remove(castBobber);
			castBobber.destroy();
			castBobber = null;
		}
		if (castTarget != null) {
			castTarget.put();
			castTarget = null;
		}
		if (castStartPos != null) {
			castStartPos.put();
			castStartPos = null;
		}
		castState = IDLE;
		powerBarBg.visible = false;
		powerBarFill.visible = false;

		// Cancel throwing
		throwing = false;
		if (rockTarget != null) {
			rockTarget.put();
			rockTarget = null;
		}

		frozen = false;
		velocity.set(0, 0);
	}

	public function reconcileFromServer(serverState:schema.PlayerState) {
		var ack = serverState.lastProcessedSeq;
		// drop all inputs the server has already processed
		while (pendingInputs.length > 0 && pendingInputs[0].seq <= ack) {
			pendingInputs.shift();
		}
		// snap to server-authoritative position and replay unacked inputs
		playerState.x = serverState.x;
		playerState.y = serverState.y;
		playerState.velocityX = serverState.velocityX;
		playerState.velocityY = serverState.velocityY;
		if (simulation != null) {
			var blockFlags = if (hotModeActive || inventory.hasWaders()) CollisionMap.FLAG_SOLID else 0;
			for (inp in pendingInputs) {
				simulation.tickPlayer(playerState, [inp], inp.elapsed, blockFlags);
			}
		}
		setPosition(playerState.x, playerState.y);
	}

	private function cleanupNetwork() {
		GameManager.ME.net.onPlayerChanged.remove(handleChange);
	}
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
