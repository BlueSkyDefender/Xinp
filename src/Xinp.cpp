/*
 * Copyright (C) 2025 Depth3D - Jose Negrete AKA BlueSkyDefender
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <Windows.h>
#include <Xinput.h>
#include <reshade.hpp>
#include <cstring>
#include <cmath>
#pragma comment(lib, "Xinput.lib")
 // Order: LX, LY, RX, RY, LT, RT, A, B, X, Y, Start, Back, DPadU, DPadD, DPadL, DPadR, LThumb, RThumb, LShoulder, RShoulder, Guide, Combo_Back+LT, Combo_Back+LB, Combo_Back+RT, Combo_Back+RB
#define OUT_COUNT 25
// Number of outputs we want to provide to shaders

// Guide button is not part of the public XInput API
#define XINPUT_GAMEPAD_GUIDE 0x0400

// Combo toggle hold duration in seconds
static constexpr double COMBO_HOLD_DURATION = 1.0;

// Combo toggle definitions (pairs of raw[] indices)
#define COMBO_COUNT 4
struct ComboToggle
{
	int index_a;       // First button raw[] index
	int index_b;       // Second button raw[] index
	bool toggle_state; // Current latched toggle
	bool is_held;      // Combo is currently being held
	bool has_toggled;  // Already toggled during this hold (prevent re-fire)
	LARGE_INTEGER hold_start; // QPC timestamp when hold began
};

// Back(11) + LT(4), Back(11) + LShoulder(18), Back(11) + RT(5), Back(11) + RShoulder(19)
static ComboToggle combos[COMBO_COUNT] = {
	{ 11, 4,  false, false, false, {} },
	{ 11, 18, false, false, false, {} },
	{ 11, 5,  false, false, false, {} },
	{ 11, 19, false, false, false, {} },
};

static LARGE_INTEGER qpc_frequency = {};

static bool toggle_states[OUT_COUNT] = {};
static bool previous_pressed[OUT_COUNT] = {};

// Store latest states so both arrays can be set for toggle and raw values
static float latest_toggle[OUT_COUNT] = {};
static float latest_raw[OUT_COUNT] = {};

// Default Microsoft Xbox deadzone
static constexpr float DEFAULT_DEADZONE = 7849.0f;
static float DEADZONE_ADJUST = 1.0f; // Slider default (100% at default deadzone)

// Undocumented XInputGetStateEx (ordinal 100) — includes Guide button
typedef DWORD(WINAPI *XInputGetStateEx_t)(DWORD dwUserIndex, XINPUT_STATE *pState);
static XInputGetStateEx_t XInputGetStateEx_fn = nullptr;

// Kingeric1992 told me to add this function to apply deadzone to the sticks.
// https://learn.microsoft.com/en-us/windows/win32/xinput/getting-started-with-xinput
static void apply_stick_deadzone(float LX, float LY, float deadzone, float max, float &outX, float &outY)
{
	float magnitude = sqrt(LX * LX + LY * LY);
	if (magnitude > deadzone)
	{
		if (magnitude > max) magnitude = max;

		magnitude -= deadzone;
		float normalizedMagnitude = magnitude / (max - deadzone);

		float vectorLength = sqrt(LX * LX + LY * LY);
		outX = (LX / vectorLength) * normalizedMagnitude;
		outY = (LY / vectorLength) * normalizedMagnitude;
	}
	else
	{
		outX = 0.0f;
		outY = 0.0f;
	}
}

static void get_gamepad_state(float out[OUT_COUNT])
{
	for (int i = 0; i < OUT_COUNT; ++i)
		out[i] = 0.0f;

	XINPUT_STATE state = {};

	// Try undocumented XInputGetStateEx first for Guide button support, fall back to XInputGetState
	DWORD result;
	if (XInputGetStateEx_fn)
		result = XInputGetStateEx_fn(0, &state);
	else
		result = XInputGetState(0, &state);

	if (result != ERROR_SUCCESS)
		return; // No controller connected

	// Microsoft default for Xbox controller
	constexpr float MAX_STICK = 32767.0f;
	float scaled_deadzone = DEADZONE_ADJUST * DEFAULT_DEADZONE;

	// Apply deadzone Left
	apply_stick_deadzone(
		static_cast<float>(state.Gamepad.sThumbLX),
		static_cast<float>(state.Gamepad.sThumbLY),
		scaled_deadzone, MAX_STICK,
		out[0], out[1]
	);
	// Apply deadzone Right
	apply_stick_deadzone(
		static_cast<float>(state.Gamepad.sThumbRX),
		static_cast<float>(state.Gamepad.sThumbRY),
		scaled_deadzone, MAX_STICK,
		out[2], out[3]
	);

	// Triggers
	out[4] = state.Gamepad.bLeftTrigger / 255.0f;
	out[5] = state.Gamepad.bRightTrigger / 255.0f;

	// Buttons
	WORD b = state.Gamepad.wButtons;
	out[6] = (b & XINPUT_GAMEPAD_A) ? 1.0f : 0.0f;
	out[7] = (b & XINPUT_GAMEPAD_B) ? 1.0f : 0.0f;
	out[8] = (b & XINPUT_GAMEPAD_X) ? 1.0f : 0.0f;
	out[9] = (b & XINPUT_GAMEPAD_Y) ? 1.0f : 0.0f;
	out[10] = (b & XINPUT_GAMEPAD_START) ? 1.0f : 0.0f;
	out[11] = (b & XINPUT_GAMEPAD_BACK) ? 1.0f : 0.0f;
	out[12] = (b & XINPUT_GAMEPAD_DPAD_UP) ? 1.0f : 0.0f;
	out[13] = (b & XINPUT_GAMEPAD_DPAD_DOWN) ? 1.0f : 0.0f;
	out[14] = (b & XINPUT_GAMEPAD_DPAD_LEFT) ? 1.0f : 0.0f;
	out[15] = (b & XINPUT_GAMEPAD_DPAD_RIGHT) ? 1.0f : 0.0f;
	out[16] = (b & XINPUT_GAMEPAD_LEFT_THUMB) ? 1.0f : 0.0f;
	out[17] = (b & XINPUT_GAMEPAD_RIGHT_THUMB) ? 1.0f : 0.0f;
	out[18] = (b & XINPUT_GAMEPAD_LEFT_SHOULDER) ? 1.0f : 0.0f;
	out[19] = (b & XINPUT_GAMEPAD_RIGHT_SHOULDER) ? 1.0f : 0.0f;
	out[20] = (b & XINPUT_GAMEPAD_GUIDE) ? 1.0f : 0.0f;
	// Indices 21-24 are combo toggles, handled separately in update_combo_toggles()
}

static void update_combo_toggles(const float raw[OUT_COUNT])
{
	LARGE_INTEGER now;
	QueryPerformanceCounter(&now);

	for (int i = 0; i < COMBO_COUNT; ++i)
	{
		ComboToggle &combo = combos[i];
		// Both buttons must be pressed (using same 0.1 threshold as single toggles)
		bool both_pressed = (raw[combo.index_a] > 0.1f) && (raw[combo.index_b] > 0.1f);

		if (both_pressed)
		{
			if (!combo.is_held)
			{
				// Combo just started being held
				combo.is_held = true;
				combo.has_toggled = false;
				combo.hold_start = now;
			}
			else if (!combo.has_toggled)
			{
				// Check if held long enough
				double elapsed = static_cast<double>(now.QuadPart - combo.hold_start.QuadPart) / static_cast<double>(qpc_frequency.QuadPart);
				if (elapsed >= COMBO_HOLD_DURATION)
				{
					combo.toggle_state = !combo.toggle_state;
					combo.has_toggled = true; // Don't toggle again until released and re-held
				}
			}
		}
		else
		{
			// Released — reset hold tracking
			combo.is_held = false;
			combo.has_toggled = false;
		}
	}
}

static void update_gamepad_states()
{
	float raw[OUT_COUNT] = {};
	get_gamepad_state(raw);

	// Process combo toggles before writing outputs
	update_combo_toggles(raw);

	for (int i = 0; i < OUT_COUNT; ++i)
	{
		// Combo toggle outputs (21-24) are toggle-only, no raw equivalent
		if (i >= 21)
		{
			latest_raw[i] = combos[i - 21].toggle_state ? 1.0f : 0.0f;
			latest_toggle[i] = latest_raw[i];
			continue;
		}

		// Treat triggers (indices 4 and 5) and all buttons (index >= 6) as toggle candidates
		bool currently_pressed = (i >= 4 && raw[i] > 0.1f);// Threshold to consider a button pressed and Triggers pressed at 10% May need to make this adjustable.

		if (currently_pressed && !previous_pressed[i])
		{
			toggle_states[i] = !toggle_states[i];
		}
		previous_pressed[i] = currently_pressed;

		// Sticks: raw analog values for both raw and toggle arrays
		if (i < 4)
		{
			latest_raw[i] = raw[i];
			latest_toggle[i] = raw[i];
		}
		else
		{
			// Triggers and buttons: raw is direct analog/press state, toggle is latched bool
			latest_raw[i] = raw[i];
			latest_toggle[i] = toggle_states[i] ? 1.0f : 0.0f;
		}
	}
}

// Attempt to read DEADZONE_ADJUST from shader added this because to make it easier to adjust deadzone for the users.
// https://reshade.me/forum/addons-discussion/9962-how-to-expose-addon-data-as-global-uniforms-for-all-shaders
static void read_deadzone_from_shader(reshade::api::effect_runtime *runtime)
{
	// Default first
	DEADZONE_ADJUST = 1.0f;

	// Enumerrate all uniforms and find DEADZONE_ADJUST by name
	runtime->enumerate_uniform_variables(nullptr, [](reshade::api::effect_runtime *rt, reshade::api::effect_uniform_variable var, void *user_data)
	{
		float *deadzone_ptr = reinterpret_cast<float *>(user_data);

		char name[128] = {};
		rt->get_uniform_variable_name(var, name);

		if (std::strcmp(name, "DEADZONE_ADJUST") == 0)
		{
			// Read the current shader value
			float value = *deadzone_ptr; // default if reading flails
			rt->get_uniform_value_float(var, &value, 1);
			*deadzone_ptr = value;
		}
	}, &DEADZONE_ADJUST);
}

static void on_begin_effects(reshade::api::effect_runtime *runtime, reshade::api::command_list *, reshade::api::resource_view, reshade::api::resource_view)
{
	// Read DEADZONE_ADJUST from shader (or use default if not present)
	read_deadzone_from_shader(runtime);

	// Update gamepad states using the slider value
	update_gamepad_states();

	// Write raw/toggle values back to shader as usual
	runtime->enumerate_uniform_variables(nullptr, [](reshade::api::effect_runtime *rt, reshade::api::effect_uniform_variable var)
	{
		char name[128] = {};
		rt->get_uniform_variable_name(var, name);
		// Keeping this so that shader that use the older method sitllworks.
		if (std::strcmp(name, "gamepad_toggle") == 0)
			rt->set_uniform_value_float(var, latest_toggle, OUT_COUNT);
		else if (std::strcmp(name, "gamepad_raw") == 0)
			rt->set_uniform_value_float(var, latest_raw, OUT_COUNT);
		else if (std::strcmp(name, "gamepad_toggle_raw") == 0)//This is for compatibility with DX9 that complain about using too many tempregisters.
		{
			// Pack toggle/raw into float2 array
			float combined[OUT_COUNT * 2] = {};
			for (int i = 0; i < OUT_COUNT; ++i)
			{
				combined[i * 2 + 0] = latest_toggle[i]; // x = toggle
				combined[i * 2 + 1] = latest_raw[i];    // y = raw
			}
			rt->set_uniform_value_float(var, combined, OUT_COUNT * 2);
		}
	});
}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID)
{
	if (reason == DLL_PROCESS_ATTACH)
	{
		if (!reshade::register_addon(hModule))
			return FALSE;

		// Cache QPC frequency for combo hold timing
		QueryPerformanceFrequency(&qpc_frequency);

		// Try to load XInputGetStateEx (ordinal 100) for Guide button support
		HMODULE xinput = LoadLibraryA("xinput1_4.dll");
		if (!xinput)
			xinput = LoadLibraryA("xinput1_3.dll");
		if (xinput)
			XInputGetStateEx_fn = reinterpret_cast<XInputGetStateEx_t>(GetProcAddress(xinput, MAKEINTRESOURCEA(100)));

		reshade::register_event<reshade::addon_event::reshade_begin_effects>(on_begin_effects);
	}
	else if (reason == DLL_PROCESS_DETACH)
	{
		reshade::unregister_addon(hModule);
	}

	return TRUE;
}

extern "C" __declspec(dllexport) const char *NAME = "Xinp Gamepad";
extern "C" __declspec(dllexport) const char *DESCRIPTION = "This Xinput Gamepad Addon passes both raw and toggle gamepad states to shaders.";
extern "C" __declspec(dllexport) const char *AUTHOR = "Depth3D - Jose Negrete";
extern "C" __declspec(dllexport) const char *VERSION = "1.0.5";

/*
Usage in shader:

uniform float gamepad_toggle[20] < source = "gamepad_toggle"; >;
uniform float gamepad_raw[20]    < source = "gamepad_raw";    >;

// Example:
// Check toggle state of A button:
if (gamepad_toggle[6] > 0.5)
{
	// A button toggle is ON
}

// Check if A button is currently held down:
if (gamepad_raw[6] > 0.5)
{
	// A button is held down
}

uniform float DEADZONE_ADJUST <
	ui_type = "slider"; ui_min = 0.0; ui_max = 2.0;
	ui_label = " DeadZone Size";
	ui_tooltip = "DeadZone Scale 0 is no deadzone and 2 is 2X the deadzone.\n"
				 "1 is default microsoft recommended settings.";
	ui_category = "Pad Stuff";
> = 1.0;
*/
