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
	public static final CONTROL_STATE_IDLE = "idle";
	public static final CONTROL_STATE_CHARGING = "charging";
	public static final CONTROL_STATE_CASTING = "casting";
	public static final CONTROL_STATE_WAITING = "waiting";
	public static final CONTROL_STATE_RETURNING = "returning";

	public static final BUTTON_A = 1 << 0;
	public static final BUTTON_B = 1 << 1;

	public static final ACTION_IDLE = "idle";
	public static final ACTION_RUN = "run";

	public static final FACING_UP = 1;
	public static final FACING_RIGHT = 2;
	public static final FACING_DOWN = 3;
	public static final FACING_LEFT = 4;

	@:type("float32") public var x:Float;
	@:type("float32") public var y:Float;
	@:type("float32") public var velocityX:Float;
	@:type("float32") public var velocityY:Float;
	@:type("boolean") public var ready:Bool;
	@:type("string") public var name:String;
	@:type("int8") public var skinIndex:Int;
	@:type("int32") public var score:Int;
	@:type("int32") public var lastProcessedSeq:Int;
	@:type("float32") public var speed:Float;
	@:type("float32") public var width:Float;
	@:type("float32") public var height:Float;
	@:type("string") public var controlState:String;
	@:type("string") public var actionIntent:String;
	@:type("string") public var actionState:String;
	@:type("uint8") public var facing:Int;
	@:type("float32") public var castPower:Float;
	@:type("float32") public var castTargetX:Float;
	@:type("float32") public var castTargetY:Float;

	public var cd:utils.Cooldowns;
	public var castPowerDir:Float;

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
		lastProcessedSeq = 0;
		speed = 100;
		width = 16;
		height = 8;
		controlState = CONTROL_STATE_IDLE;
		actionIntent = ACTION_IDLE;
		actionState = ACTION_IDLE;
		facing = FACING_DOWN;
		castPower = 0;
		castPowerDir = 1;
		castTargetX = 0;
		castTargetY = 0;
		cd = new utils.Cooldowns();
	}

	public static function copy(source:PlayerState):PlayerState {
		var s = new PlayerState();
		s.x = source.x;
		s.y = source.y;
		s.velocityX = source.velocityX;
		s.velocityY = source.velocityY;
		s.speed = source.speed;
		s.width = source.width;
		s.height = source.height;
		s.name = source.name;
		s.skinIndex = source.skinIndex;
		s.score = source.score;
		s.lastProcessedSeq = source.lastProcessedSeq;
		s.ready = source.ready;
		s.controlState = source.controlState;
		s.actionIntent = source.actionIntent;
		s.actionState = source.actionState;
		s.facing = source.facing;
		s.castPower = source.castPower;
		s.castPowerDir = source.castPowerDir;
		s.castTargetX = source.castTargetX;
		s.castTargetY = source.castTargetY;
		return s;
	}
}
