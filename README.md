# PWM (eg Peltier) Fridge Controller

## Design

Using a [4
channel](https://vi.aliexpress.com/item/1005006825918157.html)
logic-level MOSFET with many amps capacity per channel, I wanted to
overhaul a peltier fridge with a dead powersupply.  I've got the
internal fan and heatsink fan plugged into two channels, and each of
the peltier coolers, 4A each, plugged into the other two channels for
load balancing (putting a heatsink on those mosfets will be a pain
because the tabs are the output switched ground).

I've taken the 10k thermister from the inside of the fridge and
plugged it into one of the ADC GPIOs.  I've added 2 other DS18x20
1-wire temperature sensors, one reading the heatsink's temperature,
and the other reading "ambient" (or at least, inside the case of the
back of the fridge, maybe reading a couple of degrees above ambient if
the peltier is pelting.

Finally, I'm running all this from a XBOX one power supply, that
outputs 5v standby, and switched 12v.  The switch handily takes 3.3v
signal voltage, so I enable the power supply when there's been demand
on any of the PWM channels for at least 10 seconds, and switch it back
off when there's been no demand for 10 seconds.

And I'm running all this from an [ESP32
devkit](https://vi.aliexpress.com/item/33009178296.html) running
Tasmota, with PID controller compiled in.  My
[user_config_override.h](user_config_override.h) is included in this
repo.

After the kit was given a basic config with GPIOs per
[wiring.txt](wiring.txt), I ran ansible over it using my [Ansible
config](https://github.com/spacelama/ansible-initial-server-setup) to
configure all the parameters and their names (for Home Assistant's
benefit).

Upload [autoexec.be](autoexec.be) to the Tasmota filesystem to be
interpreted by Berry script at bootup, and you have a peltier fridge!
On the device webpage [http://fridge1](http://fridge1) if you go by
the rest of my ansible setup), the first slider is your setpoint
temperature (unlabelled).  When twiddled, the setpoint value is
reflected in the "Set Point" field.  The next 3 sliders are the
instantaneous demand values at time of page-load, for the peltier
cooler and internal fan (slightly offset from the coolers themselves),
and the final slider is the demand for the external heatsink, which is
more a function of the difference in temperature between heatsink and
ambient (ie, how hard we should be driving the fan to extract excess
heat from it).

PID loop tuning is done by writing to PWM6, PWM7 and PWM8 per
[wiring.txt](wiring.txt).  Default tuning of the PID loop is to have a
time constant of half an hour, and a proportional band of 1.5degrees.
If your fridge can't keep up, you probably want to slow that down a
bit (but that will take code change, because that represents the
maximum values I allowed for those PWM.  Adjust Pb, Ti and Td by
writing 0-1023 to each of PWM6 (Pb, scaled to 0-5degrees), PWM7 (Ti,
scaled to 0-1800 seconds) and PWM8 (Td, scaled to 0-450 seconds).
