package schema;

class PlayerState extends io.colyseus.serializer.schema.Schema {
	@:type("float32") public var x:Float = 0;
	@:type("float32") public var y:Float = 0;
	@:type("float32") public var velocityX:Float = 0;
	@:type("float32") public var velocityY:Float = 0;
	@:type("boolean") public var ready:Bool = false;
}
