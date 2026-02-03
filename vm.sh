#!/bin/bash
set -euo pipefail

# ==========================================
# 1. CONFIGURATION
# ==========================================
HOSTNAME="GamePlannet"
USERNAME="root"
PASSWORD="root"
MEMORY=33G
CPUS=33
DISK_SIZE=300G

WEB_PORT=8080
MC_PORT=25565
MC_UDP_PORT=19132
WINGS_PORT=8081

# --- PATHS ---
CLOUD_MNT="$(pwd)/terabox_storage"
mkdir -p "$CLOUD_MNT"

VM_DIR="$CLOUD_MNT/vm"
PTERO_DATA_HOST="$CLOUD_MNT/pterodactyl-data"
MYSQL_DATA_HOST="$CLOUD_MNT/mysql-data"
mkdir -p "$VM_DIR" "$PTERO_DATA_HOST" "$MYSQL_DATA_HOST"

RUN_FLAG="$VM_DIR/vm_should_run.flag"

# ==========================================
# 2. SESSION CLEANUP
# ==========================================
echo "🧹 Checking for existing sessions..."
tmux kill-session -t vm_console 2>/dev/null || true

# ==========================================
# 3. MOUNT TERABOX (UNCHANGED)
# ==========================================
echo "📡 Connecting to TeraBox..."
fusermount -u "$CLOUD_MNT" 2>/dev/null || true

nohup rclone mount terabox: "$CLOUD_MNT" \
  --vfs-cache-mode writes \
  --buffer-size 32M \
  --allow-other > "$CLOUD_MNT/mount.log" 2>&1 &

echo "⏳ Waiting for Cloud Storage (20s)..."
sleep 20

# ==========================================
# 4. DISK SETUP (UNCHANGED)
# ==========================================
DISK_FILE="$VM_DIR/ubuntu.qcow2"

if [ ! -f "$DISK_FILE" ]; then
  echo "📥 Downloading Ubuntu..."
  wget -q --show-progress -O "$VM_DIR/ubuntu.img" \
    https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

  qemu-img convert -O qcow2 "$VM_DIR/ubuntu.img" "$DISK_FILE"
  qemu-img resize "$DISK_FILE" $DISK_SIZE
  rm "$VM_DIR/ubuntu.img"
fi

# ==========================================
# 5. CLOUD-INIT (ONLY FIXED SECTION)
# ==========================================
rm -f "$VM_DIR/seed.iso"

echo "⚙️ Writing cloud-init (SSH FIX ONLY)..."

cat > "$VM_DIR/user-data" <<EOF
#cloud-config
hostname: $HOSTNAME
ssh_pwauth: true
disable_root: false

# 🔥 THIS IS THE FIX (RUNS EVERY BOOT)
bootcmd:
  - passwd -u root || true
  - echo "root:$PASSWORD" | chpasswd
  - sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
  - sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

users:
  - name: root
    shell: /bin/bash
    lock_passwd: false

runcmd:
  - systemctl restart ssh
EOF

touch "$VM_DIR/meta-data"

xorriso -as mkisofs -r -V cidata -J \
  -o "$VM_DIR/seed.iso" \
  "$VM_DIR/user-data" "$VM_DIR/meta-data"

# ==========================================
# 6. LAUNCH VM (UNCHANGED)
# ==========================================
KVM_FLAG=""
[ -c /dev/kvm ] && KVM_FLAG="-enable-kvm"

touch "$RUN_FLAG"

echo "🚀 Starting GamePlannet VPS..."

tmux new-session -d -s vm_console "bash -c '
while true; do
  if [ -f \"$RUN_FLAG\" ]; then
    echo \"--- VM BOOTING ---\"

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

echo "✅ VM is running"
echo "🔑 SSH: root@<TAILSCALE-IP>  (password: root)"
sleep 3
tmux attach-session -t vm_console

