import os
import json
import time
import getpass
import uuid
from ftplib import FTP
import paramiko

def print_banner():
    print("=" * 60)
    print("      IranTUN - Interactive Automated Multi-Deployer     ")
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

    # Generate fresh secure VLESS UUID dynamically
    secure_uuid = str(uuid.uuid4())

    print("\n--- Part 1: Foreign VPS Exit Node Configuration ---")
    vps_ip = prompt_input("Enter Foreign VPS IP Address")
    vps_ssh_port = int(prompt_input("Enter Foreign VPS SSH Port", "22"))
    vps_password = prompt_input("Enter VPS root Password", is_password=True)

    print("\n--- Part 2: cPanel Bridge Configurations ---")
    bridge_domain = prompt_input("Enter your cPanel Domain (e.g. yourdomain.com)")
    
    print("\nSelect Deployment Method for cPanel Host:")
    print("1. Fully Automated (via SSH - Creates and configures Node.js app automatically)")
    print("2. Semi-Automated (via FTP - Requires a simple click in cPanel Node.js App page)")
    method = prompt_input("Enter choice (1 or 2)", "1")

    app_root = prompt_input("Enter Application Root Directory on cPanel", "irantun-bridge")
    app_uri = prompt_input("Enter Application URI / Path", "/")

    cpanel_ssh_user = None
    cpanel_ssh_pass = None
    cpanel_ssh_port = 22
    
    ftp_host = None
    ftp_user = None
    ftp_pass = None

    if method == "1":
        print("\n--- Method 1 Selected: SSH Automated Deployment ---")
        cpanel_ssh_host = prompt_input("Enter cPanel Host / Domain SSH Address", bridge_domain)
        cpanel_ssh_port = int(prompt_input("Enter cPanel SSH Port", "22"))
        cpanel_ssh_user = prompt_input("Enter cPanel SSH Username")
        cpanel_ssh_pass = prompt_input("Enter cPanel SSH Password", is_password=True)
    else:
        print("\n--- Method 2 Selected: FTP Upload + Manual GUI Setup ---")
        ftp_host = prompt_input("Enter cPanel FTP Host", f"ftp.{bridge_domain}")
        ftp_user = prompt_input("Enter FTP Username")
        ftp_pass = prompt_input("Enter FTP Password", is_password=True)

    # 1. VPS Configuration
    print("\n--- Part 3: Connecting to Foreign VPS & Installing Exit Node ---")
    vps_ssh = paramiko.SSHClient()
    vps_ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    
    try:
        print(f"Connecting to VPS at {vps_ip}:{vps_ssh_port} via SSH...")
        vps_ssh.connect(vps_ip, port=vps_ssh_port, username="root", password=vps_password, timeout=15)
        print("✓ Connected to Foreign VPS successfully!")

        print("Installing Xray-core officially...")
        stdin, stdout, stderr = vps_ssh.exec_command('bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install')
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
                    "id": secure_uuid,
                    "level": 0,
                    "email": f"love@{bridge_domain}"
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
        
        sftp = vps_ssh.open_sftp()
        try:
            sftp.mkdir("/usr/local/etc/xray")
        except:
            pass
            
        with sftp.open("/usr/local/etc/xray/config.json", "w") as f:
            f.write(json.dumps(xray_config, indent=2))
        sftp.close()
        print("✓ Xray config injected!")

        print("Starting and enabling Xray daemon service...")
        vps_ssh.exec_command("systemctl daemon-reload && systemctl restart xray && systemctl enable xray")
        time.sleep(2)
        
        stdin, stdout, stderr = vps_ssh.exec_command("systemctl is-active xray")
        status = stdout.read().decode().strip()
        if status == "active":
            print("✓ Xray Service is active on VPS!")
        else:
            print("⚠ Warning: Xray service state is unknown. Please check VPS systemctl.")

    except Exception as e:
        print(f"✗ VPS deployment failed: {e}")
        return
    finally:
        vps_ssh.close()

    # 2. Local Configuration Generation
    local_config = {
      "vpsIp": vps_ip,
      "vpsPort": 8080,
      "vpsPath": "/metrics",
      "tunnelPath": "/api/v1/analytics",
      "secretUuid": secure_uuid,
      "port": 3000
    }
    
    script_dir = os.path.dirname(os.path.abspath(__file__))
    host_dir = os.path.join(script_dir, "host")
    os.makedirs(host_dir, exist_ok=True)
    
    with open(os.path.join(host_dir, "config.json"), "w") as f:
        json.dump(local_config, f, indent=2)

    # 3. cPanel Bridge Deployment
    if method == "1":
        print("\n--- Part 4: Connecting to cPanel via SSH and Deploying Bridge ---")
        cp_ssh = paramiko.SSHClient()
        cp_ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        
        try:
            print(f"Connecting to cPanel at {cpanel_ssh_host}:{cpanel_ssh_port} via SSH...")
            cp_ssh.connect(cpanel_ssh_host, port=cpanel_ssh_port, username=cpanel_ssh_user, password=cpanel_ssh_pass, timeout=15)
            print("✓ Connected to cPanel successfully!")

            print(f"Creating directory {app_root}...")
            cp_ssh.exec_command(f"mkdir -p ~/{app_root} ~/{app_root}/public")
            time.sleep(1)

            print("Uploading Node.js files via SFTP...")
            cp_sftp = cp_ssh.open_sftp()
            
            # Upload files
            files_to_upload = ["app.js", "package.json", "config.json"]
            for fname in files_to_upload:
                local_path = os.path.join(host_dir, fname)
                if os.path.exists(local_path):
                    cp_sftp.put(local_path, f"{app_root}/{fname}")
                    print(f"  ✓ Uploaded {fname}")
                    
            public_files = ["index.html", "style.css"]
            for fname in public_files:
                local_path = os.path.join(host_dir, "public", fname)
                if os.path.exists(local_path):
                    cp_sftp.put(local_path, f"{app_root}/public/{fname}")
                    print(f"  ✓ Uploaded public/{fname}")
            
            cp_sftp.close()

            # Automate CloudLinux selector
            print("Detecting CloudLinux selector and creating Node.js application...")
            # We first try to see what versions are available
            stdin, stdout, stderr = cp_ssh.exec_command("cloudlinux-selector interpreter --json --interpreter nodejs")
            node_version = "20" # fallback
            try:
                versions = json.loads(stdout.read().decode())
                if 'available_versions' in versions and len(versions['available_versions']) > 0:
                    node_version = versions['available_versions'][-1] # Choose highest version
            except:
                pass
            
            print(f"Creating Node.js app URI '{app_uri}' with root '{app_root}' using Node.js v{node_version}...")
            # Delete if exists to avoid conflicts
            cp_ssh.exec_command(f"cloudlinux-selector destroy --json --interpreter nodejs --app-root {app_root}")
            time.sleep(1)
            
            stdin, stdout, stderr = cp_ssh.exec_command(f"cloudlinux-selector create --json --interpreter nodejs --version {node_version} --app-root {app_root} --domain {bridge_domain} --app-uri {app_uri} --startup-file app.js")
            result = stdout.read().decode()
            
            # Install modules
            print("Installing package dependencies (npm install)...")
            cp_ssh.exec_command(f"cloudlinux-selector install-modules --json --interpreter nodejs --app-root {app_root}")
            time.sleep(3)

            # Start/Restart app
            print("Starting application...")
            cp_ssh.exec_command(f"cloudlinux-selector restart --json --interpreter nodejs --app-root {app_root}")
            
            print("✓ Node.js application registered and active in cPanel automatically!")

        except Exception as e:
            print(f"✗ cPanel SSH automation failed: {e}")
            print("Falling back to instructions. You might need to check your SSH credentials or setup manually.")
            return
        finally:
            cp_ssh.close()
            
    else:
        print("\n--- Part 4: Connecting to cPanel via FTP and Uploading Bridge ---")
        try:
            ftp = FTP(ftp_host)
            ftp.login(user=ftp_user, passwd=ftp_pass)
            print("✓ Logged into cPanel FTP server!")

            try:
                ftp.cwd(ftp_target_dir)
            except Exception:
                print(f"Target directory {ftp_target_dir} not found. Creating...")
                for folder in ftp_target_dir.split('/'):
                    if not folder: continue
                    try:
                        ftp.mkd(folder)
                    except:
                        pass
                    ftp.cwd(folder)
                
            print(f"Uploading files...")
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
            
            public_files = ["index.html", "style.css"]
            for fname in public_files:
                local_path = os.path.join(host_dir, "public", fname)
                if os.path.exists(local_path):
                    with open(local_path, "rb") as f:
                        ftp.storbinary(f"STOR {fname}", f)
                        print(f"  ✓ Uploaded public/{fname}")

            ftp.quit()
            print("✓ All bridge files uploaded successfully via FTP!")

        except Exception as e:
            print(f"✗ FTP upload failed: {e}")
            return

    # Print final configurations
    print("\n" + "=" * 70)
    print("🎉 DEPLOYMENT AND TUNNEL INTEGRATION COMPLETED SUCCESSFULLY! 🎉")
    print("=" * 70)
    
    if method == "2":
        print("\n📝 MANUAL CPANEL SETUP INSTRUCTIONS:")
        print("Because you used FTP, please finalize the Node.js application in your cPanel UI:")
        print("1. Search for 'Setup Node.js App' in your cPanel dashboard.")
        print("2. Click 'Create Application'.")
        print("3. Enter the following exact values (as shown in your cPanel screen):")
        print(f"   - Node.js version: Choose '20.x' or any active version.")
        print(f"   - Application root: {app_root}")
        print(f"   - Application URL: Select {bridge_domain} and leave the URI path as '{app_uri}'")
        print(f"   - Application startup file: app.js")
        print("4. Click the blue 'CREATE' button on the top right.")
        print("5. Click 'Run NPM Install' to fetch dependencies.")
    else:
        print("\n✓ AUTOMATIC SETUP SUCCESSFUL! No further action required inside cPanel.")
        
    print("\nReady-to-use Client Configurations:")
    print("-" * 70)
    print("⚡ SECURED VLESS LINK (Port 443 with SSL):")
    print(f"vless://{secure_uuid}@{bridge_domain}:443?type=ws&security=tls&path=%2Fapi%2Fv1%2Fanalytics&host={bridge_domain}#IranTUN_HighSpeed_VLESS")
    print("-" * 70)
    print("⚡ UNSECURED VLESS LINK (Port 80 HTTP):")
    print(f"vless://{secure_uuid}@{bridge_domain}:80?type=ws&security=none&path=%2Fapi%2Fv1%2Fanalytics&host={bridge_domain}#IranTUN_Unsecured_VLESS")
    print("-" * 70)
    print("======================================================================\n")

if __name__ == "__main__":
    deploy()
