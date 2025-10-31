# 🚀 ERPNext GitHub Actions Deployment

Hetzner CX43 sunucusu için GitHub Actions ile otomatik ERPNext deployment.

## 📋 Gereksinimler

- **Sunucu**: Hetzner CX43 (16GB RAM, 4 vCPU, 320GB SSD)
- **İşletim Sistemi**: Ubuntu 22.04 LTS
- **Domain**: Sunucunuza yönlendirilmiş bir domain adı
- **GitHub Repository**: https://github.com/otoeko/erpnext

## ⚡ Kurulum

### 1. Sunucu Hazırlığı

```bash
# SSH ile sunucunuza bağlanın
ssh root@YOUR_SERVER_IP

# Server setup scriptini çalıştırın
wget https://raw.githubusercontent.com/otoeko/erpnext/main/scripts/server-setup.sh
chmod +x server-setup.sh
./server-setup.sh your-domain.com admin@your-domain.com
```

### 2. SSH Key Oluşturma

Windows'ta **Git Bash** açın:

```bash
# SSH key oluştur
ssh-keygen -t rsa -b 4096 -C "erpnext-deployment"
# Enter, Enter, Enter (tüm varsayılanları kabul et)

# Public key'i kopyala
cat ~/.ssh/id_rsa.pub
```

### 3. Public Key'i Sunucuya Ekle

```bash
# SSH ile sunucuya bağlan
ssh root@YOUR_SERVER_IP

# Key'i authorized_keys'e ekle
mkdir -p ~/.ssh
echo "YOUR_PUBLIC_KEY_CONTENT" >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
exit
```

### 4. GitHub Secrets Ayarla

**https://github.com/otoeko/erpnext** → **Settings** → **Secrets and variables** → **Actions**

**3 Secret ekle:**

1. **SERVER_HOST**: Hetzner sunucu IP'si
2. **SERVER_USER**: `root`
3. **SSH_KEY**: Private key tamamı (`cat ~/.ssh/id_rsa` çıktısı)

### 5. İlk Deployment

```bash
# Repository'yi clone et
git clone https://github.com/otoeko/erpnext.git
cd erpnext

# Push et - OTOMATIK DEPLOYMENT BAŞLAR!
git push origin main
```

## 🚀 Kullanım

**Her kod değişikliğinde:**

```bash
# Kod değiştir
git add .
git commit -m "New feature"
git push origin master  # ← OTOMATIK DEPLOY + VERSİYON ARTISI!
```

**Otomatik Versiyonlama:**
- Her `git push` → Versiyon otomatik artar (1.0.0 → 1.0.1 → 1.0.2...)
- GitHub Actions otomatik versiyon commit'i yapar
- [skip ci] etiketi ile sonsuz döngü önlenir

**Deployment takibi:**
- GitHub → **Actions** sekmesi
- Her adımı canlı takip
- Version history görüntüle

## 📁 Proje Yapısı

```
erpnext-develop/
├── .github/workflows/
│   └── deploy.yml              # CI/CD pipeline
├── deployment/
│   ├── docker-compose.prod.yml # Production container config
│   └── nginx/
│       └── conf.d/
│           └── default.conf    # Nginx konfigürasyonu
├── scripts/
│   ├── server-setup.sh         # Sunucu kurulum scripti
│   ├── local-dev-setup.sh      # Local development setup
│   └── ssl-setup.sh            # SSL kurulum scripti
├── erpnext/                    # ERPNext uygulaması
└── DEPLOYMENT-GUIDE.md         # Bu dosya
```

## 🔧 Detaylı Kurulum Adımları

### Adım 1: Sunucu Hazırlığı

Server setup scripti şunları yapar:
- ✅ Docker ve Docker Compose kurulumu
- ✅ Firewall (UFW) konfigürasyonu
- ✅ Fail2Ban güvenlik ayarları
- ✅ MariaDB ve Redis ayarları
- ✅ Otomatik backup sistemi
- ✅ Monitoring ve log sistemi

### Adım 2: Deployment Konfigürasyonu

`deployment/docker-compose.prod.yml` dosyası production için optimize edilmiş:
- **Nginx**: Reverse proxy ve load balancer
- **ERPNext Backend**: Python/Frappe uygulaması
- **ERPNext Frontend**: Node.js/Vue.js arayüzü
- **MariaDB**: Veritabanı
- **Redis**: Cache ve queue sistemi
- **Workers**: Background job işlemcileri

### Adım 3: CI/CD Pipeline

`.github/workflows/deploy.yml` otomatik deployment sağlar:
- ✅ Code push'ta otomatik deployment
- ✅ Health check ve rollback
- ✅ Zero-downtime deployment
- ✅ Automatic cache clearing

## 🔐 Güvenlik Özellikleri

- **SSL/TLS**: Let's Encrypt ile otomatik SSL
- **Firewall**: Sadece 22, 80, 443 portları açık
- **Fail2Ban**: Brute force saldırı koruması
- **Docker Network**: İzole edilmiş container network
- **Nginx Security Headers**: XSS, CSRF koruması

## 📊 Monitoring ve Backup

### Otomatik Backup
- **Frequency**: Günlük 02:00
- **Retention**: 30 gün
- **Content**: Veritabanı + site dosyaları
- **Location**: `/opt/erpnext/backups/`

### Health Monitoring
- **Frequency**: Her 5 dakika
- **Checks**: Service status, disk, memory
- **Script**: `/opt/erpnext/scripts/monitor.sh`

### Log Yönetimi
- **Application Logs**: Docker container logları
- **System Logs**: `/opt/erpnext/logs/`
- **Nginx Logs**: `/var/log/nginx/`

## 🛠️ Maintenance Komutları

```bash
# Production sunucuda servis durumunu kontrol et
docker-compose -f /opt/erpnext/deployment/docker-compose.prod.yml ps

# Logları görüntüle
docker-compose -f /opt/erpnext/deployment/docker-compose.prod.yml logs -f

# Cache temizle
docker-compose -f /opt/erpnext/deployment/docker-compose.prod.yml exec erpnext-python bench --site all clear-cache

# Backup yap
/opt/erpnext/scripts/backup.sh

# Backup restore et
/opt/erpnext/scripts/restore.sh 20231201_143000

# Health check
/opt/erpnext/scripts/monitor.sh

# SSL sertifikasını yenile
certbot renew
```

## 🚨 Troubleshooting

### Container çalışmıyor
```bash
# Servis durumunu kontrol et
docker-compose -f /opt/erpnext/deployment/docker-compose.prod.yml ps

# Logları incele
docker-compose -f /opt/erpnext/deployment/docker-compose.prod.yml logs CONTAINER_NAME

# Servisi yeniden başlat
docker-compose -f /opt/erpnext/deployment/docker-compose.prod.yml restart
```

### SSL Sertifikası Sorunu
```bash
# Sertifika durumunu kontrol et
certbot certificates

# Manuel yenileme
certbot renew --dry-run

# Nginx konfigürasyonunu test et
nginx -t
```

### Veritabanı Bağlantı Sorunu
```bash
# MariaDB durumunu kontrol et
docker exec erpnext_mariadb mysql -u root -p -e "SHOW DATABASES;"

# Container restart
docker-compose -f /opt/erpnext/deployment/docker-compose.prod.yml restart mariadb
```

### Performance Sorunları
```bash
# Resource kullanımını kontrol et
docker stats

# Disk kullanımını kontrol et
df -h

# Memory kullanımını kontrol et
free -h

# Process listesi
htop
```

## 📈 Scaling ve Optimization

### Horizontal Scaling
```bash
# Worker sayısını artır
docker-compose -f /opt/erpnext/deployment/docker-compose.prod.yml scale erpnext-worker-default=3
```

### Performance Tuning
```bash
# MariaDB optimizasyonu
# /opt/erpnext/deployment/mariadb/conf.d/my.cnf dosyasını edit et

# Redis memory limit
# docker-compose.yml'de Redis için memory limit ayarla
```

## 🆘 Destek ve İletişim

Sorunlar için:
1. **GitHub Issues**: Repository issues bölümü
2. **ERPNext Community**: https://discuss.frappe.io
3. **Documentation**: https://frappeframework.com/docs

---

## 🔄 Version Management & Rollback

### Otomatik Versioning (Her Push'ta)
```bash
# Patch version (1.0.0 -> 1.0.1)
npm run version:patch
# veya
./scripts/version-manager.sh patch

# Minor version (1.0.0 -> 1.1.0)
npm run version:minor

# Major version (1.0.0 -> 2.0.0)
npm run version:major
```

### Rollback İşlemleri
```bash
# Mevcut versiyonları listele
./scripts/version-manager.sh list SERVER_IP root

# İnteraktif rollback
./scripts/version-manager.sh rollback SERVER_IP root

# Belirli versiyona rollback
./scripts/version-manager.sh rollback-to 1.2.5 SERVER_IP root

# NPM ile rollback
npm run rollback SERVER_IP root
```

### Backup Yönetimi
```bash
# Eski backup'ları temizle
./scripts/version-manager.sh cleanup SERVER_IP root

# Manuel backup
/opt/erpnext/scripts/backup.sh
```

## ⚡ Quick Reference

| Komut | Açıklama |
|-------|----------|
| `npm run version:patch` | Patch version oluştur ve deploy |
| `npm run rollback SERVER_IP` | İnteraktif rollback |
| `./scripts/direct-sync.sh SERVER_IP` | Hızlı deployment |
| `./scripts/watch-and-sync.sh SERVER_IP` | Auto-watch mode |
| `docker-compose ps` | Container durumu |
| `docker-compose logs -f` | Live loglar |
| `certbot renew` | SSL yenile |
| `/opt/erpnext/scripts/monitor.sh` | Health check |

### 🚀 Workflow Örnekleri

**Normal Development:**
```bash
# 1. Kod değiştir
# 2. Test et
npm run deploy:watch SERVER_IP  # Auto-sync mode

# 3. Memnun kalınca version oluştur
npm run version:patch           # Otomatik deployment

# 4. Sorun varsa rollback
npm run rollback SERVER_IP
```

**Emergency Rollback:**
```bash
# Son versiyona dön
./scripts/version-manager.sh rollback-to 1.2.3 SERVER_IP root

# Health check
./scripts/test-deployment.sh SERVER_IP
```

---

**🎉 Tebrikler! ERPNext production sunucunuz hazır!**

Site adresiniz: `https://your-domain.com`
Admin paneli: `https://your-domain.com/app`
