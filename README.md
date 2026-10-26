# NotchIsland

Dynamic Island untuk notch MacBook Air M2: info sistem, kontrol musik, cermin kamera, rak file, dan lirik di bawah notch. Lihat PRD untuk rencana lengkap.

## Build & jalankan

Dengan Xcode: buka `NotchIsland.xcodeproj`, pilih scheme **NotchIsland**, lalu Run (⌘R). Unit test: ⌘U.

Dari terminal:

```sh
xcodebuild -project NotchIsland.xcodeproj -scheme NotchIsland -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/NotchIsland.app

# unit test
xcodebuild -project NotchIsland.xcodeproj -scheme NotchIsland -derivedDataPath build test
```

App tidak muncul di Dock. Klik ikon kapsul di menu bar untuk **Pengaturan…** dan **Keluar**.

## Sumber musik

| Sumber | Cara kerja | Yang perlu disiapkan |
| --- | --- | --- |
| Spotify | AppleScript + notifikasi perubahan lagu | Izinkan saat macOS meminta akses Automation |
| Apple Music | AppleScript + notifikasi perubahan lagu | Izinkan saat macOS meminta akses Automation |
| YouTube / YouTube Music di Chrome, Arc, Brave, Edge | AppleScript menjalankan JavaScript kecil di tab YouTube (dicek tiap 2–5 detik selama browser terbuka) | Di browser: **View › Developer › Allow JavaScript from Apple Events**, lalu izinkan akses Automation |

MediaRemote (API privat) tidak dipakai karena sudah dibatasi Apple sejak macOS 15.4.

## Catatan

- Build ditandatangani ad-hoc, jadi macOS bisa meminta ulang izin kamera/Automation setelah build ulang. Pilih **Personal Team** di Signing & Capabilities agar izin tetap tersimpan.
- Untuk **Buka saat login**, salin app ke `/Applications` dulu, lalu aktifkan dari Pengaturan.
- Data: `~/Library/Application Support/NotchIsland/` (rak file `shelf.json`, salinan file `Files/`, cache lirik `Lyrics/`).

## Status

- [x] Fase 1: panel notch, hover expand/collapse, tidak mencuri fokus
- [x] Fase 2: jam & baterai
- [x] Fase 3: now playing (Spotify, Apple Music, YouTube di browser Chromium)
- [x] Fase 4: kamera
- [x] Fase 5: file shelf
- [x] Fase 6: lirik (LRCLIB, cache lokal, unit test parser & pencocokan)
- [x] Fase 7: pengaturan, menu bar, buka saat login, lokalisasi id/en
