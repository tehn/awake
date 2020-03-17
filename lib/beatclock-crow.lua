local BeatClockCrow = {}
BeatClockCrow.__index = BeatClockCrow

function BeatClockCrow.new(name)
  local i = {}
  setmetatable(i, BeatClockCrow)
  
  i.name = name or ""
  i.playing = false
  i.ticks_per_step = 6
  i.current_ticks = i.ticks_per_step - 1
  i.steps_per_beat = 4
  i.beats_per_bar = 4
  i.step = i.steps_per_beat - 1
  i.beat = i.beats_per_bar - 1
  i.external = false
  i.send = false
  i.midi = false
  
  i.metro = metro.init()
  i.metro.count = -1
  i.metro.event = function() i:tick() end
  i:bpm_change(110)

  i.on_step = function(e) print("BeatClockCrow executing step") end
  i.on_start = function(e) end
  i.on_stop = function(e) end
  i.on_select_internal = function(e) print("BeatClockCrow using internal clock") end
  i.on_select_midi = function(e) print("BeatClockCrow using external MIDI clock") end
  i.on_select_crow = function(e) print("BeatClockCrow using external crow clock") end
  
  i:enable_midi()

  return i
end

function BeatClockCrow:start(dev_id)
  self.playing = true
  if not self.externalmidi then
    self.metro:start()
  end
  self.current_ticks = self.ticks_per_step - 1
  if self.midi and self.send then
    for id, device in pairs(midi.devices) do
      if id ~= dev_id then
        device:send({251})
      end
    end
  end
  self.on_start()
end

function BeatClockCrow:stop(dev_id)
  self.playing = false
  self.metro:stop()
  if self.midi and self.send then
    for id, device in pairs(midi.devices) do
      if id ~= dev_id then
        device:send({252})
      end
    end
  end
  self.on_stop()
end

function BeatClockCrow:advance_step()
  self.step = (self.step + 1) % self.steps_per_beat
  if self.step == 0 then
    self.beat = (self.beat + 1) % self.beats_per_bar
  end
  self.on_step()
end

function BeatClockCrow:tick(dev_id)
  self.current_ticks = (self.current_ticks + 1) % self.ticks_per_step
  if self.playing and self.current_ticks == 0 then
    self:advance_step()
  end
  
  if self.midi and self.send then
    for id, device in pairs(midi.devices) do
      if id ~= dev_id then
        device:send({248})
      end
    end
  end
end

function BeatClockCrow:reset(dev_id)
  self.step = self.steps_per_beat - 1
  self.beat = self.beats_per_bar - 1
  self.current_ticks = self.ticks_per_step - 1
  if self.midi and self.send then
    for id, device in pairs(midi.devices) do
      if id ~= dev_id then
        device:send({250})
        if not self.playing then -- force reseting while stopped requires a start/stop (??)
          device:send({252})
        end
      end
    end
  end
end

function BeatClockCrow:clock_source_change(source)
  self.current_ticks = self.ticks_per_step - 1
  if source == 1 then
    self.externalmidi = false
    self.externalcrow = false
    if self.playing then
      self.metro:start()
    end
    self.on_select_internal()
  elseif source == 2 then
    self.externalmidi = true
    self.externalcrow = false
    self.metro:stop()
    self.on_select_midi()
  elseif source == 3 then
    self.externalmidi = false
    self.externalcrow = true
    self.metro:stop()
    self.on_select_crow()
    print("CAW!")
  end
end

function BeatClockCrow:bpm_change(bpm)
  self.bpm = bpm
  self.metro.time = 60/(self.ticks_per_step * self.steps_per_beat * self.bpm)
end

local tap = 0
local deltatap = 1

function BeatClockCrow:add_clock_params()
  params:add_option("clock", "clock", {"internal", "external: midi", "external: crow"}, self.externalcrow or 3 and self.externalmidi or 2 and 1)
  params:set_action("clock", function(x) self:clock_source_change(x) end)
  params:add_option("crow_clock_input", "crow clock input", {"disabled","input 1","input 2"})
  params:set_action("crow_clock_input", function()
    if params:get("clock") == 1 or params:get("clock") == 2 then
      params:set("crow_clock_input", 1)
    end
  end
  )
  params:add_number("bpm", "bpm", 1, 480, self.bpm)
  params:set_action("bpm", function(x) self:bpm_change(x) end)
  params:add{type = "trigger", id = "tap_tempo", name = "tap tempo [K3]", action =
    function()
      local tap1 = util.time()
      deltatap = tap1 - tap
      tap = tap1
      local tap_tempo = 60/deltatap
      if tap_tempo >=20 then
        params:set("bpm",math.floor(tap_tempo+0.5))
      end
    end
  }
  params:add_option("clock_out", "midi clock out?", { "no", "yes" }, self.send or 2 and 1)
  params:set_action("clock_out", function(x) if x == 1 then self.send = false else self.send = true end end)
  params:add_option("crow_clock_out", "crow clock: output 4", { "off", "on" }, self.crow_send or 2 and 1)
  params:set_action("crow_clock_out", function(x)
    if x == 1 then
      self.crow_send = false
    else
      self.crow_send = true
      crow.output[4].action = "{to(5,0),to(0,0.05)}"
    end
  end
  )
end

function BeatClockCrow:enable_midi()
  self.midi = true  
end

function BeatClockCrow:process_midi(data)
  if self.midi then
    status = data[1]
    data1 = data[2]
    data2 = data[3]
  
    if self.externalmidi then 
      if status == 248 then -- midi clock
        self:tick(id)
      elseif status == 250 then -- midi clock start
        self:reset(id)
        self:start(id)
      elseif status == 251 then -- midi clock continue
        self:start(id)
      elseif status == 252 then -- midi clock stop
        self:stop(id)
      end
    end 
  end
end

  
return BeatClockCrow