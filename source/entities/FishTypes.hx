package entities;

import flixel.FlxG;

class FishTypeData {
	public var name:String;
	public var basePrice:Int;
	public var minLength:Int; // in cm
	public var maxLength:Int; // in cm

	public function new(name:String, basePrice:Int, minLength:Int, maxLength:Int) {
		this.name = name;
		this.basePrice = basePrice;
		this.minLength = minLength;
		this.maxLength = maxLength;
	}
}

class FishTypes {
	// Fish type indices correspond to sprite frame indices in fish.png.
	// Data lives in shared/FishValue.hx so the server can price fish too.
	public static var TYPES:Array<FishTypeData> = [
		for (d in FishValue.TYPES) new FishTypeData(d.name, d.basePrice, d.minLength, d.maxLength)
	];

	/** Generate a random length for the given fish type index. */
	public static function randomLength(typeIndex:Int):Int {
		if (typeIndex < 0 || typeIndex >= TYPES.length) {
			return 20;
		}
		var data = TYPES[typeIndex];
		return FlxG.random.int(data.minLength, data.maxLength);
	}

	/** Calculate the sell value of a fish — delegates to the shared formula. */
	public static function calculateValue(typeIndex:Int, lengthCm:Int):Int {
		return FishValue.calculateValue(typeIndex, lengthCm);
	}
}
