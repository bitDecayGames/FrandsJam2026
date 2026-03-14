import colyseus.server.Colyseus;
import colyseus.server.LobbyRoom;
import colyseus.server.QueueRoom;
import colyseus.server.Colyseus.Server;
import rooms.GameRoom;
import rooms.CharacterSelectRoom;
import schema.Constants;

class Main {
	static function main():Void {
		var port:Int = 2567;
		var gameServer = new Server({
			express: (app) -> {
				app.use('/monitor', Colyseus.monitor());
			},
			// devMode: true, // This setting will cache servers on shutdown so we can persist state between restarts for faster iteration
		});

		gameServer.define(RoomName.LOBBY, LobbyRoom); // This would be for private games / playing with friends
		gameServer.define(RoomName.QUEUE, QueueRoom, {
			matchRoomName: RoomName.CHAR_SELECT,
			maxPlayers: 2,
		}).realtimeListingEnabled = false;

		gameServer.define(RoomName.CHAR_SELECT, CharacterSelectRoom).enableRealtimeListing();
		gameServer.define(RoomName.CHAR_SELECT_PRIVATE, CharacterSelectRoom);

		gameServer.define(RoomName.GAME, GameRoom);

		gameServer.listen(port, "0.0.0.0").then((_) -> {
			trace('Listening on ws://localhost:$port');
			#if simlag
			var lag = 200;
			trace('simulating ${lag}ms of latency');
			gameServer.simulateLatency(lag);
			#end
			return null;
		});
	}
}
