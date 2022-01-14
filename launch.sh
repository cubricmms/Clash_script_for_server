#!/bin/bash
CONTAINER_NAME=clash-client
docker stop $CONTAINER_NAME 2>/dev/null

# update latest config file
CLASH_CONFIG_LOCATION=$HOME/.config/clash
mkdir -p $CLASH_CONFIG_LOCATION
CONFIG_FILE=$CLASH_CONFIG_LOCATION/config.yaml
if [ ! -f $CONFIG_FILE ]; then
    wget -O $CONFIG_FILE  $CLASH_CONFIG_URL # source your env
fi

# download clash dashboard
if [ ! -f ./gh-pages.zip ]; then
    wget https://github.com/Dreamacro/clash-dashboard/archive/gh-pages.zip
    unzip -o gh-pages.zip -d $CLASH_CONFIG_LOCATION
fi

# 7890 http
# 7891 https
# 9090 restful api controller

docker run -d \
    --rm \
    --name $CONTAINER_NAME \
    --env TZ=Asia/Shanghai \
    -p 7890:7890 -p 7891:7891 -p 9090:9090 \
    -v $CONFIG_FILE:/root/.config/clash/config.yaml \
    -v $CLASH_CONFIG_LOCATION/clash-dashboard-gh-pages:/root/.config/clash/ui \
    dreamacro/clash:v1.8.0

# wait for services initiation
while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' localhost:9090/proxies)" != "200" ]];
do
    echo "Waiting proxy service.."
    sleep 5;
done
echo "Proxy is ready!"

# Summary latency for all proxies
PROXIES=`curl -s -X GET http://0.0.0.0:9090/proxies | jq ".proxies.Proxy.all[]" | sed -r "s/\s+/%20/g"| sed -e "s/\"//g"`

MIN_TIMEOUT=300
SELECTOR=""

for PROXY in $PROXIES
do
    url="http://127.0.0.1:9090/proxies/${PROXY}/delay"
    echo TESTING $url ...
    latency=`curl -s -G -X GET $url -d "timeout=300" -d "url=http://www.gstatic.com/generate_204" |jq ".delay" `

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
