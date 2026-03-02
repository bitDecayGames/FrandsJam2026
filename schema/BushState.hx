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

class BushState extends Schema {
	@:type("float32") public var x:Float;
	@:type("float32") public var y:Float;

	public function new(x:Float, y:Float) {
		super();
		this.x = x;
		this.y = y;
	}
}
