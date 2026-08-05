# 식탁보 런처

macOS에서 'macSandbox for Windows'를 식탁보용 .wsb 설정으로 실행하는 비공식 런처입니다. macSandbox는 샌드박스 세션이 이미 실행 중이면 새 .wsb 전달을 조용히 무시할 수 있습니다. 이 런처는 실행 전에 기존 MacSandbox 세션과 알려진 qemu-system-aarch64 VM 프로세스를 정리한 뒤 open -a로 설정 파일을 전달합니다.

## 설치

Apple Silicon macOS에서 다음 순서로 실행하십시오.

1. 공식 macSandbox 앱을 /Applications/macSandbox for Windows.app에 설치합니다.
2. no-install-spork.wsb를 기본 경로인 $HOME/Documents/식탁보/no-install-spork.wsb에 둡니다.
3. 저장소에서 build.sh를 실행합니다. /Applications/식탁보.app이 이미 있으면 스크립트가 덮어쓰기 전에 확인합니다.
4. Launchpad 또는 Finder에서 식탁보를 실행합니다.

기본 경로를 바꾸려면 런처를 실행하는 환경에 TABLECLOTH_WSB_PATH를 설정하십시오. 빌드 스크립트는 로고를 앱 아이콘으로 변환하고 앱 번들을 만들어 설치합니다.

## 업데이트 동작

런처 실행을 막지 않도록 업데이트 조회는 백그라운드에서 시작하고, 조회 결과와 실패 사유는 $HOME/Library/Application Support/TableClothLauncher/에 기록합니다. 각 항목은 상태 파일의 마지막 조회 시각을 기준으로 24시간에 한 번만 조회합니다. 네트워크가 끊기거나 응답 형식이 잘못되면 해당 상태 파일의 reason에 사유를 남깁니다.

- 식탁보 .wsb: 공식 최신 파일을 받아 XML 선언으로 시작하는지 확인합니다. 현재 파일과 다를 때 기존 파일을 .bak-날짜로 백업한 뒤 교체합니다. 백업 또는 검증에 실패하면 기존 파일을 유지합니다.
- 이 런처: renovys/tablecloth-launcher 최신 릴리스 태그와 앱의 CFBundleShortVersionString을 비교합니다. 새 버전이면 다음 실행 때 한글 알림을 표시합니다. 기본은 알림만입니다.
- macSandbox: yourtablecloth/macSandbox 최신 릴리스와 설치본의 버전을 비교하고, 새 버전이면 다음 실행 때 공식 배포처에서 직접 설치하라는 알림만 표시합니다. macSandbox 앱은 자동으로 교체하지 않습니다.

런처 자동 설치를 선택하려면 상태 폴더를 만든 뒤 launcher-auto-install 파일의 첫 줄에 1을 적으십시오. 이 기능은 최신 런처 릴리스에 .zip 설치 자산이 있고 그 안에 버전이 일치하는 식탁보.app 번들이 있을 때만 동작합니다. 설치 자산 검증에 실패하면 기존 앱을 유지하고 다음 실행 때 일반 업데이트 알림을 표시합니다. 이 설정을 지우면 기본 알림 모드로 돌아갑니다.

## 되돌리기와 제거

.wsb를 이전 버전으로 되돌리려면 같은 폴더의 .bak-날짜 파일 중 원하는 백업을 확인한 뒤 런처를 종료하고 수동으로 원래 이름에 복사하십시오. 자동 교체는 백업을 만든 뒤 진행하므로 백업이 없는 파일은 자동으로 삭제하지 않습니다.

런처와 상태 파일을 제거하려면 저장소의 uninstall.sh를 실행하고 확인하십시오. Dock에 남는 항목은 Dock에서 보조 클릭한 뒤 'Dock에서 제거'를 선택하십시오. macSandbox 자체와 공식 식탁보 파일은 이 스크립트가 제거하지 않습니다.

## 원저작자 리스펙

식탁보(TableCloth)와 macSandbox는 yourtablecloth 프로젝트의 저작물이며, 대표 개발자는 Jung Hyun Nam(남정현)입니다. 원 프로젝트는 TableCloth(https://github.com/yourtablecloth/TableCloth)와 macSandbox(https://github.com/yourtablecloth/macSandbox)에서 확인할 수 있습니다. 두 프로젝트와 관련 저작물의 라이선스는 AGPL-3.0입니다.

이 저장소는 renovys/tablecloth-launcher(https://github.com/renovys/tablecloth-launcher)에서 배포하는 개인 제작 비공식 보조 도구이며, yourtablecloth 프로젝트가 만들거나 보증하거나 운영하는 저장소가 아닙니다. 원 프로젝트의 이름과 저작권을 존중하고, 원 프로젝트의 라이선스와 고지 사항을 함께 확인하십시오.
