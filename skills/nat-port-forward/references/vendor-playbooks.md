# 各厂商路由器后台操作细节

> SKILL.md 的补充参考。只在需要精确字段 id / 页面路径 / 下拉框坑时读。
> 厂商不同时先在管理页确认 UI 版本，字段 id 可能随固件变化；本文件给的是**定位方法**，id 仅供参考。

## 通用定位思路

所有厂商的 Web 管理页都是 SPA。定位方式优先级：

1. **先看页面文字**，用 `document.body.innerText` 找菜单名，胜过猜 class。
2. 表格内容用 `innerText` 按块读，**不要用 `tr.textContent`**——相邻单元格文本会粘连（`WAN`+`80`+`80` 会拼成 `WAN8080`），必须逐单元格读。
3. 表单里区分「可见输入框」和「隐藏 input」：下拉框通常有一个 `hidden` 的 value input，**只改它的 value 不会通过校验**。
4. 下拉框必须**真正点选选项**，并以「校验错误提示消失」为通过判据。

## TL-R473G（tplink-web，新版 Web UI）

### 登录

- 地址：`http://<公网IP>:8090`（管理页已从 80 迁到 8090）。
- 账号 `admin` / 密码 `<配置里的 password>`。
- 登录后 `localStorage.token` 即 stok。

### 新增规则

页面路径：**高级功能 → 虚拟服务器 → 新增**

| 字段 | id | 值 |
|---|---|---|
| 规则名称 | `name` | 自定义 |
| 生效接口 | `virtual_interface`（hidden）+ `label.combobox-label` | **必须点选** `WAN` |
| 外部端口 | `src_dport` | |
| 内部端口 | `dest_port` | |
| 内部服务器IP | `virtual_ipaddr` | 下一层 WAN IP |
| 服务协议 | `virtual_protocol` | `ALL` |

提交：`button.editor-btn.btn-submit`

### 关键坑：生效接口必须真点选

只改隐藏 input 的 value 不生效。必须：

```javascript
document.querySelector('.combobox-container .combobox-switch').click();  // 展开下拉
document.querySelector('label.combobox-label').click();                  // 真实点选
// 校验通过的判据
document.querySelectorAll('.widget-container.error').length === 0
```

失败表现：表格出现 `--` 空行。

### 其他

- 表格容器 id：`#virtualServersGrid`
- 改管理端口：**系统工具 → 系统管理设置**，字段 `http_port` / `https_port`
- 会话有超时，操作要快

## 荣耀 / 华为路由器（huawei-honor）

### 登录

- 地址：`http://<LAN IP>`
- **只需密码，无用户名**
- hash 路由 SPA：`#/login` → `#/home`

### 端口映射

页面路径：**更多功能 → 安全设置 → NAT 服务 → 端口映射**
真实 hash 路由为 `#/more/nat`（**不是**从菜单推算出来的 `/safesettings/nat`）。

菜单 id 全表在 `vue.$store.state.Data.allMenus`；路由定义在 `vue.$router.options.routes`。

### 新增规则

| 字段 | id |
|---|---|
| 服务名 | `service_name_ctrl` |
| 设备 IP | `service_deviceip_ctrl`（**readonly**，由设备下拉联动填入） |
| 外部端口 | `service_pmsrcport_ctrl` |
| 内部端口 | `service_pmdesport_ctrl` |
| 协议 | `service_protype_selectlist_parenselect`（TCP / UDP / TCP/UDP） |

保存：`#postservice`；取消：`#calcelservice`

### 关键坑

- **光填 DOM 不够**，必须同步 Vue 响应式状态，否则保存的是空值：

```javascript
const vue = document.getElementById('app').__vue__;
let nat = null;
const walk = (v, d) => {
  if (!v || d > 15 || nat) return;
  const n = (v.$options && (v.$options.name || v.$options._componentTag)) || '';
  if (n === 'nat') { nat = v; return; }
  (v.$children || []).forEach(c => walk(c, d + 1));
};
walk(vue, 0);

nat.activeItem.Name = 'web';
nat.activeItem.HostIPAddress = '<下一层WAN IP>';
nat.activeItem.HostName = '<设备名>';
nat.activeItem.InternalHost = '<下一层WAN MAC>';   // 必须是下一层设备的 WAN MAC
nat.activeItem.Enable = true;

nat.activeAppSubItem.Protocol = 'TCP/UDP';
nat.activeAppSubItem.ExternalPort = '10080';
nat.activeAppSubItem.ExternalPortEnd = '10080';
nat.activeAppSubItem.InternalPort = '10080';
nat.activeAppSubItem.InternalPortEnd = '10080';

document.getElementById('postservice').click();
```

- **内部端口填错会静默失败**：L2 这一跳的内部端口应等于 **L3 的外部端口**（通常同名），而不是最终服务的端口。填错时外网表现为超时。
- **设备 IP 必须真实填下一层 WAN IP**，否则「设备」列会显示当前 PC 的主机名。
- **保存后核对 MAC**：`InternalHost` 应为下一层设备的 WAN MAC。若显示 PC 的 MAC 或空白，需手动改。

### 规则表

- 每行编辑按钮 id：`InternetGatewayDevice_Services_X_Portmapping_<N>__changeCtrl`
- 点开编辑框可读 DOM 字段值 + `nat.activeItem` / `nat.activeAppSubItem` 状态
- 上限：端口映射与端口触发各 32 条

## TL-WDR7661（tplink-legacy，新版 Web UI）

### 登录

- 地址：`http://<LAN IP>`，账号 `admin` / 密码 `<配置里的 password>`。
- 无 stok。登录框 id：`lgUsr` / `lgPwd`，提交按钮 `#loginSub`。

### 路径

**应用管理 → 已安装应用 → 虚拟服务器 → 进入**

「进入」按钮是 `input[type=button]` value=`进 入`，需先展开「应用管理」。

### 新增规则

1. 点「添加」按钮（`input[type=button]` value=`添加`）
2. 表单字段按顺序（在 `input[type=text]` 里）：

| 顺序 | 含义 | 值 |
|---|---|---|
| 0 | 外部端口 | `class="text"` |
| 1 | 内部端口 | `class="text"` |
| 2 | IP 地址 | `id="ipAddr1virServerLease3"` |

3. 「常用服务器」下拉可留空（= 自定义），协议默认 `ALL`
4. 保存：`input[type=button]` value=`保存`

### 坑

- **表格分页**：规则超过 8 条会分页。分页控件在 `#<表格id>pagIngListlistDiv`，翻页要点 `.ListSpan`（不是 `.listSpanS`，那是当前页）。读取全部规则前记得翻页。
- 表格容器 id：`virServerLease`

## 华为 / 小米等通用家用路由

多数为「端口映射 / 虚拟服务器 / NAT」三选一的名称，字段语义一致：

- 服务名 / 规则名
- 内部主机 / 目标 IP = 下一层 WAN IP
- 内部端口 / 目标端口 = 下一层外部端口
- 外部端口 / 起始端口
- 协议：TCP / UDP / 两者

先用 `document.body.innerText` 找到页面，再逐个 input 反查 label 文本确定字段含义。

## 服务器侧 nginx 配套改动（宝塔）

映射到某端口后，服务器 nginx 站点需要能服务该端口。

### 站点 vhost

`/www/server/panel/vhost/nginx/<站点>.conf`

```nginx
listen <内部端口>;
server_name <域名>;
```

需要 TLS 时：

```nginx
listen <内部端口> ssl;
ssl_certificate     /www/server/panel/vhost/cert/<站点>/fullchain.pem;
ssl_certificate_key /www/server/panel/vhost/cert/<站点>/privkey.pem;
```

**必须删除**（若存在）：

```nginx
error_page 497  https://$host$request_uri;
```

原因：497 = 明文请求打到 SSL 端口，该行 301 到不带端口的 443；443 常被运营商封禁 → HTTP 也打不开。

### 伪静态 / API 反代

宝塔「网站 → 伪静态」管理的文件位于：

```
/www/server/panel/vhost/rewrite/<站点>.conf
```

由站点 vhost 的 `#REWRITE-START` 段 include：

```nginx
include /www/server/panel/vhost/rewrite/<站点>.conf;
```

**注意路径层级**：是 `vhost/rewrite/`，**不是** `vhost/nginx/rewrite/`。写错会报 `emerg: open() ... No such file or directory`。

常见内容（SPA 回退 + 后端反代）：

```nginx
location / { try_files $uri $uri/ /index.html; }
location ^~ /api/  { proxy_pass http://127.0.0.1:<后端端口>/api/;  ... }
location ^~ /auth/ { proxy_pass http://127.0.0.1:<后端端口>/auth/; ... }
location ^~ /ws/   { proxy_pass http://127.0.0.1:<后端端口>/ws/;   ... }
```

### 后端不需要配 SSL

TLS 在 nginx 终结，nginx 到 `127.0.0.1:<后端端口>` 是同机明文回环。`proxy_pass` 保持 `http://` 即可。

### 改完执行

```bash
/www/server/nginx/sbin/nginx -t && /www/server/nginx/sbin/nginx -s reload
```

> 面板重新部署/续期证书会重写 vhost，改完需复核。
