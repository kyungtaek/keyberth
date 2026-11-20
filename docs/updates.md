# macOS 자동 업데이트

Apple Silicon 배포본은 시작 15초 후와 이후 6시간마다 GitHub의 최신 정식 릴리스를 확인한다. 메뉴 막대 아이콘을 오른쪽 클릭하면 **업데이트 확인…**으로 즉시 확인할 수 있다. 새 버전을 내려받으면 재시작 시점을 선택한다. DMG에서 실행 중이면 응용 프로그램 폴더로 먼저 복사한다.

1. 릴리스할 때 package.json과 package-lock.json에 이전보다 높은 동일 버전을 지정한다.
2. Developer ID Application 인증서와 notarytool 키체인 프로필을 사용할 수 있는 Apple Silicon Mac에서 아래 명령을 실행한다.
3. 해당 버전 태그에 DMG, ZIP, releases-arm64.json 세 파일을 한 릴리스 초안에 업로드한다. 피드의 ZIP 주소와 태그를 확인한 뒤 정식 최신 릴리스로 공개한다.

```sh
SIGN_IDENTITY='Developer ID Application: …' NOTARY_PROFILE='…' bash scripts/release-macos.sh
version="$(node -p 'require("./package.json").version')"
gh release create "v$version" --verify-tag --draft --repo kyungtaek/keyberth \
  --title "Keyberth $version" --generate-notes "dist/releases/$version/"*
```

기존 v0.3.0 설치에는 업데이트 클라이언트가 없다. 최초 한 번은 새 DMG를 수동 설치한다. 이후에는 같은 번들 ID와 서명 주체를 유지한다. 피드는 releases/latest/download/releases-arm64.json이고 ZIP은 해당 버전 태그에 고정된다.
