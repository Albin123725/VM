#!/bin/bash
echo "🚀 Starting Debian 11 VM..."

# Stop and remove any existing container
docker stop debian11-vm 2>/dev/null || true
docker rm debian11-vm 2>/dev/null || true

# Pull the image first
echo "Pulling VM image..."
docker pull hopingboyz/debian11-vm

# Start the VM container
echo "Starting container..."
docker run -d \
  --name debian11-vm \
  --restart unless-stopped \
  -v $(pwd)/vm-data:/data \
  -e VM_RAM=24000 \
  -e VM_CPU=8 \
  -e VM_DISK=70G \
  -p 2026:2222 \
  -p 3399:3389 \
  -p 6080:6080 \
  hopingboyz/debian11-vm

echo ""
echo "✅ VM started successfully!"
echo ""
echo "📡 Connection details:"
echo "  SSH:     ssh root@localhost -p 2026"
echo "  RDP:     localhost:3399"
echo "  Web VNC: http://localhost:6080"
echo ""
echo "🔑 Default credentials:"
echo "  Username: root"
echo "  Password: root (or try 'password')"
echo ""
echo "⏳ Waiting 30 seconds for VM to boot..."
sleep 30
echo "Ready to connect!"
