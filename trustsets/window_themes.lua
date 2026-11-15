-- TrustSets FFXI window textures (Window Types 1-8 / ROM\0\14.DAT-21.DAT).
-- The included PNG assets are extracted from the user's DAT files; no DATs
-- are modified or loaded from the game's installation at runtime.
-- This file deliberately keeps Direct3D and ImGui failures from taking down
-- the TrustSets queue: if texture support is unavailable, use the palette UI.
local M = {};
local ok_ffi, ffi = pcall(require, 'ffi');
local ok_d3d, d3d = pcall(require, 'd3d8');
local ok_d3dx = pcall(require, 'd3d8.d3dx8');
-- Ashita's addons.dll forwards D3DXCreateTextureFromFileA; ffi.C exposes it.
-- Loading a standalone d3dx8.dll is not reliable on modern game clients.
local d3dx = (ok_ffi and ok_d3d and ok_d3dx) and ffi.C or nil;

local cache = {};
local unavailable = {};
local ROOT = nil;
local names = { 'background', 'horizontal', 'vertical', 'corner' };

local function root()
    if (ROOT ~= nil) then return ROOT; end
    local base = '';
    if (AshitaCore and AshitaCore.GetInstallPath) then
        local ok, path = pcall(function () return AshitaCore:GetInstallPath(); end);
        if (ok and type(path) == 'string') then base = path; end
    end
    if (base ~= '' and not base:match('[/\\]$')) then base = base .. '\\'; end
    ROOT = base .. 'addons\\trustsets\\assets\\themes\\';
    return ROOT;
end

local function load_file(path)
    if (not d3dx) then return nil; end
    local out = ffi.new('IDirect3DTexture8*[1]');
    local dev = d3d.get_device();
    if (dev == nil) then return nil; end
    local hr = d3dx.D3DXCreateTextureFromFileA(dev, path, out);
    if (hr ~= 0 or out[0] == nil) then return nil; end
    return out[0];
end

-- Loads a theme only once (32 native textures in total for all 8 types).
function M.ensure(which)
    local id = tonumber(which);
    if (not id or id < 1 or id > 8 or id % 1 ~= 0) then return nil; end
    if (cache[id]) then return cache[id]; end
    if (unavailable[id]) then return nil; end
    local group = {};
    for _, name in ipairs(names) do
        local path = root() .. tostring(id + 13) .. '\\' .. name .. '.png';
        local ok, tex = pcall(load_file, path);
        if (ok and tex ~= nil) then group[name] = tex; end
    end
    if (not group.background) then
        -- On a failure, return to the previous readable opaque ImGui style.
        for _, texture in pairs(group) do pcall(function () texture:Release(); end); end
        -- The Direct3D device can be unavailable during startup. Try again
        -- next frame rather than locking the theme out for the session.
        return nil;
    end
    cache[id] = group;
    return group;
end

function M.available(which)
    return M.ensure(which) ~= nil;
end

function M.release()
    for _, group in pairs(cache) do
        for _, texture in pairs(group) do
            pcall(function () texture:Release(); end);
        end
    end
    cache = {};
    unavailable = {};
end

local function texture_id(texture)
    -- Ashita v4 / D3D8 is 32-bit. ImGui uses an integer texture ID.
    return tonumber(ffi.cast('uint32_t', texture));
end

-- Calibrated from the user's side-by-side screenshots of FFXI chat windows
-- (Window Types 1-8) and TrustSets v1.5.0.  The original images are already
-- correctly decoded.  The v1.5.0 color mismatch was caused mainly by an
-- additional heavy dark overlay and another dark ChildBg tint.  Apply the
-- calibration directly to the DAT texture, preserving its light and detail.
-- This is a *render* tint only; the supplied DAT-derived PNGs stay unchanged.
local settings = {
    [1] = { rgb={1.00,1.06,0.83}, alpha=1.00, trim=0.91 }, -- violet stripes
    [2] = { rgb={0.56,0.57,0.54}, alpha=1.00, trim=0.90 }, -- gray slate
    [3] = { rgb={1.10,1.12,0.82}, alpha=1.00, trim=0.91 }, -- blue/violet stripes
    [4] = { rgb={0.84,0.84,0.84}, alpha=1.00, trim=0.90 }, -- rough charcoal
    [5] = { rgb={0.62,0.60,0.63}, alpha=0.78, trim=0.90 }, -- translucent gray
    [6] = { rgb={1.00,0.68,0.54}, alpha=1.00, trim=0.92 }, -- deep blue
    [7] = { rgb={0.49,0.48,0.47}, alpha=1.00, trim=0.91 }, -- antique gold
    [8] = { rgb={1.06,0.84,0.83}, alpha=1.00, trim=0.91 }, -- teal marble
};

local function color(imgui, rgb, alpha)
    rgb = rgb or {1,1,1};
    return imgui.GetColorU32({ rgb[1], rgb[2], rgb[3], alpha or 1.0 });
end

local function draw_image(imgui, dl, tex, x, y, w, h, u0, v0, u1, v1, rgb, alpha)
    if (not tex or w <= 0 or h <= 0) then return; end
    dl:AddImage(texture_id(tex), { x, y }, { x+w, y+h },
        { u0 or 0, v0 or 0 }, { u1 or 1, v1 or 1 }, color(imgui, rgb, alpha));
end

local function tile(imgui, dl, tex, x, y, w, h, rgb, alpha)
    -- The complete DXT1 background is a 128x128 image.  The old renderer
    -- truncated it at 96px, creating visible seams and changing the pattern.
    -- Repeat the original full-size tile, cropping only the final partial one.
    local side = 128;
    local cy = 0;
    while (cy < h) do
        local dh = math.min(side, h - cy);
        local cx = 0;
        while (cx < w) do
            local dw = math.min(side, w - cx);
            draw_image(imgui, dl, tex, x+cx, y+cy, dw, dh,
                0, 0, dw/side, dh/side, rgb, alpha);
            cx = cx + side;
        end
        cy = cy + side;
    end
end

-- Draw directly after imgui.Begin(), BEFORE widgets, using the window's own
-- draw list. This means normal hit-testing, resize, and mouse handling are
-- unchanged. No GetWindowPos().x / .y (Sugarmath binding incompatibility).
function M.decorate(imgui, id)
    local t = M.ensure(id);
    if (not t) then return false; end
    local drawn = false;
    local ok = pcall(function ()
        local x, y = imgui.GetWindowPos();
        local w, h = imgui.GetWindowSize();
        if (type(x) ~= 'number' or type(y) ~= 'number' or
            type(w) ~= 'number' or type(h) ~= 'number' or w < 20 or h < 20) then return; end
        local dl = imgui.GetWindowDrawList();
        local props = settings[tonumber(id)];
        local title = (imgui.GetFrameHeight and imgui.GetFrameHeight()) or 24;
        local left, top = x+1, y+title;
        local iw, ih = math.max(0, w-2), math.max(0, h-title-1);
        -- Apply the screenshot-calibrated DAT texture directly.  Do NOT add
        -- a dark rectangle on top: it caused the old windows to look almost
        -- black, especially Window Types 2, 6, 7 and 8.
        tile(imgui, dl, t.background, left, top, iw, ih, props.rgb, props.alpha);
        -- Horizontal and vertical 32x32 DAT sprites store BOTH opposing edges.
        -- Crop from the top/bottom 4 texels or left/right 4 texels, not
        -- squash the complete texture into a thin line.
        if (t.horizontal) then
            local sx = 16;
            while (sx < w-16) do
                local len = math.min(32, w-16-sx);
                draw_image(imgui,dl,t.horizontal,x+sx,y+title,len,4,
                    0,0,len/32,4/32,nil,props.trim);
                draw_image(imgui,dl,t.horizontal,x+sx,y+h-4,len,4,
                    0,28/32,len/32,1,nil,props.trim);
                sx = sx + 32;
            end
        end
        if (t.vertical) then
            local sy = title+16;
            while (sy < h-16) do
                local len = math.min(32,h-16-sy);
                draw_image(imgui,dl,t.vertical,x+1,y+sy,4,len,
                    0,0,4/32,len/32,nil,props.trim);
                draw_image(imgui,dl,t.vertical,x+w-5,y+sy,4,len,
                    28/32,0,1,len/32,nil,props.trim);
                sy = sy + 32;
            end
        end
        if (t.corner) then
            -- Each corner occupies one non-overlapping 16x16 quadrant.
            draw_image(imgui,dl,t.corner,x+1,y+title,16,16,0,0,.5,.5,nil,props.trim);
            draw_image(imgui,dl,t.corner,x+w-17,y+title,16,16,.5,0,1,.5,nil,props.trim);
            draw_image(imgui,dl,t.corner,x+1,y+h-17,16,16,0,.5,.5,1,nil,props.trim);
            draw_image(imgui,dl,t.corner,x+w-17,y+h-17,16,16,.5,.5,1,1,nil,props.trim);
        end
        drawn = true;
    end);
    return ok and drawn;
end

function M.preview(imgui, id, width, height)
    local t = M.ensure(id);
    if (not t) then return false; end
    local ok = pcall(function ()
        local x, y = imgui.GetCursorScreenPos();
        local dl = imgui.GetWindowDrawList();
        local props = settings[tonumber(id)];
        tile(imgui, dl, t.background, x, y, width, height, props.rgb, props.alpha);
        imgui.Dummy({width,height});
    end);
    return ok;
end

return M;
