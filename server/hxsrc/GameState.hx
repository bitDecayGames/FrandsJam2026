import colyseus.server.schema.Schema;
import colyseus.server.schema.Schema.MapSchema;

class PlayerState extends Schema {
	@:type("float32") public var x:Float;
	@:type("float32") public var y:Float;
	@:type("float32") public var velocityX:Float;
	@:type("float32") public var velocityY:Float;

	public function new() {
		super();
		x = 0;
		y = 0;
		velocityX = 0;
		velocityY = 0;
	}
}

class FishState extends Schema {
	@:type("float32") public var x:Float;
	@:type("float32") public var y:Float;

	public function new(x:Float, y:Float) {
		super();
		this.x = x;
		this.y = y;
	}
}

class RoundState extends Schema {
	public static final STATUS_INACTIVE = "inactive";
	public static final STATUS_LOBBY = "lobby";
	public static final STATUS_PRE_ROUND = "pre_round";
	public static final STATUS_ACTIVE = "active";
	public static final STATUS_POST_ROUND = "post_round";
	public static final STATUS_END_GAME = "end_game";

	@:type("string") public var status:String;
	@:type("uint8") public var currentRound:Int;
	@:type("uint8") public var totalRounds:Int;

	public function new() {
		super();
		status = STATUS_INACTIVE;
		currentRound = -1;
		totalRounds = -1;
	}
}

class GameState extends Schema {
	@:type("string")
	public var hostSessionId:String;

	@:type({map: PlayerState})
	public var players:MapSchema<PlayerState>;

	@:type({map: FishState})
	public var fish:MapSchema<FishState>;

	@:type(RoundState)
	public var round:RoundState;

	public function new() {
		super();
		players = new MapSchema<PlayerState>();
		fish = new MapSchema<FishState>();
		round = new RoundState();
	}
}
