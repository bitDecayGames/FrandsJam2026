package shaders;

import flixel.system.FlxAssets.FlxShader;

/**
 * Environment color grade for time of day, applied as a camera filter.
 * Noon (12:00) is identity — tint (1,1,1), no darkening, no desaturation.
 *
 * Hues are based on photographic color temperature and film "day-for-night" grading.
 * Morning and evening are deliberately distinct: morning air is clearer, so its light
 * is a soft pale yellow; evening light passes through more haze/dust, so it's a
 * deeper orange-red.
 * - Morning (~4000K, clear air): soft yellow (1.0, 0.93, 0.72)
 * - Noon daylight (~5500K): neutral
 * - Afternoon (~4500K): soft warm (1.0, 0.93, 0.84)
 * - Evening sunset (~2200K, hazy): orange-red (1.0, 0.62, 0.38)
 * - Dusk "blue hour": purple-blue, dimmed
 * - Night (moonlight): blue shift (0.55, 0.65, 1.0), ~60% brightness, desaturated
**/
class TimeOfDayShader extends FlxShader {
	@:glFragmentSource('
		#pragma header

		uniform vec3 uTint;
		uniform float uDarken;
		uniform float uDesat;
		uniform vec2 uLightPos; // candle center, camera-buffer pixels
		uniform float uLightRadius;
		uniform float uLightStrength; // 0 = day (no candle), 1 = full night candle
		uniform float uNightVision; // 0..1 — grainy green goggle overlay (night only)
		uniform float uTime; // drives the grain animation
		// Item/dog guide glows: xy = pos px, z = radius, w = strength.
		// NOTE: unrolled into 16 scalar uniforms — OpenFL does not parse array uniforms.
		uniform vec4 uGlow0; uniform vec4 uGlow1; uniform vec4 uGlow2; uniform vec4 uGlow3;
		uniform vec4 uGlow4; uniform vec4 uGlow5; uniform vec4 uGlow6; uniform vec4 uGlow7;
		uniform vec4 uGlow8; uniform vec4 uGlow9; uniform vec4 uGlow10; uniform vec4 uGlow11;
		uniform vec4 uGlow12; uniform vec4 uGlow13; uniform vec4 uGlow14; uniform vec4 uGlow15;

		float glowAt(vec4 g, vec2 px) {
			if (g.w <= 0.0) { return 0.0; }
			// same falloff profile as the player candle: flat bright core to 35%, then fade
			return (1.0 - smoothstep(g.z * 0.35, g.z, distance(px, g.xy))) * g.w;
		}

		void main() {
			vec4 color = flixel_texture2D(bitmap, openfl_TextureCoordv);
			float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
			vec3 graded = mix(color.rgb, vec3(gray), uDesat);
			graded *= uTint * uDarken;

			vec2 px = openfl_TextureCoordv * openfl_TextureSize;

			if (uLightStrength > 0.0) {
				// Union all light sources with a screen blend (multiply the darknesses).
				// Unlike max(), this is smooth in both value AND gradient, so the candle
				// and item glows melt into one pool with no ridge where they overlap.
				// factors clamped to >= 0 so strengths above 1.0 (extra-bright sources
				// like rockets) widen the fully-lit core without breaking the blend
				float darkness = smoothstep(uLightRadius * 0.35, uLightRadius, distance(px, uLightPos));
				darkness *= max(0.0, 1.0 - glowAt(uGlow0, px)); darkness *= max(0.0, 1.0 - glowAt(uGlow1, px));
				darkness *= max(0.0, 1.0 - glowAt(uGlow2, px)); darkness *= max(0.0, 1.0 - glowAt(uGlow3, px));
				darkness *= max(0.0, 1.0 - glowAt(uGlow4, px)); darkness *= max(0.0, 1.0 - glowAt(uGlow5, px));
				darkness *= max(0.0, 1.0 - glowAt(uGlow6, px)); darkness *= max(0.0, 1.0 - glowAt(uGlow7, px));
				darkness *= max(0.0, 1.0 - glowAt(uGlow8, px)); darkness *= max(0.0, 1.0 - glowAt(uGlow9, px));
				darkness *= max(0.0, 1.0 - glowAt(uGlow10, px)); darkness *= max(0.0, 1.0 - glowAt(uGlow11, px));
				darkness *= max(0.0, 1.0 - glowAt(uGlow12, px)); darkness *= max(0.0, 1.0 - glowAt(uGlow13, px));
				darkness *= max(0.0, 1.0 - glowAt(uGlow14, px)); darkness *= max(0.0, 1.0 - glowAt(uGlow15, px));
				// per-glow strength lives in each uniform w (items faint, burning trees full blaze)
				float light = (1.0 - darkness) * uLightStrength;

				// Deep amber firelight (~1900K), dimming toward the rim
				vec3 warm = color.rgb * vec3(1.0, 0.76, 0.42);
				warm *= 0.55 + 0.45 * light;
				graded = mix(graded, warm, light);
			}

			// Night vision goggles — amplified luminance pushed to green + animated grain.
			// NOT scaled by uLightStrength: the client factor owns on/off timing so the
			// green can linger briefly over daylight before "clicking" off.
			if (uNightVision > 0.0) {
				float lum = dot(graded, vec3(0.299, 0.587, 0.114));
				// soft-knee rolloff: dark areas still get amplified, but the bright
				// candle core compresses instead of blooming painfully
				float amp = lum * 1.8 + 0.05;
				amp = amp / (1.0 + 0.75 * amp);
				float grain = fract(sin(dot(px + vec2(uTime * 37.0, uTime * 61.0), vec2(12.9898, 78.233))) * 43758.5453);
				vec3 nv = vec3(0.15, 1.0, 0.25) * amp + vec3((grain - 0.5) * 0.15);
				graded = mix(graded, nv, uNightVision);
			}

			gl_FragColor = vec4(graded, color.a);
		}
	')
	/** How strong the night lights currently are (0 = daytime). Set by applyHour. */
	public var lightStrength(default, null):Float = 0;

	public function new() {
		super();
		data.uLightPos.value = [0.0, 0.0];
		data.uLightRadius.value = [120.0];
		data.uNightVision.value = [0.0];
		data.uTime.value = [0.0];
		setGlows([]);
		applyHour(12.0);
	}

	/** Night vision goggle overlay: factor 0..1, time drives the grain animation. */
	public function setNightVision(factor:Float, time:Float) {
		data.uNightVision.value = [factor];
		data.uTime.value = [time];
	}

	/** Move the candle light (camera-space pixels). Radius jiggle = flicker. */
	public function setLight(x:Float, y:Float, radius:Float) {
		data.uLightPos.value = [x, y];
		data.uLightRadius.value = [radius];
	}

	/** Set item glow spots: flat [x, y, radius, strength] per glow, up to 16. Unused slots zeroed. */
	public function setGlows(flat:Array<Float>) {
		for (i in 0...16) {
			var o = i * 4;
			var param:Dynamic = Reflect.field(data, 'uGlow$i');
			if (o + 3 < flat.length) {
				param.value = [flat[o], flat[o + 1], flat[o + 2], flat[o + 3]];
			} else {
				param.value = [0.0, 0.0, 0.0, 0.0];
			}
		}
	}

	// Keyframes across the 24h clock — piecewise-linear interpolation between them.
	// Night is nearly black on purpose — the candle glow is your main light source.
	static var KEYS:Array<{h:Float, r:Float, g:Float, b:Float, dark:Float, desat:Float}> = [
		{h: 0.0, r: 0.45, g: 0.55, b: 1.00, dark: 0.00, desat: 0.45}, // midnight — pitch black
		{h: 4.5, r: 0.45, g: 0.55, b: 1.00, dark: 0.00, desat: 0.45}, // pre-dawn
		{h: 6.0, r: 0.85, g: 0.70, b: 0.85, dark: 0.60, desat: 0.15}, // dawn — pink-purple blue hour
		{h: 7.5, r: 1.00, g: 0.93, b: 0.72, dark: 0.97, desat: 0.00}, // morning — soft clear yellow (~4000K)
		{h: 10.0, r: 1.00, g: 0.97, b: 0.90, dark: 1.00, desat: 0.00}, // late morning
		{h: 12.0, r: 1.00, g: 1.00, b: 1.00, dark: 1.00, desat: 0.00}, // noon — neutral
		{h: 14.0, r: 1.00, g: 1.00, b: 1.00, dark: 1.00, desat: 0.00}, // early afternoon
		{h: 16.5, r: 1.00, g: 0.93, b: 0.84, dark: 0.98, desat: 0.00}, // afternoon (~4500K)
		{h: 19.0, r: 1.00, g: 0.62, b: 0.38, dark: 0.88, desat: 0.00}, // evening sunset — orange-red (~2200K)
		{h: 20.5, r: 0.65, g: 0.52, b: 0.85, dark: 0.42, desat: 0.25}, // dusk — blue hour
		{h: 22.0, r: 0.45, g: 0.55, b: 1.00, dark: 0.00, desat: 0.45}, // night
		{h: 24.0, r: 0.45, g: 0.55, b: 1.00, dark: 0.00, desat: 0.45}
	];

	/** Set the grade uniforms for the given hour (0-24). */
	public function applyHour(hour:Float) {
		hour = ((hour % 24) + 24) % 24;
		var a = KEYS[0];
		var b = KEYS[KEYS.length - 1];
		for (i in 0...KEYS.length - 1) {
			if (hour >= KEYS[i].h && hour <= KEYS[i + 1].h) {
				a = KEYS[i];
				b = KEYS[i + 1];
				break;
			}
		}
		var span = b.h - a.h;
		var f = span > 0 ? (hour - a.h) / span : 0.0;
		var dark = lerp(a.dark, b.dark, f);
		data.uTint.value = [lerp(a.r, b.r, f), lerp(a.g, b.g, f), lerp(a.b, b.b, f)];
		data.uDarken.value = [dark];
		data.uDesat.value = [lerp(a.desat, b.desat, f)];
		// Candle fades in as the world gets dark (dusk onward), full strength at night
		var strength = (0.7 - dark) / 0.4;
		if (strength < 0) { strength = 0; }
		if (strength > 1) { strength = 1; }
		lightStrength = strength;
		data.uLightStrength.value = [strength];
	}

	static inline function lerp(x:Float, y:Float, f:Float):Float {
		return x + (y - x) * f;
	}
}
