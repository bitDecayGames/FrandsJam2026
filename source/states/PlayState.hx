package states;

import schema.RoundState;
import flixel.util.FlxColor;
import flixel.FlxSprite;
import schema.FishState;
import flixel.util.FlxTimer;
import managers.GameManager;
import schema.PlayerState;
import config.Configure;
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
import levels.ldtk.BDTilemap;
import levels.ldtk.Ldtk.Enum_TileTags;
import levels.ldtk.Level;
import levels.ldtk.Ldtk.LdtkProject;
import achievements.Achievements;
import entities.Bush;
import entities.CloudShadow;
import entities.Player;
import entities.Ripple;
import entities.Seagull;
import entities.Shop;
import entities.WaterSparkle;
import events.gen.Event;
import events.EventBus;
import flixel.FlxG;
import flixel.addons.transition.FlxTransitionableState;
import flixel.util.FlxSort;
import ui.FlashingText;
import ui.InventoryHUD;
import ui.ScoreHUD;

using states.FlxStateExt;

class PlayState extends FlxTransitionableState {
	var player:Player;

	// Network things
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
	var seagullGroup = new FlxTypedGroup<Seagull>();
	var seagullTimer:Float = 0;

	var transitions = new FlxTypedGroup<CameraTransition>();

	var waterLayer:ldtk.Layer_IntGrid;
	var sparkleTimer:Float = 0;

	var ldtk = new LdtkProject();

	var round:RoundManager;

	public function new(round:RoundManager) {
		this.round = round;
		super();
	}

	override public function create() {
		super.create();

		FlxG.camera.pixelPerfectRender = true;

		Achievements.onAchieve.add(handleAchieve);
		EventBus.subscribe(ClickCount, (c) -> {
			QLog.notice('I got me an event about ${c.count} clicks having happened.');
		});

		// QLog.error('Example error');

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
		add(ySortGroup);
		add(transitions);

		#if !local
		setupNetwork();
		// GameManager.ME.net.connect(Configure.getServerURL(), Configure.getServerPort());
		fishSpawner.setNet(GameManager.ME.net);
		#end

		loadLevel("Level_0");

		hotText = new FlashingText("HOT", 0.15, 3.0);
		add(hotText);

		if (round != null) {
			round.initialize(this);
		}

		if (NetworkManager.IS_HOST) {
			GameManager.ME.net.sendMessage("round_update", {
				status: RoundState.STATUS_ACTIVE,
			});
		}
	}

	override function destroy() {
		super.destroy();
		GameManager.ME.net.onPlayerRemoved.remove(onPlayerRemoved);
		GameManager.ME.net.onFishAdded.remove(onFishAdded);
		GameManager.ME.net.onCastLine.remove(onRemoteCastLine);
		GameManager.ME.net.onFishCaught.remove(onRemoteFishCaught);
		GameManager.ME.net.onLinePulled.remove(onRemoteLinePulled);
		GameManager.ME.net.onRockSplash.remove(rockGroup.onRemoteSplash);
		GameManager.ME.net.onBushAdded.remove(onRemoteBushAdded);
		GameManager.ME.net.onShopPlaced.remove(onRemoteShopPlaced);
	}

	function setupNetwork() {
		GameManager.ME.net.onPlayerRemoved.add(onPlayerRemoved);
		GameManager.ME.net.onFishAdded.add(onFishAdded);
		GameManager.ME.net.onCastLine.add(onRemoteCastLine);
		GameManager.ME.net.onFishCaught.add(onRemoteFishCaught);
		GameManager.ME.net.onLinePulled.add(onRemoteLinePulled);
		GameManager.ME.net.onRockSplash.add(rockGroup.onRemoteSplash);
		GameManager.ME.net.onBushAdded.add(onRemoteBushAdded);
		GameManager.ME.net.onShopPlaced.add(onRemoteShopPlaced);
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
			// FmodManager.PlaySong(level.songEvent);
		}
		terrainLayer = level.terrainLayer;
		midGroundGroup.add(terrainLayer);
		midGroundGroup.add(level.tileColliders);
		shallowColliders = level.shallowTileColliders;
		midGroundGroup.add(shallowColliders);
		FlxG.worldBounds.copyFrom(terrainLayer.getBounds());

		player = new Player(level.spawnPoint.x, level.spawnPoint.y, this);
		if (GameManager.ME.mySkinIndex >= 0) {
			player.skinIndex = GameManager.ME.mySkinIndex;
			player.swapSkin();
		}
		player.sessionId = GameManager.ME.net.mySessionId;
		player.terrainLayer = terrainLayer;
		player.groundEffectsGroup = midGroundGroup;
		camera.follow(player);
		ySortGroup.add(player);

		for (index => seshID in GameManager.ME.sessions) {
			var remote = new Player(level.spawnPoint.x, level.spawnPoint.y, this);
			remote.isRemote = true;
			remote.setNetwork(seshID);
			remotePlayers.set(seshID, remote);
			ySortGroup.add(remote);
		}

		#if local
		spawnWorldItems(level);
		#else
		FlxTimer.wait(10, () -> {
			if (NetworkManager.IS_HOST) {
				spawnWorldItems(level);
			} else {
				QLog.notice('skipping spawn');
			}
		});
		#end

		var spawnerLayer = level.fishSpawnerLayer;
		waterLayer = spawnerLayer;
		player.makeRock = (rx, ry, big) -> new Rock(rx, ry, big, spawnerLayer, rockGroup.addRock, rockGroup.onLocalSplash);
		groundFishGroup.setWaterLayer(spawnerLayer);
		#if local
		spawnBushes(spawnerLayer);
		#else
		if (NetworkManager.IS_HOST) {
			spawnBushes(spawnerLayer);
		}
		#end

		spawnWeeds();

		player.onBobberLanded = (bx, by) -> {
			add(new Ripple(bx, by));
			FlxG.camera.shake(0.002, 0.1);
		};

		CloudShadow.randomizeWind();
		for (_ in 0...5) {
			add(new CloudShadow());
		}

		add(seagullGroup);

		#if local
		shop = new Shop();
		shop.spawnRandom(level);
		ySortGroup.add(shop);
		#else
		if (NetworkManager.IS_HOST) {
			var bushPositions = [for (bush in bushGroup) {x: bush.x, y: bush.y}];
			shop = new Shop();
			shop.spawnRandom(level);
			ySortGroup.add(shop);
			GameManager.ME.net.sendWorldSetup(bushPositions, shop.x, shop.y);
		} else {
			// Check if world state already arrived (e.g. late joiner)
			var state = GameManager.ME.net.getState();
			if (state != null && state.shopReady) {
				placeShopAt(state.shopX, state.shopY);
				for (_ => bush in state.bushes) {
					placeBushAt(bush.x, bush.y);
				}
			}
		}
		#end

		inventoryHUD = new InventoryHUD(player.inventory);
		add(inventoryHUD);

		player.inventory.onChange.add(onInventoryChanged);
		onInventoryChanged();

		scoreHUD = new ScoreHUD(player);
		add(scoreHUD);

		for (t in level.camTransitions) {
			transitions.add(t);
		}

		for (_ => zone in level.camZones) {
			if (zone.containsPoint(level.spawnPoint)) {
				setCameraBounds(zone);
			}
		}

		EventBus.fire(new PlayerSpawn(player.x, player.y));
	}

	static function classifyGround(color:FlxColor):String {
		if (color == FlxColor.TRANSPARENT) {
			return "";
		}
		var hue = color.hue;
		if (color.blue > color.red && color.blue > 80) {
			return "water";
		}
		if ((hue >= 15 && hue <= 55) && color.saturation > 0.15) {
			return "dirt";
		}
		if (hue >= 60 && hue <= 170 && color.saturation > 0.15) {
			return "grass";
		}
		return "";
	}

	function spawnWorldItems(level:Level) {
		rockGroup.spawn(level);
		fishSpawner.spawn(level);
		wadersPickup.spawn(level);
		pepperPickup.spawn(level);
	}

	function spawnBushes(water:ldtk.Layer_IntGrid) {
		var bounds = FlxG.worldBounds;
		for (_ in 0...5) {
			for (_ in 0...20) {
				var bx = FlxG.random.float(bounds.x, bounds.right - 32);
				var by = FlxG.random.float(bounds.y, bounds.bottom - 32);
				if (classifyGround(terrainLayer.sampleColorAt(bx, by)) == "grass") {
					var bush = new Bush(bx, by, this);
					bushGroup.add(bush);
					ySortGroup.add(bush);
					break;
				}
			}
		}
	}

	function spawnWeeds() {
		var bounds = FlxG.worldBounds;
		for (_ in 0...20) {
			for (_ in 0...20) {
				var wx = FlxG.random.float(bounds.x, bounds.right - 8);
				var wy = FlxG.random.float(bounds.y, bounds.bottom - 8);
				var ground = classifyGround(terrainLayer.sampleColorAt(wx, wy));
				if (ground == "grass" || ground == "dirt") {
					var weed = new entities.Weed(wx, wy, this);
					weedGroup.add(weed);
					midGroundGroup.add(weed);
					break;
				}
			}
		}
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
		GameManager.ME.net.sendFishCaught(fishId, catcherSessionId, fishType);
		#end

		// Trigger on the catching player immediately (avoids latency; echo-back is a no-op)
		if (catcherSessionId == player.sessionId) {
			player.onFishDelivered = () -> {
				if (!player.inventory.add(Fish(player.caughtFishSpriteIndex))) {
					groundFishGroup.addFish(player.x + 8, player.y - 14, player.caughtFishSpriteIndex);
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

	function placeBushAt(bx:Float, by:Float) {
		var bush = new Bush(bx, by, this);
		bushGroup.add(bush);
		ySortGroup.add(bush);
	}

	function placeShopAt(sx:Float, sy:Float) {
		shop = new Shop();
		shop.setPosition(sx, sy);
		ySortGroup.add(shop);
	}

	function onRemoteBushAdded(x:Float, y:Float) {
		if (NetworkManager.IS_HOST) {
			return;
		}
		placeBushAt(x, y);
	}

	function onRemoteShopPlaced(x:Float, y:Float) {
		if (NetworkManager.IS_HOST) {
			return;
		}
		placeShopAt(x, y);
	}

	function onRemoteCastLine(sessionId:String, x:Float, y:Float, dir:String) {
		var remote = remotePlayers.get(sessionId);
		if (remote != null)
			remote.remoteStartCast(x, y, dir);
	}

	function onRemoteFishCaught(sessionId:String, fishId:String, fishType:Int) {
		// Hide the remote fish sprite — it will fade back in when the host starts moving it again
		var fish = remoteFish.get(fishId);
		if (fish != null)
			fish.visible = false;

		// Non-host clients receive this to trigger the catch animation
		if (sessionId == player.sessionId) {
			player.onFishDelivered = () -> {
				if (!player.inventory.add(Fish(player.caughtFishSpriteIndex))) {
					groundFishGroup.addFish(player.x + 8, player.y - 14, player.caughtFishSpriteIndex);
				}
				player.onFishDelivered = null;
			};
			player.catchFish(true, sessionId, fishId, fishType);
		} else {
			var remote = remotePlayers.get(sessionId);
			if (remote != null)
				remote.catchFish(true, sessionId, fishId, fishType);
		}
	}

	function onRemoteLinePulled(sessionId:String) {
		if (sessionId == player.sessionId) {
			player.catchFish(false, sessionId, null);
		} else {
			var remote = remotePlayers.get(sessionId);
			if (remote != null)
				remote.catchFish(false, sessionId, null);
		}
	}

	function handleAchieve(def:AchievementDef) {
		add(def.toToast(true));
	}

	function onInventoryChanged() {
		var hasWaders = player.inventory.hasWaders();
		if (terrainLayer != null) {
			terrainLayer.setShallowCollisions(!hasWaders);
		}
		if (shallowColliders != null) {
			shallowColliders.exists = !hasWaders;
		}
	}

	override public function update(elapsed:Float) {
		super.update(elapsed);

		if (FlxG.mouse.justPressed) {
			EventBus.fire(new Click(FlxG.mouse.x, FlxG.mouse.y));
		}

		FlxG.collide(midGroundGroup, player);
		FlxG.collide(bushGroup, player, Bush.onCollide);
		FlxG.overlap(weedGroup, player, (weed:entities.Weed, _) -> {
			weed.burst();
		});
		if (shop != null) {
			FlxG.collide(shop, player, Shop.onCollide);
		}

		if (player.inventory.hasWaders() && terrainLayer != null) {
			player.inShallowWater = terrainLayer.isFullyInTaggedArea(player, [SHALLOW, SOLID]);
		} else {
			player.inShallowWater = false;
		}
		ySortGroup.sort((order, a, b) -> {
			var objA:flixel.FlxObject = cast a;
			var objB:flixel.FlxObject = cast b;
			return FlxSort.byValues(order, objA.y + objA.height, objB.y + objB.height);
		});
		handleCameraBounds();

		if (player.hotModeActive && !hotText.isFlashing()) {
			hotText.start();
		}

		// TODO helps devs call audio correctly, and helps audio folks find where sounds are needed
		TODO.sfx('scarySound');

		// DS "Debug Suite" is how we get to all of our debugging tools
		DS.get(DebugDraw).drawCameraText(50, 50, "hello", DebugLayers.AUDIO);

		var bobbers:Map<String, FlxSprite> = new Map();
		if (player.isBobberLanded())
			bobbers.set(player.sessionId, player.castBobber);
		#if !local
		if (NetworkManager.IS_HOST) {
			for (sid => remote in remotePlayers) {
				if (remote.isBobberLanded())
					bobbers.set(sid, remote.castBobber);
			}
		}
		#end
		fishSpawner.setBobbers(bobbers);
		rockGroup.checkPickup(player);
		groundFishGroup.checkPickup(player);
		wadersPickup.checkPickup(player);
		pepperPickup.checkPickup(player);
		if (shop != null) {
			shop.checkInteraction(player);
		}

		updateSparkles(elapsed);
		updateSeagulls(elapsed);
	}

	function updateSeagulls(elapsed:Float) {
		seagullTimer -= elapsed;
		if (seagullTimer > 0) {
			return;
		}
		seagullTimer = FlxG.random.float(2.0, 6.0);
		seagullGroup.add(new Seagull(FlxG.random.bool()));
	}

	function updateSparkles(elapsed:Float) {
		if (waterLayer == null)
			return;
		sparkleTimer -= elapsed;
		if (sparkleTimer > 0)
			return;
		sparkleTimer = FlxG.random.float(0.08, 0.2);

		var wx = FlxG.random.float(camera.scroll.x, camera.scroll.x + camera.width);
		var wy = FlxG.random.float(camera.scroll.y, camera.scroll.y + camera.height);
		var grid = waterLayer.gridSize;
		var tileX = Std.int(wx / grid);
		var tileY = Std.int(wy / grid);
		if (waterLayer.getInt(tileX, tileY) == 1) {
			add(new WaterSparkle(wx, wy));
		}
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
