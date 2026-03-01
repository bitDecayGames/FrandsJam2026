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
import levels.ldtk.Level;
import levels.ldtk.Ldtk.LdtkProject;
import achievements.Achievements;
import entities.Player;
import entities.Shop;
import events.gen.Event;
import events.EventBus;
import flixel.FlxG;
import flixel.addons.transition.FlxTransitionableState;
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
	var fishSpawner:FishSpawner;
	var rockGroup:RockGroup;
	var groundFishGroup:GroundFishGroup;
	var shop:Shop;
	var inventoryHUD:InventoryHUD;
	var scoreHUD:ScoreHUD;
	var activeCameraTransition:CameraTransition = null;
	var hotText:FlashingText;

	var transitions = new FlxTypedGroup<CameraTransition>();

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
		rockGroup = new RockGroup();
		groundFishGroup = new GroundFishGroup();

		// Build out our render order
		add(midGroundGroup);
		add(rockGroup);
		add(groundFishGroup);
		add(fishSpawner);
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

	function setupNetwork() {
		GameManager.ME.net.onJoined.add(onPlayerJoined);
		GameManager.ME.net.onPlayerAdded.add(onPlayerAdded);
		GameManager.ME.net.onPlayerRemoved.add(onPlayerRemoved);
		GameManager.ME.net.onFishAdded.add(onFishAdded);
		GameManager.ME.net.onCastLine.add(onRemoteCastLine);
		GameManager.ME.net.onFishCaught.add(onRemoteFishCaught);
		GameManager.ME.net.onLinePulled.add(onRemoteLinePulled);
		GameManager.ME.net.onRockSplash.add(onRemoteRockSplash);
	}

	function onPlayerJoined(sessionId:String) {
		trace('PlayState: joined as $sessionId');
		player.setNetwork(sessionId);
	}

	function onPlayerAdded(sessionId:String, data:{state:PlayerState}) {
		if (sessionId == player.sessionId) {
			return;
		}
		// TODO: Have server give us the player color, too
		trace('PlayState: remote player $sessionId appeared');
		var remote = new Player(data.state.x, data.state.y, this);
		remote.isRemote = true;
		remote.setNetwork(sessionId);
		remotePlayers.set(sessionId, remote);
		add(remote);
	}

	function onPlayerRemoved(sessionId:String) {
		trace('PlayState: remote player $sessionId left');
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

		var newFish = new WaterFish(fishId, fishState.x, fishState.y, null, true);
		remoteFish.set(fishId, newFish);
		fishSpawner.add(newFish);
		QLog.notice('fish post-add pos: ${newFish.x}, ${newFish.y}');
	}

	function onRemoteRockSplash(x:Float, y:Float) {
		fishSpawner.scareFish(x, y);
	}

	function onLocalRockSplash(x:Float, y:Float) {
		FmodManager.PlaySoundOneShot(FmodSFX.RockSplash);
		fishSpawner.scareFish(x, y);
		GameManager.ME.net.sendMessage("rock_splash", {x: x, y: y});
	}

	function loadLevel(level:String) {
		unload();

		var level = new Level(level);
		if (level.songEvent != "") {
			// FmodManager.PlaySong(level.songEvent);
		}
		midGroundGroup.add(level.terrainLayer);
		FlxG.worldBounds.copyFrom(level.terrainLayer.getBounds());

		player = new Player(level.spawnPoint.x, level.spawnPoint.y, this);
		camera.follow(player);
		add(player);

		#if local
		rockGroup.spawn(level);
		fishSpawner.spawn(level);
		#else
		FlxTimer.wait(10, () -> {
			if (NetworkManager.IS_HOST) {
				rockGroup.spawn(level);
				fishSpawner.spawn(level);
			} else {
				QLog.notice('skipping fish spawn');
			}
		});
		#end

		var spawnerLayer = level.fishSpawnerLayer;
		player.makeRock = (rx, ry) -> new Rock(rx, ry, spawnerLayer, rockGroup.addRock, onLocalRockSplash);
		groundFishGroup.setWaterLayer(spawnerLayer);

		shop = new Shop();
		shop.spawnRandom(level);
		add(shop);

		inventoryHUD = new InventoryHUD(player.inventory);
		add(inventoryHUD);

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

	function onFishCaught(fishId:String, catcherSessionId:String) {
		#if !local
		GameManager.ME.net.sendFishCaught(fishId, catcherSessionId);
		#end

		// Trigger on the catching player immediately (avoids latency; echo-back is a no-op)
		if (catcherSessionId == player.sessionId) {
			player.onFishDelivered = () -> {
				if (!player.inventory.add(Fish(player.caughtFishSpriteIndex))) {
					groundFishGroup.addFish(player.x + 8, player.y - 2, player.caughtFishSpriteIndex);
				}
				player.onFishDelivered = null;
			};
			player.catchFish(true);
		} else {
			var remote = remotePlayers.get(catcherSessionId);
			if (remote != null)
				remote.catchFish(true);
		}
	}

	function onRemoteCastLine(sessionId:String, x:Float, y:Float, dir:String) {
		var remote = remotePlayers.get(sessionId);
		if (remote != null)
			remote.remoteStartCast(x, y, dir);
	}

	function onRemoteFishCaught(sessionId:String, fishId:String) {
		// Hide the remote fish sprite — it will fade back in when the host starts moving it again
		var fish = remoteFish.get(fishId);
		if (fish != null)
			fish.visible = false;

		// Non-host clients receive this to trigger the catch animation
		if (sessionId == player.sessionId) {
			player.onFishDelivered = () -> {
				if (!player.inventory.add(Fish(player.caughtFishSpriteIndex))) {
					groundFishGroup.addFish(player.x + 8, player.y - 2, player.caughtFishSpriteIndex);
				}
				player.onFishDelivered = null;
			};
			player.catchFish(true);
		} else {
			var remote = remotePlayers.get(sessionId);
			if (remote != null)
				remote.catchFish(true);
		}
	}

	function onRemoteLinePulled(sessionId:String) {
		if (sessionId == player.sessionId) {
			player.catchFish(false);
		} else {
			var remote = remotePlayers.get(sessionId);
			if (remote != null)
				remote.catchFish(false);
		}
	}

	function handleAchieve(def:AchievementDef) {
		add(def.toToast(true));
	}

	override public function update(elapsed:Float) {
		super.update(elapsed);

		if (FlxG.mouse.justPressed) {
			EventBus.fire(new Click(FlxG.mouse.x, FlxG.mouse.y));
		}

		FlxG.collide(midGroundGroup, player);
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
		shop.checkInteraction(player);
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
