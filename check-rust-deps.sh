#!/bin/bash

# Mesa Rust Dependencies Version Checker
# 快速检查PKGBUILD中的Rust crates版本是否与Mesa源码匹配

set -e

echo "🔍 检查Mesa Rust依赖版本..."
echo "=================================="

# 检查PKGBUILD是否存在
if [[ ! -f "PKGBUILD" ]]; then
    echo "❌ 未找到PKGBUILD文件"
    exit 1
fi

# 获取PKGBUILD中的crates版本
declare -A pkgbuild_crates
while read -r line; do
    if [[ $line =~ ^[[:space:]]*([a-zA-Z0-9_-]+)[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+) ]]; then
        crate="${BASH_REMATCH[1]}"
        version="${BASH_REMATCH[2]}"
        pkgbuild_crates[$crate]=$version
    fi
done < <(sed -n '/declare -A _crates=/,/^)/p' PKGBUILD | grep -E "^[[:space:]]*[a-zA-Z0-9_-]+[[:space:]]+[0-9]")

echo "📦 PKGBUILD中的crates:"
for crate in "${!pkgbuild_crates[@]}"; do
    echo "  $crate: ${pkgbuild_crates[$crate]}"
done | sort

# 检查Mesa源码
mesa_dir=$(ls -d src/mesa-* 2>/dev/null | head -1)
if [[ -z "$mesa_dir" ]]; then
    echo ""
    echo "⚠️  Mesa源码未解压"
    echo "💡 运行: makepkg --nobuild --skipinteg"
    exit 0
fi

echo ""
echo "🔍 Mesa源码期望的版本:"

declare -A mesa_crates

# 扫描.wrap文件，只关注Rust crates
rust_crates_pattern="^(equivalent|hashbrown|indexmap|once_cell|paste|pest|pest_derive|pest_generator|pest_meta|proc-macro2|quote|roxmltree|rustc-hash|syn|ucd-trie|unicode-ident|bitflags|cfg-if|errno|libc|log|remain|rustix|thiserror|thiserror-impl|zerocopy|zerocopy-derive)$"

if [[ -d "$mesa_dir/subprojects" ]]; then
    for wrap_file in "$mesa_dir"/subprojects/*.wrap; do
        if [[ -f "$wrap_file" ]]; then
            crate=$(basename "$wrap_file" .wrap)
            
            # 只处理已知的Rust crates
            if [[ $crate =~ $rust_crates_pattern ]]; then
                version=$(grep "^directory = " "$wrap_file" 2>/dev/null | sed 's/.*-\([0-9][0-9.]*\)$/\1/')
                
                if [[ -n "$version" && "$version" =~ ^[0-9] ]]; then
                    mesa_crates[$crate]=$version
                    echo "  $crate: $version"
                fi
            fi
        fi
    done
fi

echo ""
echo "📊 版本对比结果:"
echo "=================="

# 比较版本 - 检查PKGBUILD中的crates
version_mismatch=false
auto_download_count=0

for crate in "${!pkgbuild_crates[@]}"; do
    pkg_ver="${pkgbuild_crates[$crate]}"
    mesa_ver="${mesa_crates[$crate]:-}"
    
    if [[ -z "$mesa_ver" ]]; then
        echo "⚠️  $crate: PKGBUILD有($pkg_ver), Mesa可能不需要"
    elif [[ "$pkg_ver" == "$mesa_ver" ]]; then
        echo "✅ $crate: $pkg_ver"
    else
        echo "❌ $crate: PKGBUILD($pkg_ver) ≠ Mesa($mesa_ver)"
        version_mismatch=true
    fi
done

# 检查Mesa需要但PKGBUILD缺失的 - 这些会自动下载
echo ""
echo "🌐 由Meson自动下载的crates:"
for crate in "${!mesa_crates[@]}"; do
    if [[ -z "${pkgbuild_crates[$crate]:-}" ]]; then
        echo "   $crate: ${mesa_crates[$crate]} (在线获取)"
        auto_download_count=$((auto_download_count + 1))
    fi
done

echo ""
if $version_mismatch; then
    echo "🚨 发现版本冲突! 需要更新PKGBUILD"
    exit 1
else
    matched_count=${#pkgbuild_crates[@]}
    echo "🎉 PKGBUILD中的 $matched_count 个crates版本全部匹配!"
    if (( auto_download_count > 0 )); then
        echo "📡 另有 $auto_download_count 个crates将由Meson自动下载"
        echo "💡 这是正常的，无需手动添加到PKGBUILD"
    fi
fi 