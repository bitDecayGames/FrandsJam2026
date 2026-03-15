package net;

typedef PlayerClientState = {
	var x:Float;
	var y:Float;
	var vx:Float;
	var vy:Float;
}

/**
 * Wraps a live Colyseus schema ref + our local smooth state.
 * Behavior is injected via onTick/onServerUpdate so the entity
 * doesn't need to know if it's local or remote.
 */
class NetworkedState<TServer, TClient> {
	/** Live Colyseus schema — auto-mutated by Colyseus on broadcast */
	public var server(default, null):TServer;

	/** Our smooth client-side state (local prediction or interpolation) */
	public var client:TClient;

	/**
	 * Called each frame. Injected by whoever creates this state.
	 * For local players: runs prediction + setPosition.
	 * For remote players: runs interpolation + setPosition.
	 */
	public var onTick:(elapsed:Float) -> Void = null;

	/**
	 * Called when Colyseus onChange fires.
	 * For local players: reconcile (prune inputs, snap, replay).
	 * For remote players: nothing needed — schema is live.
	 */
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
