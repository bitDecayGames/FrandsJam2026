package schema;

class GameState extends io.colyseus.serializer.schema.Schema {
	@:type("string")
	public var hostSessionId:String;

	@:type("map", PlayerState)
	public var players:io.colyseus.serializer.schema.types.MapSchema<PlayerState> = new io.colyseus.serializer.schema.types.MapSchema<PlayerState>();

	@:type("map", FishState)
	public var fish:io.colyseus.serializer.schema.types.MapSchema<FishState> = new io.colyseus.serializer.schema.types.MapSchema<FishState>();

	@:type("object", RoundState)
	public var round:RoundState = new RoundState();
}
