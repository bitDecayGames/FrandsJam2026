package math;

class Vector {
	public var x:Float;
	public var y:Float;

	public function new(X:Float = 0, Y:Float = 0) {
		x = X;
		y = Y;
	}

	/** Returns a unit vector for the given angle in degrees. 0 = up, 90 = right, 180 = down, 270 = left. **/
	public static function fromAngle(degrees:Float):Vector {
		var rad = degrees * Math.PI / 180;
		return new Vector(Math.sin(rad), -Math.cos(rad));
	}

	public function length():Float {
		return Math.sqrt(x * x + y * y);
	}

	public function normalize(v:Vector) {
		var len = length();
		if (len == 0) {
			x = 0;
			y = 0;
			return;
		}

		x = x / len;
		y = y / len;
		return;
	}
}
