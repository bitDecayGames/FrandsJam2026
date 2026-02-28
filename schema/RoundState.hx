package schema;

class RoundState extends io.colyseus.serializer.schema.Schema {
	@:type("string") public var status:String;
	@:type("uint8") public var currentRound:Int;
	@:type("uint8") public var totalRounds:Int;
}
