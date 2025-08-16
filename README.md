````markdown
# Xinp Gamepad Add-on for ReShade

**Author:** Jose Negrete (BlueSkyDefender)  
**License:** BSD-3-Clause  

## Overview
The **Xinp** add-on passes both **raw** and **toggle** XInput gamepad states directly to ReShade shaders.  
This enables shaders to react to gamepad input without requiring custom input logic in the shader.

With the latest update, you can now access both raw and toggle states in a single `float2` array.

---

## Features
- **Raw Mode** – Real-time gamepad input values:
  - Buttons: `1.0` when pressed, `0.0` when not pressed.
  - Analog sticks: normalized to `[-1.0, 1.0]`.
  - Triggers: normalized to `[0.0, 1.0]`.

- **Toggle Mode** – Persistent ON/OFF button states:
  - Pressing a button flips its state.
  - Remains ON until pressed again.
  - Analog values are passed through unchanged.

- **Combined Mode** – Both toggle and raw in a single `float2`:
  - `.x` → toggle state  
  - `.y` → raw state

---

## Shader Integration

### Uniform Declarations

```hlsl
// Combined toggle + raw mode (recommended for DX9)
uniform float2 gamepad_toggle_raw[20] < source = "gamepad_toggle_raw"; >;

// Toggle mode (persistent ON/OFF for buttons)
uniform float gamepad_toggle[20] < source = "gamepad_toggle"; >;

// Raw mode (real-time state)
uniform float gamepad_raw[20] < source = "gamepad_raw"; >;

// Deadzone adjustment slider
uniform float DEADZONE_ADJUST <
	ui_type = "slider"; ui_min = 0.0; ui_max = 2.0;
	ui_label = " DeadZone Size";
	ui_tooltip = "DeadZone Scale 0 is no deadzone and 2 is 2X the deadzone.\n"
				 "1 is default Microsoft recommended settings.";
	ui_category = "Pad Stuff";
> = 1.0;
````

---

## Index Mapping

| Index | Control        | Type   | Range      |
| ----- | -------------- | ------ | ---------- |
| 0     | LX             | Analog | -1.0 → 1.0 |
| 1     | LY             | Analog | -1.0 → 1.0 |
| 2     | RX             | Analog | -1.0 → 1.0 |
| 3     | RY             | Analog | -1.0 → 1.0 |
| 4     | LT             | Analog | 0.0 → 1.0  |
| 5     | RT             | Analog | 0.0 → 1.0  |
| 6     | A              | Button | 0.0 / 1.0  |
| 7     | B              | Button | 0.0 / 1.0  |
| 8     | X              | Button | 0.0 / 1.0  |
| 9     | Y              | Button | 0.0 / 1.0  |
| 10    | Start          | Button | 0.0 / 1.0  |
| 11    | Back           | Button | 0.0 / 1.0  |
| 12    | DPad Up        | Button | 0.0 / 1.0  |
| 13    | DPad Down      | Button | 0.0 / 1.0  |
| 14    | DPad Left      | Button | 0.0 / 1.0  |
| 15    | DPad Right     | Button | 0.0 / 1.0  |
| 16    | Left Thumb     | Button | 0.0 / 1.0  |
| 17    | Right Thumb    | Button | 0.0 / 1.0  |
| 18    | Left Shoulder  | Button | 0.0 / 1.0  |
| 19    | Right Shoulder | Button | 0.0 / 1.0  |

---

## Examples

**Toggle A Button ON/OFF**

```hlsl
if (gamepad_toggle_raw[6].x > 0.5)
{
    // A button toggle is ON
}
```

**Check if A Button is Held Down**

```hlsl
if (gamepad_toggle_raw[6].y > 0.5)
{
    // A button is currently pressed
}
```

**Use Left Stick for Movement**

```hlsl
float2 movement = float2(gamepad_toggle_raw[0].y, gamepad_toggle_raw[1].y);
// movement.x = horizontal (-1.0 left, 1.0 right)
// movement.y = vertical (-1.0 down, 1.0 up)
```

**Trigger-based Effect Strength**

```hlsl
float effect_strength = gamepad_toggle_raw[5].y; // RT trigger
// Range: 0.0 (released) to 1.0 (fully pressed)
```

---

## Notes

* Requires an **XInput-compatible controller** (Xbox 360, Xbox One, Xbox Series X|S, or equivalent).
* Only the **first connected controller** (index 0) is polled.
* Windows only.
* `gamepad_toggle_raw` is recommended for new shaders, but `gamepad_toggle` and `gamepad_raw` still work for backward compatibility.

