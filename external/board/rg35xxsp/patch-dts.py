#!/usr/bin/env python3
import sys
import os

def main():
    if len(sys.argv) < 2:
        print("Usage: patch-dts.py <dts-file-path>")
        sys.exit(1)
        
    path = sys.argv[1]
    if not os.path.exists(path):
        print(f"Error: DTS file not found at {path}")
        sys.exit(1)
        
    with open(path, "r") as f:
        text = f.read()

    # 0. Patch aliases for MMC mapping
    aliases_old = "\taliases {\n\t\tserial0 = &uart0;\n\t};"
    aliases_new = "\taliases {\n\t\tserial0 = &uart0;\n\t\tmmc0 = &mmc0;\n\t\tmmc1 = &mmc1;\n\t};"
    if aliases_old in text:
        text = text.replace(aliases_old, aliases_new)
        print("Patched aliases for MMC.")
        
    # 1. Patch GPU node
    gpu_old = "&gpu {\n\tmali-supply = <&reg_dcdc2>;\n\tstatus = \"okay\";\n};"
    gpu_new = "&gpu {\n\tmali-supply = <&reg_dcdc2>;\n\toperating-points-v2 = <&gpu_opp_table>;\n\tstatus = \"okay\";\n};"
    if gpu_old in text:
        text = text.replace(gpu_old, gpu_new)
        print("Patched GPU node.")
        
    # 2. Patch DCDC2 regulator limits
    dcdc2_old = "regulator-min-microvolt = <940000>;\n\t\t\t\tregulator-max-microvolt = <940000>;"
    dcdc2_new = "regulator-min-microvolt = <900000>;\n\t\t\t\tregulator-max-microvolt = <960000>;"
    if dcdc2_old in text:
        text = text.replace(dcdc2_old, dcdc2_new)
        print("Patched DCDC2 microvolts.")
        
    # 3. Patch pio (backlight pin function)
    pio_old_patched = "&pio {\n\tvcc-pa-supply = <&reg_cldo3>;\n\tvcc-pc-supply = <&reg_cldo3>;\n\tvcc-pd-supply = <&reg_cldo3>;\n\tvcc-pe-supply = <&reg_cldo3>;\n\tvcc-pf-supply = <&reg_cldo3>;\n\tvcc-pg-supply = <&reg_aldo4>;\n\tvcc-ph-supply = <&reg_cldo3>;\n\tvcc-pi-supply = <&reg_cldo3>;\n};"
    pio_new_patched = "&pio {\n\tvcc-pa-supply = <&reg_cldo3>;\n\tvcc-pc-supply = <&reg_cldo3>;\n\tvcc-pd-supply = <&reg_cldo3>;\n\tvcc-pe-supply = <&reg_cldo3>;\n\tvcc-pf-supply = <&reg_cldo3>;\n\tvcc-pg-supply = <&reg_aldo4>;\n\tvcc-ph-supply = <&reg_cldo3>;\n\tvcc-pi-supply = <&reg_cldo3>;\n\n\tlcd_backlight_pin: pwm0-pin {\n\t\tpins = \"PD28\";\n\t\tfunction = \"pwm0\";\n\t};\n};"
    pio_old_unpatched = "&pio {\n\tvcc-pa-supply = <&reg_cldo3>;\n\tvcc-pc-supply = <&reg_cldo3>;\n\tvcc-pe-supply = <&reg_cldo3>;\n\tvcc-pf-supply = <&reg_cldo3>;\n\tvcc-pg-supply = <&reg_aldo4>;\n\tvcc-ph-supply = <&reg_cldo3>;\n\tvcc-pi-supply = <&reg_cldo3>;\n};"
    pio_new_unpatched = "&pio {\n\tvcc-pa-supply = <&reg_cldo3>;\n\tvcc-pc-supply = <&reg_cldo3>;\n\tvcc-pe-supply = <&reg_cldo3>;\n\tvcc-pf-supply = <&reg_cldo3>;\n\tvcc-pg-supply = <&reg_aldo4>;\n\tvcc-ph-supply = <&reg_cldo3>;\n\tvcc-pi-supply = <&reg_cldo3>;\n\n\tlcd_backlight_pin: pwm0-pin {\n\t\tpins = \"PD28\";\n\t\tfunction = \"pwm0\";\n\t};\n};"
    if pio_old_patched in text:
        text = text.replace(pio_old_patched, pio_new_patched)
        print("Patched PIO nodes (with vcc-pd-supply).")
    elif pio_old_unpatched in text:
        text = text.replace(pio_old_unpatched, pio_new_unpatched)
        print("Patched PIO nodes (without vcc-pd-supply).")
        
    # 4. Append PWM, backlight, HDMI, DE, TCON nodes (only if not already present)
    if "gpu_opp_table:" not in text:
        append_block = """
/ {
	gpu_opp_table: opp-table-1 {
		compatible = "operating-points-v2";

		opp-420000000 {
			opp-hz = /bits/ 64 <420000000>;
			opp-microvolt = <900000>;
		};
		opp-456000000 {
			opp-hz = /bits/ 64 <456000000>;
			opp-microvolt = <900000>;
		};
		opp-504000000 {
			opp-hz = /bits/ 64 <504000000>;
			opp-microvolt = <900000>;
		};
		opp-552000000 {
			opp-hz = /bits/ 64 <552000000>;
			opp-microvolt = <900000>;
		};
		opp-600000000 {
			opp-hz = /bits/ 64 <600000000>;
			opp-microvolt = <900000>;
		};
		opp-648000000 {
			opp-hz = /bits/ 64 <648000000>;
			opp-microvolt = <960000>;
		};
	};

	backlight: backlight {
		compatible = "pwm-backlight";
		pwms = <&pwm 0 40000 0>;
		brightness-levels = <0 4 8 16 32 64 128 160 200 230 255>;
		default-brightness-level = <8>;
		pinctrl-names = "default";
		pinctrl-0 = <&lcd_backlight_pin>;
	};
};

&pwm {
	allwinner,pwm-paired-channel-clock-sources = "hosc", "hosc", "hosc";
	allwinner,pwm-paired-channel-clock-prescales = <0>, <0>, <0>;
	status = "okay";
};

&hdmi {
	status = "okay";
};

&hdmi_out {
	hdmi_out_con: endpoint {
		remote-endpoint = <&hdmi_con_in>;
	};
};

&de {
	status = "okay";
};

&tcon_lcd0 {
	status = "okay";
};

&tcon_lcd0_out_lcd {
	remote-endpoint = <&panel_in_rgb>;
};
"""
        text += append_block
        print("Appended device tree extension nodes.")
        
    with open(path, "w") as f:
        f.write(text)
        
    print("DTS patching complete.")

if __name__ == "__main__":
    main()
