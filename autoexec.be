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

    var low_thermostat      = 0.0
    var high_thermostat     = 20.0
#    var low_thermostat      = -50    #debugging while ADC temperature header is unplugged, yielding a temperature input of -48.85degC
#    var high_thermostat     = -46
    var low_pb              = 0
    var high_pb             = 5
    var low_ti              = 0
    var high_ti             = 1800
    var low_td              = low_ti/4
    var high_td             = high_ti/4

    #var temp_avg  = 60.0   # seconds to average internal temperature reading over
    var temp_avg  = 15.0   # seconds to average internal temperature reading over

    # print('Tick Tock', tasmota.millis())

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

    # Actually set the thermostat (based on our fake PWM0 slider)
    var setpoint_input = light.get(0).find('channels', [])[0]
    var setpoint       = low_thermostat + setpoint_input * (high_thermostat - low_thermostat) / 255.0
    tasmota.cmd("PidSp " + str(setpoint))

    # do similar for PidPb (default 5 degrees, we probably want 1.5)
    # Light only goes up to 5 sliders.  We have to obtain the other values through PWM cmd
    #   var pb_input = light.get(4).find('channels', [])[0]  # we can get PWM5 through light interface, but let us aim for consistency
    var pb_input = tasmota.cmd("pwm").find('PWM').find('PWM6')
    var pb       = low_pb + pb_input * (high_pb - low_pb) / 1023.0
    tasmota.cmd("PidPb " + str(pb))
    # do similar for PidTi (default 1800 seconds)
    var ti_input = tasmota.cmd("pwm").find('PWM').find('PWM7')
    var ti       = low_ti + ti_input * (high_ti - low_ti) / 1023.0
    tasmota.cmd("PidTi " + str(ti))
    # do similar for PidTd (default 15 seconds, should generally be about 25% of Ti once it has been optimised)
    var td_input = tasmota.cmd("pwm").find('PWM').find('PWM8')
    var td       = low_td + td_input * (high_td - low_td) / 1023.0
    tasmota.cmd("PidTd " + str(td))

    var sensorResult   = json.load(tasmota.read_sensors())
    var heatsinktemp   = sensorResult.find('DS18B20-1', []).find('Temperature', 30) # Default value provided for when reading fails
    var ambienttemp    = sensorResult.find('DS18B20-2', []).find('Temperature', 20) # Default value provided for when reading fails
    var internaltemp   = sensorResult.find('ANALOG', []).find('Temperature1', 0)    # Default value provided for when reading fails
    var internaltemp_last = sensorResult.find('PID', []).find('PidPv', 0)           # Default value provided for when reading fails

    print("internaltemp=",internaltemp, "internaltemp_last=",internaltemp_last)
    internaltemp = internaltemp/temp_avg + internaltemp_last*(temp_avg-1.0)/temp_avg
    print(" ---> PidPV " + str(internaltemp))
    tasmota.cmd("PidPV " + str(internaltemp))

    # this will be the wrong value first loop through, but will be updated within a second:
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
    print("temp=",internaltemp, "setpoint(channel2[0-100])=", setpoint, "Pb(pwm6[0-1023])=", pb, "Ti(pwm7[0-1023])=", ti, "Td(pwm8[0-1023])=", td)
    print ("is_idle=", self.is_idle, "power_time=", power_time, "power=", power, "demand=", cooling_demand, "internalfan=", internalfan, "deltat=",heatsinktemp - ambienttemp, "externalfan=", externalfan)
    if (power != "wait")
      tasmota.cmd("power1 " + power)
    end
    # channel2 (PWM1) is our setpoint temperature slider
    tasmota.cmd("channel3 " + str(cooling_demand)) # PWM2
    tasmota.cmd("channel4 " + str(cooling_demand)) # PWM3
    tasmota.cmd("channel5 " + str(internalfan))    # PWM4
#    tasmota.cmd("channel5 " + str(externalfan))    # PWM4   - currently overridden with external fan to quieten down the variations.  Want to blend them instead
    tasmota.cmd("channel6 " + str(externalfan))    # PWM5
  end
end

fridgeDriver = FridgeDriver()
