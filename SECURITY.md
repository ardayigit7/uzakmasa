# Güvenlik / Security

UzakMasa bir **uzaktan kontrol** aracıdır: anahtarı bilen kişi bilgisayarını görür ve yönetir.

## Model
- Bu repoda **hiçbir anahtar, adres ya da PIN yoktur**. Herkes kendi Firebase veritabanını ve kendi Vercel sitesini kurar; yazarın (ya da bir başkasının) bilgisayarına bağlanmanın bir yolu yoktur.
- Erişim = **Firebase adresi + 40 karakterlik gizli anahtar** (tarayıcıda rastgele üretilir). Kurallar yalnızca uzunluğu >= 32 olan yolları açar; anahtarı bilmeyen kimse veri okuyamaz/yazamaz.
- Terminal ayrıca **PIN ile imzalıdır** (PBKDF2-SHA256 200.000 tur + HMAC-SHA256, nonce + zaman penceresi). PIN laptopta yalnızca türetilmiş anahtar olarak durur.
- Ajan kendini **kendi** sitenden günceller (`config.json` içindeki `url`). Bu repo ya da yazar uzaktan kod gönderemez.
- Dışarıya tek üçüncü taraf bağlantı: isteğe bağlı bildirim/uyandırma için `ntfy.sh`.

## Sen ne yapmalısın
- "Telefona bağla" bağlantısını ve kurulum komutunu **kimseyle paylaşma** (anahtarı içerir). Sızarsa Ayarlar > "Yeni gizli anahtar üret".
- Terminal PIN'i uzun yap (8+ karakter, harf+rakam) ya da terminali kapalı bırak.
- Kendi Firebase kurallarını README'deki gibi tut; "test mode" (herkese açık) kullanma.
- Windows Defender ekran görüntüsü + fare kontrolü yüzünden uyarabilir; kodu okuyup kendi kararını ver.

## Açık bildirimi
Güvenlik açığı bulursan bir GitHub Issue yerine önce repo sahibine özel olarak (GitHub Security Advisories) bildir.
