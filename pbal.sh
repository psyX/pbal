#!/bin/bash

ERR_NEED_TWO_PARAMS="need two params"
USER_AGENT="Mozilla/5.0 (Macintosh; Intel Mac OS X 10.6; rv:5.0.1) Gecko/20100101 Firefox/5.0.1"
TIME_OUT=120

function megafon {
	tmp_file=/tmp/megafon.session_id
	curl -s -m $TIME_OUT https://moscowsg.megafon.ru/ps/scc/php/check.php?CHANNEL=WWW \
		-d "LOGIN=$1&PASSWORD=$2" > $tmp_file
	
	session_id=`sed -n -e "s/.*<SESSION_ID>\(.*\)<\/SESSION_ID>.*/\1/p" $tmp_file`
	
	rm $tmp_file
	
	balance=`curl -s -m $TIME_OUT https://moscowsg.megafon.ru//SCWWW/ACCOUNT_INFO \
		-d "CHANNEL=WWW&SESSION_ID=$session_id&P_USER_LANG_ID=1" \
			| grep balance \
			| head -n1 \
			| sed -e 's/<[^>]*>//g' \
			| cut -d " " -f 1`
	
	echo $balance
}

function mts {
	curl -s -m $TIME_OUT -L "https://ip.mts.ru/selfcarepda/security.mvc/logon" \
		-c /tmp/mts.cookies \
		--referer "https://ihelper.mts.ru/selfcare/logon.aspx" \
		--user-agent $USER_AGENT > /dev/null

	balance=`curl -s -m $TIME_OUT -L "https://ip.mts.ru/SELFCAREPDA/Security.mvc/LogOn?returnLink=http%3A%2F%2Fip.mts.ru%3A8085%2FSELFCAREPDA%2FHome.mvc" \
		-c /tmp/mts.cookies \
		-b /tmp/mts.cookies \
		-d "username=$1&password=$2" \
		--referer "https://ihelper.mts.ru/selfcare/logon.aspx" \
		--user-agent $USER_AGENT \
			| grep "Баланс" \
			| sed -n -e "s/.*<strong>\(.*\)<\/strong>.*/\1/p" \
			| sed -e 's/<[^>]*>//g' \
			| cut -d " " -f 1`

	echo $balance

	rm -f /tmp/mts.cookies
}

function beeline {
	curl -s -m $TIME_OUT -L \
		-c /tmp/beeline.cookies https://uslugi.beeline.ru/loginPage.do \
		-d "_stateParam=eCareLocale.currentLocale%3Dru_RU__Russian&_forwardName=null&_resetBreadCrumbs=false&_expandStatus=&userName=$1&password=$2&ecareAction=login" \
		--referer "https://uslugi.beeline.ru/vip/loginPage.jsp" \
		--user-agent $USER_AGENT > /dev/null

	balance=`curl -s -m $TIME_OUT -L \
		-c /tmp/beeline.cookies \
		-b /tmp/beeline.cookies https://uslugi.beeline.ru/vip/prepaid/refreshedPrepaidBalance.jsp \
			| grep small \
			| sed 's/&nbsp;/ /g' \
			| cut -d " " -f 1 \
			| sed -e 's/^[ \t]*//' \
			| sed s/,/./g`

	echo $balance

	rm -f /tmp/beeline.cookies
}

function onlime {
	curl -s -m $TIME_OUT -c /tmp/onlime.cookies  https://my.onlime.ru > /dev/null

	balance=`curl -s -m $TIME_OUT -L \
		-b /tmp/onlime.cookies \
		-c /tmp/onlime.cookies \
		-d "login_credentials[login]=$1&login_credentials[password]=$2" https://my.onlime.ru/session/login \
			| sed -n -e "s/.*<big>\(.*\)<\/big>.*/\1/p" \
			| grep -v strong \
			| head -n1`

	echo $balance

	rm -rf /tmp/onlime.cookies
}


function mgts {
	viewstate=`curl -s -m $TIME_OUT -c /tmp/mgts.cookies https://lk.mgts.ru | grep VIEWSTATE | sed -n -e 's/.*value="\(.*\)".*/\1/p'`
	curl -s -m $TIME_OUT -L -c /tmp/mgts.cookies -b /tmp/mgts.cookies https://lk.mgts.ru/start.aspx \
		--data-urlencode "__VIEWSTATE=$viewstate" \
		-d "txtPhone=$1" \
		-d "txtPIN=$2" \
		-d "btnEnter=%C2%F5%EE%E4" \
		--referer "https://lk.mgts.ru/start.aspx" \
		--user-agent $USER_AGENT > /dev/null
	balance=`curl -s -m $TIME_OUT -L -c /tmp/mgts.cookies -b /tmp/mgts.cookies https://lk.mgts.ru/CustomerInfo.aspx \
		--referer "https://lk.mgts.ru/start.aspx" \
		| grep lblBalance \
		| sed -e 's/<[^>]*>//g' \
		| sed -e 's/^[ \t]*//' \
		| sed s/,/./g`
	rm -f /tmp/mgts.cookies
	echo $balance
}

#if [ -z "$2" ] || [ -z "$3" ]; then
#	echo $ERR_NEED_TWO_PARAMS
#	exit 1
#fi

case "$1" in
	megafon)
		megafon $2 $3
	;;
	mts)
		mts $2 $3
	;;
	beeline)
		beeline $2 $3
	;;
	mgts)
		mgts $2 $3
	;;
	onlime)
		onlime $2 $3
	;;
	*)
		echo "usage: $0 {megafon|mts|beeline|mgts|onlime} {login} {password}"

esac

exit 0

