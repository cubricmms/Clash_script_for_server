#!/bin/bash

clashServiceUrl='http://localhost:9090'
LEAST_LATENCY=1000
SELECTOR=""

back_func() {
    declare -A MYGLOBAL
    local vars
    while :; do
        ((MYGLOBAL["counter"]++))
        IFS=\ / read -a vars <<< "$(</proc/uptime) $(</proc/loadavg)"
        MYGLOBAL["uptime"]=$vars
        MYGLOBAL["idle"]=${vars[1]}
        MYGLOBAL["l01m"]=${vars[2]}
        MYGLOBAL["l05m"]=${vars[3]}
        MYGLOBAL["l15m"]=${vars[4]}
        MYGLOBAL["active"]=${vars[5]}
        MYGLOBAL["procs"]=${vars[6]}
        MYGLOBAL["lpid"]=${vars[7]}
        MYGLOBAL["rand"]=$RANDOM
        MYGLOBAL["crt"]=$SECONDS
        declare -p MYGLOBAL > /dev/shm/foo
        sleep 1
    done
}

dumpMyGlobal() {
    . /dev/shm/foo
    printf "%8s " ${!MYGLOBAL[@]}
    echo
    printf "%8s " ${MYGLOBAL[@]}
    echo
}

function waitForProxy {
    while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' $clashServiceUrl/proxies)" != "200" ]];
    do
        echo "Waiting proxy service.."
        sleep 22;
    done
    echo "Proxy is ready!"
}

function testLatency {
    delayUrl="$clashServiceUrl/proxies/$1/delay"
    latency=`curl -s -G -X GET $delayUrl -d "timeout=300" -d "url=http://www.gstatic.com/generate_204" |jq ".delay" `
    if [[ "$latency" != "null" ]] && test $latency -gt 0 && test $latency -lt $LEAST_LATENCY; then
	    LEAST_LATENCY=$latency
	    SELECTOR=$1
	    echo "$1 has faster connection, latency $latency"
    fi
}

waitForProxy

# Summary latency for all proxies
proxyList=`curl -s -X GET $clashServiceUrl/proxies | jq ".proxies.Proxy.all[]" | sed -r "s/\s+/%20/g"| sed -e "s/\"//g"`

for proxy in $proxyList
do
    echo Test proxy: $proxy...
    testLatency $proxy 
done
echo "Test finished! ${SELECTOR} has fastest connection with latency ${LEAST_LATENCY} ms!"

SWITCH_URL="$clashServiceUrl/proxies/Proxy"
SELECTOR=`echo $SELECTOR | sed -e "s/%20/ /g"`
POST=$( jq -n --arg parm "$SELECTOR" '{name: $parm}' )

STATUS_CODE=`curl -s -X PUT -w "%{http_code}" -d "${POST}" $SWITCH_URL`

if test $STATUS_CODE -eq 204; then
    echo "Switch to ${SELECTOR} successfully!";
else
    echo "${STATUS_CODE}, switch failed";
fi
