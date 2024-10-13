# -*- Mode: javascript -*-

import json

# Peltier cooler function

class FridgeDriver
  var has_started
  var is_idle
  def init()
    tasmota.remove_driver(global.fridgedriver_instance)
    global.fridgedriver_instance = self
    tasmota.add_driver(global.fridgedriver_instance)

    self.has_started = 0
    self.is_idle     = 0   # a positive counter for turning power supply off, and negative counter for turning it back on
  end
  def every_second()

    var low_peltier         = 10      # peltier is turned off below this demand%
    var internal_offset     = 8       # add some additional power to the internal fan to extract cold from the coldplate (got to be lower than low_peltier for it to turn off at all)
    var low_internal_fan    = 20      # internal fan is turned to this value between low_peltier and this demand%
    var low_external_fan    = 20      # external fan is turned off below this demand%
    var heatsink_multiplier = 3       # fan is turned to this percent% multiplied by the difference in temperature between ambient and heatsink temperature

    var power_time          = 10      # turn off/on after this many seconds of all demands being off or one being on

    # print('Tick Tock', tasmota.millis())
    # FIXME: should pick up a value from a PWM input that has a range of 2-30, and set PID sp with that

    # Following somehow causes initialisation, then two valid loops, then crash for no reason:

    # if self.has_started < 10
    #   print ("Waiting for tasmota to boot before initialising fridge")
    #   self.has_started = self.has_started + 1

    #   return
    # else
    #   if self.has_started == 10
    #     self.has_started = self.has_started + 1

    #     print ("delayed start: Setting ledtable=off, option68=on, pidDSmooth=10")
    #     tasmota.cmd("ledtable off")
    #     tasmota.cmd("setoption68 1")
    #     tasmota.cmd("PidDSmooth 5")

    #     print ("delayed start: done initialising...")

    #     return
    #   end
    # end

    var sensorResult   = json.load(tasmota.read_sensors())
    var heatsinktemp   = sensorResult.find('DS18B20-1', []).find('Temperature', 30) # Default value provided for when reading fails
    var ambienttemp    = sensorResult.find('DS18B20-2', []).find('Temperature', 20) # Default value provided for when reading fails

    var cooling_demand = 100*(1-sensorResult.find('PID', []).find('PidPower', 1)) # Default value provided for when reading fails (just turn the cooler off)
    if (cooling_demand < low_peltier)
      cooling_demand = 0
    end
    if (cooling_demand > 100)
      cooling_demand = 100
    end

    var internalfan    = cooling_demand + internal_offset
    var externalfan    = (heatsinktemp - ambienttemp)*heatsink_multiplier

    if ((internalfan < low_internal_fan) && (internalfan >= low_peltier))
      internalfan = low_internal_fan
    end
    if (internalfan < low_internal_fan)
      internalfan = 0
    end
    if (internalfan > 100)
      internalfan = 100
    end

    if (externalfan < low_external_fan)
        # FIXME: will want hysteresis here
      externalfan = 0
    end
    if (externalfan > 100)
      externalfan = 100
    end


    # calculate whether to just turn off the entire power supply (with hysteresis)
    var power = "wait"
    if (externalfan + internalfan + cooling_demand == 0)
      if (self.is_idle < 0)
        self.is_idle = 0
      end
      if (self.is_idle < power_time)
        self.is_idle = self.is_idle + 1
      else
        power = "off"
      end
    else
      if (self.is_idle > 0)
        self.is_idle = 0
      end
      if (-self.is_idle < power_time)
        self.is_idle = self.is_idle - 1
      else
        power = "on"
      end
    end
    print ("is_idle, power_time, power, demand, internalfan, deltat, externalfan=", self.is_idle, power_time, power, cooling_demand, internalfan, (heatsinktemp - ambienttemp), externalfan)
    if (power != "wait")
      tasmota.cmd("power1 " + power)
    end
    tasmota.cmd("channel2 " + str(cooling_demand))
    tasmota.cmd("channel3 " + str(internalfan))
    tasmota.cmd("channel4 " + str(externalfan))
  end
end

fridgeDriver = FridgeDriver()
