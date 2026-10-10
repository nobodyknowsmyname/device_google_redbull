#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

device_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
android_root="$(cd -- "${device_dir}/../../.." && pwd)"
kernel_source="${android_root}/kernel/google/redbull"
kernel_out="${KERNEL_OUT:-${android_root}/out/redbull-kernel-build}"
prebuilt_dir="${android_root}/device/google/redbull-kernel"
clang_dir="${KERNEL_CLANG_DIR:-${android_root}/prebuilts/clang/kernel/linux-x86/clang-r416183b}"
jobs="${KERNEL_JOBS:-32}"

if [[ ! -x "${clang_dir}/bin/clang" ]]; then
    echo "Missing kernel toolchain: ${clang_dir}/bin/clang" >&2
    exit 1
fi

mkdir -p "${kernel_out}/host-bin"
ln -sfn "${android_root}/system/libufdt/utils/src/mkdtboimg.py" "${kernel_out}/host-bin/mkdtboimg"
export PATH="${clang_dir}/bin:${kernel_out}/host-bin:${PATH}"
export KBUILD_BUILD_USER=statix KBUILD_BUILD_HOST=redbull
export KBUILD_BUILD_TIMESTAMP="$(git -C "${kernel_source}" show -s --format=%cD HEAD)"
export KBUILD_BUILD_VERSION=1

kernel_make=(make -C "${kernel_source}" O="${kernel_out}" ARCH=arm64
    LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu-
    CROSS_COMPILE_COMPAT=arm-linux-gnueabi- DTC_EXT="$(command -v dtc)")

"${kernel_make[@]}" redbull_defconfig
"${kernel_make[@]}" -j"${jobs}" Image.lz4 dtbs dtbo.img modules
"${kernel_make[@]}" -j"${jobs}" headers_install INSTALL_HDR_PATH="${kernel_out}/headers"
"${kernel_make[@]}" -j"${jobs}" modules_install INSTALL_MOD_PATH="${kernel_out}/modules" INSTALL_MOD_STRIP=1

staging="$(mktemp -d "${prebuilt_dir}.tmp.XXXXXX")"
trap 'rm -rf -- "${staging}"' EXIT
cp "${kernel_out}/arch/arm64/boot/Image.lz4" "${staging}/"
cp "${kernel_out}/arch/arm64/boot/dtbo.img" "${staging}/"
cp "${kernel_out}"/arch/arm64/boot/dts/google/qcom-base/lito*.dtb "${staging}/"
cp "${kernel_out}/.config" "${staging}/kernel.config"
mkdir "${staging}/kernel-uapi-headers"
cp -a "${kernel_out}/headers/include/." "${staging}/kernel-uapi-headers/"
python3 "${device_dir}/prepare-kernel-headers.py" \
    "${staging}/kernel-uapi-headers" "${staging}/kernel-headers"

find "${kernel_out}/modules" -type f -name '*.ko' -exec cp -t "${staging}" {} +
while IFS= read -r module; do
    module="${module##*/}"
    if [[ -f "${staging}/${module}" ]]; then
        echo "${module}"
    fi
done < "${device_dir}/modules.load" > "${staging}/modules.load"

for module in wlan.ko sec_touch.ko heatmap.ko touch_offload.ko incrementalfs.ko kheaders.ko; do
    test -s "${staging}/${module}" || { echo "Missing required module: ${module}" >&2; exit 1; }
done

{
    echo "Kernel source: $(git -C "${kernel_source}" remote get-url origin)"
    echo "Kernel revision: $(git -C "${kernel_source}" rev-parse HEAD)"
    "${clang_dir}/bin/clang" --version | head -n 1
} > "${staging}/BUILD_INFO"

if [[ -d "${prebuilt_dir}" ]]; then
    mv "${prebuilt_dir}" "${prebuilt_dir}.previous.$(date +%s)"
fi
mv "${staging}" "${prebuilt_dir}"
trap - EXIT
echo "Kernel, DTBO, modules and headers installed in ${prebuilt_dir}"
