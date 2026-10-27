# 测试包 2「连我们的线路」：到香港 / 新加坡登记处、上海中转、新加坡中转的延迟和丢包（TCP 连 10 次 + ping 10 次），
# STUN 看 NAT 类型，IPv6 有没有。只连这些地址，不读本机文件。
export LC_ALL=C
jesc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\000-\037'; }
cat > targets <<'T'
hk-registry|香港登记处|43.199.238.231|9445
sg-registry|新加坡登记处|54.255.124.28|9444
sh-relay|上海中转|47.117.8.76|8446
sg-relay|新加坡中转|18.143.103.28|8447
T
tcp10() {   # 名字 主机 端口 → 平均 最慢 失败次数（毫秒）
  local n=0 t; : > "tcp.$1"
  while [ $n -lt 10 ]; do
    t=$(curl -sk -o /dev/null -I --connect-timeout 3 --max-time 4 -w '%{time_connect}' "https://$2:$3/" 2>/dev/null)
    echo "${t:-0}" >> "tcp.$1"; n=$((n+1))
  done
  awk '{ if ($1+0>0){ok++; s+=$1*1000; if($1*1000>mx)mx=$1*1000} else f++ } END{ if(ok) printf "%.0f %.0f %d\n", s/ok, mx, f+0; else printf "null null %d\n", f+0 }' "tcp.$1" > "tcpr.$1"
}
ping10() {
  ping -c 10 -i 1 -t 15 "$2" > "ping.$1" 2>&1
  loss=$(sed -n 's/.* \([0-9.]*\)% packet loss.*/\1/p' "ping.$1"); avg=$(sed -n 's/.*= [0-9.]*\/\([0-9.]*\)\/.*/\1/p' "ping.$1")
  echo "${loss:-null} ${avg:-null}" > "pingr.$1"
}
while IFS='|' read -r id name host port; do tcp10 "$id" "$host" "$port" </dev/null & ping10 "$id" "$host" </dev/null & done < targets
wait
TJ=""; SUM=""
while IFS='|' read -r id name host port; do
  read -r tavg tmax tfail < "tcpr.$id"; read -r ploss pavg < "pingr.$id"
  echo "$name $host:$port  TCP 平均 ${tavg} ms 最慢 ${tmax} ms 失败 ${tfail}/10   ping 丢包 ${ploss}% 平均 ${pavg} ms"
  TJ="$TJ${TJ:+,}{\"id\":\"$id\",\"name\":\"$name\",\"host\":\"$host\",\"port\":$port,\"tcpAvgMs\":$tavg,\"tcpMaxMs\":$tmax,\"tcpFail\":$tfail,\"pingLossPct\":$ploss,\"pingAvgMs\":$pavg}"
  SUM="$SUM${SUM:+，}$name $( [ "$tavg" = null ] && echo 不通 || echo "${tavg}ms") 丢$((tfail*10))%"
done < targets
# NAT 类型（同一个 UDP 口问几台 STUN：外网口都一样 = cone，好打洞；不一样 = symmetric，难打洞）
"$VBTA_TOOL" stun 43.199.238.231:3478 54.255.124.28:3478 stun.miwifi.com:3478 stun.chat.bilibili.com:3478 stun.cloudflare.com:3478 > stun.txt 2>&1
cat stun.txt
NAT=$(sed -n 's/^NAT=//p' stun.txt)
SJ=""; while read -r a b c; do case "$a" in NAT=*) ;; *) SJ="$SJ${SJ:+,}\"$(jesc "$a $b $c")\"";; esac; done < stun.txt
# IPv6
V6ADDR=$(ifconfig 2>/dev/null | awk '/inet6 /{print $2}' | grep -v '^fe80' | grep -v '^::1' | grep -v '^fd' | head -1)
V6=no
for u in https://6.ipw.cn https://ipv6.google.com; do
  c=$(curl -6 -s -o /dev/null -w '%{http_code}' --connect-timeout 4 --max-time 6 "$u" 2>/dev/null); case "$c" in 2*|3*) V6=yes; break;; esac
done
echo "IPv6：本机公网地址 $( [ -n "$V6ADDR" ] && echo 有 || echo 没有)，能上 IPv6 网站 $V6"
printf '{"pack":"连我们的线路","targets":[%s],"nat":"%s","stun":[%s],"ipv6":{"globalAddr":%s,"reach":%s}}' \
  "$TJ" "$(jesc "$NAT")" "$SJ" "$( [ -n "$V6ADDR" ] && echo true || echo false)" "$( [ $V6 = yes ] && echo true || echo false)" > "$VBTA_RESULT"
printf '线路：%s；NAT %s；IPv6 %s' "$SUM" "${NAT:-?}" "$( [ $V6 = yes ] && echo 有 || echo 没有)" > "$VBTA_SUMMARY"
cat "$VBTA_SUMMARY"; echo
