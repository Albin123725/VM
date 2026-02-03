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
    pkgs.xorriso

    # --- STORAGE & DOCKER ---
    pkgs.docker-client
    pkgs.docker-compose
    pkgs.rclone
    pkgs.fuse3

    # --- NETWORKING & UTILS ---
    pkgs.openssh
    pkgs.htop
    pkgs.gnutar
    pkgs.gzip
    pkgs.libguestfs-with-appliance 
  ];

  # Docker സർവീസ് എനേബിൾ ചെയ്യുന്നു
  services.docker.enable = true;

  env = {
    CLOUD_UTILS_PYTHON = "${pkgs.python3}/bin/python3";
  };

  idx = {
    # വിഷ്വൽ സ്റ്റുഡിയോ കോഡ് എക്സ്റ്റൻഷനുകൾ
    extensions = [
      "ms-azuretools.vscode-docker"
      "redhat.vscode-yaml"
    ];

    workspace = {
      # വർക്ക്‌സ്‌പെയ്‌സ് ആദ്യമായി നിർമ്മിക്കുമ്പോൾ ഫോൾഡറുകൾ സെറ്റ് ചെയ്യുന്നു
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

      # ഓരോ തവണ വർക്ക്‌സ്‌പെയ്‌സ് ഓപ്പൺ ചെയ്യുമ്പോഴും VM റൺ ചെയ്യാൻ
      onStart = {
        auto-boot-vps = ''
          chmod +x vm.sh
          # VM ഓട്ടോമാറ്റിക് ആയി റൺ ചെയ്യാൻ താഴത്തെ വരി ഉപയോഗിക്കാം
          # ./vm.sh
        '';
      };
    };

    # വെബ് പാനൽ പ്രിവ്യൂ (Port 80)
    previews = {
      enable = true;
      previews = {
        web = {
          command = ["tail" "-f" "/dev/null"];
          manager = "web";
          port = 80;
        };
      };
    };
  };
}
