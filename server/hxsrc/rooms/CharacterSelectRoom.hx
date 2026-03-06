package rooms;

import schema.Constants.RoomName;
import transition.PlayerInitData;
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
		trace('Start character select lobby: ${roomId}:${roomName}');

		maxClients = 6;
		setState(new CharSelectState());
		configureMessages();
	}

	private function configureMessages() {
		onMessage(CharSelectState.MSG_NAME_CHANGED, (client:Client, data:{
			name:String,
		}) -> {
			var player:PlayerLobbyState = state.players.get(client.sessionId);
			if (player != null) {
				player.name = data.name;
			}
		});

		// TODO: Directional selection for better controller support
		// sent when a player changes their skin selection in the lobby
		onMessage(CharSelectState.MSG_SKIN_CHANGED, (client:Client, data:Dynamic) -> {
			trace('(${client.sessionId}): ${CharSelectState.MSG_SKIN_CHANGED} skinIndex=${data.skinIndex}');
			var player:PlayerLobbyState = state.players.get(client.sessionId);
			if (player != null) {
				for (p in state.players) {
					if (p.skinIndex == data.skinIndex) {
						// rejected
						return;
					}
				}
				// Nobody else had that index, so update!
				player.skinIndex = data.skinIndex;
			}
		});

		onMessage(CharSelectState.MSG_KICK, (client:Client, data:{targetSessionId:String}) -> {
			trace('${client.sessionId}: wants to kick ${data.targetSessionId}');
			var target = clients.getById(data.targetSessionId);
			if (target == null) {
				return;
			}

			// Remove the player from state immediately so other clients see it right away.
			// onLeave will also fire after the WebSocket closes but will safely no-op.
			state.players.delete(data.targetSessionId);

			// Tell all clients explicitly so they can update their player lists without relying on the schema patch
			// cycle or background-thread schema callbacks
			broadcast(CharSelectState.SERVER_MSG_PLAYER_KICKED, {sessionId: data.targetSessionId});

			// Notify the kicked client and disconnect them via standard Colyseus method
			target.leave(CloseCode.CONSENTED);
		});

		onMessage(CharSelectState.MSG_READY, (client:Client, _) -> {
			var player:PlayerLobbyState = state.players.get(client.sessionId);
			if (player != null) {
				player.ready = true;
			}

			var ready = true;
			for (pp in state.players) {
				if (!pp.ready) {
					ready = false;
					break;
				}
			}
			if (ready) {
				this.lock();

				// TODO: move all players to a "game_room lobby" and close this one
				MatchMaker.createRoom(RoomName.GAME, buildGameInitMetadata()).then(function(reservation:Dynamic) {
					for (client in clients) {
						MatchMaker.reserveSeatFor(reservation, {sessionId: client.sessionId}).then(function(seatRes:SeatReservation) {
							client.send(CharSelectState.SERVER_MSG_MOVE_TO_GAME, seatRes);
						});
					}
				}).catchError(function(err:Dynamic) {
					trace("Failed to create game room: " + err);
				});
			}
		});
	}

	private function buildGameInitMetadata():Dynamic {
		var playerSeedData:Array<PlayerInitData> = [];
		for (sID => pData in state.players) {
			playerSeedData.push({
				sessionID: sID,
				name: pData.name,
				skin: pData.skinIndex
			});
		}
		return {
			players: playerSeedData
			// TODO: We should also seed the game mode data here
		};
	}

	override public function onJoin(client:Client, ?options:Dynamic):EitherType<Void, Promise<Dynamic>> {
		trace('player joined: ${client.sessionId}');
		var freeSlot = 0;
		for (i in 0...6) {
			for (p in state.players) {
				if (p.skinIndex != i) {
					freeSlot = i;
				}
			}
		}
		state.players.set(client.sessionId, new PlayerLobbyState(client.sessionId, "Unnamed Player", freeSlot));
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
