import colyseus.server.Colyseus;
import colyseus.server.LobbyRoom;
import colyseus.server.QueueRoom;
import colyseus.server.Colyseus.Server;
import rooms.CharacterSelectRoom;

class Main {
	static function main():Void {
		var port:Int = 2567;
		var gameServer = new Server({}); // This didn't seem to work if we pass the rooms in as server config. Claude claims it isn't implemented in the JS, but that disagrees with the docs
		gameServer.define("lobby", LobbyRoom); // This would be for private games / playing with friends
		gameServer.define("char_select", CharacterSelectRoom);
		gameServer.define("char_select_public", CharacterSelectRoom).enableRealtimeListing();
		gameServer.define("game_room", GameRoom);
		gameServer.define("queue", QueueRoom, {
			matchRoomName: "char_select",
			maxPlayers: 2,
		});

		gameServer.listen(port, "0.0.0.0").then((_) -> {
			trace('Listening on ws://localhost:$port');
		});
	}
}
