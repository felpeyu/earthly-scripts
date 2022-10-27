#!/bin/bash
max_delta=400 # in seconds

# Captures metrics when delta (time between log lines) > max_delta
if [ $# -eq 0 ]; then
    echo "No arguments supplied"
    exit 1;
fi
if [[ $OSTYPE == 'darwin'* ]]; then
  for prog in sample grep ts tee stat bc gdate; do
    if ! command -v $prog &> /dev/null; then
      echo "$prog could not be found. Please install it to proceed"
      exit
    fi
  done
else
  for prog in gstack pstree grep ts tee stat bc; do
    if ! command -v $prog &> /dev/null; then
      echo "$prog could not be found. Please install it to proceed"
      exit
    fi
  done
fi

command_name="$1"
command="$@"
logs_folder=$HOME/.$command_name/logs
 if [[ $OSTYPE == 'darwin'* ]]; then
  ts_start=$(gdate +%s%N)
 else
   ts_start=$(date +%s%N)
 fi
pid_file="$logs_folder/$ts_start.pid"
logs_file="$logs_folder/$ts_start.log"
running_file="$logs_folder/$ts_start.running"
captures_folder="$logs_folder/$ts_start.captures"
samples_per_capture=100
capture_interval=10 # in seconds
wait_interval=$(bc <<< "scale=4; $capture_interval/$samples_per_capture")

# Each second it checks the last modified time of the log file. If this time is previous to the max_delta
# this means the no lines have been received from the process stderr and stdout, and a capture is triggered
monitor(){
  declare -i recorded=0
  while [ -f $running_file ]
  do
    now=$(date +%s)
     if [[ $OSTYPE == 'darwin'* ]]; then
       last_modified=$(stat -f %m $logs_file)
     else
       last_modified=$(stat --format %Y $logs_file)
     fi
    if [ $recorded -eq 0 ] && [ $now -gt $((last_modified + max_delta)) ]; then
      recorded=1
      capture
    fi
    if [ $recorded -eq 1 ] && [ $now -lt $((last_modified + max_delta)) ]; then
      recorded=0
    fi
    sleep 1
  done
}

# Captures process metrics and saves them to disk.
capture(){
  mkdir -p $captures_folder
  declare -i pid=$(cat $pid_file)
  if [[ $OSTYPE == 'darwin'* ]]; then
    last_modified=$(stat -f %m $logs_file)
  else
    last_modified=$(stat --format %Y $logs_file)
  fi
  for ((n=0;n<$samples_per_capture;n++)); do
    iteration="$last_modified-$n"
    if [[ $OSTYPE == 'darwin'* ]]; then
      sample $pid 10 -file "$captures_folder/$iteration.sample" 2>/dev/null
      nettop -l 10 -p $pid > "$captures_folder/$iteration.earthly.nettop" 2>/dev/null &
      nettop -l 10 > "$captures_folder/$iteration.global.nettop" 2>/dev/null &
    else
      gstack $pid > "$captures_folder/$iteration.gstack" 2>/dev/null
      pstree -pT $pid 2>/dev/null | grep -o '([0-9]\+)' | grep -o '[0-9]\+' |  xargs ps -o pid,ppid,etime,group,nice,pcpu,pgid,rgroup,ruser,time,tty,user,vsz,args -p > "$captures_folder/$iteration.pstree" 2>/dev/null
    fi
  done
 }

chain(){
  echo "Command: $command"
  $command &
  pid=$!
  echo $pid>$pid_file
  wait $pid
  echo "Finished";
  rm $running_file
}

start(){
  mkdir -p "$logs_folder"
  echo "Writing logs at: $logs_file"
  touch $running_file
  monitor &
  chain 2>&1 |ts '[%s]' |tee "$logs_file"
}

start