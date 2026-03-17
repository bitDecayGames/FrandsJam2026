package states;

import input.SimpleController;
import bitdecay.flixel.debug.DebugSuite;
import schema.GameState;
import schema.GameState.P_Input;
import schema.PlayerState;
import input.InputCalculator;
import bitdecay.flixel.spacial.Cardinal;
import io.colyseus.Room;
import io.colyseus.serializer.schema.Callbacks;
import flixel.math.FlxPoint;
import flixel.util.FlxColor;
import flixel.FlxSprite;
import schema.FishState;
import net.NetworkManager;
import net.NetworkedState;
import net.NetworkedState.PlayerClientState;
import managers.RoundManager;
import debug.DebugLayers;
import bitdecay.flixel.debug.tools.draw.DebugDraw;
import todo.TODO;
import flixel.group.FlxGroup;
import flixel.math.FlxRect;
import flixel.group.FlxGroup.FlxTypedGroup;
import entities.CameraTransition;
import entities.FishSpawner;
import entities.WaterFish;
import entities.Rock;
import entities.GroundFishGroup;
import entities.Inventory.InventoryItem;
import entities.RockGroup;
import entities.PepperPickup;
import entities.WadersPickup;
import entities.Worm;
import levels.ldtk.BDTilemap;
import Ldtk.LdtkProject;
import Ldtk.Enum_TileTags;
import levels.ldtk.Level;
import entities.Bush;
import entities.CloudShadow;
import entities.Player;
import entities.Shop;
import events.gen.Event;
import events.EventBus;
import flixel.FlxG;
import flixel.addons.transition.FlxTransitionableState;
import ui.FlashingText;
import ui.InventoryHUD;
import ui.ScoreHUD;
import flixel.text.FlxText;

using states.FlxStateExt;

class PlayState extends FlxTransitionableState {
	static inline var REMOTE_TELEPORT_DIST_SQ:Float = 128 * 128;
	static inline var REMOTE_SPRING_K:Float = 8.0;

	var player:Player;

	// Network things
	var colyRoom:Room<GameState> = null;
	var remotePlayers:Map<String, Player> = new Map();
	var remoteFish:Map<String, WaterFish> = new Map();

	// A map of IDs to a NetworkState<ServerState, ClientState>
	var playerNetworkedStates:Map<String, NetworkedState<PlayerState, PlayerState>> = new Map();

	// Client-side prediction
	var simulation:Simulation;
	// var clientPlayerState:PlayerState;
	// var serverPlayerState:PlayerState;
	var lastServerPos = FlxRect.get();
	var pendingInputs:Array<P_Input> = [];
	var inputSeq:Int = 0;

	var midGroundGroup = new FlxGroup();
	var ySortGroup = new FlxGroup();
	var bushGroup = new FlxTypedGroup<Bush>();
	var fishSpawner:FishSpawner;
	var rockGroup:RockGroup;
	var groundFishGroup:GroundFishGroup;
	var wadersPickup:WadersPickup;
	var pepperPickup:PepperPickup;

	var shop:Shop;
	var terrainLayer:BDTilemap;
	var shallowColliders:FlxTypedGroup<FlxSprite>;
	var inventoryHUD:InventoryHUD;
	var scoreHUD:ScoreHUD;
	var activeCameraTransition:CameraTransition = null;
	var hotText:FlashingText;
	var weedGroup = new FlxTypedGroup<entities.Weed>();
	var seagullTimer:Float = 0;
	var wormGroup = new FlxTypedGroup<Worm>();
	var wormTimer:Float = 0;

	var transitions = new FlxTypedGroup<CameraTransition>();

	var waterLayer:levels.ldtk.WaterGrid;
	var sparkleTimer:Float = 0;

	var ldtk = new LdtkProject();

	var round:RoundManager;

	// Timer HUD — shown on all clients
	var timerHUD:FlxText;
	var timerRunSec:Float = 0;
	var timerTotalSec:Float = 0;
	var timerSynced:Bool = false;

	public function new(game:Room<GameState>) {
		super();
		#if !local
		colyRoom = game;
		QLog.notice(colyRoom.state.levelID);
		#end
	}

	override public function create() {
		super.create();

		// TODO: We need to create all of our entities now based on what is in the game state
		// Then connect the entities on our side to their IDs in the game state so we can link
		// them and keep them synced together

		#if !local
		var startingState = colyRoom.state;
		trace(startingState);
		var cb = Callbacks.get(colyRoom);
		cb.listen(colyRoom.state, "levelID", (old, now) -> {
			trace(old);
			trace(now);
		});

		colyRoom.onStateChange += (newState:GameState) -> {
			trace('level: ${newState.levelID}');
			trace("NetMan: received state change:");
			trace('  - FishCount: ${newState.fish.length}');
		};
		#end

		FlxG.camera.pixelPerfectRender = true;

		fishSpawner = new FishSpawner(onFishCaught);
		rockGroup = new RockGroup(fishSpawner, this);
		groundFishGroup = new GroundFishGroup();
		wadersPickup = new WadersPickup();
		pepperPickup = new PepperPickup();

		// Build out our render order
		add(midGroundGroup);
		add(rockGroup);
		add(groundFishGroup);
		add(wadersPickup);
		add(pepperPickup);
		add(fishSpawner);
		add(wormGroup);
		add(ySortGroup);
		add(transitions);

		#if local
		loadLevel("Level_0");
		#else
		loadLevel(colyRoom.state.levelID);
		#end

		hotText = new FlashingText("HOT", 0.15, 3.0);
		add(hotText);

		if (round != null) {
			round.initialize(this);
		}

		timerHUD = new FlxText(0, 4, FlxG.width, "--:--");
		timerHUD.size = 16;
		timerHUD.alignment = FlxTextAlign.CENTER;
		timerHUD.color = FlxColor.WHITE;
		timerHUD.scrollFactor.set(0, 0);
		add(timerHUD);

		// Wire server-reconciliation: when the server acks our inputs, replay any un-acked ones
		#if !local
		NetworkManager.ME.onPlayerChanged.add((sesId, data) -> {});
		#end
	}

	function onPlayerRemoved(sessionId:String) {
		trace('PlayState: remote player $sessionId left, removing remote player');
		playerNetworkedStates.remove(sessionId);
		var remote = remotePlayers.get(sessionId);
		if (remote != null) {
			remove(remote);
			remote.destroy();
			remotePlayers.remove(sessionId);
		}
	}

	function bindPlayer(sessionId:String, p:Player, localPrediction:PlayerState, serverState:PlayerState) {
		#if !local
		var cb = Callbacks.get(colyRoom);
		#end

		if (localPrediction == null) {
			// --- Remote player: interpolate toward server position ---
			var c:PlayerState = PlayerState.copy(serverState);
			var ns = new NetworkedState<PlayerState, PlayerState>(serverState, c);

			ns.onTick = (elapsed) -> {
				var s = ns.server;
				var cl = ns.client;

				// Teleport if way off, otherwise spring toward server
				var dx = s.x - cl.x;
				var dy = s.y - cl.y;
				if (dx * dx + dy * dy > REMOTE_TELEPORT_DIST_SQ) {
					cl.x = s.x;
					cl.y = s.y;
				} else {
					cl.x += dx * Math.min(elapsed * REMOTE_SPRING_K, 1.0);
					cl.y += dy * Math.min(elapsed * REMOTE_SPRING_K, 1.0);
				}

				// Lerp velocity so animation direction smooths out
				cl.velocityX += (s.velocityX - cl.velocityX) * Math.min(elapsed * REMOTE_SPRING_K, 1.0);
				cl.velocityY += (s.velocityY - cl.velocityY) * Math.min(elapsed * REMOTE_SPRING_K, 1.0);

				// Update facing from smooth velocity
				if (Math.abs(cl.velocityX) > 5 || Math.abs(cl.velocityY) > 5) {
					p.lastInputDir = Cardinal.closest(FlxPoint.weak(cl.velocityX, cl.velocityY));
				}

				p.isMoving = Math.abs(cl.velocityX) > 5 || Math.abs(cl.velocityY) > 5;
				p.controlState = serverState.controlState;
				p.setPosition(cl.x, cl.y);
				p.velocity.set(0, 0);
			};

			ns.onServerUpdate = () -> {/* nothing needed — schema is a live ref */};

			playerNetworkedStates.set(sessionId, ns);
			#if !local
			cb.onChange(serverState, () -> ns.serverUpdate());
			#end
			return;
		}

		// Seed controlState — copy() skips it but tickPlayer's state machine needs it
		localPrediction.controlState = serverState.controlState;

		// --- Local player: client-side prediction + server reconciliation ---
		var ns = new NetworkedState<PlayerState, PlayerState>(serverState, localPrediction);

		ns.onTick = (elapsed) -> {
			if (!player.frozen) {
				var inputDir = InputCalculator.getInputCardinal(0);
				player.isMoving = (inputDir != NONE);
				if (inputDir != NONE) {
					player.lastInputDir = inputDir;
				}
				var inp:P_Input = {
					seq: ++inputSeq,
					dir: inputDir,
					elapsed: elapsed,
					buttons: getInputMask()
				};
				pendingInputs.push(inp);
				#if !local
				// trace('sending input: ${inp}');
				colyRoom.send(schema.GameState.MSG_P_INPUT, [inp]);
				#end
				// In local mode there's no NetworkedState onTick, so tick prediction here directly
				simulation.tickPlayer(localPrediction, [inp], elapsed);
				p.setPosition(localPrediction.x, localPrediction.y);
				p.controlState = serverState.controlState;
				p.velocity.set(0, 0);
			}
		};

		ns.onServerUpdate = () -> {
			var ack = serverState.lastProcessedSeq;
			// Prune inputs the server has already processed
			while (pendingInputs.length > 0 && pendingInputs[0].seq <= ack) {
				pendingInputs.shift();
			}

			// Remember where client predicted it would be
			var oldX = localPrediction.x;
			var oldY = localPrediction.y;

			// Snap to server-confirmed position, then replay unacked inputs
			localPrediction.x = serverState.x;
			localPrediction.y = serverState.y;
			localPrediction.velocityX = serverState.velocityX;
			localPrediction.velocityY = serverState.velocityY;
			localPrediction.controlState = serverState.controlState;
			lastServerPos.set(serverState.x, serverState.y, serverState.width, serverState.height);

			for (inp in pendingInputs) {
				simulation.tickPlayer(localPrediction, [inp], inp.elapsed);
			}

			// Only log if replay diverged from predicted (real server correction)
			var ex = localPrediction.x - oldX;
			var ey = localPrediction.y - oldY;
			if (ex * ex + ey * ey > 16) {
				QLog.notice('server corrected position by (${ex}, ${ey})');
			}

			ns.client.x = localPrediction.x;
			ns.client.y = localPrediction.y;
			p.setPosition(localPrediction.x, localPrediction.y);
		};

		playerNetworkedStates.set(sessionId, ns);
		#if !local
		cb.onChange(serverState, () -> ns.serverUpdate());
		#end
	}

	function onFishAdded(fishId:String, fishState:FishState) {
		if (fishSpawner.fishMap.exists(fishId)) {
			QLog.notice('skipping fish $fishId, it already exists');
			return;
		}

		QLog.notice('adding fish $fishId: ${fishState.x}, ${fishState.y}');

		var newFish = new WaterFish(fishId, fishState.x, fishState.y, null, true, fishState.fishType);
		remoteFish.set(fishId, newFish);
		fishSpawner.add(newFish);
		QLog.notice('fish post-add pos: ${newFish.x}, ${newFish.y}');
	}

	function loadLevel(level:String) {
		unload();

		// Build collision map for client-side prediction simulation
		var col:CollisionMap;

		#if local
		var hitboxJson = openfl.Assets.getText(AssetPaths.tile_hitboxes__json);
		col = CollisionMap.fromLevel(ldtk.getLevel(level), hitboxJson);
		#else
		var gs = NetworkManager.ME.getState();
		if (gs != null) {
			col = gs.collision;
		} else {
			var hitboxJson = openfl.Assets.getText(AssetPaths.tile_hitboxes__json);
			col = CollisionMap.fromLevel(ldtk.getLevel(level), hitboxJson);
		}
		#end
		simulation = new Simulation(col);
		pendingInputs = [];
		inputSeq = 0;

		var level = new Level(level);
		if (level.songEvent != "") {
			TODO.sfx("Play song");
		}
		terrainLayer = level.terrainLayer;
		midGroundGroup.add(terrainLayer);
		midGroundGroup.add(level.tileColliders);
		shallowColliders = level.shallowTileColliders;
		midGroundGroup.add(shallowColliders);
		FlxG.worldBounds.copyFrom(terrainLayer.getBounds());

		#if local
		var clientPlayerState = new PlayerState();
		clientPlayerState.controlState = PlayerState.CONTROL_STATE_IDLE;
		player = Player.fromState(clientPlayerState, this);
		ySortGroup.add(player);
		bindPlayer("local", player, clientPlayerState, clientPlayerState);
		#else
		for (id => p in colyRoom.state.players) {
			var loadedPlayer = Player.fromState(p, this);
			var clientState:PlayerState = null;

			FlxG.watch.add(p, "controlState", 'p ${p.id} cState: ');

			if (id == colyRoom.sessionId) {
				player = loadedPlayer;
				clientState = PlayerState.copy(p);
				clientState.x = p.x;
				clientState.y = p.y;
				// clientPlayerState = clientState;
				FlxG.watch.add(loadedPlayer, "x", "pX: ");
				FlxG.watch.add(loadedPlayer, "y", "pY: ");
			}

			bindPlayer(id, loadedPlayer, clientState, p);
			ySortGroup.add(loadedPlayer);
		}
		#end

		player.terrainLayer = terrainLayer;
		player.groundEffectsGroup = midGroundGroup;
		camera.follow(player);

		waterLayer = level.waterGrid;
		player.makeRock = (rx, ry, big) -> new Rock(rx, ry, big, waterLayer, rockGroup.addRock, rockGroup.onLocalSplash);
		for (_ => remote in remotePlayers) {
			remote.makeRock = (rx, ry, big) -> new Rock(rx, ry, big, waterLayer, rockGroup.addRock, rockGroup.onRemoteSplash);
		}
		groundFishGroup.setWaterLayer(waterLayer);

		// wire up pickup callbacks for network broadcast
		// rockGroup.onPickup = (type, idx) -> {
		// 	GameManager.ME.net.sendItemPickup(type, idx);
		// };
		// wadersPickup.onPickup = () -> {
		// 	GameManager.ME.net.sendItemPickup("waders", 0);
		// };
		// pepperPickup.onPickup = () -> {
		// 	GameManager.ME.net.sendItemPickup("pepper", 0);
		// };

		player.onBobberLanded = (bx, by) -> {
			// if (classifyGround(terrainLayer.sampleColorAt(bx, by)) == "water") {
			// 	FmodManager.PlaySoundOneShot(FmodSFX.BobberLandWater);
			// 	add(new Ripple(bx, by));
			// } else {
			// 	FmodManager.PlaySoundOneShot(FmodSFX.BobberLandGround);
			// }
			// FlxG.camera.shake(0.002, 0.1);
		};

		CloudShadow.randomizeWind();
		for (_ in 0...5) {
			add(new CloudShadow());
		}

		#if local
		shop = new Shop();
		shop.spawnRandom(level, terrainLayer);
		ySortGroup.add(shop);
		#else
		if (NetworkManager.IS_HOST) {
			var bushPositions = [for (bush in bushGroup) {x: bush.x, y: bush.y}];
			shop = new Shop();
			shop.spawnRandom(level, terrainLayer);
			ySortGroup.add(shop);
			// GameManager.ME.net.sendWorldSetup(bushPositions, shop.x, shop.y);
		} else {
			// Check if world state already arrived (e.g. late joiner)
			// var state = GameManager.ME.net.getState();
			// if (state != null && state.shopReady) {
			// 	placeShopAt(state.shopX, state.shopY);
			// 	for (_ => bush in state.bushes) {
			// 		placeBushAt(bush.x, bush.y);
			// 	}
			// }
		}
		#end

		inventoryHUD = new InventoryHUD(player.inventory);
		add(inventoryHUD);

		scoreHUD = new ScoreHUD();
		add(scoreHUD);

		for (t in level.camTransitions) {
			transitions.add(t);
		}

		var playerPos = FlxPoint.get(player.x, player.y);
		for (_ => zone in level.camZones) {
			if (zone.containsPoint(playerPos)) {
				setCameraBounds(zone);
			}
		}
		playerPos.put();

		EventBus.fire(new PlayerSpawn(player.x, player.y));
	}

	function unload() {
		for (t in transitions) {
			t.destroy();
		}
		transitions.clear();

		rockGroup.clearAll();
		groundFishGroup.clearAll();
		fishSpawner.clearAll();

		for (o in midGroundGroup) {
			o.destroy();
		}
		midGroundGroup.clear();
	}

	function onFishCaught(fishId:String, catcherSessionId:String, fishType:Int) {
		#if !local
		// GameManager.ME.net.sendFishCaught(fishId, catcherSessionId, fishType);
		#end

		// Trigger on the catching player immediately (avoids latency; echo-back is a no-op)
		if (catcherSessionId == player.sessionId) {
			player.onFishDelivered = () -> {
				if (!player.inventory.add(Fish(player.caughtFishSpriteIndex, player.caughtFishLengthCm))) {
					groundFishGroup.addFish(player.x + 8, player.y - 14, player.caughtFishSpriteIndex, player.caughtFishLengthCm);
				}
				player.onFishDelivered = null;
			};
			// player.catchFish(true, catcherSessionId, fishId, fishType);
		} else {
			// var remote = remotePlayers.get(catcherSessionId);
			// if (remote != null)
			// remote.catchFish(true, catcherSessionId, fishId, fishType);
		}
	}

	function onSpawnLocations(message:Dynamic) {
		// host already placed everyone, so skip
		if (NetworkManager.IS_HOST) {
			return;
		}
		// reposition local player and remotes based on host-assigned locations
		// var myId = GameManager.ME.net.mySessionId;
		// var myPos:Dynamic = Reflect.field(message, myId);
		// if (myPos != null) {
		// 	player.setPosition(myPos.x, myPos.y);
		// }
		// for (seshID => remote in remotePlayers) {
		// 	var pos:Dynamic = Reflect.field(message, seshID);
		// 	if (pos != null) {
		// 		remote.setPosition(pos.x, pos.y);
		// 	}
		// }
	}

	function getInputMask():Int {
		var input = 0;
		if (SimpleController.pressed(A)) {
			input |= PlayerState.BUTTON_A;
		}

		if (SimpleController.pressed(B)) {
			input |= PlayerState.BUTTON_B;
		}

		return input;
	}

	override public function update(elapsed:Float) {
		// Tick all NetworkedStates before super.update() so Player.update() → playMovementAnim()
		// sees the correct position, isMoving, and lastInputDir that NS.onTick just wrote.
		for (ns in playerNetworkedStates) {
			ns.tick(elapsed);
		}

		super.update(elapsed);

		// FlxG.collide(midGroundGroup, player);

		handleCameraBounds();

		if (player.hotModeActive && !hotText.isFlashing()) {
			hotText.start();
		}

		// DS "Debug Suite" is how we get to all of our debugging tools
		DS.get(DebugDraw).drawCameraText(50, 50, "hello", DebugLayers.AUDIO);
		DS.get(DebugDraw).drawWorldRect(lastServerPos.x, lastServerPos.y, lastServerPos.width, lastServerPos.height);
	}

	function handleCameraBounds() {
		if (activeCameraTransition == null) {
			FlxG.overlap(player, transitions, (p, t) -> {
				activeCameraTransition = cast t;
			});
		} else if (!FlxG.overlap(player, activeCameraTransition)) {
			var bounds = activeCameraTransition.getRotatedBounds();
			for (dir => camZone in activeCameraTransition.camGuides) {
				switch (dir) {
					case N:
						if (player.y < bounds.top) {
							setCameraBounds(camZone);
						}
					case S:
						if (player.y > bounds.bottom) {
							setCameraBounds(camZone);
						}
					case E:
						if (player.x > bounds.right) {
							setCameraBounds(camZone);
						}
					case W:
						if (player.x < bounds.left) {
							setCameraBounds(camZone);
						}
					default:
						QLog.error('camera transition area has unsupported cardinal direction ${dir}');
				}
			}
		}
	}

	public function setCameraBounds(bounds:FlxRect) {
		camera.setScrollBoundsRect(bounds.x, bounds.y, bounds.width, bounds.height);
	}

	override public function onFocusLost() {
		super.onFocusLost();
		this.handleFocusLost();
	}

	override public function onFocus() {
		super.onFocus();
		this.handleFocus();
	}
}
