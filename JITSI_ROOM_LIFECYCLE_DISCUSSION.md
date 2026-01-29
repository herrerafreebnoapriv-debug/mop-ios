# Jitsi 房间生命周期讨论

**讨论时间**: 2026-01-24  
**核心问题**: A 和 B 结束通话后，短时间内 A 向 C 发起通话，是否会进入原先的 A-B 房间？

---

## 一、当前房间 ID 生成逻辑

### 1.1 1对1通话的房间ID生成

**代码位置**: `static/chat-calls.js` (第 46-50 行)

```javascript
const userId1 = user.id;        // 发起方ID（例如：用户2）
const userId2 = currentChat.id; // 对方ID（例如：用户6）
const sortedIds = [userId1, userId2].sort((a, b) => a - b);
const hash = await this.sha256Hash(`chat-${sortedIds[0]}-${sortedIds[1]}`);
roomId = `r-${hash.substring(0, 8)}`;
```

**特点**:
- ✅ **确定性**：相同用户对总是生成相同的房间ID（因为排序后顺序固定）
- ✅ **唯一性**：不同用户对生成不同的房间ID
- ✅ **可预测**：A(2) 和 B(6) → `chat-2-6` → 固定 hash → `r-xxxxyyyy`
- ✅ **A(2) 和 C(8) → `chat-2-8` → 不同的 hash → `r-zzzzaaaa`**

### 1.2 场景分析

| 场景 | 用户对 | 房间ID生成 | 结果 |
|------|--------|-----------|------|
| A(2) ↔ B(6) | [2, 6] | `hash('chat-2-6')` → `r-xxxxyyyy` | 房间ID: `r-xxxxyyyy` |
| A(2) ↔ C(8) | [2, 8] | `hash('chat-2-8')` → `r-zzzzaaaa` | 房间ID: `r-zzzzaaaa` |

**结论**: ✅ **不会进入原先的房间**，因为房间ID不同。

---

## 二、Jitsi 房间生命周期

### 2.1 Jitsi 房间的自动清理机制

**Jitsi Meet 的行为**:
- **房间存在条件**: 只要房间内有至少 1 个参与者，房间就会一直存在
- **房间清理时机**: 当**所有参与者都离开**后，Jitsi 会在**几分钟内**（通常 2-5 分钟）自动清理房间
- **清理后的行为**: 房间被销毁，但房间ID仍然可以重新使用（Jitsi 会创建新房间）

### 2.2 潜在问题场景

#### 场景 1: 正常情况 ✅
```
时间线:
T1: A 和 B 开始通话 → 房间 r-xxxxyyyy 创建
T2: A 和 B 结束通话，双方都离开 → 房间 r-xxxxyyyy 开始清理倒计时
T3: (2分钟后) 房间 r-xxxxyyyy 被 Jitsi 自动清理
T4: A 向 C 发起通话 → 房间 r-zzzzaaaa 创建（不同的房间ID）
```
**结果**: ✅ 不会进入原先的房间

#### 场景 2: 一方未完全离开 ⚠️
```
时间线:
T1: A 和 B 开始通话 → 房间 r-xxxxyyyy 创建
T2: A 关闭窗口，但 B 还在房间（网络延迟/未点击离开）
T3: A 向 C 发起通话 → 房间 r-zzzzaaaa 创建
T4: B 仍在房间 r-xxxxyyyy 中（等待超时或手动离开）
```
**结果**: ✅ A 进入新房间，B 仍在旧房间（符合预期）

#### 场景 3: 极短时间内重新发起 ⚠️
```
时间线:
T1: A 和 B 开始通话 → 房间 r-xxxxyyyy 创建
T2: A 和 B 结束通话，双方都离开
T3: (10秒后) A 向 C 发起通话 → 房间 r-zzzzaaaa 创建
```
**结果**: ✅ 不会进入原先的房间（房间ID不同）

#### 场景 4: 同一用户对重复通话 ✅
```
时间线:
T1: A 和 B 开始通话 → 房间 r-xxxxyyyy 创建
T2: A 和 B 结束通话，双方都离开
T3: (1分钟后) A 再次向 B 发起通话 → 房间 r-xxxxyyyy（相同房间ID）
T4: 如果房间已被清理 → Jitsi 创建新房间 r-xxxxyyyy
T5: 如果房间未清理（仍在倒计时）→ 可能进入空房间或创建新房间
```
**结果**: ⚠️ **可能进入空房间**（如果房间还未被清理）

---

## 三、问题分析

### 3.1 当前实现的优点

1. ✅ **不同用户对不会冲突**：A-B 和 A-C 的房间ID不同
2. ✅ **确定性**：相同用户对总是使用相同的房间ID（便于复用）
3. ✅ **简单**：无需后端存储房间状态

### 3.2 当前实现的问题

1. ⚠️ **同一用户对重复通话**：如果房间还未被清理，可能进入空房间
2. ⚠️ **无法强制清理房间**：后端无法主动通知 Jitsi 清理房间
3. ⚠️ **房间状态未知**：不知道房间是否还有人在，是否已被清理

---

## 四、解决方案讨论

### 方案 1: 添加时间戳到房间ID（推荐）✅

**思路**: 每次发起通话时，在房间ID中加入时间戳，确保每次都是新房间

```javascript
// 修改前
const hash = await this.sha256Hash(`chat-${sortedIds[0]}-${sortedIds[1]}`);
roomId = `r-${hash.substring(0, 8)}`;

// 修改后
const timestamp = Math.floor(Date.now() / 1000); // 秒级时间戳
const hash = await this.sha256Hash(`chat-${sortedIds[0]}-${sortedIds[1]}-${timestamp}`);
roomId = `r-${hash.substring(0, 8)}`;
```

**优点**:
- ✅ 每次通话都是新房间，避免进入旧房间
- ✅ 实现简单，无需后端改动

**缺点**:
- ❌ 无法复用房间（如果用户想重新加入之前的通话）
- ❌ 房间ID不可预测（但这不是问题）

### 方案 2: 添加会话ID（UUID）到房间ID ✅

**思路**: 每次发起通话时生成唯一的会话ID

```javascript
// 生成唯一会话ID
const sessionId = crypto.randomUUID();
const hash = await this.sha256Hash(`chat-${sortedIds[0]}-${sortedIds[1]}-${sessionId}`);
roomId = `r-${hash.substring(0, 8)}`;
```

**优点**:
- ✅ 每次通话都是新房间
- ✅ 更安全（不可预测）

**缺点**:
- ❌ 无法复用房间

### 方案 3: 检查房间状态（复杂）⚠️

**思路**: 加入房间前，先检查房间是否还有人在

**实现**:
- 后端维护房间状态（Redis 或数据库）
- 加入房间时检查房间是否活跃
- 如果房间已空且超过清理时间，使用新房间ID

**优点**:
- ✅ 可以复用活跃房间
- ✅ 精确控制房间生命周期

**缺点**:
- ❌ 实现复杂，需要后端状态管理
- ❌ 需要与 Jitsi 同步状态（困难）

### 方案 4: 混合方案（推荐）✅

**思路**: 结合时间戳和用户对，但使用较粗的时间粒度（例如：每小时）

```javascript
// 使用小时级时间戳，同一小时内同一用户对使用相同房间ID
const hourTimestamp = Math.floor(Date.now() / (1000 * 60 * 60)); // 小时级
const hash = await this.sha256Hash(`chat-${sortedIds[0]}-${sortedIds[1]}-${hourTimestamp}`);
roomId = `r-${hash.substring(0, 8)}`;
```

**优点**:
- ✅ 同一小时内可以复用房间（如果用户想重新加入）
- ✅ 不同小时使用不同房间，避免进入旧房间
- ✅ 实现简单

**缺点**:
- ⚠️ 如果通话跨小时，房间ID会变化（但通常不是问题）

---

## 五、推荐方案

### 推荐：方案 1（时间戳）或 方案 4（小时级时间戳）

**理由**:
1. **简单可靠**：实现简单，无需后端改动
2. **避免冲突**：确保每次通话都是新房间（或新时间段）
3. **符合场景**：1对1通话通常不需要复用旧房间

### 实现建议

**方案 1（秒级时间戳）** - 适合：每次通话都必须是新房间
```javascript
const timestamp = Math.floor(Date.now() / 1000);
const hash = await this.sha256Hash(`chat-${sortedIds[0]}-${sortedIds[1]}-${timestamp}`);
roomId = `r-${hash.substring(0, 8)}`;
```

**方案 4（小时级时间戳）** - 适合：允许短时间内的房间复用
```javascript
const hourTimestamp = Math.floor(Date.now() / (1000 * 60 * 60));
const hash = await this.sha256Hash(`chat-${sortedIds[0]}-${sortedIds[1]}-${hourTimestamp}`);
roomId = `r-${hash.substring(0, 8)}`;
```

---

## 六、其他考虑

### 6.1 群聊房间

当前代码中，群聊房间使用：
```javascript
const hash = await this.sha256Hash(`room-${currentChat.id}`);
roomId = `r-${hash.substring(0, 8)}`;
```

**建议**: 群聊房间可以保持固定ID（因为群聊通常需要长期存在）

### 6.2 JWT Token 过期时间

当前 JWT Token 的过期时间（`create_jitsi_token`）需要与房间生命周期匹配：
- 如果使用时间戳方案，JWT 过期时间应该足够长（例如：1小时）
- 确保用户在通话期间 Token 不会过期

### 6.3 房间清理通知

**可选功能**: 当用户离开房间时，通知后端更新房间状态（如果采用方案3）

---

## 七、总结

### 当前问题
- ✅ **A 向 C 发起通话不会进入 A-B 房间**（房间ID不同）
- ⚠️ **A 再次向 B 发起通话可能进入旧房间**（如果房间还未被清理）

### 推荐修改
**采用方案 1（秒级时间戳）**，确保每次通话都是新房间，避免进入旧房间的风险。

---

## 八、实施决策

**决策时间**: 2026-01-24  
**选择方案**: **方案 1（秒级时间戳）**  
**实施状态**: ✅ **已实施**

### 实施内容

修改 `static/chat-calls.js` 中的房间ID生成逻辑：

```javascript
// 1对1通话：每次通话都是新房间（添加秒级时间戳）
const userId1 = user.id;
const userId2 = currentChat.id;
const sortedIds = [userId1, userId2].sort((a, b) => a - b);
// 添加秒级时间戳，确保每次通话都是新房间
const timestamp = Math.floor(Date.now() / 1000);
const hash = await this.sha256Hash(`chat-${sortedIds[0]}-${sortedIds[1]}-${timestamp}`);
roomId = `r-${hash.substring(0, 8)}`;
```

**效果**:
- ✅ 每次发起1对1通话都会生成新的房间ID
- ✅ 避免进入旧房间的风险
- ✅ 群聊房间保持固定ID（符合群聊长期存在的需求）

---

*实施完成时间: 2026-01-24*
