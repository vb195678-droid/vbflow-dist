# 测试包 4「局域网体检」：查「公司 Wi-Fi 通道为什么不通」——只读本机网卡、电脑名、睡眠设置，和本机每台服务器自己报的局域网地址。
# 只读、只连 127.0.0.1；不读数据库、钥匙、聊天、开机项。结果：$VBTA_RESULT（JSON）、$VBTA_SUMMARY（一句话）。
export LC_ALL=C
jesc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\000-\037' | cut -c1-300; }
jget() { plutil -extract "$2" raw -o - "$1" 2>/dev/null; }

# ① 电脑名：服务器用「电脑名.local」拼局域网站点地址，读不到就拼不出来
LH=$(scutil --get LocalHostName 2>/dev/null)
CN=$(scutil --get ComputerName 2>/dev/null)
HN=$(scutil --get HostName 2>/dev/null)
echo "LocalHostName=[${LH}] ComputerName=[${CN}] HostName=[${HN}]"

# ② 网卡：每个 en* 的地址、状态；系统主网卡
PRIMARY=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
IFJ=""
for i in $(ifconfig -l); do
  case "$i" in en*) ;; *) continue;; esac
  ip=$(ipconfig getifaddr "$i" 2>/dev/null)
  st=$(ifconfig "$i" 2>/dev/null | awk '/status:/{print $2}')
  [ -z "$ip" ] && [ "$st" != active ] && continue
  echo "网卡 $i 地址 ${ip:-无} 状态 ${st:-?}"
  IFJ="$IFJ${IFJ:+,}{\"if\":\"$i\",\"ip\":\"$(jesc "$ip")\",\"status\":\"$(jesc "$st")\"}"
done
echo "系统主网卡：${PRIMARY:-无}"

# ③ 睡眠设置（总控报「永不睡眠」异常用）
SLP=$(pmset -g 2>/dev/null | awk '$1=="sleep"||$1=="displaysleep"||$1=="disksleep"{printf "%s=%s ",$1,$2}')
echo "睡眠：$SLP"

# ④ 主机名解析：电脑名.local 在本机能不能解析成地址
RES=""
if [ -n "$LH" ]; then RES=$(dscacheutil -q host -a name "$LH.local" 2>/dev/null | awk '/ip_address/{print $2}' | head -3 | tr '\n' ' '); fi
echo "解析 $LH.local → ${RES:-解析不出}"

# ⑤ 每台服务器自己报的：/health 与 /endpoints（公开信息）、局域网站点 8444 系口能不能连
SUP="$HOME/Library/Application Support"
SJ=""; SUM=""
for f in "$SUP/IMServer/instance.json" "$SUP"/IMServer-实例/*/instance.json(N); do
  [ -f "$f" ] || continue
  port=$(jget "$f" port); [ -n "$port" ] || continue
  inum=$(jget "$f" number)
  curl -s --max-time 5 "http://127.0.0.1:$port/api/v1/health" > h.json 2>/dev/null
  ok=$(jget h.json ok); num=$(jget h.json serverNumber); ver=$(jget h.json version)
  curl -s --max-time 5 "http://127.0.0.1:$port/api/v1/endpoints" > e.json 2>/dev/null
  EP=$(head -c 2500 e.json | tr -d '\000-\037')
  lanport=$(( 8444 + 100 * ((port - 8479) / 2) ))   # 局域网站点口：1 号 8444，第 N 号 = 8444 + 100×(N−1)（M64 实例 3 → 8644、实例 6 → 8944 对得上）
  lanh=$(curl -sk --max-time 5 -o /dev/null -w '%{http_code}' "https://127.0.0.1:$lanport/api/v1/health" 2>/dev/null)
  listen=$(netstat -an -p tcp 2>/dev/null | awk -v p=".$lanport" '$6=="LISTEN" && index($4,p){print $4}' | head -3 | tr '\n' ' ')
  echo "== 端口 $port 实例 ${inum:-1} 服务器号 ${num:-?} 版本 ${ver:-?} 状态 ${ok:-没响应}；局域网口 $lanport 自测 HTTP ${lanh:-无} 监听 ${listen:-没有}"
  echo "   endpoints（前 2500 字）：$EP"
  SJ="$SJ${SJ:+,}{\"port\":$port,\"instance\":${inum:-1},\"serverNumber\":\"$(jesc "$num")\",\"version\":\"$(jesc "$ver")\",\"lanPort\":$lanport,\"lanSelfTestHTTP\":\"$(jesc "$lanh")\",\"lanListen\":\"$(jesc "$listen")\",\"endpoints\":\"$(jesc "$EP")\"}"
  SUM="$SUM${SUM:+；}${num:-端口$port} 局域网口$lanport HTTP ${lanh:-无}"
done
[ -z "$SJ" ] && SUM="这台电脑没找到在跑的服务器"

printf '{"pack":"局域网体检","localHostName":"%s","computerName":"%s","hostName":"%s","primaryIf":"%s","interfaces":[%s],"sleep":"%s","localResolve":"%s","servers":[%s]}' \
  "$(jesc "$LH")" "$(jesc "$CN")" "$(jesc "$HN")" "$(jesc "$PRIMARY")" "$IFJ" "$(jesc "$SLP")" "$(jesc "$RES")" "$SJ" | head -c 9000 > "$VBTA_RESULT"
printf '局域网体检：电脑名[%s] 主网卡 %s 解析 %s；%s' "$LH" "${PRIMARY:-无}" "${RES:-解析不出}" "$SUM" > "$VBTA_SUMMARY"
cat "$VBTA_SUMMARY"; echo
