// The MIT License (MIT)

// Copyright © 2020 Inigo Quilez

// Permission is hereby granted, free of charge, to any person obtaining a copy of this
// software and associated documentation files (the “Software”), to deal in the Software
// without restriction, including without limitation the rights to use, copy, modify,
// merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to the following
// conditions:

// The above copyright notice and this permission notice shall be included in all copies
// or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
// INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
// PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
// CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE
// OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

// Reference: IQ's "2D Signed Distance Functions" https://iquilezles.org/articles/distfunctions2d/ No licence at the website but there is a MIT licence on the Shadertoy.
// Not sure how the licence is ment to be used in this case and I am not using the direct code from shadertoy. But, I still placed at the top.
// IQ's Code was only used for the 2D Objects and was also modfied to fit my use case.

float DrawCircle(float2 p, float2 center, float radius, float feather, float aspect)
{
    float2 diff = p - center;
    diff.x /= aspect;
    float dist = length(diff);
    return smoothstep(radius + feather, radius - feather, dist);
}

float RoundedRectBar(float2 p, float2 center, float width, float height, float feather)
{
    float2 d = abs(p - center) - float2(width * 0.5, height * 0.5);
    d = max(d, 0.0);
    float dist = length(d);
    return smoothstep(feather, 0.0, dist);
}

float sdRoundedRect(float2 p, float2 b, float r)
{
    float2 d = abs(p) - b;
    float2 d_clamped = max(d, 0.0);
    return length(d_clamped) + min(max(d.x, d.y), 0.0) - r;
}

float sdRoundedTriangle(float2 p, float r)
{
    const float k = sqrt(3.0);
    p.x = abs(p.x) - 1.0;
    p.y = p.y + 1.0/k;
    if(p.x + k*p.y > 0.0)
    {
        p = float2(p.x - k*p.y, -k*p.x - p.y) / 2.0;
    }
    p.x -= clamp(p.x, -2.0, 0.0);
    return -length(p) * sign(p.y) + r;
}