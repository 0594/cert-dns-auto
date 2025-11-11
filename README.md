# 🛡️自动申请 DNS 验证型 SSL/TLS 证书（支持通配符）

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

> 一键自动化申请 Let's Encrypt / ZeroSSL 的 **ECC 证书**，通过 **DNS API 验证**（无需开放 80/443 端口），完美支持 **通配符域名（如 `*.example.com`）**。  
> 支持 **Cloudflare、阿里云、腾讯云 DNSPod** 三大主流 DNS 服务商。

---

## ✨ 特性

- ✅ **强制使用 DNS 验证**（安全、无需公网 Web 服务）
- ✅ **原生支持通配符证书**（`*.example.com`）
- ✅ **自动续期 + cron 任务集成**
- ✅ **支持 Let's Encrypt 和 ZeroSSL**
- ✅ **凭据安全存储**（权限 `600`，不暴露在命令行）
- ✅ **极简交互式流程**（只需输入域名和 API 凭据一次）
- ✅ **兼容所有 Linux 发行版**（依赖 `bash`, `curl`, `openssl`）

---
## 📁使用截图
[![演示](https://github.com/0594/cert-dns-auto/blob/main/example.png)](example.png)
---
## 🚀 快速开始

### 一键运行（推荐）

直接在终端中执行以下命令，无需下载脚本文件：

```bash
bash -c "$(curl -s https://raw.githubusercontent.com/0594/cert-dns-auto/main/cert-dns-auto.sh)"
```

或者使用 `wget`：

```bash
bash <(wget -O - https://raw.githubusercontent.com/0594/cert-dns-auto/main/cert-dns-auto.sh)
```

### 传统方式（下载后运行）

如果你更喜欢先下载脚本：

```bash
curl -O https://raw.githubusercontent.com/0594/cert-dns-auto/main/cert-dns-auto.sh
chmod +x cert-dns-auto.sh
./cert-dns-auto.sh
```

> 或克隆整个仓库：
> ```bash
> git clone https://github.com/0594/cert-dns-auto.git
> cd cert-dns-auto
> chmod +x cert-dns-auto.sh
> ./cert-dns-auto.sh
> ```

### 运行脚本

按照提示操作：

1. 输入域名（如 `*.example.com` 或 `web.example.com`）
2. 选择证书颁发机构（CA）：Let's Encrypt（默认）或 ZeroSSL
3. 选择 DNS 服务商：Cloudflare / 阿里云 / 腾讯云 DNSPod
4. 首次使用时输入对应 API 凭据（仅需一次）

✅ 完成后，证书将保存在 `./<domain>_ecc/` 目录中。

---

## 🔐 DNS 服务商配置说明

脚本会自动创建凭据文件并设置 `600` 权限，确保安全。

| 服务商 | 插件名 | 凭据文件 | 所需权限 |
|--------|--------|----------|----------|
| **Cloudflare** | `dns_cf` | `~/.cf_token` | `Zone.Zone Read` + `Zone.DNS Edit` |
| **阿里云** | `dns_ali` | `~/.aliyun_keys` | `AliyunDNSFullAccess`（或自定义策略） |
| **腾讯云 DNSPod** | `dns_dp` | `~/.dnspod_keys` | 账号 API Token **或** CAM 用户的 `SecretId/SecretKey` |

### 🔧 如何获取 API 凭据？

#### Cloudflare
1. 登录 [Cloudflare Dashboard](https://dash.cloudflare.com)
2. 进入 **My Profile → API Tokens**
3. 创建 Token，模板选择 **“Edit zone DNS”**
4. 复制 Token 值

#### 阿里云
1. 登录 [RAM 控制台](https://ram.console.aliyun.com/users)
2. 创建用户，授权策略：`AliyunDNSFullAccess`
3. 获取 **AccessKey ID** 和 **AccessKey Secret**

#### 腾讯云 DNSPod
- **方式一（推荐）**：使用 [DNSPod Token](https://console.dnspod.cn/account/token)
  - ID = Token ID
  - Token = Token
- **方式二**：使用 CAM 用户的 SecretId/SecretKey（需授权 DNSPod 相关权限）

---

## 📁 输出目录结构

假设你申请的是 `*.example.com`，则生成目录为：

```
./_example.com_ecc/
├── fullchain.cer    # 证书链（含中间 CA）
├── private.key      # 私钥（ECC）
├── ca.cer           # 中间 CA 证书
└── renew.sh         # 续期脚本（已自动加入 cron）
```
假设你申请的是 `web.example.com`，则生成目录为：

```
./web.example.com_ecc/
├── fullchain.cer    # 证书链（含中间 CA）
├── private.key      # 私钥（ECC）
├── ca.cer           # 中间 CA 证书
└── renew.sh         # 续期脚本（已自动加入 cron）
```


> 注意：通配符 `*` 会被自动替换为 `_`，符合 acme.sh 内部命名规范。

---

## 🔄 自动续期

脚本会自动创建 cron 任务，每天凌晨 2 点检查并续期：

```cron
0 2 * * * cd /your/path && ./_example.com_ecc/renew.sh >> ./_example.com_ecc/renew.log 2>&1
```

你可以手动测试续期：

```bash
./_example.com_ecc/renew.sh
```

---

## ⚙️ 依赖项

- `bash`（>= 4.0）
- `curl`
- `openssl`
- `acme.sh`（脚本会自动安装）

> 在大多数 Linux 服务器（Ubuntu/CentOS/Debian 等）上默认满足。

---

## ❓ 常见问题

### Q: 能否申请多域名（SAN）证书？
> 当前版本仅支持单域名（含通配符）。如需 SAN，请 fork 后扩展 `-d domain1 -d domain2` 参数。

### Q: 为什么不用 HTTP 验证？
> HTTP 验证需要临时开放 80 端口并响应 ACME 挑战，不适合内网或防火墙严格环境。**DNS 验证更安全、通用**。

### Q: 凭据泄露怎么办？
> 所有凭据保存在用户家目录，权限为 `600`（仅当前用户可读）。建议定期轮换 API Token。

---

## 📜 许可证

本项目基于 [MIT License](LICENSE) 开源。

---

## 💬 反馈与贡献

欢迎提交 Issue 或 Pull Request！  
GitHub: [https://github.com/0594/cert-dns-auto](https://github.com/0594/cert-dns-auto)

---

> Made with ❤️ by [0594](https://github.com/0594)  
> Powered by [acme.sh](https://github.com/acmesh-official/acme.sh)
