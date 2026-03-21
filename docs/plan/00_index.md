# OCI MSP 관리 플랫폼 — UI/UX 설계서 목차

> 작성일: 2026-03-21 | 버전: 1.0 | 상태: 완료

---

## 문서 구성

| 파일 | 내용 | 핵심 항목 |
|------|------|----------|
| [01_design_system.md](./01_design_system.md) | 디자인 시스템 | 컬러, 타이포, 컴포넌트, 간격, 아이콘 |
| [02_page_structure.md](./02_page_structure.md) | 페이지 구조 & 라우팅 | App Router 파일 구조, URL 설계, Protected Route |
| [03_screen_designs.md](./03_screen_designs.md) | 핵심 화면 설계 | A~H 화면 와이어프레임 + 구현 코드 |
| [04_components.md](./04_components.md) | 공통 컴포넌트 | ResourceTable, StatusBadge, SideSheet, ConfirmDialog, AsyncJobButton |
| [05_ux_flows.md](./05_ux_flows.md) | UX 흐름 | 온보딩, 인스턴스 중지, Incident 생성, 재시도 |
| [06_state_management.md](./06_state_management.md) | 상태 관리 | TanStack Query 키/캐시, Zustand 스토어, WebSocket 연동 |
| [07_accessibility_responsive.md](./07_accessibility_responsive.md) | 접근성 & 반응형 | WCAG 2.1 AA, 키보드 단축키, 모바일 대응 |
| [08_empty_error_states.md](./08_empty_error_states.md) | 빈 상태 & 에러 | Empty State, OCI 연결 실패, Skeleton UI |

---

## 핵심 결정 사항 요약

### 디자인 원칙
- **기본 테마**: 다크 모드 (딥 네이비 `#0A0E1A`, OCI 브랜드 연계)
- **브랜드 컬러**: OCI Red `#C74634` (액센트: Sky `#0EA5E9`)
- **폰트**: Inter (UI) + JetBrains Mono (OCID, IP, 로그)
- **밀도**: 기본 comfortable (compact/spacious 사용자 선택 가능)

### URL 구조
```
/                        → 통합 대시보드
/tenants                 → 고객사 목록
/tenants/new             → 온보딩 위저드 (5단계)
/tenants/new?step=N      → 스텝 딥링크 (새로고침 복원)
/compute/instances       → Compute 목록
/compute/instances?detail=:ocid  → Side Sheet 딥링크
/monitoring              → 모니터링 대시보드
/incidents               → Incident 목록
/incidents/:id           → Incident 상세 + 타임라인
/billing                 → 비용 분석
/audit                   → 감사 로그
/settings/*              → 설정
```

### 상태 관리 분리
```
TanStack Query  → 서버 상태 (OCI 리소스, 모니터링 데이터)
Zustand         → 클라이언트 상태 (UI, 인증, 알림, 작업)
WebSocket       → 실시간 이벤트 → Query 캐시 업데이트
```

### 쿼리 캐시 정책
```
realtime  → staleTime: 0      (WebSocket 업데이트 데이터)
medium    → staleTime: 30s    (대부분의 리소스 목록)
slow      → staleTime: 5min   (테넌시 목록, 설정)
static    → staleTime: 1h     (리전, Shape 목록)
```

### 위험도별 UX 패턴
```
LOW      → ConfirmDialog (단순 확인)
MED      → ConfirmDialog (변경사항 요약)
HIGH     → ConfirmDialog + 리소스명 타이핑 + 영향도
CRITICAL → ConfirmDialog + 타이핑 + 2차 승인자
```

### 3클릭 이내 주요 작업
| 작업 | 클릭 경로 |
|------|----------|
| 인스턴스 중지 | 테이블 [···] → [중지] → Confirm [중지] |
| 알람 확인 | 알람 목록 → [확인] → (완료) |
| Incident 담당자 배정 | Incident 행 → [담당자▾] → 엔지니어 선택 |
| 테넌시 전환 | 사이드바 스위처 → 테넌시 선택 → (완료) |

---

## 컴포넌트 의존성 맵

```
shadcn/ui (Radix UI 기반)
    ├── Button, Input, Select, Checkbox
    ├── Dialog, AlertDialog, Sheet
    ├── Tabs, Command, Tooltip
    └── Skeleton, Separator, Progress

공통 컴포넌트 (위에 의존)
    ├── StatusBadge          → Badge + 상태 매핑
    ├── MetricBar            → Progress 커스텀
    ├── ResourceTable        → TanStack Table + Virtual
    ├── SideSheet            → Sheet 확장
    ├── ConfirmDialog        → AlertDialog 확장
    ├── AsyncJobButton       → Button + Job 상태
    ├── MetricChart          → ECharts 래퍼
    ├── CommandPalette       → cmdk + Dialog
    ├── EmptyState           → 독립
    └── ErrorBoundary        → React Class

기능 컴포넌트 (위에 의존)
    ├── Dashboard/           → KPICard, MetricChart, react-grid-layout
    ├── Tenants/             → ResourceTable, SideSheet, Wizard
    ├── Compute/             → ResourceTable, StatusBadge, AsyncJobButton
    ├── Monitoring/          → MetricChart, StatusBadge, AlarmPanel
    ├── Incidents/           → ResourceTable, Timeline, SideSheet
    └── Billing/             → MetricChart (ECharts), ResourceTable
```

---

## 개발 시작 순서 (권장)

### Week 3~5 (인증/테넌시 코어)
1. `globals.css` — CSS 변수 세팅
2. `tailwind.config.ts` — 커스텀 토큰
3. shadcn/ui 기본 컴포넌트 설치
4. `StatusBadge`, `EmptyState`, `LoadingSkeleton`
5. Layout (Sidebar + TopBar + Dashboard Layout)
6. `/login` 페이지 + Auth Store + Middleware
7. `/tenants` 목록 + `ResourceTable`
8. `/tenants/new` 위저드 (5단계)

### Week 6~8 (리소스 관리 + 대시보드)
1. `SideSheet` 컴포넌트
2. `AsyncJobButton` + `ConfirmDialog`
3. `/` 대시보드 (KPI 카드 + react-grid-layout)
4. `/compute/instances` (가상화 테이블 + Fixed Action Bar)
5. `MetricChart` (ECharts 래퍼)
6. `CommandPalette` ([Cmd+K])

### Week 9~10 (모니터링 + Incident)
1. `/monitoring` (알람 패널 + 시계열 차트)
2. `/incidents` (목록 + 타임라인)
3. `WebSocketProvider` + Notification Store
4. `JobCenter` (우하단 작업 센터)

### Week 11~12 (고도화)
1. `/billing` (비용 차트)
2. 키보드 단축키 전체 등록
3. 모바일 반응형 처리
4. 접근성 감사 (axe-core)
5. Error Boundary + 에러 화면

---

## 주요 라이브러리 버전 (package.json)

```json
{
  "dependencies": {
    "next":                  "15.x",
    "react":                 "19.x",
    "typescript":            "5.x",
    "@tanstack/react-query": "5.x",
    "@tanstack/react-table": "8.x",
    "@tanstack/react-virtual":"3.x",
    "zustand":               "5.x",
    "echarts":               "5.x",
    "recharts":              "2.x",
    "react-grid-layout":     "1.x",
    "react-hook-form":       "7.x",
    "zod":                   "3.x",
    "sonner":                "1.x",
    "cmdk":                  "1.x",
    "next-themes":           "0.x",
    "class-variance-authority": "0.x",
    "clsx":                  "2.x",
    "tailwind-merge":        "2.x",
    "lucide-react":          "0.x",
    "date-fns":              "3.x",
    "axios":                 "1.x",
    "immer":                 "10.x"
  }
}
```
