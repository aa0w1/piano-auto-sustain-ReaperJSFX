# Piano Auto Sustain (Reaper JSFX) — SDS

- 状态：**v1.1**（v1.0 双审核 FAIL：6 blocking + 14 important + 12 nit 全部采纳修复 → 待第二轮双审核）
- 上游：plan.md v0.5（定稿）。冲突时以 plan.md 为准并回改本文。

## 0. 本版设计裁决（SDS 审核引出，按推荐拍板，记录备查）

- **D1** slider 总数 16：12 参数 + 4 命令槽；**slider16 = C04_HoldOff（挂起标志就住在 slider 里）**——音频线程直写 0/1（不经 automate），UI 读它显示挂起态；@serialize 自动随工程保存（plan §4.2 N7 契约闭合）。
- **D2** 仲裁只在 M3 发生一次：`ped_active`（槽在途）→ 该音符事件的**所有**踩下/换踏请求吸收；M4 的 `ped_rep` 前置条件 = 槽 IDLE 且踏板在下，**不含退化分支**（plan §3.2.16①② 无二义）。
- **D3** 事件上下文显式传参：`(t_abs, ch, note)` 贯穿 M2→M3→M4；**槽新增 `ped_ch` 字段**，踩沿到期发往 `ped_ch`（plan §3.1 通道规则落地）。
- **D4** 通道记账 `st_ch_auto[16]` = 「发过自动 CC 的通道」（对齐 plan 收敛轮 N-2 口径）；合成值发送目标 = `st_ch_auto` 非空取之，否则取**当前事件通道**（堵住「首音符前硬件 CC 被吞」洞）；自动侧释放/重同步目标 = `st_ch_auto` 全部通道。
- **D5** `ped_tick` 块内排序：尾音到期与踩沿到期**谁早谁先**；尾音先到 → 取消槽内待踩沿（槽 IDLE）+ 发 CC0（plan 仲裁⑦落地；消除 tail 极小值下的幻影踩下）。
- **D6** 总开关沿检测在 @block：`st_prev_enabled` 影子变量，下降沿 → `st_reset(1)`；上升沿 → 强制重同步（plan §3.2.14）。
- **D7** 启动引导：`st_booted` 标志（经 @serialize 持久化）区分「首次加载」与「重播」——首次（=0）时置全部哨兵初值并置 1；重播时跳过（保运行态）。**@serialize 持久化集 = { st_booted, st_hw_cc, st_auto_cc, st_out_last }**（物理世界状态如按住表跨工程不持久，重载后由首块重同步对齐）；其余运行态靠非空 @serialize 的「免清零」跨播放启动存续。
- **D8** 重同步强制发送：`st_out_last = -1` 哨兵后调 `io_send_synth`（绕过「值未变不发」守卫，plan N2 落地）；`st_first_block` 处理后无论开关状态一律清零。
- **D9** slider11 通道作用域编码：0=全部、1–16=通道（判定 `scope==0 || ch==scope-1`，ch 为 0 基）；slider12 枚举写法 `slider12:0<0,2,1>{64,66,67}-P12_CCTarget`，底层 0..2，映射表 `cc_map[3]={64,66,67}`。
- **D10** 数组基址登记表制度（T1 产出、随任务更新）；审核工具化：标识符定义/引用 grep 差集 + 禁词扫描（T2/T7 验收）；**时间戳变量禁 `|0`**（保双精度，防 12.4h 溢出），仅普通下标取整。
- **D11** 全序实施：T1→T2→T3→T4→T5→T7 严格串行（单文件无合并协议）；仅 T6（文档，独立文件）与 T2 起并行。
- **D12** 踩沿时刻钳制：`down_at = t_abs + gap_smp + max(hum_smp + jitter, 0)`，恒 ≥ 抬沿+gap（plan §3.2.8 不变式）。
- **D13** 恢复默认走命令槽统一协议（音频线程消费 → `cfg_restore_defaults()`）；若 `slider_automate` 在 @block 内行为异常，降级为只写值+`cfg_sync_from_sliders()`（自动化记录为 nice-to-have）。

---

## 1. 模块划分与职责边界

单文件 `src/PianoAutoSustain.jsfx`（预估 1500–2500 行）。模块 = 代码分区 + 前缀纪律（全部函数定义在 @init 内；禁递归；共享数据走全局/数组；`local()` 跨 section 各持独立状态——共享状态禁止依赖 local）。

| 模块 | 前缀 | 职责 | 不负责 | 行数预算 |
|---|---|---|---|---|
| M1 参数管线 | `cfg_` | 16 slider 声明、slider→内部同步、程序化写参、恢复默认 | 业务判断 | ≤120 |
| M2 MIDI I/O | `io_` | @block 主循环（含开关沿、命令槽消费、重同步）、midirecv 分类、vel0 归一、作用域过滤、目标 CC 拦截与合成、沿输出出口 `io_send_cc_raw` | 踩放时机决策 | ≤180 |
| M3 状态机 | `st_` | 按住表/低音 pc/重复音判定、新音级判定、挂起与解除、独占请求链、软复位 | 生成 MIDI（复位释放经 `io_send_cc_raw` 委托） | ≤200 |
| M4 踏板调度 | `ped_` | 单槽（含 ped_ch/ped_kind）、gap/humanize/LFSR、限流窗、块内到期仲裁（D5）、尾音计时推进 | 音符语义 | ≤150 |
| M5 诊断 | `diag_` | 数值环形事件日志（含指派调用点）、计数器 | 字符串 | ≤90 |
| M6 UI | `ui_` | @gfx 全定制四页、hit-test（每帧重建）、控件库、踏板动画、拉伸布局（坐标全部由 gfx_w/gfx_h 派生） | 直改业务状态（一律经 cfg_/命令槽） | ≤900 |

## 2. 数据模型与状态流转

### 2.1 时基

- `st_abs_smp`：绝对采样时钟，每 @block `st_abs_smp += samplesblock`；块起点 `block_start = st_abs_smp - samplesblock`。事件绝对时刻 `t_abs = block_start + off`。
- ms→采样：`ms * srate * 0.001`。时间戳保双精度、禁 `|0`（D10）。

### 2.2 配置（M1 同步，引擎只读）

```
slider1..12 → cfg_enabled, cfg_bass_ceil, cfg_tail_ms, cfg_chord, cfg_ign_oct,
              cfg_gap_ms, cfg_hum_ms, cfg_bass_win_ms, cfg_rep_win_ms, cfg_repeat_on,
              cfg_scope, cfg_cc(经 cc_map[3] 映射，D9)
派生: cfg_tail_smp, cfg_gap_smp, cfg_hum_smp, cfg_bass_win_smp, cfg_rep_win_smp
slider13..15 = C01_TapRep / C02_Release / C03_RestoreDefaults（命令槽，0/1）
slider16     = C04_HoldOff（挂起标志，音频直写，UI 只读）
```

### 2.3 运行态

```
// 持久化（@serialize file_var，D7）
st_booted, st_hw_cc, st_auto_cc, st_out_last
// 非持久（跨播放启动靠 @serialize 免清零存续；首次加载由 st_booted 引导置哨兵）
st_note_cnt@0[128]    按住计数（作用域内合并——plan §3.1 已知限制）
st_bass_pc@128[12]    低音按住音级计数
st_ch_auto@140[16]    发过自动 CC 的通道（D4）
st_held_total, st_last_note(-1 哨兵), st_tail_end(-1 未计时),
st_prev_enabled, st_first_block, st_evt_seq,
ped_active, ped_down_at, ped_ch, ped_kind, win_bass_end, win_rep_end
// 非持久不序列化
diag_*（环形缓冲 + 计数器）, ui_*（@gfx 线程；标量竞态容忍，plan P7/N8）
```

数组基址登记表（D10，T1 建立并随任务更新）：`st_note_cnt@0[128]、st_bass_pc@128[12]、st_ch_auto@140[16]、音名表@256[128*2]、ui_hit@2048[...]`；新增数组必须登记。

### 2.4 状态流转

**@block 序列**（io_process_block）：
```
1. st_abs_smp += samplesblock
2. 开关沿检测（D6）：cfg_enabled 下降沿→st_reset(1)；上升沿→st_out_last=-1 + io_send_synth(0, fallback=首个 st_ch_auto)
3. st_first_block：置位时若 cfg_enabled → st_out_last=-1 + io_send_synth(0, fallback)；然后一律清零（D8）
4. 命令槽消费：C01→cmd_tap / C02→cmd_release / C03→cmd_restore（消费后直写 0，§2.5）
5. ped_tick：块内排序（D5）——尾音到期(offset A)与踩沿到期(offset B)比较，早者先：
   尾音先到 → 槽取消（IDLE）+ 对 st_ch_auto 逐通道 io_send_cc_raw(A, ch, 0) + st_tail_end=-1
   踩沿先到 → io_send_cc_raw(B, ped_ch, 127) + 槽 IDLE（经 io_send_cc_raw 统一记账，修复审核A N2）
6. midirecv 循环 → io_dispatch（取全发全；SysEx 由宿主自动直通）
7. diag_snapshot()
```

**io_dispatch(off, msg1, msg2, msg3)**：
```
ch = msg1 & 0x0F；t_abs = block_start + off
0x9X: vel>0 → st_on_note_on(t_abs, ch, note, vel)；vel==0 → st_on_note_off（直通）
0x8X → st_on_note_off（直通）
0xBX: cc==cfg_cc && 在作用域 → st_hw_cc=val; diag_log(3,ch,val); io_send_synth(off, ch)；拦截不直通
      cc==120||123 → st_reset(2) + 直通
      其余 → 直通
其他消息 → 直通
作用域过滤只作用于「参与状态机的音符事件」与「目标 CC 拦截」；范围外全直通
```

**st_on_note_on(t_abs, ch, note)**（取旧值判定 → 更新 → 独占请求链，修复审核A I8）：
```
若 slider16(hold)==1 → 直写 slider16=0（解除挂起，然后正常处理）
repeat      = (note == st_last_note)                 // 取旧 st_last_note
new_bass_pc = is_bass(note) && ( cfg_ign_oct ? st_bass_pc[pc]==0
                                             : (st_bass_pc[pc]==0 || st_note_cnt[note]==0) )
st_last_note = note；st_note_cnt[note]++；st_held_total++
if is_bass：st_bass_pc[pc]++；st_ch_auto 记账在此不发生（由 io_send_cc_raw 记）
st_tail_end = -1（新音取消尾音）
独占链（互斥，命中即止）：
  ① ped_active==1 → 吸收（D2，含换踏与普通踩下）
  ② cfg_chord && cfg_repeat_on && repeat        → st_request_rep(t_abs, ch, note, 重复音窗)
     （双命中时低音路径整体丢弃，plan §3.2.9；非「无窗请求」）
  ③ cfg_chord && new_bass_pc                    → st_request_rep(t_abs, ch, note, 低音窗)
  ④ st_auto_cc==0                               → ped_press(t_abs, ch, note)
```

**st_request_rep(t_abs, ch, note, kind)**：`now < win_end(kind)` → 吸收；否则 `ped_rep(t_abs, ch, note, kind)`。

**ped_rep(t_abs, ch, note, kind)**（前置：槽 IDLE 且 st_auto_cc==127，由调用链保证）：
```
io_send_cc_raw(t_abs, ch, 0)                    // 抬沿，立即
jitter = ped_jitter(note)；down_at = t_abs + cfg_gap_smp + max(cfg_hum_smp + jitter, 0)  // D12
槽 = { active:1, down_at, ch, kind }；win_end(kind) = t_abs + 对应窗
```

**ped_press(t_abs, ch, note)**：`down_at = t_abs + max(cfg_hum_smp + jitter, 0)`；槽 = {active:1, down_at, ch, kind:0}。

**st_on_note_off(t_abs, ch, note)**：`st_note_cnt[note]>0` 才递减（未知 Note Off 忽略）；低音则 `st_bass_pc[pc]--`；`st_held_total==0 && slider16==0` → `st_tail_end = t_abs + cfg_tail_smp`（挂起期间不启动尾音，修复审核A I4）。

**io_send_cc_raw(off, ch, val)**（唯一沿输出口）：`midisend(off, 0xB0|ch, cfg_cc, val)`；`val==127→st_auto_cc=127；val==0→st_auto_cc=0`；`st_out_last=val`；`st_ch_auto[ch]=1`；diag_log(0/1/2, ch, val)。

**io_send_synth(off, fallback_ch)**：`eff = max(st_hw_cc, st_auto_cc)`；目标 = st_ch_auto 非空 ? 全部 : {fallback_ch}；逐通道 midisend（eff==st_out_last 时跳过——重同步路径先用 st_out_last=-1 破守卫，D8）。

**st_reset(reason)**：槽取消；`st_auto_cc==127` → 对 st_ch_auto 逐通道 io_send_cc_raw(0, ch, 0)；清 note_cnt/bass_pc/held_total/last_note/tail_end/两窗；直写 slider16=0；diag_log(4, reason, 0)。（CC123 后 held_total==0 且 hold==0 → 尾音计时自然启动：由下一次 Note Off…**修正：st_reset 内直接置 `st_tail_end = st_abs_smp + cfg_tail_smp`**（自愈，plan §3.2.15）。）

**命令槽处理（§2.5）**：
```
cmd_tap（C01，plan §3.2.11/§3.2.16⑤⑥）：直写 slider16=0（任何情况解除挂起）
  ped_active → 吸收
  st_auto_cc==127 → io_send_cc_raw(t_abs, ch=st_ch_auto 首个或 fallback 1, 0) + 槽={down_at=t_abs+gap+hum钳制, ch, kind:2}（不开窗）
  否则 → ped_press
  完成后若 st_held_total==0 → st_tail_end = t_abs + cfg_tail_smp（⑥）
cmd_release（C02，plan §3.2.12）：槽取消；st_auto_cc==127 → 对 st_ch_auto 逐通道 io_send_cc_raw(0)；st_tail_end=-1；直写 slider16=1
cmd_restore（C03，D13）：cfg_restore_defaults()
```

**消费沿规则**（可行性审核 I7）：命令槽按 **0→非0 上升沿**消费（音频线程记 `slot_prev` 影子），防连续 CC 重放；消费后直写 0。挂起标志 slider16 为电平语义（1=挂起），UI 与诊断直读。

### 2.5 诊断事件指派（修复审核A N4）

`diag_log(type,a,b)` 调用点：0=自动踩沿（io_send_cc_raw val=127）、1=自动抬沿（val=0）、2=换踏（ped_rep）、3=硬件目标 CC 变化（io_cc_target）、4=复位（st_reset，reason=a）、5=挂起变化（slider16 写点）。快照（每块末）＝三真值（hw/auto/合成）、st_held_total、st_bass_pc 12 项、发送计数（修复 N3）。

## 3. 接口（函数签名级，全部定义于 @init）

```
// M1
cfg_sync_from_sliders()            slider1..12 → cfg_* + 派生
cfg_set_param(idx, val)            if链写 sliderN（EEL2 无 slider[idx]）+ slider_automate + cfg_sync
cfg_restore_defaults()             12 参数回默认（+slider_automate；D13 降级路径）
// M2
io_process_block()                 §2.4 序列
io_dispatch(off, msg1, msg2, msg3)
io_cc_target→并入 io_dispatch      st_hw_cc 更新 + diag_log(3) + io_send_synth
io_send_synth(off, fallback_ch)
io_send_cc_raw(off, ch, val)
// M3
st_on_note_on(t_abs, ch, note)
st_on_note_off(t_abs, ch, note)
st_request_rep(t_abs, ch, note, kind)
st_reset(reason)
// M4
ped_rep(t_abs, ch, note, kind)
ped_press(t_abs, ch, note)
ped_tick(block_start, n)           D5 块内排序 + 槽到期（offset=down_at-block_start，clamp 防御）
ped_jitter(note)                   LFSR（种子=note+st_evt_seq，每生成事件推进 st_evt_seq）→ ±2ms 采样数
// M5
diag_log(type, a, b)
diag_snapshot()
// M6（@gfx）
ui_draw()                          首帧初始化（页=0、hit 基址、连发计时）+ ui_handle_mouse + 分页
ui_widget_btn(id,x,y,w,h,label) / ui_widget_toggle / ui_widget_stepper   绘制+登记 hit（坐标全由 gfx_w/gfx_h 派生）
ui_page_perf() / ui_page_adv() / ui_page_diag() / ui_page_manual()
ui_draw_pedal(state)
```

## 4. 文件结构

```
src/PianoAutoSustain.jsfx   header（desc/in_pin/out_pin/options:gfx_hz=60/16 slider，默认值在头部）
                            @init（常量+音名表+全部函数）→ @serialize（持久化集，~10 行）→
                            @slider（cfg_sync）→ @block（io_process_block）→ @gfx（ui_draw）
docs/使用说明.md  docs/首载检查单.md  tests/测试清单.md  tests/T2语义对照.md（T2 审核工件）
```

## 5. 任务拆分表

实施约定（D11）：**T1→T2→T3→T4→T5→T7 严格串行**（单文件，无并行无合并协议）；T6 文档自 T2 起并行。每任务「写码子agent → 对抗审核子agent → 仲裁 → git commit」。审核工具化（D10）：`grep -oE '\b(cfg|st|ped|io|diag|ui)_[A-Za-z0-9_]+' src/PianoAutoSustain.jsfx | sort -u` 比对定义/引用差集为空；禁词扫描 `length`（标识符）、函数自调用（递归）、命令槽外裸写 `slider1[3-6]=`、时间戳 `|0` 命中清单为空。

| # | 目标 | 产出 | 验收标准（可执行检查） | 依赖 |
|---|---|---|---|---|
| T1 | 骨架+参数管线+数组基址表 | header、@init 常量/音名表/基址表、M1 函数、四 section 骨架、@serialize | ① slider 恰 16 个：顺序/默认/范围=plan §4.2（slider11/12 按 D9 原文）；② @init 无 slider 赋值、无运行态清零（st_booted 引导除外）；③ @serialize 含持久化集 4 项（D7）；④ cfg_sync 覆盖 12 参数+5 派生；⑤ in_pin/out_pin:none、gfx_hz=60；⑥ 基址登记表建立且无重叠；⑦ 音名表 59→B3 | — |
| T2 | 引擎 M2+M3+M4 | io_/st_/ped_ 全部函数 + @block 接线 + **tests/T2语义对照.md**（plan §3.2.1–3.2.16 逐条→代码位置对照表） | ① 对照表 16 条全命中；② §2.4 序列与 io_dispatch 分类正确（取全发全、拦截仅作用域内目标 CC、vel0 归一）；③ 独占链四条+双命中丢弃+槽占用吸收（D2）代码级核对；④ D5 块内排序+⑦取消路径存在；⑤ grep 差集为空+禁词清单为空；⑥ 无递归；⑦ LFSR 种子=note+事件序号、D12 钳制 | T1 |
| T3 | 诊断+命令槽 | M5 全部 + §2.5 事件指派 + 命令槽消费三函数 + 上升沿消费 | ① 环形缓冲纯数值；② 三命令槽接通（§2.5 流转逐条）；③ 快照含三真值/held/bass_pc12/计数；④ 新增运行态已列入 @serialize（本任务无新增则声明） | T2 |
| T4 | UI 框架+演奏页 | ui_ 框架 + 演奏页 | ① hit-test 每帧重建、首帧初始化；② 坐标全由 gfx_w/gfx_h 派生（380×460 与 2× 放大两档比对）；③ 参数全走 cfg_set_param（grep 裸 slider 赋值仅命令槽）；④ 踏板两态动画、两大参数卡（加减/连发/音名）、两开关、三按钮（写命令槽）、状态行=plan §4.3 | T3 |
| T5 | 高级/诊断/说明书页 | 三页 | ① 高级页 7 控件对齐 plan §4.2（简单模式下重复音灰置：读 cfg_chord）；② 诊断页读快照；③ 说明书页=安装一句话+5 要点+指向 docs；④ M6 行数 ≤900 | T4 |
| T6 | 文档 | docs/使用说明.md、docs/首载检查单.md、tests/测试清单.md | ① 使用说明覆盖 plan §4.3 五要点+§4.4 版本差异+§4.5 烘焙（Input FX 法）+低音锚定解释与三缓解+回放已烘焙关总开关；② 首载检查单 5 分钟可走完；③ 测试清单=plan §7 18 场景可勾选；④ **MIDI learn 绑法经官方文档核验后落笔**（含命令槽上升沿消费说明） | plan 定稿（并行） |
| T7 | 集成终审 | 终版 jsfx + 交付总结 | ① 独立审核全文通读：前缀纪律、递归、local() 跨 section、未定义变量（grep 差集）、slider16 对齐、midirecv 消费、@gfx 协议、基址表一致性；② §3.2.16 七条仲裁+D2/D5 抽查代码级；③ git log 一任务一 commit；④ 交付总结 | T1–T6 |

## 6. 验证与交付

- 本机无 REAPER 编译环境：验收=「审核 agent 对照 + grep 工具化检查 + 静态清单」（plan §5 已声明）；用户首载按 docs/首载检查单.md。
- 全部任务通过后：git log 核对 + 交付总结（做了什么/验证了什么/遗留什么/用户实测步骤）。
