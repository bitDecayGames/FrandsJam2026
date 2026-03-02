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

class GameState extends Schema {
	#if server
	// Maps and direct references seem to need slightly different type hits to compile properly
	@:type({map: PlayerState}) public var players:MapSchema<PlayerState>;
	@:type({map: FishState}) public var fish:MapSchema<FishState>;
	@:type(RoundState) public var round:RoundState;
	@:type({map: BushState}) public var bushes:MapSchema<BushState>;
	#else
	@:type("map", PlayerState) public var players = new MapSchema<PlayerState>();
	@:type("map", FishState) public var fish = new MapSchema<FishState>();
	@:type("ref", RoundState) public var round = new RoundState();
	@:type("map", BushState) public var bushes = new MapSchema<BushState>(); // Superceded by `objects`

	#end
	@:type("string") public var hostSessionId:String;
	@:type("float32") public var shopX:Float;
	@:type("float32") public var shopY:Float;
	@:type("boolean") public var shopReady:Bool;

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
