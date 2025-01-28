#/bin/bash -e

# This script searches HyperBackup or ActiveBackup logs to determine
#   the last time a specified backup task completed successfully
# That timestamp is then submitted to Icinga along with an OK
#   if the task was completed within the last number of hours
#   specified by the -w value, WARNING if between the values of
#   -w and -c, and CRITICAL for values over that.
# If no value is given for -w it will be set to -c.
# For that submission to work, the following have to be true:
# - Icinga API enabled and accessible
# - Icinga API user specified with rights to submit that passive
#   check result
# - The service name matches a service in Icinga
# - The host name matches the name of the host to which that
#   service is assigned
# It uses curl to submit the result and does not require that NRPE
# be installed on the Synology NAS
# If the Service in Icinga has both active and passive checks enabled
#   Icinga can alert the administrator if either
# - A Critical service check is received
# - No service check is received in more than check_interval
# This script can and should be used as a scheduled task on the Synology NAS

# This script assumes that ActiveBackup files are in /volume1/@ActiveBackup/
#   Adjust as needed

# v1.1 improved by Anton Daudrich www.admin-box.de
# v1.2 improved by Simon Hätty www.admin-box.de
# v1.3 improved by Simon Hätty www.admin-box.de
# v1.4 improved by Simon Hätty www.admin-box.de
# v1.5 improves by Sascha Jelinek www.admin-box.de - Change Output for Checkmk local check

function usage {
cat <<EOM
Usage: $(basename "$0") [OPTION]...
  Spaces should be quoted or escaped

Options:
  -s Service name    Service as named in Icinga
                     Spaces will be replaced with %20
                     Other special characters may need
                       to be replaced manually
  -t Task name       Name of the backup task to check
                       the logs for
  -a Application     Backup application used
                       AB for ActiveBackup
                       HB for HyperBackup
  -v               list VMs in backup task
  -b Path          ActiveBackup Path
                       Defaults to /volume1/@ActiveBackup
  -n host            Name of the host to which the
                     service is assigned in Icinga
  -w value         WARNING threshold in hours. If the
                     last successful backup occurred
                     more than this number of hours
                     in the past, a WARNING status
                     will be sent to Icinga
  -c value         CRITICAL threshold in hours. If the
                     last successful backup occurred
                     more than this number of hours
                     in the past, a CRITICAL status
                     will be sent to Icinga
                      Must be higher than Warning
                     threshold
  -i url           Icinga protocol, host and port
                     e.g. https://192.168.1.1:5665
                     Note: no trailing slash
  -u username      Icinga API User name
  -p password      Icinga API Password
  -h               Display help
EOM
exit 2
}

# default values
check_vm=0

while getopts ":s:t:a:n:w:i:u:p:c:v:" optKey; do
        case "$optKey" in
                b)
                        ABPath=$OPTARG
                        ;;
                s)
                        ServiceName=$OPTARG
                        ;;
                t)
                        TaskName=$OPTARG
                        ;;
                a)
                        BackupType=$OPTARG
                        ;;
                n)
                        HostName=$OPTARG
                        ;;
                w)
                        WarningHours=$OPTARG
                        ;;
                c)
                        CriticalHours=$OPTARG
                        ;;
                i)
                        IcingaURL=$OPTARG
                        ;;
                u)
                        IcingaUser=$OPTARG
                        ;;
                p)
                        IcingaPass=$OPTARG
                        ;;
                v)
                        check_vm=1
                        ;;
                h|*)
                        usage
                        ;;
        esac
done

#[[ "$ServiceName" == "" ]] && echo Error: && echo -s is required && echo && usage
[[ "$TaskName" == "" ]] && echo Error: && echo -t is required && usage
[[ "$BackupType" != "AB" ]] && [[ "$BackupType" != "HB" ]] && echo Error: && echo Invalid backup type && echo && usage
#[[ "$HostName" == "" ]] && echo Error: && echo -n is required && usage
[[ "$CriticalHours" == "" ]] && echo Error: && echo -c is required && echo && usage
[[ "$WarningHours" == "" ]] && WarningHours=$CriticalHours
[[ "$WarningHours" -gt "$CriticalHours" ]] && echo Error: && echo -w must be smaller than or equal to -c && usage
#[[ "$IcingaURL" == "" ]] && echo Error: && echo -i is required && usage
#[[ "$IcingaUser" == "" ]] && echo Error: && echo -u is required && usage
#[[ "$IcingaPass" == "" ]] && echo Error: && echo -p is required && usage
[[ "$BackupType" == "AB" ]] && [[ "$ABPath" == "" ]] && ABPath='/volume1/@ActiveBackup'

# temp output file for SQL Query Result
TEMPFILE=/tmp/sqliteQueryResult.out.${RANDOM}.temp
PerformanceData=""

function query_sqlite() {
  i=1
  while [ $i -le 12 ]; do
    #echo Querying sqlite. Attempt number: ${i}/12

    # check VM
        if [ ${check_vm} -eq 1 ]; then
             #sqlite3 ${ABPath}/activity.db "SELECT result_table.time_end,task_name,device_name,transfered_bytes FROM result_table LEFT JOIN device_result_table ON device_result_table.result_id = result_table.result_id WHERE result_table.time_end = (SELECT MAX(time_end) FROM result_table WHERE task_name = '$TaskName') AND task_name = '$TaskName' AND transfered_bytes IS NOT NULL ORDER BY result_table.time_end ASC" > $TEMPFILE
             sqlite3 ${ABPath}/activity.db "SELECT result_table.time_end,task_name,device_name,transfered_bytes,error_count FROM result_table LEFT JOIN device_result_table ON device_result_table.result_id = result_table.result_id WHERE result_table.time_end = (SELECT MAX(result_table.time_end) FROM result_table INNER JOIN device_result_table ON device_result_table.result_id = result_table.result_id WHERE task_name = '${TaskName}') AND task_name = '${TaskName}' AND transfered_bytes IS NOT NULL ORDER BY result_table.time_end ASC" > $TEMPFILE
       Exit_Code_Query=$?

     # check Fileserver
     else
      sqlite3 ${ABPath}/activity.db "SELECT result_table.time_end,task_name,device_name,transfered_bytes,error_count FROM result_table LEFT JOIN device_result_table ON device_result_table.result_id = result_table.result_id WHERE task_name = '${TaskName}' AND transfered_bytes IS NOT NULL ORDER BY result_table.time_end DESC LIMIT 1" > $TEMPFILE
      Exit_Code_Query=$?
    fi

          LastSuccessUnixFmt=$(cat $TEMPFILE|cut -f1 -d '|'|uniq)
    if [ $Exit_Code_Query == 0 ]; then
      #echo Successfully queried database
      LastSuccessDate=$(date --date @$LastSuccessUnixFmt)
    elif [ $Exit_Code_Query == 5 ]; then
      #echo Database is locked.
      i=$(expr $i + 1)
      sleep 5
      continue
    fi
    break
  done
  if [[ $i -ge 6 ]] && [[ "$LastSuccessDate" == "" ]]; then
    #echo Could not get a last successful backup timestamp from the database. Will send CRITICAL status to Icinga
    Output="Timeout querying ActiveBackup database"
  fi

}

if [[ $CriticalHours < $WarningHours ]]; then
  ExitStatus=2
  echo Critical threshold must be same or higher than Warning threshold
fi

Now=$(date +%s)
WarningHoursUnixFmt=$(expr $WarningHours \* 60 \* 60)
CriticalHoursUnixFmt=$(expr $CriticalHours \* 60 \* 60)
WarningThreshold=$(expr $Now - $WarningHoursUnixFmt)
CriticalThreshold=$(expr $Now - $CriticalHoursUnixFmt)

ServiceName=$(echo $ServiceName | sed 's/ /%20/g')
case $BackupType in
  HB) #echo Backup type: HyperBackup
      SearchString="Backup task finished successfully."
      LastSuccessDate=$(grep "$TaskName" /var/log/synolog/synobackup.log | grep "$SearchString" | tail -1 | awk '{print $2 " " $3}')
      LastSuccessUnixFmt=$(date --date="$LastSuccessDate" +"%s")
          ;;
  AB) #echo Backup type: ActiveBackup
      query_sqlite
          ;;
esac
IFS=$'\n'       # make newlines the only separator
set -f          # disable globbing
fail=0
if [[ "$LastSuccessDate" != "" ]]; then
  Output="Last backup $TaskName: $LastSuccessDate";
  for line in $(cat $TEMPFILE); do
                transfered=$(echo $line|cut -f4 -d'|' | tr -d ' ')
                transfered_perf=$(echo $line|cut -f4 -d'|'|awk '{$1=$1/1024**2; print $1,"MB";}'|tr -d ' ')
        if [[ $transfered -lt 1073741824 ]]; then
                        transfered_MB=$(echo $line|cut -f4 -d'|'|awk '{$1=$1/1024**2; print $1,"MB";}'|tr -d ' ')
                else
                        transfered_MB=$(echo $line|cut -f4 -d'|'|awk '{$1=$1/1024**3; print $1,"GB";}'|tr -d ' ')
                fi
        check_error=$(echo $line|cut -f5 -d'|')
    Output=$(echo $Output"\n"$(echo $line|cut -f3 -d '|') $transfered_MB)
        PerformanceData=$(echo $PerformanceData"|"$(echo $line|cut -f3 -d '|')=$transfered_perf)
        if [[ $check_error > 0 ]]; then
                fail=1
        fi
  done

  if [[ $LastSuccessUnixFmt < $CriticalThreshold ]] ||[[ $fail = 1 ]]; then
    ExitStatus=2
  elif [[ $LastSuccessUnixFmt < $WarningThreshold ]]; then
    ExitStatus=1
  else
    ExitStatus=0
  fi
else
  #echo Could not determine last successful backup date, will submit CRITICAL response to Icinga
  Output="Last backup: Unknown"
  ExitStatus=2
fi

LastSuccessUnixForm=$(cat $TEMPFILE|cut -f1 -d '|'|uniq)
LastSuccessTime=$(expr $Now - $LastSuccessUnixForm)
LastSuccessHours=$(expr $LastSuccessTime \/ 60 \/ 60)
if [[ $LastSuccessHours -lt 1 ]]; then
        LastSuccessHours=0;
fi

echo $ExitStatus \"$BackupType $TaskName\" hours=$LastSuccessHours";"$WarningHours";"$CriticalHours""$PerformanceData $Output
#echo $Output
#exit $ExitStatus
