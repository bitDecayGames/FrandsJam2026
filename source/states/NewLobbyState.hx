package states;

import states.CharacterSelectState;
import net.NetworkManager;
import schema.meta.CharSelectState;
import io.colyseus.serializer.schema.Schema;
import io.colyseus.Room;
import io.colyseus.error.HttpException;
import managers.GameManager;
import flixel.addons.transition.FlxTransitionableState;
import flixel.FlxG;
import flixel.text.FlxInputText;
import flixel.text.FlxText;
import flixel.ui.FlxButton;
import flixel.util.FlxColor;
import ui.MenuBuilder;

using states.FlxStateExt;

/**
 * Room browser — joins the Colyseus LobbyRoom and shows available game rooms
 * in a simple table. The player can click a row to join that room, create a
 * public or private room, or type a room ID and join directly. On success,
 * transitions to CharacterSelectState for skin selection / ready-up.
 */
class NewLobbyState extends FlxTransitionableState {
	// These are fixed messages that colyseus sends for the built-in LobbyRoom
	static inline var MSG_ROOMS = "rooms";
	static inline var MSG_ROOM_ADDED = "+";
	static inline var MSG_ROOM_REMOVED = "-";

	static var BG_COLOR:FlxColor = 0xff73efe8; // turquoise
	static var TEXT_COLOR:FlxColor = 0xff2b4e95; // dark navy

	static inline var MAX_ROWS:Int = 8;
	static inline var ROW_H:Int = 32;
	static inline var TABLE_LEFT:Int = 40;
	static inline var TABLE_TOP:Int = 118;
	static inline var LABEL_W:Int = 430;
	static inline var BTN_W:Int = 80;
	static inline var BTN_H:Int = 24;

	var _txtTitle:FlxText;
	var _txtStatus:FlxText;
	var _txtColHeader:FlxText;
	var _btnCreatePublic:FlxButton;
	var _btnCreatePrivate:FlxButton;
	var _inputRoomId:FlxInputText;
	var _btnJoinById:FlxButton;

	var _roomRows:Array<{label:FlxText, btn:FlxButton, roomId:String}> = [];

	// the colyseus lobby
	var lobbyRoom:Room<Schema> = null;

	var _rooms:Array<Dynamic> = [];
	var _connected:Bool = false;
	var _joining:Bool = false;

	public function new() {
		super();
	}

	override public function create():Void {
		super.create();
		bgColor = BG_COLOR;

		_txtTitle = new FlxText(0, 20, FlxG.width, "Game Rooms", 40);
		_txtTitle.setFormat(Main.menuFont, 40, TEXT_COLOR, FlxTextAlign.CENTER);
		add(_txtTitle);

		_txtStatus = new FlxText(0, 72, FlxG.width, "Connecting...", 16);
		_txtStatus.setFormat(Main.menuFont, 16, TEXT_COLOR, FlxTextAlign.CENTER);
		add(_txtStatus);

		// Column headers — hidden until rooms arrive
		_txtColHeader = new FlxText(TABLE_LEFT, TABLE_TOP - 18, LABEL_W, "Room ID         Players", 12);
		_txtColHeader.setFormat(Main.menuFont, 12, TEXT_COLOR);
		_txtColHeader.visible = false;
		add(_txtColHeader);

		// Pre-create MAX_ROWS table rows
		for (i in 0...MAX_ROWS) {
			var rowY = TABLE_TOP + i * ROW_H;

			var label = new FlxText(TABLE_LEFT, rowY + 6, LABEL_W, "", 14);
			label.setFormat(Main.menuFont, 14, TEXT_COLOR);
			label.visible = false;
			add(label);

			var capturedI = i;
			var btn = new FlxButton(TABLE_LEFT + LABEL_W + 20, rowY + (ROW_H - BTN_H) / 2, "Join");
			btn.makeGraphic(BTN_W, BTN_H, FlxColor.WHITE);
			btn.label.setFormat(Main.menuFont, 12, 0x333333, "center");
			btn.label.fieldWidth = BTN_W;
			btn.updateHitbox();
			btn.onUp.callback = () -> clickJoin(capturedI);
			btn.onOver.callback = () -> btn.color = FlxColor.GRAY;
			btn.onOut.callback = () -> btn.color = FlxColor.WHITE;
			btn.visible = false;
			add(btn);

			_roomRows.push({label: label, btn: btn, roomId: ""});
		}

		// Row 1 (y=382): Create Public Room | Create Private Room
		_btnCreatePublic = MenuBuilder.createTextButton("Create Public Room", clickCreatePublic);
		_btnCreatePublic.setPosition(150, 382);
		add(_btnCreatePublic);

		_btnCreatePrivate = MenuBuilder.createTextButton("Create Private Room", clickCreatePrivate);
		_btnCreatePrivate.setPosition(330, 382);
		add(_btnCreatePrivate);

		// Row 2 (y=432): [Room ID input] [Join Room btn]
		_inputRoomId = new FlxInputText(150, 432, 220, "", 14, TEXT_COLOR, FlxColor.WHITE);
		_inputRoomId.maxChars = 9;
		add(_inputRoomId);

		_btnJoinById = new FlxButton(380, 432, "Join Room");
		_btnJoinById.makeGraphic(110, 40, FlxColor.WHITE);
		_btnJoinById.label.setFormat(Main.menuFont, 16, 0x333333, "center");
		_btnJoinById.label.fieldWidth = 110;
		_btnJoinById.updateHitbox();
		_btnJoinById.onUp.callback = clickJoinById;
		_btnJoinById.onOver.callback = () -> _btnJoinById.color = FlxColor.GRAY;
		_btnJoinById.onOut.callback = () -> _btnJoinById.color = FlxColor.WHITE;
		add(_btnJoinById);

		NetworkManager.ME.joinLobby(setupLobby, (err) -> {});
	}

	private function setupLobby(lobby:Room<Schema>) {
		lobbyRoom = lobby;
		_connected = true;
		_rooms = [];

		lobby.onMessage(MSG_ROOMS, (rooms:Array<Dynamic>) -> {
			QLog.notice('Lobby: received ${rooms.length} room(s)');
			_rooms = rooms;
		});

		lobby.onMessage(MSG_ROOM_ADDED, (message:Dynamic) -> {
			var roomId:String = message[0];
			var roomData:Dynamic = message[1];
			var found = false;
			for (i in 0..._rooms.length) {
				if (_rooms[i].roomId == roomId) {
					_rooms[i] = roomData;
					found = true;
					break;
				}
			}
			if (!found) {
				_rooms.push(roomData);
			}
		});

		lobby.onMessage(MSG_ROOM_REMOVED, (roomId:String) -> {
			_rooms = _rooms.filter((r) -> r.roomId != roomId);
		});
	}

	override public function update(elapsed:Float):Void {
		super.update(elapsed);
		refreshTable();
	}

	private function refreshTable():Void {
		var hasRooms = _rooms.length > 0;
		_txtColHeader.visible = hasRooms && !_joining;

		// Status line logic
		if (!_connected) {
			_txtStatus.text = "Connecting...";
			_txtStatus.visible = true;
		}
		if (_joining) {
			_txtStatus.text = "Joining...";
			_txtStatus.visible = true;
		} else if (!hasRooms) {
			_txtStatus.text = "No open rooms — create one to get started!";
			_txtStatus.visible = true;
		} else {
			_txtStatus.visible = false;
		}

		// Update room rows
		for (i in 0...MAX_ROWS) {
			var row = _roomRows[i];
			if (i < _rooms.length) {
				var r:Dynamic = _rooms[i];
				var roomIdStr:String = Std.string(r.roomId);
				var clients:Int = r.clients != null ? Std.int(r.clients) : 0;
				var maxClients:Int = r.maxClients != null ? Std.int(r.maxClients) : 0;

				row.roomId = roomIdStr;
				row.label.text = '${roomIdStr}          ${clients} / ${maxClients} players';
				row.label.visible = true;

				row.btn.active = !_joining;
				row.btn.visible = !_joining;
				row.btn.alpha = _joining ? 0.4 : 1.0;
			} else {
				row.label.visible = false;
				row.btn.visible = false;
				row.roomId = "";
			}
		}

		// Dim all bottom controls while a join is in progress
		_btnCreatePublic.active = !_joining;
		_btnCreatePublic.alpha = _joining ? 0.4 : 1.0;
		_btnCreatePrivate.active = !_joining;
		_btnCreatePrivate.alpha = _joining ? 0.4 : 1.0;
		_btnJoinById.active = !_joining;
		_btnJoinById.alpha = _joining ? 0.4 : 1.0;
		_inputRoomId.active = !_joining;
		_inputRoomId.alpha = _joining ? 0.4 : 1.0;
	}

	private function clickJoin(rowIndex:Int):Void {
		if (_joining) {
			return;
		}
		var row = _roomRows[rowIndex];
		if (row.roomId == "") {
			return;
		}
		_joining = true;
		NetworkManager.ME.joinSpecificRoom(row.roomId, onJoinSuccess, onJoinFail);
	}

	private function clickCreatePublic():Void {
		if (_joining) {
			return;
		}
		_joining = true;
		NetworkManager.ME.joinQueue(onJoinSuccess, onJoinFail);
	}

	private function clickCreatePrivate():Void {
		if (_joining) {
			return;
		}
		_joining = true;
		NetworkManager.ME.createPrivateRoom(onJoinSuccess, onJoinFail);
	}

	private function clickJoinById():Void {
		if (_joining) {
			return;
		}
		var id = StringTools.trim(_inputRoomId.text);
		if (id == "") {
			return;
		}
		_joining = true;
		NetworkManager.ME.joinSpecificRoom(id, onJoinSuccess, onJoinFail);
	}

	private function onJoinSuccess(room:Room<CharSelectState>):Void {
		lobbyRoom.leave(true);
		FlxG.switchState(() -> new CharacterSelectState(room));
	}

	private function onJoinFail(err:HttpException):Void {
		_joining = false;
		_txtStatus.text = 'Failed to join — ${err.message}';
		_txtStatus.visible = true;
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
