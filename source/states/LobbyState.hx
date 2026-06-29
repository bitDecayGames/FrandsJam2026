package states;

import bitdecay.flixel.spacial.Align;
import flixel.text.FlxInputText;
import config.Configure;
import flixel.util.FlxTimer;
import flixel.util.FlxSort;
import schema.RoundState;
import managers.GameManager;
import net.NetworkManager;
import net.NetworkManager.PlayerUpdateData;
import flixel.addons.transition.FlxTransitionableState;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.ui.FlxButton;
import flixel.util.FlxColor;
import flixel.group.FlxGroup;
import flixel.math.FlxRect;
import entities.Player;
import levels.ldtk.Level;
import levels.ldtk.BDTilemap;
import states.MainMenuState;
import todo.TODO;
import misc.Macros;
import ui.MenuBuilder;

using states.FlxStateExt;

class LobbyState extends FlxTransitionableState {
	// World
	var terrainLayer:BDTilemap;
	var midGroundGroup = new FlxGroup();
	var ySortGroup = new FlxGroup();
	var labelsGroup = new FlxGroup(); // rendered above ySortGroup
	var collisionMap:CollisionMap;

	// Players
	var player:Player;
	var remotePlayers:Map<String, Player> = new Map();

	// Name labels above each player
	var localNameLabel:FlxText;
	var remoteNameLabels:Map<String, FlxText> = new Map();

	// Player list HUD (top-left)
	var playerListGroup = new FlxGroup();
	var playerListEntries:Array<FlxText> = [];

	// HUD
	var _btnReady:FlxButton;
	var _btnChangeSkin:FlxButton;
	var _txtReady:FlxText;
	var _txtTitle:FlxText;
	var _txtCountdown:FlxText;
	var _inputField:FlxInputText;
	var _localReady:Bool = false;
	var _playerName:String = "Player";

	// Countdown
	var _countdownActive:Bool = false;
	var _countdownTimer:Float = 0;

	// Skin select overlay
	var _skinOverlayVisible:Bool = false;
	var _skinOverlayGroup = new FlxGroup();
	var _skinSprites:Array<FlxSprite> = [];
	var _skinBorders:Array<FlxSprite> = [];
	var _skinNameLabels:Array<FlxText> = [];
	var _skinCloseLabel:FlxText;

	// Layout constants
	static inline var SKIN_ICON_NATIVE:Int = 32;
	static inline var SKIN_SIZE:Int = 64;
	static inline var SKIN_PADDING:Int = 12;
	static inline var BORDER_THICKNESS:Int = 2;
	static inline var MAX_PLAYERS:Int = 6;

	// Collision for prediction
	var simulation:Simulation;

	override public function create():Void {
		super.create();
		TODO.sfx("lobby_music");

		// Load the Lobby level
		var level = new Level("Lobby");
		terrainLayer = level.terrainLayer;
		midGroundGroup.add(terrainLayer);
		midGroundGroup.add(level.tileColliders);
		midGroundGroup.add(level.shallowTileColliders);
		FlxG.worldBounds.copyFrom(terrainLayer.getBounds());

		add(midGroundGroup);
		add(ySortGroup);
		add(labelsGroup); // labels render above sprites

		// Build collision map
		var hitboxJson = openfl.Assets.getText("assets/data/tile-hitboxes.json");
		collisionMap = CollisionMap.fromLevel(level.raw, hitboxJson);
		simulation = new Simulation(collisionMap);

		// Connect
		GameManager.ME.net.connect(Configure.getServerURL(), Configure.getServerPort());

		// Random walkable spawn
		var spawn = pickRandomSpawn();
		var lx = spawn.x;
		var ly = spawn.y;

		player = new Player(lx, ly, this);
		player.sessionId = GameManager.ME.net.mySessionId;
		player.terrainLayer = terrainLayer;
		player.groundEffectsGroup = midGroundGroup;

		// Random available skin
		var skinIdx = getRandomAvailableSkinIndex();
		player.skinIndex = skinIdx;
		player.swapSkin();
		GameManager.ME.mySkinIndex = skinIdx;

		// Wire up prediction
		if (GameManager.ME.net.isLocal()) {
			player.simulation = GameManager.ME.net.getLocalSimulation();
			player.playerState = GameManager.ME.net.getLocalPlayerState();
		} else {
			player.simulation = simulation;
			player.playerState = new schema.PlayerState();
			player.playerState.x = lx;
			player.playerState.y = ly;
			player.playerState.speed = 100;
			player.playerState.width = 16;
			player.playerState.height = 8;
		}

		FlxG.camera.follow(player, TOPDOWN);
		FlxG.camera.setScrollBoundsRect(
			FlxG.worldBounds.x, FlxG.worldBounds.y,
			FlxG.worldBounds.width, FlxG.worldBounds.height, true
		);
		ySortGroup.add(player);

		// Name label above local player
		localNameLabel = makeNameLabel(_playerName);
		labelsGroup.add(localNameLabel);

		// Enter key defocuses name field
		FlxG.stage.addEventListener(openfl.events.KeyboardEvent.KEY_DOWN, (e:openfl.events.KeyboardEvent) -> {
			if (e.keyCode == 13 && _inputField != null && _inputField.hasFocus) {
				_inputField.endFocus();
			}
		});

		// Wire network signals
		GameManager.ME.net.onPlayerAdded.add(onPlayerAdded);
		GameManager.ME.net.onPlayerChanged.add(onPlayerChanged);
		GameManager.ME.net.onPlayerRemoved.add(onPlayerRemoved);
		GameManager.ME.net.onSkinChanged.add(onSkinChanged);
		GameManager.ME.net.onPlayerNameChanged.add(onNameChanged);
		GameManager.ME.net.onPlayerReadyChanged.add(onReadyChanged);
		GameManager.ME.net.onSkinAssigned.add(onSkinAssigned);
		GameManager.ME.net.onPlayersReady.add(onAllPlayersReady);
		GameManager.ME.net.onKicked.addOnce(handleKicked);

		createHUD();

		// Name from compile flag or saved session
		var compileName = Macros.getDefine("player_name");
		if (compileName != null && compileName != "") {
			var name = compileName;
			if (name.indexOf("=") >= 0) {
				name = name.substr(0, Std.int(name.length / 2));
			}
			_playerName = name;
		} else if (FlxG.save.data.name != null && FlxG.save.data.name != "") {
			_playerName = FlxG.save.data.name;
		}
		_inputField.text = _playerName;
		localNameLabel.text = _playerName;

		// On join — use addOnce so it doesn't stack across state recreations
		var alreadyConnected = GameManager.ME.net.mySessionId != "";
		if (alreadyConnected) {
			trace('LobbyState: already connected, running setup');
			player.sessionId = GameManager.ME.net.mySessionId;
			GameManager.ME.net.sendMessage("set_position", {x: lx, y: ly});
			GameManager.ME.setStatus(RoundState.STATUS_LOBBY);
			GameManager.ME.net.sendMessage("player_name_changed", {name: _playerName});
			GameManager.ME.net.sendMessage("skin_changed", {skinIndex: skinIdx});
			updatePlayerList();
		} else {
			GameManager.ME.net.onJoined.addOnce((_) -> {
				trace('LobbyState: room joined');
				if (player == null) { return; } // guard against destroyed state
				player.sessionId = GameManager.ME.net.mySessionId;
				GameManager.ME.net.sendMessage("set_position", {x: lx, y: ly});
				GameManager.ME.setStatus(RoundState.STATUS_LOBBY);
				GameManager.ME.net.sendMessage("player_name_changed", {name: _playerName});
				GameManager.ME.net.sendMessage("skin_changed", {skinIndex: skinIdx});
				updatePlayerList();
			});
		}
	}

	function pickRandomSpawn():{x:Float, y:Float} {
		var w = collisionMap.cols;
		var h = collisionMap.rows;
		var grid = collisionMap.tileSize;
		for (_ in 0...100) {
			var cx = FlxG.random.int(0, w - 1);
			var cy = FlxG.random.int(0, h - 1);
			if (collisionMap.isWalkableAt(cx, cy)) {
				return {x: cx * grid + grid / 2.0, y: cy * grid + grid / 2.0};
			}
		}
		for (cy in 0...h) {
			for (cx in 0...w) {
				if (collisionMap.isWalkableAt(cx, cy)) {
					return {x: cx * grid + grid / 2.0, y: cy * grid + grid / 2.0};
				}
			}
		}
		return {x: 100.0, y: 100.0};
	}

	function getRandomAvailableSkinIndex():Int {
		var gm = GameManager.ME;
		var available:Array<Int> = [];
		for (i in 0...Player.SKINS.length) {
			var taken = false;
			for (sessionId => skinIdx in gm.skins) {
				if (skinIdx == i) { taken = true; break; }
			}
			if (!taken) { available.push(i); }
		}
		if (available.length == 0) { return FlxG.random.int(0, Player.SKINS.length - 1); }
		return available[FlxG.random.int(0, available.length - 1)];
	}

	function makeNameLabel(name:String):FlxText {
		var label = new FlxText(0, 0, 100, name);
		label.setFormat(null, 8, FlxColor.WHITE, FlxTextAlign.CENTER);
		label.setBorderStyle(SHADOW, FlxColor.BLACK, 1, 1);
		label.letterSpacing = 1;
		return label;
	}

	function makeHudText(x:Int, y:Int, text:String, color:FlxColor):FlxText {
		var t = new FlxText(x, y, 300, text);
		t.setFormat(null, 10, color);
		t.setBorderStyle(SHADOW, FlxColor.BLACK, 1, 1);
		t.scrollFactor.set(0, 0);
		t.letterSpacing = 1;
		return t;
	}

	function createHUD() {
		// Title
		_txtTitle = new FlxText(0, 8, FlxG.width);
		_txtTitle.setFormat(null, 16, FlxColor.WHITE, FlxTextAlign.CENTER);
		_txtTitle.text = if (GameManager.ME.net.isLocal()) "Single Player" else "Multiplayer Lobby";
		_txtTitle.setBorderStyle(SHADOW, FlxColor.BLACK, 1, 1);
		_txtTitle.letterSpacing = 1;
		_txtTitle.scrollFactor.set(0, 0);
		add(_txtTitle);

		// Bottom bar
		var bottomY = FlxG.height - 28;

		_btnChangeSkin = MenuBuilder.createTextButton("Character", toggleSkinOverlay);
		_btnChangeSkin.setPosition(8, bottomY);
		_btnChangeSkin.scrollFactor.set(0, 0);
		add(_btnChangeSkin);

		_btnReady = MenuBuilder.createTextButton("Ready", clickReady);
		_btnReady.setPosition(FlxG.width - _btnReady.width - 8, bottomY);
		_btnReady.scrollFactor.set(0, 0);
		add(_btnReady);

		var inputLeft = _btnChangeSkin.x + _btnChangeSkin.width + 8;
		var inputRight = _btnReady.x - 8;
		var inputWidth = Std.int(inputRight - inputLeft);
		_inputField = new FlxInputText(Std.int(inputLeft), Std.int(bottomY + 2), inputWidth, _playerName, 14, FlxColor.BLACK, FlxColor.WHITE);
		_inputField.maxChars = 20;
		_inputField.scrollFactor.set(0, 0);
		_inputField.onTextChange.add((text, _) -> onNameInputChanged(text));
		add(_inputField);

		// "READY" text
		_txtReady = new FlxText(0, 0, FlxG.width);
		_txtReady.setFormat(null, 24, FlxColor.GREEN, FlxTextAlign.CENTER);
		_txtReady.setBorderStyle(SHADOW, FlxColor.BLACK, 1, 1);
		_txtReady.letterSpacing = 1;
		_txtReady.text = "READY!";
		_txtReady.setPosition(0, FlxG.height - 60);
		_txtReady.scrollFactor.set(0, 0);
		_txtReady.visible = false;
		add(_txtReady);

		// Countdown text (center of screen)
		_txtCountdown = new FlxText(0, 0, FlxG.width);
		_txtCountdown.setFormat(null, 48, FlxColor.YELLOW, FlxTextAlign.CENTER);
		_txtCountdown.setBorderStyle(SHADOW, FlxColor.BLACK, 2, 2);
		_txtCountdown.letterSpacing = 2;
		_txtCountdown.setPosition(0, FlxG.height / 2 - 30);
		_txtCountdown.scrollFactor.set(0, 0);
		_txtCountdown.visible = false;
		add(_txtCountdown);

		// Player list
		add(playerListGroup);

		// Skin overlay
		createSkinOverlay();
	}

	function updatePlayerList() {
		for (entry in playerListEntries) {
			playerListGroup.remove(entry);
			entry.destroy();
		}
		playerListEntries = [];

		var gm = GameManager.ME;
		var y = 30;

		// Local player
		var localIsReady = _localReady || _countdownActive;
		var readyStr = localIsReady ? " [READY]" : "";
		var entry = makeHudText(8, y, '${_playerName}${readyStr}', localIsReady ? FlxColor.GREEN : FlxColor.WHITE);
		playerListGroup.add(entry);
		playerListEntries.push(entry);
		y += 16;

		// Remote players
		for (sessionId => _ in remotePlayers) {
			var name = gm.names.get(sessionId);
			if (name == null || name == "") { name = "???"; }
			// During countdown, show everyone as ready
			var ready = _countdownActive ? true : (gm.readyStates.exists(sessionId) && gm.readyStates.get(sessionId));
			var rStr = ready ? " [READY]" : "";
			var e = makeHudText(8, y, '${name}${rStr}', ready ? FlxColor.GREEN : FlxColor.WHITE);
			playerListGroup.add(e);
			playerListEntries.push(e);
			y += 16;
		}

	}

	function onNameInputChanged(text:String) {
		_playerName = text;
		localNameLabel.text = _playerName;
		GameManager.ME.net.sendMessage("player_name_changed", {name: _playerName});
		FlxG.save.data.name = _playerName;
		FlxG.save.flush();
		updatePlayerList();
	}

	function createSkinOverlay() {
		var overlay = new FlxSprite();
		overlay.makeGraphic(FlxG.width, FlxG.height, FlxColor.fromRGB(0, 0, 0, 180));
		overlay.scrollFactor.set(0, 0);
		_skinOverlayGroup.add(overlay);

		var numSkins = Player.SKINS.length;
		var cols = 4;
		var totalWidth = cols * SKIN_SIZE + (cols - 1) * SKIN_PADDING;
		var startX = Std.int((FlxG.width - totalWidth) / 2);
		var totalHeight = SKIN_SIZE * 2 + SKIN_PADDING;
		var startY = Std.int((FlxG.height - totalHeight) / 2);

		// Helper text just above the character grid
		_skinCloseLabel = new FlxText(0, startY - 20, FlxG.width, "Click a character to select  -  Click outside to close");
		_skinCloseLabel.setFormat(null, 10, FlxColor.GRAY, FlxTextAlign.CENTER);
		_skinCloseLabel.letterSpacing = 1;
		_skinCloseLabel.scrollFactor.set(0, 0);
		_skinOverlayGroup.add(_skinCloseLabel);

		for (i in 0...numSkins) {
			var col = i % cols;
			var row = Std.int(i / cols);
			var slotX = startX + col * (SKIN_SIZE + SKIN_PADDING);
			var slotY = startY + row * (SKIN_SIZE + SKIN_PADDING);

			var borderedSize = SKIN_SIZE + BORDER_THICKNESS * 2;
			var border = new FlxSprite();
			border.makeGraphic(borderedSize, borderedSize, FlxColor.TRANSPARENT);
			border.setPosition(slotX - BORDER_THICKNESS, slotY - BORDER_THICKNESS);
			border.scrollFactor.set(0, 0);
			_skinOverlayGroup.add(border);
			_skinBorders.push(border);

			var bg = new FlxSprite();
			bg.makeGraphic(SKIN_SIZE, SKIN_SIZE, FlxColor.BLACK);
			bg.setPosition(slotX, slotY);
			bg.scrollFactor.set(0, 0);
			_skinOverlayGroup.add(bg);

			var skinSprite = new FlxSprite();
			skinSprite.loadGraphic(AssetPaths.icons__png, true, SKIN_ICON_NATIVE, SKIN_ICON_NATIVE);
			skinSprite.animation.add("icon", [i]);
			skinSprite.animation.play("icon");
			skinSprite.scale.set(SKIN_SIZE / SKIN_ICON_NATIVE, SKIN_SIZE / SKIN_ICON_NATIVE);
			skinSprite.updateHitbox();
			skinSprite.setPosition(slotX, slotY);
			skinSprite.scrollFactor.set(0, 0);
			_skinOverlayGroup.add(skinSprite);
			_skinSprites.push(skinSprite);

			// Name label below each skin icon showing who owns it
			var nameLabel = new FlxText(slotX, slotY + SKIN_SIZE + 2, SKIN_SIZE, "");
			nameLabel.setFormat(null, 7, FlxColor.WHITE, FlxTextAlign.CENTER);
			nameLabel.letterSpacing = 1;
			nameLabel.scrollFactor.set(0, 0);
			_skinOverlayGroup.add(nameLabel);
			_skinNameLabels.push(nameLabel);
		}

		_skinOverlayGroup.visible = false;
		add(_skinOverlayGroup);
		refreshBorders();
	}

	function toggleSkinOverlay() {
		if (_localReady) { return; }
		_skinOverlayVisible = !_skinOverlayVisible;
		_skinOverlayGroup.visible = _skinOverlayVisible;
		if (_skinOverlayVisible) {
			refreshBorders();
		}
	}

	function clickReady() {
		if (_localReady) { return; }
		_localReady = true;
		_btnReady.visible = false;
		_btnChangeSkin.visible = false;
		_inputField.visible = false;
		_skinOverlayGroup.visible = false;
		_skinOverlayVisible = false;
		_txtReady.visible = true;
		localNameLabel.color = FlxColor.GREEN;
		GameManager.ME.mySkinIndex = player.skinIndex;
		GameManager.ME.net.sendMessage("player_ready", true);
		trace('LobbyState: player ready with skin ${player.skinIndex}');
		updatePlayerList();
	}

	function selectSkin(index:Int) {
		if (_localReady) { return; }
		if (isSkinTakenByOther(index)) { return; }

		player.skinIndex = index;
		player.swapSkin();
		GameManager.ME.mySkinIndex = index;
		GameManager.ME.net.sendMessage("skin_changed", {skinIndex: index});
		refreshBorders();
		_skinOverlayVisible = false;
		_skinOverlayGroup.visible = false;
	}

	function isSkinTakenByOther(index:Int):Bool {
		var gm = GameManager.ME;
		for (sessionId => skinIdx in gm.skins) {
			if (sessionId != gm.mySessionId && skinIdx == index) {
				return true;
			}
		}
		return false;
	}

	function getSkinOwnerName(index:Int):String {
		var gm = GameManager.ME;
		if (player.skinIndex == index) { return _playerName; }
		for (sessionId => skinIdx in gm.skins) {
			if (sessionId != gm.mySessionId && skinIdx == index) {
				var name = gm.names.get(sessionId);
				return (name != null && name != "") ? name : "???";
			}
		}
		return "";
	}

	function refreshBorders() {
		var gm = GameManager.ME;
		for (i in 0..._skinBorders.length) {
			var border = _skinBorders[i];
			var mine = (player.skinIndex == i);
			var taken = isSkinTakenByOther(i);

			if (mine) {
				border.makeGraphic(Std.int(border.width), Std.int(border.height), FlxColor.GREEN);
			} else if (taken) {
				border.makeGraphic(Std.int(border.width), Std.int(border.height), FlxColor.RED);
			} else {
				border.makeGraphic(Std.int(border.width), Std.int(border.height), FlxColor.TRANSPARENT);
			}

			// Update name label under each skin
			if (i < _skinNameLabels.length) {
				_skinNameLabels[i].text = getSkinOwnerName(i);
			}
		}
	}

	// --- Network callbacks ---

	function onPlayerAdded(sessionId:String, data:PlayerUpdateData) {
		if (sessionId == GameManager.ME.net.mySessionId) { return; }
		if (remotePlayers.exists(sessionId)) { return; }

		var rx = data.state.x;
		var ry = data.state.y;
		var remote = new Player(rx, ry, this);
		remote.isRemote = true;
		remote.terrainLayer = terrainLayer;
		remote.groundEffectsGroup = midGroundGroup;
		remote.setNetwork(sessionId);

		var skinIdx = GameManager.ME.skins.get(sessionId);
		if (skinIdx != null && skinIdx >= 0) {
			remote.skinIndex = skinIdx;
			remote.swapSkin();
		}

		remotePlayers.set(sessionId, remote);
		ySortGroup.add(remote);

		// Name label for remote
		var name = GameManager.ME.names.get(sessionId);
		var nameLabel = makeNameLabel(name != null ? name : "");
		remoteNameLabels.set(sessionId, nameLabel);
		labelsGroup.add(nameLabel);

		trace('LobbyState: remote player added $sessionId');
		refreshBorders();
		updatePlayerList();
	}

	function onPlayerChanged(sessionId:String, data:PlayerUpdateData) {
		if (sessionId == GameManager.ME.net.mySessionId) { return; }
		var remote = remotePlayers.get(sessionId);
		if (remote == null) { return; }
		remote.setPosition(data.state.x, data.state.y);
	}

	function onPlayerRemoved(sessionId:String) {
		var remote = remotePlayers.get(sessionId);
		if (remote != null) {
			ySortGroup.remove(remote);
			remote.destroy();
			remotePlayers.remove(sessionId);
		}
		var label = remoteNameLabels.get(sessionId);
		if (label != null) { labelsGroup.remove(label); label.destroy(); remoteNameLabels.remove(sessionId); }
		refreshBorders();
		updatePlayerList();
	}

	function onSkinChanged(sessionId:String, skinIdx:Int) {
		if (sessionId == GameManager.ME.net.mySessionId) { return; }
		var remote = remotePlayers.get(sessionId);
		if (remote != null && skinIdx >= 0) {
			remote.skinIndex = skinIdx;
			remote.swapSkin();
		}
		refreshBorders();
	}

	function onNameChanged(sessionId:String, name:String) {
		if (sessionId == GameManager.ME.net.mySessionId) { return; }
		var label = remoteNameLabels.get(sessionId);
		if (label != null) { label.text = name; }
		updatePlayerList();
		refreshBorders();
	}

	function onSkinAssigned(skinIndex:Int) {
		// Server confirmed our skin — update local player if it differs
		if (player.skinIndex != skinIndex) {
			trace('LobbyState: server reassigned skin ${player.skinIndex} -> ${skinIndex}');
			player.skinIndex = skinIndex;
			player.swapSkin();
			GameManager.ME.mySkinIndex = skinIndex;
			refreshBorders();
		}
	}

	function onReadyChanged(sessionId:String, ready:Bool) {
		// Don't update labels during countdown (server resets ready flags)
		if (_countdownActive) { return; }
		var nLabel = remoteNameLabels.get(sessionId);
		if (nLabel != null) {
			nLabel.color = ready ? FlxColor.GREEN : FlxColor.WHITE;
		}
		updatePlayerList();
	}

	function onAllPlayersReady() {
		// Start the 3-second countdown
		_countdownActive = true;
		_countdownTimer = 3.0;
		_txtCountdown.text = "3";
		_txtCountdown.visible = true;
		// Hide buttons during countdown
		_btnReady.visible = false;
		_btnChangeSkin.visible = false;
		_inputField.visible = false;
		// Force all name labels green
		localNameLabel.color = FlxColor.GREEN;
		for (_ => label in remoteNameLabels) {
			label.color = FlxColor.GREEN;
		}
		updatePlayerList();
	}

	function handleKicked() {
		FlxG.switchState(() -> new MainMenuState());
	}

	function positionLabelAbovePlayer(p:Player, nameLabel:FlxText) {
		var cx = p.x - p.offset.x + p.frameWidth / 2;
		var topY = p.y - p.offset.y;
		nameLabel.setPosition(cx - nameLabel.width / 2, topY - 10);
	}

	override public function update(elapsed:Float):Void {
		GameManager.ME.net.update(elapsed);

		// Freeze player while typing
		if (_inputField != null && _inputField.visible) {
			player.frozen = _inputField.hasFocus;
		}

		super.update(elapsed);

		FlxG.collide(midGroundGroup, player);
		for (_ => remote in remotePlayers) {
			FlxG.collide(midGroundGroup, remote);
		}

		// Position labels above players
		positionLabelAbovePlayer(player, localNameLabel);
		for (sessionId => remote in remotePlayers) {
			var nLabel = remoteNameLabels.get(sessionId);
			if (nLabel != null) {
				positionLabelAbovePlayer(remote, nLabel);
			}
		}

		// Y-sort
		ySortGroup.sort((order, a, b) -> {
			if (a == null || b == null) { return 0; }
			var objA:flixel.FlxObject = cast a;
			var objB:flixel.FlxObject = cast b;
			return FlxSort.byValues(order, objA.y + objA.height, objB.y + objB.height);
		});

		// Skin overlay clicks
		if (_skinOverlayVisible && FlxG.mouse.justPressed) {
			var pos = FlxG.mouse.getViewPosition();
			var clicked = false;
			for (i in 0..._skinSprites.length) {
				var s = _skinSprites[i];
				if (pos.x >= s.x && pos.x < s.x + SKIN_SIZE && pos.y >= s.y && pos.y < s.y + SKIN_SIZE) {
					selectSkin(i);
					clicked = true;
					break;
				}
			}
			pos.put();
			if (!clicked) { toggleSkinOverlay(); }
		}

		// Countdown
		if (_countdownActive) {
			_countdownTimer -= elapsed;
			var secs = Math.ceil(_countdownTimer);
			if (secs <= 0) {
				_txtCountdown.visible = false;
				_countdownActive = false;
				// Game starts via playersReady in GameManager
			} else {
				_txtCountdown.text = '${secs}';
				_txtCountdown.visible = true;
			}
		}

		// Auto-ready for single player or debug testing
		#if play_solo
		if (!_localReady) { clickReady(); }
		#elseif db
		// In debug mode, auto-ready once another player is in the room
		if (!_localReady && Lambda.count(remotePlayers) > 0) {
			clickReady();
		}
		#end
	}

	override function destroy() {
		GameManager.ME.net.onPlayerAdded.remove(onPlayerAdded);
		GameManager.ME.net.onPlayerChanged.remove(onPlayerChanged);
		GameManager.ME.net.onPlayerRemoved.remove(onPlayerRemoved);
		GameManager.ME.net.onSkinChanged.remove(onSkinChanged);
		GameManager.ME.net.onPlayerNameChanged.remove(onNameChanged);
		GameManager.ME.net.onPlayerReadyChanged.remove(onReadyChanged);
		GameManager.ME.net.onPlayersReady.remove(onAllPlayersReady);
		GameManager.ME.net.onSkinAssigned.remove(onSkinAssigned);
		super.destroy();
	}
}
