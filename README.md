# Gone-Phishing: Advanced Phishing Toolkit

![EvilGophish Logo](https://img.shields.io/badge/EvilGophish-Phishing%20Toolkit-red?style=for-the-badge&logo=github)  
[![GitHub Stars](https://img.shields.io/github/stars/fin3ss3g0d/evilgophish?style=social)](https://github.com/fin3ss3g0d/evilgophish)  
[![Docker](https://img.shields.io/badge/Docker-Ready-blue?logo=docker)](https://www.docker.com/)  
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)  
![Warning](https://img.shields.io/badge/Warning-Authorized%20Use%20Only-yellow)  

## 📋 Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Detailed Setup](#detailed-setup)
- [Configuration](#configuration)
- [Usage Guide](#usage-guide)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)
- [Contributing](#contributing)

## 🚀 Overview

**Gone-Phishing** is a comprehensive Docker-based phishing simulation platform that combines the power of evilginx3 for advanced phishing proxy capabilities with GoPhish's campaign management and tracking features. This integration provides a complete solution for authorized security testing with MFA bypass capabilities, real-time monitoring, and detailed analytics.

**Key Components**:
- **evilginx3**: Advanced phishing proxy with session capture
- **GoPhish**: Campaign management and statistics
- **evilfeed**: Real-time event monitoring dashboard
- **nginx**: Reverse proxy for external access

## 🏗️ Architecture

### Infrastructure Layout
```
Internet Users
     ↓
   nginx (80/443)
     ↓
  evilginx (phishing proxy)
     ↓
  GoPhish (campaign stats)
     ↓
  evilfeed (real-time events)
```

### Service Ports
- **External**: 80/443 (phishing traffic via nginx)
- **Internal**: 
  - GoPhish Admin: 127.0.0.1:3333
  - evilfeed: 127.0.0.1:1337
  - GoPhish Phish: 127.0.0.1:8080

### Data Persistence
```yaml
Volumes:
  - gophish_data: Campaigns, templates, database
  - evilginx_data: Phishlets, configurations
  - evilfeed_data: Event logs and feeds
  - uploads: CSV files, HTML templates
  - ssl: TLS certificates
  - logs: Application logs
```

## ⚡ Quick Start

### Prerequisites
- Docker and Docker Compose
- Ubuntu 20.04+ or similar Linux distribution
- Domain name with DNS control
- Basic understanding of phishing concepts

### Automated Setup
```bash
# Clone the repository
git clone https://github.com/fin3ss3g0d/evilgophish.git
cd evilgophish

# Run interactive setup
chmod +x setup.sh
./setup.sh
```

### Manual Configuration
```bash
# Custom domain and parameters
./setup.sh \
  "your-domain.com" \
  "login support email" \
  true \
  true \
  "custom_param" \
  "twilio_sid" \
  "twilio_token" \
  "+1234567890" \
  "turnstile_public" \
  "turnstile_private" \
  "smtp_user" \
  "smtp_pass"
```

## 🔧 Detailed Setup

### Environment Configuration
The setup script creates a comprehensive `.env` file:

```bash
# Example .env configuration
DOMAIN=amazon-u.com
SUBDOMAINS=login support email admin
PROXY_ROOT=true
FEED_ENABLED=true
RID_REPLACEMENT=user_id
TWILIO_ACCOUNT_SID=your_twilio_sid
TWILIO_AUTH_TOKEN=your_twilio_token
TWILIO_PHONE=+1234567890
TURNSTILE_PUBLIC=your_turnstile_public
TURNSTILE_PRIVATE=your_turnstile_private
SMTP_USER=your_smtp_user
SMTP_PASS=your_smtp_pass
```

### DNS Configuration
For local testing, the setup script automatically adds entries to `/etc/hosts`:
```
127.0.0.1 amazon-u.com login.amazon-u.com support.amazon-u.com email.amazon-u.com admin.amazon-u.com
```

For production, configure your domain's DNS to point to your server's IP address.

### SSL Certificate Setup
The system supports both self-signed and Let's Encrypt certificates:

```bash
# Self-signed (development)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout nginx/ssl/privkey.pem \
  -out nginx/ssl/fullchain.pem \
  -subj "/CN=amazon-u.com"

# Let's Encrypt (production - commented in setup)
# certbot certonly --standalone -d amazon-u.com
```

## ⚙️ Configuration

### GoPhish Configuration
```json
{
  "admin_server": {
    "listen_url": "0.0.0.0:3333",
    "use_tls": false
  },
  "phish_server": {
    "listen_url": "127.0.0.1:8080",
    "use_tls": false
  },
  "db_name": "sqlite3",
  "db_path": "data/gophish.db"
}
```

### Nginx Configuration
The nginx proxy handles SSL termination and routes traffic to evilginx:

```nginx
server {
    listen 443 ssl http2;
    server_name _;
    ssl_certificate /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;
    
    location / {
        proxy_pass https://evilginx/;
        proxy_set_header Host $host;
        proxy_ssl_verify off;
    }
}
```

### Cloudflare Turnstile Integration
**What**: Bot protection using Cloudflare's Turnstile service  
**Why**: Provides advanced bot detection without IP-based blacklists  
**How**: Integrate Turnstile keys into evilginx configuration

1. Create a Turnstile site in Cloudflare dashboard
2. Add public and private keys to your `.env` file
3. Customize the challenge template in `evilginx/templates/turnstile.html`

Example template:
```html
<!DOCTYPE html>
<html>
<head>
    <title>Security Check</title>
    <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
</head>
<body>
    <h1>Verify You're Human</h1>
    <form action="{{.FormActionURL}}" method="POST">
        <div class="cf-turnstile" data-sitekey="{{.TurnstilePublicKey}}"></div>
        {{if .ErrorMessage}}<p style="color:red;">{{.ErrorMessage}}</p>{{end}}
        <button type="submit">Continue</button>
    </form>
</body>
</html>
```

## 📊 Usage Guide

### Email Campaign Setup

**What**: Create and launch phishing email campaigns  
**Why**: Track user interactions and credential capture  
**How**: Use GoPhish web interface with evilginx integration

1. **Access GoPhish Interface**: http://localhost:3333 (admin/gophish)
2. **Create Sending Profile**: Configure SMTP settings
3. **Upload Target Groups**: CSV with email addresses
4. **Create Email Template**: Use {{.URL}} for phishing links
5. **Configure Landing Page**: Point to evilginx lure URL
6. **Launch Campaign**: Monitor results in real-time

### SMS Campaign Setup

**What**: Send phishing messages via Twilio integration  
**Why**: Bypass email filters and reach mobile users  
**How**: Configure Twilio credentials and SMS templates

```bash
# Twilio configuration in .env
TWILIO_ACCOUNT_SID=your_account_sid
TWILIO_AUTH_TOKEN=your_auth_token
TWILIO_PHONE=+1234567890
```

### QR Code Campaigns

**What**: Generate QR codes for physical phishing  
**Why**: Combine digital and physical social engineering  
**How**: Use {{.QR}} placeholder in email templates

```html
<!-- Example QR code in template -->
<img src="{{.QR}}" alt="Scan QR Code" width="250" height="250">
```

### Real-time Monitoring

**What**: Live event feed for campaign monitoring  
**Why**: Immediate visibility into campaign activity  
**How**: Access evilfeed dashboard at http://localhost:1337

## 🔒 Security Considerations

### Operational Security (OpSec)
- Use VPN for administrative access
- Regularly rotate domains and certificates
- Monitor for detection and blacklisting
- Use dedicated infrastructure for testing

### Data Protection
- Encrypt sensitive data at rest
- Secure API keys and credentials
- Implement log rotation and monitoring
- Regular backups of campaign data

### Legal Compliance
- **Authorization Required**: Obtain written permission for testing
- **Scope Limitation**: Test only approved systems and users
- **Data Handling**: Securely delete captured data after testing
- **Reporting**: Provide comprehensive results to stakeholders

## 🛠️ Best Practices

### Volume Management
```bash
# Backup volumes
docker volume export gophish_data > gophish_backup.tar

# Restore volumes
docker volume create gophish_data
docker volume import gophish_data gophish_backup.tar

# Cleanup unused volumes
docker volume prune
```

### Performance Optimization
- Monitor resource usage with `docker stats`
- Adjust nginx worker processes for high traffic
- Implement log rotation to prevent disk filling
- Use resource limits in docker-compose for shared environments

### Maintenance Procedures
```bash
# Update the application
cd src && git pull origin main
docker-compose down
docker-compose build --no-cache
docker-compose up -d

# Check service health
docker-compose ps
docker-compose logs -f nginx
```

## 🐛 Troubleshooting

### Common Issues

**Port Conflicts**:
```bash
# Check what's using ports 80/443
sudo lsof -i :80
sudo lsof -i :443

# Stop conflicting services
sudo systemctl stop apache2 nginx
```

**DNS Resolution**:
```bash
# Test domain resolution
ping amazon-u.com
nslookup amazon-u.com

# Check /etc/hosts entries
cat /etc/hosts
```

**Container Issues**:
```bash
# Check container status
docker-compose ps

# View logs
docker-compose logs -f evilginx
docker-compose logs -f gophish

# Restart services
docker-compose restart evilginx
```

### Debugging Techniques

**Interactive Shell Access**:
```bash
docker exec -it evilginx /bin/sh
docker exec -it gophish /bin/sh
```

**Database Inspection**:
```bash
docker exec -it gophish sqlite3 /app/data/gophish.db
.tables
SELECT * FROM campaigns;
```

**Network Testing**:
```bash
# Test internal connectivity
docker exec evilginx ping gophish
docker exec gophish curl http://evilfeed:1337
```

## 📈 Monitoring and Analytics

### GoPhish Dashboard
- Campaign performance metrics
- Email open and click rates
- Credential capture statistics
- Timeline of user interactions

### Evilfeed Real-time Events
- Live session captures
- Immediate credential submissions
- Real-time campaign activity
- WebSocket-based updates

### Log Analysis
```bash
# Monitor nginx access logs
docker-compose logs -f nginx | grep -v healthcheck

# Analyze evilginx sessions
docker exec evilginx tail -f /app/logs/sessions.log

# Check application errors
docker-compose logs | grep -i error
```

## 🔄 Advanced Features

### Custom Phishlets
**What**: Site-specific phishing configurations  
**Why**: Target specific services and applications  
**How**: Create YAML files in `evilginx/phishlets/` directory

Example phishlet structure:
```yaml
name: "example"
author: "your-name"
min_ver: "3.0"
proxy_hosts:
  - {phish_sub: "login", orig_sub: "www", domain: "target.com", session: true}
auth_tokens:
  - domain: "target.com"
    keys: ["session_token", "user_id"]
```

### RID Parameter Customization
**What**: Replace default tracking parameter  
**Why**: Avoid detection and customize URLs  
**How**: Use the RID replacement script

```bash
# Replace default 'rid' parameter
./replace_rid.sh rid custom_param

# Verify changes
grep -r "custom_param" src/
```

### Template Customization
**What**: Modify phishing email and page templates  
**Why**: Increase credibility and engagement  
**How**: Edit files in `uploads/` directory

## 🤝 Contributing

### Development Setup
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

### Contribution Areas
- New phishlet configurations
- Template improvements
- Documentation enhancements
- Bug fixes and optimizations

### Support Channels
- **GitHub Issues**: Bug reports and feature requests
- **Documentation**: Wiki and README updates
- **Community**: Discussions and knowledge sharing

## 📝 License and Disclaimer

### License
This project is licensed under the MIT License - see the LICENSE file for details.

### Important Disclaimer
**This tool is designed for authorized security testing only. Usage of this tool for attacking targets without prior mutual consent is illegal. It is the end user's responsibility to obey all applicable local, state, and federal laws. Developers assume no liability and are not responsible for any misuse or damage caused by this program.**

### Responsible Usage
- Always obtain proper authorization before testing
- Clearly define scope and rules of engagement
- Respect privacy and data protection laws
- Provide comprehensive reports to stakeholders
- Securely dispose of captured data after testing

---

**EvilGophish** provides a powerful platform for security professionals to conduct comprehensive phishing simulations. When used responsibly and ethically, it can significantly enhance organizational security awareness and defenses.

For the latest updates and detailed documentation, always refer to the official repository and release notes.