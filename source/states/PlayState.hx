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
	var remoteFish:Map<String, WaterFish> = new Map();

	var midGroundGroup = new FlxGroup();
	var ySortGroup = new FlxGroup();
	var serverFishGroup = new FlxGroup();
	var bushGroup = new FlxTypedGroup<Bush>();
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
		add(weedGroup);
		add(rockGroup);
		add(groundFishGroup);
		add(wadersPickup);
		add(pepperPickup);
		add(fishSpawner);
		add(serverFishGroup);
		add(wormGroup);
		add(ySortGroup);
		add(transitions);

		setupNetwork();
		GameManager.ME.net.connect(Configure.getServerURL(), Configure.getServerPort());

		loadLevel("Level_0");

		if (round != null) {
			round.initialize(this);
		}

		timerHUD = new FlxText(0, 4, FlxG.width, "--:--");
		timerHUD.size = 16;
		timerHUD.alignment = FlxTextAlign.CENTER;
		timerHUD.color = FlxColor.WHITE;
		timerHUD.scrollFactor.set(0, 0);
		add(timerHUD);

		GameManager.ME.net.sendMessage("round_update", {
			status: RoundState.STATUS_ACTIVE,
		});

		#if db
		addDebugButtons();
		#end
	}

	#if db
	function addDebugButtons() {
		var labels = ["Rock", "Big Rock", "Pepper", "Waders", "End Round"];
		var btnW = 60;
		var btnH = 16;
		var margin = 4;
		var startX = FlxG.width - btnW - margin;
		var startY = 40;
		for (i in 0...labels.length) {
			var bg = new FlxSprite(startX, startY + i * (btnH + margin));
			bg.makeGraphic(btnW, btnH, FlxColor.fromRGB(40, 40, 40, 180));
			bg.scrollFactor.set(0, 0);
			add(bg);
			var label = new FlxText(startX, startY + i * (btnH + margin) + 1, btnW, labels[i]);
			label.size = 8;
			label.alignment = FlxTextAlign.CENTER;
			label.color = FlxColor.WHITE;
			label.scrollFactor.set(0, 0);
			add(label);
		}
	}

	function checkDebugButtons() {
		if (FlxG.mouse.justPressedRight) {
			player.setPosition(FlxG.mouse.x, FlxG.mouse.y);
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
		for (i in 0...5) {
			var by = startY + i * (btnH + margin);
			if (my >= by && my < by + btnH) {
				switch (i) {
					case 0:
						player.inventory.add(Rock);
					case 1:
						player.inventory.add(BigRock);
					case 2:
						if (player.hotModeActive) {
							player.deactivateHotMode();
						} else {
							player.activateHotMode(99);
						}
					case 3:
						if (player.inventory.hasWaders()) {
							player.inventory.remove(Waders);
							GameManager.ME.net.sendItemPickup("waders_remove", 0);
						} else {
							player.inventory.add(Waders);
							GameManager.ME.net.sendItemPickup("waders", 0);
						}
					case 4:
						// end round: set local timer to near-end for display
						// server owns the real timer, so this is just a local preview
						if (round != null) {
							for (goal in round.getGoals()) {
								if (Std.isOfType(goal, goals.TimedGoal)) {
									goal.runTimeSec = timerTotalSec - 1;
								}
							}
						}
						timerRunSec = timerTotalSec - 1;
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
		GameManager.ME.net.onRockSplash.remove(rockGroup.onRemoteSplash);
		GameManager.ME.net.onThrowRock.remove(onRemoteThrowRock);
		GameManager.ME.net.onBushAdded.remove(onRemoteBushAdded);
		GameManager.ME.net.onShopPlaced.remove(onRemoteShopPlaced);
		GameManager.ME.net.onWorldItems.remove(onRemoteWorldItems);
		GameManager.ME.net.onItemPickup.remove(onRemoteItemPickup);
		GameManager.ME.net.onWeedBurst.remove(onRemoteWeedBurst);
		GameManager.ME.net.onBushRustle.remove(onRemoteBushRustle);
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
		GameManager.ME.net.onRockSplash.add(rockGroup.onRemoteSplash);
		GameManager.ME.net.onThrowRock.add(onRemoteThrowRock);
		GameManager.ME.net.onBushAdded.add(onRemoteBushAdded);
		GameManager.ME.net.onShopPlaced.add(onRemoteShopPlaced);
		GameManager.ME.net.onWorldItems.add(onRemoteWorldItems);
		GameManager.ME.net.onItemPickup.add(onRemoteItemPickup);
		GameManager.ME.net.onWeedBurst.add(onRemoteWeedBurst);
		GameManager.ME.net.onBushRustle.add(onRemoteBushRustle);
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
		// Tell server we're ready — triggers cloud sync, existing seagulls, and starts spawning
		GameManager.ME.net.sendMessage("start_gameplay", {});
		GameManager.ME.net.onWormSpawn.add(onServerWormSpawn);
		GameManager.ME.net.onSeagullSpawn.add(onServerSeagullSpawn);
		GameManager.ME.net.onSeagullPoop.add(onServerSeagullPoop);
		GameManager.ME.net.onSeagullDespawn.add(onServerSeagullDespawn);

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
		remoteFish.set(fishId, newFish);
		fishSpawner.fishMap.set(fishId, newFish);
		serverFishGroup.add(newFish);
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

		// static spawn points near top-left for easy testing
		var allSessionIds = [GameManager.ME.net.mySessionId];
		for (_ => seshID in GameManager.ME.sessions) {
			allSessionIds.push(seshID);
		}
		var spawnMap = new Map<String, {x:Float, y:Float}>();
		for (i in 0...allSessionIds.length) {
			spawnMap.set(allSessionIds[i], {x: 100.0 + i * 40, y: 100.0});
		}

		var localPos = spawnMap.get(GameManager.ME.net.mySessionId);
		var lx = localPos != null ? localPos.x : 100;
		var ly = localPos != null ? localPos.y : 100;
		player = new Player(lx, ly, this);
		if (GameManager.ME.mySkinIndex >= 0) {
			player.skinIndex = GameManager.ME.mySkinIndex;
			player.swapSkin();
		}
		player.sessionId = GameManager.ME.net.mySessionId;
		player.terrainLayer = terrainLayer;
		player.groundEffectsGroup = midGroundGroup;

		// Wire up client-side prediction
		player.simulation = simulation;
		player.playerState = new schema.PlayerState();
		player.playerState.x = player.x;
		player.playerState.y = player.y;
		player.playerState.speed = 100;
		player.playerState.width = 16;
		player.playerState.height = 8;

		camera.follow(player, TOPDOWN);
		ySortGroup.add(player);

		for (_ => seshID in GameManager.ME.sessions) {
			var remotePos = spawnMap.get(seshID);
			var rx = remotePos != null ? remotePos.x : level.spawnPoint.x;
			var ry = remotePos != null ? remotePos.y : level.spawnPoint.y;
			var remote = new Player(rx, ry, this);
			remote.isRemote = true;
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
		for (_ => remote in remotePlayers) {
			remote.makeRock = (rx, ry, big) -> new Rock(rx, ry, big, waterLayer, rockGroup.addRock, rockGroup.onRemoteSplash);
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
		add(inventoryHUD);

		player.inventory.onChange.add(onInventoryChanged);
		onInventoryChanged();

		scoreHUD = new ScoreHUD();
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
		switch (itemType) {
			case "rock":
				rockGroup.removeByIndex(index);
			case "waders":
				wadersPickup.remotePickup();
			case "pepper":
				pepperPickup.remotePickup();
		}
	}

	function onRemoteWeedBurst(sessionId:String, index:Int) {
		if (index >= 0 && index < weedGroup.members.length) {
			var weed = weedGroup.members[index];
			if (weed != null && weed.alive) {
				weed.burst();
			}
		}
		GameManager.ME.recordWeedKill(sessionId);
	}

	function onRemoteBushRustle(index:Int, dirX:Float, dirY:Float) {
		if (index >= 0 && index < bushGroup.members.length) {
			var bush = bushGroup.members[index];
			if (bush != null && bush.alive) {
				bush.rustleFrom(dirX, dirY);
			}
		}
	}

	function onRemoteBushIgnite(index:Int) {
		if (index >= 0 && index < bushGroup.members.length) {
			var bush = bushGroup.members[index];
			if (bush != null && bush.alive && !bush.burning) {
				bush.ignite();
			}
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
		var remote = remotePlayers.get(sessionId);
		if (remote != null) {
			add(new Splash(x + remote.width / 2, y + remote.height, true));
			remote.drown(x, y);
		}
	}

	function onRemoteHotPepper(sessionId:String, isStart:Bool) {
		var remote = remotePlayers.get(sessionId);
		if (remote == null) {
			return;
		}
		if (isStart) {
			remote.activateHotMode();
		} else {
			remote.deactivateHotMode();
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
				if (!player.inventory.add(Fish(player.caughtFishSpriteIndex, player.caughtFishLengthCm))) {
					// tell server to compute and broadcast landing position
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
		var bush = new Bush(bx, by, this);
		bush.groundGroup = midGroundGroup;
		bushGroup.add(bush);
		ySortGroup.add(bush);
		if (simulation != null) {
			var rectIdx = simulation.entityRects.length;
			simulation.entityRects.push({x: bx + 2, y: by + 2, w: 10.0, h: 2.0});
			bush.onDeath = () -> {
				removeEntityRect(rectIdx);
				GameManager.ME.net.sendMessage("bush_dead", {index: rectIdx});
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
		var fish = remoteFish.get(fishId);
		if (fish != null)
			fish.visible = false;

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

	function onRemoteGroundFishPickup(px:Float, py:Float) {
		// find the closest ground fish to the reported position and kill it
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
		super.update(elapsed);

		GameManager.ME.net.update(elapsed);

		updateTimerHUD(elapsed);

		if (FlxG.mouse.justPressed) {
			EventBus.fire(new Click(FlxG.mouse.x, FlxG.mouse.y));
		}

		#if db
		checkDebugButtons();
		#end

		// hot player touching water = drown (check before collide separates them)
		// waders protect you — just cancel pepper and wade normally
		if (player.hotModeActive && !player.drowned) {
			if (FlxG.overlap(waterColliders, player) || FlxG.overlap(shallowColliders, player)) {
				if (player.inventory.hasWaders()) {
					player.deactivateHotMode();
				} else {
					add(new Splash(player.x + player.width / 2, player.y + player.height, true));
					player.drown();
					GameManager.ME.net.sendMessage("player_drown", {x: player.x, y: player.y});
				}
			}
		}

		FlxG.collide(midGroundGroup, player);

		if (insideShop) {
			checkShopExit();
		} else {
			FlxG.collide(bushGroup, player, (bush:Bush, p:Player) -> {
				if (p.hotModeActive && !bush.burning) {
					bush.ignite();
					var index = bushGroup.members.indexOf(bush);
					GameManager.ME.net.sendMessage("bush_ignite", {index: index});
					return;
				}
				var dx = bush.x + bush.width / 2 - (p.x + p.width / 2);
				var dy = bush.y + bush.height / 2 - (p.y + p.height / 2);
				var dist = Math.sqrt(dx * dx + dy * dy);
				var dirX = dist > 0 ? dx / dist : 1.0;
				var dirY = dist > 0 ? dy / dist : 0.0;
				bush.rustleFrom(dirX, dirY);
				var index = bushGroup.members.indexOf(bush);
				GameManager.ME.net.sendBushRustle(index, dirX, dirY);
			});
			FlxG.overlap(weedGroup, player, (weed:entities.Weed, p:Player) -> {
				if (p.hotModeActive) {
					if (!weed.burning) {
						weed.ignite();
						var index = weedGroup.members.indexOf(weed);
						GameManager.ME.net.sendMessage("weed_ignite", {index: index});
					}
					return;
				}
				var index = weedGroup.members.indexOf(weed);
				weed.burst();
				GameManager.ME.net.sendWeedBurst(index);
				GameManager.ME.recordWeedKill(GameManager.ME.mySessionId);
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

			if (player.inventory.hasWaders() && terrainLayer != null) {
				player.inShallowWater = terrainLayer.isFullyInTaggedArea(player, [SHALLOW, SOLID]);
			} else {
				player.inShallowWater = false;
			}

			// Update shallow water visual for remote players
			if (terrainLayer != null) {
				for (_ => remote in remotePlayers) {
					remote.inShallowWater = terrainLayer.isFullyInTaggedArea(remote, [SHALLOW, SOLID]);
				}
			}
		}

		ySortGroup.sort((order, a, b) -> {
			var objA:flixel.FlxObject = cast a;
			var objB:flixel.FlxObject = cast b;
			return FlxSort.byValues(order, objA.y + objA.height, objB.y + objB.height);
		});

		if (!insideShop) {
			handleCameraBounds();
		}


		// DS "Debug Suite" is how we get to all of our debugging tools
		DS.get(DebugDraw).drawCameraText(50, 50, "hello", DebugLayers.AUDIO);

		if (!insideShop) {
			// Bobber checks are handled server-side now; no need to set bobbers on fish
			rockGroup.checkPickup(player);
			groundFishGroup.checkPickup(player);
			wadersPickup.checkPickup(player);
			pepperPickup.checkPickup(player);

			updateSparkles(elapsed);
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
		add(new SeagullPoop(poopX, poopY, fallDist, birdVelX, this, midGroundGroup, terrainLayer, null));
	}

	function onServerSeagullDespawn(data:Dynamic) {
		var sid:Int = Std.int(data.id);
		var gull = serverSeagulls.get(sid);
		if (gull != null) {
			gull.kill();
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
