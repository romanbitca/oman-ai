#!/usr/bin/env python3
"""Draws mac/App/AppIcon.icon/Assets/wave.svg. Usage: scripts/icon-wave.py <output.svg>

Writes the menu bar icon's wave as a filled outline: the stroke of width 2.4 around
M2.2 11.4 C4.4 2.4 7 3.2 9 9 C11 14.8 13.6 15.6 15.8 6.6 in an 18-unit box, 41 times as big and centred
in 1024 by 1024, with round ends. A filled shape has no implicit closing line for the glass to light."""
import math, sys
segments = [((2.2, 11.4), (4.4, 2.4), (7, 3.2), (9, 9)), ((9, 9), (11, 14.8), (13.6, 15.6), (15.8, 6.6))]
scale, half = 41.0, 1.2
def place(x, y):
    return (512 + scale * (x - 9), 512 + scale * (y - 9))
def point(seg, t):
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = seg
    a, b, c, d = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t ** 2, t ** 3
    return (a * x0 + b * x1 + c * x2 + d * x3, a * y0 + b * y1 + c * y2 + d * y3)
def tangent(seg, t):
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = seg
    dx = 3 * (1 - t) ** 2 * (x1 - x0) + 6 * (1 - t) * t * (x2 - x1) + 3 * t ** 2 * (x3 - x2)
    dy = 3 * (1 - t) ** 2 * (y1 - y0) + 6 * (1 - t) * t * (y2 - y1) + 3 * t ** 2 * (y3 - y2)
    n = math.hypot(dx, dy)
    return dx / n, dy / n
centre, normals = [], []
for index, seg in enumerate(segments):
    for step in range(0 if index == 0 else 1, 401):
        t = step / 400
        x, y = point(seg, t)
        tx, ty = tangent(seg, t)
        centre.append((x, y))
        normals.append((-ty, tx))
left = [(x + nx * half, y + ny * half) for (x, y), (nx, ny) in zip(centre, normals)]
right = [(x - nx * half, y - ny * half) for (x, y), (nx, ny) in zip(centre, normals)]
def cap(at, normal, forward):
    """Half a circle around `at`, from the left side to the right, bulging along `forward`."""
    x, y = at; nx, ny = normal; fx, fy = forward
    out = []
    for step in range(1, 48):
        angle = math.pi * step / 48
        out.append((x + half * (nx * math.cos(angle) + fx * math.sin(angle)),
                    y + half * (ny * math.cos(angle) + fy * math.sin(angle))))
    return out
end_t = tangent(segments[-1], 1.0)
start_t = tangent(segments[0], 0.0)
outline = left + cap(centre[-1], normals[-1], end_t) + right[::-1] + cap(centre[0], (-normals[0][0], -normals[0][1]), (-start_t[0], -start_t[1]))
points = [place(x, y) for x, y in outline]
d = "M" + " L".join(f"{x:.2f} {y:.2f}" for x, y in points) + " Z"
svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n'
       '  <!-- The menu bar icon\'s wave from MenuBarIcon.svg, 41 times its size and centred on its middle point (9, 9), as a filled\n'
       '       outline of its stroke, 2.4 wide with round ends, so that it still reads at 16 pixels. scripts/icon-wave.py\n'
       '       draws it; a stroke left open made the glass light the line between its two ends. -->\n'
       f'  <path fill="#FFFFFF" d="{d}"/>\n</svg>\n')
open(sys.argv[1], "w").write(svg)
print("points", len(points))
