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
	public static final ACTION_IDLE = "idle";
	public static final ACTION_RUN = "run";
	public static final ACTION_CAST_START = "cast_start";
	public static final ACTION_CAST_IDLE = "cast_idle";
	public static final ACTION_CAST_PULL = "cast_pull";

	public static final FACING_UP = 1;
	public static final FACING_RIGHT = 2;
	public static final FACING_DOWN = 3;
	public static final FACING_LEFT = 4;

	@:type("string") public var actionState:String;
	@:type("float32") public var x:Float;
	@:type("float32") public var y:Float;
	@:type("uint8") public var facing:Int;
	@:type("float32") public var velocityX:Float;
	@:type("float32") public var velocityY:Float;
	@:type("boolean") public var ready:Bool;
	@:type("string") public var name:String;
	@:type("int8") public var skinIndex:Int;
	@:type("int32") public var score:Int;

	public function new() {
		super();
		actionState = ACTION_IDLE;
		x = 0;
		y = 0;
		facing = FACING_DOWN;
		velocityX = 0;
		velocityY = 0;
		ready = false;
		name = "";
		skinIndex = -1;
		score = 0;
	}
}
