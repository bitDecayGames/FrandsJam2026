package net;

class NetworkedState<TServer, TClient> {
	public var server(default, null):TServer;
	public var client:TClient;
	public var onTick:(elapsed:Float) -> Void = null;
	public var onServerUpdate:() -> Void = null;

	public function new(serverRef:TServer, initialClient:TClient) {
		server = serverRef;
		client = initialClient;
	}

	public function tick(elapsed:Float):Void {
		if (onTick != null) {
			onTick(elapsed);
		}
	}

	public function serverUpdate():Void {
		if (onServerUpdate != null) {
			onServerUpdate();
		}
	}
}
