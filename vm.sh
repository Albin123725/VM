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

# --- TERABOX MAPPING ---
CLOUD_MNT="$(pwd)/terabox_storage"
mkdir -p "$CLOUD_MNT"

VM_DIR="$CLOUD_MNT/vm"
PTERO_DATA_HOST="$CLOUD_MNT/pterodactyl-data"
MYSQL_DATA_HOST="$CLOUD_MNT/mysql-data"
mkdir -p "$VM_DIR" "$PTERO_DATA_HOST" "$MYSQL_DATA_HOST"

# ഈ ഫയൽ ഉണ്ടെങ്കിൽ മാത്രമേ VM ഓട്ടോമാറ്റിക് ആയി സ്റ്റാർട്ട് ആകൂ
RUN_FLAG="$VM_DIR/vm_should_run.flag"

# ==========================================
# 2. MOUNT TERABOX
# ==========================================
echo "📡 Connecting to TeraBox..."
fusermount -u "$CLOUD_MNT" 2>/dev/null || true
nohup rclone mount terabox: "$CLOUD_MNT" \
    --vfs-cache-mode writes \
    --buffer-size 32M \
    --allow-other > "$CLOUD_MNT/mount.log" 2>&1 &

echo "⏳ Waiting for TeraBox (15s)..."
sleep 15

# ==========================================
# 3. CREATE DISK & CLOUD-INIT (Optimized)
# ==========================================
DISK_FILE="$VM_DIR/ubuntu.qcow2"
if [ ! -f "$DISK_FILE" ]; then
    echo "📥 Downloading Ubuntu..."
    wget -q --show-progress -O "$VM_DIR/ubuntu.img" "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
    qemu-img convert -O qcow2 "$VM_DIR/ubuntu.img" "$DISK_FILE"
    qemu-img resize "$DISK_FILE" $DISK_SIZE
    rm "$VM_DIR/ubuntu.img"
fi

# Cloud-init ISO creation
if [ ! -f "$VM_DIR/seed.iso" ]; then
    cat > "$VM_DIR/user-data" <<EOF
#cloud-config
hostname: $HOSTNAME
ssh_pwauth: true
chpasswd: { list: "root:$PASSWORD\n$USERNAME:$PASSWORD", expire: false }
EOF
    touch "$VM_DIR/meta-data"
    xorriso -as mkisofs -r -V cidata -J -o "$VM_DIR/seed.iso" "$VM_DIR/user-data" "$VM_DIR/meta-data"
fi

# ==========================================
# 4. SMART EXECUTION LOGIC
# ==========================================

# KVM Check
KVM_FLAG=""
[ -c /dev/kvm ] && KVM_FLAG="-enable-kvm"

# സ്റ്റാർട്ട് ചെയ്യുമ്പോൾ Flag ഫയൽ നിർമ്മിക്കുന്നു
touch "$RUN_FLAG"

echo "🚀 Starting VM Session..."

# Tmux സെഷനുള്ളിലെ ലൂപ്പ്
tmux new-session -d -s vm_console "bash -c '
while true; do
    if [ -f \"$RUN_FLAG\" ]; then
        echo \"--- VM Booting --- \";
        qemu-system-x86_64 \
            -m $MEMORY -smp $CPUS $KVM_FLAG -cpu host \
            -drive file=$DISK_FILE,format=qcow2,if=virtio \
            -cdrom $VM_DIR/seed.iso \
            -virtfs local,path=$PTERO_DATA_HOST,mount_tag=ptero_share,security_model=none \
            -virtfs local,path=$MYSQL_DATA_HOST,mount_tag=mysql_share,security_model=none \
            -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::$WEB_PORT-:80,hostfwd=tcp::$MC_PORT-:25565,hostfwd=udp::$MC_UDP_PORT-:19132,hostfwd=tcp::$WINGS_PORT-:8080 \
            -device virtio-net-pci,netdev=net0 -nographic -serial mon:stdio;
        
        echo \"⚠️ VM Stopped. Checking if it should restart...\";
        sleep 5;
    else
        echo \"🛑 Manual stop detected. Exit loop.\";
        break;
    fi
done'"

# ==========================================
# 5. HOW TO STOP (Custom Command)
# ==========================================
# മാനുവലായി ഓഫ് ചെയ്യാൻ ഈ കമാൻഡ് ഉപയോഗിക്കുക:
# rm ./terabox_storage/vm/vm_should_run.flag && tmux kill-session -t vm_console

echo "✅ VM is active. Auto-restart is ON for Workspace reopens & Crashes."
echo "👉 To STOP permanently: rm $RUN_FLAG && tmux kill-session -t vm_console"
sleep 2
tmux attach-session -t vm_console
