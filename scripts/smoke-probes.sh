# shellcheck shell=bash
# MTranServer：无账号体系，应用只认 API 令牌；网页经网关代注入 Bearer，带用户会话即可调翻译接口。

web_assert() { grep -qi 'MTranServer'; }   # 标准输入：SPA 首页 HTML 的 <title>

# 插件的用户数据是下载好的翻译模型和配置：翻一句带随机标记的英文（首次触发 en→zh-Hans 的模型下载，
# 可能要几分钟），标记存进 $SMOKE_STATE，重装后核对。
marker_file() { # SMOKE_STATE 在套件里是状态目录（e2e 传的是标记文件本身）
  if [[ -d "$SMOKE_STATE" ]]; then printf '%s' "$SMOKE_STATE/mtranserver-marker"; else printf '%s' "${SMOKE_STATE}.marker"; fi
}

data_write() {
  local marker out
  marker="wonton smoke $(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
  out="$(dweb /translate -X POST -H 'Content-Type: application/json' \
    --data "{\"from\":\"en\",\"to\":\"zh-Hans\",\"text\":\"$marker\"}")" ||
    { echo "翻译请求失败：$out"; return 1; }
  jq -er '.result // empty' <<<"$out" | grep -q . || { echo "译文为空或形状不对：$out"; return 1; }
  printf '%s' "$marker" >"$(marker_file)"
}

data_check() { # 模型目录还在且同一句翻得出来
  local marker out files
  marker="$(cat "$(marker_file)")"
  [[ -n "$marker" ]] || { echo "SMOKE_STATE 里没有标记"; return 1; }
  files="$(docker exec "wonton-$SMOKE_INSTANCE--mtranserver" sh -c 'ls /app/models 2>/dev/null')" ||
    { echo "列不出模型目录"; return 1; }
  grep -q . <<<"$files" || { echo "模型目录是空的，下载的模型没保住：$files"; return 1; }
  out="$(dweb /translate -X POST -H 'Content-Type: application/json' \
    --data "{\"from\":\"en\",\"to\":\"zh-Hans\",\"text\":\"$marker\"}")" ||
    { echo "翻译请求失败：$out"; return 1; }
  jq -er '.result // empty' <<<"$out" | grep -q . || { echo "重装后翻译不出结果：$out"; return 1; }
}
