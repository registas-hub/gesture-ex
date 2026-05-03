# gesture-ex

macOS menu-bar utility that:
1. Converts the right-click context menu trigger from **mouse-down** to **mouse-up**, matching the Windows behavior.
2. Adds Windows-style **mouse gestures** for Chromium- and WebKit-based browsers (Chrome, Edge, Brave, Arc, Whale, Vivaldi, Opera, Safari, Orion, …).

## Features

- HID-level event tap → works with Chromium's strict input validation (no extension conflicts).
- 4-direction gestures (←, →, ↑, ↓) with customizable mappings (Back / Forward / Reload / New Tab / Close Tab / …).
- Multi-segment custom gestures (e.g. `←↑`, `↓→`) drawn by the user.
- Live trail overlay during drag with action label that updates in real time.
- Per-engine gesture toggles (Chromium / WebKit independently).
- Customizable trail color, background color, opacity, action-label visibility, lingering duration.

## Build

```bash
# (1회만) 자체 서명 인증서 생성 — TCC 권한이 매 빌드마다 리셋되지 않도록
./create-signing-cert.sh

# 빌드
./build.sh

# 실행
open gesture-ex.app
```

## Required Permissions

System Settings → Privacy & Security 에서 빌드된 `gesture-ex.app`에 다음 두 권한 부여:

- **Accessibility**
- **Input Monitoring**

## Customization

메뉴바 아이콘 → **Customize Gestures…** (`⇧⌘,`)
