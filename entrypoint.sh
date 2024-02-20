#!/bin/bash
set -euo pipefail

FILE="$(basename "$0")"

# 启用 multilib 仓库
cat << EOM >> /etc/pacman.conf
[multilib]
Include = /etc/pacman.d/mirrorlist
[archlinuxcn]
Server = https://repo.archlinuxcn.org/x86_64
EOM
pacman-key --init
pacman-key --lsign-key "farseerfc@archlinux.org"
pacman -Sy --noconfirm && pacman -S --noconfirm archlinuxcn-keyring 

pacman -Syu --noconfirm --needed base-devel

# Makepkg 不允许以 root 身份运行
# 创建一个新用户 `builder`
# `builder` 需要有一个家目录，因为某些 PKGBUILD 将尝试向其写入（例如，用于缓存）
useradd builder -m
# 在安装依赖时，makepkg 将使用 sudo
# 让用户 `builder` 具有无密码 sudo 访问权限
echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# 让所有用户（特别是 builder）都可以完全访问这些文件
chmod -R a+rw .

BASEDIR="$PWD"
cd "${INPUT_PKGDIR:-.}"

# 假设如果 .SRCINFO 不存在，则是在其他地方生成的。
# AUR 检查 .SRCINFO 是否存在，因此不能忽略丢失的文件。
if [ -f .SRCINFO ] && ! sudo -u builder makepkg --printsrcinfo | diff - .SRCINFO; then
    echo "::error file=$FILE,line=$LINENO::Mismatched .SRCINFO. Update with: makepkg --printsrcinfo > .SRCINFO"
    exit 1
fi

# 如果存在 INPUT_AURDEPS，则从 AUR 安装依赖
if [ -n "${INPUT_AURDEPS:-}" ]; then
    # 首先安装 yay
    pacman -S --noconfirm --needed git
    git clone https://aur.archlinux.org/yay-bin.git /tmp/yay
    pushd /tmp/yay
    chmod -R a+rw .
    sudo -H -u builder makepkg --syncdeps --install --noconfirm
    popd

    # 从 .SRCINFO 中提取依赖关系并安装
    mapfile -t PKGDEPS < \
        <(sudo -u builder makepkg --printsrcinfo | sed -n -e 's/^[[:space:]]*\(make\)\?depends\(_x86_64\)\? = \([[:alnum:][:punct:]]*\)[[:space:]]*$/\3/p')
    sudo -H -u builder yay --sync --noconfirm "${PKGDEPS[@]}"
fi

# 将 builder 用户设置为这些文件的所有者
# 没有这个，（例如，只允许每个用户对文件进行读/写访问），
# makepkg 将尝试更改文件的权限，这将失败，因为它不拥有文件/具有权限
# 我们不能更早地这样做，因为它将更改 github actions 的文件，这会导致 github actions 日志中的警告。
chown -R builder .

# 构建包
# INPUT_MAKEPKGARGS 是故意未引用的，以允许参数分割
# shellcheck disable=SC2086
sudo -H -u builder makepkg --syncdeps --noconfirm ${INPUT_MAKEPKGARGS:-}

# 获取要构建的包数组
mapfile -t PKGFILES < <(sudo -u builder makepkg --packagelist)
echo "Package(s): ${PKGFILES[*]}"

# 报告构建的包档案
i=0
for PKGFILE in "${PKGFILES[@]}"; do
    # makepkg 报告绝对路径，必须对其他操作者设置为相对路径
    RELPKGFILE="$(realpath --relative-base="$BASEDIR" "$PKGFILE")"
    # 调用者参数对 makepkg 可能意味着未构建包
    if [ -f "$PKGFILE" ]; then
        echo "::set-output name=pkgfile$i::$RELPKGFILE"
    else
        echo "Archive $RELPKGFILE not built"
    fi
    (( ++i ))
done

function prepend () {
    # 在每个输入行之前添加参数
    while read -r line; do
        echo "$1$line"
    done
}

function namcap_check() {
    # 运行 namcap 检查
    # 在构建之后安装 namcap，以便在可以捕获任何缺少的依赖项的最小安装上进行 makepkg。
    pacman -S --noconfirm --needed namcap

    NAMCAP_ARGS=()
    if [ -n "${INPUT_NAMCAPRULES:-}" ]; then
        NAMCAP_ARGS+=( "-r" "${INPUT_NAMCAPRULES}" )
    fi
    if [ -n "${INPUT_NAMCAPEXCLUDERULES:-}" ]; then
        NAMCAP_ARGS+=( "-e" "${INPUT_NAMCAPEXCLUDERULES}" )
    fi

    # 由于某些原因，sudo 未重置 '$PATH'
    # 结果，namcap 找到的程序路径位于 /usr/sbin 而不是 /usr/bin
    # 这使得 namcap 无法识别提供程序的软件包，从而导致 namcap 无法识别软件包并因此发出虚假警告。
    # 更多细节：https://bugs.archlinux.org/task/66430
    #
    # 通过在 $PATH 中放置 bin，使得其在 sbin 之前，来解决这个问题
    export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"

    namcap "${NAMCAP_ARGS[@]}" PKGBUILD \
        | prepend "::warning file=$FILE,line=$LINENO::"
    for PKGFILE in "${PKGFILES[@]}"; do
        if [ -f "$PKGFILE" ]; then
            RELPKGFILE="$(realpath --relative-base="$BASEDIR" "$PKGFILE")"
            namcap "${NAMCAP_ARGS[@]}" "$PKGFILE" \
                | prepend "::warning file=$FILE,line=$LINENO::$RELPKGFILE:"
        fi
    done
}

if [ -z "${INPUT_NAMCAPDISABLE:-}" ]; then
    namcap_check
fi
