package states;

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
import flixel.text.FlxText;
import flixel.ui.FlxButton;
import flixel.util.FlxColor;
import ui.MenuBuilder;

using states.FlxStateExt;

class LobbyState extends FlxTransitionableState {
	var _btnDone:FlxButton;

	var _txtTitle:FlxText;
	var _inputField:FlxInputText;
	var _txtPlayerNames:FlxText;

	override public function create():Void {
		super.create();
		bgColor = FlxColor.TRANSPARENT;

		_txtTitle = new FlxText();
		_txtTitle.setPosition(FlxG.width / 2, FlxG.height / 4);
		_txtTitle.size = 40;
		_txtTitle.alignment = FlxTextAlign.CENTER;
		_txtTitle.text = "Lobby";
		add(_txtTitle);

		_inputField = new FlxInputText(FlxG.width / 2 - 50, FlxG.height / 2, 100, FlxG.save.data.name, 20, FlxColor.WHITE, FlxColor.GRAY);
		_inputField.onTextChange.add(updatePlayerName);
		add(_inputField);

		_txtPlayerNames = new FlxText();
		_txtPlayerNames.setPosition(FlxG.width / 2, _inputField.y + _inputField.height + 16);
		_txtPlayerNames.size = 12;
		_txtPlayerNames.alignment = FlxTextAlign.CENTER;
		_txtPlayerNames.text = "";
		add(_txtPlayerNames);

		_btnDone = MenuBuilder.createTextButton("Ready", clickReady);
		_btnDone.setPosition(FlxG.width / 2 - _btnDone.width / 2, FlxG.height - _btnDone.height - 40);
		_btnDone.updateHitbox();
		add(_btnDone);

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

	private function updatePlayerName(text:String, change:FlxInputTextChange) {
		GameManager.ME.net.sendMessage("player_name_changed", {name: text});
	}

	override public function update(elapsed:Float):Void {
		super.update(elapsed);
		_txtTitle.x = FlxG.width / 2 - _txtTitle.width / 2;
		updatePlayerNames();
	}

	private function updatePlayerNames():Void {
		var gm = GameManager.ME;
		var namesList = new Array<String>();
		for (sessionId in gm.sessions) {
			if (sessionId == gm.mySessionId) {
				continue;
			}
			var name = gm.names.get(sessionId);
			if (name != null && name != "") {
				namesList.push(name);
			} else {
				namesList.push("???");
			}
		}
		var newText = namesList.join("\n");
		if (_txtPlayerNames.text != newText) {
			_txtPlayerNames.text = newText;
			_txtPlayerNames.x = FlxG.width / 2 - _txtPlayerNames.width / 2;
		}
	}

	function clickReady():Void {
		FlxG.save.data.name = _inputField.text;
		FlxG.save.flush();
		GameManager.ME.net.sendMessage("player_ready", true);
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
