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
	@:type("boolean") public var alive:Bool;

	// Non-synced fields for server-side AI (no @:type annotation)
	public var targetX:Float;
	public var targetY:Float;
	public var velX:Float;
	public var velY:Float;
	public var retargetTimer:Float;
	public var pauseTimer:Float;
	public var respawnTimer:Float;
	public var scaredTimer:Float;
	public var attracted:Bool;
	public var bodyIndex:Int; // which water body this fish belongs to

	public function new(x:Float, y:Float, fishType:Int = 0) {
		super();
		this.x = x;
		this.y = y;
		this.fishType = fishType;
		alive = true;
		targetX = x;
		targetY = y;
		velX = 0;
		velY = 0;
		retargetTimer = 2.0;
		pauseTimer = 0;
		respawnTimer = 0;
		scaredTimer = 0;
		attracted = false;
		bodyIndex = 0;
	}
}
