package schema;

#if server
import colyseus.server.schema.Schema;
import colyseus.server.schema.Schema.ArraySchema;
import colyseus.server.schema.Schema.MapSchema;
#else
import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.schema.types.ArraySchema;
import io.colyseus.serializer.schema.types.MapSchema;
#end

class PlayerState extends Schema {
	@:type("float32") public var x:Float;
	@:type("float32") public var y:Float;
	@:type("float32") public var velocityX:Float;
	@:type("float32") public var velocityY:Float;
	@:type("boolean") public var ready:Bool;
	@:type("string") public var name:String;
	@:type("int8") public var skinIndex:Int;
	@:type("int32") public var score:Int;

	public function new() {
		super();
		x = 0;
		y = 0;
		velocityX = 0;
		velocityY = 0;
		ready = false;
		name = "";
		skinIndex = -1;
		score = 0;
	}
}
