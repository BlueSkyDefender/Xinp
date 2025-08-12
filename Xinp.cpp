/*
 * Copyright (C) 2025 Depth3D - Jose Negrete AKA BlueSkyDefender
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <Windows.h>
#include <Xinput.h>
#include <reshade.hpp>
#include <cstring>
//Xinput is only available on Windows, so we can use the Windows API directly
#pragma comment(lib, "Xinput.lib")
// Order: LX, LY, RX, RY, LT, RT, A, B, X, Y, Start, Back, DPadU, DPadD, DPadL, DPadR, LThumb, RThumb, LShoulder, RShoulder
#define OUT_COUNT 20
// Number of outputs we want to provide to shaders
static bool toggle_states[OUT_COUNT] = {};
static bool previous_pressed[OUT_COUNT] = {};

// Store latest states so both arrays can be set for toggle and raw values
static float latest_toggle[OUT_COUNT] = {};
static float latest_raw[OUT_COUNT] = {};

static void get_gamepad_state(float out[OUT_COUNT])
{
	for (int i = 0; i < OUT_COUNT; ++i)
		out[i] = 0.0f;

	XINPUT_STATE state = {};
	if (XInputGetState(0, &state) != ERROR_SUCCESS)
		return; // No controller connected

	// Joysticks - No toggle states for analog sticks, just raw values
	out[0] = state.Gamepad.sThumbLX / 32767.0f;
	out[1] = state.Gamepad.sThumbLY / 32767.0f;
	out[2] = state.Gamepad.sThumbRX / 32767.0f;
	out[3] = state.Gamepad.sThumbRY / 32767.0f;

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
}

static void update_gamepad_states()
{
	float raw[OUT_COUNT] = {};
	get_gamepad_state(raw);

	for (int i = 0; i < OUT_COUNT; ++i)
	{   // Treat triggers (indices 4 and 5) and all buttons (index >= 6) as toggle candidates
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

static void on_begin_effects(reshade::api::effect_runtime *runtime, reshade::api::command_list *, reshade::api::resource_view, reshade::api::resource_view)
{
	update_gamepad_states();

	runtime->enumerate_uniform_variables(nullptr, [](reshade::api::effect_runtime *rt, reshade::api::effect_uniform_variable var)
	{
		char source[32] = {};
		if (rt->get_annotation_string_from_uniform_variable(var, "source", source))
		{
			if (strcmp(source, "gamepad_toggle") == 0)
			{
				rt->set_uniform_value_float(var, latest_toggle, OUT_COUNT);
			}
			else if (strcmp(source, "gamepad_raw") == 0)
			{
				rt->set_uniform_value_float(var, latest_raw, OUT_COUNT);
			}
		}
	});
}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID)
{
	if (reason == DLL_PROCESS_ATTACH)
	{
		if (!reshade::register_addon(hModule))
			return FALSE;
		reshade::register_event<reshade::addon_event::reshade_begin_effects>(on_begin_effects);
	}
	else if (reason == DLL_PROCESS_DETACH)
	{
		reshade::unregister_addon(hModule);
	}

	return TRUE;
}

extern "C" __declspec(dllexport) const char *NAME = "Xinp";
extern "C" __declspec(dllexport) const char *DESCRIPTION = "This Xinput Gamepad Addon passes both raw and toggle gamepad states to shaders.";

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
*/
