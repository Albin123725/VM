#!/bin/bash
# ==========================================
# 🚀 GAMEPLANNET - FINAL STABLE VM CONFIGURATION
# Features: Pterodactyl, TeraBox Sync, Permissions Fix, Daily Backup
# ==========================================
set -euo pipefail

# 1. CONFIGURATION
# ------------------------------------------
HOSTNAME="GamePlannet"
USERNAME="root"
PASSWORD="root"
MEMORY=12G      # Stability-ക്കായി 12G ശുപാർശ ചെയ്യുന്നു
CPUS=8          # Smooth performance
DISK_SIZE=300G

WEB_PORT=8080
MC_PORT=25565
MC_UDP_PORT=19132
WINGS_PORT=8081

# --- PATHS (Linked to TeraBox) ---
CLOUD_MNT="$(pwd)/terabox_storage"
mkdir -p "$CLOUD_MNT"

VM_DIR="$CLOUD_MNT/vm"
PTERO_DATA_HOST="$CLOUD_MNT/pterodactyl-data"
MYSQL_DATA_HOST="$CLOUD_MNT/mysql-data"

mkdir -p "$VM_DIR" "$PTERO_DATA_HOST" "$MYSQL_DATA_HOST"
RUN_FLAG="$VM_DIR/vm_should_run.flag"

# 2. SESSION CLEANUP
# ------------------------------------------
echo "🧹 Cleaning old sessions..."
tmux kill-session -t vm_console 2>/dev/null || true

# 3. MOUNT TERABOX
# ------------------------------------------
echo "📡 Connecting to TeraBox..."
if ! mountpoint -q "$CLOUD_MNT"; then
    fusermount -u "$CLOUD_MNT" 2>/dev/null || true
    nohup rclone mount terabox: "$CLOUD_MNT" \
      --vfs-cache-mode writes \
      --buffer-size 64M \
      --vfs-read-chunk-size 32M \
      --allow-other > rclone_mount.log 2>&1 &
    echo "⏳ Waiting for Cloud Storage to stabilize (25s)..."
    sleep 25
fi

# 4. DISK SETUP
# ------------------------------------------
DISK_FILE="$VM_DIR/ubuntu.qcow2"
if [ ! -f "$DISK_FILE" ]; then
  echo "📥 Downloading Ubuntu Cloud Image..."
  wget -q --show-progress -O "$VM_DIR/ubuntu.img" \
    https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
  qemu-img convert -O qcow2 "$VM_DIR/ubuntu.img" "$DISK_FILE"
  qemu-img resize "$DISK_FILE" $DISK_SIZE
  rm "$VM_DIR/ubuntu.img"
fi

# 5. CLOUD-INIT (THE ADDED FEATURES SECTION)
# ------------------------------------------
rm -f "$VM_DIR/seed.iso"
echo "⚙️ Configuring VM with Advanced Mount & Permissions..."

cat > "$VM_DIR/user-data" <<EOF
#cloud-config
hostname: $HOSTNAME
ssh_pwauth: true
disable_root: false

bootcmd:
  - passwd -u root || true
  - echo "root:$PASSWORD" | chpasswd
  - sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
  - sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

runcmd:
  - systemctl restart ssh
  # 1. Pterodactyl-ന് ആവശ്യമായ മൗണ്ട് സെറ്റപ്പ്
  - mkdir -p /var/lib/pterodactyl
  - mount -t 9p -o trans=virtio,version=9p2000.L,msize=262144,sync ptero_share /var/lib/pterodactyl
  - chmod -R 777 /var/lib/pterodactyl
  # 2. Wings Configuration Fix (Permission Denied ഒഴിവാക്കാൻ)
  - |
    if [ -f /etc/pterodactyl/config.yml ]; then
      sed -i '/system:/a \  user:\n    rootless: true' /etc/pterodactyl/config.yml
      systemctl restart wings || true
    fi
  # 3. ഓട്ടോ ബാക്കപ്പ് സ്ക്രിപ്റ്റ്
  - |
    cat > /usr/local/bin/auto-backup <<'INNER'
    #!/bin/bash
    TIME=\$(date +%Y-%m-%d_%H-%M)
    echo "Starting Pterodactyl Cloud Backup..."
    tar -czf /var/lib/pterodactyl/ptero_full_backup_\$TIME.tar.gz /var/lib/pterodactyl/volumes 2>/dev/null
    echo "Success! Backup saved inside TeraBox: ptero_full_backup_\$TIME.tar.gz"
    INNER
  - chmod +x /usr/local/bin/auto-backup
  # 4. ദിവസവും രാത്രി 12 മണിക്ക് ഓട്ടോ ബാക്കപ്പ്
  - (crontab -l 2>/dev/null; echo "0 0 * * * /usr/local/bin/auto-backup") | crontab -
EOF

touch "$VM_DIR/meta-data"
xorriso -as mkisofs -r -V cidata -J -o "$VM_DIR/seed.iso" "$VM_DIR/user-data" "$VM_DIR/meta-data"

# 6. LAUNCH VM (WITH MAPPED PERMISSIONS)
# ------------------------------------------
KVM_FLAG=""
[ -c /dev/kvm ] && KVM_FLAG="-enable-kvm"

touch "$RUN_FLAG"
echo "🚀 Launching GamePlannet VPS..."

# 
tmux new-session -d -s vm_console "bash -c '
while true; do
  if [ -f \"$RUN_FLAG\" ]; then
    qemu-system-x86_64 \
      -m $MEMORY \
      -smp $CPUS \
      $KVM_FLAG -cpu host \
      -drive file=$DISK_FILE,format=qcow2,if=virtio \
      -cdrom $VM_DIR/seed.iso \
      -virtfs local,path=$PTERO_DATA_HOST,mount_tag=ptero_share,security_model=mapped-xattr,multidevs=remap \
      -virtfs local,path=$MYSQL_DATA_HOST,mount_tag=mysql_share,security_model=none \
      -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::$WEB_PORT-:80,hostfwd=tcp::$MC_PORT-:25565,hostfwd=udp::$MC_UDP_PORT-:19132,hostfwd=tcp::$WINGS_PORT-:8080 \
      -device virtio-net-pci,netdev=net0 \
      -nographic -serial mon:stdio
    echo \"⚠️ VM stopped, restarting...\"
    sleep 5
  else
    break
  fi
done
'"

echo "✅ VM is successfully running!"
echo "🛠️ Pterodactyl Data is now synced with TeraBox."
echo "🔐 Permissions are handled by 'mapped-xattr' to prevent crashes."
sleep 2
tmux attach-session -t vm_console
