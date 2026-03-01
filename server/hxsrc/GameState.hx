import colyseus.server.schema.Schema;
import colyseus.server.schema.Schema.MapSchema;

class BushState extends Schema {
	@:type("float32") public var x:Float;
	@:type("float32") public var y:Float;

	public function new(x:Float, y:Float) {
		super();
		this.x = x;
		this.y = y;
	}
}

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
		status = STATUS_LOBBY;
		currentRound = 0;
		totalRounds = 0;
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

	@:type({map: BushState})
	public var bushes:MapSchema<BushState>;

	@:type("float32")
	public var shopX:Float;

	@:type("float32")
	public var shopY:Float;

	@:type("boolean")
	public var shopReady:Bool;

	public function new() {
		super();
		players = new MapSchema<PlayerState>();
		fish = new MapSchema<FishState>();
		round = new RoundState();
		bushes = new MapSchema<BushState>();
		shopX = 0;
		shopY = 0;
		shopReady = false;
	}
}
