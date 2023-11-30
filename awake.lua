-- awake: time changes
-- 2.7.0 @tehn
-- l.llllllll.co/awake
--
-- top loop plays notes
-- transposed by bottom loop
--
-- (grid optional)
--
-- E1 changes modes:
-- STEP/LOOP/SOUND/OPTION
--
-- K1 held is alt *
--
-- STEP
-- E2/E3 move/change
-- K2 toggle *clear
-- K3 morph *rand
--
-- LOOP
-- E2/E3 loop length
-- K2 reset position
-- K3 jump position
--
-- SOUND
-- K2/K3 selects
-- E2/E3 changes
--
-- OPTION
-- *toggle
-- E2/E3 changes

engine.name = 'PolyPerc'

hs = include('lib/halfsecond')

MusicUtil = require "musicutil"

options = {}
options.OUT = {"audio", "midi", "audio + midi", "crow out 1+2", "crow ii JF", "crow ii 301"}

g = grid.connect()
a = arc.connect()

alt = false
running = true

mode = 1
mode_names = {"STEP","LOOP","SOUND","OPTION"}

one = {
  pos = 0,
  length = 8,
  data = {1,0,3,5,6,7,8,7,0,0,0,0,0,0,0,0}
}

two = {
  pos = 0,
  length = 7,
  data = {5,7,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
}

function add_pattern_params() 
  params:add_separator("pattern data")
  params:add_group("pattern 1",17)
  
  params:add{type = "number", id = "one_length", name = "length", min=1, max=16, 
    default = one.length,
    action=function(x) one.length = x end }

  for i=1,16 do
    params:add{type = "number", id= ("one_data_"..i), name = ("data "..i), min=0, max=8, 
      default = one.data[i],
      action=function(x)one.data[i] = x end }
  end
  
  params:add_group("pattern 2",17)
  
  params:add{type = "number", id = "two_length", name = "length",  min=1, max=16, 
    default = two.length,
    action=function(x)two.length = x end}
  
  for i=1,16 do
    params:add{type = "number", id= "two_data_"..i, name = "data "..i,  min=0, max=8, 
      default = two.data[i],
      action=function(x) two.data[i] = x end }
  end
  
end

set_loop_data = function(which, step, val)
  params:set(which.."_data_"..step, val)
end

local midi_devices
local midi_device
local midi_channel

local scale_names = {}
local notes = {}
local active_notes = {}

local edit_ch = 1
local edit_pos = 1

snd_sel = 1
snd_names = {"cut","gain","pw","rel","fb","rate", "pan", "delay_pan"}
snd_params = {"cutoff","gain","pw","release", "delay_feedback","delay_rate", "pan", "delay_pan"}
NUM_SND_PARAMS = #snd_params

notes_off_metro = metro.init()
arc_redraw_metro = metro.init()

function build_scale()
  notes = MusicUtil.generate_scale_of_length(params:get("root_note"), params:get("scale_mode"), 16)
  local num_to_add = 16 - #notes
  for i = 1, num_to_add do
    table.insert(notes, notes[16 - num_to_add])
  end
end

function all_notes_off()
  if (params:get("out") == 2 or params:get("out") == 3) then
    for _, a in pairs(active_notes) do
      midi_device:note_off(a, nil, midi_channel)
    end
  end
  active_notes = {}
end

function morph(loop, which)
  for i=1,loop.length do
    if loop.data[i] > 0 then
      set_loop_data(which, i, util.clamp(loop.data[i]+math.floor(math.random()*3)-1,1,8))
    end
  end
end

function random()
  for i=1,one.length do set_loop_data("one", i, math.floor(math.random()*9)) end
  for i=1,two.length do set_loop_data("two", i, math.floor(math.random()*9)) end
end

function step()
  while true do

    clock.sync(1/params:get("step_div"))
    if running then
      all_notes_off()

      one.pos = one.pos + 1
      if one.pos > one.length then one.pos = 1 end
      two.pos = two.pos + 1
      if two.pos > two.length then two.pos = 1 end

      if one.data[one.pos] > 0 then
        local note_num = notes[one.data[one.pos]+two.data[two.pos]]
        local freq = MusicUtil.note_num_to_freq(note_num + (params:get("detune")*0.01))
        -- Trig Probablility
        if math.random(100) <= params:get("probability") then
          -- Audio engine out
          if params:get("out") == 1 or params:get("out") == 3 then
            engine.hz(freq)
          elseif params:get("out") == 4 then
            crow.output[1].volts = (note_num-60)/12
            crow.output[2].execute()
          elseif params:get("out") == 5 then
            crow.ii.jf.play_note((note_num-60)/12,5)
          elseif params:get("out") == 6 then -- er301
            crow.ii.er301.cv(1, (note_num-60)/12)
            crow.ii.er301.tr_pulse(1)
          end

          -- MIDI out
          if (params:get("out") == 2 or params:get("out") == 3) then
            midi_device:note_on(note_num, 96, midi_channel)
            table.insert(active_notes, note_num)

            --local note_off_time = 
            -- Note off timeout
            if params:get("note_length") < 4 then
              notes_off_metro:start((60 / params:get("clock_tempo") / params:get("step_div")) * params:get("note_length") * 0.25, 1)
            end
          end
        end
      end

      gridredraw()
      redraw()
    else
    end
  end
end

function stop()
  running = false
  all_notes_off()
end

function start()
  running = true
end

function reset()
  one.pos = 0
  two.pos = 0
end

function clock.transport.start()
  reset()
  start()
end

function clock.transport.stop()
  stop()
end

function clock.transport.reset()
  reset()
end

function midi_event(data)
  msg = midi.to_msg(data)
  if msg.type == "start" then
      clock.transport.reset()
      clock.transport.start()
  elseif msg.type == "continue" then
    if running then 
      clock.transport.stop()
    else 
      clock.transport.start()
    end
  end 
  if msg.type == "stop" then
    clock.transport.stop()
  end 
end

function build_midi_device_list()
  midi_devices = {}
  for i = 1,#midi.vports do
    local long_name = midi.vports[i].name
    local short_name = string.len(long_name) > 15 and util.acronym(long_name) or long_name
    table.insert(midi_devices,i..": "..short_name)
  end
end

function init()
  for i = 1, #MusicUtil.SCALES do
    table.insert(scale_names, string.lower(MusicUtil.SCALES[i].name))
  end
  
  build_midi_device_list()

  notes_off_metro.event = all_notes_off
  arc_redraw_metro.event = arcredraw
  arc_redraw_metro:start(1 / 60)

  
  params:add_separator("AWAKE")
  
  params:add_group("outs",3)
  params:add{type = "option", id = "out", name = "out",
    options = options.OUT,
    action = function(value)
      all_notes_off()
      if value == 4 then crow.output[2].action = "{to(5,0),to(0,0.25)}"
      elseif value == 5 or value == 6 then
        crow.ii.pullup(true)
        crow.ii.jf.mode(1)
      end
    end}
  params:add{type = "option", id = "midi_device", name = "midi out device",
    options = midi_devices, default = 1,
    action = function(value) midi_device = midi.connect(value) end}
  
  params:add{type = "number", id = "midi_out_channel", name = "midi out channel",
    min = 1, max = 16, default = 1,
    action = function(value)
      all_notes_off()
      midi_channel = value
    end}
  
  params:add_group("step",8)
  params:add{type = "number", id = "step_div", name = "step division", min = 1, max = 16, default = 4}

  params:add{type = "option", id = "note_length", name = "note length",
    options = {"25%", "50%", "75%", "100%"},
    default = 4}
  
  params:add{type = "option", id = "scale_mode", name = "scale mode",
    options = scale_names, default = 5,
    action = function() build_scale() end}
  params:add{type = "number", id = "root_note", name = "root note",
    min = 0, max = 127, default = 60, formatter = function(param) return MusicUtil.note_num_to_name(param:get(), true) end,
    action = function() build_scale() end}
  params:add{type = "number", id = "probability", name = "probability",
    min = 0, max = 100, default = 100}
  params:add{type = "trigger", id = "stop", name = "stop",
    action = function() stop() reset() end}
  params:add{type = "trigger", id = "start", name = "start",
    action = function() start() end}
  params:add{type = "trigger", id = "reset", name = "reset",
    action = function() reset() end}
  
  params:add_group("synth", 7)
  cs_AMP = controlspec.new(0,1,'lin',0,0.5,'')
  params:add{type="control",id="amp",controlspec=cs_AMP,
    action=function(x) engine.amp(x) end}

  cs_PW = controlspec.new(0,100,'lin',0,50,'%')
  params:add{type="control",id="pw",controlspec=cs_PW,
    action=function(x) engine.pw(x/100) end}

  cs_REL = controlspec.new(0.1,3.2,'lin',0,1.2,'s')
  params:add{type="control",id="release",controlspec=cs_REL,
    action=function(x) engine.release(x) end}

  cs_CUT = controlspec.new(50,5000,'exp',0,800,'hz')
  params:add{type="control",id="cutoff",controlspec=cs_CUT,
    action=function(x) engine.cutoff(x) end}

  cs_GAIN = controlspec.new(0,4,'lin',0,1,'')
  params:add{type="control",id="gain",controlspec=cs_GAIN,
    action=function(x) engine.gain(x) end}
  
  cs_PAN = controlspec.new(-1,1, 'lin',0,0,'')
  params:add{type="control",id="pan",controlspec=cs_PAN,
    action=function(x) engine.pan(x) end}

  params:add{type="number",id="detune",min=-100, max=100, default=0}

  hs.init()

  params:add{type="option",id="grid_rotation",name="Grid rotation",
    options={"0","90","180","270"},default=1,
    action=function(value)
      if g then
        g:rotation(value - 1)
        gridredraw()
      end
    end
  }

  params:add{type="option",id="arc_rotation",name="Arc rotation",
    options={"0","90","180","270"},default=1}

  add_pattern_params()
  params:default()
  midi_device.event = midi_event

  clock.run(step)

  norns.enc.sens(1,8)
end

function g.key(x, y, z)
  local grid_h = g.rows
  if z > 0 then
    if (grid_h == 8 and edit_ch == 1) or (grid_h == 16 and y <= 8) then
      if one.data[x] == 9-y then
        set_loop_data("one", x, 0)
      else
        set_loop_data("one", x, 9-y)
      end
    end
    if (grid_h == 8 and edit_ch == 2) or (grid_h == 16 and y > 8) then
      if grid_h == 16 then y = y - 8 end
      if two.data[x] == 9-y then
        set_loop_data("two", x, 0)
      else
        set_loop_data("two", x, 9-y)
      end
    end
    gridredraw()
    redraw()
  end
end

function gridredraw()
  if not g then
    return
  end

  local grid_h = g.rows
  g:all(0)
  if edit_ch == 1 or grid_h == 16 then
    for x = 1, 16 do
      if one.data[x] > 0 then g:led(x, 9-one.data[x], 5) end
    end
    if one.pos > 0 and one.data[one.pos] > 0 then
      g:led(one.pos, 9-one.data[one.pos], 15)
    else
      g:led(one.pos, 1, 3)
    end
  end
  if edit_ch == 2 or grid_h == 16 then
    local y_offset = 0
    if grid_h == 16 then y_offset = 8 end
    for x = 1, 16 do
      if two.data[x] > 0 then g:led(x, 9-two.data[x] + y_offset, 5) end
    end
    if two.pos > 0 and two.data[two.pos] > 0 then
      g:led(two.pos, 9-two.data[two.pos] + y_offset, 15)
    else
      g:led(two.pos, 1 + y_offset, 3)
    end
  end
  g:refresh()
end

function a.delta(n, d)
  if n == 1 then
    params:delta("pw", 0.2 * d)
  elseif n == 2 then
    -- cutoff is exponential; we use the controlspec
    -- for adjustments to feel natural
    local now = cs_CUT:unmap(params:get("cutoff"))
    local delta = 0.002
    params:set("cutoff", cs_CUT:map(now + delta * d))
  elseif n == 3 then
    params:delta("gain", 0.2 * d)
  elseif n == 4 then
    params:delta("release", 0.2 * d)
  end
end

function arcredraw()
  if not a then
    return
  end

  -- Arc doesn't have built-in rotation support so we do
  -- it ourselves.
  local rot = 16 * (params:get("arc_rotation") - 1)
  a:all(0)
  a:led(1, rot + 1, 4)
  a:led(2, rot + 1, 4)
  a:led(3, rot + 1, 4)
  a:led(4, rot + 1, 4)

  -- ARC 1
  local percentage = 64 * cs_PW:unmap(params:get("pw"))
  for i=1,64 do
    if percentage >= i then
      a:led(1, (i-1 + rot) % 64 + 1, 15)
    end
  end
  -- ARC 2
  percentage = 64 * cs_CUT:unmap(params:get("cutoff"))
  for i=1,64 do
    if percentage >= i then
      a:led(2, (i-1 + rot) % 64 + 1, 15)
    end
  end
  -- ARC 3
  percentage = 64 * cs_GAIN:unmap(params:get("gain"))
  for i=1,64 do
    if percentage >= i then
      a:led(3, (i-1 + rot) % 64 + 1, 15)
    end
  end
  -- ARC 4
  percentage = 64 * cs_REL:unmap(params:get("release"))
  for i=1,64 do
    if percentage >= i then
      a:led(4, (i-1 + rot) % 64 + 1, 15)
    end
  end
  a:refresh()
end

function enc(n, delta)
  if n==1 then
    mode = util.clamp(mode+delta,1,4)
  elseif mode == 1 then --step
    if n==2 then
      if alt then
        params:delta("probability", delta)
      else
        local p = (edit_ch == 1) and one.length or two.length
        edit_pos = util.clamp(edit_pos+delta,1,p)
      end
    elseif n==3 then
      if edit_ch == 1 then
        params:delta("one_data_"..edit_pos, delta)
      else
        params:delta("two_data_"..edit_pos, delta)
      end
    end
  elseif mode == 2 then --loop
    if n==2 then
      params:delta("one_length", delta)
    elseif n==3 then
      params:delta("two_length", delta)
    end
  elseif mode == 3 then --sound
    if n==2 then
      params:delta(snd_params[snd_sel], delta)
    elseif n==3 then
      params:delta(snd_params[snd_sel+1], delta)
    end
  elseif mode == 4 then --option
    if n==2 then
      if alt==false then
        params:delta("clock_tempo", delta)
      else
        params:delta("step_div",delta)
      end
    elseif n==3 then
      if alt==false then
        params:delta("root_note", delta)
      else
        params:delta("scale_mode", delta)
      end
    end
  end
  redraw()
end

function key(n,z)
  if n==1 then
    alt = z==1

  elseif mode == 1 then --step
    if n==2 and z==1 then
      if not alt==true then
        -- toggle edit
        if edit_ch == 1 then
          edit_ch = 2
          if edit_pos > two.length then edit_pos = two.length end
        else
          edit_ch = 1
          if edit_pos > one.length then edit_pos = one.length end
        end
      else
        -- clear
        for i=1,one.length do params:set("one_data_"..i, 0) end
        for i=1,two.length do params:set("two_data_"..i, 0) end

      end
    elseif n==3 and z==1 then
      if not alt==true then
        -- morph
        if edit_ch == 1 then morph(one, "one") else morph(two, "two") end
      else
        -- random
        random()
        gridredraw()
      end
    end
  elseif mode == 2 then --loop
    if n==2 and z==1 then
      one.pos = 0
      two.pos = 0
    elseif n==3 and z==1 then
      one.pos = math.floor(math.random()*one.length)
      two.pos = math.floor(math.random()*two.length)
    end
  elseif mode == 3 then --sound
    if n==2 and z==1 then
      snd_sel = util.clamp(snd_sel - 2,1,NUM_SND_PARAMS-1)
    elseif n==3 and z==1 then
      snd_sel = util.clamp(snd_sel + 2,1,NUM_SND_PARAMS-1)
    end
  elseif mode == 4 then --option
    if n==2 then
    elseif n==3 then
    end
  end

  redraw()
end

function redraw()
  screen.clear()
  screen.line_width(1)
  screen.aa(0)
  -- edit point
  if mode==1 then
    screen.move(26 + edit_pos*6, edit_ch==1 and 33 or 63)
    screen.line_rel(4,0)
    screen.level(15)
    if alt then
      screen.move(0, 30)
      screen.level(1)
      screen.text("prob")
      screen.move(0, 45)
      screen.level(15)
      screen.text(params:get("probability"))
    end
    screen.stroke()
  end
  -- loop lengths
  screen.move(32,30)
  screen.line_rel(one.length*6-2,0)
  screen.move(32,60)
  screen.line_rel(two.length*6-2,0)
  screen.level(mode==2 and 6 or 1)
  screen.stroke()
  -- steps
  for i=1,one.length do
    screen.move(26 + i*6, 30 - one.data[i]*3)
    screen.line_rel(4,0)
    screen.level(i == one.pos and 15 or ((edit_ch == 1 and one.data[i] > 0) and 4 or (mode==2 and 6 or 1)))
    screen.stroke()
  end
  for i=1,two.length do
    screen.move(26 + i*6, 60 - two.data[i]*3)
    screen.line_rel(4,0)
    screen.level(i == two.pos and 15 or ((edit_ch == 2 and two.data[i] > 0) and 4 or (mode==2 and 6 or 1)))
    screen.stroke()
  end

  screen.level(4)
  screen.move(0,10)
  screen.text(mode_names[mode])

  if mode==3 then
    screen.level(1)
    screen.move(0,30)
    screen.text(snd_names[snd_sel])
    screen.level(15)
    screen.move(0,40)
    screen.text(params:string(snd_params[snd_sel]))
    screen.level(1)
    screen.move(0,50)
    screen.text(snd_names[snd_sel+1])
    screen.level(15)
    screen.move(0,60)
    screen.text(params:string(snd_params[snd_sel+1]))
  elseif mode==4 then
    screen.level(1)
    screen.move(0,30)
    screen.text(alt==false and "bpm" or "div")
    screen.level(15)
    screen.move(0,40)
    screen.text(alt==false and params:get("clock_tempo") or params:string("step_div")) 
    screen.level(1)
    screen.move(0,50)
    screen.text(alt==false and "root" or "scale")
    screen.level(15)
    screen.move(0,60)
    screen.text(alt==false and params:string("root_note") or params:string("scale_mode"))
  end



  screen.update()
end

function cleanup()
end
