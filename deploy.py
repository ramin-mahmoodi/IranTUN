import os
import json
import time
import getpass
from ftplib import FTP
import paramiko

def print_banner():
    print("=" * 60)
    print("      Duud Tunnel - Interactive Automated Deployer      ")
    print("=" * 60)

def prompt_input(prompt, default=None, is_password=False):
    if default:
        val = input(f"{prompt} [{default}]: ").strip()
        return val if val else default
    else:
        while True:
            if is_password:
                val = getpass.getpass(f"{prompt}: ").strip()
            else:
                val = input(f"{prompt}: ").strip()
            if val:
                return val
            print("Error: This field is required!")

def deploy():
    print_banner()

    print("\n--- Part 1: Foreign VPS exit node configurations ---")
    vps_ip = prompt_input("Enter Foreign VPS IP Address")
    vps_ssh_port = int(prompt_input("Enter Foreign VPS SSH Port", "22"))
    vps_password = prompt_input("Enter VPS root Password", is_password=True)

    print("\n--- Part 2: cPanel Iran Host Bridge configurations ---")
    print("Notice: Please make sure you have created the Node.js application in cPanel first!")
    print("  Application root should be: 'duud-tunnel'")
    print("  Application URL should be: 'duud.lol' (or subdomain)")
    print("  Application startup file should be: 'app.js'")
    
    ftp_host = prompt_input("Enter FTP/FTPS Host of your cPanel (e.g. ftp.duud.lol)")
    ftp_user = prompt_input("Enter FTP Username")
    ftp_pass = prompt_input("Enter FTP Password", is_password=True)
    ftp_target_dir = prompt_input("Enter FTP Target Directory (e.g. duud-tunnel or public_html/duud-tunnel)", "duud-tunnel")

    print("\n--- Part 3: Deploying Exit Node on Foreign VPS ---")
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    
    try:
        print(f"Connecting to VPS at {vps_ip}:{vps_ssh_port} via SSH...")
        ssh.connect(vps_ip, port=vps_ssh_port, username="root", password=vps_password, timeout=15)
        print("✓ Connected successfully!")

        print("Installing Xray-core exits...")
        stdin, stdout, stderr = ssh.exec_command('bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install')
        exit_status = stdout.channel.recv_exit_status()
        if exit_status != 0:
            print("Warning: Xray installer returned non-zero status. It might already be installed.")
        else:
            print("✓ Xray-core installed successfully!")

        print("Writing VLESS-WS config to VPS (/usr/local/etc/xray/config.json)...")
        xray_config = {
          "log": { "loglevel": "warning" },
          "inbounds": [
            {
              "port": 8080,
              "protocol": "vless",
              "settings": {
                "clients": [
                  {
                    "id": "cc654e3d-71b5-4a6c-b3a2-a3962b8a07c1",
                    "level": 0,
                    "email": "love@duud.lol"
                  }
                ],
                "decryption": "none"
              },
              "streamSettings": {
                "network": "ws",
                "wsSettings": { "path": "/metrics" }
              }
            }
          ],
          "outbounds": [
            { "protocol": "freedom", "settings": {}, "tag": "direct" },
            { "protocol": "blackhole", "settings": {}, "tag": "blocked" }
          ],
          "routing": {
            "rules": [
              { "type": "field", "ip": ["geoip:private"], "outboundTag": "blocked" }
            ]
          }
        }
        
        sftp = ssh.open_sftp()
        try:
            sftp.mkdir("/usr/local/etc/xray")
        except:
            pass
            
        with sftp.open("/usr/local/etc/xray/config.json", "w") as f:
            f.write(json.dumps(xray_config, indent=2))
        sftp.close()
        print("✓ Xray config injected!")

        print("Starting and enabling Xray daemon service...")
        ssh.exec_command("systemctl daemon-reload && systemctl restart xray && systemctl enable xray")
        time.sleep(2)
        
        stdin, stdout, stderr = ssh.exec_command("systemctl is-active xray")
        status = stdout.read().decode().strip()
        if status == "active":
            print("✓ Xray Service is fully active and running on VPS!")
        else:
            print("⚠ Warning: Xray service state is unknown. Please check VPS systemctl.")

    except Exception as e:
        print(f"✗ SSH deployment failed: {e}")
        return
    finally:
        ssh.close()

    print("\n--- Part 4: Deploying Bridge on Iran Host (cPanel) ---")
    try:
        local_config = {
          "vpsIp": vps_ip,
          "vpsPort": 8080,
          "vpsPath": "/metrics",
          "tunnelPath": "/api/v1/analytics",
          "secretUuid": "cc654e3d-71b5-4a6c-b3a2-a3962b8a07c1",
          "port": 3000
        }
        
        script_dir = os.path.dirname(os.path.abspath(__file__))
        host_dir = os.path.join(script_dir, "host")
        os.makedirs(host_dir, exist_ok=True)
        
        with open(os.path.join(host_dir, "config.json"), "w") as f:
            json.dump(local_config, f, indent=2)

        print(f"Connecting to FTP at {ftp_host}...")
        ftp = FTP(ftp_host)
        ftp.login(user=ftp_user, passwd=ftp_pass)
        print("✓ Logged into cPanel FTP server!")

        try:
            ftp.cwd(ftp_target_dir)
        except Exception:
            print(f"Target directory {ftp_target_dir} not found. Creating it...")
            for folder in ftp_target_dir.split('/'):
                if not folder: continue
                try:
                    ftp.mkd(folder)
                except:
                    pass
                ftp.cwd(folder)
            
        print(f"Uploading files to {ftp_target_dir}...")
        
        files_to_upload = ["app.js", "package.json", "config.json"]
        for fname in files_to_upload:
            local_path = os.path.join(host_dir, fname)
            if os.path.exists(local_path):
                with open(local_path, "rb") as f:
                    ftp.storbinary(f"STOR {fname}", f)
                    print(f"  ✓ Uploaded {fname}")

        try:
            ftp.mkd("public")
        except:
            pass
            
        ftp.cwd("public")
        
        public_dir = os.path.join(host_dir, "public")
        public_files = ["index.html", "style.css"]
        for fname in public_files:
            local_path = os.path.join(public_dir, fname)
            if os.path.exists(local_path):
                with open(local_path, "rb") as f:
                    ftp.storbinary(f"STOR {fname}", f)
                    print(f"  ✓ Uploaded public/{fname}")

        ftp.quit()
        print("✓ All bridge files uploaded to your cPanel host successfully!")

    except Exception as e:
        print(f"✗ FTP deployment failed: {e}")
        return

    print("\n" + "=" * 70)
    print("🎉 DEPLOYMENT AND TUNNEL INTEGRATION COMPLETED SUCCESSFULLY! 🎉")
    print("=" * 70)
    print("\nSteps to finalize:")
    print("1. Go to cPanel -> 'Setup Node.js App'")
    print("2. Click 'Restart' on your Node.js application to reload the uploaded files.")
    print("3. Click 'Run NPM Install' if needed to download the 'ws' module.")
    print("\nReady-to-use Client Configurations:")
    print("-" * 70)
    print("⚡ SECURED VLESS LINK (Port 443 with SSL):")
    print(f"vless://cc654e3d-71b5-4a6c-b3a2-a3962b8a07c1@duud.lol:443?type=ws&security=tls&path=%2Fapi%2Fv1%2Fanalytics&host=duud.lol#Duud_Labs_HighSpeed_VLESS")
    print("-" * 70)
    print("⚡ UNSECURED VLESS LINK (Port 80 HTTP):")
    print(f"vless://cc654e3d-71b5-4a6c-b3a2-a3962b8a07c1@duud.lol:80?type=ws&security=none&path=%2Fapi%2Fv1%2Fanalytics&host=duud.lol#Duud_Labs_Unsecured_VLESS")
    print("-" * 70)
    print("======================================================================\n")

if __name__ == "__main__":
    deploy()
