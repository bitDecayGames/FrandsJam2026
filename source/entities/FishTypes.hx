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
		new FishTypeData("Minnow", 5, 10, 25),
		new FishTypeData("Goldfish", 10, 20, 50),
		new FishTypeData("Anchovy", 15, 25, 60),
		new FishTypeData("No Name", 18, 8, 30),
		new FishTypeData("Trout", 20, 30, 45),
		new FishTypeData("Stone Fish", 25, 30, 45),
		new FishTypeData("Zebra Fish", 30, 30, 45),
		new FishTypeData("Sword Fish", 35, 30, 45),
		new FishTypeData("Bass", 40, 40, 60),
		new FishTypeData("Golden Bass", 50, 50, 80),
		new FishTypeData("Eel", 75, 20, 120),
		new FishTypeData("Boot", -30, 40, 50),
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
