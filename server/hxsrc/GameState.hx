import colyseus.server.schema.Schema;
import colyseus.server.schema.Schema.MapSchema;

class PlayerState extends Schema {
	@:type("float32") public var x:Float;
	@:type("float32") public var y:Float;

	public function new() {
		super();
		x = 0;
		y = 0;
	}
}

class GameState extends Schema {
	@:type({map: PlayerState})
	public var players:MapSchema<PlayerState>;

	public function new() {
		super();
		players = new MapSchema<PlayerState>();
	}
}
