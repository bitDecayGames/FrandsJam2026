package schema.meta;

#if server
import colyseus.server.schema.Schema;
import colyseus.server.schema.Schema.ArraySchema;
import colyseus.server.schema.Schema.MapSchema;
#else
import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.schema.types.ArraySchema;
import io.colyseus.serializer.schema.types.MapSchema;
#end

class CharSelectState extends Schema {
	#if server
	@:type({map: PlayerLobbyState}) public var players:MapSchema<PlayerLobbyState>;
	#else
	@:type("map", PlayerLobbyState) public var players = new MapSchema<PlayerLobbyState>();
	#end

	public function new() {
		super();
		this.players = new MapSchema<PlayerLobbyState>();
	}
}

class PlayerLobbyState extends Schema {
	@:type("string") public var sessionId:String;
	@:type("string") public var name:String;
	@:type("uint8") public var skinIndex:Int;
	@:type("boolean") public var ready:Bool;

	public function new(sessionId:String, name:String, skin:Int) {
		super();
		this.sessionId = sessionId;
		this.name = name;
		this.skinIndex = skin;
		ready = false;
	}
}
