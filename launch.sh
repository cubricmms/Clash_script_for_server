#!/bin/bash

docker stop clash-client
docker container rm clash-client

# update latest config file

wget -O $HOME/Clash_script_for_server/config.yml $CONFIG_URL

# 7890 http
# 7891 https
# 9090 restful api controller

docker run -d --name clash-client --restart always -p 7890:7890 -p 7891:7891 -p 9090:9090 -v $HOME/Clash_script_for_server/config.yml:/root/.config/clash/config.yaml dreamacro/clash-premium

# wait for services initiation
while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' localhost:9090/proxies)" != "200" ]]; 
do 
    echo "Waiting proxy service.."
    sleep 5; 
done
echo "Proxy is ready!"

# Summary latency for all proxies
PROXIES=`curl -s -X GET http://127.0.0.1:9090/proxies | jq ".proxies.Proxy.all"| jq ".[]"| sed -e "s/ /%20/g"| sed -e "s/\"//g"`

MIN_TIMEOUT=300
SELECTOR=""

for PROXY in $PROXIES 
do
    url="http://127.0.0.1:9090/proxies/${PROXY}/delay"
    latency=`curl -s -G -X GET $url -d "timeout=300" -d "url=http://www.youtube.com"|jq ".delay"`

    if test "$latency" -gt 0 && test "$latency" -lt $MIN_TIMEOUT; then
	    MIN_TIMEOUT=$latency
	    SELECTOR=$PROXY
	    echo "${PROXY} has faster connection"
    fi
done

echo "Test finished! ${SELECTOR} has fastest connection with latency ${MIN_TIMEOUT} ms!"

curl -s -X GET http://127.0.0.1:9090/proxies | jq ".proxies.Proxy"

SWITCH_URL="http://127.0.0.1:9090/proxies/Proxy"

SELECTOR=`echo $SELECTOR | sed -e "s/%20/ /g"`

POST=$( jq -n --arg parm "$SELECTOR" '{name: $parm}' )
echo $POST

STATUS_CODE=`curl -X PUT -w "%{http_code}" -d "${POST}" $SWITCH_URL` 

echo $STATUS_CODE
if test $STATUS_CODE -eq 204; then 
    echo "Switch to ${SELECTOR} successfully!";
else
    echo "${STATUS_CODE}, switch failed";
fi

curl -s -X GET http://127.0.0.1:9090/proxies | jq ".proxies.Proxy"
