# NotchIsland

Dynamic Island untuk notch MacBook Air M2: info sistem, kontrol musik, cermin kamera, rak file, dan lirik di bawah notch. Lihat PRD untuk rencana lengkap.

## Kebutuhan

- Mac Apple Silicon (M1 atau lebih baru), macOS 14 Sonoma atau lebih baru
- Xcode 16 atau lebih baru (untuk build dari kode)

## Pasang sebagai aplikasi (tanpa buka Xcode)

Cara ini membuat NotchIsland jadi aplikasi biasa di folder **Applications**, jadi bisa dibuka lewat Spotlight seperti app lain.

1. Clone repo dan masuk ke foldernya:

   ```sh
   git clone git@github.com:RifkalFirdaus123/notch-island.git
   cd notch-island
   ```

2. Jalankan script pemasang:

   ```sh
   ./scripts/install.sh
   ```

   Script ini mem-build versi Release, menyalinnya ke `/Applications/NotchIsland.app` (menimpa versi lama), lalu membuka app. Jalankan lagi perintah yang sama setiap kali ingin memperbarui app setelah mengubah kode.

3. Buka kapan saja dengan **Spotlight**: tekan ⌘ Space, ketik `NotchIsland`, lalu Enter. App juga muncul di Launchpad.

4. Agar otomatis aktif setiap laptop menyala: klik ikon kapsul di menu bar, buka **Pengaturan…**, lalu aktifkan **Buka saat login**.

App tidak muncul di Dock. Klik ikon kapsul di menu bar untuk **Pengaturan…** dan **Keluar**. Kalau ingin ikon di Dock, seret NotchIsland dari folder Applications ke Dock.

Saat pertama dipakai, macOS akan meminta izin **Kamera** (tab Kamera) dan **Automation** (Spotify, Music, atau browser untuk info lagu). Pilih **Allow**.

> **Kenapa script tidak memakai optimisasi Swift?** Build Release dengan optimisasi normal membuat compiler Swift crash pada proyek ini, jadi script mem-build dengan `SWIFT_OPTIMIZATION_LEVEL=-Onone`. Fungsinya sama; app ini cukup ringan sehingga perbedaannya tidak terasa.

### Membagikan ke teman

```sh
./scripts/install.sh --zip
```

Perintah ini juga membuat `~/Desktop/NotchIsland.zip` yang bisa dikirim lewat AirDrop. Mac penerima harus Apple Silicon dengan macOS 14 atau lebih baru.

Karena app belum dinotarisasi Apple, macOS penerima akan memblokirnya saat pertama dibuka (*"Apple could not verify NotchIsland is free of malware"*). Klik **Done** (jangan Move to Trash), lalu pakai salah satu cara:

- **System Settings › Privacy & Security**, gulir ke paling bawah, klik **Open Anyway**. Tombol ini hanya muncul sekitar satu jam setelah app dicoba dibuka.
- Atau di Terminal, setelah app dipindah ke folder Applications:

  ```sh
  sudo xattr -cr /Applications/NotchIsland.app
  ```

- Atau kirim lewat flashdisk, bukan AirDrop: file yang disalin dari flashdisk biasanya tidak diblokir.

Agar app bisa langsung dibuka tanpa langkah di atas, app perlu ditandatangani dengan Developer ID dan dinotarisasi lewat Apple Developer Program (berbayar).

## Build dengan Xcode (untuk pengembangan)

Buka `NotchIsland.xcodeproj`, pilih scheme **NotchIsland**, lalu Run (⌘R). Unit test: ⌘U.

Dari terminal:

```sh
xcodebuild -project NotchIsland.xcodeproj -scheme NotchIsland -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/NotchIsland.app

# unit test
xcodebuild -project NotchIsland.xcodeproj -scheme NotchIsland -derivedDataPath build test
```

## Sumber musik

| Sumber | Cara kerja | Yang perlu disiapkan |
| --- | --- | --- |
| Spotify | AppleScript + notifikasi perubahan lagu | Izinkan saat macOS meminta akses Automation |
| Apple Music | AppleScript + notifikasi perubahan lagu | Izinkan saat macOS meminta akses Automation |
| YouTube / YouTube Music di Chrome, Arc, Brave, Edge | AppleScript menjalankan JavaScript kecil di tab YouTube (dicek tiap 2–5 detik selama browser terbuka) | Chrome, Brave, Edge: **View › Developer › Allow JavaScript from Apple Events**. Arc tidak perlu pengaturan ini. Lalu izinkan akses Automation |

MediaRemote (API privat) tidak dipakai karena sudah dibatasi Apple sejak macOS 15.4.

## Tab Dev (utilitas coding)

Ikon `</>` di sisi kanan notch. Isinya:

| Bagian | Fungsi |
| --- | --- |
| Aktivitas | AI agent yang sedang berjalan (Claude Code, Codex, Gemini CLI, Aider, dll.) beserta foldernya, dan riwayat notifikasi dari terminal dan agent |
| Port | Port TCP lokal yang sedang listen (mis. `:3000 node web-app`). Ikon Safari membuka `http://localhost:PORT`; tombol ⓧ (klik dua kali) menghentikan prosesnya |
| Clipboard | 25 teks terakhir yang disalin, hanya di memori (hapus per item dengan ×, atau Hapus Semua). Jenisnya dikenali otomatis (URL, JSON, JWT, UUID, warna hex, timestamp, base64) dengan aksi satu klik. Sematkan (📌) item agar tidak hilang, atau beri label (🏷) seperti "Password database": isinya disamarkan, dan klik label langsung menyalin nilainya |
| Alat | Base64, URL encode/decode, rapikan atau minify JSON, decode JWT, epoch ke tanggal, UUID, waktu sekarang. Bekerja pada isi clipboard dan hasilnya langsung disalin |
| Hash | Ketik atau tempel teks di kolom input, lalu MD5, SHA-1, SHA-256, SHA-512 langsung muncul; klik untuk menyalin |

Alat bekerja pada teks yang ada di clipboard: salin teksnya dulu, lalu klik alatnya. Hash punya kolom input sendiri; selama kolom itu dipakai, panel tetap terbuka sampai Anda klik di luar.

### Notifikasi terminal dan AI agent

1. Buka **Pengaturan › Alat Dev**, klik **Pasang**. Helper akan disalin ke `~/.notchisland/`.
2. Terminal (zsh): tambahkan ke `~/.zshrc`:

   ```sh
   source ~/.notchisland/notchisland.zsh
   ```

   Perintah yang berjalan 10 detik atau lebih akan muncul di bawah notch saat selesai, berwarna hijau kalau berhasil dan merah kalau gagal. Editor, pager, `ssh` dan sejenisnya diabaikan. Atur dengan `NOTCHISLAND_MIN_SECONDS` dan `NOTCHISLAND_IGNORE` sebelum baris `source`.
3. Claude Code: tambahkan blok `hooks` yang bisa disalin dari Pengaturan ke `~/.claude/settings.json`. Island menampilkan saat Claude selesai atau butuh izin atau input.
4. Codex: tambahkan baris `notify = [...]` dari Pengaturan ke `~/.codex/config.toml`.

Klik **Tes** di Pengaturan untuk mencoba. Notifikasi apa pun bisa dikirim dari skrip sendiri:

```sh
~/.notchisland/bin/notchisland-notify -s ok "Deploy selesai" "production"
# -s ok | fail | attention | info
```

Item clipboard yang disematkan atau diberi label disimpan di **Keychain** macOS (item `NotchIsland.pinnedClips`), bukan di file biasa, karena bisa berisi password. Saat item berlabel disalin, clipboard ditandai *concealed* supaya pengelola clipboard lain tidak mencatatnya. Karena build ditandatangani ad-hoc, macOS bisa bertanya sekali setelah build ulang apakah NotchIsland boleh membaca item Keychain itu; pilih **Always Allow**.

Event ditulis sebagai file kecil di `~/.notchisland/inbox`, dibaca lalu dihapus oleh app. Tidak ada data yang dikirim keluar.

## Catatan

- Build ditandatangani ad-hoc, jadi macOS bisa meminta ulang izin kamera/Automation setelah build ulang. Pilih **Personal Team** di Signing & Capabilities agar izin tetap tersimpan.
- Untuk **Buka saat login**, salin app ke `/Applications` dulu, lalu aktifkan dari Pengaturan.
- Data: `~/Library/Application Support/NotchIsland/` (rak file `shelf.json`, salinan file `Files/`, cache lirik `Lyrics/`).

## Status

- [x] Fase 1: panel notch, hover expand/collapse, tidak mencuri fokus
- [x] Fase 2: jam & baterai
- [x] Fase 3: now playing (Spotify, Apple Music, YouTube di Chrome, Arc, Brave, Edge)
- [x] Fase 4: kamera
- [x] Fase 5: file shelf
- [x] Fase 6: lirik (LRCLIB, cache lokal, unit test parser & pencocokan)
- [x] Fase 7: pengaturan, menu bar, buka saat login, lokalisasi id/en
- [x] Fase 8: tab Dev (notifikasi terminal & AI agent, port aktif, clipboard, alat, hash)
