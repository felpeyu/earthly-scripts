#!/bin/bash
# Gets aggregation metrics from a log file generated with earthly-debug.sh
log_file=$1
declare -i min_elapse=$2
declare -i ts0=$(date +%s)
declare -i max_delta=0
declare -i start_ts=0
declare -i end_ts=0
declare satellite
while read -r line
do
  ts=${line:1:10}
  end_ts=$ts
  if [ $start_ts -eq 0 ]; then
    start_ts=$ts
  fi
  delta=$((ts-ts0))
  if [ -z "$satellite" ];  then
    if [ "$line" != "${line/Connecting/}" ]; then
      satellite=${line:50:-3}
    fi
  fi
  if [ $min_elapse -gt 0 ] && [ $delta -ge $min_elapse ]; then
    echo "$line0"
    printf "\n<$delta s>\n"
    echo "$line"
  fi
  if [ $delta -gt $max_delta ]; then
    max_delta=$delta;
  fi
  ts0=$ts
  line0=$line
done < "$log_file"
printf "max_delta: $max_delta s, satellite: $satellite, start_ts: $start_ts, elapsed: $((end_ts-start_ts)) s, log_file: $log_file \n"
