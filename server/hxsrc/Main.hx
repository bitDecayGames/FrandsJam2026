import colyseus.server.Colyseus;
import colyseus.server.LobbyRoom;
import colyseus.server.QueueRoom;
import colyseus.server.Colyseus.Server;
import rooms.CharacterSelectRoom;

class Main {
	static function main():Void {
		var port:Int = 2567;
		var gameServer = new Server({
			// devMode: true, // This setting will cache servers on shutdown so we can persist state between restarts for faster iteration
		});
		gameServer.define("lobby", LobbyRoom); // This would be for private games / playing with friends
		gameServer.define("queue", QueueRoom, {
			matchRoomName: "char_select",
			maxPlayers: 2,
		});

		gameServer.define("char_select", CharacterSelectRoom);
		gameServer.define("char_select_public", CharacterSelectRoom).enableRealtimeListing();

		gameServer.define("game_room", GameRoom);

		gameServer.listen(port, "0.0.0.0").then((_) -> {
			trace('Listening on ws://localhost:$port');
		});
	}
}
