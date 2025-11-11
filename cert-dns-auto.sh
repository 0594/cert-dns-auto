#!/bin/bash
set -euo pipefail

# ========================
# ANSI 颜色（仅终端启用）
# ========================
if [ -t 1 ]; then
    RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
    BLUE=$'\033[0;34m'; BOLD=$'\033[1m'; NC=$'\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
fi

log_info()    { echo "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo "${GREEN}✅ $1${NC}"; }
log_warn()    { echo "${YELLOW}⚠️  $1${NC}"; }
log_error()   { echo "${RED}❌ $1${NC}" >&2; exit 1; }

# ========================
# 全局变量
# ========================
ACME="${HOME}/.acme.sh/acme.sh"
DOMAIN=""
CA="letsencrypt"
DNS_PROVIDER=""
CERT_DIR=""
INTERNAL_DIR=""

# ========================
# 安装 acme.sh（如未安装）
# ========================
install_acme() {
    if [ ! -f "$ACME" ]; then
        log_info "正在安装 acme.sh..."
        curl -s https://get.acme.sh | sh || log_error "acme.sh 安装失败"
    fi
}

# ========================
# 设置 DNS 凭据
# ========================
setup_dns_creds() {
    case "$DNS_PROVIDER" in
        dns_cf)
            file="${HOME}/.cf_token"
            [ ! -f "$file" ] && {
                read -rsp "${YELLOW}请输入 Cloudflare API Token: ${NC}" token
                echo "$token" > "$file" && chmod 600 "$file"
            }
            export CF_API_TOKEN="$(cat "$file")"
            grep -q '^CF_Token=' ~/.acme.sh/account.conf 2>/dev/null || \
                echo "CF_Token=\"$(cat "$file")\"" >> ~/.acme.sh/account.conf
            ;;

        dns_ali)
            file="${HOME}/.aliyun_keys"
            [ ! -f "$file" ] && {
                read -rp "${YELLOW}阿里云 AccessKey ID: ${NC}" id
                read -rsp "${YELLOW}阿里云 AccessKey Secret: ${NC}" secret
                echo; echo "Ali_Key=\"$id\"" > "$file"
                echo "Ali_Secret=\"$secret\"" >> "$file"
                chmod 600 "$file"
            }
            export Ali_Key Ali_Secret
            source "$file"
            ;;

        dns_dp)
            file="${HOME}/.dnspod_keys"
            [ ! -f "$file" ] && {
                read -rp "${YELLOW}DNSPod ID / 腾讯云 SecretId: ${NC}" id
                read -rsp "${YELLOW}DNSPod Token / SecretKey: ${NC}" key
                echo; echo "DP_Id=\"$id\"" > "$file"
                echo "DP_Key=\"$key\"" >> "$file"
                chmod 600 "$file"
            }
            export DP_Id DP_Key
            source "$file"
            ;;

        *)
            log_error "不支持的 DNS 提供商: $DNS_PROVIDER"
            ;;
    esac
}

# ========================
# 选择 DNS 服务商（交互式）
# ========================
choose_dns_provider() {
    echo
    echo "${BOLD}=== 选择 DNS 服务商 ===${NC}"
    echo "1) Cloudflare"
    echo "2) 阿里云"
    echo "3) 腾讯云 DNSPod"
    read -rp "${BLUE}请选择 (1/2/3，默认 1): ${NC}" choice

    case "${choice:-1}" in
        2) DNS_PROVIDER="dns_ali" ;;
        3) DNS_PROVIDER="dns_dp" ;;
        *) DNS_PROVIDER="dns_cf" ;;
    esac
    log_info "DNS 提供商: $DNS_PROVIDER"
}

# ========================
# 主程序
# ========================
main() {
    echo
    echo "${BOLD}=== 🔐 DNS 证书申请工具（强制 DNS 验证） ===${NC}"

    # 输入域名
    read -rp "${BLUE}请输入域名（如 example.com 或 *.example.com）: ${NC}" DOMAIN
    [[ -z "$DOMAIN" ]] && log_error "域名不能为空"

    # 基础格式验证（允许 * 开头，符合 DNS 规范）
    if ! [[ "$DOMAIN" =~ ^(\*\.)?[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+$ ]]; then
        log_error "域名格式无效。示例：example.com 或 *.example.com"
    fi

    # 选择 CA
    read -rp "${BLUE}CA (1=Let's Encrypt, 2=ZeroSSL，默认 1): ${NC}" ca_opt
    [ "${ca_opt:-1}" = "2" ] && CA="zerossl"

    # ZeroSSL 注册
    if [ "$CA" = "zerossl" ] && [ ! -f ~/.acme.sh/ca/zerossl/ca.conf ]; then
        while :; do
            read -rp "${YELLOW}请输入 ZeroSSL 注册邮箱: ${NC}" email
            [[ "$email" == *@*.* ]] && break
            log_warn "邮箱格式无效，请重试。"
        done
        "$ACME" --register-account -m "$email" --server zerossl || log_error "ZeroSSL 账户注册失败"
    fi

    # 选择 DNS 服务商
    choose_dns_provider

    # 构造证书目录（* 替换为 _）
    CERT_DIR="${DOMAIN//\*/_}_ecc"
    INTERNAL_DIR="$CERT_DIR"

    # 检查是否跳过申请
    SKIP=false
    cert_path="${CERT_DIR}/fullchain.cer"
    if [ -f "$cert_path" ] && openssl x509 -in "$cert_path" -noout >/dev/null 2>&1; then
        not_after=$(openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null | cut -d= -f2)
        if [ -n "$not_after" ]; then
            days_left=$(( ($(date -d "$not_after" +%s) - $(date +%s)) / 86400 ))
            if [ "$days_left" -gt 30 ]; then
                log_success "证书有效（剩余 ${days_left} 天），跳过申请。"
                SKIP=true
            fi
        fi
    fi

    # 申请证书
    if [ "$SKIP" = false ]; then
        install_acme
        setup_dns_creds
        mkdir -p "$CERT_DIR"
        log_info "正在为 $DOMAIN 申请 ECC 证书（DNS 验证）..."
        "$ACME" --issue -d "$DOMAIN" --dns "$DNS_PROVIDER" --server "$CA" --force --ecc

        # 复制证书文件
        cp "${HOME}/.acme.sh/${INTERNAL_DIR}/fullchain.cer" "$CERT_DIR/"
        cp "${HOME}/.acme.sh/${INTERNAL_DIR}/${DOMAIN}.key" "$CERT_DIR/private.key"
        cp "${HOME}/.acme.sh/${INTERNAL_DIR}/ca.cer" "$CERT_DIR/"
        log_success "✅ 证书申请成功！"
    fi

    # 生成续期脚本
    cat > "${CERT_DIR}/renew.sh" <<EOF
#!/bin/bash
set -euo pipefail
cd "\$(dirname "\$0")"

case "$DNS_PROVIDER" in
    dns_cf)   export CF_API_TOKEN=\$(cat "${HOME}/.cf_token");;
    dns_ali)  source "${HOME}/.aliyun_keys";;
    dns_dp)   source "${HOME}/.dnspod_keys";;
esac

"${ACME}" --renew -d "${DOMAIN}" --ecc --server "${CA}"

cp "\${HOME}/.acme.sh/${INTERNAL_DIR}/fullchain.cer" ./fullchain.cer
cp "\${HOME}/.acme.sh/${INTERNAL_DIR}/${DOMAIN}.key" ./private.key
cp "\${HOME}/.acme.sh/${INTERNAL_DIR}/ca.cer" ./ca.cer
EOF

    chmod +x "${CERT_DIR}/renew.sh"

    # 添加 cron 任务
    cron_job="0 2 * * * cd $(pwd) && ./${CERT_DIR}/renew.sh >> ./${CERT_DIR}/renew.log 2>&1"
    (crontab -l 2>/dev/null | grep -F "${CERT_DIR}/renew.sh") >/dev/null || {
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
        log_success "🔄 自动续期任务已添加（每天 02:00 执行）。"
    }

    # 输出结果
    echo
    echo "${BOLD}========================================${NC}"
    log_success "🎉 操作完成！"
    echo "${BOLD}🌐 域名:${NC} $DOMAIN"
    echo "${BOLD}📂 证书目录:${NC} $(pwd)/$CERT_DIR"
    echo "${BOLD}📜 fullchain.cer:${NC} $(pwd)/$CERT_DIR/fullchain.cer"
    echo "${BOLD}🔑 私钥:${NC} $(pwd)/$CERT_DIR/private.key"
    echo "${BOLD}🔄 续期命令:${NC} $(pwd)/$CERT_DIR/renew.sh"
    echo "${BOLD}========================================${NC}"
}

# ========================
# 执行主函数
# ========================
main "$@"
