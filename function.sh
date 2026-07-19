# !/usr/bin/bash

# 分区元组校验函数
function check_partition_img_mapping() {

    # 使用 nameref 引用数组
    local category="$1"
    local -n parts_ref="$2"
    local -n imgs_ref="$3"

    local base_dir="$4"

    # 检查数组长度是否相同
    if [ "${#parts_ref[@]}" -ne "${#imgs_ref[@]}" ]; then
        log "× [${category}] [(${#parts_ref[@]})] [(${#imgs_ref[@]})] E Error"
        return 1
    fi

    # 检查数组索引是否连续且从0开始
    local expected_index=0
    for i in "${!parts_ref[@]}"; do
        if [ "$i" -ne "$expected_index" ]; then
            log "× [${category}] [${expected_index}] [${i}] M Error"
            return 1
        fi
        ((expected_index++))
    done

    # 检查每个分区是否都有对应的镜像，并进行详细验证
    for i in "${!parts_ref[@]}"; do
        # 检查分区名是否为空
        if [ -z "${parts_ref[$i]}" ]; then
            log "× [${category}] [${i}] [${parts_ref[$i]}] N NULL [${imgs_ref[$i]}]"
            return 1
        fi
    
        # 检查镜像名是否为空
        if [ -z "${imgs_ref[$i]}" ]; then
            log "× [${category}] [${i}] [${imgs_ref[$i]}] N NULL [${parts_ref[$i]}]"
            return 1
        fi
    
        # 检查分区名格式（只允许字母、数字、下划线、连字符）
        if ! [[ "${parts_ref[$i]}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            log "× [${category}] [${i}] [${parts_ref[$i]}] N Error [${imgs_ref[$i]}]"
            return 1
        fi
    
        # 检查镜像文件扩展名
        if ! [[ "${imgs_ref[$i]}" =~ \.img$ ]]; then
            log "× [${category}] [${i}] [${imgs_ref[$i]}] NE Error [${parts_ref[$i]}]"
            return 1
        fi
    
        # 检查镜像文件是否存在
        if [ ! -f "${base_dir}/${imgs_ref[$i]}" ]; then
            log "× [${category}] [${i}] [${imgs_ref[$i]}] L NULL [${parts_ref[$i]}]"
            return 1
        fi
    done

    log "√ [${category}] [${#parts_ref[@]}] [${#imgs_ref[@]}] OK"
    return 0

}

# 区分所给整数是几个2的幂相加（这个整数事先必须是2的n个任意次幂相加）
function count_addends() {
    local input="$1"
    local count=0
    
    # 核心逻辑：利用位移统计二进制中 1 的个数
    # 只要 input 大于 0，就继续循环
    while [ "$input" -gt 0 ]; do
        # 方法：检查最后一位是否为 1
        # 按位与运算 (&)：如果 input 是奇数，说明最后一位是 1
        if [ $((input & 1)) -eq 1 ]; then
            ((count++))
        fi
        
        # 右移一位 (>> 1)：相当于除以 2，丢弃已经检查过的最后一位
        input=$((input >> 1))
    done
    
    # 不用 return 是因为其只能返回0到255的退出状态码，这里需要返回计算的结果而不是状态码
    echo "$count"
}

# 检测 Bash Shell 版本
function check_bash_version() {
    # 提取主版本号和次版本号
    local major_version=$(echo "$BASH_VERSION" | cut -d. -f1 | grep -o '[0-9]*')
    local minor_version=$(echo "$BASH_VERSION" | cut -d. -f2 | grep -o '[0-9]*')
    
    if [ "$major_version" -lt 4 ] || ([ "$major_version" -eq 4 ] && [ "$minor_version" -lt 3 ]); then
        log "× 错误：需要 Bash 4.3 或更高版本！"
        return 1
    else
        return 0
    fi
}

# 刷写菜单
function confirm_category_and_slot() {
    
    local category="$1"
    local parts_ref="$2"
    local imgs_ref="$3"
    local base_dir="$4"
    local slot

    while true; do

        read -p "- 请输入 [${category}] 刷入槽位 (a/b/all)：" slot

            # 标准化输入，转换为小写
            slot=$(echo "$slot" | tr '[:upper:]' '[:lower:]')

            case $slot in
                a | b | all)
                    run_flash_batch "$category" "$slot" "$parts_ref" "$imgs_ref" "$base_dir" && exit 0 || exit 1
                ;;
                *)
                    log "× 无效输入：$slot ！"
                ;;
            esac

    done

}

# 分区刷写函数
function flash_partition() {
    local category="$1"
    local slot="$2"
    local partition="$3"
    local img_path="$4"
    local tmp_slot_arg

    # 构建槽位参数
    tmp_slot_arg="--slot=${slot}"

    # 执行刷写
    log ">>> [${category}] [${slot}] [${partition}] Flashing..."
    if fastboot flash "${tmp_slot_arg}" "${partition}" "${img_path}"; then
        log "√ [${category}] [${partition}] Success"
        return 0
    else    
        log "× [${category}] [${partition}] Error"
        return 1
    fi
}

# 询问是否清除数据
function confirm_format_data_and_reboot() {

    while true; do

        read -p "- 是否清除数据并重启？(Y/n)" format_choice
        case $format_choice in
            Y | y | "")
                log "- 确认清除数据并重启！"
                fastboot -w && fastboot reboot && exit 0
            ;;
            N | n)
                log "- 取消操作并退出！"
                exit 0
            ;;
            *)
                log "× 无效输入：$format_choice ！"
            ;;
        esac
    done

}

# 通用批量执行器
function run_flash_batch() {

    local category="$1"
    local slot="$2"
    
    # 使用 nameref 实现数组引用 (Bash 4.3+)
    local -n parts_ref="$3"
    local -n imgs_ref="$4"
    local base_dir="$5"

    log "- 开始批量任务：[${category}]"
    
    if ! ((ERROR_CODE == 0 || ((ERROR_CODE % 2) == 1 && ERROR_COUNT <= 2))); then
        log "× 不满足刷写条件！（错误码：${ERROR_CODE} 错误次数：${ERROR_COUNT}）"
        exit 1
    fi

    # 遍历数组索引
    for i in "${!parts_ref[@]}"; do
        local partition="${parts_ref[$i]}"
        local img_name="${imgs_ref[$i]}"
        local img_path="${base_dir}/${img_name}"
        
        # 调用通用刷写函数
        flash_partition "${category}" "${slot}" "${partition}" "${img_path}"
            if ! [ $? -eq 0 ]; then

                    read -p "× 任务 [${category}] [${slot}] [${partition}] 执行失败！" dummy
                    exit 1

            fi
    done
    
    log "√ 任务 [${category}] 完成！"
    
}

# 日志函数
function log() {
    echo "[$(date "+%Y年%m月%d日 %H:%M:%S")] $1" | tee -a "${LOG_FILE}"
}

# fastboot 相关函数
function check_fastboot() {

    # 检查 fastboot 命令是否存在
    if command -v fastboot > /dev/null 2>&1; then # 这里 > /dev/null 2>&1 作用是重定向标准输出到黑洞 把2（标准错误）定向到 &1 标准输出
        log "√ 已安装 fastboot 工具！"

        # 检查是否有设备连接
        if fastboot devices | grep -q "fastboot"; then
            DEVICE_SERIAL=$(fastboot devices | awk '{print $1}')
            log "√ 检测到 fastboot 设备：${DEVICE_SERIAL}"
            return 0
        else
            log "× 错误：未检测到 fastboot 设备！"
            return 1
        fi

    else
        log "× 错误：未找到 fastboot 命令！"
        return 1
    fi
}

# 刷写环境主检查函数
function check() {
    log "- 开始环境与数据完整性检测："
    check_fastboot && ((FASTBOOT_STATUS+1)) || ((ERROR_CODE+=1))
    check_partition_img_mapping "Proprietary Firmware" "PROPRIETARY_FIRMWARE_PARTS" "PROPRIETARY_FIRMWARE_IMGS" "${PROPRIETARY_FIRMWARE_DIR}" || ((ERROR_CODE+=2))
    check_partition_img_mapping "AOSP Firmware" "AOSP_FIRMWARE_PARTS" "AOSP_FIRMWARE_IMGS" "${AOSP_FIRMWARE_DIR}" || ((ERROR_CODE+=4))

    if [ ${ERROR_CODE} -eq 0 ]; then
        log "√ 检测通过！"
    else
        ERROR_COUNT=$(count_addends ${ERROR_CODE})
        log "× 共有 ${ERROR_COUNT} 项检测未通过！"
    fi  
}

# 镜像提取函数
function extract_imgs() {
    local category="$1"
    local payload="$2"
    local output="$3"
    local -n imgs_ref="$4"

    log "- 开始 [${category}] 提取任务："

    for img in "${imgs_ref[@]}"; do
        log ">>> [${img}] Extracting..."
        ${PAYLOAD_DUMPER_RUST_BIN} --images "${img}" -o "${output}" "${payload}" >/dev/null 2>&1

        if [ "$?" -ne 0 ]; then
            log "× [${img}] 提取失败！"
            return 1
        fi
    done

    log "√ 提取任务 [${category}] 完成！"
}

# function fix_captive_and_ntp() {
#     if adb devices | grep -q "devices"; then
#         log "
#     adb shell settings\
#     put global captive_portal_https_url\
#     https://google.cn/generate_204
#     adb shell settings\
#     put global captive_portal_http_url\
#     http://google.cn/generate_204

# }