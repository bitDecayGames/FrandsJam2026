package schema;

import Ldtk;
import Ldtk.LdtkProject;
#if server
import colyseus.server.schema.Schema;
import colyseus.server.schema.Schema.ArraySchema;
import colyseus.server.schema.Schema.MapSchema;
#else
import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.schema.types.ArraySchema;
import io.colyseus.serializer.schema.types.MapSchema;
#end

typedef P_Input = {
	seq:Int, // sequence number
	dir:Int // 0-359 cardinal
};

class GameState extends Schema {
	public static inline var MSG_P_INPUT = "player_input";

	public static var project = new Ldtk.LdtkProject();

	@:type("string") public var levelID:String;

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
	@:type("map", BushState) public var bushes = new MapSchema<BushState>(); // Superseded by `objects`

	#end
	@:type("string") public var hostSessionId:String;
	@:type("float32") public var shopX:Float;
	@:type("float32") public var shopY:Float;
	@:type("boolean") public var shopReady:Bool;

	public var raw:Ldtk.Ldtk_Level;

	// --- NON-Synced Fields
	// server and client each build this locally from the level data
	public var collision:CollisionMap;
	public var inputQueue:Map<String, Array<P_Input>>;

	public function new(levelID:String = "Level_0") {
		super();
		players = new MapSchema<PlayerState>();
		fish = new MapSchema<FishState>();
		round = new RoundState();
		bushes = new MapSchema<BushState>();
		shopX = 0;
		shopY = 0;
		shopReady = false;
		inputQueue = new Map();
		this.levelID = levelID;
		raw = project.getLevel(levelID);
		#if server
		var hitboxJson = sys.io.File.getContent("../assets/data/tile-hitboxes.json");
		#else
		var hitboxJson = openfl.Assets.getText("assets/data/tile-hitboxes.json");
		#end
		collision = CollisionMap.fromLevel(raw, hitboxJson);
	}
}
