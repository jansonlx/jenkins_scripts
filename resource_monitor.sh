#!/bin/bash -e
#
# Linux Resource Monitor (CPU & MEM)
#
# Janson, 01/Dec/2017
#
# Usage:
#   ./resource_monitor.sh -p <process_keyword> [-s <interval_in_seconds> -o <output_file>]
# Extra Features: 
#   --stop
#     to stop running this script (including all progresses with this script name) 
#   --nmon-stop
#     to stop running the nmon (Nigel's performance Monitor)


function current_time(){
    echo $(date +"%Y-%m-%d %H:%M:%S")
}


# Func: Define the log prefix, like '2017-12-01 12:12:12 [INFO] ...'
# Params: Log Level (ERROR|WARNING|INFO)
function log_prefix()
{
    if [[ $1 =~ ^.*[iI][nN][fF][oO].*$ ]]; then
        log_level="INFO"
    elif [[ $1 =~ ^.*[wW][aA][rR][nN].*$ ]]; then
        log_level="WARNING"
    elif [[ $1 =~ ^.*[eE][rR][rR].*$ ]]; then
        log_level="ERROR"
    else
        log_level="'$1' is NOT defined yet."
    fi
    echo "$(date +'%Y-%m-%d %H:%M:%S') [${log_level}]"
}


# Params: Log Content, Output File
function log_handle()
{
    log_content=$1
    output_file=$2
    if [[ "${output_file}" ]]; then
        echo -e "${log_content}" | tee -a "${output_file}"
    else
        echo -e "${log_content}"
    fi
}


function param_work()
{
    arr=("$@")
    for i in ${!arr[*]}
    do
        if [[ ${arr[i]} =~ ^[^-].*$ ]]; then
            continue
        fi
        case "${arr[i]}" in
            -s)
                interval_in_seconds="${arr[i+1]}"
                ;;
            -p)
                process_name="${arr[i+1]}"
                ;;
            -o)
                output_file="${arr[i+1]}"
                ;;
            -rt)
                retry_times="${arr[i+1]}"
                ;;
            -ri)
                retry_interval="${arr[i+1]}"
                ;;
                # $0 means this script's name (including the path to the script)
            --stop)
                echo "$(log_prefix INFO) All processes from this script stopped."
                ps aux | grep "$(echo $0 | awk -F/ 'END{print $NF}')" | grep -v grep | awk '{print $2}' | xargs kill -9
                # Don't need 'exit' 'cause the command above will kill itself.
                #exit 0
                ;;
                # As extra feature - to kill nmon (Nigel's performance Monitor for Linux)
            --nmon-stop)
                pgrep nmon | xargs kill -9 >/dev/null 2>&1
                echo "$(log_prefix INFO) nmon process stopped."
                exit 0
                ;;
            *)
                echo "$(log_prefix WARNING) Param '${arr[i]}' doesn't exist (will ignore)"
                ;;
        esac
    done
    if [[ ! ${process_name} ]]; then
        echo -e "\n$(log_prefix ERROR) Should use with params: -p <process_keyword> [-s <interval_in_seconds> -o <output_file>]\n"
        exit 1
    fi
    if [[ ! ${interval_in_seconds} ]]; then
        interval_in_seconds=1
    fi
    if [[ ! ${output_file} ]]; then
        echo -e "\n$(log_prefix WARNNING) Won't save results as '-o <output_file>' doesn't specified."
    fi
    if [[ ! ${retry_times} ]]; then
        retry_times=10
    fi
    if [[ ! ${retry_interval} ]]; then
        retry_interval=2
    fi
}


# Handle the vars with this script
param_work "$@"


for retry in $(seq "${retry_times}")
do
    read pid_top pid_grep <<<$(ps aux | grep "${process_name}" | \
        grep -Ev "grep|bash" | \
        awk '{if (NR==1) {pid_top=$2; pid_grep=$2} \
            else {pid_top=pid_top","$2; pid_grep=pid_grep"|"$2}} \
            END {if (NR != 0) {print pid_top,pid_grep} else {print "none","none"}}');

    if [[ "${pid_top}" != "none" ]]; then
        pid_name=$(ps aux | grep "${process_name}" | grep -Ev "grep|bash" | sed -nr 's/^.+[0-9]:[0-9]{2}\s+([^0-9].+)$/\1/p')
        log_handle "$(log_prefix INFO) '${process_name}' matches:" "${output_file}"
        log_handle "${pid_name}" "${output_file}"

        #if [[ "${pid_top}" =~ ^[0-9]+,[0-9]+$ ]]; then
        #    echo -e "$(log_prefix WARNING) Several processes match '${process_name}', including:\n"
        #    # Show these: [pid] [command]... the results are added up by those processes matched.
        #fi
        break
    else
        if [[ "${retry}" -lt "${retry_times}" ]]; then
            printf "\r%s [WARNING] No process '%s' to find. Retry: %d/%d (every %ds)" "$(current_time)" "${process_name}" "${retry}" "$((retry_times - 1))" "${retry_interval}"
            sleep "${retry_interval}"
            continue
        else
            echo -e "\n"
            log_handle "$(log_prefix ERROR) No process '${process_name}' to find." "${output_file}"
            exit 1
        fi
    fi
done

log_handle "$(log_prefix INFO) Update info. every ${interval_in_seconds} second(s)." "${output_file}"

cpu_count=$(grep -c ^processor /proc/cpuinfo)
# KB to MB
mem_total=$(($(grep ^MemTotal /proc/meminfo | awk '{print $2}') / 1024))
monitor_title="TIMESTAMP          	%CPU	%MEM	MEM(MB)"
log_handle "${monitor_title}" "${output_file}"

while true; do
    monitor_data=$(top -b -n 1 -p "${pid_top}" | grep -E "^\s*(${pid_grep})" \
        | awk -v now="$(current_time)" \
            -v cpu_count="${cpu_count}" \
            -v mem_total="${mem_total}" \
            'BEGIN{mem_pid=0; cpu_pid=0;} \
            {{cpu_pid+=$9} if ($6~/[0-9]m/) {mem_pid+=$6;} else if ($6~/[0-9]g/) {mem_pid+=$6*1024;} else {mem_pid+=$6/1024;}} \
            END{printf("%s\t%.2f\t%.2f\t%.2f", now, cpu_pid/cpu_count, mem_pid/mem_total*100, mem_pid);}'
        )
    log_handle "${monitor_data}" "${output_file}"
    sleep "${interval_in_seconds}"
done

