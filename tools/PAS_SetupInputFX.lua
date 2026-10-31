-- PAS_SetupInputFX.lua — Piano Auto Sustain 一键布防（v2 安全顺序版）
-- 逻辑：先记住主 FX 链里实例的完整名字 → 把这个名字精确添加到 Input FX（监听 FX）
--       → 添加成功之后才删除主链实例。任何一步失败都不动主链。
-- 用法：Actions 列表搜 PAS_SetupInputFX，或由 ZCode 的 script_run 触发。
-- 结果写 console 与 reaper_mcp_script_result（供 MCP 读取），不弹任何模态框。

local TARGET = "Piano Auto Sustain"
local tr = reaper.GetSelectedTrack(0, 0) or reaper.GetTrack(0, 0)
local function report(s)
  reaper.ShowConsoleMsg("PAS_SetupInputFX => " .. s .. "\n")
  reaper.SetExtState("reaper_mcp_script_result", "last_result", s, false)
end

if not tr then return report("no_track") end
local _, tr_name = reaper.GetTrackName(tr)

-- 1) 主链中定位实例并记下完整 FX 名
local main_idx, main_name = -1, nil
for i = 0, reaper.TrackFX_GetCount(tr) - 1 do
  local _, name = reaper.TrackFX_GetFXName(tr, i, "")
  if name:find(TARGET, 1, true) then main_idx, main_name = i, name break end
end

-- 2) Input FX 是否已有
local have = false
for i = 0, reaper.TrackFX_GetRecChainCount(tr) - 1 do
  local _, name = reaper.TrackFX_GetRecFXName(tr, i, "")
  if name:find(TARGET, 1, true) then have = true end
end

-- 3) 添加到 Input FX（用主链实例的完整名字精确匹配；Input FX 已有则跳过）
local added = -1
if have then
  report(string.format("track=%s | infx=already | main_kept=no_change", tostring(tr_name)))
  return
end
if main_name then
  added = reaper.TrackFX_AddByName(tr, main_name, true, -1)
elseif main_idx < 0 then
  -- 主链里没有实例：用目标名尝试（失败不会弹框——名字与已装 FX 一致）
  added = reaper.TrackFX_AddByName(tr, "JS: " .. TARGET, true, -1)
end

-- 4) 成功才删主链实例
local removed = 0
if added >= 0 and main_idx >= 0 then
  reaper.TrackFX_Delete(tr, main_idx)
  removed = 1
end

report(string.format(
  "track=%s | main_found=%s | infx_add_index=%s | main_removed=%d",
  tostring(tr_name), tostring(main_idx), tostring(added), removed))
