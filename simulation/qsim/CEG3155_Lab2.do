onerror {quit -f}
vlib work
vlog -work work CEG3155_Lab2.vo
vlog -work work CEG3155_Lab2.vt
vsim -novopt -c -t 1ps -L cycloneive_ver -L altera_ver -L altera_mf_ver -L 220model_ver -L sgate work.alu_top_vlg_vec_tst
vcd file -direction CEG3155_Lab2.msim.vcd
vcd add -internal alu_top_vlg_vec_tst/*
vcd add -internal alu_top_vlg_vec_tst/i1/*
add wave /*
run -all
