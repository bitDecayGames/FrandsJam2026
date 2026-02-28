import colyseus.server.Client;
import colyseus.server.Room.RoomOf;
import colyseus.server.Room.CloseCode;
import GameState.PlayerState;
import haxe.extern.EitherType;
import js.lib.Promise;

class GameRoom extends RoomOf<GameState, Dynamic> {
	override public function onCreate(options:Dynamic):Void {
		maxClients = 4;
		setState(new GameState());
		onMessage("move", (client:Client, data:Dynamic) -> {
			var player:PlayerState = state.players.get(client.sessionId);
			if (player != null) {
				player.x = data.x;
				player.y = data.y;
			}
		});
	}

	override public function onJoin(client:Client, ?options:Dynamic):EitherType<Void, Promise<Dynamic>> {
		trace('player joined: ${client.sessionId}');
		state.players.set(client.sessionId, new PlayerState());
		return null;
	}

	override public function onLeave(client:Client, ?code:CloseCode):EitherType<Void, Promise<Dynamic>> {
		trace('player left: ${client.sessionId}');
		trace('successful clear: ${state.players.delete(client.sessionId)}');
		return null;
	}
}
