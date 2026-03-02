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

class FishState extends Schema {
	@:type("float32") public var x:Float;
	@:type("float32") public var y:Float;
	@:type("int8") public var fishType:Int;

	public function new(x:Float, y:Float, fishType:Int = 0) {
		super();
		this.x = x;
		this.y = y;
		this.fishType = fishType;
	}
}
