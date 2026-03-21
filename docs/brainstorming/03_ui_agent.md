# UI/UX 전문 에이전트 - 브레인스토밍 결과

## 1. 디자인 철학

### 핵심 원칙: "Professional Clarity"

```
원칙 1. Context Awareness (맥락 인식)
  - 현재 고객사/리소스 위치를 항상 명확히 표시
  - Breadcrumb 가시화

원칙 2. Density with Clarity (밀도와 명료함의 균형)
  - Progressive Disclosure: 기본 뷰(핵심 지표) / 전문가 모드(전체)

원칙 3. Trust & Safety (신뢰와 안전)
  - 파괴적 작업은 시각적으로 명확하게 구분
  - Preview before action, Undo 제공

원칙 4. Speed First (속도 우선)
  - 자주 쓰는 작업은 3클릭 이내
  - Skeleton UI 즉시 피드백
  - 키보드로 모든 핵심 작업 수행 가능
```

### 정보 밀도 레벨
| 레벨 | 대상 | 내용 |
|------|------|------|
| 1. Executive View | C레벨/보고용 | KPI 카드 4~6개, 큰 차트 |
| 2. Operator View | 일반 관리자 | 리소스 테이블 + 메트릭 + 알람 |
| 3. Engineer View | 전문가 | 전체 메트릭, 로그, 원시 데이터 |

### 다크/라이트 모드 색상
```
Light: #F8FAFC 배경, #0F172A 텍스트
Dark:  #0A0E1A 배경 (딥 네이비, OCI 브랜드 연계), #F1F5F9 텍스트
상태: Success #10B981 / Warning #F59E0B / Error #EF4444
OCI Red: #C74634 (Oracle 브랜드 액센트)
```

---

## 2. 핵심 화면 구성

### 2-1. 메인 대시보드
```
상단: KPI 카드 4개 (고객사 수 / 전체 리소스 / 월간비용 / 활성알람)
중단: 고객사별 비용 차트(Bar) + 리소스 상태 요약
하단: 최근 활동 로그 + 지역별 분포
```
- 위젯 드래그앤드롭 재배치 (React Grid Layout)
- 실시간 WebSocket 업데이트

### 2-2. 고객사(테넌트) 관리
```
목록: 상태/플랜 필터 + 검색 + 일괄 작업
상세: 탭 구성 (개요 / 리소스 / 모니터링 / 비용 / 설정)
빠른 작업: 콘솔 접속 / 리소스 보기 / 비용 분석 / 알람 설정 / 보고서 생성
```

### 2-3. 리소스 관리 (Compute 예시)
```
필터: 고객사 / 지역 / 상태 + 전역 검색
뷰 전환: 목록(≡) / 카드(⊞)
인라인 지표: CPU%, 메모리%
일괄 선택: 시작/중지/재시작/삭제
상세: 슬라이드 패널 (Side Sheet)
```

### 2-4. 모니터링 & 알람
```
좌측: 알람 요약 (위급/긴급/경고) + 활성 알람 목록
우측: 메트릭 차트 (CPU/메모리/네트워크/I/O) + 타임라인
알람 규칙: Step Wizard (대상→조건→알림→확인)
```

### 2-5. 비용 분석
```
상단 KPI: 이달 총비용 / 전월 대비 / 예산 대비 / 예상 월말
중단: 고객사별 Donut + 서비스별 Bar
하단: 월별 Stacked Bar (12개월) + 상세 테이블
```

### 2-6. 설정/권한
```
좌측 탭: 사용자 관리 / 역할/권한 / API 키 / 알림 채널 / 감사 로그
권한 매트릭스: 기능 × 역할 시각화
```

---

## 3. UX 핵심 패턴

### 네비게이션: 좌측 고정 사이드바 (240px → 72px → 56px 축소)
- AWS/GCP/Azure와 동일 → 학습 곡선 없음
- [Ctrl+B] 단축키 토글
- 즐겨찾기 고객사 5개까지 사이드바 고정

### Command Palette (핵심 차별화)
- [Cmd+K] / [Ctrl+K] 전역 호출
- 최근 방문 / 빠른 작업 / 전체 검색 통합
- 카테고리: 고객사 > 리소스 > 알람 > 문서 > 작업

### 비동기 작업 상태 표시
```
1. 인라인 상태: 테이블 행 내 진행률 표시
2. 작업 센터: 우하단 고정 패널 (완료/진행 목록)
3. 완료 토스트: 3-5초 자동 사라짐 + [바로가기]
4. 실패 토스트: [오류 보기] + [재시도]
```

### 드릴다운: 3단계
```
Level 1: 대시보드 → 목록 (전체 페이지)
Level 2: 목록 → 상세 (슬라이드 Side Sheet, 컨텍스트 유지)
Level 3: Side Sheet → 전체 페이지 (복잡한 편집)
```

### 위험 작업 확인
```
LOW (중지/재시작): 단순 확인 다이얼로그
MED (설정 변경): 변경사항 Summary 표시
HIGH (삭제): 리소스 이름 타이핑 확인 + 영향도 표시
```

### 키보드 단축키
```
Cmd/Ctrl+K  : Command Palette
Cmd/Ctrl+B  : 사이드바 토글
G then D/C/R/M/B : 주요 페이지 바로가기
J/K         : 테이블 행 이동
Enter       : 상세 열기
Esc         : 패널 닫기
```

---

## 4. 기술 구현 추천

### 프론트엔드 스택
```
Framework:    Next.js 15 (App Router)
UI Library:   shadcn/ui (Tailwind CSS 기반, Radix UI 접근성)
차트:         Apache ECharts (성능) + Recharts (소형 스파크라인)
테이블:       TanStack Table v8 + TanStack Virtual (수천 행 가상화)
서버 상태:    TanStack Query (React Query)
클라이언트:  Zustand
폼:           React Hook Form + Zod
날짜:         date-fns
드래그:       @dnd-kit/core (대시보드 위젯)
알림:         Sonner (Shadcn 공식 추천)
WebSocket:    native WebSocket
아이콘:       Lucide React
모노폰트:     JetBrains Mono (OCID, IP, 로그)
```

---

## 5. 레퍼런스 분석 및 적용점

| 레퍼런스 | 적용할 것 | 피할 것 |
|----------|----------|---------|
| AWS Console | 최근 방문 즐겨찾기, CloudShell | UI 파편화, 약한 전역 검색 |
| GCP Console | 전역 검색 UX, 테넌트 스위처 | 높은 초심자 학습 곡선 |
| Azure Portal | 대시보드 위젯 핀, 즐겨찾기 | 느린 렌더링, 깊은 중첩 메뉴 |
| Datadog | 모니터링 UX, 드릴다운, 다크모드 | 압도적인 기능량 |
| Grafana | 시계열 차트 UX, 패널 레이아웃 | 복잡한 쿼리 빌더 |
