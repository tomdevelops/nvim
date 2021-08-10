-- Attempt to write useful color scheme functionality:
-- - Implement 'base16' theme in Lua.
-- - Implement 'mini16' theme which should take only two colors: main
--   background and main foreground. Everything else should be autogenerated
--   based on personal euristics.

-- Module and its helper
local MiniColors = {}
local H = {}

-- Module setup
function MiniColors.setup(config)
  -- Export module
  _G.MiniColors = MiniColors
end

function MiniColors.mini16_generate_scale(background, foreground)
  if not (H.is_hex(background) and H.is_hex(foreground)) then return nil end
  local back, fore = H.hex_to_hsl(background), H.hex_to_hsl(foreground)

  local res = {}

  -- First four colors are "background": have same hue and saturation as
  -- `background`, but lightness progresses towards middle
  vim.list_extend(res, H.make_lightness_scale(back, fore.lightness))
  -- Second four colors are "foreground": have same hue and saturation as
  -- `foreground`, but lightness progresses towards middle
  vim.list_extend(res, H.make_lightness_scale(fore, back.lightness))

  -- Eight accent colors are generated as pairs:
  -- - Each pair has same hue from set of hues "most different" to background
  --   and foreground hues.
  -- - Within pair there is base lightness (equal to foreground lightness) and
  --   alternative (as middle lightness between foreground and background).
  -- - All colors have the same saturation as foreground (as they will appear
  --   next to each other).
  local middle_lightness = 0.5 * (fore.lightness + back.lightness)
  local accent_hues = H.make_different_hues({back.hue, fore.hue}, 4)
  for _, hue in pairs(accent_hues) do
    local base = {hue = hue, saturation = fore.saturation, lightness = fore.lightness}
    local alt  = {hue = hue, saturation = fore.saturation, lightness = middle_lightness}
    vim.list_extend(res, {H.hsl_to_hex(base), H.hsl_to_hex(alt)})
  end

  return res
end

-- Helpers
---- Optimal scales
---- Make a set of equally spaced hues which are as different to present hues
---- as possible
function H.make_different_hues(present_hues, n)
  local max_offset = math.floor(360 / n + 0.5) - 1
  local best_dist = -math.huge
  local cur_dist, dist, p_dist
  local best_hues, new_hues

  for offset=0,max_offset,1 do
    new_hues = H.make_hue_scale(n, offset)

    -- Compute distance as usual 'minimum distance' between two sets
    dist = H.dist_set(new_hues, present_hues)

    -- Decide if it is the best
    if dist > best_dist then
      best_hues, best_dist = new_hues, dist
    end
  end

  return best_hues
end

function H.make_hue_scale(n, offset)
  local res, step = {}, math.floor(360 / n + 0.5)
  for i=0,n-1,1 do table.insert(res, (offset + i * step) % 360) end
  return res
end

function H.make_lightness_scale(base, opposite_lightness)
  local middle = 0.5 * (base.lightness + opposite_lightness)
  local h = (middle - base.lightness) / 3

  local res = {}
  for i=0,3,1 do
    local l = base.lightness + i * h
    local hsl = {hue = base.hue, saturation = base.saturation, lightness = l}
    table.insert(res, H.hsl_to_hex(hsl))
  end

  return res
end

---- Color conversion
function H.hex_to_rgb(hex)
  if not H.is_hex(hex) then return nil end

  local dec = tonumber(hex:sub(2), 16)

  local blue = math.fmod(dec, 256)
  local green = math.fmod((dec - blue) / 256, 256)
  local red = math.floor(dec / 65536)

  return {red = red, green = green, blue = blue}
end

function H.rgb_to_hex(rgb)
  if not H.is_rgb(rgb) then return nil end

  local dec = 65536 * rgb.red + 256 * rgb.green + rgb.blue
  return string.format('#%06x', dec)
end

------ Source: https://en.wikipedia.org/wiki/HSL_and_HSV#From_RGB
function H.rgb_to_hsl(rgb)
  if not H.is_rgb(rgb) then return nil end

  local r, g, b = rgb.red / 255, rgb.green / 255, rgb.blue / 255
  local m, M = math.min(r, g, b), math.max(r, g, b)
  local chroma = M - m

  local l = 0.5 * (m + M)

  local s = 0
  if l ~= 0 and l ~= 1 then s = (M - l) / math.min(l, 1 - l) end

  local h
  if chroma == 0 then
    h = 0
  elseif M == r then
    h = 60 * (0 + (g - b) / chroma)
  elseif M == g then
    h = 60 * (2 + (b - r) / chroma)
  elseif M == b then
    h = 60 * (4 + (r - g) / chroma)
  end
  if h < 0 then h = h + 360 end

  return {hue = h, saturation = s, lightness = l}
end

function H.hsl_to_rgb(hsl)
  if not H.is_hsl(hsl) then return nil end

  local f = function(n)
    local k = math.fmod(n + hsl.hue / 30, 12)
    local a = hsl.saturation * math.min(hsl.lightness, 1 - hsl.lightness)
    local m = math.min(k - 3, 9 - k, 1)
    return hsl.lightness - a * math.max(-1, m)
  end

  return {
    -- Add 0.5 to make crude rounding and not floor
    red = math.floor(255 * f(0) + 0.5),
    green = math.floor(255 * f(8) + 0.5),
    blue = math.floor(255 * f(4) + 0.5)
  }
end

function H.hex_to_hsl(hex)
  if not H.is_hex(hex) then return nil end
  return H.rgb_to_hsl(H.hex_to_rgb(hex))
end

function H.hsl_to_hex(hsl)
  if not H.is_hsl(hsl) then return nil end
  return H.rgb_to_hex(H.hsl_to_rgb(hsl))
end

function H.is_hex(x)
  return type(x) == 'string' and x:len() == 7 and
    x:sub(1, 1) == '#' and (tonumber(x:sub(2), 16) ~= nil)
end

function H.is_rgb(x)
  return type(x) == 'table' and
    type(x.red) == 'number' and 0 <= x.red and x.red <= 255 and
    type(x.green) == 'number' and 0 <= x.green and x.green <= 255 and
    type(x.blue) == 'number' and 0 <= x.blue and x.blue <= 255
end

function H.is_hsl(x)
  return type(x) == 'table' and
    type(x.hue) == 'number' and 0 <= x.hue and x.hue <= 360 and
    type(x.saturation) == 'number' and 0 <= x.saturation and x.saturation <= 1 and
    type(x.lightness) == 'number' and 0 <= x.lightness and x.lightness <= 1
end

---- Distances
function H.dist_circle(x, y)
  local d = math.abs(x - y) % 360
  return d > 180 and 360 - d or d
end

function H.dist_set(set1, set2)
  local dist = math.huge
  local d
  for _, x in pairs(set1) do
    for _, y in pairs(set2) do
      d = H.dist_circle(x, y)
      if dist > d then dist = d end
    end
  end
  return dist
end

return MiniColors