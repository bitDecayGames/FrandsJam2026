package managers;

import events.gen.Event.FishCollected;
import events.gen.Event.FishCaught;
import events.EventBus;

class FishManager {
	public static var ME:FishManager;

	public var db:FishDb;

	public function new(db:FishDb) {
		ME = this;
		this.db = db;

		EventBus.subscribe(FishCaught, (e) -> {
			var err = db.markAsCaught(e.fishId, e.ownerId);
			if (err != null) {
				QLog.error('failed to catch fish: ${err}');
			}
		});
		EventBus.subscribe(FishCollected, (e) -> {
			var err = db.markAsCollected(e.fishId);
			if (err != null) {
				QLog.error('failed to collect fish: ${err}');
			}
		});
	}
}

class FishDb {
	public var id:Array<String> = [];
	public var ownerId:Array<Null<String>> = [];
	public var status:Array<Int> = [];
	public var type:Array<Int> = [];
	public var quality:Array<Int> = [];
	public var weightOz:Array<Int> = [];
	public var lengthCm:Array<Int> = [];

	public function new() {}

	public function add(fish:FishRecord) {
		id.push(fish.id);
		ownerId.push(fish.ownerId);
		status.push(fish.status);
		type.push(fish.type);
		quality.push(fish.quality);
		weightOz.push(fish.weightOz);
		lengthCm.push(fish.lengthCm);
	}

	public function update(fish:FishRecord):Null<String> {
		var index = findIndex(fish.id);
		if (index < 0) {
			return 'fish with id "${fish.id}" could not be found';
		}
		id[index] = fish.id;
		ownerId[index] = fish.ownerId;
		status[index] = fish.status;
		type[index] = fish.type;
		quality[index] = fish.quality;
		weightOz[index] = fish.weightOz;
		lengthCm[index] = fish.lengthCm;
		return null;
	}

	public function delete(id:String) {
		var index = findIndex(id);
		if (index < 0) {
			return;
		}
		status[index] = FishStatus.STATUS_DELETED;
	}

	public function markAsCaught(id:String, ownerId:String):Null<String> {
		var index = findIndex(id);
		if (index < 0) {
			return 'fish with id "${id}" could not be found';
		}
		if (this.ownerId[index] != null) {
			return 'fish with id "${id}" was already caught by "${this.ownerId[index]}"';
		}
		if (this.status[index] != FishStatus.STATUS_UNCAUGHT) {
			return 'fish with id "${id}" status was "${this.status[index]}"';
		}
		this.ownerId[index] = ownerId;
		status[index] = FishStatus.STATUS_CAUGHT;
		return null;
	}

	public function markAsCollected(id:String):Null<String> {
		var index = findIndex(id);
		if (index < 0) {
			return 'fish with id "${id}" could not be found';
		}
		if (this.ownerId[index] == null) {
			return 'fish with id "${id}" has no owner';
		}
		if (this.status[index] != FishStatus.STATUS_CAUGHT) {
			return 'fish with id "${id}" status was "${this.status[index]}"';
		}
		status[index] = FishStatus.STATUS_COLLECTED;
		return null;
	}

	public function export():Array<FishRecord> {
		var result:Array<FishRecord> = [];
		for (index in 0...id.length) {
			var r = new FishRecord();
			r.id = id[index];
			r.ownerId = ownerId[index];
			r.status = status[index];
			r.type = type[index];
			r.quality = quality[index];
			r.weightOz = weightOz[index];
			r.lengthCm = lengthCm[index];
			result.push(r);
		}
		return result;
	}

	private function findIndex(id:String):Int {
		for (index in 0...this.id.length) {
			if (this.id[index] == id) {
				return index;
			}
		}
		return -1;
	}
}

class FishRecord {
	public var id:String;
	public var ownerId:Null<String>;
	public var status:Int;
	public var type:Int;
	public var quality:Int;
	public var weightOz:Int;
	public var lengthCm:Int;

	public function new() {}
}

class FishStatus {
	public static final STATUS_DELETED = -1;
	public static final STATUS_UNKNOWN = 0;
	public static final STATUS_UNCAUGHT = 1;
	public static final STATUS_CAUGHT = 2;
	public static final STATUS_COLLECTED = 3;
}
