#!/bin/bash

##########################################################
#
# Скрипт предназначен для анализа журналов регистрации,
# имеющихся на локальном сервере 1С:Предприятия
# Использование: ./1cjolurnals_du.sh
#
##########################################################



# find 1C services
UNIT_NAME=`systemctl list-unit-files --type=service --state=enabled --no-pager --no-legend | grep srv1c | awk '{print $1}'`
SRV1CV8_REGPORT=`systemctl cat $UNIT_NAME --no-pager | grep -oP '^Environment=SRV1CV8_REGPORT=\K[^\s]+'`
SRV1CV8_DATA=`systemctl cat $UNIT_NAME --no-pager | grep -oP '^Environment=SRV1CV8_DATA=\K[^\s]+'`
SRV1CV8_BIN=`systemctl cat $UNIT_NAME --no-pager | grep -oP '^ExecStart=\K[^\s]+'`

if [ ! -f "$SRV1CV8_BIN" ]; then
   echo "Исполняемый файл 1С не найден."
   exit 1
fi

SRV1CV8_DIR=`dirname $SRV1CV8_BIN`

if [ ! -f "$SRV1CV8_DIR/rac" ]; then
   echo "Исполняемый файл 1С rac не найден."
   exit 2
fi

RAC="${SRV1CV8_DIR}/rac"

OUTPUT=`$RAC cluster list 2> >(stderr=$(cat) >&2)`

[ -n "$stderr" ] && echo "Не удалось подключиться к серверу 1С RAS" && exit 3

CLUSTER_ID=`echo "$OUTPUT" | grep -i "^cluster" | awk -F': ' '{print $2}' | xargs`

SRV1CV8_SRVDIR="${SRV1CV8_DATA}/reg_${SRV1CV8_REGPORT}"

if [ ! -d "$SRV1CV8_SRVDIR" ]; then
   echo "Не найден каталог данных сервера 1С"
   exit 4
fi

JOURNALS_LIST=`ls -1 $SRV1CV8_SRVDIR | grep -E "^[a-zA-Z0-9]{8}-[a-zA-Z0-9]{4}-[a-zA-Z0-9]{4}-[a-zA-Z0-9]{4}-[a-zA-Z0-9]{12}$"`

if [[ -z "$JOURNALS_LIST" ]]; then
   echo "Не найдены каталоги с журналами регистрации"
   exit 5
else
        declare -A journals_hash
        current_num=1
        while IFS= read -r line; do
                journals_hash["$current_num"]=$line
                current_num=$((current_num+1))
        done <<< "$JOURNALS_LIST"
fi

declare -A infobase_hash
current_infobase=""
current_name=""

while IFS= read -r line; do
        if [[ $line == infobase* ]]; then
                current_infobase=$(echo "$line" | awk '{print $3}')
        fi
        if [[ $line == name* ]]; then
                current_name=$(echo "$line" | awk '{print $3}')
                infobase_hash["$current_infobase"]=$(echo "$current_name" | tr -d '"')
        fi
done <<< "$($RAC infobase summary list --cluster=$CLUSTER_ID)"

echo -e "Найденные журналы:"
printf "%-6s %-40s %15s\n" "#" "Имя базы" "Размер журналов"

n=1
a=0

for i in "${!journals_hash[@]}"; do
        if [[ -n ${infobase_hash[${journals_hash[$i]}]} ]]; then
                BASE_NAME=${infobase_hash[${journals_hash[$i]}]}
                APPENDIX=""
        else
                BASE_NAME=${journals_hash[$i]}
                APPENDIX="X"
                a=$((a+1))
        fi
    JOURNAL_SIZE=`du -sh $SRV1CV8_SRVDIR/${journals_hash[$i]} | awk '{print $1}'`
    printf "%-6s %-40s %-6s %-4s\n" "${n})" $BASE_NAME $JOURNAL_SIZE $APPENDIX
    n=$((n+1))
done

[ "$a" -gt 0 ] && echo -e "\n\tX) Журналы регистрации не связаны ни с одной базой на сервере."
