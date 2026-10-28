#!/usr/bin/env bash
#####################################################################
# Créditos: Saroj-Tajpuriya - (disponibilizou a device tree)        #
# Créditos: Angelpro09xd - (Por me ensinar a compilar).             #
# Créditos: fwlta - (Por me ensinar a remover apps)                 #
#####################################################################

#------------------------------------------------------------------------------------------------#
# Cores
#------------------------------------------------------------------------------------------------#
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput bold)$(tput setaf 3)
CYAN=$(tput setaf 6)
DIM=$(tput dim)
RESET=$(tput sgr0)

#------------------------------------------------------------------------------------------------#
# Configurações
#------------------------------------------------------------------------------------------------#
FORGE_URL="https://github.com/SapphireForge"

#------------------------------------------------------------------------------------------------#
# Setup do Terminal
#------------------------------------------------------------------------------------------------#
tput civis                    # esconde o cursor
trap 'tput cnorm' EXIT        # restaura o cursor ao sair

#------------------------------------------------------------------------------------------------#
# Funções Auxiliares
#------------------------------------------------------------------------------------------------#

# Imprime mensagem de erro com timestamp e encerra o script.
error_exit() {
    local message="$1"
    local exit_code="${2:-1}"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo -e "${RED}${timestamp} - ${message}${RESET}" >&2
    exit "$exit_code"
}

# Imprime uma etapa concluída com o tempo decorrido; $2 opcional define a cor.
print_header() {
    local cor="${2:-$GREEN}"

    printf '%s%s%s %s(%dm%02ds)%s\n' "$cor" "$1" "$RESET" "$DIM" $((SECONDS / 60)) $((SECONDS % 60)) "$RESET"
}

# Clona (ou reclona) um repositório git raso em um diretório de destino.
clone_repo() {
    local repo_url=$1
    local branch=$2
    local dest=$3

    echo -e "${YELLOW}Cloning $dest...${RESET}"

    [ -d "$dest" ] && rm -rf "$dest"

    git clone --depth 1 -b "$branch" "$repo_url" "$dest" || error_exit "Failed to clone $dest"

    print_header "${dest} clone success" "$YELLOW"
}

# Clona um repositório de HAL, sobrescrevendo o path caso já exista.
clone_hal() {
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

# Adiciona o sufixo -MicroG na versão do LineageOS.
patch_version_mk() {
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

# Cria o diretório de trabalho e entra nele, caso ainda não esteja.
setup_lineage_dir() {
    LINEAGE_DIR="LOSMG"
    TARGET_DIR="$HOME/$LINEAGE_DIR"

    [ "$PWD" = "$TARGET_DIR" ] && return

    mkdir -p "$TARGET_DIR" || error_exit "Failed to create $TARGET_DIR"
    cd "$TARGET_DIR" || error_exit "Failed to cd to $TARGET_DIR"
}

# Instala o script de upload do GoFile e cria o alias "gofile" no bashrc.
gofile_install() {
    echo -e "${YELLOW}Installing gofile upload tool...${RESET}"
    wget -q https://raw.githubusercontent.com/kenway214/GoFile-Upload-Script/master/upload.sh \
        -O "$TARGET_DIR/gofile" && chmod +x "$TARGET_DIR/gofile" || error_exit "Failed to install gofile"

    grep -q 'alias gofile' ~/.bashrc || echo "alias gofile=\"$TARGET_DIR/gofile\"" >> ~/.bashrc
}

# Localiza a ROM mais recente, gera o SHA256 e envia para o GoFile.
upload() {
    local build_dir="out/target/product/sapphire"
    local gofile_script="$TARGET_DIR/gofile"
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
# Começa aqui
#------------------------------------------------------------------------------------------------#
clear; setup_lineage_dir
echo -e "${YELLOW}Starting LineageOS 22.2 build script...${RESET}"

#------------------------------------------------------------------------------------------------#
# Repository Initialization
# Initialize the LineageOS source repository
#------------------------------------------------------------------------------------------------#
echo -e "${YELLOW}Initializing repo...${RESET}"
repo init -u https://github.com/LineageOS/android.git -b lineage-22.2 --git-lfs --depth=1 || error_exit "Repo init failed"
print_header "Repo init success"

#------------------------------------------------------------------------------------------------#
# Local Manifests
# Manifest único da SapphireForge (device, vendor, kernel, MicroG e hardware)
#------------------------------------------------------------------------------------------------#
clone_repo "$FORGE_URL/local_manifests_sapphire" "sapphire15" ".repo/local_manifests"

#------------------------------------------------------------------------------------------------#
# Repository Synchronization
# Download and synchronize the complete source tree
#------------------------------------------------------------------------------------------------#
clear; echo -e "${YELLOW}Syncing full repo...${RESET}"
repo sync -c -j15 --force-sync --no-clone-bundle --no-tags --optimized-fetch --prune || error_exit "Repo sync failed"
print_header "Repo sync success"

#------------------------------------------------------------------------------------------------#
# Qualcomm HALs
# Clone the required SM6225 hardware components
#------------------------------------------------------------------------------------------------#
clear; echo -e "${YELLOW}Cloning HALs for SM6225...${RESET}"
clone_hal "$FORGE_URL/android_hardware_qcom-caf_common.git" "hardware/qcom-caf/common" "lineage-22.2"
clone_hal "$FORGE_URL/vendor_qcom_opensource_agm.git" "hardware/qcom-caf/sm6225/audio/agm" "lineage-22.2-caf-sm6225"
clone_hal "$FORGE_URL/vendor_qcom_opensource_arpal-lx.git" "hardware/qcom-caf/sm6225/audio/pal" "lineage-22.0-caf-sm6225"
clone_hal "$FORGE_URL/vendor_qcom_opensource_data-ipa-cfg-mgr.git" "hardware/qcom-caf/sm6225/data-ipa-cfg-mgr" "lineage-22.0-caf-sm6225"
clone_hal "$FORGE_URL/vendor_qcom_opensource_dataipa.git" "hardware/qcom-caf/sm6225/dataipa" "lineage-22.0-caf-sm6225"
clone_hal "$FORGE_URL/hardware_qcom_display.git" "hardware/qcom-caf/sm6225/display" "lineage-22.0-caf-sm6225"
clone_hal "$FORGE_URL/hardware_qcom_media.git" "hardware/qcom-caf/sm6225/media" "lineage-22.0-caf-sm6225"
clone_hal "$FORGE_URL/hardware_qcom_audio.git" "hardware/qcom-caf/sm6225/audio/primary-hal" "lineage-22.0-caf-sm6225"
clone_hal "$FORGE_URL/device_qcom_sepolicy_vndr.git" "device/qcom/sepolicy_vndr/sm6225" "lineage-22.0-caf-sm6225"
print_header "HALs cloned"

#------------------------------------------------------------------------------------------------#
# Coisas que voce não precisa saber
#------------------------------------------------------------------------------------------------#
patch_signature_spoofing
patch_version_mk
gofile_install

#------------------------------------------------------------------------------------------------#
# Build Environment Setup
#------------------------------------------------------------------------------------------------#
clear; echo -e "${YELLOW}Setting up build environment...${RESET}"
source build/envsetup.sh
export BUILD_USERNAME=LineageOS-22.2-MicroG
export BUILD_HOSTNAME=WhoFoss
export SKIP_ABI_CHECKS=true
export WITH_GMS=true
mkdir -p out/target/product/sapphire/obj/KERNEL_OBJ/usr

#------------------------------------------------------------------------------------------------#
# Build
# Start ROM compilation
#------------------------------------------------------------------------------------------------#
echo -e "${YELLOW}Starting build...${RESET}"
brunch sapphire user || error_exit "Brunch failed"
upload
