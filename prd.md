# ReadBook — Flutter 독서 앱 (Android)

voca-pin Chrome 확장과 동일한 기능을 안드로이드 앱으로 구현

---

## 기능

| 기능 | 설명 |
|------|------|
| 텍스트 입력 | 편집 모드에서 텍스트를 붙여넣기, 읽기 모드로 전환 |
| 단어 탭 → 사전 팝업 | 텍스트 내 단어를 탭하면 Gemini 검색 팝업 표시 |
| 문맥 분석 | 탭 위치 기준 ±150자를 Gemini에 전달 → 문맥 맞는 의미 우선 표시 |
| 사전 팝업 | 발음(IPA) · 품사별 한글 뜻 · TTS |
| 저장 | 📌 탭 → 로컬(AsyncStorage) + GitHub Gist 자동 동기화 |
| 하이라이트 | 저장된 단어 보라색 강조 표시 |
| 후리가나 | 하이라이트 단어 위에 한글 뜻 표시 |
| 후리가나 선택 | 팝업에서 ko 칩 탭 → 원하는 뜻을 후리가나로 고정 |
| 후리가나 전체 토글 | 툴바의 뜻 ON/OFF 버튼으로 전체 숨김/표시 |
| 폰트 크기 조절 | 툴바 A− / A+ 버튼 (12~28pt 범위) |
| 위아래 스크롤 | ScrollView 기반 자연스러운 모바일 스크롤 |
| 단어장 | 저장 목록 · 실시간 검색 · 단건/전체 삭제 |
| 설정 | Gemini API Key · GitHub PAT 입력 (expo-secure-store 암호화 저장) |
| 연결 테스트 | 설정 화면에서 Gemini/GitHub 연결 상태 확인 |

---

## 기술 스택

| 항목 | 선택 |
|------|------|
| 프레임워크 | Flutter (stable) |
| 언어 | Dart |
| 내비게이션 | go_router (BottomNavigationBar) |
| 로컬 저장소 | shared_preferences / hive |
| 보안 저장소 | flutter_secure_storage (Android Keystore 기반) |
| TTS | flutter_tts |
| AI 사전 | Google Gemini API (gemini-2.5-flash-lite → gemini-2.5-flash → gemini-2.0-flash 캐스케이드) |
| Gist 동기화 | GitHub REST API — 4-샤드 구조 (voca-pin 동일) |

---

## 프로젝트 구조

```
read-book-with-dictionnty/
  pubspec.yaml                        # 패키지 의존성
  lib/
    main.dart                         # 앱 진입점 (BottomNavigationBar 라우팅)
    types/
      word_entry.dart                 # 공통 타입 (WordEntry, WordsDict …)
    utils/
      normalize.dart                  # 단어 키 정규화, 토큰화, 컨텍스트 추출
      storage.dart                    # SharedPreferences / Hive 래퍼 (단어, 후리가나 설정)
      secure_storage.dart             # flutter_secure_storage 래퍼 (API 키)
      gemini.dart                     # Gemini API + 모델 캐스케이드
      gist.dart                       # GitHub Gist 4-샤드 동기화
    screens/
      reader_screen.dart              # 메인 리더 (편집/읽기 모드, 하이라이트, 팝업)
      word_list_screen.dart           # 단어장 (검색, 삭제)
      settings_screen.dart            # API 키 설정
    widgets/
      dict_popup.dart                 # 사전 팝업 모달 (IPA, 품사, TTS, 후리가나 선택)
```

---

## 데이터 포맷 (voca-pin 동일)

```json
{
  "rests": {
    "word": "rests",
    "lemma": "rest",
    "form": "3rd person singular",
    "phonetic": "/rɛst/",
    "definitionKo": "쉬다",
    "meanings": [
      { "pos": "v.", "ko": ["쉬다", "기대다", "달려 있다"] },
      { "pos": "n.", "ko": ["휴식", "나머지"] }
    ],
    "savedAt": 1741500000000
  }
}
```

---

## 실행 방법

```bash
cd read-book-with-dictionnty
flutter pub get
flutter run
```

릴리즈 APK 빌드:
```bash
flutter build apk --release
```