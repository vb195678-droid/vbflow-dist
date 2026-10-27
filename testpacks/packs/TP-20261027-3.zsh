# 测试包 3「升级源测速」：GitHub raw 清单、jsDelivr 清单、GitHub Releases 安装包前 10MB 的速度（写 /dev/null，不存盘）。
export LC_ALL=C
jesc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\000-\037'; }
RAW="https://raw.githubusercontent.com/vb195678-droid/vbflow-dist/main/imconsole/manifest.json"
JSD="https://cdn.jsdelivr.net/gh/vb195678-droid/vbflow-dist@main/imconsole/manifest.json"
one() {   # 名字 地址 [范围] → 一行 JSON
  local w; w=$(curl -sL ${3:+-r} ${3:+$3} --connect-timeout 10 --max-time ${4:-30} -o /dev/null -w '%{http_code} %{speed_download} %{size_download} %{time_connect} %{time_starttransfer} %{time_total}' "$2" 2>/dev/null)
  set -- "$1" "$2" ${=w:-000 0 0 0 0 0}
  echo "$1：HTTP $3  收到 $5 字节  速度 $(awk -v s=$4 'BEGIN{printf "%.0f", s/1024}') KB/s  连上 $6 s  首字节 $7 s  共 $8 s"
  printf '{"name":"%s","url":"%s","http":"%s","bytes":%s,"KBps":%s,"connectS":%s,"ttfbS":%s,"totalS":%s}' "$(jesc "$1")" "$(jesc "$2")" "$3" "${5%.*}" "$(awk -v s=$4 'BEGIN{printf "%.0f", s/1024}')" "$6" "$7" "$8" >> rows
  echo >> rows
}
: > rows
one "GitHub raw 清单" "$RAW"
one "jsDelivr 清单" "$JSD"
# 最新安装包地址从 GitHub raw 清单里读，读不到再试 jsDelivr
curl -sL --max-time 20 -o m.json "$RAW" 2>/dev/null; PKG=$(plutil -extract parts.0.url raw -o - m.json 2>/dev/null)
[ -z "$PKG" ] && { curl -sL --max-time 20 -o m.json "$JSD" 2>/dev/null; PKG=$(plutil -extract parts.0.url raw -o - m.json 2>/dev/null); }
[ -n "$PKG" ] && one "GitHub Releases 安装包前 10MB" "$PKG" 0-10485759 120
RJ=$(paste -sd, rows)
printf '{"pack":"升级源测速","rows":[%s]}' "$RJ" > "$VBTA_RESULT"
SUM=$(awk -F'"' '{ for(i=1;i<NF;i++){ if($i=="name")n=$(i+2); if($i=="http")h=$(i+2) } match($0,/"KBps":[0-9]+/); k=substr($0,RSTART+7,RLENGTH-7); printf "%s%s %s", (NR>1?"；":""), n, (h ~ /^2/ ? k " KB/s" : "失败(HTTP " h ")") }' rows)
printf '升级源：%s%s' "$SUM" "$( [ -z "$PKG" ] && echo '；清单读不到，安装包没测')" > "$VBTA_SUMMARY"
cat "$VBTA_SUMMARY"; echo
