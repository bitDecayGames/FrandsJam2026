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
	// Fish type indices correspond to sprite frame indices (0-4) in fish.png
	public static var TYPES:Array<FishTypeData> = [
		new FishTypeData("Bluegill", 5, 10, 25),
		new FishTypeData("Bass", 10, 20, 50),
		new FishTypeData("Trout", 15, 25, 60),
		new FishTypeData("Catfish", 20, 30, 80),
		new FishTypeData("Salmon", 30, 40, 100),
	];

	/** Generate a random length for the given fish type index. */
	public static function randomLength(typeIndex:Int):Int {
		if (typeIndex < 0 || typeIndex >= TYPES.length) {
			return 20;
		}
		var data = TYPES[typeIndex];
		return FlxG.random.int(data.minLength, data.maxLength);
	}

	/** Calculate the sell value of a fish: baseAmount * ((length - min) / (max - min)) + baseAmount * 0.5 */
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
