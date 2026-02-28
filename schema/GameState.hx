package schema;

class GameState extends io.colyseus.serializer.schema.Schema {
	@:type("map", PlayerState)
	public var players:io.colyseus.serializer.schema.types.MapSchema<PlayerState> = new io.colyseus.serializer.schema.types.MapSchema<PlayerState>();
}
