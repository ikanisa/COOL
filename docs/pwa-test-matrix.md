# COOL PWA — Cross-Browser Test Matrix

## Last Updated
2026-04-04

## Test Environment

| Property | Value |
|----------|-------|
| App URL | https://cool.app |
| Flutter Version | See `.fvmrc` |
| Renderer | CanvasKit (WASM) |
| Service Worker | `flutter_service_worker.js` + `custom-sw.js` |

---

## Repo Validation Status

| Check | Status | Date | Notes |
|-------|--------|------|-------|
| Source wiring (`flutter analyze`) | ✅ | 2026-04-04 | PWA bridge, overlay, BioPay web stub, and path routing compile cleanly |
| PWA asset regression test | ✅ | 2026-04-04 | `flutter test test/docs/pwa_web_assets_test.dart` |
| Release web build | ✅ | 2026-04-04 | `flutter build web --release --no-wasm-dry-run` produced `build/web` |

Browser matrix below remains manual verification status. Source/build validation does not replace real-device testing.

---

## Desktop Browsers

| Browser | Version | Install | Offline | SW Update | Deep Links | Notes |
|---------|---------|---------|---------|-----------|------------|-------|
| Chrome | 124+ | ⏳ | ⏳ | ⏳ | ⏳ | Primary target |
| Edge | 124+ | ⏳ | ⏳ | ⏳ | ⏳ | Chromium-based, same engine |
| Firefox | 126+ | ❌ N/A | ⏳ | ⏳ | ⏳ | No install support |
| Safari macOS | 17.4+ | ❌ N/A | ⏳ | ⏳ | ⏳ | SW support since 17.4 |

## Mobile Browsers

| Browser | Platform | Version | Install | Offline | SW Update | Deep Links | Notes |
|---------|----------|---------|---------|---------|-----------|------------|-------|
| Chrome | Android | 124+ | ⏳ | ⏳ | ⏳ | ⏳ | Primary mobile target |
| Samsung Internet | Android | 25+ | ⏳ | ⏳ | ⏳ | ⏳ | Significant market share in Rwanda |
| Firefox | Android | 126+ | ❌ N/A | ⏳ | ⏳ | ⏳ | Limited PWA support |
| Safari | iOS 16.4+ | 16.4+ | ⏳ (A2HS) | ⏳ | ⏳ | ⏳ | Guided install via share sheet |
| Safari | iOS 17+ | 17+ | ⏳ (A2HS) | ⏳ | ⏳ | ⏳ | Push notification support |

## Legend
- ✅ Tested and passing
- ⚠️ Tested with known issues (document issue)
- ❌ Not supported / not applicable
- ⏳ Not yet tested

---

## Test Checklist Per Browser

### 1. Installation
- [ ] PWA install prompt appears (Chrome/Edge/Samsung) OR guided A2HS works (iOS Safari)
- [ ] App icon appears on home screen after install
- [ ] App opens in standalone mode (no browser chrome)
- [ ] `start_url` loads correctly
- [ ] Theme color matches status bar

### 2. Offline Behavior
- [ ] Disconnect network → navigate → `offline.html` shown (not browser error)
- [ ] Reconnect → reload → app resumes normally
- [ ] Previously cached pages load from cache

### 3. Service Worker Update
- [ ] Deploy new version
- [ ] On next visit, new content loads after page reload
- [ ] Old caches are purged

### 4. Deep Links
- [ ] `/home` → loads home screen
- [ ] `/profile` → loads profile (if authenticated)
- [ ] `/contribution-circles/:id` → loads group detail
- [ ] Unknown route → appropriate fallback

### 5. Accessibility
- [ ] Tab through interactive elements → focus ring visible (web only)
- [ ] Screen reader announces key elements (VoiceOver on iOS, TalkBack on Android)
- [ ] Touch targets ≥ 48px on mobile

### 6. Performance
- [ ] App loads within 5 seconds on 4G simulation
- [ ] Interactions feel smooth (no jank on scroll/tap)
- [ ] Splash screen shows immediately, then app loads

---

## Rwanda-Specific Testing Notes

| Consideration | Details |
|---------------|---------|
| Primary Android browser | Samsung Internet has ~25% market share in Rwanda |
| Network conditions | Test on simulated 3G (1.5 Mbps) in addition to 4G |
| Device targets | Samsung Galaxy A-series (2–4GB RAM), Infinix, Tecno |
| iOS share | Rwanda iOS market is small (~5%) but growing |

---

## How to Run Tests

### Desktop
1. Open Chrome DevTools → Application → Service Workers → check worker registered
2. Toggle "Offline" mode in DevTools Network tab
3. Navigate → verify offline.html fallback

### Mobile (Android)
1. Open `chrome://flags` → enable "Show install prompt" if needed
2. Visit app URL → wait for install banner
3. Use remote debugging: `chrome://inspect` from desktop

### Mobile (iOS)
1. Open Safari → visit app URL
2. Tap Share → scroll to "Add to Home Screen"
3. Test offline by enabling Airplane Mode
