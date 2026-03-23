# Survivor – Full Setup Guide

## 1. Open the Project

1. Launch **Godot 4.2+** → *Import* → select `project.godot`
2. Let Godot import assets on first open

---

## 2. Collision Layers (Project → Project Settings → Layer Names → 2D Physics)

| Layer | Name       | Used by                  |
|-------|-----------|--------------------------|
| 1     | Player     | Player body              |
| 2     | Enemies    | Enemy CharacterBody2D    |
| 3     | Projectile | Projectile Area2D        |
| 4     | Pickup     | Coin Area2D              |

---

## 3. Create Scenes (FileSystem panel → right-click → New Scene)

### 3a. `scenes/projectile.tscn`

```
Projectile  (Area2D)            ← script: scripts/projectile.gd
├── Sprite2D                    ← assign projectile texture (8×8 bright yellow square)
├── CollisionShape2D            ← CircleShape2D, radius 4
│   └── Shape: CircleShape2D
└── LifetimeTimer (Timer)       ← One Shot: ON, Wait Time: 2.8
```

**Area2D Inspector:**
- Collision Layer: 3 (Projectile)
- Collision Mask:  2 (Enemies)

---

### 3b. `scenes/enemy.tscn`

```
Enemy  (CharacterBody2D)        ← script: scripts/enemy.gd
├── Sprite2D                    ← placeholder: colored square (see below per type)
├── CollisionShape2D            ← CapsuleShape2D or CircleShape2D, radius 14
├── HealthBar  (ProgressBar)    ← size: (40, 5), min 0, max 100, value 100
│   └── Position: (-20, -28)
└── DamageArea  (Area2D)
    └── CollisionShape2D        ← CircleShape2D, radius 14
```

**CharacterBody2D:**
- Collision Layer: 2 (Enemies)
- Collision Mask:  1 (Player)

**DamageArea (Area2D):**
- Collision Layer: (none)
- Collision Mask:  1 (Player)
- Monitoring: ON

HealthBar styling: set Fill color to red in Theme Overrides.

---

### 3c. `scenes/coin.tscn`

```
Coin  (Area2D)                  ← script: scripts/coin.gd
├── Sprite2D                    ← small green/yellow gem sprite (8×8)
└── CollisionShape2D            ← CircleShape2D, radius 8
```

**Area2D:**
- Collision Layer: 4 (Pickup)
- Collision Mask:  1 (Player)
- Monitoring: ON

---

### 3d. `scenes/game.tscn`  ← main scene

```
Game  (Node2D)                          ← script: scripts/game.gd
│
├── World  (Node2D)
│   ├── Background  (Sprite2D)          ← tiling background texture, centered at 0,0
│   ├── Enemies  (Node2D)               ← empty container
│   └── Coins  (Node2D)                 ← empty container
│
├── Player  (CharacterBody2D)           ← script: scripts/player.gd
│   ├── Sprite2D                        ← player sprite (16×16 or 32×32)
│   ├── CollisionShape2D                ← CapsuleShape2D (10, 14)
│   ├── Camera2D                        ← script: scripts/camera_shake.gd
│   │     Position Smoothing: ON, Speed 8
│   ├── AttackTimer  (Timer)            ← One Shot: OFF, Wait Time: 1.0
│   └── IFramesTimer  (Timer)           ← One Shot: ON,  Wait Time: 0.6
│
├── ProjectilePool  (Node)              ← script: scripts/object_pool.gd
│   └── Inspector: scene = projectile.tscn, initial_size = 20
│
├── Spawner  (Node)                     ← script: scripts/spawner.gd
│   └── Inspector: enemy_scene = enemy.tscn
│
└── UI  (CanvasLayer)                   ← script: scripts/ui_manager.gd
    │   Layer: 10, process_mode: Always
    │
    ├── HUD  (Control)
    │   ├── HealthBar  (ProgressBar)    size (200,18), anchor top-left
    │   ├── XPBar      (ProgressBar)    size (540,12), anchor bottom-full-width
    │   ├── TimerLabel  (Label)         center-top, font_size 22
    │   ├── WaveLabel   (Label)         top-right corner
    │   ├── LevelLabel  (Label)         top-left, below health
    │   ├── CoinLabel   (Label)         top-right, below wave
    │   └── PauseButton (Button)        top-right corner, text "⏸", size (50,50)
    │
    ├── VirtualJoystick  (Control)      ← script: scripts/virtual_joystick.gd
    │   │   Full-rect anchor, process_mode: Always
    │   ├── Base  (ColorRect)           size (130,130), color rgba(255,255,255,60)
    │   │                               pivot at center, circle via shader or as-is
    │   └── Thumb (ColorRect)           size (60,60),   color rgba(255,255,255,140)
    │
    ├── UpgradeMenu  (Control)          ← script: scripts/upgrade_manager.gd
    │   │   Full-rect anchor, process_mode: Always
    │   └── Panel  (PanelContainer)     centered, min-size (480,300)
    │       └── VBox  (VBoxContainer)
    │           ├── TitleLabel (Label)  text "LEVEL UP!", centered, font_size 26
    │           └── CardContainer (HBoxContainer)   separation 12
    │
    └── GameOverScreen  (Control)       Full-rect anchor, process_mode: Always
        └── Panel  (PanelContainer)     centered, min-size (380,320)
            └── VBox  (VBoxContainer)   alignment center, separation 16
                ├── Label               text "GAME OVER", font_size 32
                ├── TimeLabel  (Label)  text "Time: 00:00"
                ├── LevelLabel (Label)  text "Level: 1"
                └── RestartButton (Button)  text "PLAY AGAIN"
```

**Player CharacterBody2D:**
- Collision Layer: 1 (Player)
- Collision Mask:  2 (Enemies)  ← so it bumps enemies physically (optional)

---

## 4. Connect Signals (select node → Node tab → Signals)

Most signals are connected via code. The ones needing Editor wiring:

| Node          | Signal              | Target      | Method                        |
|---------------|---------------------|-------------|-------------------------------|
| AttackTimer   | timeout             | Player      | _on_attack_timer_timeout      |
| IFramesTimer  | timeout             | Player      | _on_i_frames_timer_timeout    |

All other signals (GameManager, joystick, spawner) are wired in `game.gd _ready()`.

---

## 5. Placeholder Art (immediate playability without real assets)

You can use Godot's **Polygon2D** or just set **Sprite2D modulate** for colored placeholders.

Quick placeholder recipe in Godot editor – for any Sprite2D without a texture:
1. Add a `MeshInstance2D` with a `QuadMesh` (or keep Sprite2D with no texture – it shows a white square)
2. Set `modulate` to desired color in Inspector

Or: Select Sprite2D → drag a color from the color picker to Texture slot (Godot will create a 1px texture). Then scale the Sprite2D.

**Recommended placeholder colors:**
- Player:       Blue   `#4477FF`
- Enemy Basic:  Red    `#FF4444`
- Enemy Fast:   Yellow `#FFCC00`
- Enemy Tank:   Purple `#8833CC`
- Projectile:   Cyan   `#00FFFF`
- Coin/Gem:     Green  `#44FF88`

---

## 6. Autoload Verification

*Project → Project Settings → Autoload*

| Name          | Path                         | Singleton |
|---------------|------------------------------|-----------|
| GameManager   | res://scripts/game_manager.gd | ✓         |

---

## 7. Import Real Assets

Once you have AI-generated sprites (PNG with transparency):
1. Drag PNGs into `assets/sprites/` in the FileSystem panel
2. Select each texture → Import tab:
   - Filter: **Nearest** (crisp pixel art)
   - Mipmaps: **OFF**
3. Assign to Sprite2D nodes in the Inspector

---

## 8. Audio Setup

1. Place `.wav` or `.ogg` files in `assets/audio/`
2. Add an **AudioStreamPlayer** to Game node (or player/enemy as needed)
3. Assign stream in Inspector
4. Call `$AudioStreamPlayer.play()` on events (hit, death, shoot)

---

## 9. Export to Android APK

### Prerequisites
- Android SDK + JDK installed
- Android Build Template installed (Editor → Android → Install Android Build Template)
- Keystore file for signing (one-time setup)

### Steps

1. **Project → Export → Add → Android**

2. Android Export settings:
   - Package: `com.yourname.survivor`
   - Min SDK: 21 (Android 5.0)
   - Target SDK: 33
   - Orientation: **Portrait**
   - Screen: Landscape **unchecked**

3. **Permissions tab** (enable):
   - `VIBRATE` (optional for haptics)

4. **Keystore** (one-time):
   ```bash
   keytool -genkey -v -keystore survivor.keystore \
     -alias survivorkey -keyalg RSA -keysize 2048 -validity 10000
   ```
   Set path + alias + password in Export → Keystore section.

5. Click **Export Project** → save as `survivor.apk`

6. Install on device:
   ```bash
   adb install survivor.apk
   ```

### One-Click Deploy (USB debugging)
- Connect Android device with USB debugging ON
- Editor → Remote Debug → Deploy to Device

---

## 10. Performance Tips (already baked in)

- Projectiles use **ObjectPool** – no allocation per shot
- Enemies use `queue_free()` (max 45 on screen) – acceptable for mobile
- Gravity disabled globally (`physics/2d/default_gravity = 0`)
- Camera uses Camera2D position smoothing to reduce jitter
- No expensive shadows or lighting
- Target 60 FPS; if needed lower to 30 in Project Settings → Display → FPS

---

## 11. Quick Test Checklist

- [ ] Player moves with touch joystick
- [ ] Camera follows player
- [ ] Enemies spawn from edges and chase player
- [ ] Bullets fire at nearest enemy, enemies take damage and die
- [ ] Coins spawn on enemy death and attract to player
- [ ] XP gained, level-up menu appears with 3 choices
- [ ] Upgrade applies (e.g., Multishot fires 2 bullets)
- [ ] Health decreases on enemy contact, screen shakes
- [ ] Game Over screen shows on death, Restart works
- [ ] Pause button works
- [ ] Wave number increases every 22 seconds
