# 🖥️ Mac Os ve Unix Yetki Yükseltme ve Güvenlik Denetim Aracı

[![Versiyon](https://img.shields.io/badge/Versiyon-7.0.0-blue?style=flat-square)](https://github.com/vedattascier/mac-os-yetki-yukseltme)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20FreeBSD%20%7C%20OpenBSD%20%7C%20NetBSD-green?style=flat-square)](https://github.com/vedattascier/mac-os-yetki-yukseltme)
[![Lisans](https://img.shields.io/badge/Lisans-MIT-yellow?style=flat-square)](LICENSE)
[![Geliştirici](https://img.shields.io/badge/Geliştirici-Vedat%20Taşçıer-orange?style=flat-square)](https://github.com/vedattascier)

> **Unix/BSD/macOS** tabanlı sistemler için kapsamlı yetki yükseltme ve güvenlik denetim aracı.

## 🚀 Özellikler

### 🔍 Güvenlik Taramaları
- **SUID/SGID Binary Taraması** - GTFOBins entegrasyonu
- **Sudoers Yapılandırma Analizi**
- **Cron & LaunchAgent Kontrolü**
- **Yazılabilir PATH Dizinleri**
- **Kernel Extension Analizi**
- **XPC Servisleri İnceleme**

### 🛡️ Platform Özellikleri
| macOS | BSD Sistemleri |
|-------|----------------|
| SIP Durumu | Jails Tespiti |
| FileVault Kontrolü | Capsicum |
| Gatekeeper | MAC Framework |
| AMFI | Kernel Modülleri |
| T2 Security Chip | rc.d Servisleri |

### ⚡ Gelişmiş Tarama Modları
- `-F` Tam Kapsamlı Analiz
- `-N` Ağ Güvenlik Taraması
- `-D` Derinlemesine Tarama
- `-P` Persistence (Kalıcılık) Taraması
- `-C` CVE Tarama Modu
- `-a` AI Akıllı Analiz
- `-e` Exploit Modu

### 📊 Risk Değerlendirme
- **Otomatik Risk Skoru** (0-100)
- **Zafiyet Sayımı** (Critical/High/Medium/Low)
- **Detaylı Özet Raporu**

### 📝 Raporlama
- **HTML Rapor** (`-r html`)
- **JSON Rapor** (`-r json`)
- **Text Çıktısı**

## 📖 Kullanım

### Temel Kullanım
```bash
chmod +x mac-os-yetki-yükseltme-araci.sh
./mac-os-yetki-yükseltme-araci.sh
```

### Seçenekler
| Parametre | Açıklama |
|-----------|----------|
| `-c` | Renk çıktısını kapat |
| `-f` | Hızlı mod (daha az kontrol) |
| `-q` | Sessiz mod |
| `-v` | Ayrıntılı mod |
| `-o <dosya>` | Çıktıyı dosyaya kaydet |
| `-j` | JSON formatında çıktı |
| `-r html\|json` | Rapor formatı |
| `-i` | İnteraktif mod |
| `-a` | AI akıllı analiz modu |
| `-p` | Paralel tarama |
| `-e` | Exploit modu |
| `-F` | Tam kapsamlı analiz |
| `-N` | Ağ tarama modu |
| `-D` | Derinlemesine tarama |
| `-P` | Persistence taraması |
| `-C` | CVE tarama modu |
| `-V` | Versiyon bilgisi |
| `-h` | Yardım |

### Örnek Kullanımlar
```bash
# Tam kapsamlı analiz
./mac-os-yetki-yükseltme-araci.sh -F

# AI analiz + exploit üret
./mac-os-yetki-yükseltme-araci.sh -a -e

# HTML rapor oluştur
./mac-os-yetki-yükseltme-araci.sh -r html -o rapor.html

# İnteraktif mod
./mac-os-yetki-yükseltme-araci.sh -i

# Hızlı tarama + dosyaya kaydet
./mac-os-yetki-yükseltme-araci.sh -f -v -o sonuc.txt

# Tam analiz + HTML rapor
./mac-os-yetki-yükseltme-araci.sh -F -r html -o rapor.html
```

## 🏗️ Desteklenen Platformlar

- ✅ **macOS** (tüm sürümler)
- ✅ **FreeBSD**
- ✅ **OpenBSD**
- ✅ **NetBSD**

> **Not:** Linux desteği bulunmamaktadır. Bu araç Unix/BSD tabanlı sistemler için tasarlanmıştır.

## 🔒 Güvenlik Kontrolleri

- [x] SIP (System Integrity Protection)
- [x] FileVault Şifreleme
- [x] Gatekeeper
- [x] AMFI (Apple Mobile File Integrity)
- [x] Code Signing
- [x] Kernel Extensions
- [x] LaunchDaemons/Agents
- [x] Docker Socket
- [x] Container Tespiti
- [x] VM Tespiti

## 📦 Kurulum

```bash
# Repoyu klonla
git clone https://github.com/vedattascier/mac-os-yetki-yukseltme.git

# Dizine gir
cd mac-os-yetki-yukseltme

# Çalıştırılabilir yap
chmod +x mac-os-yetki-yükseltme-araci.sh

# Çalıştır
./mac-os-yetki-yükseltme-araci.sh
```

## ⚠️ Yasal Uyarı

> Bu araç **yalnızca yetkili güvenlik testleri** ve **eğitim amaçlı** kullanım için tasarlanmıştır.
> 
> Sadece sahip olduğunuz veya **yazılı izin** aldığınız sistemlerde kullanın.
> 
> Yetkisiz erişim **yasadışıdır** ve cezai yaptırımlara tabidir.
> 
> Kullanımdan doğabilecek her türlü zarardan **kullanıcı sorumludur**.

## 🔗 Faydalı Kaynaklar

- [GTFOBins](https://gtfobins.github.io/) - Binary istismarı
- [PayloadsAllTheThings](https://github.com/swisskyrepo/PayloadsAllTheThings)
- [HackTricks](https://book.hacktricks.xyz/)
- [macOS Exploits](https://github.com/nickvourd/Privilege-Escalation)

## 👨‍💻 Geliştirici

**Vedat Taşçıer**

[![GitHub](https://img.shields.io/badge/GitHub-vedattascier/mac-os-yetki-yukseltme-333?style=flat-square)](https://github.com/vedattascier/mac-os-yetki-yukseltme)
[![Web Sitesi](https://img.shields.io/badge/Web-vedattascier.com-0077B5?style=flat-square)](https://www.vedattascier.com)
[![E-posta](https://img.shields.io/badge/E-posta-vedattascier@hotmail.com-red?style=flat-square)](mailto:vedattascier@hotmail.com)

---

<div align="center">

⭐ Bu projeyi beğendiyseniz yıldız vermeyi unutmayın!

❤️ [vedattascier](https://github.com/vedattascier) tarafından yapıldı

</div>
