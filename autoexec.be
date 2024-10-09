import json

# Peltier cooler function

class FridgeDriver
  var has_started
  def init()
    tasmota.remove_driver(global.fridgedriver_instance)
    global.fridgedriver_instance = self
    tasmota.add_driver(global.fridgedriver_instance)

    self.has_started = 0
  end
  def every_second()

    var low_peltier         = 10      # peltier is turned off below this demand%
    var low_internal_fan    = 20      # internal fan is turned to this value between low_peltier and this demand%
    var low_external_fan    = 20      # external fan is turned off below this demand%
    var heatsink_multiplier = 2       # fan is turned to this percent% multiplied by the difference in temperature between ambient and heatsink temperature
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

    var sensorResult = json.load(tasmota.read_sensors())
    var demand       = 100*(1-sensorResult.find('PID', []).find('PidPower', 1)) # Default value to know that reading failed
    if (demand < low_peltier)
      demand = 0
    end
    var heatsinktemp = sensorResult.find('DS18B20-1', []).find('Temperature', 30) # Default value to know that reading failed
    var ambienttemp  = sensorResult.find('DS18B20-2', []).find('Temperature', 20) # Default value to know that reading failed
    var insidefan    = demand
    if ((insidefan < low_internal_fan) && (insidefan > low_peltier))
      insidefan = low_internal_fan
    end
    var outsidefan   = (heatsinktemp - ambienttemp)*3
    if (outsidefan > 100)
      outsidefan = 100
    end
    if (outsidefan < low_external_fan)
      outsidefan = 0
    end

    print ("demand, insidefan, deltat, outsidefan=", demand, insidefan, (heatsinktemp - ambienttemp), outsidefan)
    tasmota.cmd("channel1 " + str(demand))
    tasmota.cmd("channel2 " + str(insidefan))
    tasmota.cmd("channel3 " + str(outsidefan))
  end
end

fridgeDriver = FridgeDriver()
