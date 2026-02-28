package config;

import com.bitdecay.analytics.Bitlytics;
import com.bitdecay.net.influx.InfluxDB;
import misc.Macros;

/**
 * Provides access to the configuration json for the project. Helper functions
 * for computing more complex types can go in here, or you can use `get()` to
 * just get the whole config to process it any way you wish
 */
class Configure {
	public static var config = Validator.load("assets/data/config.json");

	/**
	 * Initializes analytics based on the values loaded from config.json
	 *
	 * @param dev control if analytics should be started in dev mode
	 */
	public static function initAnalytics(devMode:Bool = false) {
		var analyticsToken = "";

		if (Macros.isDefined("API_KEY")) {
			var define = Macros.getDefine("API_KEY");
			// our define comes back as <val>=<val>
			// Take the first half explicitly, as splitting on '=' might have unexpected
			// behavior if the token has '=' characters in it
			analyticsToken = define.substr(0, Std.int(define.length / 2));
			if (analyticsToken.length <= 0) {
				trace("no valid analytics token found in API_KEY define, setting dev mode to true");
				devMode = true;
			}
		} else {
			trace('No API_KEY compile flag found. Production metrics will not work.');
			devMode = true;
		}

		Bitlytics.Init(config.analytics.name, InfluxDB.load(config.analytics.influx, analyticsToken), devMode);
		Bitlytics.Instance().NewSession();
	}

	/**
	 * Helper to load credits entries from config.json
	 *
	 * @returns Array of CreditEntry objects
	 */
	public static function getCredits():Array<CreditEntry> {
		var creditSections:Array<CreditEntry> = cast config.credits.sections;
		return creditSections;
	}

	public static function getServerURL():String {
		#if sys
		return Sys.getEnv("SERVER_URL");
		#end

		if (Macros.isDefined("SERVER_URL")) {
			var define = Macros.getDefine("SERVER_URL");
			// our define comes back as <val>=<val>
			// Take the first half explicitly, as splitting on '=' might have unexpected
			// behavior if the token has '=' characters in it
			var url = define.substr(0, Std.int(define.length / 2));
			if (url.length <= 0) {
				trace("no valid analytics token found in API_KEY define, setting dev mode to true");
				return config.server.host;
			}
			return url;
		} else {
			return config.server.host;
		}
	}

	public static function getServerPort():Int {
		#if sys
		return Std.parseInt(Sys.getEnv("SERVER_PORT"));
		#end

		if (Macros.isDefined("SERVER_PORT")) {
			var define = Macros.getDefine("SERVER_PORT");
			// our define comes back as <val>=<val>
			// Take the first half explicitly, as splitting on '=' might have unexpected
			// behavior if the token has '=' characters in it
			var port = define.substr(0, Std.int(define.length / 2));
			if (port.length <= 0) {
				trace("no valid analytics token found in API_KEY define, setting dev mode to true");
				return config.server.port;
			}
			return Std.parseInt(port);
		} else {
			return config.server.port;
		}
	}

	public static function getServerProtocol():String {
		#if sys
		return Sys.getEnv("SERVER_PROTOCOL");
		#end

		return "ws://";
	}
}
