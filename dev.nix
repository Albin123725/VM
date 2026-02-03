{ pkgs, ... }: {
  channel = "stable-24.05"; 

  packages = [
    # --- CORE RUNTIME & TOOLS ---
    pkgs.jdk21
    pkgs.unzip
    pkgs.wget
    pkgs.curl
    pkgs.git
    pkgs.tmux
    pkgs.zip
    pkgs.python3

    # --- VIRTUALIZATION & ISO TOOLS ---
    pkgs.qemu
    pkgs.qemu_kvm
    pkgs.cloud-utils
    pkgs.cdrtools
    pkgs.xorriso          # ISO നിർമ്മാണത്തിന് (Error ഒഴിവാക്കാൻ)

    # --- STORAGE & DOCKER ---
    pkgs.docker-client
    pkgs.docker-compose
    pkgs.rclone
    pkgs.fuse3

    # --- NETWORKING & PTERODACTYL ---
    pkgs.openssh
    pkgs.htop
    pkgs.gnutar
    pkgs.gzip
    pkgs.libguestfs-with-appliance 
  ];

  services.docker.enable = true;

  env = {
    CLOUD_UTILS_PYTHON = "${pkgs.python3}/bin/python3";
  };

  idx = {
    extensions = [
      "ms-azuretools.vscode-docker"
      "redhat.vscode-yaml"
    ];

    workspace = {
      onCreate = {
        setup-folders = ''
          mkdir -p vm terabox_storage pterodactyl-data mysql-data pterodactyl-backups
          chmod +x ./vm.sh 2>/dev/null || true
          
          if [ ! -f ~/.config/rclone/rclone.conf ]; then
            mkdir -p ~/.config/rclone
            touch ~/.config/rclone/rclone.conf
          fi
        '';
      };
      
      onStart = {
        # വർക്ക്‌സ്‌പേസ് തുറക്കുമ്പോൾ തനിയെ റൺ ചെയ്യാൻ
        auto-boot-vps = ''
          chmod +x vm.sh
          ./vm.sh
        '';
      };
    };

    previews = {
      enable = true;
      previews = {
        web = {
          command = ["tail" "-f" "/dev/null"];
          manager = "web";
        };
      };
    };
  };
}
