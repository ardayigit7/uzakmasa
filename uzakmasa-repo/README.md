# UzakMasa

Telefonundan Windows bilgisayarını uzaktan gör ve yönet: canlı ekran, fare/klavye, dosya gönderme-alma, pano, uygulamalar, ses/parlaklık, PIN korumalı terminal, pil bildirimi.

**Sunucun yok, uygulama mağazası yok.** Panel bir web sayfası (Vercel), aradaki köprü senin Firebase veritabanın, bilgisayarda ise bağımlılıksız küçük bir PowerShell ajanı çalışır.

> English: a phone web panel (Vercel + Firebase Realtime Database) that controls your own Windows PC through a zero-dependency PowerShell 5.1 agent. You host everything yourself; this repo contains no keys, URLs or PINs.

```
Telefon (web paneli)  <->  SENİN Firebase veritabanın  <->  Windows ajanı (PowerShell)
```

## ⚠️ Önce oku
Bu bir uzaktan kontrol aracıdır. Gizli anahtarı bilen biri bilgisayarını görür ve yönetir.
- Bu repoda **anahtar, veritabanı adresi, site adresi ya da PIN yok**. Herkes kendi kurulumunu yapar; kimse başkasının bilgisayarına bu koddan bağlanamaz.
- Kendi bilgisayarların için kullan. Başkasının bilgisayarına izinsiz kurmak suçtur.
- Ayrıntılar: [SECURITY.md](SECURITY.md)

## Özellikler
- Canlı ekran (~10 fps, dokununca otomatik hızlanır), pinch zoom, fare ve canlı klavye (Türkçe karakterler dahil)
- Dosya gönder/indir (100 MB'a kadar, parçalı), uzaktaki klasörlere göz at
- Pano aktarımı, açık uygulamaları görme/kapatma, uygulama başlatma
- Ses, parlaklık, kilitle / yeniden başlat / kapat
- PIN ile imzalı terminal (isteğe bağlı)
- Pil düşünce / bilgisayar uyanınca telefona bildirim (ntfy, isteğe bağlı)
- Birden çok bilgisayar

## Yapay zekayla kurulum (en kolay yol)
Claude, ChatGPT ya da Gemini gibi bir yapay zekaya bu repoyu verip kurulumu adım adım yaptırabilirsin. Aşağıdakini kopyalayıp yapıştır (`REPO-ADRESİ` yerine bu sayfanın adresini yaz):

```
REPO-ADRESİ adresindeki UzakMasa projesini kurmak istiyorum. README'yi oku ve beni
adım adım yönlendir: Firebase Realtime Database kurulumu ve kuralları, Vercel'e
"web" klasörünü Root Directory yaparak deploy etmek, sonra bilgisayarıma ajanı
eklemek. Her adımı tek tek ver, ben yapıp sonucu yazayım. Hiçbir anahtarı, şifreyi
ya da PIN'i senden isteme ve ben de sana vermeyeceğim; onları sadece kendi
tarayıcımda/bilgisayarımda gireceğim.
```

Önemli: yapay zekaya **gizli anahtarı, "Telefona bağla" bağlantısını, kurulum komutunu ve PIN'ini yapıştırma**. Bunlar bilgisayarına tam erişim verir. Sana sadece nereye tıklayacağını anlatması yeter.

## Kurulum (yaklaşık 10 dakika)

### 1) Firebase veritabanı
1. [console.firebase.google.com](https://console.firebase.google.com) → proje oluştur.
2. **Build → Realtime Database → Create database** ("locked mode").
3. Panel ilk açılışta sana **kuralları** gösterir; **Rules** sekmesine yapıştırıp **Publish** de. (Kurallar yalnızca 32+ karakterlik gizli yolu bilenlere izin verir.)
4. Veritabanı adresini not al (`https://….firebasedatabase.app`).

### 2) Paneli Vercel'e koy
1. Bu repoyu fork'la (ya da indir) ve [vercel.com](https://vercel.com)'da **Add New → Project** ile içe aktar.
2. **Root Directory = `web`**, framework "Other", build komutu yok. Deploy.
3. Sitenin adresini aç, Firebase adresini yapıştır. Tarayıcın otomatik 40 karakterlik rastgele gizli anahtar üretir.

### 3) Bilgisayarı ekle
Panelde **Bilgisayar ekle** → çıkan komutu eklemek istediğin Windows bilgisayarda PowerShell'e yapıştır. Ajan kurulur, açılışta kendiliğinden başlar, birkaç saniye içinde panelde görünür. Ajan güncellemeyi **senin** sitenden çeker (sürüm numarası artınca).

### 4) Telefona bağla
Panelde **Telefona bağla** bağlantısını kendine gönder ve telefonda aç. iPhone'da "Ana Ekrana Ekle" ile uygulama gibi kullanabilirsin. **Bu bağlantıyı kimseyle paylaşma.**

### 5) (İsteğe bağlı) Terminal
Bilgisayarda `tools/Terminal-PIN.cmd` çalıştır, PIN belirle (8+ karakter). Telefonda Terminal'i açıp aynı PIN'i gir. PIN'i boş bırakırsan terminal tamamen kapanır.

## Kaldırma
Panelde **Bilgisayar ekle → Bilgisayardan kaldırma komutu**nu o bilgisayarda çalıştır. Gizli anahtarı değiştirmek için Ayarlar → "Yeni gizli anahtar üret".

## Klasörler
| Yol | Ne |
|---|---|
| `web/` | Vercel'e giden panel + ajan dosyaları (`agent.ps1`, `install.ps1`, `send.ps1` buradan sunulur) |
| `tools/` | Bilgisayarda çalıştırılan yardımcılar (Terminal PIN ayarı) |

## Bilinen sınırlar
- Ekran gerçek video akışı değil, JPEG kare akışıdır (ses yok).
- Yalnızca ana ekran (çoklu monitör yok), yalnızca Windows 10/11 + PowerShell 5.1.
- Windows Defender ekran görüntüsü + fare kontrolü yüzünden uyarabilir; kod açık, okuyup karar ver.
- Bilgisayar uykudayken uzaktan uyandırma ayrı, elle kurulan bir "Nöbet" görevi gerektirir (bu repoda hazır değil).

## Lisans
MIT — bkz. [LICENSE](LICENSE). Hiçbir garanti verilmez; kendi sorumluluğunda kullan.
