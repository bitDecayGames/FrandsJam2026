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
