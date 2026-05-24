<div align="center">
  <img src="https://img.shields.io/badge/IranTUN-NextGen_Tunnel-blue?style=for-the-badge&logo=cloudflare&logoColor=white" alt="IranTUN Logo">
  <h1>IranTUN</h1>
  <p><strong>Ultra-High-Speed, Multi-User VLESS Proxy Bridge for cPanel Shared Hosts</strong></p>
  
  <p>
    <a href="#features">Features</a> •
    <a href="#architecture">Architecture</a> •
    <a href="#installation">Installation</a> •
    <a href="#multi-user-management">Multi-User</a> •
    <a href="#web-admin-panel">Web Panel</a>
  </p>
</div>

---

**IranTUN** is a highly optimized, serverless WebSocket VLESS proxy tunnel specifically engineered for shared cPanel hosting environments. It bypasses stringent host resource limits (CloudLinux LVE) and domestic network filtering (GFW) by utilizing an asynchronous event-driven Node.js bridge.

This project completely eliminates the need for expensive domestic intermediary servers by turning your cheap Iranian shared host into a secure, camouflaged forward-proxy bridge.

## :star2: Key Features

* :rocket: **Serverless Architecture**: Your clients connect directly to your Iranian cPanel host, which securely bridges traffic to your Foreign VPS (Exit Node). No domestic VPS needed!
* :busts_in_silhouette: **Multi-User Management CLI**: Easily create, manage, and delete multiple users directly from the Linux VPS terminal using the built-in `irantun` command.
* :lock: **Cloudflare WARP Integration**: Automatically routes outgoing traffic from your VPS through Cloudflare WARP (SOCKS5), hiding your real VPS IP from target sites and preventing blocks from services like Netflix or ChatGPT.
* :zap: **Adaptive Upload (Batching)**: A smart buffering algorithm designed specifically for cPanel limits. It queues small packets and flushes them in bursts, exponentially increasing upload speeds on congested networks while keeping CPU usage at **0.00%**.
* :art: **100% Camouflage Portfolio**: Serves a beautiful, interactive tech-startup landing page at your root domain (`https://yourdomain.com/`) to easily pass hosting manual reviews.
* :key: **Anti-DPI Secure WebSocket (WSS)**: Wraps VLESS-WS traffic in TLS using automatically generated self-signed SSL certificates, encrypting headers at the transport layer to bypass Deep Packet Inspection (DPI).
* :wrench: **Dynamic Web Admin Panel**: A hidden dashboard (`https://yourdomain.com/?secret=ADMIN_SECRET`) offering real-time diagnostics, active connections, live logs, and a built-in **VLESS Link Generator**.

---

## :globe_with_meridians: How it Works (Architecture)

IranTUN operates on a **Forward-Proxy** model with strict separation of concerns to guarantee security and performance.

1. **The Client (V2rayNG/Nekobox)**: Connects to your Iranian cPanel Domain on standard Web Ports (443/80).
2. **The cPanel Bridge (`app.js`)**: A lightweight Node.js script. It has **zero knowledge** of your VLESS UUIDs. It simply takes the encrypted WebSocket traffic and aggressively forwards it to your Foreign VPS.
3. **The VPS Exit Node (Xray-core)**: Receives the WSS traffic, authenticates the multi-user UUIDs, decrypts the VLESS protocol, and routes it to the internet via Cloudflare WARP.

---

## :computer: Interactive One-Click Installation

To deploy the entire system (both the Foreign VPS and your Iran cPanel Host), run the interactive Bash installer directly on your **Foreign VPS** as `root`:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ramin-mahmoodi/IranTUN/main/deploy.sh)
```

### What the installer does:
1. Prompts you to set an **Admin Secret** (for Web Panel access) to ensure your web UI remains strictly private.
2. Prompts you to enable/disable **Adaptive Upload** and **Cloudflare WARP**.
3. Compiles a customized Node.js package and uploads it directly to your cPanel host via FTP.
4. Installs Xray-core and configures the Multi-User framework on the VPS.
5. Installs the `irantun` CLI menu for easy VPS management.

---

## :busts_in_silhouette: Multi-User Management (CLI)

IranTUN supports unlimited users. Once installed, simply type `irantun` in your VPS terminal to launch the interactive management menu:

```bash
root@vps:~# irantun
```

**Features available in the menu:**
- `[1] View All Users`: Displays a list of all active users and their full VLESS connection links.
- `[2] Add New User`: Generates a new UUID for a user, adds it to the Xray config, and prints the VLESS link.
- `[3] Remove User`: Allows you to safely delete a user's access.
- `[4] Change VPS Listen Port`: Quickly change the internal Xray port.
- `[5] System Status`: Check if Xray and WARP proxies are running correctly.

---

## :bar_chart: Secret Web Admin Panel

Your cPanel host comes with a hidden dashboard. Access it by visiting:
`https://yourdomain.com/?secret=YOUR_ADMIN_SECRET`

**Inside the Web Panel you can:**
* View real-time Active Connections and Total Bandwidth Transferred.
* Monitor live logs to catch any failed handshakes or zombie sockets.
* Dynamically adjust the **Adaptive Upload** settings (Delay in ms) without restarting the Node.js app!
* Use the **Link Generator** to quickly produce VLESS links for users you created on the VPS.

---

## :lock: License & Disclaimer
This project is open-source and intended for educational and network optimization purposes. Please respect the Terms of Service of your hosting provider.
