package;

typedef FishTypeDef = {
	name:String,
	basePrice:Int,
	minLength:Int,
	maxLength:Int
};

/**
 * Fish pricing data + value formula — single source of truth shared by the
 * client (FishTypes delegates here) and the server (round summary payouts).
**/
class FishValue {
	// Fish type indices correspond to sprite frame indices in fish.png
	public static var TYPES:Array<FishTypeDef> = [
		{name: "Minnow", basePrice: 5, minLength: 10, maxLength: 25},
		{name: "Goldfish", basePrice: 10, minLength: 20, maxLength: 50},
		{name: "Anchovy", basePrice: 15, minLength: 25, maxLength: 60},
		{name: "No Name", basePrice: 18, minLength: 8, maxLength: 30},
		{name: "Trout", basePrice: 20, minLength: 30, maxLength: 45},
		{name: "Stone Fish", basePrice: 25, minLength: 30, maxLength: 45},
		{name: "Zebra Fish", basePrice: 30, minLength: 30, maxLength: 45},
		{name: "Sword Fish", basePrice: 35, minLength: 30, maxLength: 45},
		{name: "Bass", basePrice: 40, minLength: 40, maxLength: 60},
		{name: "Golden Bass", basePrice: 50, minLength: 50, maxLength: 80},
		{name: "Eel", basePrice: 75, minLength: 20, maxLength: 120},
		{name: "Boot", basePrice: -30, minLength: 40, maxLength: 50},
	];

	/** Calculate the sell value of a fish: basePrice * ((length - min) / (max - min)) + basePrice * 0.5 */
	public static function calculateValue(typeIndex:Int, lengthCm:Int):Int {
		if (typeIndex < 0 || typeIndex >= TYPES.length) {
			return 10;
		}
		var data = TYPES[typeIndex];
		var range = data.maxLength - data.minLength;
		var lengthFactor:Float = if (range > 0) {
			(lengthCm - data.minLength) / range;
		} else {
			0.5;
		};
		var value:Float = data.basePrice * lengthFactor + data.basePrice * 0.5;
		return Math.round(value);
	}
}
