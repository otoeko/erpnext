#!/bin/bash

# ERPNext Production Server Setup Script for Hetzner CX43
# Ubuntu 22.04 LTS için optimize edilmiş

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
DOMAIN=${1:-"your-domain.com"}
EMAIL=${2:-"admin@your-domain.com"}
APP_PATH="/opt/erpnext"
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)
FRAPPE_USER_PASSWORD=$(openssl rand -base64 32)

echo -e "${GREEN}🚀 ERPNext Production Server Setup Started${NC}"
echo -e "${YELLOW}Domain: $DOMAIN${NC}"
echo -e "${YELLOW}Email: $EMAIL${NC}"

# Update system
echo -e "${GREEN}📦 Updating system packages...${NC}"
apt update && apt upgrade -y

# Install essential packages
echo -e "${GREEN}📦 Installing essential packages...${NC}"
apt install -y \
    curl \
    wget \
    git \
    unzip \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    ufw \
    fail2ban \
    htop \
    nginx \
    certbot \
    python3-certbot-nginx

# Install Docker
echo -e "${GREEN}🐳 Installing Docker...${NC}"
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Add current user to docker group
usermod -aG docker $USER

# Install Docker Compose (standalone)
echo -e "${GREEN}📦 Installing Docker Compose...${NC}"
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Configure Firewall
echo -e "${GREEN}🔥 Configuring UFW Firewall...${NC}"
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# Configure Fail2Ban
echo -e "${GREEN}🔒 Configuring Fail2Ban...${NC}"
systemctl start fail2ban
systemctl enable fail2ban

# Create application directory
echo -e "${GREEN}📁 Creating application directories...${NC}"
mkdir -p $APP_PATH
mkdir -p $APP_PATH/apps
mkdir -p $APP_PATH/deployment
mkdir -p $APP_PATH/logs
mkdir -p $APP_PATH/backups
mkdir -p $APP_PATH/deployment/nginx/ssl

# Set proper permissions
chown -R $USER:$USER $APP_PATH

# Create MariaDB configuration
echo -e "${GREEN}🗄️ Creating MariaDB configuration...${NC}"
mkdir -p $APP_PATH/deployment/mariadb/conf.d
cat > $APP_PATH/deployment/mariadb/conf.d/my.cnf << 'EOF'
[mysqld]
innodb_file_format=barracuda
innodb_file_per_table=1
innodb_large_prefix=1
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

[mysql]
default-character-set = utf8mb4
EOF

# Create environment file
echo -e "${GREEN}📝 Creating environment configuration...${NC}"
cat > $APP_PATH/.env << EOF
# Database Configuration
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
MYSQL_USER=frappe
MYSQL_PASSWORD=$FRAPPE_USER_PASSWORD
DB_HOST=mariadb
DB_PORT=3306

# Redis Configuration
REDIS_CACHE=redis-cache:6379
REDIS_QUEUE=redis-queue:6379
REDIS_SOCKETIO=redis-socketio:6379

# App Configuration
DOMAIN=$DOMAIN
EMAIL=$EMAIL
SOCKETIO_PORT=9000

# Backup Configuration
BACKUP_RETENTION_DAYS=30
EOF

# Create backup script
echo -e "${GREEN}💾 Creating backup script...${NC}"
cat > $APP_PATH/scripts/backup.sh << 'EOF'
#!/bin/bash

BACKUP_DIR="/opt/erpnext/backups"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=30

# Create backup directory
mkdir -p $BACKUP_DIR

# Backup database
echo "Creating database backup..."
docker exec erpnext_mariadb mysqldump --all-databases -u root -p$MYSQL_ROOT_PASSWORD | gzip > $BACKUP_DIR/database_$DATE.sql.gz

# Backup sites
echo "Creating sites backup..."
docker exec erpnext_backend tar -czf /tmp/sites_backup_$DATE.tar.gz -C /home/frappe/frappe-bench sites
docker cp erpnext_backend:/tmp/sites_backup_$DATE.tar.gz $BACKUP_DIR/
docker exec erpnext_backend rm /tmp/sites_backup_$DATE.tar.gz

# Remove old backups
find $BACKUP_DIR -name "*.gz" -mtime +$RETENTION_DAYS -delete

echo "Backup completed: $DATE"
EOF

chmod +x $APP_PATH/scripts/backup.sh

# Create restore script
cat > $APP_PATH/scripts/restore.sh << 'EOF'
#!/bin/bash

if [ $# -eq 0 ]; then
    echo "Usage: $0 <backup_date> (e.g., 20231201_143000)"
    exit 1
fi

BACKUP_DATE=$1
BACKUP_DIR="/opt/erpnext/backups"

# Restore database
if [ -f "$BACKUP_DIR/database_$BACKUP_DATE.sql.gz" ]; then
    echo "Restoring database..."
    gunzip < $BACKUP_DIR/database_$BACKUP_DATE.sql.gz | docker exec -i erpnext_mariadb mysql -u root -p$MYSQL_ROOT_PASSWORD
fi

# Restore sites
if [ -f "$BACKUP_DIR/sites_backup_$BACKUP_DATE.tar.gz" ]; then
    echo "Restoring sites..."
    docker cp $BACKUP_DIR/sites_backup_$BACKUP_DATE.tar.gz erpnext_backend:/tmp/
    docker exec erpnext_backend tar -xzf /tmp/sites_backup_$BACKUP_DATE.tar.gz -C /home/frappe/frappe-bench
    docker exec erpnext_backend rm /tmp/sites_backup_$BACKUP_DATE.tar.gz
fi

echo "Restore completed"
EOF

chmod +x $APP_PATH/scripts/restore.sh

# Create monitoring script
echo -e "${GREEN}📊 Creating monitoring script...${NC}"
cat > $APP_PATH/scripts/monitor.sh << 'EOF'
#!/bin/bash

# Health check script
check_service() {
    local service=$1
    if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "$service.*Up"; then
        echo "✅ $service is running"
        return 0
    else
        echo "❌ $service is not running"
        return 1
    fi
}

echo "🔍 ERPNext Health Check - $(date)"
echo "=================================="

# Check all services
SERVICES=("erpnext_nginx" "erpnext_backend" "erpnext_frontend" "erpnext_mariadb" "erpnext_redis_cache")
ALL_OK=true

for service in "${SERVICES[@]}"; do
    if ! check_service "$service"; then
        ALL_OK=false
    fi
done

# Check disk space
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ $DISK_USAGE -gt 80 ]; then
    echo "⚠️  Disk usage is high: ${DISK_USAGE}%"
    ALL_OK=false
else
    echo "✅ Disk usage: ${DISK_USAGE}%"
fi

# Check memory usage
MEM_USAGE=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
if [ $MEM_USAGE -gt 85 ]; then
    echo "⚠️  Memory usage is high: ${MEM_USAGE}%"
else
    echo "✅ Memory usage: ${MEM_USAGE}%"
fi

if $ALL_OK; then
    echo "✅ All systems operational"
    exit 0
else
    echo "❌ Some issues detected"
    exit 1
fi
EOF

chmod +x $APP_PATH/scripts/monitor.sh

# Setup cron jobs
echo -e "${GREEN}⏰ Setting up cron jobs...${NC}"
(crontab -l 2>/dev/null; echo "0 2 * * * $APP_PATH/scripts/backup.sh") | crontab -
(crontab -l 2>/dev/null; echo "*/5 * * * * $APP_PATH/scripts/monitor.sh") | crontab -

# Generate SSL certificate placeholder (will be replaced by real cert later)
echo -e "${GREEN}🔐 Creating SSL certificate placeholder...${NC}"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout $APP_PATH/deployment/nginx/ssl/key.pem \
    -out $APP_PATH/deployment/nginx/ssl/cert.pem \
    -subj "/C=TR/ST=State/L=City/O=Organization/CN=$DOMAIN"

# Save passwords to file
echo -e "${GREEN}💾 Saving credentials...${NC}"
cat > $APP_PATH/credentials.txt << EOF
ERPNext Production Server Credentials
====================================
Generated: $(date)

MySQL Root Password: $MYSQL_ROOT_PASSWORD
Frappe User Password: $FRAPPE_USER_PASSWORD

Domain: $DOMAIN
Email: $EMAIL

IMPORTANT: Save these credentials securely and delete this file after noting them down.
EOF

chmod 600 $APP_PATH/credentials.txt

echo -e "${GREEN}✅ Server setup completed successfully!${NC}"
echo -e "${YELLOW}Next steps:${NC}"
echo -e "${YELLOW}1. Update domain DNS to point to this server${NC}"
echo -e "${YELLOW}2. Run: ssl-setup.sh $DOMAIN $EMAIL${NC}"
echo -e "${YELLOW}3. Deploy your ERPNext application${NC}"
echo -e "${YELLOW}4. Credentials saved in: $APP_PATH/credentials.txt${NC}"

# Create SSL setup script
cat > $APP_PATH/scripts/ssl-setup.sh << 'EOF'
#!/bin/bash

DOMAIN=${1:-"your-domain.com"}
EMAIL=${2:-"admin@your-domain.com"}

echo "🔐 Setting up SSL certificate for $DOMAIN"

# Stop nginx temporarily
systemctl stop nginx

# Get SSL certificate
certbot certonly --standalone -d $DOMAIN --email $EMAIL --agree-tos --no-eff-email

# Copy certificates
cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem /opt/erpnext/deployment/nginx/ssl/cert.pem
cp /etc/letsencrypt/live/$DOMAIN/privkey.pem /opt/erpnext/deployment/nginx/ssl/key.pem

# Update nginx config
sed -i "s/YOUR_DOMAIN.COM/$DOMAIN/g" /opt/erpnext/deployment/nginx/conf.d/default.conf

# Start nginx
systemctl start nginx

# Setup auto-renewal
(crontab -l 2>/dev/null; echo "0 12 * * * certbot renew --quiet --post-hook 'systemctl reload nginx'") | crontab -

echo "✅ SSL certificate setup completed"
EOF

chmod +x $APP_PATH/scripts/ssl-setup.sh

echo -e "${GREEN}🎉 Installation completed! Reboot recommended.${NC}"
