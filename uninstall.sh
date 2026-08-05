#!/bin/bash
# 식탁보 앱과 이 런처가 만든 상태 파일을 제거한다.

APP_PATH="/Applications/식탁보.app"
STATE_DIR="$HOME/Library/Application Support/TableClothLauncher"

echo '다음 항목을 제거합니다.'
echo "- $APP_PATH"
echo "- $STATE_DIR"
printf '계속하겠습니까? [y/N] '
IFS= read -r answer || { echo '응답을 읽지 못해 취소했습니다.' >&2; exit 1; }
case "$answer" in
	y|Y|yes|YES|예) ;;
	*) echo '제거를 취소했습니다.'; exit 0 ;;
esac

if [ -e "$APP_PATH" ] || [ -L "$APP_PATH" ]; then
	/bin/rm -rf "$APP_PATH" || { echo '앱 번들을 제거하지 못했습니다.' >&2; exit 1; }
fi
if [ -e "$STATE_DIR" ]; then
	/bin/rm -rf "$STATE_DIR" || { echo '상태 파일을 제거하지 못했습니다.' >&2; exit 1; }
fi

echo '식탁보 앱 번들과 상태 파일을 제거했습니다.'
echo 'Dock에 남은 아이콘은 Dock에서 보조 클릭한 뒤 "Dock에서 제거"를 선택하십시오.'

