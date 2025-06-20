proc generate_fsbl {} {
	set fsbl_design [hsi::create_sw_design fsbl_1 -proc psu_cortexa53_0 -app zynqmp_fsbl]
	common::set_property APP_COMPILER "aarch64-none-elf-gcc" $fsbl_design
	common::set_property -name APP_COMPILER_FLAGS -value "-DRSA_SUPPORT -DFSBL_DEBUG_INFO -DXPS_BOARD_ZCU102" -objects $fsbl_design
	hsi::generate_app -dir zynqmp_fsbl -compile
	return "zynqmp_fsbl/executable.elf"
}

#Generate ZynqMP PMUFW
proc generate_pmufw {} {
	hsi::generate_app -app zynqmp_pmufw -proc psu_pmu_0 -dir pmu_fw -compile
	return "pmu_fw/executable.elf"
}

#Open HW
proc open_hw {hdf} {
	hsi::open_hw_design $hdf
}

#Close HW
proc close_hw {} {
	hsi::close_hw_design [hsi::current_hw_design]
}

proc phy_read {args} {
	set addr [string range [lindex $args 0] 2 [expr {[string length [lindex $args 0]]-1}]]
	set reg [string range [lindex $args 1] 2 [expr {[string length [lindex $args 1]]-1}]]
	binary scan [binary format H* $addr] B* bits
	set phy_addr [string range $bits 3 [expr {[string length $bits]-1}]]
	binary scan [binary format H* $reg] B* bits
	set phy_reg [string range $bits 3 [expr {[string length $bits]-1}]]
	set write_command "0110${phy_addr}${phy_reg}100000000000000000"
	mwr 0xff0e0034 0x[bin2hex $write_command]
	set data [split [mrd 0xff0e0034] " "]
	return [string range [lindex $data [expr {[llength $data]-1}]] 4 7]
	
}

proc bin2hex bin {
    ## No sanity checking is done
    array set t {
	0000 0 0001 1 0010 2 0011 3 0100 4
	0101 5 0110 6 0111 7 1000 8 1001 9
	1010 a 1011 b 1100 c 1101 d 1110 e 1111 f
    }
    set diff [expr {4-[string length $bin]%4}]
    if {$diff != 4} {
        set bin [format %0${diff}d$bin 0]
    }
    regsub -all .... $bin {$t(&)} hex
    return [subst $hex]
}

proc get_phy_addr {} {
	for {set i 0} {$i < 32} {incr i} {
		set temp_addr 0x[format %02X $i]
		set phy_addr [phy_read $temp_addr 0x01]
		if {$phy_addr != "FFFF" && $phy_addr != "0000"} {
			return $i
		}
	}
	puts "PHY Address Not Found"
	return -1
}

proc init_man_port {} {
	mwr 0xff0e0004 0x001c0000
	after 500
	mwr 0xff0e0000 0x00000010
	after 500
}

open_hw system.hdf
if {[file exists pmu_fw/executable.elf] == 1} {
	set pmufw "pmu_fw/executable.elf"
} else {
	set pmufw [generate_pmufw]
}
if {[file exists zynqmp_fsbl/executable.elf] == 1} {
	set fsbl "zynqmp_fsbl/executable.elf"
} else {
	set fsbl [generate_fsbl]
}
close_hw
connect
targets -set -filter {name =~ "PSU"}
mwr 0xffca0038 0x1FF
targets -set -filter {name =~ "MicroBlaze PMU"}
dow $pmufw
con
targets -set -filter {name =~ "PSU"}
# write bootloop and release A53-0 reset
mwr 0xffff0000 0x14000000
mwr 0xFD1A0104 0x380E
exec sleep 1
mrd 0xff0e0034
# download and run FSBL
targets -set -filter {name =~ "Cortex-A53 #0"}
# downloading FSBL
dow $fsbl
con
after 500
stop
init_man_port
set phy_addr "0x0[format %X [get_phy_addr]]"
puts "Phy Address is: $phy_addr"
puts "To read a PHY Reg, use the command below:"
puts "phy_read $phy_addr 0x<phy register>"



