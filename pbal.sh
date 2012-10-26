#!/bin/bash

#set -x

#ERR_NEED_TWO_PARAMS="need two params"
USER_AGENT="Mozilla/5.0 (Macintosh; Intel Mac OS X 10.6; rv:5.0.1) Gecko/20100101 Firefox/5.0.1"
TIME_OUT=120
ATTEMPTS=5
ATTEMPTS_TIME_OUT=30
SILENT=0
VERBOSE=0

function resp {
	if [ -r $1 ]; then
		status_code=`head -n1 $1 | cut -d' ' -f2`
		if [ "$status_code" == "302" ]; then # may be it's header like cookie
			status_code_new=`grep -e "^HTTP" $1 | tail -n1 | cut -d' ' -f2`
			if [ -n "$status_code_new" ]; then 
				echo $status_code_new
			else
				echo $status_code
			fi
		else
			echo $status_code
		fi
	else
		echo 999
	fi
}

function err {
	if [ $SILENT -eq 0 ]; then
		if [ $VERBOSE -eq 0 ]; then
			echo "ERROR: $1"
		else
			echo "$voperator $vlogin ERROR: $1"
		fi
	fi
	rm -f $tmp_cookie
	rm -f $tmp_file
	exit 1
}

function err404 {
	err "Page $1 has been change own structure"
}

function err999 {
	err "Connection error or can't write to /tmp"
}

function errATT {
	err "Exceeded the number of connection attempts to the server"
}

function errCOO {
	err "Can't get cookies from $1 or can't write to /tmp"
}

##### CUT HERE #####

function megafon {
	tmp_file=/tmp/megafon.session_id

	rv=0
	i=0
	page="https://moscowsg.megafon.ru/ps/scc/php/check.php?CHANNEL=WWW"
	while [ "$rv" != "200" ]; do
		curl -i -s -m $TIME_OUT $page \
			-d "LOGIN=$1&PASSWORD=$2" | iconv -c -fcp1251 > $tmp_file

		rv=$(resp "$tmp_file")

		if [ "$rv" != "200" ]; then
			case "$rv" in
				"999")
					err999
					;;
				"404")
					err404 "$page"
					;;
				*)
					sleep $ATTEMPTS_TIME_OUT
					let i=i+1
					;;
			esac
		fi

		if [ $i -ge $ATTEMPTS ]; then
			errATT
		fi	 
	done

	session_id=`sed -n -e "s/.*<SESSION_ID>\(.*\)<\/SESSION_ID>.*/\1/p" $tmp_file`
	error_message=`sed -n -e "s/.*<ERROR_MESSAGE>\(.*\)<\/ERROR_MESSAGE>.*/\1/p" $tmp_file`

	if [ -n "$error_message" ]; then
		err "$error_message"
	fi
	
	if [ -z "$session_id" ]; then
		err "Can't get session_id from $page"
	fi
	
	rm $tmp_file

	tmp_file=/tmp/megafon.balance
	rv=0
	i=0
	page="https://moscowsg.megafon.ru//SCWWW/ACCOUNT_INFO"	
	while [ "$rv" != "200" ]; do
		curl -i -s -m $TIME_OUT $page \
			-d "CHANNEL=WWW&SESSION_ID=$session_id&P_USER_LANG_ID=1" \
			| iconv -c -fcp1251 > $tmp_file
	
		rv=$(resp "$tmp_file")

		if [ "$rv" != "200" ]; then
			case "$rv" in
				"999")
					err999
					;;
				"404")
					err404 "$page"
					;;
				*)
					sleep $ATTEMPTS_TIME_OUT
					let i=i+1
					;;
			esac
		fi

		if [ $i -ge $ATTEMPTS ]; then
			errATT
		fi	 
	done

	balance=`cat $tmp_file \
			| grep balance \
			| head -n1 \
			| sed -e 's/<[^>]*>//g' \
			| cut -d " " -f 1`
	rm $tmp_file
	
	if [ $VERBOSE -eq 0 ]; then
		echo $balance
	else
		echo megafon $1 $balance
	fi
}

function mts {
	tmp_file=/tmp/mts.response
	tmp_cookie=/tmp/mts.cookies

	rv=0
	i=0
	page="https://login.mts.ru/amserver/UI/Login?service=lk&goto=https://lk.ssl.mts.ru/"
	while [ "$rv" != "200" ]; do
		curl -i -s -m $TIME_OUT "$page" \
			-c $tmp_cookie \
			--user-agent $USER_AGENT > $tmp_file

		rv=$(resp "$tmp_file")

		if [ "$rv" != "200" ]; then
			case "$rv" in
				"999")
					err999
					;;
				"404")
					err404 "$page"
					;;
				*)
					sleep $ATTEMPTS_TIME_OUT
					let i=i+1
					;;
			esac
		fi

		if [ $i -ge $ATTEMPTS ]; then
			errATT
		fi	

	done

    CSRTFoken=`grep CSRTFoken $tmp_file | sed -n -e 's/.*value="\(.*\)".*/\1/p'`

    if [ -z "$CSRTFoken" ]; then
        err "Can't get CSRTFoken from $page"
    fi

	rv=0
	i=0
	page="https://login.mts.ru/amserver/UI/Login?service=lk&goto=https://lk.ssl.mts.ru/"
	while [ "$rv" != "200" ]; do
		curl -i -s -m $TIME_OUT -L "$page" \
			-c $tmp_cookie \
			-b $tmp_cookie \
			-d "CSRTFoken=$CSRTFoken" \
            -d "IDToken1=$1" \
            -d "IDToken2=$2" \
            --data-urlencode "goto=https://lk.ssl.mts.ru/" \
			--user-agent $USER_AGENT > $tmp_file

		rv=$(resp "$tmp_file")

		if [ "$rv" != "200" ]; then
			case "$rv" in
				"999")
					err999
					;;
				"404")
					err404 "$page"
					;;
				*)
					sleep $ATTEMPTS_TIME_OUT
					let i=i+1
					;;
			esac
		fi

		if [ $i -ge $ATTEMPTS ]; then
			errATT
		fi	

	done

    errmsg=`grep small $tmp_file | sed -n -e 's/.*<small>\(.*\)<\/small>.*/\1/p'`
    if [ -n "$errmsg" ]; then
        err "$errmsg"
    fi

    errmsg=`grep 'label validate="IDToken2"' $tmp_file | sed -n -e 's/.*<label.*>\(.*\)<\/label>.*/\1/p'`
    if [ -n "$errmsg" ]; then
        err "$errmsg"
    fi

	rv=0
	i=0
	page="https://login.mts.ru/profile/mobile/get"
	while [ "$rv" != "200" ]; do
		curl -i -s -m $TIME_OUT "$page" \
			-b $tmp_cookie \
			--user-agent $USER_AGENT > $tmp_file
		rv=$(resp "$tmp_file")

		if [ "$rv" != "200" ]; then
			case "$rv" in
				"999")
					err999
					;;
				"404")
					err404 "$page"
					;;
				*)
					sleep $ATTEMPTS_TIME_OUT
					let i=i+1
					;;
			esac
		fi

		if [ $i -ge $ATTEMPTS ]; then
			errATT
		fi	
	done
	
	balance=`sed -n -e 's/.*balance":"\(.*\)","tariff.*/\1/p' $tmp_file`

	if [ $VERBOSE -eq 0 ]; then
		echo $balance
	else
		echo mts $1 $balance
	fi

	rm -f $tmp_cookie
    rm -f $tmp_file
}

function beeline {
	tmp_file=/tmp/beeline.response
	tmp_cookie=/tmp/beeline.cookies

	rv=0
	i=0
	page="https://uslugi.beeline.ru/loginPage.do"
	while [ "$rv" != "200" ]; do
		curl -i -s -m $TIME_OUT -L -c $tmp_cookie $page \
			-d "_stateParam=eCareLocale.currentLocale%3Dru_RU__Russian&_forwardName=null&_resetBreadCrumbs=false&_expandStatus=&userName=$1&password=$2&ecareAction=login" \
			--referer "https://uslugi.beeline.ru/vip/loginPage.jsp" \
			--user-agent $USER_AGENT | iconv -c -fcp1251 > $tmp_file

		rv=$(resp "$tmp_file")

		if [ "$rv" != "200" ]; then
			case "$rv" in
				"999")
					err999
					;;
				"404")
					err404 "$page"
					;;
				*)
					sleep $ATTEMPTS_TIME_OUT
					let i=i+1
					;;
			esac
		fi

		if [ $i -ge $ATTEMPTS ]; then
			errATT
		fi	
	done

	if [ ! -r "$tmp_cookie" ]; then
		errCOO "$page"
	fi

	errmsg=`grep "Ошибка\!" $tmp_file | awk -F "</b> " '{print $2}'`
	
	if [ -n "$errmsg" ]; then
		err $errmsg
	fi

	rv=0
	i=0
	page="https://uslugi.beeline.ru/vip/prepaid/refreshedPrepaidBalance.jsp"
	while [ "$rv" != "200" ]; do
		curl -i -s -m $TIME_OUT -L -c $tmp_cookie -b $tmp_cookie $page > $tmp_file

		rv=$(resp "$tmp_file")

		if [ "$rv" != "200" ]; then
			case "$rv" in
				"999")
					err999
					;;
				"404")
					err404 "$page"
					;;
				*)
					sleep $ATTEMPTS_TIME_OUT
					let i=i+1
					;;
			esac
		fi

		if [ $i -ge $ATTEMPTS ]; then
			errATT
		fi	
	done

	balance=`grep small $tmp_file \
			| sed 's/&nbsp;/ /g' \
			| cut -d " " -f 1 \
			| sed -e 's/^[ \t]*//' \
			| sed s/,/./g`
    
    if [ -z "$balance" ]; then
        err "Can't get balance"
    fi

	if [ $VERBOSE -eq 0 ]; then
		echo $balance
	else
		echo beeline $1 $balance
	fi

	rm -f $tmp_cookie
    rm -f $tmp_file
}

function onlime {
	tmp_file=/tmp/onlime.response
	tmp_cookie=/tmp/onlime.cookies

	rv=0
	i=0
	page="https://my.onlime.ru"
	while [ "$rv" != "200" ]; do
		curl -i -s -m $TIME_OUT -c $tmp_cookie $page > $tmp_file

		rv=$(resp "$tmp_file")

		if [ "$rv" != "200" ]; then
			case "$rv" in
				"999")
					err999
					;;
				"404")
					err404 "$page"
					;;
				*)
					sleep $ATTEMPTS_TIME_OUT
					let i=i+1
					;;
			esac
		fi

		if [ $i -ge $ATTEMPTS ]; then
			errATT
		fi	
	done

	if [ ! -r "$tmp_cookie" ]; then
		errCOO "$page"
	fi

	rv=0
	i=0
	page="https://my.onlime.ru/session/login"
	while [ "$rv" != "200" ]; do
		curl -i -s -m $TIME_OUT -L \
			-b $tmp_cookie \
			-c $tmp_cookie \
			-d "login_credentials[login]=$1&login_credentials[password]=$2" $page > $tmp_file

		rv=$(resp "$tmp_file")

		if [ "$rv" != "200" ]; then
			case "$rv" in
				"999")
					err999
					;;
				"404")
					err404 "$page"
					;;
				*)
					sleep $ATTEMPTS_TIME_OUT
					let i=i+1
					;;
			esac
		fi

		if [ $i -ge $ATTEMPTS ]; then
			errATT
		fi	
	done

	errmsg=`grep "<title>ERROR</title>" $tmp_file | sed -n -e "s/.*<h1>\(.*\)<\/h1>.*/\1/p"`
	if [ -n "$errmsg" ]; then
		err "$errmsg"
	fi

	errmsg=`grep err_msg_password $tmp_file | sed -n -e "s/.*<br>\(.*\)<br>.*/\1/p"`
	if [ -n "$errmsg" ]; then
		err "$errmsg"
	fi

    rv=0
    i=0
    page="https://my.onlime.ru/json/cabinet/"
    while [ "$rv" != "200" ]; do
        curl -i -s -m $TIME_OUT -L \
            -b $tmp_cookie \
            -c $tmp_cookie \
            $page > $tmp_file

        rv=$(resp "$tmp_file")

        if [ "$rv" != "200" ]; then
            case "$rv" in
                "999")
                    err999
                    ;;
                "404")
                    err404 "$page"
                    ;;
                *)
                    sleep $ATTEMPTS_TIME_OUT
                    let i=i+1
                    ;;
            esac
        fi

        if [ "$rv" == "200" ]; then
            #balance=`sed -n 's/.*\"balance\":\(.*\),\"lock\".*/\1/p' $tmp_file`
            balance=`grep -o 'balance":[0-9]*.[0-9]*' $tmp_file | cut -d':' -f2`
            if [ ! -n "$balance" ]; then
                rv=500
                let i=i+1
                #exit 1
            fi
        fi

        if [ $i -ge $ATTEMPTS ]; then
            errATT
        fi
    done

	#balance=`sed -n -e "s/.*<big>\(.*\)<\/big>.*/\1/p" $tmp_file \
	#	| grep -v strong \
	#	| head -n1`

    #balance=`sed -n 's/.*\"balance\":\(.*\),\"lock\".*/\1/p' $tmp_file`
    balance=`grep -o 'balance":[0-9]*.[0-9]*' $tmp_file | cut -d':' -f2`

	if [ $VERBOSE -eq 0 ]; then
		echo $balance
	else
		echo onlime $1 $balance
	fi

	rm -f $tmp_cookie
}

function qiwi {
    tmp_file=/tmp/qiwi.response
    tmp_cookie=/tmp/qiwi.cookies

    rv=0
    i=0
    page="https://w.qiwi.com/auth/login.action"
    while [ "$rv" != "200" ]; do
        curl -i -s -m $TIME_OUT -c $tmp_cookie --get -d "source=MENU" --data-urlencode "login=$1" --data-urlencode "password=$2" $page > $tmp_file

		rv=$(resp "$tmp_file")

		if [ "$rv" != "200" ]; then
			case "$rv" in
				"999")
					err999
					;;
				"404")
					err404 "$page"
					;;
				*)
					sleep $ATTEMPTS_TIME_OUT
					let i=i+1
					;;
			esac
		fi

		if [ $i -ge $ATTEMPTS ]; then
			errATT
		fi	
	done

	errmsg=`grep -v NORMAL $tmp_file | sed -n -e 's/.*message":"\(.*\)",".*/\1/p'`
	if [ -n "$errmsg" ]; then
		err "$errmsg"
	fi
	
	rv=0
	i=0
	page="https://w.qiwi.com/user/person/account/list.action"
	while [ "$rv" != "200" ]; do
		curl -i -s -m $TIME_OUT -b $tmp_cookie  $page \
			--referer "https://w.qiwi.com/person/account/main.action" > $tmp_file

		rv=$(resp "$tmp_file")

		if [ "$rv" != "200" ]; then
			case "$rv" in
				"999")
					err999
					;;
				"404")
					err404 "$page"
					;;
				*)
					sleep $ATTEMPTS_TIME_OUT
					let i=i+1
					;;
			esac
		fi

		if [ $i -ge $ATTEMPTS ]; then
			errATT
		fi	
	done

	balance=`grep balance $tmp_file \
        | head -n2 \
        | tail -n1 \
        | sed 's/[^0-9,-]*//g' \
        | sed "s/,/\./g"`

	rm -f $tmp_cookie
    rm -f $tmp_file

	if [ $VERBOSE -eq 0 ]; then
		echo $balance
	else
		echo qiwi $1 $balance
	fi
}

function mgts {
	tmp_file=/tmp/mgts.response
	tmp_cookie=/tmp/mgts.cookies

	rv=0
	i=0
	page="https://ihelper.mgts.ru/CustomerSelfCare2/logon.aspx"
	while [ "$rv" != "200" ]; do
		curl -k -i -s -m $TIME_OUT -c $tmp_cookie $page > $tmp_file

		rv=$(resp "$tmp_file")

		if [ "$rv" != "200" ]; then
			case "$rv" in
				"999")
					err999
					;;
				"404")
					err404 "$page"
					;;
				*)
					sleep $ATTEMPTS_TIME_OUT
					let i=i+1
					;;
			esac
		fi

		if [ $i -ge $ATTEMPTS ]; then
			errATT
		fi	
	done

	viewstate=`grep VIEWSTATE $tmp_file | sed -n -e 's/.*value="\(.*\)".*/\1/p'`
	if [ -z "$viewstate" ]; then
		err "Can't get VIEWSTATE__ from $page"
	fi
	
	rv=0
	i=0
	page="https://ihelper.mgts.ru/CustomerSelfCare2/logon.aspx"
	while [ "$rv" != "200" ]; do
		curl -k -L -i -s -m $TIME_OUT -c $tmp_cookie -b $tmp_cookie $page \
			--data-urlencode "__VIEWSTATE=$viewstate" \
			-d "ctl00%24MainContent%24tbPhoneNumber=$1" \
			-d "ctl00%24MainContent%24tbPassword=$2" \
			-d "ctl00%24MainContent%24btnEnter=%D0%92%D0%BE%D0%B9%D1%82%D0%B8+%3E" \
			--referer "$page" \
			--user-agent $USER_AGENT > $tmp_file

		rv=$(resp "$tmp_file")

		if [ "$rv" != "200" ]; then
			case "$rv" in
				"999")
					err999
					;;
				"404")
					err404 "$page"
					;;
				*)
					sleep $ATTEMPTS_TIME_OUT
					let i=i+1
					;;
			esac
		fi

		if [ $i -ge $ATTEMPTS ]; then
			errATT
		fi	
	done

	errmsg=`grep "b_error" $tmp_file | grep -v "%CONTENT%" | sed -n -e 's/.*<div\ class="bln">\(.*\)<\/div><div\ class="lbottom">.*/\1/p'`
	if [ -n "$errmsg" ]; then
		err "$errmsg"
	fi
	
	rv=0
	i=0
	page="https://ihelper.mgts.ru/CustomerSelfCare2/account-status.aspx"
	while [ "$rv" != "200" ]; do
		curl -k -i -s -m $TIME_OUT -c $tmp_cookie -b $tmp_cookie $page \
			--referer "https://ihelper.mgts.ru/CustomerSelfCare2/logon.aspx" > $tmp_file

		rv=$(resp "$tmp_file")

		if [ "$rv" != "200" ]; then
			case "$rv" in
				"999")
					err999
					;;
				"404")
					err404 "$page"
					;;
				*)
					sleep $ATTEMPTS_TIME_OUT
					let i=i+1
					;;
			esac
		fi

		if [ $i -ge $ATTEMPTS ]; then
			errATT
		fi	
	done

	balance=`sed -n -e "s/.*<td\ class=\"right\">\(.*\)<\/td>/\1/p" $tmp_file \
        | sed 's/[^0-9,-]*//g' | sed "s/,/\./g"`

	rm -f $tmp_cookie
    rm -f $tmp_file

	if [ $VERBOSE -eq 0 ]; then
		echo $balance
	else
		echo mgts $1 $balance
	fi
}

function usage {
	echo "usage: $0 [-t{sec}] [-a{attempts}] [-T{sec_attempts}] [-s] [-v] [-h] {megafon|mts|beeline|mgts|onlime} {login} {password}"
	echo "	-t Timeout for connections, default $TIME_OUT sec"
	echo "	-a Attempts of conections, default $ATTEMPTS"
	echo "	-T Sleep between attempts, default $ATTEMPTS_TIME_OUT"
	echo "	-s Silent, don't show any errors"
	echo "	-v Verbose, show operator name and login before balance"
	exit $1
}

while getopts "t:a:T:svh" optname; do
	case "$optname" in
		"t")
			if ! [[ "$OPTARG" =~ ^[0-9]+$ ]]; then
				usage 1
			else 
				TIME_OUT=$OPTARG
			fi
			;;
		"a")
			if ! [[ "$OPTARG" =~ ^[0-9]+$ ]]; then
				usage 1
			else
				ATTEMPTS=$OPTARG
			fi
			;;
		"T")
			if ! [[ "$OPTARG" =~ ^[0-9]+$ ]]; then
				usage 1
			else
				ATTEMPTS_TIME_OUT=$OPTARG
			fi
			;;
		"s")
			SILENT=1
			;;
		"v")
			VERBOSE=1
			;;
		"h")
			usage 0
			;;
		*)
			usage 1
			;;
	esac
done

p="${@:$OPTIND}"

voperator=`echo $p | cut -d' ' -f1`
vlogin=`echo $p | cut -d' ' -f2`
vpassword=`echo $p | cut -d' ' -f3`

if [ -z "$voperator" ] || [ -z "$vlogin" ] || [ -z "$vpassword" ]; then
	usage 1
fi


case "$voperator" in
	megafon)
		megafon $vlogin $vpassword
	;;
	mts)
		mts $vlogin $vpassword
	;;
	beeline)
		beeline $vlogin $vpassword
	;;
	mgts)
		mgts $vlogin $vpassword
	;;
	onlime)
		onlime $vlogin $vpassword
	;;
	qiwi)
		qiwi $vlogin $vpassword
	;;
	*)
		usage 1

esac

exit 0

