# Asset Generation Guide

All assets use a **consistent pixel-art style**:
- Top-down view, 45° slight angle
- 16×16 or 32×32 pixel sprites (scale up 4× for display)
- Limited palette: ~16 colors (NES-inspired)
- Black outlines (1px)
- Transparent background (PNG)

**Recommended tools:** Stable Diffusion (SDXL + PixelArt LoRA), Midjourney, DALL-E 3, or Aseprite for manual pixel art.

---

## Color Palette Reference

```
Background dark  #1a1a2e
Background mid   #16213e
Accent blue      #0f3460
Player blue      #4477ff
Player highlight #88aaff
Enemy red        #e94560
Enemy yellow     #ffd166
Enemy purple     #7b2d8b
Health red       #ff4444
XP green         #06d6a0
Coin gold        #ffd700
White            #f0f0f0
Shadow           #2d2d2d
```

---

## Sprite Prompts

### Player Character
```
pixel art, top-down RPG, small warrior character, 32x32 pixels, blue armor,
helmet, sword at side, black outline, transparent background, 16-bit style,
NES color palette, facing down, idle pose, clean pixel art
```

**Variations needed:**
- Idle (1 frame)
- Walk cycle (4 frames: down/up/left/right)

Size: 32×32 px, export 4 frames in a row as spritesheet (128×32)

---

### Enemy – Basic (Red Slime / Zombie)
```
pixel art, top-down RPG enemy, red blob creature, angry eyes, 24x24 pixels,
black outline, transparent background, 16-bit retro style, NES palette,
simple round body, small menacing enemy
```

---

### Enemy – Fast (Yellow Bat / Ghost)
```
pixel art, top-down RPG, fast enemy, yellow ghost or bat, 20x20 pixels,
glowing effect, black outline, transparent background, 16-bit retro,
sharp wings or streamlined body, aggressive pose
```

---

### Enemy – Tank (Purple Ogre / Golem)
```
pixel art, top-down RPG, large tank enemy, dark purple stone golem,
32x32 pixels, heavy armor, thick black outline, transparent background,
16-bit retro style, large imposing silhouette
```

---

### Projectile (Bullet / Energy Orb)
```
pixel art, small glowing energy orb, cyan blue, 8x8 pixels,
bright center with soft glow halo, transparent background,
game projectile sprite, retro arcade style
```

**Alternative:** Simple 8×8 white circle with cyan tint (make in Aseprite in 2 minutes)

---

### XP Gem / Coin
```
pixel art, small gem pickup, bright green emerald, 10x10 pixels,
shiny highlight dot, black outline, transparent background,
top-down RPG pickup item, 16-bit retro style
```

---

### Background Tile
```
pixel art, top-down dungeon or grass floor tile, 32x32 pixels,
seamlessly tileable, dark stone bricks or grass patches,
subtle texture variation, 16-bit retro RPG style, muted dark tones,
NES inspired palette
```

Import as **TileSet** in Godot (TileMap node) for infinite scrolling background.

---

## Animation Frames

For the player walk cycle, generate 4 frames or use Aseprite to animate manually.

In Godot: use **AnimatedSprite2D** instead of Sprite2D, or **AnimationPlayer** with SpriteFrames.

Minimum animation set:
- `idle`  – 1-2 frames, slight bob
- `walk`  – 4 frames
- `hurt`  – 1-2 frames (already handled by code modulate flash)

---

## Audio Prompts (AI Sound Generation)

Recommended tools: **ElevenLabs Sound Effects**, **Freesound.org**, **sfxr/jsfxr**, **Bfxr**

### Shoot / Attack Sound
```
8-bit retro laser shot, short blip, 0.1 seconds,
bright high-pitched pew, arcade game sound effect
```
jsfxr settings: Laser/Shoot preset, pitch high, short decay

### Enemy Hit Sound
```
8-bit retro hit sound, short thud or splat, 0.15 seconds,
low-pitched impact, retro game enemy damage sound
```
jsfxr: Hit/Hurt preset

### Enemy Death Sound
```
8-bit retro death sound, short pop or explosion, 0.2 seconds,
satisfying defeat sound, arcade game enemy kill
```
jsfxr: Explosion preset, very short

### Level Up Sound
```
8-bit retro level up jingle, ascending arpeggio, 0.5 seconds,
bright cheerful chime, classic RPG level up
```
jsfxr: Powerup preset

### Coin Pickup
```
8-bit coin pickup chime, single bright ding, 0.1 seconds,
classic arcade coin collect sound
```
jsfxr: Coin preset

---

## Quick Asset Pipeline

1. Generate images with AI tool (Stable Diffusion / Midjourney / DALL-E)
2. Remove background in **remove.bg** or manually in GIMP/Photoshop
3. Downscale to 32×32 in **Aseprite** (nearest-neighbor scaling)
4. Export as PNG with transparency
5. Drop into `assets/sprites/` in Godot
6. Set import filter to **Nearest** (critical for crisp pixels!)

---

## Recommended Free Tools

| Tool       | Use                    | Link                      |
|------------|------------------------|---------------------------|
| Aseprite   | Pixel art editor       | aseprite.org              |
| jsfxr      | 8-bit SFX generator    | sfxr.me                   |
| remove.bg  | Background removal     | remove.bg                 |
| Lospec     | Pixel art palettes     | lospec.com/palette-list   |
| Piskel     | Free pixel art online  | piskelapp.com             |
