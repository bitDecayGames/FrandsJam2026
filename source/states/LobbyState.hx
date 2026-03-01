package states;

import ui.font.BitmapText.PressStart;
import flixel.text.FlxBitmapText;
import misc.FlxTextFactory;
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
import ui.MenuBuilder;

using states.FlxStateExt;

class LobbyState extends FlxTransitionableState {
	var _btnDone:FlxButton;
	var _txtReady:FlxText;
	var _txtRoomID:FlxBitmapText;

	var _txtTitle:FlxText;
	var _inputField:FlxInputText;
	var _txtOtherPlayers:FlxText;

	// Skin selection
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

	override public function create():Void {
		super.create();
		bgColor = FlxColor.TRANSPARENT;

		_txtTitle = new FlxText();
		_txtTitle.setPosition(FlxG.width / 2, 20);
		_txtTitle.size = 40;
		_txtTitle.alignment = FlxTextAlign.CENTER;
		_txtTitle.text = "Lobby";
		add(_txtTitle);

		_txtRoomID = FlxTextFactory.make("Room ID: ", 10, 10, 12, FlxTextAlign.LEFT, FlxColor.WHITE, PressStart.font);
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
		_txtReady.size = 24;
		_txtReady.alignment = FlxTextAlign.CENTER;
		_txtReady.color = FlxColor.LIME;
		_txtReady.text = "READY";
		_txtReady.setPosition(FlxG.width / 2 - _txtReady.width / 2, _btnDone.y);
		_txtReady.visible = false;
		add(_txtReady);

		// Input field centered directly above the Ready button
		_inputField = new FlxInputText(0, 0, 200, FlxG.save.data.name, 20, FlxColor.WHITE, FlxColor.GRAY);
		_inputField.maxChars = 20;
		_inputField.setPosition(FlxG.width / 2 - _inputField.width / 2, _btnDone.y - _inputField.height - 8);
		_inputField.onTextChange.add(updatePlayerName);
		add(_inputField);

		var _txtNameLabel = new FlxText();
		_txtNameLabel.size = 12;
		_txtNameLabel.text = "Enter your name:";
		_txtNameLabel.setPosition(FlxG.width / 2 - _txtNameLabel.width / 2, _inputField.y - _txtNameLabel.height - 4);
		add(_txtNameLabel);

		// Other players text in the lower-right corner
		_txtOtherPlayers = new FlxText();
		_txtOtherPlayers.size = 10;
		_txtOtherPlayers.alignment = FlxTextAlign.RIGHT;
		_txtOtherPlayers.text = "";
		add(_txtOtherPlayers);

		// Create skin selection sprites
		createSkinSelection();

		#if !local
		GameManager.ME.net.connect(Configure.getServerURL(), Configure.getServerPort());
		#end
		FlxTimer.wait(2, () -> {
			GameManager.ME.setStatus(RoundState.STATUS_LOBBY);
			if (_inputField.text != null && _inputField.text != "") {
				GameManager.ME.net.sendMessage("player_name_changed", {name: _inputField.text});
			}
		});
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
			nameLabel.size = 8;
			nameLabel.alignment = FlxTextAlign.CENTER;
			nameLabel.text = "";
			nameLabel.setPosition(slotX + SKIN_SIZE / 2, skinY - nameHeight);
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
		GameManager.ME.net.sendMessage("skin_changed", {skinIndex: _selectedSkinIndex});

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
		var gm = GameManager.ME;
		for (sessionId => skinIdx in gm.skins) {
			if (sessionId != gm.mySessionId && skinIdx == index) {
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
				_skinBorders[i].makeGraphic(borderedSize, borderedSize, FlxColor.LIME);
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
		GameManager.ME.net.sendMessage("player_name_changed", {name: text});
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

		@:privateAccess(NetworkManager)
		{
			if (GameManager.ME.net.room != null) {
				_txtRoomID.text = 'Room ID: ${GameManager.ME.net.room.roomId}';
			}
		}
	}

	private function updateNameLabels():Void {
		var gm = GameManager.ME;

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
		for (sessionId => skinIdx in gm.skins) {
			if (sessionId == gm.mySessionId) {
				continue;
			}
			if (skinIdx >= 0 && skinIdx < _skinNameLabels.length) {
				var name = gm.names.get(sessionId);
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

		// Build the "Other Players:" list — always shows all other players
		var playerLines = new Array<String>();
		for (sessionId in gm.sessions) {
			if (sessionId == gm.mySessionId) {
				continue;
			}
			var name = gm.names.get(sessionId);
			if (name == null || name == "") {
				name = "???";
			}
			var isReady = gm.readyStates.exists(sessionId) && gm.readyStates.get(sessionId);
			if (isReady) {
				playerLines.push(name + " (READY)");
			} else {
				playerLines.push(name);
			}
		}

		var newText = if (playerLines.length > 0) {
			"Other Players:\n" + playerLines.join("\n");
		} else {
			"";
		};

		if (_txtOtherPlayers.text != newText) {
			_txtOtherPlayers.text = newText;
		}
		// Position in the lower-right corner
		_txtOtherPlayers.x = FlxG.width - _txtOtherPlayers.width - 10;
		_txtOtherPlayers.y = FlxG.height - _txtOtherPlayers.height - 10;
	}

	function clickReady():Void {
		if (_selectedSkinIndex < 0) {
			return;
		}

		FlxG.save.data.name = _inputField.text;
		FlxG.save.flush();
		GameManager.ME.mySkinIndex = _selectedSkinIndex;
		GameManager.ME.net.sendMessage("player_ready", true);

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
