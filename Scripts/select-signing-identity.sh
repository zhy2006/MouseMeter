#!/bin/bash
# 从 security 的输出选择唯一私钥身份，并按指纹提取对应公开证书。
set -euo pipefail

case "${1:-}" in
    fingerprint)
        # 未受信任的自签身份也参与选择；去重匹配列表和有效列表中的同一身份。
        fingerprint="$(awk '$1 ~ /^[0-9]+\)$/ && length($2) == 40 && $2 ~ /^[[:xdigit:]]+$/ { print toupper($2) }' | sort -u)"
        if [[ ! "$fingerprint" =~ ^[[:xdigit:]]{40}$ ]]; then
            echo "p12 必须包含且只包含一个带私钥的代码签名身份" >&2
            exit 1
        fi
        printf '%s\n' "$fingerprint"
        ;;
    certificate)
        target="${2:?需要证书指纹}"
        # p12 可含证书链；只提取与私钥身份指纹对应的证书，不按顺序猜测。
        awk -v target="$target" '
            /^SHA-1 hash:/ { selected = toupper($3) == toupper(target) }
            /^-----BEGIN CERTIFICATE-----/ { printing = selected; if (printing) found = 1 }
            printing { print }
            /^-----END CERTIFICATE-----/ { printing = 0 }
            END { if (!found) exit 1 }
        '
        ;;
    *)
        echo "用法：select-signing-identity.sh fingerprint|certificate <指纹>" >&2
        exit 1
        ;;
esac
