# Ada

Claude Code çalışırken ekranın tepesinde, çentiğin altında duran küçük siyah ada. O anda ne yapıldığını ("Düzenliyor · main.swift", "Çalıştırıyor", "Düşünüyor") ve turun süresini gösterir; tur bitince çan çalar, uzun turlarda bütün ekranlar üç kez yanıp söner. Harici monitörde de çalışır: ada farenin olduğu ekrana geçer.

- Üzerine gelince diğer Claude sohbetleri adları, o anki işleri ve süreleriyle alt alta açılır.
- Bir satıra tıklamak Claude masaüstü uygulamasında o sohbeti açar.
- Claude yeniden başlayana kadar son tur "Bitti" olarak kalır.

## Kurulum

```bash
./build.sh --install
```

Uygulama `/Applications/Ada.app` altına kurulur. Dock'ta ve menü çubuğunda görünmez.

Ardından `~/.claude/settings.json` içindeki `hooks` bölümüne şu olaylar için aynı komut eklenir: `UserPromptSubmit`, `PreToolUse` ve `PostToolUse` (matcher `*`), `Notification` (matcher `permission_prompt`), `Stop`, `SessionEnd`.

```json
{ "type": "command", "command": "/Applications/Ada.app/Contents/MacOS/Ada hook", "timeout": 5 }
```

Ada kapalıysa ilk kanca onu kendiliğinden açar.

## Komutlar

- `Ada selftest`: kanca etiketlerini sınar.
- `Ada snapshot dosya.png`: adanın hallerini bir önizleme görseline çizer.
- `Ada title <oturum-kimliği>`: o oturumun Claude uygulamasındaki adını yazar.

macOS 14 ve sonrası, Apple Silicon.
