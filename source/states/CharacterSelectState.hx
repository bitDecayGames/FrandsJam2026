package states;

import schema.GameState;
import io.colyseus.serializer.schema.Callbacks;
import schema.meta.CharSelectState;
import io.colyseus.Room;
import bitdecay.flixel.spacial.Align;
import flixel.text.FlxInputText;
import goals.PersonalFishCountGoal;
import goals.TimedGoal;
import rounds.Round;
import config.Configure;
import flixel.util.FlxTimer;
import schema.RoundState;
import managers.GameManager;
import net.NetworkManager;
import flixel.addons.transition.FlxTransitionableState;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.ui.FlxButton;
import flixel.util.FlxColor;
import entities.Player;
import todo.TODO;
import ui.MenuBuilder;

using states.FlxStateExt;

class CharacterSelectState extends FlxTransitionableState {
	var _btnDone:FlxButton;
	var _txtReady:FlxText;
	var _txtRoomID:FlxText;

	var _txtTitle:FlxText;
	var _inputField:FlxInputText;
	var _txtOtherHeader:FlxText;
	var _kickRows:Array<{label:FlxText, btn:FlxButton, sessionId:String}> = [];

	var playerNames = new Map<String, String>();
	var playerReadiness = new Map<String, Bool>();

	// Skin selection
	var playerSkins = new Map<String, Int>(); // sessionId -> skinIndex
	var _skinSprites:Array<FlxSprite> = [];
	var _skinBorders:Array<FlxSprite> = [];
	var _skinNameLabels:Array<FlxText> = [];
	var _selectedSkinIndex:Int = -1; // -1 means no skin selected
	var _localReady:Bool = false;

	// Layout constants
	static inline var SKIN_ICON_NATIVE:Int = 32; // native pixel size of icons.png frames
	static inline var SKIN_SIZE:Int = 64; // displayed size (2x scale)
	static inline var SKIN_PADDING:Int = 12;
	static inline var BORDER_THICKNESS:Int = 2;
	static inline var MAX_REMOTE_PLAYERS:Int = 5;
	static inline var KICK_BTN_W:Int = 80;
	static inline var ROW_H:Int = 22;

	// Title screen colors
	static var BG_COLOR:FlxColor = 0xff73efe8; // turquoise
	static var TEXT_COLOR:FlxColor = 0xff2b4e95; // dark navy

	var colySessionId:String = "";
	var colyRoom:Room<CharSelectState> = null;

	public function new(room:Room<CharSelectState>) {
		super();
		setupCharSelect(room);
	}

	override public function create():Void {
		super.create();
		TODO.sfx("lobby_music");
		bgColor = BG_COLOR;

		_txtTitle = new FlxText();
		_txtTitle.setPosition(FlxG.width / 2, 20);
		_txtTitle.setFormat(Main.menuFont, 40, TEXT_COLOR, FlxTextAlign.CENTER);
		_txtTitle.text = "Lobby";
		add(_txtTitle);

		_txtRoomID = new FlxText();
		_txtRoomID.setPosition(10, 10);
		_txtRoomID.setFormat(Main.menuFont, 12, TEXT_COLOR);
		_txtRoomID.text = "Room ID: ";
		add(_txtRoomID);

		// Ready button at the bottom center — starts disabled
		_btnDone = MenuBuilder.createTextButton("Ready", clickReady);
		_btnDone.setPosition(FlxG.width / 2 - _btnDone.width / 2, FlxG.height - _btnDone.height - 40);
		_btnDone.updateHitbox();
		_btnDone.active = false;
		_btnDone.alpha = 0.3;
		add(_btnDone);

		// Large green "READY" text — hidden until the player clicks Ready
		_txtReady = new FlxText();
		_txtReady.setFormat(Main.menuFont, 24, TEXT_COLOR, FlxTextAlign.CENTER);
		_txtReady.text = "READY";
		_txtReady.setPosition(FlxG.width / 2 - _txtReady.width / 2, _btnDone.y);
		_txtReady.visible = false;
		add(_txtReady);

		// Input field centered directly above the Ready button
		_inputField = new FlxInputText(0, 0, 200, FlxG.save.data.name, 20, TEXT_COLOR, FlxColor.WHITE);
		_inputField.maxChars = 20;
		_inputField.setPosition(FlxG.width / 2 - _inputField.width / 2, _btnDone.y - _inputField.height - 8);
		_inputField.onTextChange.add(updatePlayerName);
		add(_inputField);

		var _txtNameLabel = new FlxText();
		_txtNameLabel.setFormat(Main.menuFont, 12, TEXT_COLOR);
		_txtNameLabel.text = "Enter your name:";
		_txtNameLabel.setPosition(FlxG.width / 2 - _txtNameLabel.width / 2, _inputField.y - _txtNameLabel.height - 4);
		add(_txtNameLabel);

		// Header label for the other players section
		_txtOtherHeader = new FlxText(0, 0, 0, "Other Players:", 16);
		_txtOtherHeader.setFormat(Main.menuFont, 16, TEXT_COLOR);
		_txtOtherHeader.visible = false;
		add(_txtOtherHeader);

		// Pre-create kick rows (up to MAX_REMOTE_PLAYERS)
		for (i in 0...MAX_REMOTE_PLAYERS) {
			var label = new FlxText(0, 0, 150, "", 12);
			label.setFormat(Main.menuFont, 12, TEXT_COLOR);
			label.visible = false;
			add(label);

			var capturedI = i;
			var btn = new FlxButton(0, 0, "Kick");
			btn.onUp.callback = () -> kickPlayer(capturedI);
			btn.onOver.callback = () -> btn.color = FlxColor.GRAY;
			btn.onOut.callback = () -> btn.color = FlxColor.WHITE;
			btn.visible = false;
			add(btn);

			_kickRows.push({label: label, btn: btn, sessionId: ""});
		}

		// GameManager.ME.net.onKicked.addOnce(handleKicked);
		// GameManager.ME.net.onPlayerRemoved.add(onRemotePlayerRemoved);

		// Create skin selection sprites
		createSkinSelection();

		FlxTimer.wait(2, () -> {
			if (_inputField.text != null && _inputField.text != "") {
				colyRoom.send(CharSelectState.MSG_NAME_CHANGED, {name: _inputField.text});
			}

			// just send the skin request message to the server
			// _selectedSkinIndex = GameManager.ME.getFirstAvailableSkinIndex();
			if (_selectedSkinIndex > -1) {
				colyRoom.send(CharSelectState.MSG_NAME_CHANGED, {skinIndex: _selectedSkinIndex});
			}
		});
	}

	function setupCharSelect(room:Room<CharSelectState>) {
		this.colyRoom = room;

		colySessionId = room.sessionId;

		var cb = Callbacks.get(room);
		cb.onAdd(room.state, "players", (player:PlayerLobbyState, sessionId:String) -> {
			trace('Player added: $sessionId');
			playerNames.set(sessionId, player.name);
			cb.onChange(player, () -> {});
		});

		room.onMessage(CharSelectState.SERVER_MSG_PLAYER_KICKED, (message:{sessionId:String}) -> {
			if (message.sessionId == colySessionId) {
				trace('[NetMan] we got kicked!');
				room.leave(true);
				room = null;
				FlxG.switchState(MainMenuState.new);
				return;
			}

			trace('[NetMan] player_kicked => ${message.sessionId}');
			playerNames.remove(message.sessionId);
			playerSkins.remove(message.sessionId);
		});

		room.onMessage(CharSelectState.SERVER_MSG_MOVE_TO_GAME, (reservation) -> {
			trace('received game reservation for session: ${reservation.sessionId}');

			// Join the match room with the reservation
			NetworkManager.ME.client.consumeSeatReservation(reservation, GameState, function(err, match:Room<GameState>) {
				if (err != null) {
					trace("join error: " + err);
					FlxG.switchState(MainMenuState.new);
					return;
				}
				trace('Joined game ${match.roomId} as ${match.sessionId}');
				// GameManager.ME.init(match);
				// FlxG.switchState(() -> new PlayState(match));
			});
		});
	}

	private function updateRemotePlayer(p:PlayerLobbyState) {
		playerSkins.set(p.sessionId, p.skinIndex);
		playerNames.set(p.sessionId, p.name);
		playerReadiness.set(p.sessionId, p.ready);
	}

	private function createSkinSelection():Void {
		var numSkins = Player.SKINS.length;
		var cols = 4;
		var nameHeight = 12; // vertical space reserved above each icon for name labels
		var rowGap = nameHeight + SKIN_PADDING; // extra gap between rows so row-2 names don't overlap row-1 icons
		var totalWidth = cols * SKIN_SIZE + (cols - 1) * SKIN_PADDING;
		var startX = Std.int((FlxG.width - totalWidth) / 2);
		// vertically center the two rows (each row = nameHeight + SKIN_SIZE) in the screen
		var totalHeight = SKIN_SIZE + rowGap + nameHeight + SKIN_SIZE;
		var gridStartY = Std.int(FlxG.height / 2 - totalHeight / 2);
		var borderedSize = SKIN_SIZE + BORDER_THICKNESS * 2;

		for (i in 0...numSkins) {
			var col = i % cols;
			var row = Std.int(i / cols);
			var slotX = startX + col * (SKIN_SIZE + SKIN_PADDING);
			var skinY = gridStartY + row * (SKIN_SIZE + rowGap + nameHeight);

			// Border sprite (initially transparent)
			var border = new FlxSprite();
			border.makeGraphic(borderedSize, borderedSize, FlxColor.TRANSPARENT);
			border.setPosition(slotX - BORDER_THICKNESS, skinY - BORDER_THICKNESS);
			add(border);
			_skinBorders.push(border);

			// Black background behind each skin icon
			var skinBg = new FlxSprite();
			skinBg.makeGraphic(SKIN_SIZE, SKIN_SIZE, FlxColor.BLACK);
			skinBg.setPosition(slotX, skinY);
			add(skinBg);

			// Skin preview sprite — use the icons sheet (frame i = skin i), scaled 2x
			var skinSprite = new FlxSprite();
			skinSprite.loadGraphic(AssetPaths.icons__png, true, SKIN_ICON_NATIVE, SKIN_ICON_NATIVE);
			skinSprite.animation.add("icon", [i]);
			skinSprite.animation.play("icon");
			skinSprite.scale.set(SKIN_SIZE / SKIN_ICON_NATIVE, SKIN_SIZE / SKIN_ICON_NATIVE);
			skinSprite.updateHitbox();
			skinSprite.setPosition(slotX, skinY);
			add(skinSprite);
			_skinSprites.push(skinSprite);

			// Name label above each skin
			var nameLabel = new FlxText();
			nameLabel.setFormat(Main.menuFont, 12, TEXT_COLOR, FlxTextAlign.CENTER);
			nameLabel.text = "";
			nameLabel.setPosition(slotX + SKIN_SIZE / 2, skinY - nameHeight);
			Align.center(nameLabel, skinSprite, X);
			Align.stack(nameLabel, skinSprite, UP, 2);
			add(nameLabel);
			_skinNameLabels.push(nameLabel);
		}

		// No skin selected by default — all borders start transparent
		refreshBorders();
	}

	private function selectSkin(index:Int):Void {
		// Can't change skin after readying up
		if (_localReady) {
			return;
		}

		// Don't allow selecting a skin that another player already has
		if (isSkinTakenByOther(index)) {
			return;
		}

		// Toggle off if clicking the already-selected skin
		if (_selectedSkinIndex == index) {
			_selectedSkinIndex = -1;
		} else {
			_selectedSkinIndex = index;
		}

		// Send skin selection to server
		colyRoom.send(CharSelectState.MSG_SKIN_CHANGED, {skinIndex: _selectedSkinIndex});

		// Enable/disable Ready button based on skin selection
		if (_selectedSkinIndex >= 0) {
			_btnDone.active = true;
			_btnDone.alpha = 1.0;
		} else {
			_btnDone.active = false;
			_btnDone.alpha = 0.3;
		}

		refreshBorders();
	}

	private function isSkinTakenByOther(index:Int):Bool {
		// TODO: We can replace all of this with a request to the server to change skin and it will tell us what we get
		for (sessionId => skinIdx in playerSkins) {
			if (sessionId != colySessionId && skinIdx == index) {
				return true;
			}
		}
		return false;
	}

	private function refreshBorders():Void {
		var borderedSize = SKIN_SIZE + BORDER_THICKNESS * 2;

		for (i in 0..._skinBorders.length) {
			if (i == _selectedSkinIndex) {
				// Bright green border for the local player's selection
				_skinBorders[i].makeGraphic(borderedSize, borderedSize, TEXT_COLOR);
				// Cut out the interior to make it a border frame
				var pixels = _skinBorders[i].pixels;
				for (py in BORDER_THICKNESS...BORDER_THICKNESS + SKIN_SIZE) {
					for (px in BORDER_THICKNESS...BORDER_THICKNESS + SKIN_SIZE) {
						pixels.setPixel32(px, py, FlxColor.TRANSPARENT);
					}
				}
				_skinBorders[i].dirty = true;
			} else if (isSkinTakenByOther(i)) {
				// Dim border for skins taken by other players
				_skinBorders[i].makeGraphic(borderedSize, borderedSize, FlxColor.fromRGB(80, 80, 80));
				var pixels = _skinBorders[i].pixels;
				for (py in BORDER_THICKNESS...BORDER_THICKNESS + SKIN_SIZE) {
					for (px in BORDER_THICKNESS...BORDER_THICKNESS + SKIN_SIZE) {
						pixels.setPixel32(px, py, FlxColor.TRANSPARENT);
					}
				}
				_skinBorders[i].dirty = true;
			} else {
				_skinBorders[i].makeGraphic(borderedSize, borderedSize, FlxColor.TRANSPARENT);
			}
		}
	}

	private function updatePlayerName(text:String, change:FlxInputTextChange) {
		colyRoom.send(CharSelectState.MSG_NAME_CHANGED, {name: text});
	}

	override public function update(elapsed:Float):Void {
		super.update(elapsed);
		_txtTitle.x = FlxG.width / 2 - _txtTitle.width / 2;

		// Check for clicks on skin sprites
		if (FlxG.mouse.justPressed) {
			for (i in 0..._skinSprites.length) {
				var sprite = _skinSprites[i];
				if (FlxG.mouse.x >= sprite.x && FlxG.mouse.x < sprite.x + SKIN_SIZE && FlxG.mouse.y >= sprite.y && FlxG.mouse.y < sprite.y + SKIN_SIZE) {
					selectSkin(i);
					break;
				}
			}
		}

		updateNameLabels();

		if (colyRoom != null) {
			_txtRoomID.text = 'Room ID: ${colyRoom.roomId}';
		} else {
			_txtRoomID.text = '';
		}
	}

	private function updateNameLabels():Void {
		// Clear all name labels first
		for (label in _skinNameLabels) {
			label.text = "";
		}

		// Place the local player's name above their selected skin
		if (_selectedSkinIndex >= 0) {
			var localName = (_inputField.text != null && _inputField.text != "") ? _inputField.text : "You";
			_skinNameLabels[_selectedSkinIndex].text = localName;
			_skinNameLabels[_selectedSkinIndex].x = _skinSprites[_selectedSkinIndex].x + SKIN_SIZE / 2 - _skinNameLabels[_selectedSkinIndex].width / 2;
		}

		// Place other players' names above their selected skins
		for (sessionId => skinIdx in playerSkins) {
			if (sessionId == colySessionId) {
				continue;
			}
			if (skinIdx >= 0 && skinIdx < _skinNameLabels.length) {
				var name = playerNames.get(sessionId);
				if (name == null || name == "") {
					name = "???";
				}
				if (_skinNameLabels[skinIdx].text != "") {
					_skinNameLabels[skinIdx].text = _skinNameLabels[skinIdx].text + "\n" + name;
				} else {
					_skinNameLabels[skinIdx].text = name;
				}
				_skinNameLabels[skinIdx].x = _skinSprites[skinIdx].x + SKIN_SIZE / 2 - _skinNameLabels[skinIdx].width / 2;
			}
		}

		// Refresh borders since other players' skins may have changed
		refreshBorders();

		// Build the kick rows for all other players
		var others:Array<String> = [];
		for (sessionId => _ in playerSkins) {
			if (sessionId != colySessionId) {
				others.push(sessionId);
			}
		}

		var sectionRight = FlxG.width - 10;
		var sectionBottom = FlxG.height - 10;
		var headerH = 28;
		var sectionH = others.length > 0 ? (others.length * ROW_H + headerH) : 0;

		_txtOtherHeader.visible = others.length > 0;
		if (others.length > 0) {
			_txtOtherHeader.x = sectionRight - _txtOtherHeader.width;
			_txtOtherHeader.y = sectionBottom - sectionH;
		}

		for (i in 0...MAX_REMOTE_PLAYERS) {
			var row = _kickRows[i];
			if (i < others.length) {
				var sessionId = others[i];
				var name = playerNames.get(sessionId);
				if (name == null || name == "") {
					name = "???";
				}
				var isReady = playerReadiness.exists(sessionId) && playerReadiness.get(sessionId);

				row.sessionId = sessionId;
				row.label.text = name + (isReady ? " (READY)" : "");

				var rowY = sectionBottom - sectionH + headerH + i * ROW_H;
				row.btn.x = sectionRight - KICK_BTN_W;
				row.btn.y = rowY;
				row.btn.visible = true;

				row.label.x = row.btn.x - row.label.width - 4;
				row.label.y = rowY + 6; // vertically center the text in the row
				row.label.visible = true;
			} else {
				row.label.visible = false;
				row.btn.visible = false;
				row.sessionId = "";
			}
		}
	}

	private function onRemotePlayerRemoved(sessionId:String):Void {
		updateNameLabels();
	}

	private function kickPlayer(rowIndex:Int):Void {
		var row = _kickRows[rowIndex];
		if (row.sessionId != "") {
			colyRoom.send(CharSelectState.MSG_KICK, row.sessionId);
		}
	}

	private function handleKicked():Void {
		FlxG.switchState(() -> new MainMenuState());
	}

	function clickReady():Void {
		if (_selectedSkinIndex < 0) {
			return;
		}

		FlxG.save.data.name = _inputField.text;
		FlxG.save.flush();
		// GameManager.ME.mySkinIndex = _selectedSkinIndex;
		colyRoom.send(CharSelectState.MSG_READY, true);

		// Hide button, show green READY text
		_localReady = true;
		_btnDone.visible = false;
		_btnDone.active = false;
		_txtReady.visible = true;
		_txtReady.x = FlxG.width / 2 - _txtReady.width / 2;
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
