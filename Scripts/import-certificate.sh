#!/bin/bash
# 仅供 GitHub 托管 macOS runner 使用，导入 p12 并自动识别唯一签名身份。
set -euo pipefail
set +x
umask 077

: "${RUNNER_TEMP:?需要 RUNNER_TEMP}"
: "${GITHUB_OUTPUT:?需要 GITHUB_OUTPUT}"
: "${MACOS_CERTIFICATE_P12_BASE64:?请配置 MACOS_CERTIFICATE_P12_BASE64 Secret}"
: "${MACOS_CERTIFICATE_PASSWORD:?请配置 MACOS_CERTIFICATE_PASSWORD Secret}"

certificate_path="$RUNNER_TEMP/mousemeter-signing.p12"
public_certificate="$RUNNER_TEMP/mousemeter-signing.pem"
keychain_path="$RUNNER_TEMP/mousemeter-signing.keychain-db"
keychain_password="$(openssl rand -hex 32)"
printf '::add-mask::%s\n' "$keychain_password"

printf '%s' "$MACOS_CERTIFICATE_P12_BASE64" | base64 --decode > "$certificate_path"
echo "Creating temporary signing keychain"
security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
echo "Importing certificate and private key"
security import "$certificate_path" -P "$MACOS_CERTIFICATE_PASSWORD" -k "$keychain_path" -T /usr/bin/codesign
echo "Configuring non-interactive private key access"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain_path" > /dev/null
security list-keychains -d user -s "$keychain_path"

echo "Selecting signing identity and matching public certificate"
# 自签证书需在一次性的 runner 上建立信任，否则不会被列为有效代码签名身份。
fingerprint="$(security find-identity -p codesigning "$keychain_path" | bash Scripts/select-signing-identity.sh fingerprint)"
security find-certificate -a -p -Z "$keychain_path" |
    bash Scripts/select-signing-identity.sh certificate "$fingerprint" > "$public_certificate"
echo "Trusting signing certificate in the admin domain"
sudo -n security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain "$public_certificate"
echo "Validating signing identity"
certificate_fingerprint="$(openssl x509 -in "$public_certificate" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')"
if [ "$certificate_fingerprint" != "$fingerprint" ]; then
    echo "公开证书与签名私钥身份不匹配" >&2
    exit 1
fi
if ! security find-identity -v -p codesigning "$keychain_path" | grep -Fq "$fingerprint"; then
    echo "证书必须包含有效的代码签名私钥，请检查导出的 p12" >&2
    exit 1
fi
printf 'identity=%s\n' "$fingerprint" >> "$GITHUB_OUTPUT"
# 私钥仅保留在临时钥匙串，解码文件在导入后立即移除。
rm -f "$certificate_path" "$public_certificate"
