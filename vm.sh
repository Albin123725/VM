#!/bin/bash
# ==========================================
# 🚀 GAMEPLANNET - FULL VM CONFIGURATION
# Features: Pterodactyl, TeraBox Auto-Sync, Auto-Mount, Daily Backup
# ==========================================
set -euo pipefail

# 1. CONFIGURATION
# ------------------------------------------
HOSTNAME="GamePlannet"
USERNAME="root"
PASSWORD="root"
MEMORY=12G      # Balanced for stability
CPUS=8          # Recommended for KVM
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

# 3. MOUNT TERABOX (The Core Resource)
# ------------------------------------------
echo "📡 Connecting to TeraBox..."
fusermount -u "$CLOUD_MNT" 2>/dev/null || true

nohup rclone mount terabox: "$CLOUD_MNT" \
  --vfs-cache-mode writes \
  --buffer-size 64M \
  --vfs-read-chunk-size 32M \
  --allow-other > rclone_mount.log 2>&1 &

echo "⏳ Waiting for Cloud Storage to stabilize (25s)..."
sleep 25

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
echo "⚙️ Configuring VM with Auto-Mount & Auto-Backup..."

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
  # [ADDED] Create mount point inside VM
  - mkdir -p /mnt/ptero_share
  # [ADDED] Auto-mount the TeraBox-linked folder from host
  - mount -t 9p -o trans=virtio,version=9p2000.L ptero_share /mnt/ptero_share
  # [ADDED] Creating the 'auto-backup' command script
  - |
    cat > /usr/local/bin/auto-backup <<'INNER'
    #!/bin/bash
    TIME=\$(date +%Y-%m-%d_%H-%M)
    echo "Starting Pterodactyl Cloud Backup..."
    tar -czf /mnt/ptero_share/ptero_full_backup_\$TIME.tar.gz /var/lib/pterodactyl/volumes 2>/dev/null
    echo "Success! Backup saved inside TeraBox: ptero_full_backup_\$TIME.tar.gz"
    INNER
  - chmod +x /usr/local/bin/auto-backup
  # [ADDED] Setting up Cron Job for Daily Midnight Backup
  - (crontab -l 2>/dev/null; echo "0 0 * * * /usr/local/bin/auto-backup") | crontab -
EOF

touch "$VM_DIR/meta-data"
xorriso -as mkisofs -r -V cidata -J -o "$VM_DIR/seed.iso" "$VM_DIR/user-data" "$VM_DIR/meta-data"

# 6. LAUNCH VM (VIRTFS ENABLED)
# ------------------------------------------
KVM_FLAG=""
[ -c /dev/kvm ] && KVM_FLAG="-enable-kvm"

touch "$RUN_FLAG"
echo "🚀 Launching GamePlannet VPS..."

tmux new-session -d -s vm_console "bash -c '
while true; do
  if [ -f \"$RUN_FLAG\" ]; then
    qemu-system-x86_64 \
      -m $MEMORY \
      -smp $CPUS \
      $KVM_FLAG -cpu host \
      -drive file=$DISK_FILE,format=qcow2,if=virtio \
      -cdrom $VM_DIR/seed.iso \
      -virtfs local,path=$PTERO_DATA_HOST,mount_tag=ptero_share,security_model=none \
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
echo "🛠️  Daily Backup is active. Manual backup: run 'auto-backup' inside VM."
sleep 2
tmux attach-session -t vm_console
