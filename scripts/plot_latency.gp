# Usage:
#   gnuplot -c scripts/plot_latency.gp results/runs.csv results/latency.png
#
# Input CSV columns:
# run_id,scenario,host,port,connections,threads,duration_s,total,ok,err,rps,p50_us,p95_us,p99_us

infile = ARG1
outfile = ARG2

set datafile separator comma
set terminal pngcairo size 1400,800 font "Sans,12"
set output outfile

set title "Latency (microseconds) - p50 / p95 / p99"
set xlabel "Run (scenario)"
set ylabel "Latency (us)"
set grid ytics
set key outside right

set xtics rotate by -45

# Use run index on x, label with scenario
set style data linespoints

plot \
  infile using 0:12:xtic(2) title "p50" lw 2, \
  infile using 0:13 title "p95" lw 2, \
  infile using 0:14 title "p99" lw 2



