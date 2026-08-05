#!/bin/bash
# 식탁보 런처 — macOS에서 macSandbox로 식탁보를 실행하는 비공식 보조 도구
# Copyright (C) 2026 renovys
# 이 프로그램은 GNU Affero General Public License v3.0 조건으로 배포된다.
# 식탁보(TableCloth)와 macSandbox는 yourtablecloth 프로젝트의 저작물이며
# 이 런처는 원 프로젝트와 무관한 개인 제작물이다. 자세한 고지는 NOTICE 참고.
#
# 식탁보를 실행하고, 다음 실행을 위한 업데이트 확인을 예약한다.
# macSandbox는 샌드박스 세션이 이미 떠 있으면 .wsb 전달을 무시할 수 있다.
# 따라서 현재 세션을 정리한 뒤 open -a로 설정 파일을 전달한다.

STATE_DIR="$HOME/Library/Application Support/TableClothLauncher"
if [ -n "$TABLECLOTH_WSB_PATH" ]; then
	WSB_PATH="$TABLECLOTH_WSB_PATH"
else
	WSB_PATH="$HOME/Documents/식탁보/no-install-spork.wsb"
fi
SANDBOX_APP="/Applications/macSandbox for Windows.app"
SANDBOX_BUNDLE_ID="com.rkttu.macsandbox"
LAUNCHER_APP="/Applications/식탁보.app"
WSB_URL="https://github.com/yourtablecloth/TableCloth/releases/latest/download/no-install-spork.wsb"
LAUNCHER_RELEASE_API="https://api.github.com/repos/renovys/tablecloth-launcher/releases/latest"
SANDBOX_RELEASE_API="https://api.github.com/repos/yourtablecloth/macSandbox/releases/latest"
UPDATE_LOCK_DIR="$STATE_DIR/.update-lock"
WSB_STATE_FILE="$STATE_DIR/wsb.state"
LAUNCHER_STATE_FILE="$STATE_DIR/launcher.state"
SANDBOX_STATE_FILE="$STATE_DIR/macsandbox.state"
NOTIFICATION_STATE_FILE="$STATE_DIR/notifications.state"
LAUNCHER_PENDING_FILE="$STATE_DIR/launcher.pending"
SANDBOX_PENDING_FILE="$STATE_DIR/macsandbox.pending"
AUTO_INSTALL_FILE="$STATE_DIR/launcher-auto-install"

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "$0")"

if [ -f "$SCRIPT_DIR/../Info.plist" ]; then
	LAUNCHER_INFO_PLIST="$SCRIPT_DIR/../Info.plist"
elif [ -f "$SCRIPT_DIR/Info.plist" ]; then
	LAUNCHER_INFO_PLIST="$SCRIPT_DIR/Info.plist"
else
	LAUNCHER_INFO_PLIST=""
fi

current_epoch() {
	/bin/date +%s
}

current_time() {
	/bin/date '+%Y-%m-%dT%H:%M:%S%z'
}

state_value() {
	state_file="$1"
	state_key="$2"
	[ -r "$state_file" ] || return 1
	/usr/bin/awk -F= -v key="$state_key" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$state_file" 2>/dev/null
}

write_provider_state() {
	state_file="$1"
	status_value="$2"
	reason_value="$3"
	epoch_value="$4"
	time_value="$5"
	latest_value="$6"
	installed_value="$7"
	pending_value="$8"
	temp_state="$(/usr/bin/mktemp "$STATE_DIR/.state.XXXXXX" 2>/dev/null)" || return 1
	{
		printf 'last_check_epoch=%s\n' "$epoch_value"
		printf 'last_check_time=%s\n' "$time_value"
		printf 'status=%s\n' "$status_value"
		printf 'reason=%s\n' "$reason_value"
		printf 'latest_version=%s\n' "$latest_value"
		printf 'installed_version=%s\n' "$installed_value"
		printf 'pending=%s\n' "$pending_value"
	} > "$temp_state" || {
		/bin/rm -f "$temp_state"
		return 1
	}
	/bin/mv -f "$temp_state" "$state_file" || {
		/bin/rm -f "$temp_state"
		return 1
	}
}

write_notification_state() {
	notification_type="$1"
	notification_status="$2"
	notification_reason="$3"
	temp_state="$(/usr/bin/mktemp "$STATE_DIR/.notification.XXXXXX" 2>/dev/null)" || return 1
	{
		printf 'last_time=%s\n' "$(current_time)"
		printf 'type=%s\n' "$notification_type"
		printf 'status=%s\n' "$notification_status"
		printf 'reason=%s\n' "$notification_reason"
	} > "$temp_state" || {
		/bin/rm -f "$temp_state"
		return 1
	}
	/bin/mv -f "$temp_state" "$NOTIFICATION_STATE_FILE" || {
		/bin/rm -f "$temp_state"
		return 1
	}
}

write_pending() {
	pending_file="$1"
	pending_kind="$2"
	pending_version="$3"
	temp_pending="$(/usr/bin/mktemp "$STATE_DIR/.pending.XXXXXX" 2>/dev/null)" || return 1
	{
		printf '%s\n' "$pending_kind"
		printf '%s\n' "$pending_version"
	} > "$temp_pending" || {
		/bin/rm -f "$temp_pending"
		return 1
	}
	/bin/mv -f "$temp_pending" "$pending_file" || {
		/bin/rm -f "$temp_pending"
		return 1
	}
}

version_is_newer() {
	/usr/bin/awk -v candidate="$1" -v installed="$2" '
	BEGIN {
		sub(/^[vV]/, "", candidate)
		sub(/[^0-9.].*$/, "", candidate)
		sub(/^[vV]/, "", installed)
		sub(/[^0-9.].*$/, "", installed)
		if (candidate !~ /^[0-9]+([.][0-9]+)*$/ || installed !~ /^[0-9]+([.][0-9]+)*$/) {
			exit 1
		}
		candidate_count = split(candidate, candidate_parts, ".")
		installed_count = split(installed, installed_parts, ".")
		limit = candidate_count > installed_count ? candidate_count : installed_count
		for (i = 1; i <= limit; i++) {
			left = i <= candidate_count ? candidate_parts[i] + 0 : 0
			right = i <= installed_count ? installed_parts[i] + 0 : 0
			if (left > right) {
				exit 0
			}
			if (left < right) {
				exit 1
			}
		}
		exit 1
	}'
}

normalize_version() {
	printf '%s\n' "$1" | /usr/bin/sed -e 's/^[vV]//' -e 's/[[:space:]]*$//'
}

extract_release_tag() {
	/usr/bin/sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | /usr/bin/head -n 1
}

extract_launcher_asset_url() {
	/usr/bin/awk '
		/"browser_download_url"[[:space:]]*:/ {
			line = $0
			sub(/^.*"browser_download_url"[[:space:]]*:[[:space:]]*"/, "", line)
			sub(/".*$/, "", line)
			lower = tolower(line)
			if (lower ~ /\.zip([?].*)?$/) {
				print line
				exit
			}
		}
	' "$1"
}

download_url() {
	url="$1"
	destination="$2"
	/usr/bin/curl --fail --location --silent --show-error --retry 2 \
		--connect-timeout 10 --max-time 60 \
		-H 'Accept: application/vnd.github+json' \
		-H 'User-Agent: TableClothLauncher' \
		-o "$destination" "$url"
}

xml_starts_correctly() {
	/usr/bin/awk '
	{
		line = $0
		sub(/^[[:space:]]*/, "", line)
		if (line ~ /^<\?xml([[:space:]]|>)/) {
			found = 1
			exit
		}
		if (line != "") {
			exit
		}
	}
	END {
		if (found) {
			exit 0
		}
		exit 1
	}' "$1"
}

plist_value() {
	plist_file="$1"
	plist_key="$2"
	[ -f "$plist_file" ] || return 1
	/usr/libexec/PlistBuddy -c "Print :$plist_key" "$plist_file" 2>/dev/null
}

check_is_due() {
	state_file="$1"
	last_epoch="$(state_value "$state_file" last_check_epoch 2>/dev/null)"
	case "$last_epoch" in
		''|*[!0-9]*) return 0 ;;
	esac
	now_epoch="$(current_epoch)"
	case "$now_epoch" in
		''|*[!0-9]*) return 0 ;;
	esac
	[ "$now_epoch" -ge "$last_epoch" ] || return 1
	[ $((now_epoch - last_epoch)) -ge 86400 ]
}

begin_provider_check() {
	state_file="$1"
	check_epoch="$(current_epoch)"
	check_time="$(current_time)"
	write_provider_state "$state_file" 'checking' '조회 중입니다.' "$check_epoch" "$check_time" '' '' ''
}

finish_provider_check() {
	state_file="$1"
	status_value="$2"
	reason_value="$3"
	check_epoch="$4"
	check_time="$5"
	latest_value="$6"
	installed_value="$7"
	pending_value="$8"
	write_provider_state "$state_file" "$status_value" "$reason_value" "$check_epoch" "$check_time" "$latest_value" "$installed_value" "$pending_value"
}

launcher_auto_install_enabled() {
	[ -r "$AUTO_INSTALL_FILE" ] || return 1
	setting_value="$(/usr/bin/head -n 1 "$AUTO_INSTALL_FILE" 2>/dev/null | /usr/bin/tr -d '[:space:]')"
	case "$setting_value" in
		1|yes|true|YES|TRUE) return 0 ;;
		*) return 1 ;;
	esac
}

send_notification() {
	notification_title="$1"
	notification_body="$2"
	/usr/bin/osascript \
		-e 'on run argv' \
		-e 'display notification (item 2 of argv) with title (item 1 of argv)' \
		-e 'end run' "$notification_title" "$notification_body" >/dev/null 2>&1
}

# macSandbox 번들 경로에서 실행된 VM 프로세스만 골라 종료한다.
# `ps -Ao comm=`은 실행 파일의 전체 경로를 주므로 번들 경로로 소유를 판별할 수 있다.
# 대상을 하나도 특정하지 못하면 아무것도 죽이지 않는다(남의 VM 보호가 우선).
terminate_sandbox_vms() {
	/bin/ps -Ao pid=,comm= 2>/dev/null | while read -r vm_pid vm_command; do
		case "$vm_command" in
			"$SANDBOX_APP"/*qemu-system-*)
				/bin/kill "$vm_pid" >/dev/null 2>&1
				;;
		esac
	done
	return 0
}

show_error() {
	error_message="$1"
	/usr/bin/osascript \
		-e 'on run argv' \
		-e 'display alert "식탁보 실행 실패" message (item 1 of argv) as critical' \
		-e 'end run' "$error_message" >/dev/null 2>&1
	exit 1
}

show_pending_notifications() {
	[ -d "$STATE_DIR" ] || return 0
	for pending_file in "$LAUNCHER_PENDING_FILE" "$SANDBOX_PENDING_FILE"; do
		[ -f "$pending_file" ] || continue
		pending_kind="$(/usr/bin/sed -n '1p' "$pending_file" 2>/dev/null)"
		pending_version="$(/usr/bin/sed -n '2p' "$pending_file" 2>/dev/null)"
		if [ -z "$pending_version" ]; then
			/bin/rm -f "$pending_file"
			write_notification_state 'unknown' 'error' '대기 중인 업데이트 버전이 비어 있습니다.'
			continue
		fi
		if [ "$pending_file" = "$LAUNCHER_PENDING_FILE" ]; then
			notification_title='식탁보 업데이트 알림'
			if [ "$pending_kind" = 'installed' ]; then
				notification_body="런처를 버전 $pending_version 으로 자동 설치했습니다."
			else
				notification_body="새 런처 버전 $pending_version 을 사용할 수 있습니다. 저장소의 빌드 스크립트로 설치하십시오."
			fi
			notification_type='launcher'
		else
			notification_title='식탁보 업데이트 알림'
			notification_body="macSandbox for Windows의 새 버전 $pending_version 을 사용할 수 있습니다. 공식 배포처에서 직접 설치하십시오."
			notification_type='macsandbox'
		fi
		if send_notification "$notification_title" "$notification_body"; then
			/bin/rm -f "$pending_file"
			write_notification_state "$notification_type" 'sent' '다음 실행에서 업데이트 알림을 표시했습니다.'
		else
			write_notification_state "$notification_type" 'error' 'macOS 알림을 표시하지 못했습니다.'
		fi
	done
}

update_wsb() {
	state_file="$WSB_STATE_FILE"
	check_is_due "$state_file" || return 0
	begin_provider_check "$state_file"
	check_epoch="$(current_epoch)"
	check_time="$(current_time)"
	download_file="$(/usr/bin/mktemp "$STATE_DIR/.wsb-download.XXXXXX" 2>/dev/null)" || {
		finish_provider_check "$state_file" 'error' '최신 설정 파일을 받을 임시 파일을 만들지 못했습니다.' "$check_epoch" "$check_time" '' '' ''
		return 1
	}

	download_url "$WSB_URL" "$download_file"
	curl_status=$?
	if [ "$curl_status" -ne 0 ]; then
		finish_provider_check "$state_file" 'error' "최신 설정 파일 요청에 실패했습니다(curl 종료 코드 $curl_status)." "$check_epoch" "$check_time" '' '' ''
		/bin/rm -f "$download_file"
		return 1
	fi
	if ! xml_starts_correctly "$download_file"; then
		finish_provider_check "$state_file" 'error' '받은 설정 파일이 XML 선언으로 시작하지 않아 버렸습니다.' "$check_epoch" "$check_time" '' '' ''
		/bin/rm -f "$download_file"
		return 1
	fi

	if [ -f "$WSB_PATH" ] && /usr/bin/cmp -s "$download_file" "$WSB_PATH"; then
		finish_provider_check "$state_file" 'unchanged' '최신 설정 파일과 현재 파일이 같습니다.' "$check_epoch" "$check_time" '' '' ''
		/bin/rm -f "$download_file"
		return 0
	fi

	wsb_parent="$(/usr/bin/dirname "$WSB_PATH")"
	if [ ! -d "$wsb_parent" ] && ! /bin/mkdir -p "$wsb_parent"; then
		finish_provider_check "$state_file" 'error' '설정 파일 폴더를 만들지 못했습니다.' "$check_epoch" "$check_time" '' '' ''
		/bin/rm -f "$download_file"
		return 1
	fi

	if [ -f "$WSB_PATH" ]; then
		backup_stamp="$(/bin/date '+%Y%m%d-%H%M%S')"
		backup_path="$WSB_PATH.bak-$backup_stamp"
		backup_number=1
		while [ -e "$backup_path" ]; do
			backup_path="$WSB_PATH.bak-$backup_stamp-$backup_number"
			backup_number=$((backup_number + 1))
		done
		if ! /bin/cp -p "$WSB_PATH" "$backup_path"; then
			finish_provider_check "$state_file" 'error' '기존 설정 파일의 백업을 만들지 못해 교체하지 않았습니다.' "$check_epoch" "$check_time" '' '' ''
			/bin/rm -f "$download_file"
			return 1
		fi
	fi

	install_file="$(/usr/bin/mktemp "$WSB_PATH.tmp.XXXXXX" 2>/dev/null)" || {
		finish_provider_check "$state_file" 'error' '새 설정 파일을 설치할 임시 파일을 만들지 못했습니다.' "$check_epoch" "$check_time" '' '' ''
		/bin/rm -f "$download_file"
		return 1
	}
	if ! /bin/cp "$download_file" "$install_file" || ! /bin/mv -f "$install_file" "$WSB_PATH"; then
		/bin/rm -f "$install_file"
		finish_provider_check "$state_file" 'error' '새 설정 파일로 교체하지 못했습니다.' "$check_epoch" "$check_time" '' '' ''
		/bin/rm -f "$download_file"
		return 1
	fi
	/bin/rm -f "$download_file"
	if [ -f "$WSB_PATH" ]; then
		finish_provider_check "$state_file" 'updated' '최신 설정 파일로 교체했습니다.' "$check_epoch" "$check_time" '' '' ''
	else
		finish_provider_check "$state_file" 'error' '설정 파일 교체 결과를 확인하지 못했습니다.' "$check_epoch" "$check_time" '' '' ''
		return 1
	fi
}

launcher_install_error=''
launcher_download_file=''
launcher_extract_dir=''
launcher_old_backup=''

cleanup_launcher_install() {
	[ -n "$launcher_download_file" ] && /bin/rm -f "$launcher_download_file"
	[ -n "$launcher_extract_dir" ] && /bin/rm -rf "$launcher_extract_dir"
	[ -n "$launcher_old_backup" ] && /bin/rm -rf "$launcher_old_backup"
}

install_launcher_from_release() {
	release_json="$1"
	release_version="$2"
	launcher_install_error=''
	launcher_download_file=''
	launcher_extract_dir=''
	launcher_old_backup=''
	asset_url="$(extract_launcher_asset_url "$release_json")"
	if [ -z "$asset_url" ]; then
		launcher_install_error='최신 런처 릴리스에서 ZIP 설치 파일을 찾지 못했습니다.'
		return 1
	fi
	launcher_download_file="$(/usr/bin/mktemp "$STATE_DIR/.launcher-download.XXXXXX" 2>/dev/null)" || {
		launcher_install_error='런처 설치 파일을 받을 임시 파일을 만들지 못했습니다.'
		return 1
	}
	download_url "$asset_url" "$launcher_download_file"
	curl_status=$?
	if [ "$curl_status" -ne 0 ]; then
		launcher_install_error="런처 설치 파일을 받지 못했습니다(curl 종료 코드 $curl_status)."
		cleanup_launcher_install
		return 1
	fi
	launcher_extract_dir="$(/usr/bin/mktemp -d "$STATE_DIR/.launcher-extract.XXXXXX" 2>/dev/null)" || {
		launcher_install_error='런처 설치 파일을 풀 임시 폴더를 만들지 못했습니다.'
		cleanup_launcher_install
		return 1
	}
	if ! /usr/bin/ditto -x -k "$launcher_download_file" "$launcher_extract_dir" >/dev/null 2>&1; then
		launcher_install_error='런처 ZIP 설치 파일을 풀지 못했습니다.'
		cleanup_launcher_install
		return 1
	fi
	candidate_app="$(/usr/bin/find "$launcher_extract_dir" -type d -name '식탁보.app' -print 2>/dev/null | /usr/bin/head -n 1)"
	if [ -z "$candidate_app" ] || [ ! -x "$candidate_app/Contents/MacOS/launcher" ]; then
		launcher_install_error='ZIP 안에서 올바른 식탁보 앱 번들을 찾지 못했습니다.'
		cleanup_launcher_install
		return 1
	fi
	candidate_version="$(plist_value "$candidate_app/Contents/Info.plist" 'CFBundleShortVersionString' 2>/dev/null)"
	if [ -z "$candidate_version" ] || [ "$candidate_version" != "$release_version" ]; then
		launcher_install_error='다운로드한 앱 버전이 릴리스 태그와 일치하지 않습니다.'
		cleanup_launcher_install
		return 1
	fi

	if [ -e "$LAUNCHER_APP" ] || [ -L "$LAUNCHER_APP" ]; then
		launcher_old_backup="$STATE_DIR/launcher-previous-$release_version-$(/bin/date '+%Y%m%d-%H%M%S').app"
		if ! /usr/bin/ditto "$LAUNCHER_APP" "$launcher_old_backup" >/dev/null 2>&1; then
			launcher_install_error='현재 런처의 임시 백업을 만들지 못해 자동 설치를 중단했습니다.'
			cleanup_launcher_install
			return 1
		fi
	fi
	/bin/rm -rf "$LAUNCHER_APP"
	if ! /bin/mv "$candidate_app" "$LAUNCHER_APP"; then
		if [ -n "$launcher_old_backup" ] && [ -d "$launcher_old_backup" ]; then
			/bin/mv "$launcher_old_backup" "$LAUNCHER_APP"
			launcher_old_backup=''
		fi
		launcher_install_error='새 런처 앱을 응용 프로그램 폴더에 배치하지 못했습니다.'
		cleanup_launcher_install
		return 1
	fi
	installed_version="$(plist_value "$LAUNCHER_APP/Contents/Info.plist" 'CFBundleShortVersionString' 2>/dev/null)"
	if [ "$installed_version" != "$release_version" ]; then
		/bin/rm -rf "$LAUNCHER_APP"
		if [ -n "$launcher_old_backup" ] && [ -d "$launcher_old_backup" ]; then
			/bin/mv "$launcher_old_backup" "$LAUNCHER_APP"
			launcher_old_backup=''
		fi
		launcher_install_error='자동 설치 후 앱 버전을 확인하지 못했습니다.'
		cleanup_launcher_install
		return 1
	fi
	lsregister_path='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
	[ -x "$lsregister_path" ] && "$lsregister_path" -f "$LAUNCHER_APP" >/dev/null 2>&1
	/usr/bin/killall Dock >/dev/null 2>&1 || true
	cleanup_launcher_install
	return 0
}

update_launcher() {
	state_file="$LAUNCHER_STATE_FILE"
	check_is_due "$state_file" || return 0
	begin_provider_check "$state_file"
	check_epoch="$(current_epoch)"
	check_time="$(current_time)"
	if [ -z "$LAUNCHER_INFO_PLIST" ]; then
		finish_provider_check "$state_file" 'error' '런처의 Info.plist를 찾지 못했습니다.' "$check_epoch" "$check_time" '' '' ''
		return 1
	fi
	installed_version="$(plist_value "$LAUNCHER_INFO_PLIST" 'CFBundleShortVersionString' 2>/dev/null)"
	if [ -z "$installed_version" ]; then
		finish_provider_check "$state_file" 'error' '런처의 현재 버전을 읽지 못했습니다.' "$check_epoch" "$check_time" '' '' ''
		return 1
	fi
	release_json="$(/usr/bin/mktemp "$STATE_DIR/.launcher-release.XXXXXX" 2>/dev/null)" || {
		finish_provider_check "$state_file" 'error' '런처 릴리스 응답을 받을 임시 파일을 만들지 못했습니다.' "$check_epoch" "$check_time" '' "$installed_version" ''
		return 1
	}
	download_url "$LAUNCHER_RELEASE_API" "$release_json"
	curl_status=$?
	if [ "$curl_status" -ne 0 ]; then
		finish_provider_check "$state_file" 'error' "런처 릴리스 조회에 실패했습니다(curl 종료 코드 $curl_status)." "$check_epoch" "$check_time" '' "$installed_version" ''
		/bin/rm -f "$release_json"
		return 1
	fi
	release_tag="$(extract_release_tag "$release_json")"
	release_version="$(normalize_version "$release_tag")"
	if [ -z "$release_version" ] || ! version_is_newer "$release_version" '0'; then
		finish_provider_check "$state_file" 'error' '런처 릴리스 응답에서 유효한 버전을 읽지 못했습니다.' "$check_epoch" "$check_time" '' "$installed_version" ''
		/bin/rm -f "$release_json"
		return 1
	fi
	if version_is_newer "$release_version" "$installed_version"; then
		pending_kind='available'
		pending_reason='새 런처 버전을 확인했습니다. 다음 실행에서 알립니다.'
		pending_status='update_available'
		if launcher_auto_install_enabled; then
			if install_launcher_from_release "$release_json" "$release_version"; then
				pending_kind='installed'
				pending_reason='새 런처 버전을 자동 설치했습니다.'
				pending_status='installed'
				installed_version="$release_version"
			else
				pending_reason="새 런처 버전을 확인했지만 자동 설치에 실패했습니다: $launcher_install_error"
			fi
		fi
		if ! write_pending "$LAUNCHER_PENDING_FILE" "$pending_kind" "$release_version"; then
			finish_provider_check "$state_file" 'error' '런처 업데이트 알림 대기 파일을 기록하지 못했습니다.' "$check_epoch" "$check_time" "$release_version" "$installed_version" '0'
			/bin/rm -f "$release_json"
			return 1
		fi
		finish_provider_check "$state_file" "$pending_status" "$pending_reason" "$check_epoch" "$check_time" "$release_version" "$installed_version" '1'
	else
		finish_provider_check "$state_file" 'current' '현재 런처가 최신 버전입니다.' "$check_epoch" "$check_time" "$release_version" "$installed_version" '0'
	fi
	/bin/rm -f "$release_json"
}

update_macsandbox() {
	state_file="$SANDBOX_STATE_FILE"
	check_is_due "$state_file" || return 0
	begin_provider_check "$state_file"
	check_epoch="$(current_epoch)"
	check_time="$(current_time)"
	if [ ! -d "$SANDBOX_APP" ]; then
		finish_provider_check "$state_file" 'error' 'macSandbox for Windows 설치본을 찾지 못했습니다.' "$check_epoch" "$check_time" '' '' ''
		return 1
	fi
	bundle_id="$(plist_value "$SANDBOX_APP/Contents/Info.plist" 'CFBundleIdentifier' 2>/dev/null)"
	if [ "$bundle_id" != "$SANDBOX_BUNDLE_ID" ]; then
		finish_provider_check "$state_file" 'error' '설치된 앱의 번들 식별자가 예상값과 다릅니다.' "$check_epoch" "$check_time" '' '' ''
		return 1
	fi
	installed_version="$(plist_value "$SANDBOX_APP/Contents/Info.plist" 'CFBundleShortVersionString' 2>/dev/null)"
	if [ -z "$installed_version" ]; then
		installed_version="$(plist_value "$SANDBOX_APP/Contents/Info.plist" 'CFBundleVersion' 2>/dev/null)"
	fi
	if [ -z "$installed_version" ]; then
		finish_provider_check "$state_file" 'error' 'macSandbox for Windows의 현재 버전을 읽지 못했습니다.' "$check_epoch" "$check_time" '' '' ''
		return 1
	fi
	release_json="$(/usr/bin/mktemp "$STATE_DIR/.macsandbox-release.XXXXXX" 2>/dev/null)" || {
		finish_provider_check "$state_file" 'error' 'macSandbox 릴리스 응답을 받을 임시 파일을 만들지 못했습니다.' "$check_epoch" "$check_time" '' "$installed_version" ''
		return 1
	}
	download_url "$SANDBOX_RELEASE_API" "$release_json"
	curl_status=$?
	if [ "$curl_status" -ne 0 ]; then
		finish_provider_check "$state_file" 'error' "macSandbox 릴리스 조회에 실패했습니다(curl 종료 코드 $curl_status)." "$check_epoch" "$check_time" '' "$installed_version" ''
		/bin/rm -f "$release_json"
		return 1
	fi
	release_tag="$(extract_release_tag "$release_json")"
	release_version="$(normalize_version "$release_tag")"
	if [ -z "$release_version" ] || ! version_is_newer "$release_version" '0'; then
		finish_provider_check "$state_file" 'error' 'macSandbox 릴리스 응답에서 유효한 버전을 읽지 못했습니다.' "$check_epoch" "$check_time" '' "$installed_version" ''
		/bin/rm -f "$release_json"
		return 1
	fi
	if version_is_newer "$release_version" "$installed_version"; then
		if ! write_pending "$SANDBOX_PENDING_FILE" 'available' "$release_version"; then
			finish_provider_check "$state_file" 'error' 'macSandbox 업데이트 알림 대기 파일을 기록하지 못했습니다.' "$check_epoch" "$check_time" "$release_version" "$installed_version" '0'
			/bin/rm -f "$release_json"
			return 1
		fi
		finish_provider_check "$state_file" 'update_available' '새 macSandbox 버전을 확인했습니다. 자동 설치하지 않습니다.' "$check_epoch" "$check_time" "$release_version" "$installed_version" '1'
	else
		finish_provider_check "$state_file" 'current' '설치된 macSandbox가 최신 버전입니다.' "$check_epoch" "$check_time" "$release_version" "$installed_version" '0'
	fi
	/bin/rm -f "$release_json"
}

acquire_update_lock() {
	if /bin/mkdir "$UPDATE_LOCK_DIR" 2>/dev/null; then
		printf '%s\n' "$$" > "$UPDATE_LOCK_DIR/pid"
		return 0
	fi
	lock_pid="$(/bin/cat "$UPDATE_LOCK_DIR/pid" 2>/dev/null)"
	case "$lock_pid" in
		''|*[!0-9]*)
			/bin/rm -rf "$UPDATE_LOCK_DIR"
			/bin/mkdir "$UPDATE_LOCK_DIR" 2>/dev/null || return 1
			printf '%s\n' "$$" > "$UPDATE_LOCK_DIR/pid"
			return 0
			;;
	esac
	if /bin/kill -0 "$lock_pid" >/dev/null 2>&1; then
		return 1
	fi
	/bin/rm -rf "$UPDATE_LOCK_DIR"
	/bin/mkdir "$UPDATE_LOCK_DIR" 2>/dev/null || return 1
	printf '%s\n' "$$" > "$UPDATE_LOCK_DIR/pid"
	return 0
}

run_background_updates() {
	/bin/mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
	acquire_update_lock || exit 0
	trap '/bin/rm -rf "$UPDATE_LOCK_DIR"' EXIT HUP INT TERM
	update_wsb
	update_launcher
	update_macsandbox
}

schedule_background_updates() {
	/bin/mkdir -p "$STATE_DIR" 2>/dev/null || return 0
	needs_update=0
	check_is_due "$WSB_STATE_FILE" && needs_update=1
	check_is_due "$LAUNCHER_STATE_FILE" && needs_update=1
	check_is_due "$SANDBOX_STATE_FILE" && needs_update=1
	[ "$needs_update" -eq 1 ] || return 0
	/usr/bin/nohup "$SCRIPT_PATH" --background-update </dev/null >> "$STATE_DIR/update.log" 2>&1 &
}

if [ "$1" = '--background-update' ]; then
	umask 077
	run_background_updates
	exit 0
fi

umask 077
show_pending_notifications
schedule_background_updates

[ -f "$WSB_PATH" ] || show_error "설정 파일을 찾을 수 없습니다:
$WSB_PATH

식탁보 릴리스에서 no-install-spork.wsb를 다시 받아 이 경로에 두십시오."
[ -d "$SANDBOX_APP" ] || show_error 'macSandbox for Windows가 설치되어 있지 않습니다.'

# 실행 중인 샌드박스 세션을 정리한다. 일회용 환경이므로 버려도 무방하다.
if /usr/bin/pgrep -x MacSandbox >/dev/null 2>&1; then
	/usr/bin/osascript -e 'tell application "macSandbox for Windows" to quit' >/dev/null 2>&1
	i=0
	while [ "$i" -lt 20 ]; do
		/usr/bin/pgrep -x MacSandbox >/dev/null 2>&1 || break
		sleep 0.5
		i=$((i + 1))
	done
	# 앱이 남아 있으면 macSandbox 번들 안에서 실행된 VM 프로세스만 정리한다.
	# 이름만 보고 죽이면 UTM 등 사용자가 따로 띄운 QEMU까지 함께 종료된다.
	if /usr/bin/pgrep -x MacSandbox >/dev/null 2>&1; then
		terminate_sandbox_vms
		sleep 2
	fi
fi

/usr/bin/open -a "$SANDBOX_APP" "$WSB_PATH"
open_status=$?
if [ "$open_status" -ne 0 ]; then
	show_error 'macSandbox에 설정 파일을 전달하지 못했습니다.'
fi
exit 0
