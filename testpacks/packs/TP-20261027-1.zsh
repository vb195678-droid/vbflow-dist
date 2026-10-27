# 测试包 1「通道体检」：读本机每台服务器的 7 条通道状态和原因（/admin/api/conn/channels，本机只读）、/health、服务器号、版本。
# 只读、只连 127.0.0.1；不读数据库、钥匙、聊天。结果：$VBTA_RESULT（JSON）、$VBTA_SUMMARY（一句话）。
export LC_ALL=C
jesc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\000-\037'; }
jget() { plutil -extract "$2" raw -o - "$1" 2>/dev/null; }
SUP="$HOME/Library/Application Support"
SJ=""; SUM=""
for f in "$SUP/IMServer/instance.json" "$SUP"/IMServer-实例/*/instance.json(N); do
  [ -f "$f" ] || continue
  port=$(jget "$f" port); [ -n "$port" ] || continue
  [ -n "$VBTA_ONLY_PORT" ] && [ "$port" != "$VBTA_ONLY_PORT" ] && continue
  inum=$(jget "$f" number)
  curl -s --max-time 5 "http://127.0.0.1:$port/api/v1/health" > h.json 2>/dev/null
  ok=$(jget h.json ok); num=$(jget h.json serverNumber); ver=$(jget h.json version); bld=$(jget h.json build)
  name=$(jget "${f:h}/data/server-name.json" serverName)
  echo "== 端口 $port 实例 ${inum:-1} 服务器号 ${num:-?} 版本 ${ver:-?} 状态 ${ok:-没响应}"
  CHJ=""; okn=0; tot=0; okids=""
  if [ "$ok" = true ]; then
    curl -s --max-time 25 "http://127.0.0.1:$port/admin/api/conn/channels" > ch.json 2>/dev/null
    k=0
    while cid=$(jget ch.json rows.$k.id); do
      cok=$(jget ch.json rows.$k.ok); cwhy=$(jget ch.json rows.$k.why); cname=$(jget ch.json rows.$k.name); cms=$(jget ch.json rows.$k.ms); cdev=$(jget ch.json rows.$k.devices)
      tot=$((tot+1)); [ "$cok" = true ] && { okn=$((okn+1)); okids="$okids$cid"; }
      echo "   $cname：$( [ "$cok" = true ] && echo 通 || echo 不通)  $cwhy"
      CHJ="$CHJ${CHJ:+,}{\"id\":\"$(jesc "$cid")\",\"name\":\"$(jesc "$cname")\",\"ok\":$( [ "$cok" = true ] && echo true || echo false),\"why\":\"$(jesc "$cwhy")\",\"ms\":${cms:-null},\"devices\":${cdev:-0}}"
      k=$((k+1)); [ $k -gt 20 ] && break
    done
    pt=$(jget ch.json punchStats.today.tries); po=$(jget ch.json punchStats.today.ok)
    pr=$(jget ch.json paidRelay.on); lastwhy=$(jget ch.json punchStats.last.why); mynat=$(jget ch.json punchStats.last.myNat)
    echo "   打洞今天 ${po:-0}/${pt:-0}  本机 NAT ${mynat:-?}  上次打洞：${lastwhy:-无}"
  fi
  SJ="$SJ${SJ:+,}{\"port\":$port,\"instance\":${inum:-1},\"serverNumber\":\"$(jesc "$num")\",\"name\":\"$(jesc "$name")\",\"version\":\"$(jesc "$ver")\",\"build\":\"$(jesc "$bld")\",\"healthOK\":$( [ "$ok" = true ] && echo true || echo false),\"channels\":[$CHJ],\"punchToday\":\"${po:-0}/${pt:-0}\",\"myNat\":\"$(jesc "$mynat")\",\"lastPunchWhy\":\"$(jesc "$lastwhy")\",\"paidRelayOn\":$( [ "$pr" = true ] && echo true || echo false)}"
  SUM="$SUM${SUM:+；}${num:-端口$port} ${ver:-?} $( [ "$ok" = true ] && echo "通 $okn/$tot（${okids:-无}）" || echo 没响应)"
done
[ -z "$SJ" ] && SUM="这台电脑没找到在跑的服务器"
printf '{"pack":"通道体检","servers":[%s]}' "$SJ" > "$VBTA_RESULT"
printf '通道体检：%s' "$SUM" > "$VBTA_SUMMARY"
cat "$VBTA_SUMMARY"; echo
