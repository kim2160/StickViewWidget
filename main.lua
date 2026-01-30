-- StickView (Dot size + BG color + Dot color + Throttle stats)
-- Reads CH1..CH4 (AETR default): CH1=Ail, CH2=Ele, CH3=Thr, CH4=Rud
-- Stats:
--  1) Full throttle hold time (cumulative) : "FThr:00.0s" (inside left box, bottom-left)
--  2) Average throttle position (sampled)  : "AvgThr:56%"  (inside right box, bottom-right)
--     - sample every 200ms
--     - exclude 0% throttle samples
--  3) Reset when opening widget options

local function rgb(r, g, b)
  if lcd.RGB then return lcd.RGB(r, g, b) end
  return 0
end

local BLACKC = (BLACK ~= nil) and BLACK or rgb(0, 0, 0)
local WHITEC = (WHITE ~= nil) and WHITE or rgb(255, 255, 255)

-- Text labels (edit here to change on-screen strings)
local WIDGET_NAME = "StickView"
local OPT_DOTR = "DotSize"
local OPT_BGCOL = "BgColor"
local OPT_DOTCOL = "DotColor"
local FTHR_FMT = "FullThr : %04.1fs"
local AVGTHR_FMT = "AvgThr : %d%%"
local AVGTHR_NONE = "AvgThr : --%"

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function round(x)
  if x >= 0 then return math.floor(x + 0.5) else return math.ceil(x - 0.5) end
end

local function si(name) return getSourceIndex(name) end

local function to1024(v)
  v = v or 0
  if type(v) ~= "number" then return 0 end
  return clamp(v, -1024, 1024)
end

local function toPix(v1024, half)
  return math.floor((v1024 * half) / 1024)
end

local function drawDot(x, y, r, color)
  if lcd.drawFilledCircle then
    lcd.drawFilledCircle(x, y, r, color)
  else
    -- fallback: concentric circles so radius is visible even without filled circle
    if r < 1 then r = 1 end
    for rr = 1, r do
      lcd.drawCircle(x, y, rr, color)
    end
  end
end

local function create(zone, options)
  local src = {}
  src.ail = si("CH1") or si("CH01") or si("Ail")
  src.ele = si("CH2") or si("CH02") or si("Ele")
  src.thr = si("CH3") or si("CH03") or si("Thr")
  src.rud = si("CH4") or si("CH04") or si("Rud")

  local now = getTime() or 0

  return {
    zone = zone,
    options = options,
    src = src,

    -- timing
    lastT = now,
    lastSampleT = now,

    -- stats
    fullThrSec = 0.0,
    avgSum = 0.0,
    avgCnt = 0,

    -- reset edge detect
    resetPrev = 0,
  }
end

local function update(w, o)
  w.options = o
  -- EdgeTX calls update when the widget options screen opens; reset stats then.
  w.fullThrSec = 0.0
  w.avgSum = 0.0
  w.avgCnt = 0
  w.lastSampleT = getTime() or 0
  w.lastT = getTime() or 0
  w.resetPrev = 0
end

local function refresh(w)
  local z = w.zone
  local opt = w.options

  local bg   = opt[OPT_BGCOL]  or BLACKC
  local col  = opt[OPT_DOTCOL] or WHITEC
  local dotR = opt[OPT_DOTR]   or 12

  -- If user accidentally picks same as BG, keep it visible (prevents "nothing appears")
  local drawCol = col
  if drawCol == bg then
    drawCol = (bg == BLACKC) and WHITEC or BLACKC
  end

  -- Background
  lcd.drawFilledRectangle(z.x, z.y, z.w, z.h, bg)

  if not (w.src and w.src.rud and w.src.thr and w.src.ail and w.src.ele) then
    return
  end

  -- Time delta
  local now = getTime() or 0
  local dtTicks = now - (w.lastT or now)
  if dtTicks < 0 then dtTicks = 0 end
  w.lastT = now
  local dtSec = dtTicks / 100.0

  -- Read channels (-1024..1024)
  local rud = to1024(getValue(w.src.rud))
  local thr = to1024(getValue(w.src.thr))
  local ail = to1024(getValue(w.src.ail))
  local ele = to1024(getValue(w.src.ele))

  -- 1) Full throttle time (cumulative)
  -- threshold slightly below max to avoid missing due to calibration
  if thr >= 1000 then
    w.fullThrSec = (w.fullThrSec or 0) + dtSec
  end

  -- 2) Avg throttle (sample every 200ms, ignore 0% throttle)
  if (now - (w.lastSampleT or now)) >= 20 then -- 20 ticks = 200ms
    w.lastSampleT = now

    -- map -1024..1024 -> 0..100 (%)
    local pct = (thr + 1024) * 100 / 2048
    if pct > 0.5 then -- treat <=0.5% as "0%" and exclude
      w.avgSum = (w.avgSum or 0) + pct
      w.avgCnt = (w.avgCnt or 0) + 1
    end
  end

  -- Layout (two squares centered)
  local pad, gap = 4, 6
  local availW = z.w - pad*2
  local availH = z.h - pad*2
  local boxW   = math.floor((availW - gap) / 2)
  local size   = math.min(boxW, availH)
  if size < 20 then return end

  local totalW = size * 2 + gap
  local x1 = z.x + pad + math.floor((availW - totalW) / 2)
  local y1 = z.y + pad + math.floor((availH - size) / 2)
  local x2 = x1 + size + gap
  local y2 = y1

  local function drawBox(x, y, vx, vy)
    lcd.drawRectangle(x, y, size, size, drawCol)

    local cx = x + math.floor(size/2)
    local cy = y + math.floor(size/2)
    local half = math.floor((size/2) - (dotR + 2))
    if half < 2 then half = 2 end

    local dx = toPix(vx, half)
    local dy = toPix(vy, half)

    local dotX = cx + dx
    local dotY = cy - dy

    -- crosshair
    lcd.drawLine(cx-half, cy, cx+half, cy, SOLID, drawCol)
    lcd.drawLine(cx, cy-half, cx, cy+half, SOLID, drawCol)

    -- dot
    drawDot(dotX, dotY, dotR, drawCol)
  end

  -- Draw boxes + dots
  drawBox(x1, y1, rud, thr) -- Left: Rud/Thr
  drawBox(x2, y2, ail, ele) -- Right: Ail/Ele

  -- Stats text INSIDE boxes (bottom-left / bottom-right)
  local textH = 10
  local txPad = 2
  local textMargin = 5
  local ty = y1 + size - textH - textMargin

  local ftxt = string.format(FTHR_FMT, w.fullThrSec or 0.0)

  local atxt
  if (w.avgCnt or 0) > 0 then
    local avg = (w.avgSum or 0) / w.avgCnt
    atxt = string.format(AVGTHR_FMT, round(avg))
  else
    atxt = AVGTHR_NONE
  end

  -- left box bottom-left
  lcd.drawText(x1 + txPad, ty, ftxt, SMLSIZE + drawCol)
  -- right box bottom-right
  lcd.drawText(x2 + size - txPad, ty, atxt, RIGHT + SMLSIZE + drawCol)
end

return {
  name = WIDGET_NAME,
  options = {
    { OPT_DOTR,   VALUE, 12, 2, 14 },
    { OPT_BGCOL,  COLOR, BLACKC },
    { OPT_DOTCOL, COLOR, WHITEC },
  },
  create = create,
  update = update,
  refresh = refresh
}
