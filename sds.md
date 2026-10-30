# Piano Auto Sustain (Reaper JSFX) — SDS

- 状态：**v1.3 定稿**（第三轮双审核 blocking/important/nit 全部采纳修复；SOP 3 轮上限已到，剩余发现均为已给修法的内部一致性项，按用户预授权采纳；关卡2 通过，2026-10-31）→ 进入阶段3 实施
- 上游：plan.md v0.5（定稿）。冲突时以 plan.md 为准并回改本文。

## 官方文档核实基线（第三轮修订）

- @init 于加载/采样率变化/每次播放启动执行；**恢复流中 @init 有时后于 @serialize 执行**（js.php 原文："sometimes @init will be called following @serialize"）→ 任何依赖「@init 先读零」的设计不可靠，本版不依赖（D7 v1.3）。
- 非空 @serialize 阻止变量清零；@slider "following an @init" 必随 @init 再跑（D23 双保险成立）。
- midirecv "will automatically passthrough any SysEx events"——dispatch 永不见 0xF0（N-6 销闭）。
- `-` 前缀隐藏 slider；samplesblock；slider_automate 各 section 合法、sliderchange(-1) 仅 @gfx 出 undo 点；midirecv 取全发全；midisend offset 越界未定义 → 恒守 [0, samplesblock)。

## 0. 设计裁决（D1–D25）

- **D1** slider 总数 16：12 参数 + 4 命令槽；slider16 = C04_HoldOff（挂起电平住 slider，音频直写，UI 只读；重载首块清 0，见 D7）。
- **D2** 仲裁只在 M3 一次：`ped_active` → 事件全部请求吸收；`ped_rep` 前置 = 槽 IDLE 且 st_auto_cc==127（D15 闸）。plan §3.2.16②「覆盖槽中旧踩沿」在①下不可达（死文本，plan 保留、本文不实现）。
- **D3** 事件上下文 `(t_abs, ch, note)` 贯穿；槽含 ped_ch。
- **D4** `st_ch_auto[16]` = 发过自动 CC 的通道；`io_send_synth` 目标 = st_ch_auto ∪ {事件通道或 fallback 索引 0}；自动侧释放/重同步目标 = st_ch_auto 全部（空 → 索引 0）。
- **D5+D16** 块内时序：**midirecv 先于 ped_tick**（同块音符可取消未到期尾音，符合 plan §3.2.6）；到期按**绝对时刻**；过期 clamp [block_start, block_start+n)；**≥ 块末顺延下块**（上界含等号，修复 I-5）；平局尾音先。
- **D6** 开关沿检测 `st_prev_enabled`，**每块末尾无条件同步**（X4）。
- **D7 v1.3（时序无关化）** `@serialize` = 非空占位（一条赋值语句），**不持久化任何变量**；用户参数持久化由 slider 自动保存承担；**st_booted 为运行态门控，在 @block 首块安装哨兵**（对 @init/@serialize 任何次序稳健）；重载 = 全零 + 首块哨兵（含直写 slider16=0）+ 重同步补发 → 释放态起步（§7.12）；停止→播放 = 状态存续 + `st_resync_pending`（@init 置 1）→ 首个启用块强制补发合成值（§7.16，修复 X1）。
- **D8** 重同步破守卫：全部 `st_out_last[ch] = -1` 后调 io_send_synth。
- **D9 v1.3.2 勘误** slider11：0=全部/1–16=通道；slider12：`slider12:0<0,2,1{64,66,67}>-P12_CCTarget`（枚举在尖括号**内**——官方 js.php 原文形式，T1 审核裁定；原写法为笔误），`cc_map[3]={64,66,67}`。
- **D10** 基址登记表（设计伪记法，落地基址常量）；grep 判据改**调用形**（I-4）；`|0` 操作定义：仅允许数组下标 `[…|0]`，时间戳/采样计数语境违规。
- **D11** 全序 T1→T2→T3→T4→T5→T7；T6 并行。
- **D12** `down_at = t_abs + gap_smp + max(hum_smp + jitter, 0)`。
- **D13** 恢复默认走 C03；@gfx 点击时先 `sliderchange(-1)`（undo 点）再写 C03；音频线程消费时写值 + `cfg_sync_from_sliders()` + `slider_automate`（@block 合法；异常则降级只写值+sync）。
- **D14 v1.3** 关态门控：`!cfg_enabled` → 直通循环 + **目标 CC 仅跟踪 st_hw_cc=val（不拦截不合成，diag_log(3)）**（修复 X2/I-2 幻象延音）+ 快照；命令槽/状态机/ped_tick 全跳过。
- **D15** 独占链②③加 `st_auto_cc==127` 闸。
- **D17** 无事件调度点 `t_abs = block_start`；fallback 通道 = 索引 0。
- **D18** kind：0=普通踩沿、1=换踏-低音窗、2=换踏-重复音窗、3=换踏-按钮（不开窗）；`win_lookup(3)`→无。
- **D19** 命令槽影子 `slot_prev[3]`（独立上升沿）。
- **D20 v1.3** 诊断 type：0/1=踩/抬沿（io_send_cc_raw 按**意图值**记）、2=换踏（ped_rep，含按钮路径）、3=硬件 CC（含关态跟踪）、4=复位、5=挂起翻转（仅实际翻转）、6=合成重同步（io_send_synth）。
- **D21 v1.3.1** st_reset(reason, t_abs)：清槽/按住表/pc/两窗/last_note=-1/tail_end=-1/直写 slider16=0；**st_auto_cc==127 → 对 st_ch_auto（空→索引0）逐通道立即 io_send_cc_raw(0, ch_i, 0)**（plan §3.2.15「立即释放」为准；D24 出口合并保证硬件踩住时输出保持硬件值）；**reason==2 → `st_tail_end = t_abs + cfg_tail_smp` 自愈兜底**（冗余无害，去重守卫抑制重复发送）。
- **D22** st_on_note_on/off 均 3 参 `(t_abs, ch, note)`。
- **D23** @init 末尾无条件 `cfg_sync_from_sliders()`（只读；采样率变化由 @slider 双保险再同步）。
- **D24（新，B-1/X3 修复）** **`io_send_cc_raw` = 唯一自动沿出口，出口内合成**：`out = max(val, st_hw_cc)`；`out != st_out_last[ch]` 才 midisend；`st_out_last[ch]=out`；`st_auto_cc` 按 val 记（意图态）；`st_ch_auto[ch]=1`；diag 按意图值。硬件踩住时自动抬沿输出保持 max 值（不切延音）。
- **D25（新，X5 修复）** `io_send_synth` **独立实现**（不经 io_send_cc_raw）：对目标集逐通道 midisend eff=max(hw,auto)、按通道写 st_out_last；**不触 st_auto_cc/st_ch_auto**；diag_log(6)。

## 1. 模块划分

| 模块 | 前缀 | 职责 | 行数预算 |
|---|---|---|---|
| M1 参数管线 | `cfg_` | 16 slider、同步、程序化写参、恢复默认 | ≤120 |
| M2 MIDI I/O | `io_` + `cmd_` | @block 主循环（哨兵引导/沿检测/关态门控/重同步/命令槽消费）、分类、vel0、作用域、拦截合成、`io_send_cc_raw`/`io_send_synth`；cmd_tap/cmd_release/cmd_restore | ≤220 |
| M3 状态机 | `st_` | 按住表/低音 pc/重复音/新音级、挂起、独占链、软复位 | ≤200 |
| M4 踏板调度 | `ped_` | 单槽、gap/humanize/LFSR、限流窗、D16 仲裁、尾音 | ≤150 |
| M5 诊断 | `diag_` | 数值环形日志（D20）、计数器 | ≤90 |
| M6 UI | `ui_` | 四页、hit-test、控件库（含 draw_text 帮助）、踏板动画、拉伸布局 | ≤900（T4≤550） |
| @init 公共段 | — | 常量/音名串/基址表/函数定义承载 | ~60–80 |

音名显示：12 个 `#string` 音名 + pc/八度算术派生（N-4，EEL2 无字符串数组）。总预估 ~1700 行 ∈ [1500,2500]。

## 2. 数据模型与状态流转

### 2.1 时基

`st_abs_smp`（每块 += samplesblock）；`block_start = st_abs_smp - samplesblock`；`t_abs = block_start + off`；ms→采样 `ms*srate*0.001`；时间戳非下标语境禁 `|0`。

### 2.2 配置

同 v1.2：slider1..12 → cfg_* + 5 派生；slider13/14/15 = C01/C02/C03（上升沿消费）；slider16 = C04_HoldOff（电平）。

### 2.3 运行态（全部非持久化，D7 v1.3）

```
st_booted（@block 首块门控）、st_resync_pending（@init 置 1）
st_note_cnt@0[128]  st_bass_pc@128[12]  st_ch_auto@140[16]
st_out_last@156[16]（按通道去重，I-3 修复）  slot_prev@172[3]
st_held_total, st_last_note, st_tail_end, st_prev_enabled, st_evt_seq,
st_hw_cc, st_auto_cc,
ped_active, ped_down_at, ped_ch, ped_kind, win_bass_end, win_rep_end
diag_*（环形日志+计数器）、ui_*（@gfx 线程，标量竞态容忍）
基址表：0/128/140/156/172 + cc_map@512[3] + ui_hit@2048[256]（4页×16控件×4字段，N-7）
```

### 2.4 状态流转

**@block 序列（io_process_block）**：
```
0. 哨兵引导（D7）：!st_booted → last_note=-1/tail_end=-1/seq=0/out_last[0..15]=-1/hw=0/auto=0/
   ped_active=0/两窗=-1/slot_prev 清零/ch_auto 清零/直写 slider16=0 → st_booted=1
1. st_abs_smp += samplesblock
2. 沿检测（D6）：下降沿→st_reset(1, block_start)；上升沿→st_resync_pending=1；
   pending && cfg_enabled → out_last[0..15]=-1 + io_send_synth(0, 0) + pending=0（D8，X1 修复）
3. D14 关态门控：!cfg_enabled → midirecv 直通循环（目标 CC：原样直通 + st_hw_cc=val + diag_log(3)）
   + diag_snapshot() + st_prev_enabled=0 → 结束
4. 命令槽消费（上升沿，t_abs=block_start）：C01→cmd_tap / C02→cmd_release / C03→cmd_restore
5. midirecv 循环 → io_dispatch（SysEx 由 midirecv 原生直通）
6. ped_tick（D16：A=st_tail_end 与 B=ped_down_at 绝对时刻比较；过期 clamp；≥块末顺延；平局尾音先）
   A 先 → 槽取消 + 对 st_ch_auto（空→索引0）逐通道 io_send_cc_raw(offset, ch_i, 0) + tail_end=-1
   B 先 → io_send_cc_raw(offset, ped_ch, 127) + 槽 IDLE
7. st_prev_enabled = cfg_enabled（X4）
8. diag_snapshot()
```

**io_dispatch(off, msg1, msg2, msg3)**（仅 cfg_enabled 时含状态机分支）：
```
ch = msg1 & 0x0F；t_abs = block_start + off
0x9X：vel>0 → st_on_note_on(t_abs, ch, note)（D22 3参）；vel==0 → st_on_note_off(t_abs, ch, note)；直通
0x8X → st_on_note_off；直通
0xBX：作用域内 && cc==cfg_cc → st_hw_cc=val + diag_log(3) + io_send_synth(off, ch)；拦截不直通
      cc==120||123 → st_reset(2, t_abs) + 直通
      其余 → 直通
其他消息 → 直通
```

**st_on_note_on(t_abs, ch, note)**：
```
slider16==1 → 直写 slider16=0 + diag_log(5)（仅翻转时）
repeat = (note == st_last_note)
new_bass_pc = is_bass && (cfg_ign_oct ? st_bass_pc[pc]==0 : (st_bass_pc[pc]==0 || st_note_cnt[note]==0))
st_last_note=note；st_note_cnt[note]++；st_held_total++；is_bass→st_bass_pc[pc]++
st_tail_end=-1
独占链（互斥）：
  ① ped_active → 吸收
  ② cfg_chord && cfg_repeat_on && repeat && st_auto_cc==127 → st_request_rep(t_abs,ch,note,2)
  ③ cfg_chord && new_bass_pc && st_auto_cc==127             → st_request_rep(t_abs,ch,note,1)
  ④ st_auto_cc==0                                           → ped_press(t_abs, ch, note)
```

**st_request_rep**：`now < win_lookup(kind)` → 吸收；否则 ped_rep。
**ped_rep(t_abs, ch, note, kind)**（前置：槽 IDLE && auto==127）：
```
对 st_ch_auto（空→索引0）逐通道 io_send_cc_raw(t_abs偏移, ch_i, 0)     // 抬沿逐通道
down_at = t_abs + cfg_gap_smp + max(cfg_hum_smp + ped_jitter(note), 0) // D12
槽 = {active, down_at, ch, kind}；kind≠3 → win_end(kind) = t_abs + 窗
```
**ped_press(t_abs, ch, note)**：槽 = {active, down_at = t_abs + max(hum+jitter,0), ch, 0}。
**st_on_note_off**：note_cnt>0 才递减（bass_pc 递减下限 0，X11）；held==0 && slider16==0 → tail_end = t_abs + tail_smp。
**io_send_cc_raw(off, ch, val)**（D24）：见 §0。
**io_send_synth(off, ev_ch)**（D25）：见 §0。
**st_reset(reason, t_abs)**（D21）：见 §0。
**命令槽**：
```
cmd_tap（C01）：slider16==1 → 直写 0 + diag_log(5)
  ped_active → 吸收
  auto==127 → ped_rep(block_start, ch_first=st_ch_auto 升序首个非零否则0, note=0, kind 3)（D20 type2 覆盖按钮换踏，X9）
  否则 → ped_press(block_start, ch_first, 0)
  完成后 held==0 → tail_end = block_start + tail_smp（plan §3.2.16⑥）
cmd_release（C02）：槽取消；auto==127 → 对 st_ch_auto（空→索引0）逐通道 io_send_cc_raw(0,ch_i,0)；tail_end=-1；直写 slider16=1 + diag_log(5)
cmd_restore（C03）：cfg_restore_defaults()（D13）
```
**ped_jitter(note)**：LFSR（种子=note+st_evt_seq，**每次生成事件 st_evt_seq++**，X11）→ ±2ms 采样数。

### 2.5 诊断

D20 指派 + 快照 = 三真值/held/bass_pc[12]/发送计数。已知限制（记入对照表）：采样率变化时在途绝对时刻不重标定（一次性时长偏差，X12）；命令槽点击在关态滞留、保存瞬间槽=1 会于重载首块触发（X13，罕见，文档记录）。

## 3. 接口（全部定义于 @init；末尾 cfg_sync_from_sliders()，D23）

```
cfg_sync_from_sliders()  cfg_set_param(idx,val)  cfg_restore_defaults()
io_process_block()  io_dispatch(off,m1,m2,m3)  io_send_synth(off,ev_ch)  io_send_cc_raw(off,ch,val)
cmd_tap()  cmd_release()  cmd_restore()
st_on_note_on(t_abs,ch,note)  st_on_note_off(t_abs,ch,note)  st_request_rep(t_abs,ch,note,kind)  st_reset(reason,t_abs)
ped_rep(t_abs,ch,note,kind)  ped_press(t_abs,ch,note)  ped_tick(block_start,n)  ped_jitter(note)  win_lookup(kind)
diag_log(type,a,b)  diag_snapshot()
ui_draw()  ui_widget_btn/toggle/stepper(...)  ui_draw_text(...)  ui_page_perf/adv/diag/manual()  ui_draw_pedal(state)
```

## 4. 文件结构

```
src/PianoAutoSustain.jsfx
  header：desc / in_pin:none / out_pin:none / options:gfx_hz=60 / 16 slider（默认值在头部）
  @init：常量+音名串+基址表+全部函数 + cfg_sync_from_sliders()（无哨兵安装——移至 @block 首块，D7）
  @serialize：st_serialize_marker = 1;（非空占位，不持久化）
  @slider：cfg_sync_from_sliders()   @block：io_process_block()   @gfx：ui_draw()
docs/使用说明.md  docs/首载检查单.md  tests/测试清单.md  tests/T2语义对照.md（审核方产出）
```

## 5. 任务拆分表

约定（D11）：T1→T2→T3→T4→T5→T7 严格串行；T6 并行。每任务「写码子agent → 对抗审核子agent（产出 tests/T2语义对照.md 于 T2）→ 仲裁 → git commit」。
审核工具化（D10/I-4）：定义集 `grep -oE 'function (cfg|st|ped|io|cmd|diag|ui)_[A-Za-z0-9_]+' src/PianoAutoSustain.jsfx | awk '{print $2}' | sort -u`；调用集 `grep -oE '\b(cfg|st|ped|io|cmd|diag|ui)_[A-Za-z0-9_]+\(' src/PianoAutoSustain.jsfx | tr -d '(' | sort -u`；`comm -13 <(定义集) <(调用集)` 应为空。禁词：标识符 `length`；命令槽与 slider16 外裸 `sliderN=`；`grep -nE '\|0'` 仅允许 `[…|0]` 下标（N-3）；递归人工核对。

| # | 目标 | 产出 | 验收标准 | 依赖 |
|---|---|---|---|---|
| T1 | 骨架+参数管线+基址表 | header、@init 常量/音名串/基址表、M1、四 section 骨架、@serialize 占位 | ① slider 恰 16（plan §4.2，D9 原文）；② @init 无 slider 写入、无运行态清零（哨兵在 @block 首块，D7）；③ @serialize 仅占位赋值；④ cfg_sync 覆盖 12+5；⑤ in/out_pin:none、gfx_hz=60；⑥ 基址表无重叠（含 cc_map/slot_prev/out_last[16]/ui_hit@2048[256]）；⑦ 12 音名串 59→B3 派生抽查 | — |
| T2 | 引擎 M2+M3+M4（含 cmd_*） | io_/cmd_/st_/ped_ 全部 + @block 接线 + @init 补 `st_resync_pending=1;`（D7 载体，T1 审核挂账）+ cfg_set_param 契约注释（idx=slider 编号 1..12；slider12 传枚举索引）+ header 注释改 `//` | ① 审核 agent 产出 tests/T2语义对照.md：plan §3.2.1–3.2.16 逐条→代码位置全命中（I-7 对照表由审核方产出）+「SDS 伪记法→g_mem[基址+idx]」映射 + cfg_repeat_on↔cfg_repeat_repedal 映射；② §2.4 序列逐行核对（哨兵引导/D8 重同步/D14 跟踪式直通/D16 排序含 ≥块末顺延/D24 出口合成/D25 独立 synth）；③ 独占链+双命中丢弃+槽吸收；④ grep 差集空+禁词清单空+数组寻址纪律 grep `\b(st|ped|io|cmd|diag)_[A-Za-z0-9_]*\[` 为空（T1 审核挂账）；⑤ 无递归；⑥ LFSR/D12；⑦ 每块末 st_prev_enabled 同步（X4）；⑧ **填充顺序=叶子在前**：ped_→st_→cmd_→io_process_block 收尾（EEL2 先声明后调用）；diag 调用点以 `// T3: diag_log...` 注释占位（不带括号），diag 函数本体归 T3 | T1 |
| T3 | 诊断 | M5 全部（diag_log/diag_snapshot 实现 + 基址登记）+ 替换 T2 的 `// T3:` 占位为真实调用 + @block 步7 接线 | ① 环形缓冲纯数值；② 快照项齐全；③ type5 仅翻转、type2 覆盖按钮路径；④ 基址表更新（diag 缓冲登记空闲区）；⑤ 替换后 grep 差集复跑为空 | T2 |
| T4 | UI 框架+演奏页 | ui_ 框架+演奏页（≤550 行）+ **两档坐标表**（每控件 x/y/w/h @380×460 与 @760×920，I-8） | ① hit-test 每帧重建+首帧初始化；② 审核对坐标表逐行复算（越界/重叠/失真为零）+ 与代码派生式对照 + grep 裸坐标（颜色/字号外为零）；③ 参数全走 cfg_set_param（裸 sliderN= 仅命令槽与 slider16）；④ 演奏页=plan §4.3；⑤ draw_text 帮助函数就位 | T3 |
| T5 | 高级/诊断/说明书页 | 三页（M6 总量 ≤900） | ① 高级页 7 控件对齐 §4.2（灰置读 cfg_chord）；② 诊断页读快照；③ 说明书页=安装一句话+5 要点短行+指向 docs；④ M6 行数核对 | T4 |
| T6 | 文档 | docs/使用说明.md、docs/首载检查单.md、tests/测试清单.md | ① 覆盖 plan §4.3 五要点+§4.4 版本差异+§4.5 烘焙+低音锚定与三缓解+回放已烘焙关总开关+X12/X13 已知行为；② 首载检查单 5 分钟；③ 测试清单=plan §7 18 场景；④ MIDI learn 绑法官方核验（上升沿消费说明） | plan 定稿（并行） |
| T7 | 集成终审 | 终版 jsfx+交付总结 | ① 独立通读：前缀/递归/local()/grep 差集/slider16/midirecv 消费/@gfx 协议/基址表一致；② D2/D15/D16/D24/D25 抽查代码级；③ §7.7/§7.12/§7.16 场景走查（三条链：加载/停止→播放/关→开）；④ git log 一任务一 commit；⑤ 交付总结 | T1–T6 |

## 6. 验证与交付

验收 = 审核 agent 对照（含对照表/坐标表）+ grep 工具化 + 静态清单；用户首载按 docs/首载检查单.md。全部通过后 git log 核对 + 交付总结。
