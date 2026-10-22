#!/usr/bin/env bash

#----------------------------------#
# Cores
#----------------------------------#
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
B=$'\e[1m' # bold
RESET='\033[0m'

#####################################
#----------------------------------#
# Setup do Terminal
#----------------------------------#
echo -en "\033[?25l"  # esconde o cursor
trap 'echo -en "\033[?12l\033[?25h"' EXIT  # restaura ao sair

#####################################
#----------------------------------#
# Funções Auxiliares
#----------------------------------#

# Imprime mensagem de erro formatada com timestamp e encerra o script.
error_exit() {
    local message="$1"
    local exit_code="${2:-1}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[ERROR] ${timestamp} - ${message}${RESET}" >&2
    exit "$exit_code"
}

#----------------------------------#
# Verifica se existe um .repo residual no HOME e aborta caso encontrado.
#----------------------------------#
check_repo_valid() {
    local repo_dir="$HOME/.repo"

    [ -d "$repo_dir" ] || return 0

    echo "[ERROR] $repo_dir found: leftover workspace in home directory"
    { [ ! -f "$repo_dir/manifest.xml" ] && [ ! -L "$repo_dir/manifest.xml" ]; } \
        && echo "[ERROR] Also, this .repo appears incomplete/corrupted (missing manifest.xml)"

    error_exit "Remove or move $repo_dir before continuing (rm -rf $repo_dir)"
}

# Imprime a mensagem
print_header() 
{
    echo -e "${3:-$B}>>>${RESET} ${1}"
}

# Clona (ou reclona) um repositório git raso em um diretório de destino.
clone_repo() 
{
    local repo_url=$1
    local branch=$2
    local dest=$3

    echo -e "${CYAN}Cloning $dest...${RESET}"

    [ -d "$dest" ] && rm -rf "$dest"

    git clone --depth 1 -b "$branch" "$repo_url" "$dest" || error_exit "Failed to clone $dest"

    print_header "${dest} clone success" "#" "$YELLOW"
}

# Clona um repositório de HAL, sobrescrevendo o path caso já exista. 
clone_hal() 
{
    local url=$1
    local path=$2
    local branch=$3
    rm -rf "$path"
    git clone --depth 1 -b "$branch" "$url" "$path" || error_exit "Failed to clone HAL $path"
}

# Aplica o patch de Signature Spoofing em ComputerEngine.java.
patch_signature_spoofing() {
    local COMPUTER_ENGINE="frameworks/base/services/core/java/com/android/server/pm/ComputerEngine.java"

    [ -f "$COMPUTER_ENGINE" ] || error_exit "ComputerEngine.java not found: $COMPUTER_ENGINE"
    grep -q 'if (!isDebuggable())' "$COMPUTER_ENGINE" || error_exit "Signature Spoofing: isDebuggable() block not found"

    sed -i '/if (!isDebuggable()) {/{N;N;d}' "$COMPUTER_ENGINE"

    grep -q 'if (!isDebuggable())' "$COMPUTER_ENGINE" && error_exit "Signature Spoofing patch failed"
}

# Adiciona sufixo -MicroG
patch_version_mk()
{
    local version_mk="vendor/lineage/config/version.mk"

    [ -f "$version_mk" ] || error_exit "version.mk not found: $version_mk"
    grep -q "MicroG" "$version_mk" && return

    sed -i '/^LINEAGE_VERSION_SUFFIX := .*/a \
\
# Add MICROG to suffix if WITH_GMS is true\
ifeq ($(WITH_GMS),true)\
    LINEAGE_VERSION_SUFFIX := $(LINEAGE_VERSION_SUFFIX)-MicroG\
endif\
\
# Add custom build tag/feature to suffix if BUILD_TAG is defined\
ifneq ($(BUILD_TAG),)\
    LINEAGE_VERSION_SUFFIX := $(LINEAGE_VERSION_SUFFIX)-$(BUILD_TAG)\
endif' "$version_mk"

   grep -q "MicroG" "$version_mk" || error_exit "MicroG suffix patch failed"
}

#--------------------------------------------------------------------#
# REMOVEAPPS
#--------------------------------------------------------------------#
# Gera o módulo RemovePackages com a lista de apps a remover e registra no device.mk
remove_apps() {
    local apps=(StorageManager)
    local dir="device/xiaomi/sapphire/RemoveApps"
    local device_mk="device/xiaomi/sapphire/device.mk"
    local lista="" i

    for ((i = 0; i < ${#apps[@]}; i++)); do
        lista+="    ${apps[i]}"
        ((i < ${#apps[@]} - 1)) && lista+=" \\"$'\n'
    done

    echo "$(tput setaf 6)$(tput bold)Gerando módulo RemovePackages...$(tput sgr0)"
    mkdir -p "${dir}" \
        && cat > "${dir}/Android.mk" << EOF
LOCAL_PATH := \$(call my-dir)

include \$(CLEAR_VARS)
LOCAL_MODULE := RemovePackages
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_TAGS := optional
LOCAL_OVERRIDES_PACKAGES := \\
${lista}
LOCAL_UNINSTALLABLE_MODULE := true
LOCAL_CERTIFICATE := PRESIGNED
LOCAL_SRC_FILES := /dev/null
include \$(BUILD_PREBUILT)
EOF

    [ -f "${device_mk}" ] || error_exit "device.mk not found: ${device_mk}"
    grep -q '^# Bluetooth$' "${device_mk}" || error_exit "Marcador '# Bluetooth' não encontrado em ${device_mk}"

    sed -i '/^PRODUCT_PACKAGES += RemovePackages$/{N;/\n$/d}' "${device_mk}" \
        && sed -i '/^PRODUCT_PACKAGES += RemovePackages$/d' "${device_mk}" \
        && sed -i '0,/^# Bluetooth$/s/^# Bluetooth$/PRODUCT_PACKAGES += RemovePackages\n\n# Bluetooth/' "${device_mk}"

    print_header "Apps removidos: ${apps[*]}"
}

#####################################
#----------------------------------#
# Script Principal
#----------------------------------#

setup_lineage_dir() {
    LINEAGE_DIR="LOSMG-24"
    TARGET_DIR="$HOME/$LINEAGE_DIR"

    [ "$PWD" = "$TARGET_DIR" ] && return

    mkdir -p "$TARGET_DIR" || error_exit "Failed to create $TARGET_DIR"
    cd "$TARGET_DIR" || error_exit "Failed to cd to $TARGET_DIR"
}; clear; check_repo_valid; setup_lineage_dir
echo -e "${YELLOW}Starting LineageOS 24.0 build script...${RESET}"

# ========================================
# Repository Initialization
# ========================================
echo -e "${CYAN}Initializing repo...${RESET}"
repo init -u https://github.com/LineageOS/android.git -b lineage-24.0 --git-lfs --depth=1 || error_exit "Repo init failed"
print_header "Repo init success"

clone_repo "https://github.com/saroj-nokia/local_manifests_sapphire" "sapphire17" ".repo/local_manifests"

# ========================================
# MG Manifest
# Baixa o manifest do MicroG do repositorio remoto
# ========================================
mg_manifest() {
    echo -e "${CYAN}Baixando MicroG Manifest...${RESET}"
    mkdir -p .repo/local_manifests

    local tmp_file remote_url
    tmp_file=$(mktemp)
    remote_url="https://raw.githubusercontent.com/WhoFoss/LOSMG/refs/heads/main/MG-MANIFEST/microg.xml"

    if ! curl -fsSL -o "$tmp_file" "$remote_url" || [ ! -s "$tmp_file" ]; then
        rm -f "$tmp_file"
        error_exit "Falha ao baixar $remote_url (ou arquivo vazio)"
    fi

    mv -f "$tmp_file" .repo/local_manifests/microg.xml
    print_header "MG manifest baixado"
}; mg_manifest


# ========================================
# Repository Synchronization
# ========================================
clear; echo -e "${CYAN}Syncing full repo...${RESET}"
repo sync -c -j16 --force-sync --no-clone-bundle --no-tags --optimized-fetch --prune || error_exit "Repo sync failed"
print_header "Repo sync success"

# ========================================
# Qualcomm HALs
# Clone the required SM6225 hardware components
# ========================================
clear; echo -e "${CYAN}Cloning HALs for SM6225...${RESET}"
clone_hal "https://github.com/sapphire-sm6225/android_hardware_qcom-caf_common.git" "hardware/qcom-caf/common" "lineage-24.0"
clone_hal "https://github.com/sapphire-sm6225/vendor_qcom_opensource_agm.git" "hardware/qcom-caf/sm6225/audio/agm" "lineage-24.0-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/vendor_qcom_opensource_arpal-lx.git" "hardware/qcom-caf/sm6225/audio/pal" "lineage-24.0-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/vendor_qcom_opensource_data-ipa-cfg-mgr.git" "hardware/qcom-caf/sm6225/data-ipa-cfg-mgr" "lineage-24.0-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/vendor_qcom_opensource_dataipa.git" "hardware/qcom-caf/sm6225/dataipa" "lineage-24.0-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/hardware_qcom_display.git" "hardware/qcom-caf/sm6225/display" "lineage-24.0-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/hardware_qcom_media.git" "hardware/qcom-caf/sm6225/media" "lineage-24.0-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/hardware_qcom_audio.git" "hardware/qcom-caf/sm6225/audio/primary-hal" "lineage-24.0-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/device_qcom_sepolicy_vndr.git" "device/qcom/sepolicy_vndr/sm6225" "lineage-24.0-caf-sm6225"
print_header "HALs cloned"

# Instala o script de upload do GoFile e cria o alias "gofile" no bashrc.
gofile_install()
{
echo -e "${CYAN}Installing gofile upload tool...${RESET}"
wget -q https://raw.githubusercontent.com/kenway214/GoFile-Upload-Script/master/upload.sh \
    -O ~/LOSMG-24/gofile && chmod +x ~/LOSMG-24/gofile
if ! grep -q 'alias gofile' ~/.bashrc; then
    echo 'alias gofile="~/LOSMG-24/gofile"' >> ~/.bashrc
fi
source ~/.bashrc 2>/dev/null || true
 print_header "gofile installed"
}

# Substitui o lineage_sapphire.mk do device por uma versão sem GApps.
rgapps()
{
    local MK_FILE="device/xiaomi/sapphire/lineage_sapphire.mk"
    local REMOTE_URL="https://raw.githubusercontent.com/WhoFoss/LOSMG-24/refs/heads/main/sapphire.mk/lineage_sapphire.mk"
    local TMP_FILE

    [ -f "$MK_FILE" ] || error_exit "$MK_FILE nao encontrado"

    TMP_FILE=$(mktemp)

    if ! curl -fsSL -o "$TMP_FILE" "$REMOTE_URL" || [ ! -s "$TMP_FILE" ]; then
        rm -f "$TMP_FILE"
        error_exit "Falha ao baixar $REMOTE_URL"
    fi

    mv -f "$TMP_FILE" "$MK_FILE"
}; rgapps

#----------------------------------#
# Coisas que voce não precisa saber
#----------------------------------#
patch_signature_spoofing
patch_version_mk
remove_apps
gofile_install

#========================================
# Build Environment Setup
# ========================================
clear; echo -e "${CYAN}Setting up build environment...${RESET}"
source build/envsetup.sh
export BUILD_USERNAME=LineageOS-24.0-MicroG
export BUILD_HOSTNAME=WhoFoss
export SKIP_ABI_CHECKS=true
export WITH_GMS=true
mkdir -p out/target/product/sapphire/obj/KERNEL_OBJ/usr

# ========================================
# Build
# ========================================
echo -e "${CYAN}Starting build...${RESET}"
 # clear; brunch sapphire user || error_exit "Brunch failed"

# Localiza a ROM mais recente, gera o SHA256 e envia para o GoFile.
upload() {
    local build_dir="out/target/product/sapphire"
    local gofile_script="${HOME}/LOSMG-24/gofile"
    local rom_path boot_path rom_name rom_size rom_sha256
    local boot_sha256 rom_output boot_output rom_url boot_url

    [ -d "$build_dir" ] || { echo -e "${RED}Build dir não existe: $build_dir${RESET}"; return 1; }
    [ -x "$gofile_script" ] || { echo -e "${RED}gofile não executável: $gofile_script${RESET}"; return 1; }

    ### Localiza os arquivos 
    rom_path=$(ls -t "$build_dir"/lineage-24.0-*-UNOFFICIAL-sapphire*.zip 2>/dev/null | head -n1)
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
    echo -e "${CYAN}ROM:${RESET} ${rom_name} (${rom_size})"
    [ -n "$rom_url" ] && echo -e "${CYAN}Link ROM:${RESET} $rom_url"
    echo -e "${CYAN}SHA256 ROM:${RESET} $rom_sha256"
    echo
    echo -e "${CYAN}init_boot:${RESET} init_boot.img"
    [ -n "$boot_url" ] && echo -e "${CYAN}Link Boot:${RESET} $boot_url"
    echo -e "${CYAN}SHA256 init_boot:${RESET} $boot_sha256"

    [ -n "$rom_url" ] && [ -n "$boot_url" ]
}
