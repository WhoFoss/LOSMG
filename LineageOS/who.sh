#!/usr/bin/env bash

#####################################################################
# Autor: WhoFoss
# Programa: los23.sh
# DESCRIÇÃO: Compila o LineageOS 23.2 com MicroG para o sapphire
# Dependências: repo, git, curl, wget, sed, tput, sha256sum
# Recursos: HALs SM6225, MicroG, Signature Spoofing, GoFile
#####################################################################

#####################################
#----------------------------------#
# Cores
#----------------------------------#
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
B=$(tput bold)
RESET=$(tput sgr0)

#####################################
#----------------------------------#
# Setup do Terminal
#----------------------------------#
tput civis                      # esconde o cursor
trap 'tput cnorm' EXIT          # restaura ao sair

#####################################
#----------------------------------#
# Funções Auxiliares
#----------------------------------#

# Imprime mensagem de erro formatada com timestamp e encerra o script.
error_exit() {
    local message="$1"
    local exit_code="${2:-1}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${RED}${timestamp} - ${message}${RESET}" >&2
    exit "$exit_code"
}

# Imprime a mensagem
print_header()
{
    echo "${3:-$B}>>>${RESET} ${1}"
}

# Clona (ou reclona) um repositório git raso em um diretório de destino.
clone_repo()
{
    local repo_url=$1
    local branch=$2
    local dest=$3

    echo "${CYAN}Cloning $dest...${RESET}"

    [ -d "$dest" ] && rm -rf "$dest"

    git clone --depth 1 -b "$branch" "$repo_url" "$dest" || error_exit "Failed to clone $dest"

    print_header "${dest} clone success" "$YELLOW"
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

# Adiciona um pacote ao device.mk do sapphire, sem duplicar.
add_to_device_mk()
{
    local package=$1
    local device_mk="device/xiaomi/sapphire/device.mk"

    [ -f "$device_mk" ] || { echo "${YELLOW}device.mk not found, skipping $package addition${RESET}"; return; }

    if grep -q "^PRODUCT_PACKAGES += $package$" "$device_mk"; then
        echo "${YELLOW}$package already exists in device.mk${RESET}"
    else
        echo "PRODUCT_PACKAGES += $package" >> "$device_mk"
        print_header "$package added to device.mk"
    fi
}

# Aplica o patch de Signature Spoofing em ComputerEngine.java.
patch_signature_spoofing() {
    local COMPUTER_ENGINE="frameworks/base/services/core/java/com/android/server/pm/ComputerEngine.java"

    [ -f "$COMPUTER_ENGINE" ] || error_exit "ComputerEngine.java not found: $COMPUTER_ENGINE"
    [ -f "${COMPUTER_ENGINE}.backup" ] || cp "$COMPUTER_ENGINE" "${COMPUTER_ENGINE}.backup"

    if ! grep -q 'if (!isDebuggable())' "$COMPUTER_ENGINE"; then
        print_header "Signature Spoofing already patched"
        return 0
    fi

    sed -i '/if (!isDebuggable()) {/{N;N;d}' "$COMPUTER_ENGINE"

    grep -q 'if (!isDebuggable())' "$COMPUTER_ENGINE" && error_exit "Signature Spoofing patch failed"
    print_header "Signature Spoofing patch applied"
}

# Adiciona sufixo -MicroG
patch_version_mk()
{
    local version_mk="vendor/lineage/config/version.mk"

    [ -f "$version_mk" ] || error_exit "version.mk not found: $version_mk"
    grep -q "MicroG" "$version_mk" && { print_header "MicroG suffix already patched"; return; }

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
    print_header "MicroG suffix patch applied"
}

# Comenta a linha de GApps no lineage_sapphire.mk.
comentar_gapps()
{
    local mk="device/xiaomi/sapphire/lineage_sapphire.mk"

    [ -f "$mk" ] || { echo "${YELLOW}lineage_sapphire.mk not found, skipping Gapps comment${RESET}"; return; }

    sed -i 's/^-include vendor\/gapps\/arm64\/arm64-vendor.mk/#-include vendor\/gapps\/arm64\/arm64-vendor.mk/' "$mk"
    print_header "Gapps line commented in lineage_sapphire.mk"
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
        lista+="${apps[i]}"
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

# Baixa o manifest do MicroG do repositório remoto.
mg_manifest()
{
    echo "${CYAN}Baixando MicroG Manifest...${RESET}"
    mkdir -p .repo/local_manifests

    local tmp_file remote_url
    tmp_file=$(mktemp)
    remote_url="https://raw.githubusercontent.com/WhoFoss/LOSMG/refs/heads/Lineage-23.2/MG-MANIFEST/microg.xml"

    if ! curl -fsSL -o "$tmp_file" "$remote_url" || [ ! -s "$tmp_file" ]; then
        rm -f "$tmp_file"
        error_exit "Falha ao baixar $remote_url (ou arquivo vazio)"
    fi

    mv -f "$tmp_file" .repo/local_manifests/microg.xml
    print_header "MG manifest baixado"
}

# Instala o script de upload do GoFile e cria o alias "gofile" no bashrc.
gofile_install()
{
    echo "${CYAN}Installing gofile upload tool...${RESET}"
    wget -q https://raw.githubusercontent.com/WhoFoss/LOSMG/refs/heads/Lineage-23.2/gofile/gofile.sh \
        -O "$TARGET_DIR/gofile" && chmod +x "$TARGET_DIR/gofile" || error_exit "Failed to install gofile"

    grep -q 'alias gofile' ~/.bashrc || echo "alias gofile=\"$TARGET_DIR/gofile\"" >> ~/.bashrc

    print_header "gofile installed"
}

# Localiza a ROM mais recente, gera o SHA256 e envia para o GoFile.
upload() {
    local build_dir="out/target/product/sapphire"
    local gofile_script="${TARGET_DIR}/gofile"
    local rom_path boot_path rom_name rom_size rom_sha256
    local boot_sha256 rom_output boot_output rom_url boot_url

    [ -d "$build_dir" ] || { echo "${RED}Build dir não existe: $build_dir${RESET}"; return 1; }
    [ -x "$gofile_script" ] || { echo "${RED}gofile não executável: $gofile_script${RESET}"; return 1; }

    ### Localiza os arquivos
    rom_path=$(ls -t "$build_dir"/lineage-23.2-*sapphire*.zip 2>/dev/null | head -n1)
    boot_path="$build_dir/init_boot.img"

    [ -z "$rom_path" ] && { echo "${YELLOW}ROM não encontrada em $build_dir${RESET}"; return 1; }
    [ -f "$boot_path" ] || { echo "${YELLOW}init_boot.img não encontrado: $boot_path${RESET}"; return 1; }

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
        || { echo "${RED}Upload da ROM falhou:\n$rom_output${RESET}"; return 1; }
    rom_url=$(grep -oP 'https?://[^\s]+' <<< "$rom_output" | head -n1)

    #### Upload init_boot
    boot_output=$("$gofile_script" "$boot_path" 2>&1) \
        || { echo "${RED}Upload do init_boot falhou:\n$boot_output${RESET}"; return 1; }
    boot_url=$(grep -oP 'https?://[^\s]+' <<< "$boot_output" | head -n1)

    #### Resumo
    echo "${CYAN}ROM:${RESET} ${rom_name} (${rom_size})"
    [ -n "$rom_url" ] && echo "${CYAN}Link ROM:${RESET} $rom_url"
    echo "${CYAN}SHA256 ROM:${RESET} $rom_sha256"
    echo
    echo "${CYAN}init_boot:${RESET} init_boot.img"
    [ -n "$boot_url" ] && echo "${CYAN}Link Boot:${RESET} $boot_url"
    echo "${CYAN}SHA256 init_boot:${RESET} $boot_sha256"

    [ -n "$rom_url" ] && [ -n "$boot_url" ]
}


#----------------------------------#
# Script Principal
#----------------------------------#
# Entra (ou cria) o diretório de trabalho do LineageOS-MicroG.
#----------------------------------#
setup_lineage_dir() {
    LINEAGE_DIR="LineageOS-MicroG"
    TARGET_DIR="$HOME/$LINEAGE_DIR"

    [ "$PWD" = "$TARGET_DIR" ] && return

    mkdir -p "$TARGET_DIR" || error_exit "Failed to create $TARGET_DIR"
    cd "$TARGET_DIR" || error_exit "Failed to cd to $TARGET_DIR"
}; clear; check_repo_valid; setup_lineage_dir
echo "${YELLOW}Starting LineageOS 23.2 build script...${RESET}"

#----------------------------------#
# Repository Initialization
#----------------------------------#
echo "${CYAN}Initializing repo...${RESET}"
repo init -u https://github.com/LineageOS/android.git -b lineage-23.2 --git-lfs --depth=1 || error_exit "Repo init failed"
print_header "Repo init success"

clone_repo "https://github.com/saroj-nokia/local_manifests_sapphire" "sapphire16" ".repo/local_manifests"
mg_manifest

#----------------------------------#
# Repository Synchronization
#----------------------------------#
clear; echo "${CYAN}Syncing full repo...${RESET}"
repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags --optimized-fetch --prune || error_exit "Repo sync failed"
print_header "Repo sync success"

# ========================================
# Qualcomm HALs
# Clone the required SM6225 hardware components
# ========================================
clear; echo "${CYAN}Cloning HALs for SM6225...${RESET}"
clone_hal "https://github.com/sapphire-sm6225/android_hardware_qcom-caf_common.git" "hardware/qcom-caf/common" "lineage-23.2"
clone_hal "https://github.com/sapphire-sm6225/vendor_qcom_opensource_agm.git" "hardware/qcom-caf/sm6225/audio/agm" "lineage-22.2-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/vendor_qcom_opensource_arpal-lx.git" "hardware/qcom-caf/sm6225/audio/pal" "lineage-22.0-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/vendor_qcom_opensource_data-ipa-cfg-mgr.git" "hardware/qcom-caf/sm6225/data-ipa-cfg-mgr" "lineage-23.2-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/vendor_qcom_opensource_dataipa.git" "hardware/qcom-caf/sm6225/dataipa" "lineage-23.2-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/hardware_qcom_display.git" "hardware/qcom-caf/sm6225/display" "lineage-22.0-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/hardware_qcom_media.git" "hardware/qcom-caf/sm6225/media" "lineage-23.2-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/hardware_qcom_audio.git" "hardware/qcom-caf/sm6225/audio/primary-hal" "lineage-22.0-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/device_qcom_sepolicy_vndr.git" "device/qcom/sepolicy_vndr/sm6225" "lineage-23.2-caf-sm6225"
print_header "HALs cloned"

#----------------------------------#
# Coisas que voce não precisa saber
#----------------------------------#
gofile_install
comentar_gapps
remove_apps
patch_signature_spoofing
patch_version_mk

#----------------------------------#
# Build Environment Setup
#----------------------------------#
clear; echo "${CYAN}Setting up build environment...${RESET}"
source build/envsetup.sh
export BUILD_USERNAME=WhoFoss
export BUILD_HOSTNAME=LineageOS-23.2
export SKIP_ABI_CHECKS=true
export WITH_GMS=true
mkdir -p out/target/product/sapphire/obj/KERNEL_OBJ/usr
print_header "Build environment ready"

#----------------------------------#
# Build
#----------------------------------#
echo "${RED}Starting build...${RESET}"
brunch sapphire user || error_exit "Brunch failed"
upload
