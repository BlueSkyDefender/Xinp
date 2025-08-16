////----------------//
///**Ximp Gamepad**///
//----------------////

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Xinp Gamepad Test Shader
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// For Controller Debugging. 
// Author: Jose Negrete (BlueSkyDefender)  
// License: BSD-3-Clause  
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#include "2DSDFunctions.fxh"

uniform float DEADZONE_ADJUST <
    ui_type = "slider"; ui_min = 0.0; ui_max = 2.0;
	ui_label = " DeadZone Size";
	ui_tooltip = "DeadZone Scale 0 is no deadzone and 2 is 2X the deadzone.\n"
			     "1 is default microsoft recommended settings.";
	ui_category = "Pad Stuff";
> = 1.0;

uniform float Pad_Size <
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0;
	ui_label = " Pad Size";
	ui_tooltip = "Scale The pad to a size you like.\n"
			     "Scale game pad Bottom right.";
	ui_category = "Pad Stuff";
> = 0.5;

uniform bool Show_Pad <
	ui_label = " Show Pad";
	ui_tooltip = "Shows the game pad on screen.\n"
			     "Bottom Right.";
	ui_category = "Pad Stuff";
> = 1;

uniform bool FullScreen_Pad <
	ui_label = " FullScreen Pad";
	ui_tooltip = "Shows the game at Max Size on screen.\n"
			     "Center of the screen.";
	ui_category = "Pad Stuff";
> = 0;

uniform bool Show_Dots <
	ui_label = " Show Dots";
	ui_tooltip = "Shows the left and right dots for testing analog joy sticks.\n"
			     "Reload the shader when it's on to center them.";
	ui_category = "Joy Stuff";
> = 0;

uniform float DotRadiusPx <
    ui_type = "slider"; ui_min = 1.0; ui_max = 100.0;
    ui_label = "Dot Radius (px)";
	ui_category = "Joy Stuff";    
> = 25.0;

uniform float EdgeSoftPx <
    ui_type = "slider"; ui_min = 0.0; ui_max = 20.0;
    ui_label = "Edge Softness (px)";
	ui_category = "Joy Stuff";
> = 1.0;

uniform float Sensitivity <
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0;
    ui_label = "Stick Sensitivity";
	ui_category = "Joy Stuff";
> = 0.5;

uniform float4 DotColor_L <
ui_type = "color";
    ui_label = "Dot Color";
	ui_category = "Joy Stuff";
> = float4(1.0, 0.0, 0.0, 1.0);

uniform float4 DotColor_R <
ui_type = "color";
    ui_label = "Dot Color";
	ui_category = "Joy Stuff";
> = float4(0.0, 0.0, 1.0, 1.0);
//Controller Usage in Shader
//uniform float gamepad_toggle[20] < source = "gamepad_toggle"; >;
//uniform float gamepad_toggle_raw[20]    < source = "gamepad_raw";    >;
uniform float2 gamepad_toggle_raw[20]    < source = "gamepad_toggle_raw";>;//was added because of DX9

uniform int Frames < source = "framecount";>;
uniform float timer < source = "timer"; >;
/////////////////////////////////////////////D3D Starts Here/////////////////////////////////////////////////////////////////
texture BackBufferTex : COLOR;

sampler BackBuffer
	{
		Texture = BackBufferTex;
	};
//Pos
texture P_CDBuffer  { Width = 1; Height = 1; Format = RGBA32F;};

sampler PastBuffer
	{
		Texture = P_CDBuffer;
	};

texture C_CDBuffer  { Width = 1; Height = 1; Format = RGBA32F;};// MipLevels = 12;};

sampler CurrentBuffer
	{
		Texture = C_CDBuffer;
	};
//Time
texture P_TDBuffer  { Width = 1; Height = 1; Format = R32F;};

sampler PastTimeBuffer
	{
		Texture = P_TDBuffer;
	};

texture C_TDBuffer  { Width = 1; Height = 1; Format = R32F;};

sampler CurrentTimeBuffer
	{
		Texture = C_TDBuffer;
	};


texture W_Buffer  { Width = 1; Height = 1; Format = RGBA32F;};

sampler WakeBuffer
	{
		Texture = W_Buffer;
	};

texture B_Buffer  { Width = 64; Height = 64; Format = RGBA8;};

sampler BodyBuffer
	{
		Texture = B_Buffer;
		MagFilter = POINT;
		MinFilter = POINT;
		MipFilter = POINT;
	};


#define pix float2(BUFFER_RCP_WIDTH, BUFFER_RCP_HEIGHT)
#define rez float2(BUFFER_WIDTH, BUFFER_HEIGHT)
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

float HasElapsed(float targetSeconds)
{
    float startTime = tex2D(PastTimeBuffer, float2(0.5, 0.5)).x;
    float elapsedMs = timer - startTime;       // timer is in ms
    float targetMs = targetSeconds * 1000.0;   // convert seconds to ms
    return elapsedMs >= targetMs ? 1.0 : 0.0;
}

float DrawBody(float2 tc, float2 resolution)
{
    // Normalize TC to [-1,1], center at screen middle, maintain aspect ratio
    float2 p = (tc * resolution - 0.5 * resolution) / resolution.y;

    // Size
    float2 BodySize = float2(0.5, 0.25);
    float ArmSize = 0.5;
    float cornerRadius = 0.05;
    
	float2 off0 = float2(-0.125, 0);
	float2 off1 = float2(0.125, 0);
	float2 off2 = float2(0.5, -0.125);
	float2 off3 = float2(-0.5, -0.125);
    // Compute distance from point to rounded rectangle border
    float body0 = sdRoundedRect(p + off0, BodySize, cornerRadius);
    float body1 = sdRoundedRect(p + off1, BodySize, cornerRadius);  
    float arm0 = sdRoundedTriangle(p + off2, ArmSize);
    float arm1 = sdRoundedTriangle(p + off3, ArmSize);
	float combDist = (arm0 * arm1) + (body0 + body1);
    float thickness = 0.001;    
	//float S_cDist = fwidth(combDist);
	
    // Smooth edge for anti-aliasing but not sure if I need this when rendered at a lowr rez
    float alpha = smoothstep(thickness, -thickness, combDist);

	//float alpha = smoothstep(thickness, thickness-S_cDist, combDist);
 
    return lerp(0, 1, alpha);
}

float4 DrawButtons(float2 tc, float2 resolution)
{
    // Calculate aspect ratio
    float aspect = resolution.x / resolution.y;

    float2 p = (tc * resolution - 0.5 * resolution) / resolution.y;
    p.x *= aspect;

    // Button radius in UV units (adjust for aspect ratio)
    float btnRadius = 0.02;
    float feather = 0.001;

    // Positions relative to center of controller body (aspect corrected)
    float2 center = float2(0.5, 0.5);
    center = (center * resolution - 0.5 * resolution) / resolution.y;
    center.x *= aspect;
	float ABXY_off = 0.225;
	float ABXYS_off = -0.0125;
    // Button positions, aspect corrected
    float2 posA = center + float2( (ABXY_off + 0.05) * aspect, 0.0 + ABXYS_off);
    float2 posB = center + float2( (ABXY_off + 0.1) * aspect, -0.05 + ABXYS_off);
    float2 posX = center + float2( ABXY_off * aspect,  -0.05 + ABXYS_off);
    float2 posY = center + float2( (ABXY_off + 0.05) * aspect, -0.10 + ABXYS_off);
	//Start and Select
	float2 posStart = center + float2( -0.1 * aspect, -0.05 + ABXYS_off);
	float2 posSelect = center + float2( 0.1 * aspect, -0.05 + ABXYS_off);

    // Draw buttons with smooth circles
    float aAlpha = DrawCircle(p, posA, btnRadius, feather, aspect);
    float bAlpha = DrawCircle(p, posB, btnRadius, feather, aspect);
    float xAlpha = DrawCircle(p, posX, btnRadius, feather, aspect);
    float yAlpha = DrawCircle(p, posY, btnRadius, feather, aspect);
    float stAlpha = DrawCircle(p, posStart, btnRadius, feather, aspect);
    float seAlpha = DrawCircle(p, posSelect, btnRadius, feather, aspect);
    
    // Colors for each button
    float4 colorA = float4(0.0, 1.0, 0.0, 1.0);
    float4 colorB = float4(1.0, 0.0, 0.0, 1.0);
    float4 colorX = float4(0.0, 0.0, 1.0, 1.0);
    float4 colorY = float4(1.0, 1.0, 0.0, 1.0);
    float4 colorST = float4(0.25, 0.25, 0.25, 1.0);
    float4 colorSE = float4(0.25, 0.25, 0.25, 1.0);
	colorA.rgb = lerp(colorA.rgb,1,gamepad_toggle_raw[6].y);
	colorB.rgb = lerp(colorB.rgb,1,gamepad_toggle_raw[7].y);
	colorX.rgb = lerp(colorX.rgb,1,gamepad_toggle_raw[8].y);
	colorY.rgb = lerp(colorY.rgb,1,gamepad_toggle_raw[9].y);
	colorST.rgb = lerp(colorST.rgb,1,gamepad_toggle_raw[11].y);
	colorSE.rgb = lerp(colorSE.rgb,1,gamepad_toggle_raw[10].y);	
    float4 bgColor = float4(0, 0, 0, 1);
    float4 col = bgColor;
    col = lerp(col, colorA, aAlpha);
    col = lerp(col, colorB, bAlpha);
    col = lerp(col, colorX, xAlpha);
    col = lerp(col, colorY, yAlpha);
	col = lerp(col, colorST, stAlpha);
	col = lerp(col, colorSE, seAlpha);
	
    return col;
}

float4 JoyLeftRight(float2 tc, float2 resolution, bool Switch)
{
    //Joystick input
    float LRJoyX = -gamepad_toggle_raw[0].y * 0.025;
    float LRJoyY = gamepad_toggle_raw[1].y * 0.04;
	if(Switch)
	{
    	LRJoyX = -gamepad_toggle_raw[2].y * 0.025;
    	LRJoyY = gamepad_toggle_raw[3].y * 0.04;	
    }
    //Aspect ratio
    float aspect = resolution.x / resolution.y;

    //Deformation
    float2 dir = float2(LRJoyX, LRJoyY);
    float mag = length(dir);

    float2 pivot = 0.5; // default center pivot
    float2 tcTrans = tc;

    if (mag > 1e-5)
    {
        dir /= mag; // normalize joystick direction

        // Stretch factor along joystick
        float stretchAmount = 1.625; // exaggerate deformation
        float s_parallel = 1 + mag * stretchAmount;
        float s_perp = 1.0;

        // Rotation matrix to align with joystick
        float2x2 R = float2x2(dir.x, -dir.y,
                              dir.y,  dir.x);
        float2x2 S = float2x2(s_parallel, 0,
                              0,          s_perp);
        float2x2 M = mul(R, mul(S, transpose(R)));

        // Smooth pivot mapping: radiates evenly in all directions
        float2 joyDirNorm = normalize(float2(LRJoyX, LRJoyY) + 1e-6);
        pivot = float2(!Switch ? 0.375 : 0.625,0.5) - 0.5 * joyDirNorm;

        // Apply transformation
        tcTrans = mul(M, (tc - pivot)) + pivot;
    }
    
	float2 StoreTC = tc;
    tc = tcTrans;

    float2 p0 = (tc * resolution - 0.5 * resolution) / resolution.y;
    p0.x *= aspect;

    float2 p1 = (StoreTC * resolution - 0.5 * resolution) / resolution.y;
    p1.x *= aspect;


    float btnRadius = 0.055;
    float feather = 0.001;

    // Controller center in aspect-corrected space
    float2 center = float2(0.35, 0.4375);
    if(Switch)
    center = float2(0.6, 0.60);
    
    center = (center * resolution - 0.5 * resolution) / resolution.y;
    center.x *= aspect;

    // positions
    float2 posA = center + float2(0.0 * aspect, -0.0);

    // Draw Circle
    float aAlpha = DrawCircle(p0, posA, btnRadius-0.0025, feather, aspect);
    float bAlpha = DrawCircle(p1, posA, btnRadius+0.0025, feather, aspect);

    // Colors
    float4 colorA = float4(0.1, 0.1, 0.1, 1.0);
    float4 colorB = float4(0.05, 0.05, 0.05, 1.0);
    
    if(!Switch && gamepad_toggle_raw[16].y)
    	colorB.rgb = 1;
    	
    if(Switch && gamepad_toggle_raw[17].y)
    	colorB.rgb = 1;    
    	
    float4 col = float4(0, 0, 0, 1);
    	   col = lerp(col, colorB, bAlpha);
		   col = lerp(col, colorA, aAlpha);
		   
    return col;
}


float4 DrawDPad(float2 uv, float2 resolution)
{
    float aspect = resolution.x / resolution.y;

    // Move UV into aspect-corrected space centered at (0,0)
    float2 p = (uv - 0.5) * float2(aspect, 1.0);

    float armLength = 0.10;   // length along X and Y after aspect correction
    float thickness = 0.035;   // thickness of bars
    float feather = 0.001;
	float2 off0 = float2(-0.175, 0.10);

    // Since p is aspect-corrected, pass widths/heights unmodified
    float hBar = RoundedRectBar(p, off0, armLength, thickness, feather);
    float vBar = RoundedRectBar(p, off0, thickness, armLength, feather);
	float cBar = max(hBar, vBar);
	
	float3 Color = float3(0.1875,0.1875,0.1875);
	if(p.x > -0.156 && gamepad_toggle_raw[15].y)
		Color = 1;
	if(p.x < -0.194 && gamepad_toggle_raw[14].y)
		Color = 1;	
	if(p.y > 0.119 && gamepad_toggle_raw[13].y)
		Color = 1;
	if(p.y < 0.081 && gamepad_toggle_raw[12].y)
		Color = 1;	 
		
	return float4(Color,cBar);
}

float4 DrawLeftRightButton(float2 tc, float2 resolution)
{
    // Normalize TC to [-1,1], center at screen middle, maintain aspect ratio
    float2 p = (tc * resolution - 0.5 * resolution) / resolution.y;

    // Size
    float2 BodySize = float2(0.075, 0.0125);
    float cornerRadius = 0.001;
    
	float2 off0 = float2(-0.285, 0.235);
	float2 off1 = float2(0.285, 0.235);

    // Compute distance from point to rounded rectangle border
    float body0 = sdRoundedRect(p + off0, BodySize, cornerRadius);
    float body1 = sdRoundedRect(p + off1, BodySize, cornerRadius);  
	float combDist = body0 / body1;
    float thickness = 0.001;    
	
    // Smooth edge for anti-aliasing but not sure if I need this when rendered at a lowr rez
    float Alpha = smoothstep(thickness, -thickness, body0);
    float Beta = smoothstep(thickness, -thickness, body1);
    float Sten = Alpha + Beta;
    float3 Color = float3(0.125,0.125,0.125) * Sten;
    if(gamepad_toggle_raw[18].y && Beta)
    	Color = float3(1.0,1.0,1.0) * Sten;
    if(gamepad_toggle_raw[19].y && Alpha)
    	Color = float3(1.0,1.0,1.0) * Sten;    
    return float4(Color,Sten);
}

float4 DrawLeftRightTriggers(float2 tc, float2 resolution)
{
    // Normalize TC to [-1,1], center at screen middle, maintain aspect ratio
    float2 p = (tc * resolution - 0.5 * resolution) / resolution.y;

    // Size
    float2 BodySize = float2(0.01875, 0.0875);
    float cornerRadius = 0.001;
    
	float2 off0 = float2(-0.43125, 0.2125);
	float2 off1 = float2(0.43125, 0.2125);

    // Compute distance from point to rounded rectangle border
    float body0 = sdRoundedRect(p + off0, BodySize, cornerRadius);
    float body1 = sdRoundedRect(p + off1, BodySize, cornerRadius);  
	float combDist = body0 / body1;
    float thickness = 0.001;    
	
    // Smooth edge for anti-aliasing but not sure if I need this when rendered at a lowr rez
    float Alpha = smoothstep(thickness, -thickness, body0);
    float Beta = smoothstep(thickness, -thickness, body1);
    float Sten = Alpha + Beta;
    float3 Color = float3(0.125,0.125,0.125) * Sten;
    if(Beta)//gamepad_toggle_raw[4]
    	Color = p.y < -lerp(0.123,0.3,gamepad_toggle_raw[4].y) ? Color : float3(1.0,1.0,1.0);
    if(Alpha)//gamepad_toggle_raw[5]
    	Color = p.y < -lerp(0.123,0.3,gamepad_toggle_raw[5].y) ? Color : float3(1.0,1.0,1.0);    
    return float4(Color*Sten,Sten);
}

float4 Debug_Out(float4 position : SV_Position, float2 texcoord : TEXCOORD) : SV_Target
{

    float4 bg = tex2D(BackBuffer, texcoord);

    // Read stored position
    float2 dotPos_A = tex2D(CurrentBuffer, float2(0.5, 0.5)).xy;
    float2 dotPos_B = tex2D(CurrentBuffer, float2(0.5, 0.5)).zw;
    
    // Aspect-correct distance in pixels
    float2 dPx_A    = (texcoord - dotPos_A) * float2(BUFFER_WIDTH, BUFFER_HEIGHT);
    float  distPx_A = length(dPx_A);
    float2 dPx_B    = (texcoord - dotPos_B) * float2(BUFFER_WIDTH, BUFFER_HEIGHT);
    float  distPx_B = length(dPx_B);
    
    // Feathered circle
    float feather = max(EdgeSoftPx, 1e-3);
    float Alpha   = smoothstep(DotRadiusPx + feather, DotRadiusPx - feather, distPx_A);
	float Beta   = smoothstep(DotRadiusPx + feather, DotRadiusPx - feather, distPx_B);
	
    float4 Dot_A = lerp(bg, DotColor_L, Alpha * DotColor_L.a);
    float4 Dot_B = lerp(Dot_A, DotColor_R, Beta * DotColor_R.a);
    if(Show_Dots)
		bg = Dot_B;
	
	float2 Scale_Pad = lerp(float2(10,9),float2(2,1.175),Pad_Size);
	
	// Adjust UV space to focus on controller
	if(!FullScreen_Pad)
		texcoord = texcoord * Scale_Pad.x - Scale_Pad.y;
	
	//  BODY
	float4 bodyTex = tex2D(BodyBuffer, texcoord);
	float bodyMask = 1 - bodyTex.a; // Inverted alpha
	
	// Solid white if fully opaque, else faint grey
	float3 bodyColor = (bodyMask > 1.0) ? 1.0 : 0.035;

	//  BUTTONS
	float4 buttonShape = DrawButtons(texcoord, rez);
	buttonShape.a = dot(buttonShape.rgb, buttonShape.rgb); // Length^2 of color
	float4 buttons = lerp(0, buttonShape, buttonShape.a);  // Only visible if alpha > 0
	buttonShape.a = (buttonShape.a > 0);
	
	// The D-PAD
	float4 dpad = DrawDPad(texcoord, rez);
	dpad.a = (dpad.a > 0);
	
	//  JOYSTICKS
	float4 joyLeft = JoyLeftRight(texcoord, rez, 0);
	joyLeft.a = (joyLeft.x > 0);
	
	float4 joyRight = JoyLeftRight(texcoord, rez, 1);
	joyRight.a = (joyRight.x > 0);
	
	//  TRIGGERS & SIDE BUTTONS
	float4 sideButtons = DrawLeftRightButton(texcoord, rez);
	sideButtons.a = (sideButtons.a > 0);
	
	float4 triggers = DrawLeftRightTriggers(texcoord, rez);
	triggers.a = (triggers.a > 0);
	
	// Controller main shape, dimmed where body is but no input elements
	float4 controllerBase = lerp(
	    joyRight + joyLeft + dpad.a + buttonShape.a,
	    0.07,
	    bodyMask - buttonShape.a - dpad.a - joyLeft.a - joyRight.a
	);
	
	// Used for blending specific input overlays
	float sten      = buttonShape.a - joyLeft.a - joyRight.a;
	float newSten   = buttonShape.a + dpad.a + sideButtons.a + triggers.a + joyLeft.a + joyRight.a;
	
	float4 finalColor = lerp(controllerBase, buttonShape, sten);
	finalColor        = lerp(finalColor, dpad,           dpad.a);
	finalColor        = lerp(finalColor, sideButtons,    sideButtons.a);
	finalColor        = lerp(finalColor, triggers,       triggers.a);
	finalColor        = lerp(bg,         finalColor,     newSten);
	

	float4 bodyFinal = lerp(float4(bodyColor, 1), bg, bodyMask);
	
	return Show_Pad ? lerp(bodyFinal, finalColor, newSten) : bg;
}

void Past_Controller_Debug_PS(float4 position : SV_Position, float2 texcoord : TEXCOORD, out float4 Position : SV_Target0, out float Time : SV_Target1)
{    
	//Note if recursive ps are supported we could just feed the sampler into it self and skip the pass below.	
	float4 Info = tex2D(CurrentBuffer, float2(0.5, 0.5)).rgba;
    float2 currentPos_A = Info.xy;
	float2 currentPos_B = Info.zw;
	
    // Joystick movement (invert Y so up is up)
    float2 stick_A = float2(gamepad_toggle_raw[0].y, -gamepad_toggle_raw[1].y);
    float2 stick_B = float2(gamepad_toggle_raw[2].y, -gamepad_toggle_raw[3].y);
    
    // Sensitivity controls speed (in UV units per frame)
    currentPos_A += stick_A * (Sensitivity * 0.01); // tweak 0.01 to control speed
    currentPos_B += stick_B * (Sensitivity * 0.01); // tweak 0.01 to control speed
    
    // Clamp inside the screen
    currentPos_A = saturate(currentPos_A);
    currentPos_B = saturate(currentPos_B);
    
    // Save new position (store in RG)
    Position = float4(currentPos_A, currentPos_B);
    Time = tex2D(CurrentTimeBuffer, float2(0.5, 0.5)).x;
}

void Current_Controller_Debug_PS(float4 position : SV_Position, float2 texcoord : TEXCOORD, out float4 Position : SV_Target0, out float Time : SV_Target1)
{
	float wake = tex2D(WakeBuffer,float2(0.5, 0.5)).x;
	float4 stored = tex2D(PastBuffer, float2(0.5, 0.5)).xyzw;
	
	float time = tex2D(PastTimeBuffer, float2(0.5, 0.5)).x;
    float2 prevPos_A = stored.xy;
    float2 prevPos_B = stored.zw;
    
    float startTime = time;

    if (startTime < 0.001)
        startTime = timer; // initialize startTime on first frame
        
	// If this is the very first frame set it to center
	if (!wake)
	{
	    prevPos_A = float2(0.5, 0.5);
	    prevPos_B = float2(0.5, 0.5);
	}
	
    // Joystick movement (invert Y so up is up)
    float2 stick_A = float2(gamepad_toggle_raw[0].y, -gamepad_toggle_raw[1].y);
    float2 stick_B = float2(gamepad_toggle_raw[2].y, -gamepad_toggle_raw[3].y);
    
    // Sensitivity controls speed (in UV units per frame)
    prevPos_A += stick_A * (Sensitivity * 0.01); // tweak 0.01 to control speed
    prevPos_B += stick_B * (Sensitivity * 0.01); // tweak 0.01 to control speed
    
    // Clamp inside the screen
    prevPos_A = saturate(prevPos_A);
    prevPos_B = saturate(prevPos_B);
    
    // Save new position in RG
    Position = float4(prevPos_A, prevPos_B);
    Time = startTime;
}

void Wake_PS(float4 position : SV_Position, float2 texcoord : TEXCOORD, out float4 color : SV_Target0)
{
    color = HasElapsed(1);
}

void Body_PS(float4 position : SV_Position, float2 texcoord : TEXCOORD, out float4 color : SV_Target0)
{
	//DrawButtons(texcoord, rez).rgb
    color = float4(0,0,0,DrawBody(texcoord, rez).x);
}
///////////////////////////////////////////////////////////ReShade.fxh/////////////////////////////////////////////////////////////
// Vertex shader generating a triangle covering the entire screen
void PostProcessVS(in uint id : SV_VertexID, out float4 position : SV_Position, out float2 texcoord : TEXCOORD)
{
	texcoord.x = (id == 2) ? 2.0 : 0.0;
	texcoord.y = (id == 1) ? 2.0 : 0.0;
	position = float4(texcoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}
	technique WakeTime	< ui_label = "WakeSleepState";
	 hidden = true;
	 enabled = true;
	 timeout = 1250; >
	{
			pass W_CD
		{
			VertexShader = PostProcessVS;
			PixelShader = Wake_PS;
			RenderTarget = W_Buffer;
		}
			pass B_CD
		{
			VertexShader = PostProcessVS;
			PixelShader = Body_PS;
			RenderTarget = B_Buffer;
		}
	}
	
	technique Xinp_Gamepad_Debugger
	{
			pass P_CD
		{
			VertexShader = PostProcessVS;
			PixelShader = Past_Controller_Debug_PS;
			RenderTarget0 = P_CDBuffer;
			RenderTarget1 = P_TDBuffer;
		}
			pass C_CTD
		{
			VertexShader = PostProcessVS;
			PixelShader = Current_Controller_Debug_PS;
			RenderTarget0 = C_CDBuffer;
			RenderTarget1 = C_TDBuffer;
		}
			pass SimpleMipDemo
		{
			VertexShader = PostProcessVS;
			PixelShader = Debug_Out;
		}
	}


/*
    float4 bg = tex2D(BackBuffer, texcoord);

    // Left stick: X = [0], Y = [1]
    float2 stick = float2(gamepad_toggle_raw[0].y, -gamepad_toggle_raw[1].y); // invert Y so up is up
    float2 stickUV = stick * 0.5 + 0.5;                     // [-1,1] -> [0,1]

    // Center controller movements
    float2 center = float2(0.5, 0.5);
    float2 dotPos = center + (stickUV - 0.5) * Sensitivity;
    dotPos = saturate(dotPos);
    // Aspect Correct
    float2 res    = float2(BUFFER_WIDTH, BUFFER_HEIGHT);
    float2 dPx    = (texcoord - dotPos) * res;
    float  distPx = length(dPx);
    // Feathered circle
    float feather = max(EdgeSoftPx, 1e-3);
    float alpha   = smoothstep(DotRadiusPx + feather, DotRadiusPx - feather, distPx);
    //Mix
    return lerp(bg, DotColor, alpha * DotColor.a);
*/