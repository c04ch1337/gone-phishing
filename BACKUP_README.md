# EvilGophish

![EvilGophish Logo](https://img.shields.io/badge/EvilGophish-Phishing%20Toolkit-red?style=for-the-badge&logo=github)  
[![GitHub Stars](https://img.shields.io/github/stars/fin3ss3g0d/evilgophish?style=social)](https://github.com/fin3ss3g0d/evilgophish)  
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)  
[![Docker Pulls](https://img.shields.io/docker/pulls/alpine.svg)](https://hub.docker.com/_/alpine)  
![Warning](https://img.shields.io/badge/Warning-Authorized%20Use%20Only-yellow)  

**What**: Dockerized evilginx3, GoPhish, and docker-mailserver for phishing simulations on Lightsail (3.147.37.21).  
**Why**: MFA bypass, campaign tracking, email/SMS, and custom SMTP (support@amazon-u.online).  
**How**: Deploy on Ubuntu with `setup.sh`; manage DNS in Lightsail/GoDaddy.

![Avatar](https://avatars.githubusercontent.com/u/12345678?s=100) – Developer Avatar  
![Logo](https://via.placeholder.com/150?text=EvilGophish) – Logo Placeholder

## 📜 Table of Contents

- [A Word About Sponsorship](#a-word-about-sponsorship)
- [Credits](#credits)
- [Prerequisites](#prerequisites)
- [Disclaimer](#disclaimer)
- [Why?](#why)
- [Background](#background)
- [Infrastructure Layout](#infrastructure-layout)
- [Setup](#setup)
- [Docker SMTP Solution](#docker-smtp-solution)
- [Cloudflare Turnstile Setup](#cloudflare-turnstile-setup)
- [Replace RID](#replace-rid)
- [Email Campaign Setup](#email-campaign-setup)
- [QR Code Generator](#qr-code-generator)
- [SMS Campaign Setup](#sms-campaign-setup)
- [Live Feed Setup](#live-feed-setup)
- [A Word About Phishlets](#a-word-about-phishlets)
- [A Word About The Evilginx3 Update](#a-word-about-the-evilginx3-update)
- [Debugging](#debugging)
- [Installation Notes](#installation-notes)
- [A Note About Campaign Testing And Tracking](#a-note-about-campaign-testing-and-tracking)
- [A Note About The Blacklist and Tracking](#a-note-about-the-blacklist-and-tracking)
- [Changes to GoPhish](#changes-to-gophish)
- [Changelog](#changelog)
- [Issues and Support](#issues-and-support)
- [Future Goals](#future-goals)
- [Contributing](#contributing)

## A Word About Sponsorship

**What**: Public version lags behind sponsored.  
**Why**: Funds development; latest features for sponsors.  
**How**: Join via GitHub Sponsors.

## Credits

**What**: Thanks to Kuba Gretzky (evilginx3), Jordan Wright (GoPhish), docker-mailserver team.  
**Why**: Core components enable this toolkit.  
**How**: Custom integration with SMTP enhancements.

## Prerequisites

**What**: Docker, Git, Ubuntu 22.04 on Lightsail (3.147.37.21), GoDaddy domain (amazon-u.online).  
**Why**: Containerized setup; tested OS; custom email.  
**How**: Install Docker: `curl -fsSL https://get.docker.com | sudo sh`. Basic phishing/DNS knowledge.

## Disclaimer

**What**: Authorized pentesting only.  
**Why**: Legal/ethical compliance.  
**How**: Obtain written permission.

## Why?

**What**: Adds tracking, GUI, email/SMS, and custom SMTP to evilginx3.  
**Why**: Full social engineering toolkit with reliable sending.  
**How**: GoPhish for campaigns/stats, evilginx for proxy, mailserver for emails.

## Background

**What**: GoPhish sends/tracks, evilginx lands/phishes, mailserver sends from support@amazon-u.online.  
**Why**: MFA bypass with stats; owned email domain.  
**How**: Links to evilginx; emails via internal SMTP.

![Diagram](https://via.placeholder.com/600x300?text=Infrastructure+Diagram) – Placeholder

## Infrastructure Layout

**What**: evilginx (443), GoPhish (3333/8080 local), evilfeed (1337 local), mailserver (25/465/587), nginx proxy.  
**Why**: Secure external access; internal tools; reliable mail.  
**How**: Docker network; volumes for data.

## Setup

**What**: Run `setup.sh` to configure services, DNS, and SMTP.  
**Why**: Automates Docker, configs, mail user, DKIM.  
**How**: `./setup.sh amazon-u.online "support email reset admin" true true user_id <twilio_sid> <twilio_token> <twilio_phone> "" "" support@amazon-u.online <smtp_pass>`  
**Example**: Deploy on Lightsail; access GoPhish at `localhost:3333`.  
**Use Case**: Test phishing campaign with custom domain.

### Lightsail DNS Setup
1. **Create Zone**: Lightsail > Networking > Domains & DNS > Create DNS zone > `amazon-u.online` > Third-party registrar.  
2. **Delegate at GoDaddy**: Go to GoDaddy > DNS > Nameservers > Custom > Enter Lightsail NS (e.g., `ns-123.awsdns-45.com`).  
3. **Add Records** (Lightsail > Domains & DNS > `amazon-u.online`):
   - A: `@` -> `3.147.37.21`
   - A: `support`, `email`, `reset`, `admin`, `mail` -> `3.147.37.21`
   - CNAME: `www` -> `amazon-u.online`
   - MX: `@` -> `10 mail.amazon-u.online`
   - TXT: `@` -> `v=spf1 mx a ip4:3.147.37.21 ~all`
   - TXT: `mail._domainkey` -> (from `./mailconfig/opendkim/keys/amazon-u.online/mail.txt`)
   - TXT: `_dmarc` -> `v=DMARC1; p=quarantine; rua=mailto:dmarc@amazon-u.online; ruf=mailto:dmarc@amazon-u.online; fo=1; pct=100`
4. **Verify**: `dig A amazon-u.online`, `dig MX amazon-u.online`, `dig TXT mail._domainkey.amazon-u.online`.

### Lightsail Firewall
Open ports in Lightsail > Instances > Networking > Add rule:
- TCP 80/443: For nginx/evilginx (0.0.0.0/0).
- TCP 25/465/587: For mailserver (0.0.0.0/0; request port 25 throttle removal).
- TCP 3333/1337: GoPhish/evilfeed (127.0.0.1/32 or your IP).
- TCP 22: SSH (restrict to your IP).

**Port 25 Throttle**: Submit request at [AWS Port 25 Removal](https://portal.aws.amazon.com/gp/aws/html-forms-controller/contactus/ec2-email-limit-rdns-request):
- IP: `3.147.37.21`
- rDNS: `mail.amazon-u.online`
- Justification: "Legitimate email server for authorized pentesting; low volume; SPF/DKIM/DMARC configured."

## Docker SMTP Solution

**What**: docker-mailserver for sending from `support@amazon-u.online`.  
**Why**: Long-term, reliable email relay; avoids external provider limits.  
**How**: Integrated in compose; setup.sh adds user, generates DKIM. GoPhish profile uses `mail.amazon-u.online:587`.  
**Example**: Test: `docker exec mailserver swaks -tls -au support@amazon-u.online -ap PASS --from support@amazon-u.online --to test@gmail.com`.  
**Use Case**: Spoofed support emails for phishing.  
**Configuration**:
- **DNS** (Lightsail): See above.
- **Postfix Override** (`mailconfig/postfix-main.cf`):
```text
myhostname = mail.amazon-u.online
mydomain = amazon-u.online