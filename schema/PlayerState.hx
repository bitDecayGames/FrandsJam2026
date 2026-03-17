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
import utils.Cooldowns;

class PlayerState extends Schema {
	public static final CONTROL_STATE_IDLE = "idle";
	public static final CONTROL_STATE_CHARGING = "charging";
	public static final CONTROL_STATE_CASTING = "casting";
	public static final CONTROL_STATE_WAITING = "waiting";
	public static final CONTROL_STATE_RETURNING = "returning";

	public static final BUTTON_A = 1 << 0;
	public static final BUTTON_B = 1 << 1;

	public static final ACTION_IDLE = "idle";
	public static final ACTION_RUN = "run";
	public static final ACTION_CAST_START = "cast_start";
	public static final ACTION_CAST_IDLE = "cast_idle";
	public static final ACTION_CAST_PULL = "cast_pull";

	public static final FACING_UP = 1;
	public static final FACING_RIGHT = 2;
	public static final FACING_DOWN = 3;
	public static final FACING_LEFT = 4;

	// Do we want to try to sync these?
	public var cd:Cooldowns;

	@:type("uint8") public var id:Int;

	@:type("string") public var controlState:String;
	@:type("string") public var actionIntent:String;
	@:type("string") public var actionState:String;

	@:type("float32") public var speed:Float;
	@:type("float32") public var x:Float;
	@:type("float32") public var y:Float;
	@:type("float32") public var width:Float;
	@:type("float32") public var height:Float;
	@:type("float32") public var velocityX:Float;
	@:type("float32") public var velocityY:Float;

	@:type("uint8") public var facing:Int;
	@:type("string") public var name:String;
	@:type("int8") public var skinIndex:Int;
	@:type("int32") public var score:Int;
	@:type("int32") public var lastProcessedSeq:Int;

	public function new() {
		super();
		actionState = ACTION_IDLE;
		x = 0;
		y = 0;
		width = 16;
		height = 8;
		speed = 100;
		facing = FACING_DOWN;
		velocityX = 0;
		velocityY = 0;
		name = "";
		skinIndex = -1;
		score = 0;
		lastProcessedSeq = 0;

		cd = new Cooldowns();
	}

	public static function copy(source:PlayerState):PlayerState {
		var newState = new PlayerState();

		newState.actionState = source.actionState;
		newState.x = source.x;
		newState.y = source.y;
		newState.width = source.width;
		newState.height = source.height;
		newState.speed = source.speed;
		newState.facing = source.facing;
		newState.velocityX = source.velocityX;
		newState.velocityY = source.velocityY;
		newState.name = source.name;
		newState.skinIndex = source.skinIndex;
		newState.score = source.score;
		newState.lastProcessedSeq = source.lastProcessedSeq;

		return newState;
	}
}
