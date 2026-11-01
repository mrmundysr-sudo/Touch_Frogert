-- research harness: coin, start, scripted/random inputs, memory logging
local m = manager.machine
local game = emu.romname()
local frame = 0
local log = io.open("/tmp/work/"..game.."_ram.log","w")
local function port(tag,name) return m.ioport.ports[tag].fields[name] end
local function press(tag,name,v) port(tag,name):set_value(v) end
local cpu = m.devices[":maincpu"]
local mem = cpu.spaces["program"]
local START_AT, COIN_AT = 600, 300   -- frames of attract first
math.randomseed(7)
local dirs, hold = nil, 0
local held = nil
if game=="frogger" then dirs={{":IN2","P1 Up"},{":IN2","P1 Up"},{":IN2","P1 Up"},{":IN0","P1 Left"},{":IN0","P1 Right"},{":IN2","P1 Down"}}
else dirs={{":IN4","P1 Down (Down-Left)"},{":IN4","P1 Right (Down-Right)"},{":IN4","P1 Down (Down-Left)"},{":IN4","P1 Right (Down-Right)"},{":IN4","P1 Up (Up-Right)"},{":IN4","P1 Left (Up-Left)"}} end
emu.register_frame_done(function()
  frame = frame + 1
  if frame==COIN_AT then
    if game=="frogger" then press(":IN0","Coin 1",1) else press(":IN1","Coin 1",1) end
  elseif frame==COIN_AT+4 then
    if game=="frogger" then press(":IN0","Coin 1",0) else press(":IN1","Coin 1",0) end
  elseif frame==START_AT then
    if game=="frogger" then press(":IN1","1 Player Start",1) else press(":IN1","1 Player Start",1) end
  elseif frame==START_AT+4 then press(":IN1","1 Player Start",0) end
  if frame>START_AT+120 then
    hold = hold - 1
    if hold<=0 then
      if held then press(held[1],held[2],0) end
      if hold<=-6 then
        held = dirs[math.random(#dirs)]; press(held[1],held[2],1); hold = 5
      end
    end
  end
  if frame % 2 == 0 then
    local t = {}
    if game=="frogger" then
      for a=0xb000,0xb0ff do t[#t+1]=string.format("%02x",mem:read_u8(a)) end
    end
    log:write(frame," ",table.concat(t),"\n")
  end
end)
