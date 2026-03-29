# ReadBook — Flutter 독서 앱 (Android)

voca-pin Chrome 확장과 동일한 단어 저장·하이라이트 기능을 안드로이드 앱으로 구현.  
앱 내부 독서 모드 외에, **홈버튼 길게 누름(Assist)** 으로 화면을 OCR 인식해 단어를 저장하는 모드를 함께 제공한다.

---

## 진입점 (Entry Points)

| 진입점 | 설명 |
|--------|------|
| 일반 실행 | 앱 아이콘 → 독서 · 단어장 · 설정 3탭 UI |
| Assist 모드 | 홈버튼 길게 누름 → OCR 오버레이 화면 · 단어 선택 → 번역 · 저장 |

> **설정 방법**: 기기 설정 → 앱 → 기본 앱 → 디지털 어시스턴트 앱 → ReadBook 선택

---

## 기능

### A. 앱 내부 독서 모드 (기존)

| 기능 | 설명 |
|------|------|
| 파일 불러오기 | FilePicker로 텍스트 파일 로드 (UTF-8 BOM 제거) |
| 편집 / 읽기 모드 | 텍스트 편집 후 읽기 모드로 전환 |
| 단어 탭 → 사전 팝업 | 탭 위치 기준 ±150자를 Gemini에 전달 → 문맥 맞는 의미 우선 표시 (IPA · 품사별 한글 뜻 · TTS) |
| 저장 | 📌 탭 → SharedPreferences 로컬 저장 + GitHub Gist 자동 동기화 |
| 하이라이트 | 저장된 단어 보라색 강조 표시 |
| 후리가나 | 하이라이트 단어 위에 한글 뜻 표시 · 팝업 ko 칩으로 고정 · 툴바 ON/OFF 전체 토글 |
| 단어 의미 숨김 | 후리가나를 단어별로 개별 숨김/표시 토글 |
| 폰트 크기 | 툴바 A− / A+ (12–28pt) |
| 페이지네이션 | 페이지 단위 분할 · 현재 페이지 위치 자동 저장/복원 |
| 북마크 | 페이지 북마크 추가 · 목록에서 바로 이동 · 삭제 |
| 문장 TTS | 텍스트 선택 → "Read aloud" — 한글 주석(`\uFFFC` WidgetSpan 포함) 제거 후 영어 전용 문자열 재생 |
| 단어장 | 저장 목록 · 실시간 검색 · 단건/전체 삭제 |
| 설정 | Gemini API Key · GitHub PAT 입력 — flutter_secure_storage 암호화 저장 |
| 연결 테스트 | 설정 화면에서 Gemini / GitHub 연결 상태 확인 |

### B. Assist(홈버튼 길게 누름) 모드 (신규)

| 기능 | 설명 |
|------|------|
| Assist 진입 | `ACTION_ASSIST` 인텐트 수신 → `AssistActivity` 실행 |
| 화면 스크린샷 | Assist API가 제공하는 `AssistContent` 번들의 스크린샷 비트맵 사용 (MediaProjection 불필요) |
| 텍스트 OCR | ML Kit On-Device Text Recognition — 무료 · 오프라인 · 한/영/일 지원 |
| 단어 박스 탭 | OCR 결과 바운딩 박스를 오버레이로 표시 → 단어 탭 시 사전 팝업 |
| 번역 · 저장 | 기존 Gemini 사전 팝업 재사용 → 📌 저장 → SharedPreferences + Gist |
| 텍스트 드래그 | 오버레이 위에서 드래그 → 복수 단어 선택 후 번역 |
| 닫기 | 뒤로 가기 또는 화면 밖 탭 → Assist Activity 종료, 원래 앱으로 복귀 |

---

## 기술 스택

| 항목 | 선택 |
|------|------|
| 프레임워크 | Flutter (stable) · Dart |
| 내비게이션 | NavigationBar (Material 3) + IndexedStack |
| 로컬 저장소 | shared_preferences |
| 보안 저장소 | flutter_secure_storage (Android Keystore) |
| TTS | flutter_tts — 전달 문자열에서 한글 사전 제거 (한국어 음성 전환 방지) |
| 파일 선택 | file_picker |
| AI 사전 | Gemini API — structured output (JSON schema) · 모델 캐스케이드: `gemini-3.1-flash-lite-preview` → `gemini-3-flash-preview` → `gemini-2.5-flash` · 프롬프트 컨텍스트 최대 300자 |
| Gist 동기화 | GitHub REST API — 단일 Gist PATCH (voca-pin 공유) |
| OCR (신규) | `google_mlkit_text_recognition` — 온디바이스 · 무료 · 오프라인 · 한/영/일 지원 |
| Assist 브릿지 (신규) | Flutter MethodChannel (`com.readbook/assist`) ↔ 네이티브 `AssistActivity` |

---

## 프로젝트 구조

```
lib/
  main.dart                  # 앱 진입점 (NavigationBar 3탭) + /assist 라우트
  types/
    word_entry.dart           # WordEntry 타입
  utils/
    normalize.dart            # 키 정규화 · 토큰화 · 컨텍스트 추출
    storage.dart              # SharedPreferences 래퍼
    secure_storage.dart       # flutter_secure_storage 래퍼 (API 키)
    gemini.dart               # Gemini API + 모델 캐스케이드
    gist.dart                 # GitHub Gist 단일 동기화
  screens/
    reader_screen.dart        # 리더 (파일 로드 · 페이지 · 북마크 · 하이라이트 · 팝업)
    word_list_screen.dart     # 단어장 (검색 · 삭제)
    settings_screen.dart      # API 키 설정 · 연결 테스트
    ocr_overlay_screen.dart   # [신규] Assist 모드 OCR 오버레이
  widgets/
    dict_popup.dart           # 사전 팝업 (IPA · 품사 · TTS · 후리가나 선택)

android/app/src/main/
  kotlin/.../
    MainActivity.kt           # 기존 Flutter Activity
    AssistActivity.kt         # [신규] ACTION_ASSIST 수신 · 스크린샷 → MethodChannel 전달
  res/values/
    strings.xml
  AndroidManifest.xml         # AssistActivity 등록 · ACTION_ASSIST intent-filter 추가
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
    "definition": "쉬다",
    "meanings": [
      { "pos": "v.", "trans": ["쉬다", "기대다", "달려 있다"] },
      { "pos": "n.", "trans": ["휴식", "나머지"] }
    ],
    "savedAt": 1741500000000,
    "furiganaMIdx": 0,
    "furiganaKIdx": 0
  }
}
```

---

## 실행

```bash
flutter pub get
flutter run                      # 개발
flutter build apk --release      # 릴리즈 APK
```

---

## Assist 모드 구현 계획

### 동작 흐름

```
사용자: 홈버튼 길게 누름
  └─ Android: 기본 어시스턴트 앱 실행
       └─ AssistActivity.onCreate()
            ├─ getIntent().getParcelableExtra(Intent.EXTRA_ASSIST_SCREENSHOT) → Bitmap
            ├─ 비트맵을 임시 파일(PNG)로 저장
            └─ FlutterEngine 초기화 → 라우트 "/assist?path=<파일경로>" 로 진입
                 └─ OcrOverlayScreen
                      ├─ google_mlkit_text_recognition으로 OCR 수행
                      ├─ 인식된 TextBlock / Element 바운딩 박스를 스크린샷 위에 오버레이
                      ├─ 단어 탭 → DictPopup (기존 재사용)
                      └─ 📌 저장 → 기존 storage / gist 유틸 재사용
```

### 단계별 구현 순서

#### 1단계 — Android 네이티브 (`AssistActivity.kt`)

- `AndroidManifest.xml`에 `AssistActivity` 등록
  ```xml
  <activity
      android:name=".AssistActivity"
      android:theme="@style/Theme.Transparent"
      android:exported="true">
    <intent-filter>
      <action android:name="android.intent.action.ASSIST" />
      <category android:name="android.intent.category.DEFAULT" />
    </intent-filter>
  </activity>
  ```
- `onCreate`에서 `EXTRA_ASSIST_SCREENSHOT` 비트맵 추출 → 캐시 디렉터리에 PNG 저장
- 캐시 파일 경로를 initial route 파라미터로 `FlutterEngine`에 주입
- Activity finish 시 임시 파일 삭제

#### 2단계 — Flutter 라우팅

- `main.dart`에 `/assist` 라우트 추가 (GoRouter 또는 `onGenerateRoute`)
- `OcrOverlayScreen(imagePath: String)` 에 경로 전달

#### 3단계 — `OcrOverlayScreen` (`lib/screens/ocr_overlay_screen.dart`)

- `Image.file`로 스크린샷 렌더링 (Stack 최하단)
- `google_mlkit_text_recognition` → `TextRecognizer().processImage(InputImage.fromFile(...))`
- 인식된 각 `TextElement`의 `boundingBox`를 `CustomPaint` 오버레이로 그리기
- 단어 탭 → `DictPopup` 표시 (context는 탭한 TextElement의 라인 전체)
- 드래그 선택 → 선택된 Element들을 공백으로 합쳐 Gemini에 전달
- `WillPopScope` / `BackButton` → Activity 종료 (MethodChannel `closeAssist` 호출)

#### 4단계 — `pubspec.yaml` 의존성 추가

```yaml
google_mlkit_text_recognition: ^0.13.0
```

> ML Kit 온디바이스 모델은 앱 첫 실행 시 자동 다운로드(또는 번들 포함 가능).  
> 한국어·영어·일본어 스크립트는 별도 `MlKitLanguage` 설정 없이 `latin` + `korean` + `japanese` 스크립트로 지정.

### 제약 사항 및 대안

| 이슈 | 내용 | 대안 |
|------|------|------|
| `EXTRA_ASSIST_SCREENSHOT` 미제공 | Android 버전·제조사에 따라 비트맵이 null일 수 있음 | `MediaProjection` 권한 요청 팝업으로 fallback |
| 기본 어시스턴트 미설정 | 사용자가 설정을 바꾸지 않으면 앱이 호출 안 됨 | 설정 화면에서 안내 딥링크 (`Settings.ACTION_VOICE_INPUT_SETTINGS`) 제공 |
| Android 14+ 스크린샷 제한 | `EXTRA_ASSIST_SCREENSHOT`은 여전히 Assist 앱에는 허용됨 | 문서 기준 현재 허용, 추후 변경 시 MediaProjection fallback 사용 |
| 다중 언어 OCR 정확도 | ML Kit는 스크립트 단위로 인식기를 분리 | 화면 언어 자동 감지 or 설정에서 선택 (latin / korean / japanese / chinese) |