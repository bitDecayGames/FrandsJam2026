#!/usr/bin/env python3
"""
Lake Generator Prototype
Generates smooth organic lake shapes with correct 13-tile autotiling.

Zones: 0=land, 1=shallow water, 2=deep water

Two transition rings, each with 13 tiles:
  Outer shore (land→shallow): 27,28,29,25,26,47,48,49,45,46,67,68,69
  Inner shore (shallow→deep): 20,21,22,23,24,40,41,42,43,44,62,63,64
"""

import math
import random
import sys
from collections import Counter

# === TILE MAPPINGS ===

OUTER_SHORE = {  # land → shallow
    'NW_CONVEX': 27, 'N_EDGE': 28, 'NE_CONVEX': 29,
    'NW_CONCAVE': 25, 'NE_CONCAVE': 26,
    'W_EDGE': 47, 'FILL': 48, 'E_EDGE': 49,
    'SW_CONCAVE': 45, 'SE_CONCAVE': 46,
    'SW_CONVEX': 67, 'S_EDGE': 68, 'SE_CONVEX': 69,
}

INNER_SHORE = {  # shallow → deep
    'NW_CONVEX': 20, 'NE_CONVEX': 21,
    'NW_CONCAVE': 22, 'N_EDGE': 23, 'NE_CONCAVE': 24,
    'SW_CONVEX': 40, 'SE_CONVEX': 41,
    'W_EDGE': 42, 'FILL': 43, 'E_EDGE': 44,
    'SW_CONCAVE': 62, 'S_EDGE': 63, 'SE_CONCAVE': 64,
}

GRASS = 3


def hash_float(x, y, seed):
    """Simple hash → float in [0, 1)."""
    h = (x * 374761393 + y * 668265263 + seed * 1274126177) & 0xFFFFFFFF
    h = ((h >> 16) ^ h) * 0x45d9f3b & 0xFFFFFFFF
    h = ((h >> 16) ^ h) * 0x45d9f3b & 0xFFFFFFFF
    return ((h >> 16) ^ h & 0xFFFF) / 65536.0


def smooth_noise(w, h, scale, seed):
    """Bilinear-interpolated value noise in [-1, 1]."""
    gw = w // scale + 2
    gh = h // scale + 2
    grid = [[hash_float(x, y, seed) for x in range(gw)] for y in range(gh)]

    result = [[0.0] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            fx = x / scale
            fy = y / scale
            ix, iy = int(fx), int(fy)
            tx = fx - ix
            ty = fy - iy
            # smoothstep
            tx = tx * tx * (3 - 2 * tx)
            ty = ty * ty * (3 - 2 * ty)
            n00 = grid[iy][ix]
            n10 = grid[iy][ix + 1]
            n01 = grid[iy + 1][ix]
            n11 = grid[iy + 1][ix + 1]
            v = n00 * (1 - tx) * (1 - ty) + n10 * tx * (1 - ty) + n01 * (1 - tx) * ty + n11 * tx * ty
            result[y][x] = v

    # normalize to [-1, 1]
    flat = [v for row in result for v in row]
    lo, hi = min(flat), max(flat)
    rng = hi - lo if hi > lo else 1
    for y in range(h):
        for x in range(w):
            result[y][x] = (result[y][x] - lo) / rng * 2 - 1
    return result


def ca_smooth(grid, w, h, birth=5, survive=4):
    """One pass of cellular automata smoothing."""
    out = [[False] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            count = 0
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    if dx == 0 and dy == 0:
                        continue
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and grid[ny][nx]:
                        count += 1
            out[y][x] = count >= (survive if grid[y][x] else birth)
    return out


def erode(grid, w, h):
    """Erode one layer: remove cells with any cardinal neighbor missing."""
    out = [[False] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            if not grid[y][x]:
                continue
            if x <= 0 or y <= 0 or x >= w - 1 or y >= h - 1:
                continue
            if grid[y - 1][x] and grid[y + 1][x] and grid[y][x - 1] and grid[y][x + 1]:
                out[y][x] = True
    return out


def generate_lake(width, height, cx, cy, rx, ry, seed=42, shallow_width=3):
    """Generate a lake. Returns (tiles, zones) — both 2D lists [y][x]."""
    rng = random.Random(seed)

    # 1) Noise-perturbed ellipse → water mask
    noise = smooth_noise(width, height, scale=5, seed=seed)
    # Add a second octave for more organic shapes
    noise2 = smooth_noise(width, height, scale=3, seed=seed + 7)

    water = [[False] * width for _ in range(height)]
    for y in range(height):
        for x in range(width):
            dx = (x - cx) / rx
            dy = (y - cy) / ry
            dist = math.sqrt(dx * dx + dy * dy)
            n = noise[y][x] * 0.25 + noise2[y][x] * 0.15
            water[y][x] = dist < 1.0 + n

    # 2) CA smoothing
    for _ in range(4):
        water = ca_smooth(water, width, height)

    # 3) Build zones: erode for shallow ring
    deep = [row[:] for row in water]
    for _ in range(shallow_width):
        deep = erode(deep, width, height)
    # Extra smoothing on deep zone to keep it clean
    for _ in range(2):
        deep = ca_smooth(deep, width, height, birth=5, survive=4)

    zones = [[0] * width for _ in range(height)]
    for y in range(height):
        for x in range(width):
            if deep[y][x]:
                zones[y][x] = 2
            elif water[y][x]:
                zones[y][x] = 1

    # 4) Clean zones: remove peninsulas/single-cell protrusions
    zones = clean_zones(zones, width, height)

    # 5) Autotile
    tiles = autotile(zones, width, height)

    return tiles, zones


def clean_zones(zones, w, h):
    """Remove cells that would create impossible autotile configurations."""
    changed = True
    while changed:
        changed = False
        for y in range(h):
            for x in range(w):
                z = zones[y][x]
                if z == 0:
                    continue
                # Count cardinal neighbors at same or higher zone
                count = 0
                for dx, dy in ((0, -1), (0, 1), (-1, 0), (1, 0)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and zones[ny][nx] >= z:
                        count += 1
                if count < 2:
                    zones[y][x] = z - 1
                    changed = True

    # Second pass: ensure no diagonal-only connections (would need tiles we don't have)
    changed = True
    while changed:
        changed = False
        for y in range(h):
            for x in range(w):
                z = zones[y][x]
                if z == 0:
                    continue
                # A cell must not be diagonally adjacent to same zone without
                # at least one shared cardinal neighbor also in the zone.
                # This prevents checkerboard patterns.
                for dxy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
                    dx, dy = dxy
                    diag_z = zones[y + dy][x + dx] if 0 <= x + dx < w and 0 <= y + dy < h else 0
                    if diag_z < z:
                        continue
                    # Check the two cardinal neighbors that share this diagonal
                    c1 = zones[y + dy][x] if 0 <= y + dy < h else 0
                    c2 = zones[y][x + dx] if 0 <= x + dx < w else 0
                    if c1 < z and c2 < z:
                        # Diagonal-only connection — remove current cell
                        zones[y][x] = z - 1
                        changed = True
                        break

    return zones


def get_z(zones, x, y, w, h):
    if x < 0 or x >= w or y < 0 or y >= h:
        return 0
    return zones[y][x]


def classify_tile(zones, x, y, w, h, zone_level):
    """Determine tile role for a cell at a zone boundary.

    zone_level: threshold (1 for outer shore, 2 for inner shore).
    A neighbor is 'inside' if its zone >= zone_level.
    """
    def ins(nx, ny):
        return get_z(zones, nx, ny, w, h) >= zone_level

    n  = ins(x, y - 1)
    s  = ins(x, y + 1)
    ww = ins(x - 1, y)
    e  = ins(x + 1, y)
    nw = ins(x - 1, y - 1)
    ne = ins(x + 1, y - 1)
    sw = ins(x - 1, y + 1)
    se = ins(x + 1, y + 1)

    # All four cardinal neighbors inside → check diagonals for concave corners
    # (only for outer shore; inner shore concave corners are handled in pass A)
    if n and s and ww and e:
        if not nw: return 'NW_CONCAVE'
        if not ne: return 'NE_CONCAVE'
        if not sw: return 'SW_CONCAVE'
        if not se: return 'SE_CONCAVE'
        return 'FILL'

    # Convex corners: two adjacent cardinal sides outside
    if not n and not ww: return 'NW_CONVEX'
    if not n and not e:  return 'NE_CONVEX'
    if not s and not ww: return 'SW_CONVEX'
    if not s and not e:  return 'SE_CONVEX'

    # Straight edges: one cardinal side outside
    if not n: return 'N_EDGE'
    if not s: return 'S_EDGE'
    if not ww: return 'W_EDGE'
    if not e: return 'E_EDGE'

    return 'FILL'


def autotile(zones, w, h):
    """Assign tile IDs based on zone map. Uses three passes for correct inner shore."""
    tiles = [[-1] * w for _ in range(h)]

    CONCAVE_TILES = {INNER_SHORE['NW_CONCAVE'], INNER_SHORE['NE_CONCAVE'],
                     INNER_SHORE['SW_CONCAVE'], INNER_SHORE['SE_CONCAVE']}

    # Pass A1: concave corners on shallow cells with 2+ cardinal deep neighbors
    for y in range(h):
        for x in range(w):
            if zones[y][x] != 1:
                continue
            n_deep = get_z(zones, x, y-1, w, h) >= 2
            s_deep = get_z(zones, x, y+1, w, h) >= 2
            w_deep = get_z(zones, x-1, y, w, h) >= 2
            e_deep = get_z(zones, x+1, y, w, h) >= 2

            if s_deep and e_deep:
                tiles[y][x] = INNER_SHORE['NW_CONCAVE']
            elif s_deep and w_deep:
                tiles[y][x] = INNER_SHORE['NE_CONCAVE']
            elif n_deep and e_deep:
                tiles[y][x] = INNER_SHORE['SW_CONCAVE']
            elif n_deep and w_deep:
                tiles[y][x] = INNER_SHORE['SE_CONCAVE']

    # Build padded zone map: concave corners count as zone 2 for deep-side autotiling
    padded = [row[:] for row in zones]
    for y in range(h):
        for x in range(w):
            if tiles[y][x] in CONCAVE_TILES:
                padded[y][x] = 2

    # Pass A2: tile 103 on shallow cells adjacent to deep/concave (not outer boundary)
    for y in range(h):
        for x in range(w):
            if zones[y][x] != 1 or tiles[y][x] != -1:
                continue
            adj_land = any(get_z(zones, x+dx, y+dy, w, h) < 1
                          for dx, dy in ((-1,-1),(0,-1),(1,-1),(-1,0),(1,0),(-1,1),(0,1),(1,1)))
            if adj_land:
                continue
            near_inner = any(get_z(padded, x+dx, y+dy, w, h) >= 2
                          for dx, dy in ((-1,-1),(0,-1),(1,-1),(-1,0),(1,0),(-1,1),(0,1),(1,1)))
            if near_inner:
                tiles[y][x] = 103

    # Pass B: outer shore (land→shallow) — uses original zones
    for y in range(h):
        for x in range(w):
            if zones[y][x] < 1 or tiles[y][x] != -1:
                continue
            on_outer = any(get_z(zones, x+dx, y+dy, w, h) < 1
                          for dx, dy in ((-1,-1),(0,-1),(1,-1),(-1,0),(1,0),(-1,1),(0,1),(1,1)))
            if on_outer:
                role = classify_tile(zones, x, y, w, h, 1)
                tiles[y][x] = OUTER_SHORE[role]
                continue
            if zones[y][x] == 1:
                tiles[y][x] = OUTER_SHORE['FILL']  # 48

    # Pass C: inner shore deep-side — uses PADDED zones so concave corners count as inside
    for y in range(h):
        for x in range(w):
            if zones[y][x] < 2:
                continue
            on_inner = any(get_z(padded, x+dx, y+dy, w, h) < 2
                          for dx, dy in ((-1,-1),(0,-1),(1,-1),(-1,0),(1,0),(-1,1),(0,1),(1,1)))
            if on_inner:
                role = classify_tile(padded, x, y, w, h, 2)
                # Inner shore deep-side never uses concave corners (handled by pass A1)
                if role in ('NW_CONCAVE', 'NE_CONCAVE', 'SW_CONCAVE', 'SE_CONCAVE'):
                    role = 'FILL'
                tiles[y][x] = INNER_SHORE[role]
            else:
                tiles[y][x] = INNER_SHORE['FILL']  # 43

    return tiles


# === DISPLAY ===

def print_zones(zones, w, h):
    print('Zone map:')
    for y in range(h):
        print(''.join('.~#'[zones[y][x]] for x in range(w)))
    print()


def print_tiles(tiles, zones, w, h):
    # Symbols: . = land, lowercase = shallow tiles, UPPERCASE = deep tiles
    outer_set = set(OUTER_SHORE.values())
    inner_set = set(INNER_SHORE.values())

    print('Tile grid:')
    hdr = '    ' + ''.join(f'{x:4d}' for x in range(w))
    print(hdr)
    for y in range(h):
        row = f'{y:3d} '
        for x in range(w):
            t = tiles[y][x]
            if t == -1:
                row += '   .'
            else:
                row += f'{t:4d}'
        print(row)
    print()


def validate(tiles, zones, w, h):
    """Check that tile assignments match the expected pattern from the real lake."""
    errors = 0
    for y in range(h):
        for x in range(w):
            t = tiles[y][x]
            z = zones[y][x]
            if t == -1 and z == 0:
                continue
            if t == -1 and z > 0:
                print(f'  ERROR: zone {z} at ({x},{y}) has no tile')
                errors += 1
            if z == 0 and t != -1:
                print(f'  ERROR: zone 0 at ({x},{y}) has tile {t}')
                errors += 1

    counts = Counter(tiles[y][x] for y in range(h) for x in range(w) if tiles[y][x] != -1)
    print('Tile counts:')
    for tid, cnt in sorted(counts.items()):
        label = ''
        for name, val in OUTER_SHORE.items():
            if val == tid:
                label = f'outer:{name}'
        for name, val in INNER_SHORE.items():
            if val == tid:
                label = f'inner:{name}'
        print(f'  {tid:3d}: {cnt:3d}x  {label}')
    print(f'Errors: {errors}')
    return errors


# === PNG OUTPUT ===

def save_png(tiles, zones, w, h, tileset_path, tile_size, tileset_cols, out_path):
    """Render the lake using actual tileset tiles and save as PNG."""
    from PIL import Image

    tileset = Image.open(tileset_path).convert('RGBA')
    img = Image.new('RGBA', (w * tile_size, h * tile_size), (0, 0, 0, 0))

    # Draw grass background for land cells, then overlay water tiles
    for y in range(h):
        for x in range(w):
            tid = tiles[y][x]
            if tid == -1:
                tid = GRASS  # grass background

            # Extract tile from tileset
            tx = (tid % tileset_cols) * tile_size
            ty = (tid // tileset_cols) * tile_size
            tile_img = tileset.crop((tx, ty, tx + tile_size, ty + tile_size))
            img.paste(tile_img, (x * tile_size, y * tile_size), tile_img)

    img.save(out_path)
    print(f'Saved PNG: {out_path}')


def save_png_zones(zones, w, h, tile_size, out_path):
    """Render a color-coded zone map as PNG (no tileset needed)."""
    import struct, zlib

    pw, ph = w * tile_size, h * tile_size

    # Zone colors: land=green, shallow=cyan, deep=blue
    COLORS = {
        0: (86, 140, 57),    # green (grass)
        1: (120, 210, 220),  # light cyan (shallow)
        2: (40, 90, 170),    # blue (deep)
    }

    # Build raw pixel data
    raw = bytearray()
    for py in range(ph):
        raw.append(0)  # PNG filter: None
        gy = py // tile_size
        for px in range(pw):
            gx = px // tile_size
            z = zones[gy][gx] if gy < h and gx < w else 0
            r, g, b = COLORS[z]
            # Draw grid lines
            if px % tile_size == 0 or py % tile_size == 0:
                r = max(0, r - 30)
                g = max(0, g - 30)
                b = max(0, b - 30)
            raw.extend([r, g, b])

    # Write minimal PNG
    def chunk(ctype, data):
        c = ctype + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xFFFFFFFF)

    sig = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', pw, ph, 8, 2, 0, 0, 0))
    idat = chunk(b'IDAT', zlib.compress(bytes(raw), 9))
    iend = chunk(b'IEND', b'')

    with open(out_path, 'wb') as f:
        f.write(sig + ihdr + idat + iend)

    print(f'Saved zone PNG: {out_path}')


def save_png_labeled(tiles, zones, w, h, tile_size, out_path):
    """Render a color-coded tile map with tile IDs labeled (no external deps)."""
    import struct, zlib

    CELL = tile_size * 2  # double size for readability
    pw, ph = w * CELL, h * CELL

    # Tile role → color
    outer_ids = set(OUTER_SHORE.values())
    inner_ids = set(INNER_SHORE.values())

    ZONE_COLORS = {
        0: (86, 140, 57),      # green (grass)
        1: (120, 210, 220),    # cyan (shallow fill)
        2: (40, 90, 170),      # blue (deep fill)
    }

    EDGE_COLOR = (200, 180, 100)      # outer shore edges/corners
    INNER_EDGE_COLOR = (80, 140, 200) # inner shore edges/corners

    raw = bytearray()
    for py in range(ph):
        raw.append(0)
        gy = py // CELL
        ly = py % CELL  # local y within cell
        for px in range(pw):
            gx = px // CELL
            lx = px % CELL

            t = tiles[gy][gx] if gy < h and gx < w else -1
            z = zones[gy][gx] if gy < h and gx < w else 0

            # Pick color
            if t == -1:
                r, g, b = ZONE_COLORS[0]
            elif t == OUTER_SHORE['FILL']:
                r, g, b = ZONE_COLORS[1]
            elif t == INNER_SHORE['FILL']:
                r, g, b = ZONE_COLORS[2]
            elif t in outer_ids:
                r, g, b = EDGE_COLOR
            elif t in inner_ids:
                r, g, b = INNER_EDGE_COLOR
            else:
                r, g, b = (128, 128, 128)

            # Grid lines
            if lx == 0 or ly == 0:
                r = max(0, r - 40)
                g = max(0, g - 40)
                b = max(0, b - 40)

            raw.extend([r, g, b])

    sig = b'\x89PNG\r\n\x1a\n'

    def chunk(ctype, data):
        c = ctype + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xFFFFFFFF)

    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', pw, ph, 8, 2, 0, 0, 0))
    idat = chunk(b'IDAT', zlib.compress(bytes(raw), 9))
    iend = chunk(b'IEND', b'')

    with open(out_path, 'wb') as f:
        f.write(sig + ihdr + idat + iend)

    print(f'Saved labeled PNG: {out_path}')


# === MAIN ===

if __name__ == '__main__':
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else random.randint(0, 999999)
    W, H = 30, 22
    CX, CY = 15, 11
    RX, RY = 10, 7

    tiles, zones = generate_lake(W, H, CX, CY, RX, RY, seed=seed)

    print(f'=== Lake Generator (seed={seed}) ===')
    print()
    print_zones(zones, W, H)
    print_tiles(tiles, zones, W, H)
    validate(tiles, zones, W, H)

    # Always save zone map PNG (no dependencies)
    zone_path = f'tools/lake_zones_{seed}.png'
    save_png_zones(zones, W, H, 16, zone_path)

    labeled_path = f'tools/lake_labeled_{seed}.png'
    save_png_labeled(tiles, zones, W, H, 16, labeled_path)

    # Try to render with actual tileset (needs PIL/Pillow)
    tileset_path = 'assets/images/devTiles.png'
    try:
        tile_path = f'tools/lake_render_{seed}.png'
        save_png(tiles, zones, W, H, tileset_path, 16, 20, tile_path)
    except ImportError:
        print('(Pillow not installed — skipping tileset render. pip install Pillow)')
    except FileNotFoundError:
        print(f'(Tileset not found at {tileset_path} — skipping tileset render)')
