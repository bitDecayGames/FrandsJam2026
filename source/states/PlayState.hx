package states;

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
import entities.FishGroup;
import entities.FishSpawner;
import levels.ldtk.Level;
import levels.ldtk.Ldtk.LdtkProject;
import achievements.Achievements;
import entities.Player;
import events.gen.Event;
import events.EventBus;
import flixel.FlxG;
import flixel.addons.transition.FlxTransitionableState;
import ui.FlashingText;

using states.FlxStateExt;

class PlayState extends FlxTransitionableState {
	var player:Player;

	// Network things
	var remotePlayers:Map<String, Player> = new Map();
	var net:NetworkManager;

	var midGroundGroup = new FlxGroup();
	var fishSpawner = new FishSpawner();
	var fishGroup = new FishGroup();
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

		// Build out our render order
		add(midGroundGroup);
		add(fishSpawner);
		add(fishGroup);
		add(transitions);

		loadLevel("Level_0");
		#if !local
		setupNetwork();
		#end

		hotText = new FlashingText("HOT", 0.15, 3.0);
		add(hotText);
		round.initialize(this);
	}

	function setupNetwork() {
		net = new NetworkManager();
		net.onJoined = (sessionId) -> {
			trace('PlayState: joined as $sessionId');
			player.setNetwork(net, sessionId);
		};
		net.onPlayerAdded = (sessionId, playerState) -> {
			if (sessionId == player.sessionId) {
				return;
			}
			// TODO: Have server give us the player color, too
			trace('PlayState: remote player $sessionId appeared');
			var remote = new Player(playerState.x, playerState.y, this);
			remote.isRemote = true;
			remote.setNetwork(net, sessionId);
			remotePlayers.set(sessionId, remote);
			add(remote);
		};
		net.onPlayerRemoved = (sessionId) -> {
			trace('PlayState: remote player $sessionId left');
			var remote = remotePlayers.get(sessionId);
			if (remote != null) {
				remove(remote);
				remote.destroy();
				remotePlayers.remove(sessionId);
			}
		};
		net.connect(Configure.getServerURL(), Configure.getServerPort());
	}

	function loadLevel(level:String) {
		unload();

		var level = new Level(level);
		if (level.songEvent != "") {
			FmodManager.PlaySong(level.songEvent);
		}
		midGroundGroup.add(level.terrainLayer);
		FlxG.worldBounds.copyFrom(level.terrainLayer.getBounds());

		player = new Player(level.spawnPoint.x, level.spawnPoint.y, this);
		camera.follow(player);
		add(player);

		fishSpawner.spawn(level);

		fishGroup.spawn(FlxG.worldBounds);

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

		fishGroup.clearAll();

		fishSpawner.clearAll();

		for (o in midGroundGroup) {
			o.destroy();
		}
		midGroundGroup.clear();
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

		fishGroup.handleOverlap(player);
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
