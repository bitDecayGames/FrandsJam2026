package schema;

class PlayerState extends io.colyseus.serializer.schema.Schema {
	@:type("float32") public var x:Float = 0;
	@:type("float32") public var y:Float = 0;
}
