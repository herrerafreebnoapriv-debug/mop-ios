# 为什么「视频通话邀请」之前一直无法实现？

根本原因有多处，**缺一不可**，之前是多个问题叠加导致「对方收不到弹窗 + 聊天里没有带接受/拒绝的系统消息」。

---

## 1. 后端：`get_messages` 没有返回 `extra_data`（已修）

**位置**：`app/api/v1/chat.py` 里 `get_messages` 组装 `MessageResponse` 的循环。

**问题**：  
列表接口在构造每条消息时**没有把 `extra_data` 放进响应**。  
通话邀请的系统消息在库里是有 `extra_data = {'call_invitation': ...}` 的，但接口不返回，前端拿不到。

**后果**：  
- 对方**打开会话**时，是通过「拉历史消息」拿到消息列表的。  
- 历史里的系统消息没有 `extra_data`，前端 `_getCallInvitation(message)` 读不到 `call_invitation`。  
- 所以聊天记录里**要么不显示这条系统消息的按钮，要么整条展示异常**，看起来就像「聊天记录里没有带接受/拒绝的系统消息」。

**修复**：  
在 `get_messages` 的 `MessageResponse` 构造里加上：

```python
extra_data=getattr(msg, 'extra_data', None),
```

这样历史消息里也会带上通话邀请数据，前端的「接受/拒绝」按钮才能显示。

---

## 2. 后端：`target_user_id` 类型不一致，对方被当成「离线」（已修）

**位置**：`app/core/socketio.py` 的 `call_invitation` 处理。

**问题**：  
- Socket 收到的 `data['target_user_id']` 来自 JSON，可能是 **字符串**（如 `"7"`）。  
- `connected_users` 的 key 是 **int**（如 `7`）。  
- 判断用的是：`if target_user_id not in connected_users`。  
- 没有先把 `target_user_id` 转成 int，导致 `"7" not in {7: ...}` 永远为 True。

**后果**：  
- 对方明明在线，后端也认为「对方不在线」。  
- 只做「落库」，**不向对方推送** `message` 和 `call_invitation` 事件。  
- 对方收不到实时弹窗，也收不到实时进聊天列表的那条系统消息（只有之后拉历史时能看到，但当时历史又缺 `extra_data`，见上一条）。

**修复**：  
在用到 `target_user_id` 前统一转成 int，例如：

```python
try:
    target_user_id = int(raw_target)
except (TypeError, ValueError):
    ...
```

再用 `target_user_id` 查 `connected_users`、发 `user_{target_user_id}`。

---

## 3. 前端：弹窗被聊天页盖住（已修）

**位置**：`mobile/lib/screens/chat/chat_main_screen.dart` 里 `_CallInvitationListener` 的 `showDialog`。

**问题**：  
- 对方正在和发起人聊天（`ChatWindowScreen` 已 push）时，`showDialog(context, ...)` 用的是当前 Navigator 的 context。  
- 对话框会叠在**当前页面**的栈上，有可能被聊天页挡住或不在最前。

**后果**：  
- 即使后端正确推送了 `call_invitation`，对方也「看不到弹窗」或一点就没了，误以为没实现。

**修复**：  
使用根 Navigator 弹出对话框，保证在最顶层：

```dart
showDialog<String>(
  context: context,
  useRootNavigator: true,  // 关键
  ...
);
```

---

## 4. 前端：实时系统消息要明确按「系统消息」处理（已修）

**位置**：`mobile/lib/screens/chat/chat_window_screen.dart` 里 `onMessage` 的回调逻辑。

**问题**：  
- 原来只按「是否来自对方/发往对方」决定是否加入 `_messages`。  
- 系统消息的 `message_type == 'system'`，理论上也会满足条件，但在不同数据类型（int/string）或边界情况下，可能没被正确加入列表。

**修复**：  
对系统消息单独、明确处理：  
若 `message_type == 'system'` 且 `receiver_id == 当前用户`、`sender_id == 当前会话对方`，则把该条消息加入 `_messages`，并保证带 `call_invitation`/`extra_data`，这样列表里一定会出现带「接受/拒绝」的系统消息。

---

## 小结

| 问题 | 表现 | 修复 |
|------|------|------|
| 接口不返回 `extra_data` | 聊天记录里没有/没有按钮 | `get_messages` 里加上 `extra_data` |
| `target_user_id` 类型错误 | 对方在线也收不到实时推送 | 后端统一 `int(raw_target)` |
| 弹窗不在最前 | 对方「收不到弹窗」 | `showDialog(..., useRootNavigator: true)` |
| 实时系统消息未明确处理 | 实时那条也可能不显示/无按钮 | 单独分支处理 `message_type == 'system'` |

之前是**接口少字段 + 后端判在线错误 + 弹窗层级 + 前端对系统消息的处理**一起导致「发起视频通话 → 对方应收到弹窗 + 聊天记录里带接受/拒绝的系统消息」一直无法实现；这几处都修掉后，功能就按预期工作了。
