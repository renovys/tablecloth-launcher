#!/bin/bash
# 식탁보 앱 번들을 만들고 응용 프로그램 폴더에 설치한다.

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
APP_PATH="/Applications/식탁보.app"
LSREGISTER_PATH="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
TEMP_ROOT=''
if [ -n "$TMPDIR" ]; then
	TEMP_BASE="$TMPDIR"
else
	TEMP_BASE="/tmp"
fi

fail() {
	echo "빌드 실패: $1" >&2
	exit 1
}

if [ -e "$APP_PATH" ] || [ -L "$APP_PATH" ]; then
	echo "이미 설치된 앱이 있습니다: $APP_PATH"
	printf '기존 앱을 덮어쓰겠습니까? [y/N] '
	IFS= read -r answer || fail '응답을 읽지 못했습니다.'
	case "$answer" in
		y|Y|yes|YES|예) ;;
		*) echo '설치를 취소했습니다.'; exit 0 ;;
	esac
fi

[ -x /usr/bin/sips ] || fail 'sips를 찾지 못했습니다.'
[ -x /usr/bin/iconutil ] || fail 'iconutil을 찾지 못했습니다.'
[ -x /usr/bin/plutil ] || fail 'plutil을 찾지 못했습니다.'
[ -x "$LSREGISTER_PATH" ] || fail 'lsregister를 찾지 못했습니다.'
[ -f "$SCRIPT_DIR/src/launcher.sh" ] || fail 'src/launcher.sh를 찾지 못했습니다.'
[ -f "$SCRIPT_DIR/src/Info.plist" ] || fail 'src/Info.plist를 찾지 못했습니다.'
[ -f "$SCRIPT_DIR/assets/tablecloth-logo.png" ] || fail 'assets/tablecloth-logo.png를 찾지 못했습니다.'

TEMP_ROOT="$(/usr/bin/mktemp -d "$TEMP_BASE/tablecloth-launcher-build.XXXXXX" 2>/dev/null)" || fail '임시 빌드 폴더를 만들지 못했습니다.'
trap '/bin/rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM

STAGING_APP="$TEMP_ROOT/식탁보.app"
CONTENTS_DIR="$STAGING_APP/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$TEMP_ROOT/AppIcon.iconset"

/bin/mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR" || fail '앱 번들 폴더를 만들지 못했습니다.'
/bin/cp "$SCRIPT_DIR/src/launcher.sh" "$MACOS_DIR/launcher" || fail '런처를 번들에 복사하지 못했습니다.'
/bin/cp "$SCRIPT_DIR/src/Info.plist" "$CONTENTS_DIR/Info.plist" || fail 'Info.plist를 번들에 복사하지 못했습니다.'
/bin/chmod 755 "$MACOS_DIR/launcher" || fail '런처 실행 권한을 설정하지 못했습니다.'
/usr/bin/plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null || fail 'Info.plist 문법 검증에 실패했습니다.'

make_icon() {
	icon_size="$1"
	icon_dpi="$2"
	icon_name="$3"
	/usr/bin/sips -s dpiWidth "$icon_dpi" -s dpiHeight "$icon_dpi" -z "$icon_size" "$icon_size" "$SCRIPT_DIR/assets/tablecloth-logo.png" --out "$ICONSET_DIR/$icon_name" >/dev/null || fail "아이콘 $icon_name 을 만들지 못했습니다."
}

make_icon 16 72 'icon_16x16.png'
make_icon 32 144 'icon_16x16@2x.png'
make_icon 32 72 'icon_32x32.png'
make_icon 64 144 'icon_32x32@2x.png'
make_icon 128 72 'icon_128x128.png'
make_icon 256 144 'icon_128x128@2x.png'
make_icon 256 72 'icon_256x256.png'
make_icon 512 144 'icon_256x256@2x.png'
make_icon 512 72 'icon_512x512.png'
make_icon 1024 144 'icon_512x512@2x.png'

if ! /usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns" >/dev/null 2>&1; then
    echo 'iconutil 변환이 실패해 호환용 ICNS 변환을 다시 시도합니다.' >&2
    [ -x /usr/bin/perl ] || fail 'iconutil과 Perl을 모두 사용할 수 없어 icns 아이콘을 만들지 못했습니다.'
    /usr/bin/perl -e 'use bytes; my $iconset = shift @ARGV; my $out = "icns" . pack("N", 0); my @items = (["ic04", "icon_16x16.png"], ["ic11", "icon_16x16\@2x.png"], ["ic05", "icon_32x32.png"], ["ic12", "icon_32x32\@2x.png"], ["ic07", "icon_128x128.png"], ["ic13", "icon_128x128\@2x.png"], ["ic08", "icon_256x256.png"], ["ic14", "icon_256x256\@2x.png"], ["ic09", "icon_512x512.png"], ["ic10", "icon_512x512\@2x.png"]); for my $item (@items) { open my $fh, "<", "$iconset/$item->[1]" or die $!; binmode $fh; local $/; my $data = <$fh>; close $fh; $out .= pack("a4N", $item->[0], length($data) + 8) . $data; } substr($out, 4, 4, pack("N", length($out))); binmode STDOUT; print $out;' "$ICONSET_DIR" > "$RESOURCES_DIR/AppIcon.icns" || fail '호환용 icns 아이콘을 만들지 못했습니다.'
fi
[ -s "$RESOURCES_DIR/AppIcon.icns" ] || fail 'icns 아이콘 파일이 비어 있습니다.'
VERIFY_ICONSET_DIR="$TEMP_ROOT/IconVerification.iconset"
/usr/bin/iconutil -c iconset -o "$VERIFY_ICONSET_DIR" "$RESOURCES_DIR/AppIcon.icns" >/dev/null 2>&1 || fail '생성한 icns 아이콘을 다시 읽지 못했습니다.'
for icon_name in icon_16x16.png icon_16x16@2x.png icon_32x32.png icon_32x32@2x.png icon_128x128.png icon_128x128@2x.png icon_256x256.png icon_256x256@2x.png icon_512x512.png icon_512x512@2x.png; do
    [ -s "$VERIFY_ICONSET_DIR/$icon_name" ] || fail "생성한 icns에서 $icon_name 을 확인하지 못했습니다."
done

if [ -e "$APP_PATH" ] || [ -L "$APP_PATH" ]; then
	/bin/rm -rf "$APP_PATH" || fail '기존 앱을 덮어쓰지 못했습니다.'
fi
/bin/mv "$STAGING_APP" "$APP_PATH" || fail '앱을 응용 프로그램 폴더에 설치하지 못했습니다.'

"$LSREGISTER_PATH" -u "$APP_PATH" >/dev/null 2>&1 || true
"$LSREGISTER_PATH" -f "$APP_PATH" >/dev/null 2>&1 || fail '앱 등록에 실패했습니다.'
/usr/bin/touch "$APP_PATH"
/usr/bin/killall Dock >/dev/null 2>&1 || true

echo "식탁보 앱을 설치했습니다: $APP_PATH"
echo '앱 등록과 Dock 아이콘 캐시 갱신을 마쳤습니다.'
