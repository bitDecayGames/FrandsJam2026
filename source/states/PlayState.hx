package states;

import flixel.math.FlxPoint;
import schema.RoundState;
import flixel.util.FlxColor;
import flixel.FlxSprite;
import schema.FishState;
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
import entities.Worm;
import entities.WormSplat;
import levels.ldtk.BDTilemap;
import levels.ldtk.Ldtk.Enum_TileTags;
import levels.ldtk.Level;
import levels.ldtk.Ldtk.LdtkProject;
import achievements.Achievements;
import entities.Bush;
import entities.Splash;
import entities.CloudShadow;
import entities.Player;
import entities.Ripple;
import entities.Seagull;
import entities.SeagullPoop;
import entities.BaitShopInterior;
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
import flixel.text.FlxText;

using states.FlxStateExt;

class PlayState extends FlxTransitionableState {
	var player:Player;

	// Network things
	var remotePlayers:Map<String, Player> = new Map();
	// Fish are stored in fishSpawner (single group + fishMap for ID lookup)

	var midGroundGroup = new FlxGroup();
	var ySortGroup = new FlxGroup();
	// serverFishGroup removed — fishSpawner is the single fish render group
	var bushGroup = new FlxTypedGroup<Bush>();
	var localBushContacts = new Map<Int, Bool>(); // entityRect index -> in contact
	var remoteBushContacts = new Map<String, Map<Int, Bool>>(); // sessionId -> bushIndex -> inContact
	var bushByRectIndex = new Map<Int, Bush>(); // entityRect index -> bush sprite
	var serverDogs = new Map<Int, entities.Dog>(); // dogId -> Dog sprite
	var powerUpSprite:FlxSprite;
	var gravityBombSprite:entities.GravityBomb;
	var rocketSprites = new Map<Int, FlxSprite>();
	var rocketData = new Map<Int, {x:Float, y:Float, dirX:Float, dirY:Float, speed:Float}>();
	var rocketEmitters = new Map<Int, flixel.effects.particles.FlxEmitter>();
	var hungerOverlay:FlxSprite;
	var baitOverlay:FlxSprite;
	var arcingItems:Array<{sprite:FlxSprite, startX:Float, startY:Float, landX:Float, landY:Float, flightTime:Float, elapsed:Float, onLand:Void->Void}> = [];
	var groundItems:Array<{sprite:FlxSprite, item:entities.Inventory.InventoryItem}> = [];
	var fishSpawner:FishSpawner;
	var rockGroup:RockGroup;
	var groundFishGroup:GroundFishGroup;
	var wadersPickup:WadersPickup;
	var pepperPickup:PepperPickup;

	var shop:Shop;
	var terrainLayer:BDTilemap;
	var shallowColliders:FlxTypedGroup<FlxSprite>;
	var waterColliders:FlxTypedGroup<FlxSprite>;
	var inventoryHUD:InventoryHUD;
	var scoreHUD:ScoreHUD;
	var activeCameraTransition:CameraTransition = null;
	var weedGroup = new FlxTypedGroup<entities.Weed>();
	var seagullGroup = new FlxTypedGroup<Seagull>();
	var seagullTimer:Float = 0;
	var serverSeagulls:Map<Int, Seagull> = new Map();
	var wormGroup = new FlxTypedGroup<Worm>();
	var wormTimer:Float = 0;

	var transitions = new FlxTypedGroup<CameraTransition>();

	var waterLayer:levels.ldtk.WaterGrid;
	var sparkleTimer:Float = 0;

	var shopInterior:BaitShopInterior;
	var insideShop:Bool = false;
	var shopReturnX:Float = 0;
	var shopReturnY:Float = 0;
	var mainWorldBounds:FlxRect;
	var mainCameraBounds:FlxRect;

	var ldtk = new LdtkProject();
	var simulation:Simulation;

	var round:RoundManager;

	// Timer HUD — shown on all clients
	var timerHUD:FlxText;
	var timerRunSec:Float = 0;
	var timerTotalSec:Float = 0;
	var timerSynced:Bool = false;

	// UI camera — drawn on top of the game camera, skips the time-of-day filter
	var uiCamera:flixel.FlxCamera;

	// Time of day — server-synced clock + environment color grade
	var timeHud:ui.TimeOfDayHUD;
	var todShader:shaders.TimeOfDayShader;
	var todHour:Float = 12.0;
	var todRate:Float = 0.0; // matches GameLogic.TIME_NORMAL_RATE — time only moves via the buttons
	var todCandleR:Float = 120; // eased candle radius (pepper doubles it smoothly)
	var remoteGlowR = new Map<String, Float>(); // eased bonfire radius per remote player
	var todNvFactor:Float = 0; // eased night vision goggle factor (0..1)
	var todNvTime:Float = 0; // grain animation clock
	var todNvArmed:Bool = false; // goggles held + full night
	var todNvDelay:Float = 0; // ~1s of normal night before the goggles "click" on/off

	public function new(round:RoundManager) {
		this.round = round;
		super();
	}

	override public function create() {
		super.create();

		FlxG.camera.pixelPerfectRender = true;

		// HUD renders on its own camera so the time-of-day shader doesn't dim it.
		// Must exist before loadLevel() — inventory/score HUDs are created in there.
		uiCamera = new flixel.FlxCamera();
		uiCamera.bgColor = FlxColor.TRANSPARENT;
		FlxG.cameras.add(uiCamera, false);

		Achievements.onAchieve.add(handleAchieve);
		EventBus.subscribe(ClickCount, (c) -> {
			QLog.notice('I got me an event about ${c.count} clicks having happened.');
		});

		// QLog.error('Example error');

		fishSpawner = new FishSpawner();
		rockGroup = new RockGroup(this);
		groundFishGroup = new GroundFishGroup();
		wadersPickup = new WadersPickup();
		pepperPickup = new PepperPickup();

		// Build out our render order
		add(midGroundGroup);
		add(weedGroup);
		add(rockGroup);
		add(groundFishGroup);
		add(wadersPickup);
		add(pepperPickup);
		add(fishSpawner);
		add(wormGroup);
		add(ySortGroup);
		add(transitions);

		setupNetwork();
		var host = GameManager.soloMode ? "local" : Configure.getServerURL();
		GameManager.ME.net.connect(host, Configure.getServerPort());

		loadLevel("Level_0");

		if (round != null) {
			round.initialize(this);
		}

		timerHUD = new FlxText(0, 4, FlxG.width, "--:--");
		timerHUD.size = 16;
		timerHUD.alignment = FlxTextAlign.CENTER;
		timerHUD.color = FlxColor.WHITE;
		timerHUD.scrollFactor.set(0, 0);
		timerHUD.cameras = [uiCamera];
		add(timerHUD);

		// Sundial clock + Day/Night fast-forward buttons
		timeHud = new ui.TimeOfDayHUD();
		timeHud.onSetTime = (h) -> GameManager.ME.net.sendMessage("set_time", {hour: h});
		timeHud.cameras = [uiCamera];
		add(timeHud);

		// Environment tint shader driven by time of day (noon = identity)
		todShader = new shaders.TimeOfDayShader();
		FlxG.camera.filters = [new openfl.filters.ShaderFilter(todShader)];

		GameManager.ME.net.sendMessage("round_update", {
			status: RoundState.STATUS_ACTIVE,
		});

		// Tell server we're ready — triggers world spawning, fish, timer, clouds
		// Must be after loadLevel so player exists for spawn_locations
		GameManager.ME.net.sendMessage("start_gameplay", {});

		#if db
		addDebugButtons();
		#end
	}

	#if db
	function addDebugButtons() {
		var labels = ["Rock", "Big Rock", "Pepper", "Waders", "End Round", "Dog", "Rocket", "Potion", "Fish", "Bait", "Gravity", "NVG"];
		var btnW = 60;
		var btnH = 16;
		var margin = 4;
		var startX = FlxG.width - btnW - margin;
		var startY = 40;
		for (i in 0...labels.length) {
			var bg = new FlxSprite(startX, startY + i * (btnH + margin));
			bg.makeGraphic(btnW, btnH, FlxColor.fromRGB(40, 40, 40, 180));
			bg.scrollFactor.set(0, 0);
			bg.cameras = [uiCamera];
			add(bg);
			var label = new FlxText(startX, startY + i * (btnH + margin) + 1, btnW, labels[i]);
			label.size = 8;
			label.alignment = FlxTextAlign.CENTER;
			label.color = FlxColor.WHITE;
			label.scrollFactor.set(0, 0);
			label.cameras = [uiCamera];
			add(label);
		}
	}

	function checkDebugButtons() {
		if (FlxG.mouse.justPressedRight) {
			var mx = FlxG.mouse.x;
			var my = FlxG.mouse.y;
			player.setPosition(mx, my);
			if (player.playerState != null) {
				player.playerState.x = mx;
				player.playerState.y = my;
			}
			player.clearPendingInputs();
			GameManager.ME.net.sendMessage("set_position", {x: mx, y: my});
		}
		if (!FlxG.mouse.justPressed) {
			return;
		}
		var btnW = 60;
		var btnH = 16;
		var margin = 4;
		var startX = FlxG.width - btnW - margin;
		var startY = 40;
		var pos = FlxG.mouse.getScreenPosition();
		var mx = pos.x;
		var my = pos.y;
		pos.put();
		if (mx < startX || mx > startX + btnW) {
			return;
		}
		for (i in 0...12) {
			var by = startY + i * (btnH + margin);
			if (my >= by && my < by + btnH) {
				switch (i) {
					case 0:
						GameManager.ME.net.sendMessage("debug_inventory",
							{action: if (player.inventory.has(Rock)) "remove" else "add", type: "rock"});
					case 1:
						GameManager.ME.net.sendMessage("debug_inventory",
							{action: if (player.inventory.has(BigRock)) "remove" else "add", type: "big_rock"});
					case 2:
						GameManager.ME.net.sendHotPepper(!player.hotModeActive, 99);
					case 3:
						GameManager.ME.net.sendMessage("debug_inventory",
							{action: if (player.inventory.hasWaders()) "remove" else "add", type: "waders"});
					case 4:
						GameManager.ME.net.sendMessage("debug_end_round", {});
					case 5:
						GameManager.ME.net.sendMessage("debug_spawn_dog", {});
					case 6:
						GameManager.ME.net.sendMessage("debug_inventory",
							{action: if (player.inventory.has(Rocket)) "remove" else "add", type: "rocket"});
					case 7:
						GameManager.ME.net.sendMessage("debug_inventory",
							{action: if (player.inventory.has(HungerPotion)) "remove" else "add", type: "hunger_potion"});
					case 8:
						GameManager.ME.net.sendMessage("debug_inventory",
							{action: "add", type: "fish", fishType: FlxG.random.int(0, 11), lengthCm: FlxG.random.int(20, 60)});
					case 9:
						GameManager.ME.net.sendMessage("debug_inventory",
							{action: if (player.inventory.has(FishBait)) "remove" else "add", type: "fish_bait"});
					case 10:
						GameManager.ME.net.sendMessage("debug_inventory",
							{action: if (player.inventory.has(GravityBomb)) "remove" else "add", type: "gravity_bomb"});
					case 11:
						GameManager.ME.net.sendMessage("debug_inventory",
							{action: if (player.inventory.has(NightVision)) "remove" else "add", type: "night_vision"});
				}
				return;
			}
		}
	}
	#end

	override function destroy() {
		super.destroy();
		GameManager.ME.net.onPlayerRemoved.remove(onPlayerRemoved);
		GameManager.ME.net.onFishAdded.remove(onFishAdded);
		GameManager.ME.net.onCastStart.remove(onRemoteCastStart);
		GameManager.ME.net.onCastLine.remove(onRemoteCastLine);
		GameManager.ME.net.onFishCaught.remove(onRemoteFishCaught);
		GameManager.ME.net.onLinePulled.remove(onRemoteLinePulled);
		GameManager.ME.net.onRockSplash.remove(onRockSplash);
		GameManager.ME.net.onThrowRock.remove(onRemoteThrowRock);
		GameManager.ME.net.onBushAdded.remove(onRemoteBushAdded);
		GameManager.ME.net.onShopPlaced.remove(onRemoteShopPlaced);
		GameManager.ME.net.onWorldItems.remove(onRemoteWorldItems);
		GameManager.ME.net.onItemPickup.remove(onRemoteItemPickup);
		GameManager.ME.net.onWeedBurst.remove(onRemoteWeedBurst);
		GameManager.ME.net.onBushIgnite.remove(onRemoteBushIgnite);
		GameManager.ME.net.onWeedIgnite.remove(onRemoteWeedIgnite);
		GameManager.ME.net.onHotPepper.remove(onRemoteHotPepper);
		GameManager.ME.net.onPlayerDrown.remove(onRemotePlayerDrown);
		GameManager.ME.net.onSpawnLocations.remove(onSpawnLocations);
		GameManager.ME.net.onTimerSync.remove(onTimerSync);
		GameManager.ME.net.onLocalPlayerAck.remove(onServerAck);
		GameManager.ME.net.onWormSpawn.remove(onServerWormSpawn);
		GameManager.ME.net.onSeagullSpawn.remove(onServerSeagullSpawn);
		GameManager.ME.net.onSeagullPoop.remove(onServerSeagullPoop);
		GameManager.ME.net.onSeagullDespawn.remove(onServerSeagullDespawn);
		GameManager.ME.net.onPepperExtinguish.remove(onPepperExtinguish);
		GameManager.ME.net.onInventoryUpdate.remove(onInventoryUpdate);
		GameManager.ME.net.onDogSpawn.remove(onDogSpawn);
		GameManager.ME.net.onDogUpdate.remove(onDogUpdate);
		GameManager.ME.net.onDogCaught.remove(onDogCaught);
		GameManager.ME.net.onDogDespawn.remove(onDogDespawn);
		GameManager.ME.net.onDogItemLanded.remove(onDogItemLanded);
		GameManager.ME.net.onDogAteFish.remove(onDogAteFish);
		GameManager.ME.net.onPlayerKnockback.remove(onPlayerKnockback);
		GameManager.ME.net.onPowerUpSpawn.remove(onPowerUpSpawn);
		GameManager.ME.net.onPowerUpPickup.remove(onPowerUpPickup);
		GameManager.ME.net.onRocketFired.remove(onRocketFired);
		GameManager.ME.net.onRocketUpdate.remove(onRocketUpdate);
		GameManager.ME.net.onRocketHit.remove(onRocketHit);
		GameManager.ME.net.onRocketDespawn.remove(onRocketDespawn);
		GameManager.ME.net.onThrowPotion.remove(onThrowPotion);
		GameManager.ME.net.onHungerActive.remove(onHungerActive);
		GameManager.ME.net.onHungerExpired.remove(onHungerExpired);
		GameManager.ME.net.onThrowBait.remove(onThrowBait);
		GameManager.ME.net.onBaitActive.remove(onBaitActive);
		GameManager.ME.net.onBaitExpired.remove(onBaitExpired);
		GameManager.ME.net.onGravityBombActive.remove(onGravityBombActive);
		GameManager.ME.net.onGravityBombExpired.remove(onGravityBombExpired);
		GameManager.ME.net.onTimeOfDaySync.remove(onTimeOfDaySync);
		FlxG.camera.filters = null;
		if (uiCamera != null) {
			FlxG.cameras.remove(uiCamera);
			uiCamera = null;
		}
		GameManager.ME.net.onCloudSync.remove(onServerCloudSync);
		GameManager.ME.net.onGroundFishSpawn.remove(onRemoteGroundFishSpawn);
		GameManager.ME.net.onGroundFishPickup.remove(onRemoteGroundFishPickup);
		GameManager.ME.net.onWormKilled.remove(onRemoteWormKilled);
	}

	function setupNetwork() {
		GameManager.ME.net.onPlayerRemoved.add(onPlayerRemoved);
		GameManager.ME.net.onFishAdded.add(onFishAdded);
		GameManager.ME.net.onCastStart.add(onRemoteCastStart);
		GameManager.ME.net.onCastLine.add(onRemoteCastLine);
		GameManager.ME.net.onFishCaught.add(onRemoteFishCaught);
		GameManager.ME.net.onLinePulled.add(onRemoteLinePulled);
		GameManager.ME.net.onRockSplash.add(onRockSplash);
		GameManager.ME.net.onThrowRock.add(onRemoteThrowRock);
		GameManager.ME.net.onBushAdded.add(onRemoteBushAdded);
		GameManager.ME.net.onShopPlaced.add(onRemoteShopPlaced);
		GameManager.ME.net.onWorldItems.add(onRemoteWorldItems);
		GameManager.ME.net.onItemPickup.add(onRemoteItemPickup);
		GameManager.ME.net.onWeedBurst.add(onRemoteWeedBurst);
		GameManager.ME.net.onBushIgnite.add(onRemoteBushIgnite);
		GameManager.ME.net.onWeedIgnite.add(onRemoteWeedIgnite);
		GameManager.ME.net.onHotPepper.add(onRemoteHotPepper);
		GameManager.ME.net.onPlayerDrown.add(onRemotePlayerDrown);
		GameManager.ME.net.onSpawnLocations.add(onSpawnLocations);
		GameManager.ME.net.onTimerSync.add(onTimerSync);
		GameManager.ME.net.onLocalPlayerAck.add(onServerAck);
		GameManager.ME.net.onGroundFishSpawn.add(onRemoteGroundFishSpawn);
		GameManager.ME.net.onGroundFishPickup.add(onRemoteGroundFishPickup);
		GameManager.ME.net.onWormKilled.add(onRemoteWormKilled);
		GameManager.ME.net.onCloudSync.add(onServerCloudSync);
		GameManager.ME.net.onWormSpawn.add(onServerWormSpawn);
		GameManager.ME.net.onSeagullSpawn.add(onServerSeagullSpawn);
		GameManager.ME.net.onSeagullPoop.add(onServerSeagullPoop);
		GameManager.ME.net.onSeagullDespawn.add(onServerSeagullDespawn);
		GameManager.ME.net.onPepperExtinguish.add(onPepperExtinguish);
		GameManager.ME.net.onInventoryUpdate.add(onInventoryUpdate);
		GameManager.ME.net.onDogSpawn.add(onDogSpawn);
		GameManager.ME.net.onDogUpdate.add(onDogUpdate);
		GameManager.ME.net.onDogCaught.add(onDogCaught);
		GameManager.ME.net.onDogDespawn.add(onDogDespawn);
		GameManager.ME.net.onDogItemLanded.add(onDogItemLanded);
		GameManager.ME.net.onDogAteFish.add(onDogAteFish);
		GameManager.ME.net.onPlayerKnockback.add(onPlayerKnockback);
		GameManager.ME.net.onPowerUpSpawn.add(onPowerUpSpawn);
		GameManager.ME.net.onPowerUpPickup.add(onPowerUpPickup);
		GameManager.ME.net.onRocketFired.add(onRocketFired);
		GameManager.ME.net.onRocketUpdate.add(onRocketUpdate);
		GameManager.ME.net.onRocketHit.add(onRocketHit);
		GameManager.ME.net.onRocketDespawn.add(onRocketDespawn);
		GameManager.ME.net.onThrowPotion.add(onThrowPotion);
		GameManager.ME.net.onHungerActive.add(onHungerActive);
		GameManager.ME.net.onHungerExpired.add(onHungerExpired);
		GameManager.ME.net.onThrowBait.add(onThrowBait);
		GameManager.ME.net.onBaitActive.add(onBaitActive);
		GameManager.ME.net.onBaitExpired.add(onBaitExpired);
		GameManager.ME.net.onGravityBombActive.add(onGravityBombActive);
		GameManager.ME.net.onGravityBombExpired.add(onGravityBombExpired);
		GameManager.ME.net.onTimeOfDaySync.add(onTimeOfDaySync);

		// Fish may have been added to the schema before we subscribed
		// (server spawns fish on room creation, before clients join PlayState).
		// Manually check for any existing fish and create renderers.
		var serverState = GameManager.ME.net.getState();
		if (serverState != null) {
			for (id => fish in serverState.fish) {
				onFishAdded(id, fish);
			}
		}
	}

	function onPlayerRemoved(sessionId:String) {
		trace('PlayState: remote player $sessionId left, removing remote player');
		remoteGlowR.remove(sessionId);
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

		QLog.notice('adding fish $fishId: ${fishState.x}, ${fishState.y} alive=${fishState.alive}');

		var newFish = new WaterFish(fishId, fishState.x, fishState.y, null, true, fishState.fishType);
		// Direct reference to the FishState for reading synced fields (position, aiState, etc.)
		newFish.serverFishState = fishState;
		fishSpawner.fishMap.set(fishId, newFish);
		fishSpawner.add(newFish);
		QLog.notice('fish post-add pos: ${newFish.x}, ${newFish.y}');
	}

	function loadLevel(level:String) {
		unload();

		var level = new Level(level);
		if (level.songEvent != "") {
			// FmodManager.PlaySong(level.songEvent);
			TODO.sfx("Play song");
		}
		terrainLayer = level.terrainLayer;
		midGroundGroup.add(terrainLayer);
		waterColliders = level.tileColliders;
		midGroundGroup.add(waterColliders);
		shallowColliders = level.shallowTileColliders;
		midGroundGroup.add(shallowColliders);
		FlxG.worldBounds.copyFrom(terrainLayer.getBounds());
		mainWorldBounds = FlxRect.get();
		mainWorldBounds.copyFrom(FlxG.worldBounds);

		// Build collision map for client-side prediction
		var hitboxJson = openfl.Assets.getText("assets/data/tile-hitboxes.json");
		var col = CollisionMap.fromLevel(level.raw, hitboxJson);
		simulation = new Simulation(col);

		// Use server's current player position if available, otherwise fallback
		var lx:Float = level.spawnPoint.x;
		var ly:Float = level.spawnPoint.y;
		var serverState = GameManager.ME.net.getState();
		if (serverState != null) {
			var myState = serverState.players.get(GameManager.ME.net.mySessionId);
			if (myState != null && (myState.x != 0 || myState.y != 0)) {
				lx = myState.x;
				ly = myState.y;
			}
		}
		player = new Player(lx, ly, this);
		if (GameManager.ME.mySkinIndex >= 0) {
			player.skinIndex = GameManager.ME.mySkinIndex;
			player.swapSkin();
		}
		player.sessionId = GameManager.ME.net.mySessionId;
		player.terrainLayer = terrainLayer;
		player.groundEffectsGroup = midGroundGroup;

		// Wire up client-side prediction — in local mode, use the server's own
		// simulation and player state so they're always in sync (no reconciliation needed)
		if (GameManager.ME.net.isLocal()) {
			player.simulation = GameManager.ME.net.getLocalSimulation();
			player.playerState = GameManager.ME.net.getLocalPlayerState();
		} else {
			player.simulation = simulation;
			player.playerState = new schema.PlayerState();
			player.playerState.x = player.x;
			player.playerState.y = player.y;
			player.playerState.speed = 100;
			player.playerState.width = 16;
			player.playerState.height = 8;
		}

		camera.follow(player, TOPDOWN);
		ySortGroup.add(player);

		for (_ => seshID in GameManager.ME.sessions) {
			var rx:Float = level.spawnPoint.x;
			var ry:Float = level.spawnPoint.y;
			if (serverState != null) {
				var remoteState = serverState.players.get(seshID);
				if (remoteState != null && (remoteState.x != 0 || remoteState.y != 0)) {
					rx = remoteState.x;
					ry = remoteState.y;
				}
			}
			var remote = new Player(rx, ry, this);
			remote.isRemote = true;
			remote.simulation = simulation; // shared simulation for wall collision
			remote.terrainLayer = terrainLayer;
			remote.groundEffectsGroup = midGroundGroup;
			if (GameManager.ME.skins.exists(seshID)) {
				var remoteSkin = GameManager.ME.skins.get(seshID);
				if (remoteSkin >= 0) {
					remote.skinIndex = remoteSkin;
					remote.swapSkin();
				}
			}
			remote.setNetwork(seshID);
			remotePlayers.set(seshID, remote);
			ySortGroup.add(remote);
		}

		// World items, fish, bushes, spawn locations all come from the server
		// (real or local in-process) via start_gameplay -> onRemoteWorldItems / onBushAdded

		waterLayer = level.waterGrid;
		player.makeRock = (rx, ry, big) -> new Rock(rx, ry, big, waterLayer, rockGroup.addRock, rockGroup.onLocalSplash);
		player.makePotion = (rx, ry) -> {
			var r = new Rock(rx, ry, false, waterLayer, null, (lx, ly, _) -> {
				GameManager.ME.net.sendMessage("potion_landed", {x: lx, y: ly});
			});
			r.makeGraphic(8, 8, 0xFF00CC66);
			return r;
		};
		player.makeBait = (rx, ry) -> {
			var r = new Rock(rx, ry, false, waterLayer, null, (lx, ly, _) -> {
				GameManager.ME.net.sendMessage("bait_landed", {x: lx, y: ly});
			});
			r.makeGraphic(8, 8, 0xFFDDAA00); // golden bait placeholder
			return r;
		};
		for (_ => remote in remotePlayers) {
			remote.makeRock = (rx, ry, big) -> new Rock(rx, ry, big, waterLayer, rockGroup.addRock, rockGroup.onRemoteSplash);
			remote.makePotion = (rx, ry) -> {
				var r = new Rock(rx, ry, false, waterLayer, null, null);
				r.makeGraphic(8, 8, 0xFF00CC66);
				return r;
			};
			remote.makeBait = (rx, ry) -> {
				var r = new Rock(rx, ry, false, waterLayer, null, null);
				r.makeGraphic(8, 8, 0xFFDDAA00);
				return r;
			};
		}
		groundFishGroup.setWaterLayer(waterLayer);
		groundFishGroup.onPickedUp = (fx, fy) -> {
			GameManager.ME.net.sendMessage("ground_fish_pickup", {x: fx, y: fy});
		};

		// wire up pickup callbacks for network broadcast
		rockGroup.onPickup = (type, idx) -> {
			GameManager.ME.net.sendItemPickup(type, idx);
		};
		wadersPickup.onPickup = () -> {
			GameManager.ME.net.sendItemPickup("waders", 0);
		};
		pepperPickup.onPickup = () -> {
			GameManager.ME.net.sendItemPickup("pepper", 0);
		};

		player.onBobberLanded = (bx, by) -> {
			if (classifyGround(terrainLayer.sampleColorAt(bx, by)) == "water") {
				FmodManager.PlaySoundOneShot(FmodSFX.BobberLandWater);
				add(new Ripple(bx, by));
			} else {
				FmodManager.PlaySoundOneShot(FmodSFX.BobberLandGround);
			}
			FlxG.camera.shake(0.002, 0.1);
		};

		// Clouds come from server (real or local) via cloud_sync

		add(seagullGroup);

		// shopInterior = new BaitShopInterior();
		// midGroundGroup.add(shopInterior.tilemap);

		inventoryHUD = new InventoryHUD(player.inventory);
		inventoryHUD.cameras = [uiCamera];
		add(inventoryHUD);

		player.inventory.onChange.add(onInventoryChanged);
		onInventoryChanged();

		scoreHUD = new ScoreHUD();
		scoreHUD.cameras = [uiCamera];
		add(scoreHUD);

		for (t in level.camTransitions) {
			transitions.add(t);
		}

		var playerPos = FlxPoint.get(player.x, player.y);
		for (_ => zone in level.camZones) {
			if (zone.containsPoint(playerPos)) {
				setCameraBounds(zone);
				mainCameraBounds = zone;
			}
		}
		playerPos.put();

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

	function onRemoteWorldItems(data:Dynamic) {
		var rockPositions:Array<Dynamic> = data.rocks;
		if (rockPositions != null) {
			var typed:Array<{x:Float, y:Float, big:Bool}> = [];
			for (r in rockPositions) {
				typed.push({x: r.x, y: r.y, big: r.big});
			}
			rockGroup.spawnFromPositions(typed);
		}

		// spawn weeds from host positions
		var weedPositions:Array<Dynamic> = data.weeds;
		if (weedPositions != null) {
			for (w in weedPositions) {
				var weed = new entities.Weed(w.x, w.y, this);
				weed.groundGroup = midGroundGroup;
				weedGroup.add(weed);
			}
		}

		// spawn waders if host sent position
		if (data.wadersX != null && data.wadersY != null) {
			wadersPickup.spawnAt(data.wadersX, data.wadersY);
		}

		// spawn pepper if host sent position
		if (data.pepperX != null && data.pepperY != null) {
			pepperPickup.spawnAt(data.pepperX, data.pepperY);
		}
	}

	function onRemoteItemPickup(sessionId:String, itemType:String, index:Int) {
		var isMe = sessionId == player.sessionId;
		switch (itemType) {
			case "rock":
				rockGroup.removeByIndex(index);
			case "waders":
				wadersPickup.remotePickup();
				// Inventory update comes from server via inventory_update
			case "pepper":
				pepperPickup.remotePickup();
				// Hot mode activation comes from server via onRemoteHotPepper
		}
	}

	function onRemoteWeedBurst(sessionId:String, index:Int) {
		// Tier 2: server confirmed the weed burst — record score for the player
		if (index >= 0 && index < weedGroup.members.length) {
			var weed = weedGroup.members[index];
			if (weed != null && weed.alive) {
				// Remote player or sender whose prediction hasn't fired yet
				weed.burst();
			}
		}
		GameManager.ME.recordWeedKill(sessionId);
	}

	function onRemoteBushIgnite(index:Int) {
		var bush = bushByRectIndex.get(index);
		if (bush != null && bush.alive && !bush.burning) {
			bush.ignite();
		}
	}

	/** Process bush hits from Simulation.hitEntityIndices for any player. */
	function processBushHits(p:Player, contacts:Map<Int, Bool>, isLocal:Bool) {
		for (entityIdx in p.lastHitEntityIndices) {
			var bush = bushByRectIndex.get(entityIdx);
			if (bush == null || !bush.alive) { continue; }
			if (isLocal && p.hotModeActive && !bush.burning) {
				bush.ignite();
				GameManager.ME.net.sendMessage("bush_ignite", {index: entityIdx});
				continue;
			}
			if (!contacts.exists(entityIdx)) {
				contacts.set(entityIdx, true);
				var dx = bush.x + bush.width / 2 - (p.x + p.width / 2);
				var dy = bush.y + bush.height / 2 - (p.y + p.height / 2);
				var dist = Math.sqrt(dx * dx + dy * dy);
				bush.rustleFrom(dist > 0 ? dx / dist : 1.0, dist > 0 ? dy / dist : 0.0);
			}
		}
		// Clear contacts for bushes no longer hit
		for (idx in [for (k in contacts.keys()) k]) {
			var stillHit = false;
			for (h in p.lastHitEntityIndices) {
				if (h == idx) { stillHit = true; break; }
			}
			if (!stillHit) { contacts.remove(idx); }
		}
	}

	function removeEntityRect(index:Int) {
		if (simulation != null && index >= 0 && index < simulation.entityRects.length) {
			simulation.entityRects[index] = {x: 0.0, y: 0.0, w: 0.0, h: 0.0};
		}
	}

	function onRemoteWeedIgnite(index:Int) {
		if (index >= 0 && index < weedGroup.members.length) {
			var weed = weedGroup.members[index];
			if (weed != null && weed.alive && !weed.burning) {
				weed.ignite();
			}
		}
	}

	function onRemotePlayerDrown(sessionId:String, x:Float, y:Float) {
		if (sessionId == player.sessionId) {
			if (!player.drowned) {
				// Offset splash into the water (forward in facing direction)
				var dir = player.lastInputDir.asVector();
				var splashX = player.x + player.width / 2 + dir.x * 12;
				var splashY = player.y + player.height + dir.y * 12;
				dir.put();
				add(new Splash(splashX, splashY, true));
				player.drown();
			}
		} else {
			var remote = remotePlayers.get(sessionId);
			if (remote != null) {
				var dir = remote.lastInputDir.asVector();
				var splashX = x + remote.width / 2 + dir.x * 12;
				var splashY = y + remote.height + dir.y * 12;
				dir.put();
				add(new Splash(splashX, splashY, true));
				remote.drown(x, y);
			}
		}
	}

	var steamEmitter:flixel.effects.particles.FlxEmitter;
	var steamTarget:Player;
	var steamTimer:Float = 0;

	function onPepperExtinguish(data:Dynamic) {
		var sessionId:String = data.sessionId;
		// Deactivate hot mode
		if (sessionId == player.sessionId) {
			player.deactivateHotMode();
			steamTarget = player;
		} else {
			var remote = remotePlayers.get(sessionId);
			if (remote != null) {
				remote.deactivateHotMode();
				steamTarget = remote;
			}
		}
		TODO.sfx("sizzle");
		// Create emitter that follows the player's butt for 2 seconds
		if (steamEmitter != null) { remove(steamEmitter); steamEmitter.destroy(); }
		steamEmitter = new flixel.effects.particles.FlxEmitter(0, 0, 60);
		steamEmitter.makeParticles(6, 6, 0xFFDDDDDD, 60);
		steamEmitter.lifespan.set(0.6, 1.2);
		steamEmitter.speed.set(15, 35);
		steamEmitter.alpha.set(0.8, 0.9, 0.0, 0.0);
		steamEmitter.scale.set(1.5, 2.5, 0.4, 0.6);
		steamEmitter.launchMode = flixel.effects.particles.FlxEmitter.FlxEmitterMode.CIRCLE;
		steamEmitter.launchAngle.set(250, 290); // upward (270° = straight up, ±20° spread)
		steamEmitter.frequency = 0.03;
		steamEmitter.start(false);
		add(steamEmitter);
		steamTimer = 2.0;
	}

	function onRemoteHotPepper(sessionId:String, isStart:Bool) {
		// Server-authoritative hot mode — applies to ALL players including local
		if (sessionId == player.sessionId) {
			if (isStart) {
				player.activateHotMode();
			} else {
				player.deactivateHotMode();
			}
		} else {
			var remote = remotePlayers.get(sessionId);
			if (remote != null) {
				if (isStart) {
					remote.activateHotMode();
				} else {
					remote.deactivateHotMode();
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
		// Server detects fish catches directly and broadcasts fish_caught;
		// no need to send from client.

		// Trigger on the catching player immediately (avoids latency; echo-back is a no-op)
		if (catcherSessionId == player.sessionId) {
			player.onFishDelivered = () -> {
				// Server already added fish to inventory via inventory_update.
				// If inventory was full at catch time, server didn't add — drop ground fish.
				if (player.inventory.isFull()) {
					GameManager.ME.net.sendMessage("ground_fish_drop", {
						playerX: player.x + 8,
						playerY: player.y - 14,
						fishType: player.caughtFishSpriteIndex,
						lengthCm: player.caughtFishLengthCm
					});
				}
				player.onFishDelivered = null;
			};
			player.catchFish(true, catcherSessionId, fishId, fishType);
		} else {
			var remote = remotePlayers.get(catcherSessionId);
			if (remote != null) {
				remote.catchFish(true, catcherSessionId, fishId, fishType);
			}
		}
	}

	function placeBushAt(bx:Float, by:Float) {
		trace('placeBushAt(${bx}, ${by}) bushGroup.length=${bushGroup.length} entityRects=${simulation != null ? simulation.entityRects.length : -1}');
		var bush = new Bush(bx, by, this);
		bush.groundGroup = midGroundGroup;
		bushGroup.add(bush);
		ySortGroup.add(bush);
		if (simulation != null) {
			var rectIdx = simulation.entityRects.length;
			simulation.entityRects.push({x: bx + 2, y: by + 2, w: 10.0, h: 2.0});
			bushByRectIndex.set(rectIdx, bush);
			bush.onDeath = () -> {
				removeEntityRect(rectIdx);
				bushByRectIndex.remove(rectIdx);
				GameManager.ME.net.sendMessage("bush_dead", {index: rectIdx});
				bushGroup.remove(bush, true);
				ySortGroup.remove(bush, true);
			};
		}
	}

	function placeShopAt(sx:Float, sy:Float) {
		shop = new Shop();
		shop.setPosition(sx, sy);
		ySortGroup.add(shop);
	}

	function onRemoteBushAdded(x:Float, y:Float) {
		placeBushAt(x, y);
	}

	function onRemoteShopPlaced(x:Float, y:Float) {
		placeShopAt(x, y);
	}

	function onSpawnLocations(message:Dynamic) {
		// reposition local player and remotes based on server-assigned locations
		var myId = GameManager.ME.net.mySessionId;
		var myPos:Dynamic = Reflect.field(message, myId);
		if (myPos != null) {
			player.setPosition(myPos.x, myPos.y);
			if (player.playerState != null) {
				player.playerState.x = myPos.x;
				player.playerState.y = myPos.y;
			}
			// Clear pending inputs so reconciliation doesn't jump back to old position
			player.clearPendingInputs();
		}
		for (seshID => remote in remotePlayers) {
			var pos:Dynamic = Reflect.field(message, seshID);
			if (pos != null) {
				remote.setPosition(pos.x, pos.y);
			}
		}
	}

	function onRemoteCastStart(sessionId:String, dir:String) {
		var remote = remotePlayers.get(sessionId);
		if (remote != null) {
			remote.remoteStartCharge(dir);
		}
	}

	function onRemoteCastLine(sessionId:String, x:Float, y:Float, dir:String) {
		var remote = remotePlayers.get(sessionId);
		if (remote != null) {
			remote.remoteStartCast(x, y, dir);
		}
	}

	function onRemoteThrowRock(sessionId:String, target:FlxPoint, big:Bool, dir:String) {
		var remote = remotePlayers.get(sessionId);
		if (remote != null) {
			remote.remoteThrowRock(target.x, target.y, big, dir);
		}
	}

	function onRemoteFishCaught(sessionId:String, fishId:String, fishType:Int) {
		// Hide the remote fish sprite — it will fade back in when the host starts moving it again
		var fish = fishSpawner.fishMap.get(fishId);
		if (fish != null) {
			fish.visible = false;
		}

		// Non-host clients receive this to trigger the catch animation
		if (sessionId == player.sessionId) {
			player.onFishDelivered = () -> {
				if (!player.inventory.add(Fish(player.caughtFishSpriteIndex, player.caughtFishLengthCm))) {
					GameManager.ME.net.sendMessage("ground_fish_drop", {
						playerX: player.x + 8,
						playerY: player.y - 14,
						fishType: player.caughtFishSpriteIndex,
						lengthCm: player.caughtFishLengthCm
					});
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

	function onRemoteGroundFishSpawn(data:Dynamic) {
		var startX:Float = data.startX;
		var startY:Float = data.startY;
		var landX:Float = data.landX;
		var landY:Float = data.landY;
		var fishType:Int = Std.int(data.fishType);
		var lengthCm:Int = Std.int(data.lengthCm);
		trace('ground_fish_spawn received: start=($startX,$startY) land=($landX,$landY) type=$fishType');
		groundFishGroup.add(new entities.GroundFish(startX, startY, landX, landY, fishType, lengthCm));
	}

	function onRemoteGroundFishPickup(px:Float, py:Float, sessionId:String) {
		// Local player already killed the fish in handleOverlap — skip the echo
		if (sessionId == player.sessionId) { return; }
		// For remote players, find the closest ground fish and kill it
		var closest:entities.GroundFish = null;
		var closestDist = Math.POSITIVE_INFINITY;
		for (fish in groundFishGroup) {
			if (fish == null || !fish.alive) {
				continue;
			}
			var dx = fish.x - px;
			var dy = fish.y - py;
			var dist = dx * dx + dy * dy;
			if (dist < closestDist) {
				closestDist = dist;
				closest = fish;
			}
		}
		if (closest != null) {
			closest.kill();
		}
	}

	#if FLX_DEBUG
	override public function draw() {
		super.draw();
		// Draw simulation entity rects (green) to compare with Flixel hitboxes
		if (simulation != null && FlxG.camera.debugLayer != null) {
			var gfx = FlxG.camera.debugLayer.graphics;
			var scrollX = FlxG.camera.scroll.x;
			var scrollY = FlxG.camera.scroll.y;
			for (b in simulation.entityRects) {
				gfx.lineStyle(1, 0x00FF00, 0.8);
				gfx.drawRect(b.x - scrollX, b.y - scrollY, b.w, b.h);
			}
		}
	}
	#end

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

	function onTimerSync(runTimeSec:Float, totalSec:Float) {
		timerRunSec = runTimeSec;
		timerTotalSec = totalSec;
		timerSynced = true;
	}

	function onServerAck(serverState:schema.PlayerState) {
		player.reconcileFromServer(serverState);
		player.inShallowWater = serverState.inShallowWater;
	}

	function updateTimerHUD(elapsed:Float) {
		// Server broadcasts timer_sync every 5s; tick locally between syncs for smooth display
		if (timerSynced) {
			timerRunSec += elapsed;
		}

		if (!timerSynced) {
			timerHUD.text = "--:--";
			return;
		}

		var remaining = timerTotalSec - timerRunSec;
		if (remaining < 0) {
			remaining = 0;
		}
		var minutes = Math.floor(remaining / 60);
		var secs = Math.floor(remaining - minutes * 60);
		timerHUD.text = '${minutes}:${secs < 10 ? "0" : ""}${secs}';
	}

	override public function update(elapsed:Float) {
		// Tick game logic (local or networked) BEFORE updating children
		// so Player.update() reads the latest server-computed position
		GameManager.ME.net.update(elapsed);

		super.update(elapsed);

		updateTimerHUD(elapsed);

		if (FlxG.mouse.justPressed) {
			EventBus.fire(new Click(FlxG.mouse.x, FlxG.mouse.y));
		}

		#if db
		checkDebugButtons();
		#end

		// Advance the time-of-day clock locally at the server-given rate; syncs correct drift
		todHour = (todHour + todRate * elapsed) % 24;
		timeHud.setHour(todHour);
		todShader.applyHour(todHour);

		// Candle glow bound to the local player — steady, no flicker
		var lp = FlxPoint.get();
		player.getScreenPosition(lp);
		// Night vision goggles — doubles the light radius + green grain overlay.
		// Whenever the desired state flips (night falls with goggles held, goggles
		// added/removed, morning comes), hold the current look for ~1s first so it
		// feels like the player is reaching up to flick them on/off.
		todNvTime += elapsed;
		var nvDesired = player.inventory.has(NightVision) && todShader.lightStrength > 0.95;
		if (nvDesired != todNvArmed) {
			todNvArmed = nvDesired;
			todNvDelay = 0.5;
		}
		if (todNvDelay > 0) { todNvDelay -= elapsed; }
		var nvTarget:Float = (todNvArmed && todNvDelay <= 0) || (!todNvArmed && todNvDelay > 0 && todNvFactor > 0.5) ? 1.0 : 0.0;
		todNvFactor += (nvTarget - todNvFactor) * Math.min(1, elapsed * 4.0);
		todShader.setNightVision(todNvFactor, todNvTime);

		// Hot pepper turns you into a walking bonfire — ease the radius toward double
		var candleTarget:Float = (player.hotModeActive ? 240 : 120) * (1 + todNvFactor);
		todCandleR += (candleTarget - todCandleR) * Math.min(1, elapsed * 4.0);
		todShader.setLight(lp.x + player.width / 2, lp.y - 4, todCandleR);
		lp.put();

		// Ease remote bonfire glows in/out so they expand/contract instead of popping
		for (sessionId => remote in remotePlayers) {
			var target:Float = (remote != null && remote.alive && remote.hotModeActive) ? 240 : 0;
			var cur = remoteGlowR.exists(sessionId) ? remoteGlowR.get(sessionId) : 0;
			remoteGlowR.set(sessionId, cur + (target - cur) * Math.min(1, elapsed * 4.0));
		}

		// Clouds fade out at night, drift back in come morning
		var isNightNow = todHour >= 21 || todHour < 6;
		var cloudTarget:Float = isNightNow ? 0.0 : 1.0;
		var cf = entities.CloudShadow.visibilityFactor;
		entities.CloudShadow.visibilityFactor = cf + (cloudTarget - cf) * Math.min(1, elapsed * 0.8);

		// Faint glows over ground items + dogs so players can find them in the dark
		if (todShader.lightStrength > 0) {
			collectNightGlows();
		} else {
			todShader.setGlows([]);
		}

		// Hot mode drown is handled server-side in GameLogic.fixedTick()
		// Server broadcasts "player_drown" when a hot player touches water

		// NO FlxG.collide(midGroundGroup, player) — Simulation handles all terrain collision.

		// Remote players use Simulation.tickPlayer in their updateRemoteInterpolation.
		// Bush rustle for remotes is handled below alongside the local player.

		if (insideShop) {
			checkShopExit();
		} else {
			// Bush interaction — driven by Simulation hitEntityIndices.
			// Same system for local AND remote players — one collision path.
			processBushHits(player, localBushContacts, true);
			for (sessionId => remote in remotePlayers) {
				var contacts = remoteBushContacts.get(sessionId);
				if (contacts == null) { contacts = new Map<Int, Bool>(); remoteBushContacts.set(sessionId, contacts); }
				processBushHits(remote, contacts, false);
			}

			// Weed interaction — burst is Tier 2 (stateful, affects score)
			// ignite is Tier 2 (stateful, destroys weed)
			FlxG.overlap(weedGroup, player, (weed:entities.Weed, p:Player) -> {
				if (p.hotModeActive) {
					if (!weed.burning) {
						weed.ignite();
						var index = weedGroup.members.indexOf(weed);
						GameManager.ME.net.sendMessage("weed_ignite", {index: index});
					}
					return;
				}
				if (!weed.alive) { return; }
				var index = weedGroup.members.indexOf(weed);
				// Tier 2: play burst immediately (predicted cosmetic), send to server for scoring
				weed.burst();
				GameManager.ME.net.sendWeedBurst(index);
				// Score is recorded when server confirms via onRemoteWeedBurst
			});
			FlxG.overlap(wormGroup, player, (worm:Worm, _) -> {
				TODO.sfx("worm_squish");
				midGroundGroup.add(new WormSplat(worm.x + worm.width / 2, worm.y + worm.height / 2));
				worm.kill();
				GameManager.ME.net.sendMessage("worm_killed", {id: worm.wormId});
				GameManager.ME.recordWormKill(GameManager.ME.mySessionId);
			});
			if (shop != null && FlxG.overlap(shop, player)) {
				enterShop();
			}

			// inShallowWater is set server-authoritatively via PlayerState schema
			// (local player reads it in onServerAck, remotes in handleChange)
		}

		// Update steam emitter (pepper extinguish — follows player butt)
		if (steamTimer > 0 && steamEmitter != null && steamTarget != null) {
			steamTimer -= elapsed;
			steamEmitter.setPosition(steamTarget.x + steamTarget.width / 2, steamTarget.y + 2);
			if (steamTimer <= 0) {
				steamEmitter.emitting = false;
				var capturedEmitter = steamEmitter;
				flixel.util.FlxTimer.wait(1.5, () -> {
					remove(capturedEmitter);
					capturedEmitter.destroy();
				});
				steamEmitter = null;
				steamTarget = null;
			}
		}

		// Update arcing items (dog-dropped gear)
		var ai = arcingItems.length;
		while (ai-- > 0) {
			var item = arcingItems[ai];
			item.elapsed += elapsed;
			var t = Math.min(1.0, item.elapsed / item.flightTime);
			var gx = item.startX + (item.landX - item.startX) * t;
			var gy = item.startY + (item.landY - item.startY) * t;
			var dist = Math.sqrt((item.landX - item.startX) * (item.landX - item.startX) + (item.landY - item.startY) * (item.landY - item.startY));
			var arcH = Math.min(dist * 0.5, 64);
			item.sprite.setPosition(gx, gy - arcH * 4 * t * (1 - t));
			if (t >= 1.0) {
				if (item.onLand != null) { item.onLand(); }
				arcingItems.splice(ai, 1);
			}
		}

		// Simulate rockets locally (deterministic: straight line + acceleration)
		var hasRockets = false;
		for (rid => rd in rocketData) {
			hasRockets = true;
			rd.speed += 300.0 * elapsed; // ROCKET_ACCELERATION
			if (rd.speed > 350.0) { rd.speed = 350.0; } // ROCKET_MAX_SPEED
			rd.x += rd.dirX * rd.speed * elapsed;
			rd.y += rd.dirY * rd.speed * elapsed;
			var sprite = rocketSprites.get(rid);
			if (sprite != null) {
				sprite.setPosition(rd.x - 4, rd.y - 4);
			}
			var emitter = rocketEmitters.get(rid);
			if (emitter != null) {
				emitter.setPosition(rd.x, rd.y);
			}
		}

		// Toggle fish scare radius debug circles when rockets are in flight
		#if db
		for (fishSprite in fishSpawner.members) {
			if (fishSprite != null) {
				fishSprite.showScareRadius = hasRockets;
			}
		}
		#end

		ySortGroup.sort((order, a, b) -> {
			if (a == null || b == null) { return 0; }
			var objA:flixel.FlxObject = cast a;
			var objB:flixel.FlxObject = cast b;
			return FlxSort.byValues(order, objA.y + objA.height, objB.y + objB.height);
		});

		if (!insideShop) {
			handleCameraBounds();
		}


		// DS "Debug Suite" is how we get to all of our debugging tools
		DS.get(DebugDraw).drawCameraText(50, 50, "hello", DebugLayers.AUDIO);

		if (!insideShop && !player.frozen) {
			// Bobber checks are handled server-side now; no need to set bobbers on fish
			rockGroup.checkPickup(player);
			groundFishGroup.checkPickup(player);
			wadersPickup.checkPickup(player);
			pepperPickup.checkPickup(player);

			// Check ground items (dropped from dog bites)
			var gi = groundItems.length;
			while (gi-- > 0) {
				var gItem = groundItems[gi];
				if (gItem.sprite == null || !gItem.sprite.alive) {
					groundItems.splice(gi, 1);
					continue;
				}
				if (FlxG.overlap(player, gItem.sprite)) {
					if (!player.inventory.isFull()) {
						// Tell server about the pickup — inventory_update will sync
						var encoded = entities.Inventory.encodeItem(gItem.item);
						GameManager.ME.net.sendMessage("ground_item_pickup", {
							x: gItem.sprite.x, y: gItem.sprite.y,
							itemType: encoded.type, fishType: encoded.fishType, lengthCm: encoded.lengthCm
						});
						remove(gItem.sprite);
						gItem.sprite.destroy();
						groundItems.splice(gi, 1);
						break;
					} else {
						player.showInventoryFull(gItem.sprite);
					}
				}
			}

			updateSparkles(elapsed);
		}
	}

	// --- Dog handlers ---

	function onDogSpawn(data:Dynamic) {
		var id:Int = data.id;
		if (serverDogs.exists(id)) { return; }
		var dog = new entities.Dog(id, data.x, data.y);
		serverDogs.set(id, dog);
		ySortGroup.add(dog);
	}

	function onDogUpdate(data:Dynamic) {
		var dog = serverDogs.get(Std.int(data.id));
		if (dog != null) {
			dog.serverUpdate(data.x, data.y, data.velX, data.velY);
		}
	}

	function onDogCaught(data:Dynamic) {
		var sessionId:String = data.sessionId;
		var dogId:Int = data.id;

		if (sessionId == player.sessionId) {
			// Cancel any active cast — reel in the line
			if (player.isCasting()) {
				player.catchFish(false);
			}
			// Freeze + blink
			player.frozen = true;
			trace('DOG CAUGHT: player=(${Std.int(player.x)},${Std.int(player.y)}) frozen=${player.frozen} inventory=${player.inventory.count()}');
			flixel.effects.FlxFlicker.flicker(player, 3.0, 0.13);
			flixel.util.FlxTimer.wait(3.0, () -> {
				player.frozen = false;
			});

			// Server reads inventory and computes drops — just send position
			GameManager.ME.net.sendMessage("dog_item_drop", {
				dogId: dogId,
				playerX: player.x + 8,
				playerY: player.y - 14
			});
		} else {
			var remote = remotePlayers.get(sessionId);
			if (remote != null) {
				flixel.effects.FlxFlicker.flicker(remote, 3.0, 0.13);
			}
		}
	}

	function onDogItemLanded(data:Dynamic) {
		var startX:Float = data.startX;
		var startY:Float = data.startY;
		var landX:Float = data.landX;
		var landY:Float = data.landY;
		var itemType:String = data.itemType;
		var itemData:Dynamic = data.itemData;
		trace('DOG ITEM LANDED: type=${itemType} start=(${Std.int(startX)},${Std.int(startY)}) land=(${Std.int(landX)},${Std.int(landY)}) player=(${Std.int(player.x)},${Std.int(player.y)}) frozen=${player.frozen}');

		switch (itemType) {
			case "fish":
				var fishType:Int = itemData.fishType != null ? Std.int(itemData.fishType) : 0;
				var lengthCm:Int = itemData.lengthCm != null ? Std.int(itemData.lengthCm) : 10;
				groundFishGroup.add(new entities.GroundFish(startX, startY, landX, landY, fishType, lengthCm));
			case "rock":
				var big:Bool = itemData.big == true;
				var rs = new FlxSprite(startX, startY);
				rs.makeGraphic(8, 8, 0xFF888888);
				add(rs);
				spawnArcItem(rs, startX, startY, landX, landY, () -> {
					remove(rs); rs.destroy();
					rockGroup.addRock(landX, landY, big);
				});
			case "waders":
				var ws = new FlxSprite(startX, startY);
				ws.makeGraphic(8, 8, 0xFF0088FF);
				add(ws);
				spawnArcItem(ws, startX, startY, landX, landY, () -> {
					remove(ws); ws.destroy();
					wadersPickup.spawnAt(landX, landY);
				});
			case "rocket":
				var rk = new FlxSprite(startX, startY);
				rk.makeGraphic(8, 8, 0xFFFF4400);
				add(rk);
				spawnArcItem(rk, startX, startY, landX, landY, () -> {
					groundItems.push({sprite: rk, item: Rocket});
				});
			case "potion":
				var pt = new FlxSprite(startX, startY);
				pt.makeGraphic(8, 8, 0xFF00CC66);
				add(pt);
				spawnArcItem(pt, startX, startY, landX, landY, () -> {
					groundItems.push({sprite: pt, item: HungerPotion});
				});
			case "bait":
				var bt = new FlxSprite(startX, startY);
				bt.makeGraphic(8, 8, 0xFFDDAA00);
				add(bt);
				spawnArcItem(bt, startX, startY, landX, landY, () -> {
					groundItems.push({sprite: bt, item: FishBait});
				});
			case "gravity_bomb":
				var gb = new FlxSprite(startX, startY);
				gb.makeGraphic(8, 8, 0xFF7722CC);
				add(gb);
				spawnArcItem(gb, startX, startY, landX, landY, () -> {
					groundItems.push({sprite: gb, item: GravityBomb});
				});
		}
	}

	function spawnArcItem(sprite:FlxSprite, sx:Float, sy:Float, lx:Float, ly:Float, onLand:Void->Void) {
		var dist = Math.sqrt((lx - sx) * (lx - sx) + (ly - sy) * (ly - sy));
		arcingItems.push({
			sprite: sprite, startX: sx, startY: sy, landX: lx, landY: ly,
			flightTime: if (dist > 0) dist / 200 else 0.01, elapsed: 0, onLand: onLand
		});
	}

	function onDogAteFish(data:Dynamic) {
		// Remove the ground fish closest to where the dog picked it up
		var fx:Float = data.x;
		var fy:Float = data.y;
		var closest:entities.GroundFish = null;
		var closestDist = Math.POSITIVE_INFINITY;
		for (gf in groundFishGroup) {
			if (gf == null || !gf.alive) { continue; }
			var fish:entities.GroundFish = cast gf;
			var dx = fish.x - fx;
			var dy = fish.y - fy;
			var dist = dx * dx + dy * dy;
			if (dist < closestDist) {
				closestDist = dist;
				closest = fish;
			}
		}
		if (closest != null) {
			closest.kill();
		}
	}

	function onDogDespawn(data:Dynamic) {
		var id:Int = data.id;
		var dog = serverDogs.get(id);
		if (dog != null) {
			ySortGroup.remove(dog);
			dog.destroy();
			serverDogs.remove(id);
		}
	}

	// ── Power-Up / Rocket ──

	function onPlayerKnockback(data:Dynamic) {
		var sessionId:String = data.sessionId;
		var duration:Float = data.duration;
		if (sessionId == player.sessionId) {
			player.knockbackTimer = duration;
		} else {
			var remote = remotePlayers.get(sessionId);
			if (remote != null) {
				remote.knockbackTimer = duration;
			}
		}
	}

	function onPowerUpSpawn(data:Dynamic) {
		if (powerUpSprite != null) {
			powerUpSprite.kill();
		}
		powerUpSprite = new FlxSprite(data.x - 8, data.y - 8);
		powerUpSprite.makeGraphic(16, 16, 0xFFFF00FF); // magenta box placeholder
		ySortGroup.add(powerUpSprite);
	}

	function onPowerUpPickup(data:Dynamic) {
		var sessionId:String = data.sessionId;
		if (powerUpSprite != null) {
			ySortGroup.remove(powerUpSprite);
			powerUpSprite.destroy();
			powerUpSprite = null;
		}
		if (sessionId == player.sessionId) {
			// Inventory update comes from server via inventory_update
			TODO.sfx("powerup_pickup");
		}
	}

	// ── Time of Day ──

	function onTimeOfDaySync(data:Dynamic) {
		todHour = data.hour;
		todRate = data.rate;
	}

	/** Gather screen-space glow spots (items on the ground, dogs) for the night shader. Max 16. */
	function collectNightGlows() {
		var flat:Array<Float> = [];
		var scrollX = FlxG.camera.scroll.x;
		var scrollY = FlxG.camera.scroll.y;

		function addGlow(wx:Float, wy:Float, radius:Float, strength:Float = 0.6) {
			if (flat.length >= 16 * 4) { return; }
			var sx = wx - scrollX;
			var sy = wy - scrollY;
			// skip glows well off-screen
			if (sx < -radius || sx > FlxG.width + radius || sy < -radius || sy > FlxG.height + radius) { return; }
			flat.push(sx);
			flat.push(sy);
			flat.push(radius);
			flat.push(strength);
		}

		// Burning trees blaze at full strength — add first so they never get capped out
		for (bush in bushGroup) {
			if (bush != null && bush.alive && bush.burning) {
				addGlow(bush.x + bush.width / 2, bush.y + bush.height / 2, 90, 1.0);
			}
		}
		// Remote players on fire are walking bonfires — eased radius (grows/shrinks with pepper)
		for (sessionId => remote in remotePlayers) {
			var r = remoteGlowR.exists(sessionId) ? remoteGlowR.get(sessionId) : 0;
			if (remote != null && remote.alive && r > 4) {
				addGlow(remote.x + remote.width / 2, remote.y - 4, r, 1.0);
			}
		}
		// Rockets in flight burn extra bright (strength > 1 widens the fully-lit core)
		for (rd in rocketData) {
			addGlow(rd.x, rd.y, 60, 2.0);
		}
		for (rock in rockGroup) {
			if (rock != null && rock.alive && rock.exists) {
				addGlow(rock.x + rock.width / 2, rock.y + rock.height / 2, 22);
			}
		}
		for (gf in groundFishGroup) {
			if (gf != null && gf.alive && gf.exists) {
				addGlow(gf.x + gf.width / 2, gf.y + gf.height / 2, 22);
			}
		}
		for (gItem in groundItems) {
			if (gItem.sprite != null && gItem.sprite.alive) {
				addGlow(gItem.sprite.x + gItem.sprite.width / 2, gItem.sprite.y + gItem.sprite.height / 2, 22);
			}
		}
		if (powerUpSprite != null && powerUpSprite.alive) {
			addGlow(powerUpSprite.x + powerUpSprite.width / 2, powerUpSprite.y + powerUpSprite.height / 2, 24);
		}
		if (wadersPickup != null && wadersPickup.alive && wadersPickup.visible) {
			addGlow(wadersPickup.x + wadersPickup.width / 2, wadersPickup.y + wadersPickup.height / 2, 22);
		}
		if (pepperPickup != null && pepperPickup.alive && pepperPickup.visible) {
			addGlow(pepperPickup.x + pepperPickup.width / 2, pepperPickup.y + pepperPickup.height / 2, 22);
		}
		for (dog in serverDogs) {
			if (dog != null && dog.alive) {
				addGlow(dog.x, dog.y, 28); // dog x,y is its center
			}
		}

		todShader.setGlows(flat);
	}

	// ── Gravity Bomb ──

	function onGravityBombActive(data:Dynamic) {
		var bx:Float = data.x;
		var by:Float = data.y;
		// The well lives on the shared Simulation, so local prediction + reconciliation
		// replay apply the same additive pull the server does.
		if (simulation != null) {
			simulation.gravityWell = {x: bx, y: by};
		}
		if (gravityBombSprite != null) {
			ySortGroup.remove(gravityBombSprite);
			gravityBombSprite.destroy();
		}
		gravityBombSprite = new entities.GravityBomb(bx, by, midGroundGroup);
		ySortGroup.add(gravityBombSprite);
		TODO.sfx("gravity_bomb");
	}

	function onGravityBombExpired(data:Dynamic) {
		if (simulation != null) {
			simulation.gravityWell = null;
		}
		if (gravityBombSprite != null) {
			ySortGroup.remove(gravityBombSprite);
			gravityBombSprite.destroy();
			gravityBombSprite = null;
		}
	}

	function onRocketFired(data:Dynamic) {
		var rid:Int = data.id;
		var rx:Float = data.x;
		var ry:Float = data.y;
		var dirX:Float = data.dirX;
		var dirY:Float = data.dirY;
		var sprite = new FlxSprite(rx - 4, ry - 4);
		sprite.makeGraphic(8, 8, 0xFFFF4400); // orange rocket placeholder
		ySortGroup.add(sprite);
		rocketSprites.set(rid, sprite);
		rocketData.set(rid, {x: rx, y: ry, dirX: dirX, dirY: dirY, speed: 40.0});

		// Trailing smoke emitter
		var emitter = new flixel.effects.particles.FlxEmitter(rx, ry, 500);
		emitter.makeParticles(6, 6, 0xFFBBBBBB, 500);
		emitter.lifespan.set(0.5, 1.2);
		// Spray smoke backwards from the rocket's direction
		var smokeSpeedMin:Float = 20;
		var smokeSpeedMax:Float = 60;
		var backAngle = Math.atan2(-dirY, -dirX) * 180 / Math.PI; // opposite of travel dir
		emitter.launchMode = flixel.effects.particles.FlxEmitter.FlxEmitterMode.CIRCLE;
		emitter.launchAngle.set(backAngle - 50, backAngle + 50); // 100 degree spread behind rocket
		emitter.speed.set(smokeSpeedMin, smokeSpeedMax);
		emitter.alpha.set(0.9, 0.9, 0.0, 0.0);
		emitter.scale.set(1.5, 2.5, 0.3, 0.5);
		emitter.frequency = 0.001;
		emitter.start(false);
		emitter.start(false);
		add(emitter);
		rocketEmitters.set(rid, emitter);

		TODO.sfx("rocket_fire");
	}

	function onRocketUpdate(data:Dynamic) {
		// Clients simulate locally — server updates not used
	}

	function removeRocket(rid:Int) {
		var sprite = rocketSprites.get(rid);
		if (sprite != null) {
			ySortGroup.remove(sprite);
			sprite.destroy();
			rocketSprites.remove(rid);
		}
		rocketData.remove(rid);
		var emitter = rocketEmitters.get(rid);
		if (emitter != null) {
			emitter.emitting = false;
			// Let remaining particles fade out, then remove
			flixel.util.FlxTimer.wait(1.0, () -> {
				remove(emitter);
				emitter.destroy();
			});
			rocketEmitters.remove(rid);
		}
	}

	function onRocketHit(data:Dynamic) {
		var rid:Int = data.id;
		var targetSessionId:String = data.targetSessionId;

		removeRocket(rid);

		TODO.sfx("rocket_hit");

		// Stun the target player (same as dog caught)
		if (targetSessionId == player.sessionId) {
			if (player.isCasting()) {
				player.catchFish(false);
			}
			player.frozen = true;
			flixel.effects.FlxFlicker.flicker(player, 3.0, 0.13);
			flixel.util.FlxTimer.wait(3.0, () -> {
				player.frozen = false;
			});

			// Server reads inventory and computes drops
			GameManager.ME.net.sendMessage("dog_item_drop", {
				dogId: -1,
				playerX: player.x + 8,
				playerY: player.y - 14
			});
		} else {
			var remote = remotePlayers.get(targetSessionId);
			if (remote != null) {
				flixel.effects.FlxFlicker.flicker(remote, 3.0, 0.13);
			}
		}
	}

	function onRocketDespawn(data:Dynamic) {
		removeRocket(data.id);
	}

	function onRockSplash(sx:Float, sy:Float, big:Bool) {
		rockGroup.onRemoteSplash(sx, sy, big);
		// Scare fish visually — all fish are in fishSpawner now
		var radius = if (big) 160.0 else 80.0;
		for (fishSprite in fishSpawner.members) {
			if (fishSprite == null || !fishSprite.alive) { continue; }
			var dx = (fishSprite.x + fishSprite.width / 2) - sx;
			var dy = (fishSprite.y + fishSprite.height / 2) - sy;
			if (dx * dx + dy * dy < radius * radius) {
				fishSprite.scare(sx, sy);
			}
		}
	}

	function onThrowPotion(data:Dynamic) {
		var sessionId:String = data.sessionId;
		if (sessionId == player.sessionId) { return; } // local player already threw
		var remote = remotePlayers.get(sessionId);
		if (remote != null) {
			remote.remoteThrowRock(data.targetX, data.targetY, false, data.dir);
		}
	}

	function onHungerActive(data:Dynamic) {
		TODO.sfx("hunger_potion");
		var landX:Float = data.x;
		var landY:Float = data.y;
		// Flood-fill from landing position to find the water body, then tint those tiles
		if (waterLayer != null) {
			var gs = waterLayer.gridSize;
			var startCx = Std.int(landX / gs);
			var startCy = Std.int(landY / gs);
			if (waterLayer.getInt(startCx, startCy) == 1) {
				// Flood-fill to find all tiles in this water body
				var visited = new Map<Int, Bool>();
				var queue = new Array<Int>();
				var key = startCy * waterLayer.cWid + startCx;
				queue.push(key);
				visited.set(key, true);
				while (queue.length > 0) {
					var k = queue.shift();
					var cx = k % waterLayer.cWid;
					var cy = Std.int(k / waterLayer.cWid);
					for (d in [{dx: 0, dy: -1}, {dx: 0, dy: 1}, {dx: -1, dy: 0}, {dx: 1, dy: 0}]) {
						var nx = cx + d.dx;
						var ny = cy + d.dy;
						if (nx < 0 || nx >= waterLayer.cWid || ny < 0 || ny >= waterLayer.cHei) { continue; }
						var nk = ny * waterLayer.cWid + nx;
						if (visited.exists(nk)) { continue; }
						if (waterLayer.getInt(nx, ny) != 1) { continue; }
						visited.set(nk, true);
						queue.push(nk);
					}
				}
				// Create overlay sprites for each water tile in the body
				if (hungerOverlay != null) { remove(hungerOverlay); hungerOverlay.destroy(); }
				hungerOverlay = new FlxSprite();
				hungerOverlay.makeGraphic(waterLayer.cWid * gs, waterLayer.cHei * gs, 0x00000000);
				// Fill the water body tiles with a green tint
				flixel.util.FlxSpriteUtil.drawRect(hungerOverlay, 0, 0, 0, 0, 0x00000000); // ensure pixels exist
				for (k => _ in visited) {
					var cx = k % waterLayer.cWid;
					var cy = Std.int(k / waterLayer.cWid);
					flixel.util.FlxSpriteUtil.drawRect(hungerOverlay, cx * gs, cy * gs, gs, gs, 0x2200FF66);
				}
				add(hungerOverlay);
			}
		}
	}

	function onHungerExpired(data:Dynamic) {
		if (hungerOverlay != null) {
			remove(hungerOverlay);
			hungerOverlay.destroy();
			hungerOverlay = null;
		}
	}

	function onThrowBait(data:Dynamic) {
		var sessionId:String = data.sessionId;
		if (sessionId == player.sessionId) { return; }
		var remote = remotePlayers.get(sessionId);
		if (remote != null) {
			remote.remoteThrowRock(data.targetX, data.targetY, false, data.dir);
		}
	}

	function onBaitActive(data:Dynamic) {
		TODO.sfx("bait_splash");
		var cx:Float = data.x;
		var cy:Float = data.y;
		var rx:Float = data.radiusX;
		var ry:Float = data.radiusY;
		// Draw a golden oval overlay at the bait zone
		var diam = Std.int(rx * 2);
		var diamY = Std.int(ry * 2);
		if (baitOverlay != null) { remove(baitOverlay); baitOverlay.destroy(); }
		baitOverlay = new FlxSprite();
		baitOverlay.makeGraphic(diam, diamY, 0x00000000);
		// Draw filled oval
		for (py in 0...diamY) {
			for (px in 0...diam) {
				var dx = (px - rx) / rx;
				var dy = (py - ry) / ry;
				if (dx * dx + dy * dy < 1) {
					baitOverlay.pixels.setPixel32(px, py, 0x22DDAA00);
				}
			}
		}
		baitOverlay.dirty = true;
		baitOverlay.setPosition(cx - rx, cy - ry);
		add(baitOverlay);
	}

	function onBaitExpired(data:Dynamic) {
		if (baitOverlay != null) {
			remove(baitOverlay);
			baitOverlay.destroy();
			baitOverlay = null;
		}
	}

	function onInventoryUpdate(data:Dynamic) {
		var prevCount = player.inventory.count();
		player.inventory.syncFromServer(data.items);
		if (player.inventory.count() > prevCount) {
			FmodManager.PlaySoundOneShot(FmodSFX.ItemCollect);
		}
	}

	function onServerCloudSync(data:Dynamic) {
		var cloudArray:Array<Dynamic> = data.clouds;
		if (cloudArray != null) {
			for (cd in cloudArray) {
				add(CloudShadow.fromServer(cd));
			}
		}
	}

	function onRemoteWormKilled(sessionId:String, wormId:Int) {
		for (worm in wormGroup) {
			if (worm != null && worm.alive && worm.wormId == wormId) {
				TODO.sfx("worm_squish");
				midGroundGroup.add(new WormSplat(worm.x + worm.width / 2, worm.y + worm.height / 2));
				worm.kill();
				break;
			}
		}
	}

	function onServerWormSpawn(data:Dynamic) {
		var w = new Worm(data.srcX, data.srcY, data.destX, data.destY);
		w.wormId = Std.int(data.id);
		wormGroup.add(w);
	}

	function onServerSeagullSpawn(data:Dynamic) {
		var gull = Seagull.fromServer(data, this, midGroundGroup, terrainLayer);
		seagullGroup.add(gull);
		serverSeagulls.set(gull.seagullId, gull);
	}

	function onServerSeagullPoop(data:Dynamic) {
		// Create a poop projectile at the given position. Fish scare is handled server-side.
		var poopX:Float = data.x;
		var poopY:Float = data.y;
		var fallDist:Float = data.fallDist;
		var birdVelX:Float = data.birdVelX;
		add(new SeagullPoop(poopX, poopY, fallDist, birdVelX, this, midGroundGroup, terrainLayer));
	}

	function onServerSeagullDespawn(data:Dynamic) {
		var sid:Int = Std.int(data.id);
		var gull = serverSeagulls.get(sid);
		if (gull != null) {
			seagullGroup.remove(gull, true);
			gull.destroy();
			serverSeagulls.remove(sid);
		}
	}

	function updateWorms(elapsed:Float) {
		if (terrainLayer == null) {
			return;
		}
		wormTimer -= elapsed;
		if (wormTimer > 0) {
			return;
		}
		wormTimer = FlxG.random.float(2.5, 4.5);

		var bounds = FlxG.worldBounds;
		var grid = 16;

		for (_ in 0...10) {
			var srcX = FlxG.random.float(bounds.x + grid, bounds.right - grid);
			var srcY = FlxG.random.float(bounds.y + grid, bounds.bottom - grid);

			if (classifyGround(terrainLayer.sampleColorAt(srcX, srcY)) != "dirt") {
				continue;
			}
			if (terrainLayer.isShallowAt(srcX, srcY) || terrainLayer.isSolidAt(srcX, srcY)) {
				continue;
			}

			var dirs = [{dx: 1, dy: 0}, {dx: -1, dy: 0}];
			FlxG.random.shuffle(dirs);

			var spawned = false;
			for (dir in dirs) {
				var dist = FlxG.random.int(2, 4);
				var destX = srcX + dir.dx * dist * grid;
				var destY = srcY + dir.dy * dist * grid;

				if (destX < bounds.x || destX >= bounds.right || destY < bounds.y || destY >= bounds.bottom) {
					continue;
				}

				if (classifyGround(terrainLayer.sampleColorAt(destX, destY)) != "dirt") {
					continue;
				}
				if (terrainLayer.isShallowAt(destX, destY) || terrainLayer.isSolidAt(destX, destY)) {
					continue;
				}

				var pathClear = true;
				for (step in 1...dist) {
					var checkX = srcX + dir.dx * step * grid;
					var checkY = srcY + dir.dy * step * grid;
					if (classifyGround(terrainLayer.sampleColorAt(checkX, checkY)) != "dirt") {
						pathClear = false;
						break;
					}
					if (terrainLayer.isShallowAt(checkX, checkY) || terrainLayer.isSolidAt(checkX, checkY)) {
						pathClear = false;
						break;
					}
				}

				if (pathClear) {
					wormGroup.add(new Worm(srcX, srcY, destX, destY));
					spawned = true;
					break;
				}
			}

			if (spawned) {
				break;
			}
		}
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

	function enterShop() {
		insideShop = true;
		shopReturnX = shop.x + shop.width / 2;
		shopReturnY = shop.y + shop.height + 4;

		// Cancel any active casting or throwing before teleport
		player.cancelAllActions();

		// Sell fish on entry
		shop.sellFish(player);

		// Teleport player into the shop interior
		player.setPosition(shopInterior.spawnPoint.x, shopInterior.spawnPoint.y);
		FlxG.worldBounds.copyFrom(shopInterior.worldBounds);
		setCameraBounds(shopInterior.cameraBounds);
	}

	function checkShopExit() {
		if (shopInterior.isPlayerPastExit(player.y, player.height)) {
			exitShop();
		}
	}

	function exitShop() {
		insideShop = false;
		player.setPosition(shopReturnX, shopReturnY);

		FlxG.worldBounds.copyFrom(mainWorldBounds);
		if (mainCameraBounds != null) {
			setCameraBounds(mainCameraBounds);
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
