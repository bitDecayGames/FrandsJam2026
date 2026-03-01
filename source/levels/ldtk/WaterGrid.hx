package levels.ldtk;

class WaterGrid {
	public var cWid:Int;
	public var cHei:Int;
	public var gridSize:Int;

	var data:Array<Int>;

	public function new(w:Int, h:Int, gridSize:Int) {
		this.cWid = w;
		this.cHei = h;
		this.gridSize = gridSize;
		data = new Array<Int>();
		data.resize(w * h);
		for (i in 0...data.length) {
			data[i] = 0;
		}
	}

	public function setWater(cx:Int, cy:Int) {
		if (cx >= 0 && cx < cWid && cy >= 0 && cy < cHei) {
			data[cy * cWid + cx] = 1;
		}
	}

	public function getInt(cx:Int, cy:Int):Int {
		if (cx < 0 || cx >= cWid || cy < 0 || cy >= cHei) {
			return 0;
		}
		return data[cy * cWid + cx];
	}
}
