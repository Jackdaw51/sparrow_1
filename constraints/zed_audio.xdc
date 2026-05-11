# timing constraints
create_clock -period 10.000 -name clk_100 [get_ports clk_100]

set_false_path -from [get_clocks zed_audio_clk_48M] -to [get_clocks clk_100]
set_false_path -from [get_clocks clk_100] -to [get_clocks zed_audio_clk_48M]


# 100 mhz clock
set_property PACKAGE_PIN Y9 [get_ports clk_100]
set_property IOSTANDARD LVCMOS33 [get_ports clk_100]

# 24 mhz clock to audio chip
set_property PACKAGE_PIN AB2 [get_ports AC_MCLK]
set_property IOSTANDARD LVCMOS33 [get_ports AC_MCLK]


# I2S transfers audio samples
# i2s bit clock to ADAU1761
set_property PACKAGE_PIN Y8 [get_ports AC_GPIO0]
set_property IOSTANDARD LVCMOS33 [get_ports AC_GPIO0]

# i2s bit clock from ADAU1761
set_property PACKAGE_PIN AA7 [get_ports AC_GPIO1]
set_property IOSTANDARD LVCMOS33 [get_ports AC_GPIO1]

# i2s bit clock from ADAU1761
set_property PACKAGE_PIN AA6 [get_ports AC_GPIO2]
set_property IOSTANDARD LVCMOS33 [get_ports AC_GPIO2]

# i2s l/r 48 khz toggling signal from ADAU1761 (sample clock)
set_property PACKAGE_PIN Y6 [get_ports AC_GPIO3]
set_property IOSTANDARD LVCMOS33 [get_ports AC_GPIO3]


# OLED display
set_property PACKAGE_PIN U10  [get_ports {oled_dc}];  # "OLED-DC"
set_property PACKAGE_PIN U9   [get_ports {oled_res}];  # "OLED-RES"
set_property PACKAGE_PIN AB12 [get_ports {oled_sclk}];  # "OLED-SCLK"
set_property PACKAGE_PIN AA12 [get_ports {oled_sdin}];  # "OLED-SDIN"
set_property PACKAGE_PIN U11  [get_ports {oled_vbat}];  # "OLED-VBAT"
set_property PACKAGE_PIN U12  [get_ports {oled_vdd}];  # "OLED-VDD"


# User Switches - Bank 35 / 34
set_property PACKAGE_PIN F22 [get_ports {sw_in[0]}];  # "SW0"
set_property PACKAGE_PIN G22 [get_ports {sw_in[1]}];  # "SW1"
set_property PACKAGE_PIN H22 [get_ports {sw_in[2]}];  # "SW2"
set_property PACKAGE_PIN F21 [get_ports {sw_in[3]}];  # "SW3"
set_property PACKAGE_PIN H19 [get_ports {sw_in[4]}];  # "SW4"
set_property PACKAGE_PIN H18 [get_ports {sw_in[5]}];  # "SW5"
set_property PACKAGE_PIN H17 [get_ports {sw_in[6]}];  # "SW6"
set_property PACKAGE_PIN M15 [get_ports {sw_in[7]}];  # "SW7"
# Set IOSTANDARD for all switches
set_property IOSTANDARD LVCMOS25 [get_ports {sw_in[*]}]


# User Push Buttons - Bank 34 / 35
set_property PACKAGE_PIN P16 [get_ports {btn_in[0]}];   # "BTNC"
set_property PACKAGE_PIN T18 [get_ports {btn_in[1]}];   # "BTNU"
set_property PACKAGE_PIN R16 [get_ports {btn_in[2]}];   # "BTND"
set_property PACKAGE_PIN N15 [get_ports {btn_in[3]}];   # "BTNL"
set_property PACKAGE_PIN R18 [get_ports {btn_in[4]}];   # "BTNR"
# Set IOSTANDARD for all buttons
set_property IOSTANDARD LVCMOS25 [get_ports {btn_in[*]}]


# LEDs - Bank 33
set_property PACKAGE_PIN T22 [get_ports {led_out[0]}];  # "LD0"
set_property PACKAGE_PIN T21 [get_ports {led_out[1]}];  # "LD1"
set_property PACKAGE_PIN U22 [get_ports {led_out[2]}];  # "LD2"
set_property PACKAGE_PIN U21 [get_ports {led_out[3]}];  # "LD3"
set_property PACKAGE_PIN V22 [get_ports {led_out[4]}];  # "LD4"
set_property PACKAGE_PIN W22 [get_ports {led_out[5]}];  # "LD5"
set_property PACKAGE_PIN U19 [get_ports {led_out[6]}];  # "LD6"
set_property PACKAGE_PIN U14 [get_ports {led_out[7]}];  # "LD7"
# Set IOSTANDARD to 3.3V for all LEDs
set_property IOSTANDARD LVCMOS33 [get_ports {led_out[*]}]


# PMOD JA - Bank 13 (3.3V)
set_property PACKAGE_PIN Y11  [get_ports {sm_pins[0]}];  # "JA1"
set_property PACKAGE_PIN AA11 [get_ports {sm_pins[1]}];  # "JA2"
set_property PACKAGE_PIN Y10  [get_ports {sm_pins[2]}];  # "JA3"
# Set IOSTANDARD to 3.3V
set_property IOSTANDARD LVCMOS33 [get_ports {sm_pins[*]}]



# I2C Data Interface to ADAU1761 (for configuration)
set_property PACKAGE_PIN AB4 [get_ports AC_SCK]
set_property IOSTANDARD LVCMOS33 [get_ports AC_SCK]

set_property PACKAGE_PIN AB5 [get_ports AC_SDA]
set_property IOSTANDARD LVCMOS33 [get_ports AC_SDA]

set_property PACKAGE_PIN AB1 [get_ports AC_ADR0]
set_property IOSTANDARD LVCMOS33 [get_ports AC_ADR0]

set_property PACKAGE_PIN Y5 [get_ports AC_ADR1]
set_property IOSTANDARD LVCMOS33 [get_ports AC_ADR1]

# Voltage settings
set_property IOSTANDARD LVCMOS18 [get_ports -of_objects [get_iobanks 34]];
set_property IOSTANDARD LVCMOS33 [get_ports -of_objects [get_iobanks 13]];
