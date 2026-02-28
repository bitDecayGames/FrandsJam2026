package schema;

class RoundState extends io.colyseus.serializer.schema.Schema {
	public static final STATUS_INACTIVE = "inactive";
	public static final STATUS_LOBBY = "lobby";
	public static final STATUS_PRE_ROUND = "pre_round";
	public static final STATUS_ACTIVE = "active";
	public static final STATUS_POST_ROUND = "post_round";
	public static final STATUS_END_GAME = "end_game";

	@:type("string") public var status:String;
	@:type("uint8") public var currentRound:Int;
	@:type("uint8") public var totalRounds:Int;
}
