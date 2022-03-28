#!/bin/bash

clashServiceUrl='http://localhost:9090'
echo 1000 >/dev/shm/clash-llatency
echo "" >/dev/shm/clash-selector
sleep .3;

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
    _least_latency=$(</dev/shm/clash-llatency)
    if [[ "$latency" != "null" ]] && test $latency -gt 0 && test $latency -lt $_least_latency; then
	    echo $latency >/dev/shm/clash-llatency
	    echo $1 >/dev/shm/clash-selector
        sleep .3;
	    echo "$1 has faster connection, latency $latency"
    fi
}

waitForProxy

# Summary latency for all proxies
proxyList=`curl -s -X GET $clashServiceUrl/proxies | jq ".proxies.Proxy.all[]" | sed -r "s/\s+/%20/g"| sed -e "s/\"//g"`

for proxy in $proxyList
do
    echo Test proxy: $proxy...
    testLatency $proxy &
done
wait

SELECTOR=$(</dev/shm/clash-selector)
LEAST_LATENCY=$(</dev/shm/clash-llatency)

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

rm /dev/shm/clash-llatency
rm /dev/shm/clash-selector