#!/usr/bin/bash

REAL_PATH=$(readlink -f "$0")
BASE_DIR=$(dirname "${REAL_PATH}")

source "${BASE_DIR}/variable.sh" || exit 1
source "${BASE_DIR}/function.sh" || exit 1

[ -f "${LOG_FILE}" ] || touch "${LOG_FILE}"

mkdir -p "${TMP_DIR}" "${PROPRIETARY_FIRMWARE_DIR}" "${AOSP_FIRMWARE_DIR}"

check_bash_version || exit 1
check

case $1 in
    -F)
        case $2 in
            proprietary)
                confirm_category_and_slot "Proprietary Firmware" "PROPRIETARY_FIRMWARE_PARTS" "PROPRIETARY_FIRMWARE_IMGS" "${PROPRIETARY_FIRMWARE_DIR}"
            ;;

            aosp)
                confirm_category_and_slot "AOSP Firmware" "AOSP_FIRMWARE_PARTS" "AOSP_FIRMWARE_IMGS" "${AOSP_FIRMWARE_DIR}"
            ;;

            *)
                log "- Usage: '-F proprietary' 刷写厂商私有固件 '-F aosp' 刷写自定义 ROM 固件"
            ;;
        esac
    ;;   

    -E)
        case $2 in
            proprietary)
                extract_imgs "proprietary-firmware" "$3" "${PROPRIETARY_FIRMWARE_DIR}" "PROPRIETARY_FIRMWARE_PARTS"
            ;;
        
            aosp)
                extract_imgs "aosp-firmware" "$3" "${AOSP_FIRMWARE_DIR}" "AOSP_FIRMWARE_PARTS"
            ;;

            *)
                log "- Usage: '-E proprietary' 提取厂商私有固件 '-E aosp' 提取自定义 ROM 固件"
            ;;
        esac
    ;;

    *)
        log "- Usage: [options] [category] [dir]"
    ;;

esac