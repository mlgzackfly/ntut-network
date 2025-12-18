# Usage:
#   gnuplot -c scripts/plot_throughput.gp results/runs.csv results/throughput.png
#
# Input CSV columns:
# run_id,scenario,host,port,connections,threads,duration_s,total,ok,err,rps,p50_us,p95_us,p99_us

infile = ARG1
outfile = ARG2

set datafile separator comma
set terminal pngcairo size 1400,800 font "Sans,12"
set output outfile

set title "Throughput (requests/sec)"
set xlabel "Run (scenario)"
set ylabel "req/s"
set grid ytics
set key off

set xtics rotate by -45
set style data linespoints

plot infile using 0:11:xtic(2) lw 2



