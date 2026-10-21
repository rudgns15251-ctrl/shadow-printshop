shader_type canvas_item;
// Night printshop atmosphere between the scene art and the UI: vignette toward
// the dark room, fine paper grain, and a cold fluorescent band at the top that
// very rarely dips. Time terms are wrapped so the hash keeps float precision. `motion` scales every time-based change; reduced motion sets 0.

uniform float motion : hint_range(0.0, 1.0) = 1.0;
// The fluorescent tube is switched off after midnight; 0 removes its cold band.
uniform float tube : hint_range(0.0, 1.0) = 1.0;
uniform float vignette : hint_range(0.0, 1.0) = 0.55;
uniform float grain : hint_range(0.0, 0.2) = 0.035;
uniform vec4 cold_light : source_color = vec4(0.85, 0.91, 0.93, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME * motion;
	// Mostly steady tube; about 1.5% of 1/12 s steps dim slightly (never strobing).
	float dip = motion * 0.35 * step(0.985, hash(vec2(mod(floor(t * 12.0), 997.0), 7.3)));
	float band = smoothstep(0.30, 0.0, uv.y) * 0.10 * (1.0 - dip) * tube;
	float edge = smoothstep(0.38, 0.98, distance(uv, vec2(0.5, 0.58))) * vignette;
	float noise = (hash(floor(FRAGCOORD.xy) + mod(floor(t * 18.0), 61.0) * 13.0) - 0.5) * grain;
	vec3 dark = vec3(0.035, 0.03, 0.03);
	float alpha = clamp(edge + band + abs(noise), 0.0, 0.8);
	vec3 color = mix(dark, cold_light.rgb, band / max(alpha, 0.0001));
	COLOR = vec4(color + noise, alpha);
}
