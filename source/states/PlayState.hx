package states;

import schema.GameState;
import io.colyseus.Room;
import flixel.math.FlxPoint;
import flixel.util.FlxColor;
import flixel.FlxSprite;
import schema.FishState;
import net.NetworkManager;
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
	var player:Player;

	// Network things
	var colyRoom:Room<GameState> = null;
	var remotePlayers:Map<String, Player> = new Map();
	var remoteFish:Map<String, WaterFish> = new Map();

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

	public function new(round:RoundManager) {
		this.round = round;
		super();
	}

	override public function create() {
		super.create();

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

		loadLevel("Level_0");

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
	}

	function onPlayerRemoved(sessionId:String) {
		trace('PlayState: remote player $sessionId left, removing remote player');
		var remote = remotePlayers.get(sessionId);
		if (remote != null) {
			remove(remote);
			remote.destroy();
			remotePlayers.remove(sessionId);
		}
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

		// standin until we get everything sent down from the server
		player = new Player(0, 0, this);

		player.terrainLayer = terrainLayer;
		player.groundEffectsGroup = midGroundGroup;
		camera.follow(player);
		ySortGroup.add(player);

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
			player.catchFish(true, catcherSessionId, fishId, fishType);
		} else {
			var remote = remotePlayers.get(catcherSessionId);
			if (remote != null)
				remote.catchFish(true, catcherSessionId, fishId, fishType);
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

	override public function update(elapsed:Float) {
		super.update(elapsed);

		updateTimerHUD(elapsed);

		// FlxG.collide(midGroundGroup, player);

		handleCameraBounds();

		if (player.hotModeActive && !hotText.isFlashing()) {
			hotText.start();
		}

		// DS "Debug Suite" is how we get to all of our debugging tools
		DS.get(DebugDraw).drawCameraText(50, 50, "hello", DebugLayers.AUDIO);
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
