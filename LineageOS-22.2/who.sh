#!/usr/bin/env bash
#####################################################################
#                                                                   #
# Autor: WhoFoss <https://github.com/WhoFoss>                       #
# Créditos: Saroj-Tajpuriya - (disponibilizou a device tree)        #
# Créditos: Angelpro09xd - (Por me ensinar a compilar).             #
# Créditos: Sem nome - (Por me ensinar a remover apps)              #
#                                                                   #
# DESCRIÇÃO: script automatizado do LineageOS 22.2 com MicroG para  #
#            o Xiaomi Redmi Note 13 4G (sapphire, SM6225/SD685).    #
#            Faz repo init/sync, clone de device tree/HALs/pacotes  #
#            modificados, manifest local do MicroG, patches         #
#            (signature spoofing, sufixo de versão), instalação de  #
#            apps, remoção dos GApps, preparo                       #
#            do ambiente de build e upload da ROM via GoFile.       #
#                                                                   #
#####################################################################

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
# Verifica se existe um .repo residual no HOME e aborta caso encontrado. - 29/09/2026
#----------------------------------#
check_repo_valid() {
    local repo_dir="$HOME/.repo"

    if [ -d "$repo_dir" ]; then
        echo "[ERROR] $repo_dir found: leftover workspace in home directory"

        if [ ! -f "$repo_dir/manifest.xml" ] && [ ! -L "$repo_dir/manifest.xml" ]; then
            echo "[ERROR] Also, this .repo appears incomplete/corrupted (missing manifest.xml)"
        fi

        error_exit "Remove or move $repo_dir before continuing (rm -rf $repo_dir)"
    fi
}

# Imprime a mensagem - 29/09/2026
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

# Adiciona um pacote em PRODUCT_PACKAGES do device.mk - 29/09/2026
add_to_device_mk()
{
    local package=$1
    local device_mk="device/xiaomi/sapphire/device.mk"

    [ -f "$device_mk" ] || error_exit "device.mk not found: $device_mk"
    grep -qxF "PRODUCT_PACKAGES += $package" "$device_mk" && return

    echo "PRODUCT_PACKAGES += $package" >> "$device_mk"
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

#####################################################################
# Autor: WhoFoss
# Programa: IronFox Browser Prebuilt
# DESCRIÇÃO: Baixa o APK do IronFox (fork do Firefox) e gera o
#            Android.bp para importação prebuilt. Substitui Browser2 e Jelly.
# Dependências: wget, add_to_device_mk
# Recursos: Versão 157.0.1 | Licença MPL-2.0
#           https://gitlab.com/ironfox-oss/IronFox
#           https://ironfoxoss.org/releases/
#####################################################################

#--------------------------------------------------------------------#
# IRONFOX
#--------------------------------------------------------------------#

# Baixa o APK do IronFox, gera o Android.bp e registra no device.mk
install_ironfox() {
    local versao="157.0.1"
    local dir="device/xiaomi/sapphire/prebuilt/ironfox"
    local url="https://releases.ironfoxoss.org/ironfox/releases/${versao}/arm64-v8a/ironfox-${versao}-arm64-v8a.apk"

    echo "$(tput setaf 6)$(tput bold)Baixando IronFox ${versao}...$(tput sgr0)"
    mkdir -p "${dir}" \
        && wget -q --show-progress -O "${dir}/IronFox.apk.tmp" "${url}" \
        && mv "${dir}/IronFox.apk.tmp" "${dir}/IronFox.apk" \
        || { rm -f "${dir}/IronFox.apk.tmp"; echo "$(tput setaf 1)Falha ao baixar o IronFox.apk$(tput sgr0)"; return 1; }

    cat > "${dir}/Android.bp" << 'EOF'
android_app_import {
    name: "IronFox",
    apk: "IronFox.apk",
    presigned: true,
    preprocessed: true,
    skip_preprocessed_apk_checks: true,
    product_specific: true,
    dex_preopt: {
        enabled: false,
    },
    overrides: ["Browser2", "Jelly"],
}

install_davx5() 
{
    echo -e "${YELLOW}Baixando DAVx5 (v4.5.19-ose)...${RESET}"

    local target_dir="device/xiaomi/sapphire/prebuilt/davx5"
    mkdir -p "$target_dir"

    wget -q --show-progress -O "$target_dir/DAVx5.apk" \
        "https://f-droid.org/repo/at.bitfire.davdroid_405190003.apk" \
        || { echo "ERRO: Falha ao baixar DAVx5.apk"; return 1; }

    cat > "$target_dir/Android.bp" << 'EOF'
android_app_import {
    name: "DAVx5",
    apk: "DAVx5.apk",
    presigned: true,
    preprocessed: true,
    product_specific: true,
    dex_preopt: {
        enabled: false,
    },
}
EOF
    add_to_device_mk "DAVx5"
}

# Baixa o APK do Thunderbird e gera o Android.bp para importação prebuilt.
install_thunderbird() 
{
    echo -e "${CYAN}Cloning Thunderbird prebuilt...${RESET}"
    mkdir -p device/xiaomi/sapphire/prebuilt/thunderbird
    wget -q --show-progress -O device/xiaomi/sapphire/prebuilt/thunderbird/Thunderbird.apk \
        "https://f-droid.org/repo/net.thunderbird.android_23.apk" \
        || { echo "[ERRO] Falha ao baixar Thunderbird.apk"; return 1; }

    cat > device/xiaomi/sapphire/prebuilt/thunderbird/Android.bp << 'EOF'
android_app_import {
    name: "Thunderbird",
    apk: "Thunderbird.apk",
    presigned: true,
    preprocessed: true,
    dex_preopt: {
        enabled: false,
    },
}
EOF
    add_to_device_mk "Thunderbird"
}

##################################################
# AuroraStore
# --------------------------------------------------
# Baixa Android.mk, CleanSpec.mk e aurorasetup.sh do proprio repo, depois roda o
# aurorasetup.sh para baixar o APK mais recente.
# Baixa os arquivos do AuroraStore e roda o aurorasetup.sh para obter o APK.
install_aurorastore()
{
    echo -e "${CYAN}Baixando AuroraStore...${RESET}"

    local BASE_URL="https://raw.githubusercontent.com/WhoFoss/LOSMG/main/AuroraStore"
    local files=("Android.mk" "CleanSpec.mk" "aurorasetup.sh")
    local f

    rm -rf vendor/aurora && mkdir -p vendor/aurora

    for f in "${files[@]}"; do
        curl -fsSL -o "vendor/aurora/$f" "$BASE_URL/$f" || error_exit "Falha ao baixar $f"
    done

    chmod +x vendor/aurora/aurorasetup.sh

    echo -e "${CYAN}Rodando aurorasetup.sh (baixa o APK)...${RESET}"
    bash vendor/aurora/aurorasetup.sh || error_exit "aurorasetup.sh falhou"

    add_to_device_mk "AuroraStore"
}

install_gramophone() {
    echo -e "${CYAN}Cloning Gramophone prebuilt...${RESET}"
    mkdir -p device/xiaomi/sapphire/prebuilt/gramophone
    
    wget -q --show-progress -O device/xiaomi/sapphire/prebuilt/gramophone/Gramophone.apk \
        "https://f-droid.org/repo/org.akanework.gramophone_24.apk" \
        || { echo "ERRO: Falha ao baixar Gramophone.apk"; return 1; }
    
    cat > device/xiaomi/sapphire/prebuilt/gramophone/Android.bp << 'EOF'
android_app_import {
    name: "Gramophone",
    apk: "Gramophone.apk",
    presigned: true,
    preprocessed: true,
    product_specific: true,
    dex_preopt: {
        enabled: false,
    },
    overrides: ["Twelve"],
}
EOF
    add_to_device_mk "Gramophone"
}

#####################################
#----------------------------------#
# Script Principal
#----------------------------------#

# Dei uma pequena melhorada nessa função. o intuito é diminuir as linhas e diminuir as funções inúteis - 29/09/2026
setup_lineage_dir() {
    LINEAGE_DIR="LOSMG"
    TARGET_DIR="$HOME/$LINEAGE_DIR"

    [ "$PWD" = "$TARGET_DIR" ] && return

    mkdir -p "$TARGET_DIR" || error_exit "Failed to create $TARGET_DIR"
    cd "$TARGET_DIR" || error_exit "Failed to cd to $TARGET_DIR"
}; clear; check_repo_valid; setup_lineage_dir
echo -e "${YELLOW}Starting LineageOS 22.2 build script...${RESET}"

# ========================================
# Repository Initialization
# Initialize the LineageOS source repository
# ========================================
echo -e "${CYAN}Initializing repo...${RESET}"
repo init -u https://github.com/LineageOS/android.git -b lineage-22.2 --git-lfs --depth=1 || error_exit "Repo init failed"
print_header "Repo init success"

clone_repo "https://github.com/saroj-nokia/local_manifests_sapphire" "sapphire15" ".repo/local_manifests"


# ========================================
# MG Manifest
# Baixa o manifest do MicroG do repositorio remoto
# ========================================
MG-Manifest()
{
echo -e "${CYAN}Baixando MicroG Manifest...${RESET}"
mkdir -p .repo/local_manifests

TMP_FILE=$(mktemp)
REMOTE_URL="https://raw.githubusercontent.com/WhoFoss/LOSMG/refs/heads/main/MG-MANIFEST/microg.xml"

if ! curl -fsSL -o "$TMP_FILE" "$REMOTE_URL"; then
    rm -f "$TMP_FILE"
    error_exit "Falha ao baixar $REMOTE_URL"
fi

if [ ! -s "$TMP_FILE" ]; then
    rm -f "$TMP_FILE"
    error_exit "Arquivo vazio"
fi

mv -f "$TMP_FILE" .repo/local_manifests/microg.xml

print_header "MG manifest baixado"
}; MG-Manifest

# ========================================
# Repository Synchronization
# Download and synchronize the complete source tree
# ========================================
clear; echo -e "${CYAN}Syncing full repo...${RESET}"
repo sync -c -j4 --force-sync --no-clone-bundle --no-tags --optimized-fetch --prune
print_header "Repo sync success"

# ========================================
# Qualcomm HALs
# Clone the required SM6225 hardware components
# ========================================
clear; echo -e "${CYAN}Cloning HALs for SM6225...${RESET}"
clone_hal "https://github.com/sapphire-sm6225/android_hardware_qcom-caf_common.git" "hardware/qcom-caf/common" "lineage-22.2"
clone_hal "https://github.com/sapphire-sm6225/vendor_qcom_opensource_agm.git" "hardware/qcom-caf/sm6225/audio/agm" "lineage-22.2-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/vendor_qcom_opensource_arpal-lx.git" "hardware/qcom-caf/sm6225/audio/pal" "lineage-22.0-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/vendor_qcom_opensource_data-ipa-cfg-mgr.git" "hardware/qcom-caf/sm6225/data-ipa-cfg-mgr" "lineage-22.0-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/vendor_qcom_opensource_dataipa.git" "hardware/qcom-caf/sm6225/dataipa" "lineage-22.0-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/hardware_qcom_display.git" "hardware/qcom-caf/sm6225/display" "lineage-22.0-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/hardware_qcom_media.git" "hardware/qcom-caf/sm6225/media" "lineage-22.0-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/hardware_qcom_audio.git" "hardware/qcom-caf/sm6225/audio/primary-hal" "lineage-22.0-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/device_qcom_sepolicy_vndr.git" "device/qcom/sepolicy_vndr/sm6225" "lineage-22.0-caf-sm6225"
print_header "HALs cloned"

# Instala o script de upload do GoFile e cria o alias "gofile" no bashrc.
gofile_install()
{
echo -e "${CYAN}Installing gofile upload tool...${RESET}"
wget -q https://raw.githubusercontent.com/kenway214/GoFile-Upload-Script/master/upload.sh \
    -O ~/LOSMG/gofile && chmod +x ~/LOSMG/gofile
if ! grep -q 'alias gofile' ~/.bashrc; then
    echo 'alias gofile="~/LOSMG/gofile"' >> ~/.bashrc
fi
source ~/.bashrc 2>/dev/null || true
 print_header "gofile installed"
}

# Substitui o lineage_sapphire.mk do device por uma versão sem GApps.
rgapps()
{
    local MK_FILE="device/xiaomi/sapphire/lineage_sapphire.mk"
    local REMOTE_URL="https://raw.githubusercontent.com/WhoFoss/LOSMG/refs/heads/main/sapphire.mk/lineage_sapphire.mk"
    local TMP_FILE

    [ -f "$MK_FILE" ] || error_exit "$MK_FILE nao encontrado"

    TMP_FILE=$(mktemp)

    if ! curl -fsSL -o "$TMP_FILE" "$REMOTE_URL" || [ ! -s "$TMP_FILE" ]; then
        rm -f "$TMP_FILE"
        error_exit "Falha ao baixar $REMOTE_URL"
    fi

    mv -f "$TMP_FILE" "$MK_FILE"
}; rgapps

#####################################
#----------------------------------#
# Coisas que voce não precisa saber
#----------------------------------#
patch_signature_spoofing
patch_version_mk
install_ironfox
# install_thunderbird
# install_aurorastore
install_davx5
#install_gramophone
gofile_install


# ========================================
# Build Environment Setup
# ========================================
clear; echo -e "${CYAN}Setting up build environment...${RESET}"
source build/envsetup.sh
export BUILD_USERNAME=LineageOS-22.2-MicroG
export BUILD_HOSTNAME=WhoFoss
export SKIP_ABI_CHECKS=true
export WITH_GMS=true
mkdir -p out/target/product/sapphire/obj/KERNEL_OBJ/usr

# ========================================
# Build
# Start ROM compilation
# ========================================
echo -e "${CYAN}Starting build...${RESET}"
clear; brunch sapphire user || error_exit "Brunch failed"

# ========================================
# ROM Upload to GoFile
# Find, checksum, and upload the latest ROM
# ========================================
# Localiza a ROM mais recente, gera o SHA256 e envia para o GoFile
# (usando o script local se existir)
upload(){
    # Upload ROM to GoFile
    BUILD_DIR="out/target/product/sapphire"
    GOFILE_SCRIPT="${HOME}/LOSMG/gofile"
    ROM_URL=""
    ROM_SHA256=""
    ROM_SIZE=""

    if [ ! -d "$BUILD_DIR" ]; then
        echo -e "${RED}ERROR: Build directory not found: $BUILD_DIR${RESET}"
        return 1
    fi

    # Find the most recent ROM (by modification date)
    ROM_NAME=$(ls -t "$BUILD_DIR" 2>/dev/null | grep "lineage-22.2-.*-UNOFFICIAL-sapphire.*\.zip$" | head -n 1)

    if [ -n "$ROM_NAME" ]; then
        ROM_PATH="$BUILD_DIR/$ROM_NAME"
        ROM_SIZE=$(du -h "$ROM_PATH" | cut -f1)
        ROM_SHA256=$(sha256sum "$ROM_PATH" | cut -d' ' -f1)
        echo "$ROM_SHA256  $ROM_NAME" > "${ROM_PATH}.sha256"

        # Try using the local script first
        if [ -x "$GOFILE_SCRIPT" ]; then
            ROM_OUTPUT=$("$GOFILE_SCRIPT" "$ROM_PATH" 2>&1)
            UPLOAD_EXIT=$?
        else
            TMP_SCRIPT=$(mktemp)
            if curl -fsSL -o "$TMP_SCRIPT" "https://raw.githubusercontent.com/saroj-nokia/GoFile-Upload/refs/heads/master/upload.sh"; then
                ROM_OUTPUT=$(bash "$TMP_SCRIPT" "$ROM_PATH" 2>&1)
                UPLOAD_EXIT=$?
            else
                ROM_OUTPUT="Failed to download fallback script"
                UPLOAD_EXIT=1
            fi
            rm -f "$TMP_SCRIPT"
        fi

        if [ $UPLOAD_EXIT -eq 0 ]; then
            ROM_URL=$(echo "$ROM_OUTPUT" | grep -oP 'https?://[^\s]+' | head -n1)
            if [ -z "$ROM_URL" ]; then
                echo -e "${YELLOW}Warning: upload completed but the URL could not be extracted${RESET}"
                echo -e "${YELLOW}Output: $ROM_OUTPUT${RESET}"
            fi
        else
            echo -e "${RED}Failed to upload ROM to GoFile. Code: $UPLOAD_EXIT${RESET}"
            echo -e "${RED}$ROM_OUTPUT${RESET}"
        fi
    else
        echo -e "${YELLOW}ROM not found in $BUILD_DIR${RESET}"
        echo -e "${YELLOW}Upload skipped${RESET}"
        return 1
    fi

    print_header "Upload complete"
    echo -e "${CYAN}ROM:${RESET}${ROM_NAME:-N/A}"
    echo -e "${CYAN}Size:${RESET}${ROM_SIZE:-N/A}"
    if [ -n "$ROM_URL" ]; then
        echo -e "${CYAN}Link:${RESET}$ROM_URL"
    fi
    if [ -n "$ROM_SHA256" ]; then
        echo -e "${CYAN}SHA256:${RESET}$ROM_SHA256"
    fi

    [ -n "$ROM_URL" ] && return 0 || return 1
}; upload
