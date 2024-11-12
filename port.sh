#!/bin/bash

source bin/TRT/functions.sh
#删除nohup的日志
rm -rf nohup.out
rm -rf 
#声明全局变量
onedrive_pan="onedrive"
DEBUG=OFF

function send_msg() {
    message="$1"
    echo $message
    if [[ "$type" == "priv" ]]; then
        python3 bin/python/send_priv_msg.py priv $user_id "$message"
    elif [[ "$type" == "group" ]]; then
        python3 bin/python/send_priv_msg.py group $group_id "$message"
    fi
}

function upload_file()  {
    file=$1
    filename=$5
    devicecode=$2
    type=$3
    version=$4
    devicecode_self=$(echo $devicecode | tr [:upper:] [:lower:])
    devicename_self=$(curl -s https://gitee.com/hanfy-djc/auto-port/raw/master/devicelist | grep -w $device_code  | awk -F'(' '{print $1}' | sed s/\ /_/g)
    if [[ "$type" == "123pan" ]]; then
        yellow 当前使用方案为[123云盘]上传
        # 获取fileid
        fileid=$(bash bin/TRT/getFileID.sh $device_code)
        python3 bin/TRT/123pan.py "$1" $fileid
    elif [[ "$type" == "onedrive" ]]; then
        yellow 当前使用方案为[onedrive云盘]上传
        rclone copy $file onedrive:/HyperOS移植/$devicename_self/$version/$filename  --transfers=16 --progress
    elif [[ "$type" == "123openapi" ]]; then
        yellow 当前使用123openapi方案上传
    fi
}

function local_onedrive_upload() {
    file=$1
    filename=$5
    devicecode=$2
    type=$3
    version=$4
    devicecode_self=$(echo $devicecode | tr [:upper:] [:lower:])
    devicename_self=$(curl -s https://gitee.com/hanfy-djc/auto-port/raw/master/devicelist | grep -w $device_code  | awk -F'(' '{print $1}' | sed s/\ /_/g)
    mkdir -p "$onedrive_pan/HyperOS移植/$devicename_self/$filename"
    mv $file "$onedrive_pan/HyperOS移植/$devicename_self/$filename/$file"
}


rm -rf build tmp
mkdir -p build/baserom/images/
mkdir -p build/portrom/images/
pack_type=erofs
build_user="HF-Team"
build_host=$(hostname)
remove_data_encrypt=true

# 底包和移植包为外部参数传入
baserom="$1"
portrom="$2"

echo $baserom $portrom

work_dir=$(pwd)
tools_dir=${work_dir}/bin/$(uname)/$(uname -m)
export PATH=$(pwd)/bin/$(uname)/$(uname -m)/:$PATH

# Import TRT/functions
source bin/TRT/functions.sh

if [ -z "$1" ] ;then
    yellow "usage :  br pr"
    exit
else
    yellow 开始...
fi

yellow ==================================================================
yellow ""
yellow ""
yellow                移植文件=$(basename $portrom)
yellow                底层文件=$(basename $baserom)
yellow ""
yellow ""
yellow ==================================================================
yellow "===\> step2 开始解压包文件"
blue 1.开始解压压缩包
send_msg "正在解压ROM资料"
yellow "step2-解压" 
mkdir -p build/baserom build/portrom
7z x $portrom payload.bin -obuild/portrom 1>/dev/null 2>&1
7z x $baserom payload.bin -obuild/baserom 1>/dev/null 2>&1
blue 2.开始解压payload文件
payload-dumper-go -o build/baserom/images build/baserom/payload.bin 1>/dev/null 2>&1

for part in system system_dlkm system_ext product product_dlkm mi_ext ;do
    extract_partition build/baserom/images/${part}.img build/baserom/images    
done
send_msg "正在提取分解镜像"
yellow "分解" 
for image in vendor odm vendor_dlkm odm_dlkm;do
    if [ -f build/baserom/images/${image}.img ];then
        mv -f build/baserom/images/${image}.img build/portrom/images/${image}.img

        # Extracting vendor at first, we need to determine which super parts to pack from Baserom fstab. 
        extract_partition build/portrom/images/${image}.img build/portrom/images/

    fi
done

super_list=$(sed '/^#/d;/^\//d;/overlay/d;/^$/d' $(find -type f -name fstab.qcom) \
                | awk '{ print $1}' | sort | uniq)
blue super分区"$super_list"

for part in ${super_list};do
# Skip already extraced parts from BASEROM
    if [[ ! -d build/portrom/images/${part} ]]; then
        if [[ ${is_eu_rom} == true ]];then
            yellow "PORTROM super.img 提取 [${part}] 分区..." "Extracting [${part}] from PORTROM super.img"
            yellow "lpunpack.py PORTROM super.img ${part}_a"
            python3 bin/lpunpack.py -p ${part}_a build/portrom/super.img build/portrom/images 
            mv build/portrom/images/${part}_a.img build/portrom/images/${part}.img
        elif [[ ${portrom_type} == "fastboot" ]];then
            yellow "PORTROM super.img 提取 [${part}] 分区..." "Extracting [${part}] from PORTROM super.img"
            yellow "lpunpack.py PORTROM super.img ${part}_a"
            python3 bin/lpunpack.py -p ${part}_a build/portrom/super.img build/portrom/images 
            mv build/portrom/images/${part}_a.img build/portrom/images/${part}.img
        else
            yellow "payload.bin 提取 [${part}] 分区..." "Extracting [${part}] from PORTROM payload.bin"

            payload-dumper-go -p ${part} -o build/portrom/images/ build/portrom/payload.bin >/dev/null 2>&1 || error "提取移植包 [${part}] 分区时出错" "Extracting partition [${part}] error."
        fi
    extract_partition "${work_dir}/build/portrom/images/${part}.img" "${work_dir}/build/portrom/images/"
    else
        yellow "跳过从PORTORM提取分区[${part}]" "Skip extracting [${part}] from PORTROM"
    fi
done
rm -rf config




base_android_version=$(< build/portrom/images/vendor/build.prop grep "ro.vendor.build.version.release" |awk 'NR==1' |cut -d '=' -f 2)
port_android_version=$(< build/portrom/images/system/system/build.prop grep "ro.system.build.version.release" |awk 'NR==1' |cut -d '=' -f 2)
green "安卓版本: 底包为[Android ${base_android_version}], 移植包为 [Android ${port_android_version}]" "Android Version: BASEROM:[Android ${base_android_version}], PORTROM [Android ${port_android_version}]"
send_msg "安卓版本: 底包为[Android ${base_android_version}], 移植包为 [Android ${port_android_version}]" "Android Version: BASEROM:[Android ${base_android_version}], PORTROM [Android ${port_android_version}]"
# SDK版本
base_android_sdk=$(< build/portrom/images/vendor/build.prop grep "ro.vendor.build.version.sdk" |awk 'NR==1' |cut -d '=' -f 2)
port_android_sdk=$(< build/portrom/images/system/system/build.prop grep "ro.system.build.version.sdk" |awk 'NR==1' |cut -d '=' -f 2)
green "SDK 版本: 底包为 [SDK ${base_android_sdk}], 移植包为 [SDK ${port_android_sdk}]" "SDK Verson: BASEROM: [SDK ${base_android_sdk}], PORTROM: [SDK ${port_android_sdk}]"
send_msg "SDK 版本: 底包为 [SDK ${base_android_sdk}], 移植包为 [SDK ${port_android_sdk}]" "SDK Verson: BASEROM: [SDK ${base_android_sdk}], PORTROM: [SDK ${port_android_sdk}]"
# ROM版本
base_rom_version=$(< build/portrom/images/vendor/build.prop grep "ro.vendor.build.version.incremental" |awk 'NR==1' |cut -d '=' -f 2)

#HyperOS版本号获取
port_mios_version_incremental=$(< build/portrom/images/mi_ext/etc/build.prop grep "ro.mi.os.version.incremental" | awk 'NR==1' | cut -d '=' -f 2)

base_rom_code=$(< build/portrom/images/vendor/build.prop grep "ro.product.vendor.device" |awk 'NR==1' |cut -d '=' -f 2)
port_rom_code=$(< build/portrom/images/product/etc/build.prop grep "ro.product.product.name" |awk 'NR==1' |cut -d '=' -f 2)
base_rom_code=$(echo $(basename $baserom) | cut -f2 -d_ | tr [:upper:] [:lower:])
green "机型代号: 底包为 [${base_rom_code}], 移植包为 [${port_rom_code}]" "Device Code: BASEROM: [${base_rom_code}], PORTROM: [${port_rom_code}]"
send_msg "机型代号: 底包为 [${base_rom_code}], 移植包为 [${port_rom_code}]" "Device Code: BASEROM: [${base_rom_code}], PORTROM: [${port_rom_code}]"
# displayconfig id
blue 3.替换displayconfig
rm -rf build/portrom/images/product/etc/displayconfig/display_id*.xml
cp -rf build/baserom/images/product/etc/displayconfig/display_id*.xml build/portrom/images/product/etc/displayconfig/
send_msg "开始修改"

yellow "修改" 

if grep -q "ro.build.ab_update=true" build/portrom/images/vendor/build.prop;  then
    is_ab_device=true
else
    is_ab_device=false

fi
blue  4.替换device_features
# device_features
yellow "Copying device_features"   
rm -rf build/portrom/images/product/etc/device_features/*
cp -rf build/baserom/images/product/etc/device_features/* build/portrom/images/product/etc/device_features/

for prop_file in $(find build/portrom/images/vendor/ -name "*.prop"); do
    vndk_version=$(< "$prop_file" grep "ro.vndk.version" | awk "NR==1" | cut -d '=' -f 2)
    if [ -n "$vndk_version" ]; then
        yellow "ro.vndk.version为$vndk_version" "ro.vndk.version found in $prop_file: $vndk_version"
        break  
    fi
done
base_vndk=$(find build/baserom/images/system_ext/apex -type f -name "com.android.vndk.v${vndk_version}.apex")
port_vndk=$(find build/portrom/images/system_ext/apex -type f -name "com.android.vndk.v${vndk_version}.apex")

if [ ! -f "${port_vndk}" ]; then
    yellow "apex不存在，从原包复制" "target apex is missing, copying from baserom"
    cp -rf "${base_vndk}" "build/portrom/images/system_ext/apex/"
fi

for prop_file in $(find build/portrom/images/vendor/ -name "*.prop"); do
    vndk_version=$(< "$prop_file" grep "ro.vndk.version" | awk "NR==1" | cut -d '=' -f 2)
    if [ -n "$vndk_version" ]; then
        yellow "ro.vndk.version为$vndk_version" "ro.vndk.version found in $prop_file: $vndk_version"
        break  
    fi
done
base_vndk=$(find build/baserom/images/system_ext/apex -type f -name "com.android.vndk.v${vndk_version}.apex")
port_vndk=$(find build/portrom/images/system_ext/apex -type f -name "com.android.vndk.v${vndk_version}.apex")

if [ ! -f "${port_vndk}" ]; then
    yellow "apex不存在，从原包复制" "target apex is missing, copying from baserom"
    cp -rf "${base_vndk}" "build/portrom/images/system_ext/apex/"
fi
overlays=" AospGoogleWifiResOverlay.apk AospWifResOverlay.apk DevicesAndroidOverlay.apk DevicesOverlay.apk MiuiBiometricResOverlay.apk MiuiBtRRODeviceConfigOverlay.apk MiuiCarrierConfigOverlay.apk  SettingsRroDeviceConfigOverlay.apk SettingsRroDeviceTypeOverlay.apk WifResCommon_Sys.apk WifResCommonMainline_Sys.apk"
for overlay in ${overlays}; do
    baseoverlay=$(find build/baserom/images/product -type f -name "$overlay")
    portoverlay=$(find build/portrom/images/product -type f -name "$overlay")
    if [ -f "${baseoverlay}" ] && [ -f "${portoverlay}" ];then
        yellow "正在替换 [$overlay] "
        cp -rf ${baseoverlay}  ${portoverlay}
    fi
done


blue 6.替换人脸组件包
# 人脸
baseMiuiBiometric=$(find build/baserom/images/product/app -type d -name "*Biometric*")
portMiuiBiometric=$(find build/portrom/images/product/app -type d -name "*Biometric*")
if [ -d "${baseMiuiBiometric}" ] && [ -d "${portMiuiBiometric}" ];then
    yellow "查找MiuiBiometric" "Searching and Replacing MiuiBiometric.."
    rm -rf ./${portMiuiBiometric}/*
    cp -rf ./${baseMiuiBiometric}/* ${portMiuiBiometric}/
else
    if [ -d "${baseMiuiBiometric}" ] && [ ! -d "${portMiuiBiometric}" ];then
        yellow "未找到MiuiBiometric，替换为原包" "MiuiBiometric is missing, copying from base..."
        cp -rf ${baseMiuiBiometric} build/portrom/images/product/app/
    fi
fi

targetVintf=$(find build/portrom/images/system_ext/etc/vintf -type f -name "manifest.xml")
if [ -f "$targetVintf" ]; then
    # Check if the file contains $vndk_version
    if grep -q "<version>$vndk_version</version>" "$targetVintf"; then
        yellow "${vndk_version}已存在，跳过修改" "The file already contains the version $vndk_version. Skipping modification."
    else
        # If it doesn't contain $vndk_version, then add it
        ndk_version="<vendor-ndk>\n     <version>$vndk_version</version>\n </vendor-ndk>"
        sed -i "/<\/vendor-ndk>/a$ndk_version" "$targetVintf"
        yellow "添加成功" "Version $vndk_version added to $targetVintf"
    fi
else
    yellow "File $targetVintf not found."
fi

blue 7.移除service.jar签名验证

if [[ ${port_rom_code} != "sheng" ]] || [[ ${port_rom_code} != "shennong" ]];then
    
    if [[ ! -d tmp ]];then
        mkdir -p tmp/
    fi
    yellow "开始移除 Android 成功" "Disalbe Android 14 Apk Signature Verfier"
    mkdir -p tmp/services/
    cp -rf build/portrom/images/system/system/framework/services.jar tmp/services.jar
    java -jar bin/apktool/APKEditor.jar d -f -i tmp/services.jar -o tmp/services  > /dev/null 2>&1
    target_method='getMinimumSignatureSchemeVersionForTargetSdk' 
    old_smali_dir=""
    declare -a smali_dirs

    while read -r smali_file; do
        smali_dir=$(yellow "$smali_file" | cut -d "/" -f 3)

        if [[ $smali_dir != $old_smali_dir ]]; then
            smali_dirs+=("$smali_dir")
        fi

        method_line=$(grep -n "$target_method" "$smali_file" | cut -d ':' -f 1)
        register_number=$(tail -n +"$method_line" "$smali_file" | grep -m 1 "move-result" | tr -dc '0-9')
        move_result_end_line=$(awk -v ML=$method_line 'NR>=ML && /move-result /{print NR; exit}' "$smali_file")
        orginal_line_number=$method_line
        replace_with_command="const/4 v${register_number}, 0x0"
        { sed -i "${orginal_line_number},${move_result_end_line}d" "$smali_file" && sed -i "${orginal_line_number}i\\${replace_with_command}" "$smali_file"; } &&    yellow "${smali_file}  修改成功" "${smali_file} patched"
        old_smali_dir=$smali_dir
    done < <(find tmp/services/smali/*/com/android/server/pm/ tmp/services/smali/*/com/android/server/pm/pkg/parsing/ -maxdepth 1 -type f -name "*.smali" -exec grep -H "$target_method" {} \; | cut -d ':' -f 1)
    java -jar bin/apktool/APKEditor.jar b -f -i tmp/services -o tmp/services_patched.jar > /dev/null 2>&1
    cp -rf tmp/services_patched.jar build/portrom/images/system/system/framework/services.jar
    
fi

if [[ ${is_eu_rom} == "true" ]];then
    patch_smali "miui-services.jar" "SystemServerImpl.smali" ".method public constructor <init>()V/,/.end method" ".method public constructor <init>()V\n\t.registers 1\n\tinvoke-direct {p0}, Lcom\/android\/server\/SystemServerStub;-><init>()V\n\n\treturn-void\n.end method" "regex"

elif [[ ${port_rom_code} != "sheng" ]] || [[ ${port_rom_code} != "shennong" ]];then
    
    if [[ ! -d tmp ]];then
        mkdir -p tmp/
    fi
    yellow "开始移除 Android 签名校验" "Disalbe Android 14 Apk Signature Verfier"
    mkdir -p tmp/services/
    cp -rf build/portrom/images/system/system/framework/services.jar tmp/services.jar
    
    java -jar bin/apktool/APKEditor.jar d -f -i tmp/services.jar -o tmp/services  > /dev/null 2>&1
    target_method='getMinimumSignatureSchemeVersionForTargetSdk' 
    old_smali_dir=""
    declare -a smali_dirs

    while read -r smali_file; do
        smali_dir=$(yellow "$smali_file" | cut -d "/" -f 3)

        if [[ $smali_dir != $old_smali_dir ]]; then
            smali_dirs+=("$smali_dir")
        fi

        method_line=$(grep -n "$target_method" "$smali_file" | cut -d ':' -f 1)
        register_number=$(tail -n +"$method_line" "$smali_file" | grep -m 1 "move-result" | tr -dc '0-9')
        move_result_end_line=$(awk -v ML=$method_line 'NR>=ML && /move-result /{print NR; exit}' "$smali_file")
        orginal_line_number=$method_line
        replace_with_command="const/4 v${register_number}, 0x0"
        { sed -i "${orginal_line_number},${move_result_end_line}d" "$smali_file" && sed -i "${orginal_line_number}i\\${replace_with_command}" "$smali_file"; } &&    yellow "${smali_file}  修改成功" "${smali_file} patched"
        old_smali_dir=$smali_dir
    done < <(find tmp/services/smali/*/com/android/server/pm/ tmp/services/smali/*/com/android/server/pm/pkg/parsing/ -maxdepth 1 -type f -name "*.smali" -exec grep -H "$target_method" {} \; | cut -d ':' -f 1)
    java -jar bin/apktool/APKEditor.jar b -f -i tmp/services -o tmp/services_patched.jar > /dev/null 2>&1
    cp -rf tmp/services_patched.jar build/portrom/images/system/system/framework/services.jar
    
fi

blue 8.补全刷新率[60-90-120]

maxFps=$(xmlstarlet sel -t -v "//integer-array[@name='fpsList']/item" build/portrom/images/product/etc/device_features/${base_rom_code}.xml | sort -nr | head -n 1)

if [ -z "$maxFps" ]; then
    maxFps=90
fi

unlock_device_feature "whether support fps change " "bool" "support_smart_fps"
unlock_device_feature "smart fps value" "integer" "smart_fps_value" "${maxFps}"
patch_smali "PowerKeeper.apk" "DisplayFrameSetting.smali" "unicorn" "${base_rom_code}"
if [[ ${is_eu_rom} == true ]];then
    patch_smali "MiSettings.apk" "NewRefreshRateFragment.smali" "const-string v1, \"btn_preferce_category\"" "const-string v1, \"btn_preferce_category\"\n\n\tconst\/16 p1, 0x1"

else
    patch_smali "MISettings.apk" "NewRefreshRateFragment.smali" "const-string v1, \"btn_preferce_category\"" "const-string v1, \"btn_preferce_category\"\n\n\tconst\/16 p1, 0x1"
fi

blue 7.添加护眼模式
# Unlock eyecare mode 
unlock_device_feature "default rhythmic eyecare mode" "integer" "default_eyecare_mode" "2"
unlock_device_feature "default texture for paper eyecare" "integer" "paper_eyecare_default_texture" "0"

blue 8.添加主题防恢复
# 主题防恢复
if [ -f build/portrom/images/system/system/etc/init/hw/init.rc ];then
	sed -i '/on boot/a\'$'\n''    chmod 0731 \/data\/system\/theme' build/portrom/images/system/system/etc/init/hw/init.rc
fi

#  通信共享
source ./bin/module/CelluarShared.sh 1>/dev/null 2>&1
#  自定义ui
source ./bin/module/CustomCenter.sh 1>/dev/null 2>&1
#  build修改
source ./bin/module/ModifyBuild.sh 1>/dev/null 2>&1
#  添加HyperMind
source ./bin/module/HyperMind.sh 1>/dev/null 2>&1
#  添加小爱翻译解限
source ./bin/module/AiAsstVision.sh 1>/dev/null 2>&1
#
#blue 9.添加状态栏歌词[HyperOS1.0.x可用]
#Settings=$(find build/portrom -type f -name Settings.apk)
#Lyric -settings $Settings 1>/dev/null 2>&1
#services=$(find build/portrom -type f -name services.jar)
#Lyric -services $services 1>/dev/null 2>&1
#MiuiSystemUI=$(find build/portrom -type f -name MiuiSystemUI.apk)
#Lyric -ui $MiuiSystemUI 1>/dev/null 2>&1
#
#

# Unlock MEMC; unlocking the screen enhance engine is a prerequisite.
# This feature add additional frames to videos to make content appear smooth and transitions lively.
if  grep -q "ro.vendor.media.video.frc.support" build/portrom/images/vendor/build.prop ;then
    sed -i "s/ro.vendor.media.video.frc.support=.*/ro.vendor.media.video.frc.support=true/" build/portrom/images/vendor/build.prop
else
    yellow "ro.vendor.media.video.frc.support=true" >> build/portrom/images/vendor/build.prop
fi
blue 10.添加游戏动画3倍加速
# Game splashscreen speed up
yellow "debug.game.video.speed=true" >> build/portrom/images/product/etc/build.prop
yellow "debug.game.video.support=true" >> build/portrom/images/product/etc/build.prop

blue 11.去除data加密
if [ ${remove_data_encrypt} = "true" ];then
    yellow "去除data加密"
    for fstab in $(find build/portrom/images -type f -name "fstab.*");do
		yellow "Target: $fstab"
		sed -i "s/,fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0//g" $fstab
		sed -i "s/,fileencryption=aes-256-xts:aes-256-cts:v2+emmc_optimized+wrappedkey_v0//g" $fstab
		sed -i "s/,fileencryption=aes-256-xts:aes-256-cts:v2//g" $fstab
		sed -i "s/,metadata_encryption=aes-256-xts:wrappedkey_v0//g" $fstab
		sed -i "s/,fileencryption=aes-256-xts:wrappedkey_v0//g" $fstab
		sed -i "s/,metadata_encryption=aes-256-xts//g" $fstab
		sed -i "s/,fileencryption=aes-256-xts//g" $fstab
        sed -i "s/,fileencryption=ice//g" $fstab
		sed -i "s/fileencryption/encryptable/g" $fstab
	done
fi

blue 12.添加常规修改

# props from k60
echo "persist.vendor.mi_sf.optimize_for_refresh_rate.enable=1" >> build/portrom/images/vendor/build.prop
echo "ro.vendor.mi_sf.ultimate.perf.support=true"  >> build/portrom/images/vendor/build.prop

#echo "debug.sf.set_idle_timer_ms=1100" >> build/portrom/images/vendor/build.prop

#echo "ro.surface_flinger.set_touch_timer_ms=200" >> build/portrom/images/vendor/build.prop

# https://source.android.com/docs/core/graphics/multiple-refresh-rate
echo "ro.surface_flinger.use_content_detection_for_refresh_rate=false" >> build/portrom/images/vendor/build.prop
echo "ro.surface_flinger.set_touch_timer_ms=0" >> build/portrom/images/vendor/build.prop
echo "ro.surface_flinger.set_idle_timer_ms=0" >> build/portrom/images/vendor/build.prop
patch_smali "MiuiSystemUI.apk" "NotificationIconAreaController.smali" "iput p10, p0, Lcom\/android\/systemui\/statusbar\/phone\/NotificationIconContainer;->mMaxStaticIcons:I" "const\/4 p10, 0x6\n\n\tiput p10, p0, Lcom\/android\/systemui\/statusbar\/phone\/NotificationIconContainer;->mMaxStaticIcons:I"

yellow "删除多余的App" "Debloating..." 
# List of apps to be removed
debloat_apps=("MSA" "mab" "Updater" "MiuiUpdater" "MiService" "MIService" "SoterService" "Hybrid" "AnalyticsCore")
for debloat_app in "${debloat_apps[@]}"; do
    # Find the app directory
    app_dir=$(find build/portrom/images/product -type d -name "*$debloat_app*")
    
    # Check if the directory exists before removing
    if [[ -d "$app_dir" ]]; then
        yellow "删除目录: $app_dir" "Removing directory: $app_dir"
        rm -rf "$app_dir"
    fi
done
rm -rf build/portrom/images/product/etc/auto-install*
rm -rf build/portrom/images/product/data-app/*GalleryLockscreen* >/dev/null 2>&1
mkdir -p tmp/app
kept_data_apps=("DownloadProviderUi" "VirtualSim" "ThirdAppAssistant" "GameCenter" "Video" "Weather" "DeskClock" "Gallery" "SoundRecorder" "ScreenRecorder" "Calculator" "CleanMaster" "Calendar" "Compass" "Notes" "MediaEditor" "Scanner" "SpeechEngine" "wps-lite")
for app in "${kept_data_apps[@]}"; do
    mv build/portrom/images/product/data-app/*"${app}"* tmp/app/ >/dev/null 2>&1
done
rm -rf build/portrom/images/product/data-app/*
cp -rf tmp/app/* build/portrom/images/product/data-app
rm -rf tmp/app
rm -rf build/portrom/images/system/verity_key
rm -rf build/portrom/images/vendor/verity_key
rm -rf build/portrom/images/product/verity_key
rm -rf build/portrom/images/system/recovery-from-boot.p
rm -rf build/portrom/images/vendor/recovery-from-boot.p
rm -rf build/portrom/images/product/recovery-from-boot.p
rm -rf build/portrom/images/product/media/theme/miui_mod_icons/com.google.android.apps.nbu*
rm -rf build/portrom/images/product/media/theme/miui_mod_icons/dynamic/com.google.android.apps.nbu*


buildDate=$(date -u +"%a %b %d %H:%M:%S UTC %Y")
buildUtc=$(date +%s)
for i in $(find build/portrom/images -type f -name "build.prop");do
    blue "正在处理 ${i}" "modifying ${i}"
    sed -i "s/ro.build.date=.*/ro.build.date=${buildDate}/g" ${i}
    sed -i "s/ro.build.date.utc=.*/ro.build.date.utc=${buildUtc}/g" ${i}
    sed -i "s/ro.odm.build.date=.*/ro.odm.build.date=${buildDate}/g" ${i}
    sed -i "s/ro.odm.build.date.utc=.*/ro.odm.build.date.utc=${buildUtc}/g" ${i}
    sed -i "s/ro.vendor.build.date=.*/ro.vendor.build.date=${buildDate}/g" ${i}
    sed -i "s/ro.vendor.build.date.utc=.*/ro.vendor.build.date.utc=${buildUtc}/g" ${i}
    sed -i "s/ro.system.build.date=.*/ro.system.build.date=${buildDate}/g" ${i}
    sed -i "s/ro.system.build.date.utc=.*/ro.system.build.date.utc=${buildUtc}/g" ${i}
    sed -i "s/ro.product.build.date=.*/ro.product.build.date=${buildDate}/g" ${i}
    sed -i "s/ro.product.build.date.utc=.*/ro.product.build.date.utc=${buildUtc}/g" ${i}
    sed -i "s/ro.system_ext.build.date=.*/ro.system_ext.build.date=${buildDate}/g" ${i}
    sed -i "s/ro.system_ext.build.date.utc=.*/ro.system_ext.build.date.utc=${buildUtc}/g" ${i}
   
    sed -i "s/ro.product.device=.*/ro.product.device=${base_rom_code}/g" ${i}
    sed -i "s/ro.product.product.name=.*/ro.product.product.name=${base_rom_code}/g" ${i}
    sed -i "s/ro.product.odm.device=.*/ro.product.odm.device=${base_rom_code}/g" ${i}
    sed -i "s/ro.product.vendor.device=.*/ro.product.vendor.device=${base_rom_code}/g" ${i}
    sed -i "s/ro.product.system.device=.*/ro.product.system.device=${base_rom_code}/g" ${i}
    sed -i "s/ro.product.board=.*/ro.product.board=${base_rom_code}/g" ${i}
    sed -i "s/ro.product.system_ext.device=.*/ro.product.system_ext.device=${base_rom_code}/g" ${i}
    sed -i "s/persist.sys.timezone=.*/persist.sys.timezone=Asia\/Shanghai/g" ${i}
    #全局替换device_code
    if [[ $port_mios_version_incremental != *DEV* ]];then
        sed -i "s/$port_device_code/$base_device_code/g" ${i}
    fi
    # 添加build user信息
    sed -i "s/ro.build.user=.*/ro.build.user=${build_user}/g" ${i}
    if [[ ${is_eu_rom} == "true" ]];then
        sed -i "s/ro.product.mod_device=.*/ro.product.mod_device=${base_rom_code}_xiaomieu_global/g" ${i}
        sed -i "s/ro.build.host=.*/ro.build.host=xiaomi.eu/g" ${i}

    else
        sed -i "s/ro.product.mod_device=.*/ro.product.mod_device=${base_rom_code}/g" ${i}
        sed -i "s/ro.build.host=.*/ro.build.host=${build_host}/g" ${i}
    fi                              
    sed -i "s/ro.build.characteristics=tablet/ro.build.characteristics=nosdcard/g" ${i}
    sed -i "s/ro.config.miui_multi_window_switch_enable=true/ro.config.miui_multi_window_switch_enable=false/g" ${i}
    sed -i "s/ro.config.miui_desktop_mode_enabled=true/ro.config.miui_desktop_mode_enabled=false/g" ${i}
    sed -i "/ro.miui.density.primaryscale=.*/d" ${i}
    sed -i "/persist.wm.extensions.enabled=true/d" ${i}
done

for prop in $(find build/baserom/images/product build/baserom/images/system -type f -name "build.prop");do
    base_rom_density=$(< "$prop" grep "ro.sf.lcd_density" |awk 'NR==1' |cut -d '=' -f 2)
    if [ "${base_rom_density}" != "" ];then
        green "底包屏幕密度值 ${base_rom_density}" "Screen density: ${base_rom_density}"
        break 
    fi
done

[ -z ${base_rom_density} ] && base_rom_density=440

found=0
for prop in $(find build/portrom/images/product build/portrom/images/system -type f -name "build.prop");do
    if grep -q "ro.sf.lcd_density" ${prop};then
        sed -i "s/ro.sf.lcd_density=.*/ro.sf.lcd_density=${base_rom_density}/g" ${prop}
        found=1
    fi
    sed -i "s/persist.miui.density_v2=.*/persist.miui.density_v2=${base_rom_density}/g" ${prop}
done

if [ $found -eq 0  ]; then
        blue "未找到ro.fs.lcd_density，build.prop新建一个值$base_rom_density" "ro.fs.lcd_density not found, create a new value ${base_rom_density} "
        echo "ro.sf.lcd_density=${base_rom_density}" >> build/portrom/images/product/etc/build.prop
fi

echo "ro.miui.cust_erofs=0" >> build/portrom/images/product/etc/build.prop

# Millet fix
blue "修复Millet" "Fix Millet"

millet_netlink_version=$(grep "ro.millet.netlink" build/baserom/images/product/etc/build.prop | cut -d "=" -f 2)

if [[ -n "$millet_netlink_version" ]]; then
  update_netlink "$millet_netlink_version" "build/portrom/images/product/etc/build.prop"
else
  blue "原包未发现ro.millet.netlink值，请手动赋值修改(默认为29)" "ro.millet.netlink property value not found, change it manually(29 by default)."
  millet_netlink_version=29
  update_netlink "$millet_netlink_version" "build/portrom/images/product/etc/build.prop"
fi
# add advanced texture
if ! is_property_exists persist.sys.background_blur_supported build/portrom/images/product/etc/build.prop; then
    echo "persist.sys.background_blur_supported=true" >> build/portrom/images/product/etc/build.prop
    echo "persist.sys.background_blur_version=2" >> build/portrom/images/product/etc/build.prop
else
    sed -i "s/persist.sys.background_blur_supported=.*/persist.sys.background_blur_supported=true/" build/portrom/images/product/etc/build.prop
fi

#Add perfect icons
#blue "添加完美图标"  
#git clone --depth=1 https://gitee.com/siitake/Perfect-Icons-Completion-Project.git icons &>/dev/null
#for pkg in "$work_dir"/build/portrom/images/product/media/theme/miui_mod_icons/dynamic/*; do
#  if [[ -d "$work_dir"/icons/icons/$pkg ]]; then
#    rm -rf "$work_dir"/icons/icons/$pkg
#  fi
#done
#rm -rf "$work_dir"/icons/icons/com.xiaomi.scanner
#mv "$work_dir"/build/portrom/images/product/media/theme/default/icons "$work_dir"/build/portrom/images/product/media/theme/default/icons.zip
#rm -rf "$work_dir"/build/portrom/images/product/media/theme/default/dynamicicons
#mkdir -p "$work_dir"/icons/res
#mv "$work_dir"/icons/icons "$work_dir"/icons/res/drawable-xxhdpi
#cd "$work_dir"/icons
#zip -qr "$work_dir"/build/portrom/images/product/media/theme/default/icons.zip res
#cd "$work_dir"/icons/themes/Hyper/
#zip -qr "$work_dir"/build/portrom/images/product/media/theme/default/dynamicicons.zip layer_animating_icons
#cd "$work_dir"/icons/themes/common/
#zip -qr "$work_dir"/build/portrom/images/product/media/theme/default/dynamicicons.zip layer_animating_icons
#mv "$work_dir"/build/portrom/images/product/media/theme/default/icons.zip "$work_dir"/build/portrom/images/product/media/theme/default/icons
#mv "$work_dir"/build/portrom/images/product/media/theme/default/dynamicicons.zip "$work_dir"/build/portrom/images/product/media/theme/default/dynamicicons
#rm -rf "$work_dir"/icons
#cd "$work_dir"

# Optimize prop from K40s 
if ! is_property_exists ro.miui.surfaceflinger_affinity build/portrom/images/product/etc/build.prop; then
    echo "ro.miui.surfaceflinger_affinity=true" >> build/portrom/images/product/etc/build.prop
fi

disable_avb_verify build/portrom/images/

send_msg "开始打包"
yellow "打包" 

blue 开始打包
for pname in ${super_list};do
    if [ "$pname" = "vendor" ] || [ "$pname" = "odm" ] || [ "$pname" = "vendor_dlkm" ]; then
        pack_type=erofs
    else
        pack_type=erofs
    fi
    if [ -d "build/portrom/images/$pname" ];then
        thisSize=$(du -sb build/portrom/images/${pname} |tr -cd 0-9)
        case $pname in
            mi_ext) addSize=4194304 ;;
            odm) addSize=34217728 ;;
            system|vendor|system_ext) addSize=84217728 ;;
            product) addSize=104217728 ;;
            *) addSize=8554432 ;;
        esac
        if [ "$pack_type" = "EXT" ];then
            for fstab in $(find build/portrom/images/${pname}/ -type f -name "fstab.*");do
                #sed -i '/overlay/d' $fstab
                sed -i '/system * erofs/d' $fstab
                sed -i '/system_ext * erofs/d' $fstab
                sed -i '/vendor * erofs/d' $fstab
                sed -i '/product * erofs/d' $fstab
            done
            thisSize=$(yellow "$thisSize + $addSize" |bc)
            yellow 以[$pack_type]文件系统打包[${pname}.img]大小[$thisSize] "Packing [${pname}.img]:[$pack_type] with size [$thisSize]"
            python3 bin/TRT/fspatch.py build/portrom/images/${pname} build/portrom/images/config/${pname}_fs_config  >/dev/null 2>&1
            python3 bin/TRT/contextpatch.py build/portrom/images/${pname} build/portrom/images/config/${pname}_file_contexts >/dev/null 2>&1  >/dev/null 2>&1
            make_ext4fs -J -T $(date +%s) -S build/portrom/images/config/${pname}_file_contexts -l $thisSize -C build/portrom/images/config/${pname}_fs_config -L ${pname} -a ${pname} build/portrom/images/${pname}.img build/portrom/images/${pname}   >/dev/null 2>&1

            if [ -f "build/portrom/images/${pname}.img" ];then
                blue "成功以大小 [$thisSize] 打包 [${pname}.img] [${pack_type}] 文件系统" "Packing [${pname}.img] with [${pack_type}], size: [$thisSize] success"
                #rm -rf build/baserom/images/${pname}
            else
                error "以 [${pack_type}] 文件系统打包 [${pname}] 分区失败" "Packing [${pname}] with[${pack_type}] filesystem failed!"
            fi
        else
            
                yellow 以[$pack_type]文件系统打包[${pname}.img] "Packing [${pname}.img] with [$pack_type] filesystem"
                python3 bin/TRT/fspatch.py build/portrom/images/${pname} build/portrom/images/config/${pname}_fs_config  >/dev/null 2>&1
                python3 bin/TRT/contextpatch.py build/portrom/images/${pname} build/portrom/images/config/${pname}_file_contexts  >/dev/null 2>&1
                #sudo perl -pi -e 's/\\@/@/g' build/portrom/images/config/${pname}_file_contexts  >/dev/null 2>&1
                mkfs.erofs -zlz4hc,9 --mount-point /${pname} --fs-config-file build/portrom/images/config/${pname}_fs_config --file-contexts build/portrom/images/config/${pname}_file_contexts build/portrom/images/${pname}.img build/portrom/images/${pname}  >/dev/null 2>&1
                if [ -f "build/portrom/images/${pname}.img" ];then
                    blue "成功以 [erofs] 文件系统打包 [${pname}.img]" "Packing [${pname}.img] successfully with [erofs] format"
                    #rm -rf build/portrom/images/${pname}
                else
                    error "以 [${pack_type}] 文件系统打包 [${pname}] 分区失败" "Faield to pack [${pname}]"
                    exit 1
                fi
        fi
        unset fsType
        unset thisSize
    fi
done

device_code=${base_rom_code}
deviceName=$(bash bin/TRT/getDeviceName.sh $port_rom_code)
device_code_A=$(echo $device_code | tr  '[:lower:]' '[:upper:]')
device_code_B=$(echo ${device_code^})
superSize=$(bash bin/TRT/getSuperSize.sh $device_code_A)
yellow super打包大小[$superSize]
blue 开始打包super镜像
if [[ "$is_ab_device" == false ]];then
    yellow "打包A-only super.img" "Packing super.img for A-only device"
    lpargs="-F --output build/portrom/images/super.img --metadata-size 65536 --super-name super --metadata-slots 2 --block-size 4096 --device super:$superSize --group=qti_dynamic_partitions:$superSize"
    for pname in odm mi_ext system system_ext product vendor;do
        if [ -f "build/portrom/images/${pname}.img" ];then
            if [[ "$OSTYPE" == "darwin"* ]];then
               subsize=$(find build/portrom/images/${pname}.img | xargs stat -f%z | awk ' {s+=$1} END { print s }')
            else
                subsize=$(du -sb build/portrom/images/${pname}.img |tr -cd 0-9)
            fi
            green "Super 子分区 [$pname] 大小 [$subsize]" "Super sub-partition [$pname] size: [$subsize]"
            args="--partition ${pname}:none:${subsize}:qti_dynamic_partitions --image ${pname}=build/portrom/images/${pname}.img"
            lpargs="$lpargs $args"
            unset subsize
            unset args
        fi
    done
else
    yellow "打包V-A/B机型 super.img" "Packing super.img for V-AB device"
    lpargs="-F --virtual-ab --output build/portrom/images/super.img --metadata-size 65536 --super-name super --metadata-slots 3 --device super:$superSize --group=qti_dynamic_partitions_a:$superSize --group=qti_dynamic_partitions_b:$superSize"

    for pname in ${super_list};do
        if [ -f "build/portrom/images/${pname}.img" ];then
            subsize=$(du -sb build/portrom/images/${pname}.img |tr -cd 0-9)
            green "Super 子分区 [$pname] 大小 [$subsize]" "Super sub-partition [$pname] size: [$subsize]"
            args="--partition ${pname}_a:none:${subsize}:qti_dynamic_partitions_a --image ${pname}_a=build/portrom/images/${pname}.img --partition ${pname}_b:none:0:qti_dynamic_partitions_b"
            lpargs="$lpargs $args"
            unset subsize
            unset args
        fi
    done
fi
lpmake $lpargs > /dev/null 2>&1

if [ -f "build/portrom/images/super.img" ];then
    blue "成功打包 super.img" "Pakcing super.img done."
else
    blue "无法打包 super.img"  "Unable to pack super.img."
    exit 1
fi

blue "正在压缩 super.img" "Comprising super.img"
zstd --rm build/portrom/images/super.img -o build/portrom/images/super.hf


rm -rf tmp/*
mv build/portrom/images/super.hf tmp
mkdir tmp/images
mv build/baserom/images/*.img tmp/images
cp -rf bin/images/cust.img tmp/images


cp -rf bin/flashscript/* tmp
echo $base_rom_code > tmp/META-INF/DeviceName
echo HanfyROM > tmp/META-INF/FlashInfoAuthor
unix2dos  tmp/META-INF/FlashInfoAuthor 
echo 2in1AutoFlashTOOL[$base_rom_code]线刷工具  > tmp/META-INF/FlashInfoTitle
unix2dos tmp/META-INF/FlashInfoTitle 
echo 请进入FASTBOOT模式开始刷机 请勿泄露ROM 否则停更  > tmp/META-INF/FlashInfoTip
unix2dos tmp/META-INF/FlashInfoTip

#cp -rf bin/MiFlash/* tmp
#sed -i s/HFdevice/$device_code/g tmp/flash_all.bat
#unix2dos tmp/flash_all.bat
#sed -i s/HFdevice/$device_code/g tmp/flash_all_except_storage.bat
#unix2dos tmp/flash_all_except_storage.bat
#sed -i s/HFdevice/$device_code/g tmp/META-INF/com/google/android/update-binary
#sed -i s/HFdevice/$device_code/g tmp/META-INF/com/google/android/update-binary
cd tmp
blue 压缩ROM文件
7z a  tmp.zip -mx=0 *  > /dev/null 2>&1
cd ..
md5=$(md5sum tmp/tmp.zip | cut -c 1-8 )
current_time=$(date +%Y%m%d)

# 判断变量 VAR 是否已设置（存在且非空）
if [ -n "${deviceName}" ]; then
    pack3=$deviceName
else
    pack3=$port_rom_code
fi
low_port_rom_code=$(echo $port_rom_code | tr [:upper:] [:lower:])
devicename_self_changen=$(curl -s https://gitee.com/hanfy-djc/auto-port/raw/master/devicelist | grep -w $base_rom_code  | awk -F'(' '{print $1}' | sed s/\ //g)

romname=${devicename_self_changen}_${port_mios_version_incremental}_From_${pack3}_${md5}_${current_time}.zip
mv tmp/tmp.zip tmp/$romname

###############
# 移植包型号 = $port_rom_code
# 移植包版本 = $port_mios_version_incremental
# 移植包安卓版本 = $port_android_version

send_msg "开始上传"
yellow "上传" 
filename=$(basename tmp/$romname)
echo $devicename_self_changen
python3 bin/XUI/XiaomiUpdateInfo.py $low_port_rom_code $port_mios_version_incremental  $port_android_version > tmp/$low_port_rom_code.xml
yellow "python3 bin/XUI/XiaomiUpdateInfo.py $low_port_rom_code $port_mios_version_incremental  $port_android_version "
change="$(sed -n '/changelog:/,$p' tmp/$low_port_rom_code.xml)"
changen=readme.md
touch tmp/$changen
cat bin/rom_show > tmp/$changen
sed -n '/changelog:/,$p' tmp/$low_port_rom_code.xml >> tmp/$changen
current_time=$(date +"%Y-%m-%d_%H:%M:%S")
sed -i s/datehfteam/$current_time/g tmp/$changen
sed -i s/devicehfteam/$devicename_self_changen/g tmp/$changen
echo $(uname -a) >> tmp/$changen
onedrive-uploader -c bin/config.json upload "tmp/$romname" HF-TEAM/HyperOS/$devicename_self_changen/$port_mios_version_incremental 
onedrive-uploader -c bin/config.json upload "tmp/$changen" HF-TEAM/HyperOS/$devicename_self_changen/$port_mios_version_incremental 


