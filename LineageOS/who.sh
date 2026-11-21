#!/usr/bin/env bash
#####################################################################
# Autor: WhoFoss <https://github.com/WhoFoss>                       #
# Créditos: Saroj-Tajpuriya - (disponibilizou a device tree)        #
# Créditos: Angelpro09xd - (Por me ensinar a compilar).             #
# Créditos: fwlta - (Por me ensinar a remover apps)                 #
#####################################################################

#------------------------------------------------------------------------------------------------#
# Cores
#------------------------------------------------------------------------------------------------#
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
B=$'\e[1m'
RESET='\033[0m'

#------------------------------------------------------------------------------------------------#
# Setup do Terminal
#------------------------------------------------------------------------------------------------#
echo -en "\033[?25l"  # esconde o cursor
trap 'echo -en "\033[?12l\033[?25h"' EXIT  # restaura ao sair


#------------------------------------------------------------------------------------------------#
# Funções Auxiliares
#------------------------------------------------------------------------------------------------#
# Imprime mensagem de erro formatada com timestamp e encerra o script.
#------------------------------------------------------------------------------------------------#
error_exit() {
    local message="$1"
    local exit_code="${2:-1}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[ERROR] ${timestamp} - ${message}${RESET}" >&2
    exit "$exit_code"
}

#------------------------------------------------------------------------------------------------#
# Imprime a mensagem - 29/09/2026
#------------------------------------------------------------------------------------------------#
# Imprime uma etapa concluída com o tempo decorrido do script; $2 opcional define a cor.
# Imprime a mensagem
print_header()
{
    echo -e "${3:-$B}>>>${RESET} ${1}"
}
    
#------------------------------------------------------------------------------------------------#
# Clona (ou reclona) um repositório git raso em um diretório de destino.
#------------------------------------------------------------------------------------------------#
clone_repo() 
{
    local repo_url=$1
    local branch=$2
    local dest=$3

    echo -e "${YELLOW}Cloning $dest...${RESET}"

    [ -d "$dest" ] && rm -rf "$dest"

    git clone --depth 1 -b "$branch" "$repo_url" "$dest" || error_exit "Failed to clone $dest"

    print_header "${dest} clone success" "#" "$YELLOW"
}

#------------------------------------------------------------------------------------------------#
# Clona um repositório de HAL, sobrescrevendo o path caso já exista. 
#------------------------------------------------------------------------------------------------#
clone_hal() 
{
    local url=$1
    local path=$2
    local branch=$3
    rm -rf "$path"
    git clone --depth 1 -b "$branch" "$url" "$path" || error_exit "Failed to clone HAL $path"
}

#------------------------------------------------------------------------------------------------#
# Começa aqui 
#------------------------------------------------------------------------------------------------#
# Dei uma pequena melhorada nessa função. o intuito é diminuir as funções inúteis - 29/09/2026
#------------------------------------------------------------------------------------------------#
setup_lineage_dir() {
    LINEAGE_DIR="LOSMG"
    TARGET_DIR="$HOME/$LINEAGE_DIR"

    [ "$PWD" = "$TARGET_DIR" ] && return

    mkdir -p "$TARGET_DIR" || error_exit "Failed to create $TARGET_DIR"
    cd "$TARGET_DIR" || error_exit "Failed to cd to $TARGET_DIR"
}; setup_lineage_dir
echo -e "${YELLOW}Starting LineageOS 22.2 build script...${RESET}"

#------------------------------------------------------------------------------------------------#
# Repository Initialization
# Initialize the LineageOS source repository
#------------------------------------------------------------------------------------------------#
echo -e "${YELLOW}Initializing repo...${RESET}"
repo init -u https://github.com/LineageOS/android.git -b lineage-22.2 --git-lfs --depth=1 || error_exit "Repo init failed"
print_header "Repo init success"

#------------------------------------------------------------------------------------------------#
# Clona o local_manifests_sapphire
#------------------------------------------------------------------------------------------------#
clone_repo "https://github.com//WF-DT-Sapphire/local_manifests_sapphire" "whofoss15" ".repo/local_manifests"

#------------------------------------------------------------------------------------------------#
# Repository Synchronization
# Download and synchronize the complete source tree
#------------------------------------------------------------------------------------------------#
 echo -e "${YELLOW}Syncing full repo...${RESET}"
repo sync -c -j15 --force-sync --no-clone-bundle --no-tags --optimized-fetch --prune
print_header "Repo sync success"

#------------------------------------------------------------------------------------------------#
# Qualcomm HALs
# Clone the required SM6225 hardware components
#------------------------------------------------------------------------------------------------#
echo -e "${YELLOW}Cloning HALs for SM6225...${RESET}"
clone_hal "https://github.com/WF-DT-Sapphire/android_hardware_qcom-caf_common.git" "hardware/qcom-caf/common" "lineage-22.2"
clone_hal "https://github.com/WF-DT-Sapphire/vendor_qcom_opensource_agm.git" "hardware/qcom-caf/sm6225/audio/agm" "lineage-22.2-caf-sm6225"
clone_hal "https://github.com/WF-DT-Sapphire/vendor_qcom_opensource_arpal-lx.git" "hardware/qcom-caf/sm6225/audio/pal" "lineage-22.0-caf-sm6225"
clone_hal "https://github.com/WF-DT-Sapphire/vendor_qcom_opensource_data-ipa-cfg-mgr.git" "hardware/qcom-caf/sm6225/data-ipa-cfg-mgr" "lineage-22.0-caf-sm6225"
clone_hal "https://github.com/WF-DT-Sapphire/vendor_qcom_opensource_dataipa.git" "hardware/qcom-caf/sm6225/dataipa" "lineage-22.0-caf-sm6225"
clone_hal "https://github.com/WF-DT-Sapphire/hardware_qcom_display.git" "hardware/qcom-caf/sm6225/display" "lineage-22.0-caf-sm6225"
clone_hal "https://github.com/WF-DT-Sapphire/hardware_qcom_media.git" "hardware/qcom-caf/sm6225/media" "lineage-22.0-caf-sm6225"
clone_hal "https://github.com/WF-DT-Sapphire/hardware_qcom_audio.git" "hardware/qcom-caf/sm6225/audio/primary-hal" "lineage-22.0-caf-sm6225"
clone_hal "https://github.com/WF-DT-Sapphire/device_qcom_sepolicy_vndr.git" "device/qcom/sepolicy_vndr/sm6225" "lineage-22.0-caf-sm6225"
print_header "HALs cloned"

#------------------------------------------------------------------------------------------------#
# Instala o script de upload do GoFile e cria o alias "gofile" no bashrc.
#------------------------------------------------------------------------------------------------#
gofile_install()
{
    echo -e "${YELLOW}Installing gofile upload tool...${RESET}"
    wget -q https://raw.githubusercontent.com/kenway214/GoFile-Upload-Script/master/upload.sh \
        -O "$TARGET_DIR/gofile" && chmod +x "$TARGET_DIR/gofile" || error_exit "Failed to install gofile"

    grep -q 'alias gofile' ~/.bashrc || echo "alias gofile=\"$TARGET_DIR/gofile\"" >> ~/.bashrc
}; gofile_install

#------------------------------------------------------------------------------------------------#
# Localiza a ROM mais recente, gera o SHA256 e envia para o GoFile.
#------------------------------------------------------------------------------------------------#
upload() {
    local build_dir="out/target/product/sapphire"
    local gofile_script="${HOME}/LOSMG/gofile"
    local rom_path boot_path rom_name rom_size rom_sha256
    local boot_sha256 rom_output boot_output rom_url boot_url

    [ -d "$build_dir" ] || { echo -e "${RED}Build dir não existe: $build_dir${RESET}"; return 1; }
    [ -x "$gofile_script" ] || { echo -e "${RED}gofile não executável: $gofile_script${RESET}"; return 1; }

    ### Localiza os arquivos 
    rom_path=$(ls -t "$build_dir"/lineage-22.2-*-UNOFFICIAL-sapphire*.zip 2>/dev/null | head -n1)
    boot_path="$build_dir/init_boot.img"

    [ -z "$rom_path" ] && { echo -e "${YELLOW}ROM não encontrada em $build_dir${RESET}"; return 1; }
    [ -f "$boot_path" ] || { echo -e "${YELLOW}init_boot.img não encontrado: $boot_path${RESET}"; return 1; }

    ### Metadados da ROM
    rom_name=${rom_path##*/}
    rom_size=$(du -h "$rom_path" | cut -f1)
    rom_sha256=$(sha256sum "$rom_path" | cut -d' ' -f1)
    echo "$rom_sha256 $rom_name" > "${rom_path}.sha256"

    ### Metadados do init_boot 
    boot_sha256=$(sha256sum "$boot_path" | cut -d' ' -f1)
    echo "$boot_sha256 init_boot.img" > "${boot_path}.sha256"

    #### Upload ROM
    rom_output=$("$gofile_script" "$rom_path" 2>&1) \
        || { echo -e "${RED}Upload da ROM falhou:\n$rom_output${RESET}"; return 1; }
    rom_url=$(grep -oP 'https?://[^\s]+' <<< "$rom_output" | head -n1)

    #### Upload init_boot 
    boot_output=$("$gofile_script" "$boot_path" 2>&1) \
        || { echo -e "${RED}Upload do init_boot falhou:\n$boot_output${RESET}"; return 1; }
    boot_url=$(grep -oP 'https?://[^\s]+' <<< "$boot_output" | head -n1)

    #### Resumo
    echo -e "${YELLOW}ROM:${RESET} ${rom_name} (${rom_size})"
    [ -n "$rom_url" ] && echo -e "${YELLOW}Link ROM:${RESET} $rom_url"
    echo -e "${YELLOW}SHA256 ROM:${RESET} $rom_sha256"
    echo
    echo -e "${YELLOW}init_boot:${RESET} init_boot.img"
    [ -n "$boot_url" ] && echo -e "${CYAN}Link Boot:${RESET} $boot_url"
    echo -e "${YELLOW}SHA256 init_boot:${RESET} $boot_sha256"

    [ -n "$rom_url" ] && [ -n "$boot_url" ]
}

#------------------------------------------------------------------------------------------------#
# Build Environment Setup
#------------------------------------------------------------------------------------------------#
echo -e "${YELLOW}Setting up build environment...${RESET}"
source build/envsetup.sh
export BUILD_USERNAME=LineageOS-22.2-MicroG
export BUILD_HOSTNAME=WhoFoss
export SKIP_ABI_CHECKS=true

#------------------------------------------------------------------------------------------------#
# Build
# Start ROM compilation
#------------------------------------------------------------------------------------------------#
echo -e "${YELLOW}Starting build...${RESET}"
# brunch sapphire user || error_exit "Brunch failed"
# upload
