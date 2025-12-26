# 認證機制詳細說明

## 目錄

- [概述](#概述)
- [設計目標](#設計目標)
- [認證流程](#認證流程)
  - [1. HELLO 握手](#1-hello-握手)
  - [2. LOGIN 驗證](#2-login-驗證)
- [Nonce 機制](#nonce-機制)
- [Token 計算](#token-計算)
- [XOR 加密演示（可選）](#xor-加密演示可選)
- [安全性考量](#安全性考量)
- [程式碼實作](#程式碼實作)
- [時序圖](#時序圖)
- [常見問題](#常見問題)

---

## 概述

本專案實作了基於 **nonce + simple hash** 的登入握手機制，用於示範網路協定中的基本認證流程。此實作包含：

- **Nonce-based Challenge-Response**：使用伺服器產生的隨機數防止重放攻擊
- **Simple Hash Verification**：使用 CRC32 作為簡單的雜湊函式（教學用途）
- **Optional XOR Encryption**：可選的 XOR 加密演示（教學用途）

> **注意**：此認證機制僅供**教學與演示**使用，不適合生產環境。生產環境應使用 TLS/SSL + 強加密演算法（如 bcrypt、Argon2）+ JWT/OAuth2 等成熟方案。

---

## 設計目標

本認證機制的設計目標：

1. **教學性**：展示 challenge-response 認證的基本原理
2. **簡單性**：使用 CRC32 而非 SHA-256，降低實作複雜度
3. **可擴展性**：支援 XOR 加密 flag，演示加密協定
4. **防重放**：使用 server nonce 確保每次登入都需要新的 token
5. **無狀態驗證**：伺服器可以用同一個 nonce 服務多個客戶端（demo 模式）

---

## 認證流程

### 完整流程概覽

```
客戶端                              伺服器
  |                                   |
  |  ---- OP_HELLO (req_id=1) ---->   |
  |                                   |  生成/讀取 server_nonce
  |  <--- HELLO Response --------     |  (8-byte random number)
  |       (nonce: 0x1234567890ABCDEF) |
  |                                   |
  |  計算 token:                      |
  |  token = CRC32(username || nonce) |
  |                                   |
  |  ---- OP_LOGIN (req_id=2) ---->   |
  |       (username="alice")          |
  |       (token=0xABCDEF01)          |  驗證:
  |                                   |  expected = CRC32("alice" || nonce)
  |                                   |  if (token == expected) → 成功
  |  <--- LOGIN Response ---------    |
  |       (user_id=1, balance=0)      |
  |                                   |
  |  ---- 其他操作 (已認證) ---->     |
  |                                   |
```

---

### 1. HELLO 握手

#### 客戶端請求

- **OpCode**: `OP_HELLO` (0x0001)
- **Body**: 空（無 payload）
- **目的**: 請求伺服器的 nonce

#### 伺服器回應

- **Status**: `ST_OK` (0x0000)
- **Body**: 8-byte `server_nonce`（Big-Endian）
- **實作位置**: `src/server/worker.c:195-199`

```c
case OP_HELLO: {
  uint8_t resp[8];
  ns_put_be64(resp, shm->server_nonce);
  send_simple_response(c, OP_HELLO, ST_OK, req_id, resp, sizeof(resp));
  break;
}
```

#### Nonce 生成

伺服器在啟動時生成一次性 nonce（位於共享記憶體）：

```c
// src/server/shm_state.c:79-81
uint64_t now_ms(void) {
  // 時間戳 + PID + magic number
  return (now_ms() ^ getpid() ^ 0x9E3779B97F4A7C15ULL);
}

shm->server_nonce = now_ms();
```

---

### 2. LOGIN 驗證

#### 客戶端請求

- **OpCode**: `OP_LOGIN` (0x0002)
- **Body 格式**:
  ```
  [ u16 username_len ][ username (variable) ][ u32 token ]
  ```

#### Token 計算

客戶端使用伺服器的 nonce 計算 token：

```c
// src/client/interactive.c:255-258
uint8_t tmp[NS_MAX_USERNAME + 8];
memcpy(tmp, username, ulen);
ns_put_be64(tmp + ulen, nonce);  // 附加 nonce (big-endian)
uint32_t token = ns_crc32(tmp, ulen + 8u);
```

**計算公式**:
```
token = CRC32(username || server_nonce_be64)
```

#### 伺服器驗證

- **實作位置**: `src/server/worker.c:216-224`

```c
// 重新計算 expected token
uint8_t tmp[NS_MAX_USERNAME + 8];
memcpy(tmp, uname, ulen);
ns_put_be64(tmp + ulen, shm->server_nonce);
uint32_t want = ns_crc32(tmp, ulen + 8u);

if (token != want) {
  send_simple_response(c, OP_LOGIN, ST_ERR_UNAUTHORIZED, req_id, NULL, 0);
  break;
}
```

#### 成功回應

- **Status**: `ST_OK` (0x0000)
- **Body 格式**:
  ```
  [ u32 user_id ][ i64 balance ]
  ```

```c
// src/server/worker.c:240-245
uint8_t resp[4 + 8];
ns_put_be32(resp, uid);
int64_t bal = shm->balance[uid];
ns_put_be64(resp + 4, (uint64_t)bal);
send_simple_response(c, OP_LOGIN, ST_OK, req_id, resp, sizeof(resp));
```

---

## Nonce 機制

### 什麼是 Nonce？

**Nonce** (Number used ONCE) 是一個只使用一次的隨機數，用於防止重放攻擊。

### 本專案的 Nonce 特性

1. **生成時機**: 伺服器啟動時生成一次
2. **儲存位置**: 共享記憶體 (`ns_shm_t.server_nonce`)
3. **生命週期**: 伺服器重啟前保持不變
4. **共享性**: 所有 worker 共用同一個 nonce（簡化實作）

### 為什麼需要 Nonce？

```
情境 1: 沒有 nonce
┌────────────────────────────────────────────┐
│ 攻擊者截獲: LOGIN(username="alice",       │
│              token=0xABCDEF01)             │
│                                            │
│ → 攻擊者可以無限次重放此封包登入！         │
└────────────────────────────────────────────┘

情境 2: 使用 nonce
┌────────────────────────────────────────────┐
│ 第一次登入: token = CRC32("alice" || nonce₁) │
│ 第二次登入: token = CRC32("alice" || nonce₂) │
│                                            │
│ → 每次登入的 nonce 不同，token 也不同！    │
│ → 舊的 token 無法重複使用                  │
└────────────────────────────────────────────┘
```

---

## Token 計算

### CRC32 雜湊函式

- **演算法**: CRC32（polynomial 0xEDB88320）
- **實作**: `src/common/proto.c:42-59`
- **特性**: 快速、簡單、**非加密等級**

```c
uint32_t ns_crc32(const void *data, size_t len) {
  uint32_t crc = 0xFFFFFFFFu;
  crc = crc32_update(crc, data, len);
  return ~crc;
}
```

### 為什麼用 CRC32 而非 SHA-256？

| 特性 | CRC32 | SHA-256 |
|------|-------|---------|
| **安全性** | ❌ 不抗碰撞 | ✅ 加密等級 |
| **速度** | ✅ 極快 | ⚠️ 較慢 |
| **實作複雜度** | ✅ 簡單 | ⚠️ 複雜 |
| **教學價值** | ✅ 易於理解 | ⚠️ 實作細節複雜 |
| **適用場景** | 教學演示 | 生產環境 |

**結論**: 本專案優先考慮**教學性與簡單性**，因此選擇 CRC32。

---

## XOR 加密演示（可選）

### XOR 加密函式

- **實作位置**: `src/common/proto.c:73-80`
- **Key**: `NS_XOR_KEY = 0xA5A5A5A5`

```c
void ns_xor_crypt(uint8_t *data, size_t len, uint32_t key) {
  if (!data || len == 0) return;
  uint8_t k[4];
  ns_put_be32(k, key);
  for (size_t i = 0; i < len; i++) {
    data[i] ^= k[i % 4];
  }
}
```

### 如何啟用加密？

在建立 frame 時設置 `NS_FLAG_ENCRYPTED` flag：

```c
// 客戶端發送加密訊息
uint8_t body[256];
// ... 填充 body ...

// 加密 body
ns_xor_crypt(body, body_len, NS_XOR_KEY);

// 建立 header (設置加密 flag)
ns_header_t hdr;
ns_build_header(&hdr, NS_FLAG_ENCRYPTED, OP_CHAT_SEND, 0, req_id, body, body_len);

// 發送...
```

### 伺服器端解密

```c
// src/server/worker.c:428-432
if (flags & NS_FLAG_ENCRYPTED) {
  ns_xor_crypt(rbuf + 32, body_len, NS_XOR_KEY);
  // 重新驗證 checksum
  if (!ns_validate_checksum(&hdr_be, rbuf + 32, body_len)) {
    // 解密失敗或 checksum 錯誤
    c->err_count++;
    continue;
  }
}
```

### XOR 加密的限制

⚠️ **警告**: XOR 加密**極度不安全**，僅供教學演示：

1. **Key 固定**: 使用硬編碼的 key，容易被逆向
2. **無 IV**: 相同明文產生相同密文
3. **易破解**: 已知明文攻擊可輕易破解
4. **無完整性保護**: 無法防止中間人修改

**生產環境請使用**: TLS 1.3、AES-GCM、ChaCha20-Poly1305 等。

---

## 安全性考量

### 本實作的安全特性

| 特性 | 實作狀態 | 說明 |
|------|----------|------|
| **防重放攻擊** | ✅ 部分支援 | Nonce 在伺服器重啟前保持不變，仍可能重放 |
| **完整性驗證** | ✅ 支援 | 使用 CRC32 checksum |
| **傳輸加密** | ⚠️ Demo only | XOR 加密不安全 |
| **密碼保護** | ❌ 未實作 | 無密碼欄位，僅驗證 username |
| **Session 管理** | ✅ 基本支援 | 登入後設置 `c->authed` flag |
| **Token 過期** | ❌ 未實作 | Token 無時間限制 |

### 生產環境改進建議

1. **使用 TLS/SSL**: 加密整個通訊層
2. **密碼雜湊**: 使用 bcrypt 或 Argon2 儲存密碼
3. **動態 Nonce**: 每次 HELLO 請求生成新的 nonce
4. **Token 過期**: 加入時間戳與 TTL
5. **Rate Limiting**: 防止暴力破解
6. **Audit Logging**: 記錄所有認證嘗試

---

## 程式碼實作

### 完整客戶端登入範例

```c
// src/client/interactive.c:228-277 (簡化版)

static int do_login(int fd, const char *username) {
  ns_header_t rh;
  uint8_t *rb = NULL;
  uint32_t rbl = 0;

  // Step 1: HELLO 握手
  uint64_t rid = ++g_req_id;
  if (send_and_wait(fd, OP_HELLO, rid, NULL, 0, &rh, &rb, &rbl) != 0) {
    printf("HELLO failed\n");
    return -1;
  }

  // Step 2: 解析 nonce
  if (ns_be16(&rh.status) != ST_OK || rbl != 8) {
    free(rb);
    printf("HELLO response invalid\n");
    return -1;
  }
  uint64_t nonce = ns_be64(rb);
  free(rb);

  // Step 3: 計算 token
  size_t ulen = strnlen(username, NS_MAX_USERNAME - 1);
  uint8_t tmp[NS_MAX_USERNAME + 8];
  memcpy(tmp, username, ulen);
  ns_put_be64(tmp + ulen, nonce);
  uint32_t token = ns_crc32(tmp, ulen + 8u);

  // Step 4: 構建 LOGIN body
  uint8_t body[2 + NS_MAX_USERNAME + 4];
  ns_put_be16(body, (uint16_t)ulen);
  memcpy(body + 2, username, ulen);
  ns_put_be32(body + 2 + ulen, token);

  // Step 5: 發送 LOGIN
  rid = ++g_req_id;
  if (send_and_wait(fd, OP_LOGIN, rid, body, 2u + ulen + 4u, &rh, &rb, &rbl) != 0) {
    printf("LOGIN failed\n");
    return -1;
  }

  // Step 6: 解析回應
  uint16_t st = ns_be16(&rh.status);
  if (st != ST_OK || rbl < 12) {
    free(rb);
    printf("LOGIN failed: status=%u\n", st);
    return -1;
  }

  g_user_id = ns_be32(rb);
  int64_t balance = (int64_t)ns_be64(rb + 4);
  free(rb);

  printf("Login successful! User ID: %u, Balance: %ld\n", g_user_id, balance);
  return 0;
}
```

### 完整伺服器驗證範例

```c
// src/server/worker.c:201-246 (簡化版)

case OP_LOGIN: {
  // 1. 解析 body
  bool ok = true;
  uint16_t ulen = rd_u16(body, body_len, 0, &ok);
  if (!ok || ulen == 0 || ulen >= NS_MAX_USERNAME) {
    send_simple_response(c, OP_LOGIN, ST_ERR_BAD_PACKET, req_id, NULL, 0);
    break;
  }

  const char *uname = (const char *)(body + 2);
  uint32_t token = rd_u32(body, body_len, 2u + ulen, &ok);
  if (!ok) {
    send_simple_response(c, OP_LOGIN, ST_ERR_BAD_PACKET, req_id, NULL, 0);
    break;
  }

  // 2. 驗證 token
  uint8_t tmp[NS_MAX_USERNAME + 8];
  memcpy(tmp, uname, ulen);
  ns_put_be64(tmp + ulen, shm->server_nonce);
  uint32_t want = ns_crc32(tmp, ulen + 8u);

  if (token != want) {
    send_simple_response(c, OP_LOGIN, ST_ERR_UNAUTHORIZED, req_id, NULL, 0);
    break;
  }

  // 3. 建立使用者 session
  uint32_t uid = 0;
  pthread_mutex_lock(&shm->user_mu);
  char ustr[NS_MAX_USERNAME];
  memset(ustr, 0, sizeof(ustr));
  memcpy(ustr, uname, ulen);
  int rc = ns_user_find_or_create(shm, ustr, &uid);
  pthread_mutex_unlock(&shm->user_mu);

  if (rc != 0) {
    send_simple_response(c, OP_LOGIN, ST_ERR_INTERNAL, req_id, NULL, 0);
    break;
  }

  c->authed = true;
  c->user_id = uid;

  // 4. 回應成功
  uint8_t resp[12];
  ns_put_be32(resp, uid);
  ns_put_be64(resp + 4, (uint64_t)shm->balance[uid]);
  send_simple_response(c, OP_LOGIN, ST_OK, req_id, resp, sizeof(resp));
  break;
}
```

---

## 時序圖

```
┌─────────┐                                          ┌─────────┐
│ Client  │                                          │ Server  │
└────┬────┘                                          └────┬────┘
     │                                                    │
     │  1. OP_HELLO (req_id=1)                           │
     │ ─────────────────────────────────────────────────>│
     │                                                    │
     │                                   讀取 shm->server_nonce
     │                                   (例如: 0x123...ABC)
     │                                                    │
     │  2. HELLO Response (nonce)                        │
     │ <─────────────────────────────────────────────────│
     │    Body: [ 0x01 0x23 ... 0xAB 0xCD ]              │
     │                                                    │
     │  計算 token:                                       │
     │  tmp = "alice" || 0x0123...ABCD                   │
     │  token = CRC32(tmp) = 0xDEADBEEF                  │
     │                                                    │
     │  3. OP_LOGIN (username="alice", token)            │
     │ ─────────────────────────────────────────────────>│
     │    Body: [ 0x00 0x05 'a''l''i''c''e'              │
     │            0xDE 0xAD 0xBE 0xEF ]                   │
     │                                                    │
     │                                   重新計算 token:
     │                                   tmp = "alice" || nonce
     │                                   want = CRC32(tmp)
     │                                   if (token == want) ✅
     │                                                    │
     │                                   建立 user session:
     │                                   user_id = 1
     │                                   balance = 0
     │                                                    │
     │  4. LOGIN Response (user_id, balance)             │
     │ <─────────────────────────────────────────────────│
     │    Status: ST_OK                                  │
     │    Body: [ 0x00 0x00 0x00 0x01  (user_id=1)       │
     │            0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 (balance=0) ]
     │                                                    │
     │  ✅ 認證成功，可以執行其他操作                     │
     │                                                    │
     │  5. OP_BALANCE (req_id=3)                         │
     │ ─────────────────────────────────────────────────>│
     │                                   檢查 c->authed ✅
     │                                   查詢餘額 = 0
     │  6. BALANCE Response                              │
     │ <─────────────────────────────────────────────────│
     │    Body: [ 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 ]
     │                                                    │
```

---

## 常見問題

### Q1: 為什麼伺服器的 nonce 不會每次 HELLO 都改變？

**A**: 為了簡化實作，本專案使用**全域共享的單一 nonce**（儲存在共享記憶體）。這種設計：

- ✅ **優點**: 實作簡單、所有 worker 共用
- ❌ **缺點**: 同一個 token 可以在伺服器重啟前重複使用
- 🎓 **教學價值**: 展示基本原理，但也暴露了安全缺陷

**生產環境改進**: 每次 HELLO 請求生成新的 per-session nonce，並記錄已使用的 token。

### Q2: CRC32 的碰撞風險有多大?

**A**: CRC32 有 2³² (約 43 億) 種可能值，碰撞機率：

- **理想情況** (生日悖論): 約 √(2³²) ≈ 65536 次嘗試後有 50% 碰撞機率
- **實際情況**: 攻擊者可以刻意構造碰撞

**結論**: CRC32 **不適合安全應用**，僅供教學演示。

### Q3: 如何防止暴力破解？

**A**: 本實作**未防護**暴力破解。生產環境改進：

1. **Rate Limiting**: 限制每 IP 的登入嘗試次數
2. **CAPTCHA**: 多次失敗後要求驗證碼
3. **Account Lockout**: 鎖定多次失敗的帳號
4. **Audit Logging**: 記錄所有登入嘗試

### Q4: 為什麼不實作密碼驗證？

**A**: 本專案聚焦於**協定設計與網路程式設計**，而非完整的帳號系統。加入密碼驗證需要：

- 密碼儲存 (bcrypt hash)
- 密碼重設流程
- Email 驗證
- ...（超出課程範圍）

**教學重點**: nonce-based challenge-response、token 驗證、協定狀態機。

### Q5: XOR 加密有什麼用？

**A**: XOR 加密在本專案中的用途：

1. **演示加密協定**: 展示如何在 frame 中加入加密 flag
2. **教學價值**: 理解對稱加密的基本概念
3. **整合測試**: 驗證 checksum 在加密後仍能正確計算

**實際應用**: 生產環境應使用 TLS 取代應用層加密。

### Q6: 如何測試認證功能？

**A**: 使用互動式客戶端：

```bash
# 1. 啟動伺服器
./bin/server --workers 2

# 2. 啟動客戶端
./bin/interactive --host 127.0.0.1 --port 9000

# 3. 登入測試
> login alice
Login successful! User ID: 1, Balance: 0

# 4. 嘗試未登入操作（會失敗）
> balance
Error: ST_ERR_UNAUTHORIZED
```

**單元測試** (可自行擴展):

```bash
# 測試協定編碼/解碼
make test_proto
./bin/test_proto

# 建議新增的測試:
# - test_auth_nonce: 測試 nonce 生成
# - test_auth_token: 測試 token 計算
# - test_auth_replay: 測試重放攻擊防護
```

---

## 參考資料

### 相關原始碼

- **協定定義**: `include/proto.h`
- **伺服器認證邏輯**: `src/server/worker.c:195-246`
- **客戶端登入流程**: `src/client/interactive.c:228-277`
- **CRC32 實作**: `src/common/proto.c:42-59`
- **XOR 加密實作**: `src/common/proto.c:73-80`
- **共享記憶體**: `src/server/shm_state.c`

### 延伸閱讀

- [Challenge-Response Authentication (Wikipedia)](https://en.wikipedia.org/wiki/Challenge%E2%80%93response_authentication)
- [CRC32 演算法](https://en.wikipedia.org/wiki/Cyclic_redundancy_check)
- [RFC 5869 - HMAC-based Key Derivation](https://tools.ietf.org/html/rfc5869)
- [OWASP Authentication Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html)

---

## 總結

本專案實作了一個**簡單但完整的 nonce + hash 認證機制**：

✅ **已實作**:
- HELLO/LOGIN 握手流程
- Server nonce 生成
- CRC32 token 驗證
- XOR 加密演示
- Session 狀態管理

⚠️ **教學限制**:
- CRC32 非加密等級雜湊
- Nonce 不隨 session 變化
- 無密碼保護
- XOR 加密不安全

🎓 **教學價值**:
- 理解 challenge-response 原理
- 學習網路協定狀態機設計
- 實作 client-server 認證流程
- 認識安全機制的基本概念

**適用場景**: 課程專案、技術演示、協定學習
**不適用**: 生產環境、真實應用、安全要求高的系統

---

*文件版本*: 1.0
*最後更新*: 2025-12-26
*作者*: NTUT Network Programming Course Team
