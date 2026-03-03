package rooms;

import colyseus.server.MatchMaker;
import haxe.Json;
import colyseus.server.Client;
import colyseus.server.Room.RoomOf;
import colyseus.server.Room.CloseCode;
import haxe.extern.EitherType;
import js.lib.Promise;
import schema.meta.CharSelectState;
import schema.meta.CharSelectState.PlayerLobbyState;

class CharacterSelectRoom extends RoomOf<CharSelectState, Dynamic> {
	override public function onCreate(options:Dynamic):Void {
		maxClients = 6;
		setState(new CharSelectState());

		trace('Start character select lobby: ${roomId}:${roomName}');
		onMessage("player_name_changed", (client:Client, data:{
			name:String,
		}) -> {
			var player:PlayerLobbyState = state.players.get(client.sessionId);
			if (player != null) {
				player.name = data.name;
			}
		});

		// sent when a player changes their skin selection in the lobby
		onMessage("skin_changed", (client:Client, data:Dynamic) -> {
			trace('${client.sessionId}: sent "skin_changed" message: skinIndex=${data.skinIndex}');
			var player:PlayerLobbyState = state.players.get(client.sessionId);
			if (player != null) {
				player.skinIndex = data.skinIndex;
			}
		});

		onMessage("kick", (client:Client, data:{targetSessionId:String}) -> {
			trace('${client.sessionId}: wants to kick ${data.targetSessionId}');
			var target = clients.getById(data.targetSessionId);
			if (target == null) {
				return;
			}

			// Remove the player from state immediately so other clients see it right away.
			// onLeave will also fire after the WebSocket closes but will safely no-op.
			state.players.delete(data.targetSessionId);

			// Notify the kicked client and disconnect them via standard Colyseus method
			target.send("kicked", {});
			target.leave(CloseCode.CONSENTED);

			if (state.players.size == 0) {
				trace('Lobby ${roomId} has no players. closing');
				disconnect(1000);
				return;
			}

			// Tell all remaining clients explicitly so they can update their player lists
			// without relying on the schema patch cycle or background-thread schema callbacks
			broadcast("player_kicked", {sessionId: data.targetSessionId}, {except: target});
		});

		onMessage("player_ready", (client:Client, _) -> {
			var player:PlayerLobbyState = state.players.get(client.sessionId);
			if (player != null) {
				player.ready = true;
			}

			var ready = true;
			for (sId => pp in state.players) {
				if (!pp.ready) {
					ready = false;
					break;
				}
			}
			if (ready) {
				this.lock();

				// TODO: move all players to a "game_room lobby" and close this one
				MatchMaker.createRoom("game_room", {}).then(function(reservation:Dynamic) {
					for (client in clients) {
						MatchMaker.reserveSeatFor(reservation, {sessionId: client.sessionId}).then(function(seatRes:SeatReservation) {
							client.send("move_to_game", seatRes);
						});
					}
				}).catchError(function(err:Dynamic) {
					trace("Failed to create game room: " + err);
				});
			}
		});
	}

	override public function onJoin(client:Client, ?options:Dynamic):EitherType<Void, Promise<Dynamic>> {
		trace('player joined: ${client.sessionId}');
		state.players.set(client.sessionId, new PlayerLobbyState(client.sessionId, "Player 1", 1));
		return null;
	}

	override public function onLeave(client:Client, ?code:CloseCode):EitherType<Void, Promise<Dynamic>> {
		trace('player left: ${client.sessionId}');

		state.players.delete(client.sessionId);

		if (state.players.size == 0) {
			trace('Lobby ${roomId} has no players. closing');
			disconnect(1000);
		}

		return null;
	}
}
