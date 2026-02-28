import colyseus.server.Colyseus.Server;

class Main {
	static function main():Void {
		var port:Int = 2567;
		var gameServer = new Server();
		gameServer.define("game_room", GameRoom);
		gameServer.listen(port, "0.0.0.0").then((_) -> {
			trace('Listening on ws://localhost:$port');
		});
	}
}
