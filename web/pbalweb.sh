#!/bin/bash

#set -x

# where is pbal.sh location
pbal='~/bin/pbal.sh'

# where is DB location
db=/secret/place/pbalweb.db

# web dir location
webdir=/srv/http

# send message to user when balance less then limit via jabber
limit=20

if [ ! -w $db ]; then

    # Create TABLEs
    sqlite3 $db \
        "CREATE TABLE IF NOT EXISTS usr ( \
            usrid INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
            usrname TEXT NOT NULL,
            xmpp TEXT);"

    sqlite3 $db \
        "CREATE TABLE IF NOT EXISTS op ( \
            opid INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, \
            usrid INTEGER NOT NULL, \
            opname TEXT NOT NULL, \
            lgn TEXT NOT NULL, \
            pass TEXT NOT NULL, \
            dsc TEXT, \
            ntfdate TEXT NOT NULL DEFAULT '1900-01-01', \
            ntf INTEGER NOT NULL DEFAULT 1, \
            FOREIGN KEY (usrid) REFERENCES usr(usrid) \
                ON DELETE CASCADE \
                ON UPDATE CASCADE);"

    sqlite3 $db \
        "CREATE TABLE IF NOT EXISTS bal (\
            balid INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, \
            opid INTEGER NOT NULL, \
            baldate TEXT NOT NULL, \
            bal REAL NOT NULL, \
            FOREIGN KEY (opid) REFERENCES op(opid) \
                ON DELETE CASCADE \
                ON UPDATE CASCADE);"

    # Create INDEXs
    sqlite3 $db \
        "CREATE INDEX IF NOT EXISTS idx_bal_1 ON bal (baldate, opid);"

    # Create VIEWs
    sqlite3 $db \
        "CREATE VIEW IF NOT EXISTS v_bal_last AS \
            SELECT O_.usrid, O_.opid, O_.dsc, O_.lgn, B_.baldate, B_.bal FROM op O_ \
            JOIN (SELECT opid, MAX(baldate) AS baldate FROM bal GROUP BY opid) BM_ \
                ON BM_.opid = O_.opid \
            JOIN bal B_ \
                ON B_.opid = O_.opid AND B_.baldate = BM_.baldate;"

    sqlite3 $db \
        "CREATE VIEW IF NOT EXISTS v_bal_history AS \
            SELECT \
                opid, date(baldate) AS dd, time(baldate) AS tt, baldate, bal, ROUND(bal_prev-bal, 2) AS chg \
            FROM ( \
                SELECT \
                    B_.opid, B_.baldate, B_.bal, IFNULL(BP_.bal,'xxx') AS bal_prev \
                FROM bal B_ \
                LEFT JOIN bal BP_ ON \
                    BP_.opid = B_.opid AND \
                    BP_.balid = ( \
                        SELECT MAX(BM_.balid) \
                        FROM \
                            bal BM_ \
                        WHERE \
                            BM_.opid = B_.opid AND \
                            BM_.balid < B_.balid \
                    ) \
                ORDER BY B_.opid, B_.balid DESC \
            ) \
            WHERE bal <> bal_prev \
            ORDER BY opid, baldate DESC;"

    # Create first user
    sqlite3 $db "INSERT INTO usr ('usrname', 'xmpp') VALUES \
        ('user_name', 'me@jabber.tld');"

    # Create some operators
    sqlite3 $db "INSERT INTO op ('usrid', 'opname', 'lgn', 'pass', 'dsc') VALUES \
        (1, 'megafon', '9265556677', '12345678', 'мой мегафон');" 
    sqlite3 $db "INSERT INTO op ('usrid', 'opname', 'lgn', 'pass', 'dsc') VALUES \
        (1, 'mgts', '4957778899', '12345678', 'мой домашний');"
fi

if [ -w $db ]; then
    # Get balances
    sqlite3 $db "SELECT opname, lgn, pass, opid, ntfdate, ntf FROM op" |\
        while read line; do
            opname=`echo $line | cut -d'|' -f1`
            lgn=`echo $line | cut -d'|' -f2`
            pass=`echo $line | cut -d'|' -f3`
            opid=`echo $line | cut -d'|' -f4`
            ntfdate=`echo $line | cut -d'|' -f5`
            ntf=`echo $line | cut -d'|' -f6`
            echo -n "get data for $opname $lgn... "
            bal=`$pbal $opname $lgn $pass`
            echo "$bal"
            d=`date +'%F %T.000'`
            if [[ "$bal" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
                sqlite3 $db "INSERT INTO bal ('opid', 'baldate', 'bal') VALUES \
                    ('$opid', '$d', '$bal');"
            fi
        done

        d=`date +'%F'`

    # Generate HTML
    echo "<html>" > $webdir/index.html
    echo '<head><link href="all.css" rel="stylesheet" media="all" /></head>' >> $webdir/index.html
    echo "<ul>" >> $webdir/index.html
    sqlite3 $db "SELECT usrid, usrname FROM usr" |\
        while read usr; do
            usrid=`echo $usr | cut -d'|' -f1`
            usrname=`echo $usr | cut -d'|' -f2`
            mkdir -p $webdir/$usrid
            echo "<li><a href=\"$usrid\">$usrname</a></li>" >> $webdir/index.html

            echo "<html>" > $webdir/$usrid/index.html
            echo '<head><link href="../all.css" rel="stylesheet" media="all" /></head>' >> $webdir/$usrid/index.html
            echo '<a href="../">go back</a>' >> $webdir/$usrid/index.html
            echo "<table>" >> $webdir/$usrid/index.html
            sqlite3 $db "SELECT opid, dsc, bal, baldate, lgn FROM v_bal_last WHERE usrid = $usrid" |\
                while read op; do
                    opid=`echo $op | cut -d'|' -f1`
                    dsc=`echo $op | cut -d'|' -f2`
                    bal=`echo $op | cut -d'|' -f3`
                    baldate=`echo $op | cut -d'|' -f4`
                    lgn=`echo $op | cut -d'|' -f5`
                    mkdir -p $webdir/$usrid/$opid
                    echo "<tr><td><a href=\"$opid/full.html\" title=\"Full history\">$dsc</a></td><td>$lgn</td><td title=\"As of date: $baldate\">$bal</td></tr>" >> $webdir/$usrid/index.html

                        echo "<html>" > $webdir/$usrid/$opid/full.html
                        echo '<head><link href="../../all.css" rel="stylesheet" media="all" /></head>' >> $webdir/$usrid/$opid/full.html
                        echo "<strong>$dsc ($lgn)</strong>" >> $webdir/$usrid/$opid/full.html
                        echo '<a href="../">go back</a>' >> $webdir/$usrid/$opid/full.html
                        echo "<table>" >> $webdir/$usrid/$opid/full.html
                        sqlite3 -html $db "SELECT dd, tt, bal, chg FROM v_bal_history WHERE opid = $opid" >> $webdir/$usrid/$opid/full.html
                        echo "</table></html>" >> $webdir/$usrid/$opid/full.html

                done
            echo "</table></html>" >> $webdir/$usrid/index.html

        done
    echo "</ul></html>" >> $webdir/index.html


    # Send message via jabber
    sqlite3 $db "SELECT \
        O_.opid, O_.opname, O_.lgn, O_.dsc, B_.bal, O_.ntfdate, U_.xmpp \
        FROM op O_, bal B_, usr U_ WHERE \
        B_.opid = O_.opid AND \
        U_.usrid = O_.usrid AND \
        B_.baldate = (SELECT MAX(B2_.baldate) FROM bal B2_ WHERE B2_.opid = O_.opid) AND \
        date(O_.ntfdate) < '$d' AND \
        O_.ntf = 1 AND \
        B_.bal < '$limit';" |\
        while read line2; do
            opid=`echo $line2 | cut -d'|' -f1`
            opname=`echo $line2 | cut -d'|' -f2`
            lgn=`echo $line2 | cut -d'|' -f3`
            dsc=`echo $line2 | cut -d'|' -f4`
            bal=`echo $line2 | cut -d'|' -f5`
            xmpp=`echo $line2 | cut -d'|' -f6`

            if [ -n "$xmpp" ]; then
                echo -ne "$lgn ($opname) less then  $limit\n$dsc\n\n" | /usr/lib/perl5/site_perl/bin/sendxmpp $xmpp
            fi

            sqlite3 $db "UPDATE op SET ntfdate='$d' WHERE opid=$opid"
        done

fi
