#!/bin/bash
# Validate generated TPCx-AI UC03/UC08 data (run after gen_sf.sh, on the generation machine):
#   M3/datagen/validate_sf.sh <data root> <log dir> SF...   e.g. ~/Works_ub/m3data/data ~/Works_ub/m3data 1 3 9 10
# Checks: PDGF log, 14 files + headers + trailing newline, row counts vs schema formulas, order ids 1..N,
#   lineitem order/product references, every order has a line item, scoring labels. Uses plain comma split:
#   department names with quoted commas (e.g. "LIQUOR,WINE,BEER") are not field-checked.
# Expected sizes come from data-gen/config/tpcxai-schema.xml:
#   CUSTOMER = 100000*sqrt(SF)*TTVF, WEEKS = max(104,(floor(log10 SF)+2)*52), ORDER = floor(CUSTOMER*0.5*WEEKS)
#   PRODUCT = floor(1000*sqrt(SF)), STORES = round(sqrt(SF)+10), store_dept = STORES*68; scoring is -sf 1.
ROOT=$1; LOGS=$2; shift 2
FAIL=0
ok()  { printf "  OK   %s\n" "$*"; }
bad() { printf "  FAIL %s\n" "$*"; FAIL=1; }
chk() { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: got $2, expected $3"; fi; }

for SF in "$@"; do
  D=$ROOT/sf$SF; L=$LOGS/gen_sf$SF.log
  echo "===== SF$SF ($D)"
  read TR_O SV_O PR SD <<<"$(awk -v s=$SF 'BEGIN{q=sqrt(s); w=int(log(s)/log(10)+1e-9); w=(w+2)*52; if(w<104)w=104;
     printf "%d %d %d %d", int(100000*q*0.5*w), int(100000*q*0.1*0.5*w), int(1000*q), int(q+10+0.5)*68}')"

  # log
  chk "log: 'All work done'" "$(grep -c 'All work done' $L)" 3
  chk "log: Exception lines" "$(grep -c 'Exception' $L)" 0
  grep -q '\] done' $L && ok "log: done marker" || bad "log: no done marker"

  # files, headers, trailing newline
  chk "file count" "$(find $D -name '*.csv' | wc -l)" 14
  declare -A H=(
    [training/order]="o_order_id,o_customer_sk,weekday,date,store,trip_type"
    [serving/order]="o_order_id,o_customer_sk,weekday,date,store"
    [scoring/order]="o_order_id,o_customer_sk,weekday,date,store"
    [scoring/order_labels]="o_order_id,trip_type"
    [scoring/store_dept]="store,department,periods"
    [scoring/store_dept_labels]="store,department,date,weekly_sales")
  for sp in training serving scoring; do
    for t in lineitem product store_dept order; do H[$sp/$t]=${H[$sp/$t]:-}; done
  done
  hdr_ok=1
  for f in $(cd $D && find . -name '*.csv' | sed 's|^\./||; s|\.csv$||' | sort); do
    exp=${H[$f]}
    case $f in */lineitem) exp="li_order_id,li_product_id,quantity,price";; */product) exp="p_product_id,name,department";;
               training/store_dept) exp="store,department";; serving/store_dept) exp="store,department,periods";; esac
    [ "$(head -1 $D/$f.csv)" = "$exp" ] || { bad "header $f: $(head -1 $D/$f.csv)"; hdr_ok=0; }
    [ "$(tail -c1 $D/$f.csv | od -An -c | tr -d ' ')" = '\n' ] || { bad "$f: no trailing newline (truncated?)"; hdr_ok=0; }
  done
  [ $hdr_ok = 1 ] && ok "headers and trailing newlines (14 files)"

  for sp in training serving scoring; do
    if [ $sp = scoring ]; then EO=520000; EP=1000; ES=748; else EP=$PR; ES=$SD; [ $sp = training ] && EO=$TR_O || EO=$SV_O; fi
    NP=$(($(wc -l < $D/$sp/product.csv)-1))
    chk "$sp product rows" $NP $EP
    chk "$sp store_dept rows" $(($(wc -l < $D/$sp/store_dept.csv)-1)) $ES
    # order: ids 1..N in order, constant field count, non-empty fields, date range
    r=$(awk -F, 'NR==1{nf=NF;next} {n++; if($1!=n)bad++; if(NF!=nf)nfbad++; for(i=1;i<=NF;i++) if($i==""||$i=="\"\"")empty++;
          d=$4; gsub(/"/,"",d); if(d!~/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/)dbad++; if(mn==""||d<mn)mn=d; if(d>mx)mx=d}
          END{printf "%d %d %d %d %d %s~%s", n, bad, nfbad, empty, dbad, mn, mx}' $D/$sp/order.csv)
    read n idbad nfbad empty dbad range <<<"$r"
    chk "$sp order rows" $n $EO
    [ $((idbad+nfbad+empty+dbad)) = 0 ] && ok "$sp order: ids 1..N, fields, dates valid ($range)" \
      || bad "$sp order: idgap=$idbad fieldcount=$nfbad empty=$empty baddate=$dbad"
    # lineitem: order id sorted and within 1..N, every order has a line, product id within 1..P, field count
    r=$(awk -F, -v N=$n -v P=$NP 'NR==1{nf=NF;next} {c++; o=$1+0; if(o<prev)unsorted++; if(o<1||o>N)orange++; if(o!=prev)distinct++; prev=o;
          p=$2+0; if(p<1||p>P)prange++; if(NF!=nf)nfbad++; if($3==""||$4=="")empty++}
          END{printf "%d %d %d %d %d %d %d", c, distinct, unsorted, orange, prange, nfbad, empty}' $D/$sp/lineitem.csv)
    read c distinct unsorted orange prange nfbad empty <<<"$r"
    [ $((unsorted+orange+prange+nfbad+empty)) = 0 ] && [ $distinct = $n ] \
      && ok "$sp lineitem: $c rows, all $n orders covered, ids/product refs valid" \
      || bad "$sp lineitem: rows=$c distinctOrders=$distinct/$n unsorted=$unsorted orderRange=$orange productRange=$prange fields=$nfbad empty=$empty"
  done
  # scoring labels
  r=$(awk -F, 'NR>1{n++; if($1!=n)bad++; if($2=="")empty++} END{print n+0, bad+0, empty+0}' $D/scoring/order_labels.csv)
  read n b e <<<"$r"; [ "$n $b $e" = "520000 0 0" ] && ok "scoring order_labels: 520000 ids match orders" || bad "order_labels: n=$n idgap=$b empty=$e"
  chk "scoring store_dept_labels rows" $(($(wc -l < $D/scoring/store_dept_labels.csv)-1)) 38896
done
echo; [ $FAIL = 0 ] && echo "ALL CHECKS PASSED" || echo "SOME CHECKS FAILED"
exit $FAIL
