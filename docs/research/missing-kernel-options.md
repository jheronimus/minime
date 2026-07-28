# Missing Kernel Options

Valid, non-duplicated config options relevant to Anbernic handhelds that are
not yet in the board fragments. Add after confirming the device boots.

## RK3326 (RG351V / RG351MP)

```
CONFIG_JOYSTICK_ADC=y          # analog stick via ADC
CONFIG_SND_SIMPLE_CARD=y        # audio card binding
CONFIG_SND_SOC_ES8316=y         # ES8316 audio codec (RG351V)
CONFIG_SND_SOC_ROCKCHIP_I2S=y   # I2S audio controller
CONFIG_SND_SOC_SIMPLE_AMPLIFIER=y  # external speaker amplifier
CONFIG_RTC_DRV_RK808=y          # RK808 PMIC RTC
```

## RK3566 (RG353M / RG353P)

```
CONFIG_PHY_ROCKCHIP_INNO_HDMI=y  # HDMI PHY (RG353P has mini-HDMI)
CONFIG_BACKLIGHT_LED=y            # LED-based backlight
```

## H700 (RG35XX Plus)

```
CONFIG_BACKLIGHT_GPIO=y  # GPIO-driven backlight
```
