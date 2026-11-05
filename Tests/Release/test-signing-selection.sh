#!/bin/bash
# 验证自签身份自动选择，拒绝缺少私钥或含多个身份的 p12。
set -euo pipefail
cd "$(dirname "$0")/../.."
first=F59A55AA31DD7E2DB36EF2ACD1FA467C2BE84547
second=0123456789ABCDEF0123456789ABCDEF01234567

# 同一个身份可同时出现在匹配和有效列表中；未受信任时仍能被选出。
test "$(printf '  1) %s "Demo"\n  1) %s "Demo"\n' "$first" "$first" |
    bash Scripts/select-signing-identity.sh fingerprint)" = "$first"
test "$(printf '  1) %s "Demo" (CSSMERR_TP_NOT_TRUSTED)\n' "$first" |
    bash Scripts/select-signing-identity.sh fingerprint)" = "$first"
if printf '0 identities found\n' | bash Scripts/select-signing-identity.sh fingerprint > /dev/null 2>&1; then
    echo "不应接受缺少私钥身份的输出" >&2
    exit 1
fi
if printf '1) %s "First"\n2) %s "Second"\n' "$first" "$second" |
    bash Scripts/select-signing-identity.sh fingerprint > /dev/null 2>&1; then
    echo "不应自动猜测多个签名身份" >&2
    exit 1
fi

# 即使证书链在前面，也必须按指纹选出正确证书。
certificate="$(printf 'SHA-1 hash: %s\n-----BEGIN CERTIFICATE-----\nCHAIN\n-----END CERTIFICATE-----\nSHA-1 hash: %s\n-----BEGIN CERTIFICATE-----\nSIGNER\n-----END CERTIFICATE-----\n' "$second" "$first" |
    bash Scripts/select-signing-identity.sh certificate "$first")"
test "$certificate" = $'-----BEGIN CERTIFICATE-----\nSIGNER\n-----END CERTIFICATE-----'
if printf 'SHA-1 hash: %s\n-----BEGIN CERTIFICATE-----\nCHAIN\n-----END CERTIFICATE-----\n' "$second" |
    bash Scripts/select-signing-identity.sh certificate "$first" > /dev/null 2>&1; then
    echo "缺少匹配证书时必须失败" >&2
    exit 1
fi
echo "签名身份自动识别测试通过"
