# UI/UX 설계서 — Part 3: 핵심 화면 상세 설계

> OCI MSP 관리 플랫폼 | 작성일: 2026-03-21

---

## A. 통합 대시보드 (/)

### A-1. 와이어프레임

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ [≡ Sidebar]  대시보드                   [🔍] [🔔3] [🌙] [홍길동▾]          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  안녕하세요, 홍길동님  ·  금일 2026-03-21  [위젯 편집] [새로고침 ↺]          │
│                                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ 📊 총 테넌시  │  │ 💻 총 리소스  │  │ 🔔 활성 알람  │  │ 💰 이달 비용  │  │
│  │              │  │              │  │              │  │              │  │
│  │    24        │  │   1,247      │  │   🔴 3 P1    │  │  ₩12,840만   │  │
│  │              │  │              │  │   🟠 8 P2    │  │              │  │
│  │  ↑ 2 이번달  │  │  +43 오늘    │  │   🟡 21 P3   │  │  +7.2% 전월  │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘  │
│                                                                             │
│  ┌─────────────────────────────────┐  ┌───────────────────────────────┐   │
│  │ 테넌시별 월간 비용 (Bar Chart)    │  │ 알람 심각도 분포 (Donut)        │   │
│  │                                 │  │                               │   │
│  │  ████ Acme Corp    ₩4.2M       │  │        ●─────────────          │   │
│  │  ██   Beta Inc     ₩2.8M       │  │      ╱                 ╲       │   │
│  │  ███  Gamma Co     ₩3.1M       │  │     │  P1:3  P2:8      │      │   │
│  │  █    Delta LLC    ₩0.9M       │  │     │  P3:21 P4:45     │      │   │
│  │  ██   Epsilon      ₩2.1M       │  │      ╲                 ╱       │   │
│  │  [▼ 5개 더 보기]               │  │        ─────────────●          │   │
│  │                                 │  │                               │   │
│  └─────────────────────────────────┘  └───────────────────────────────┘   │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ 이상 테넌시 하이라이트                              [전체 테넌시 보기→] │  │
│  │                                                                      │  │
│  │ 🔴 Acme Corp    P1 알람 2건 · 비용 이상 +127%    [즉시 확인→]        │  │
│  │ 🟠 Beta Inc     P2 알람 5건 · 인스턴스 오류       [즉시 확인→]        │  │
│  │ 🟡 Gamma Co     SLA 위반 임박 (가용성 99.1%)      [즉시 확인→]        │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  ┌────────────────────────────────┐  ┌─────────────────────────────────┐  │
│  │ 최근 활동 피드                  │  │ 리전별 리소스 분포                │  │
│  │                                │  │                                 │  │
│  │ 🔴 Acme: P1 알람 발생   2분전  │  │  ap-seoul-1    ███████  648개   │  │
│  │ ✅ Delta: 인스턴스 시작  5분전  │  │  ap-chuncheon1 ████     312개   │  │
│  │ 👤 배정: 홍길동 → Acme  8분전  │  │  us-phoenix-1  ██       187개   │  │
│  │ 🔄 Beta: 온보딩 완료   15분전  │  │  eu-frankfurt1 █        100개   │  │
│  │ [전체 활동 보기→]               │  │                                 │  │
│  └────────────────────────────────┘  └─────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                              [작업 센터 ↕] 진행중 2
```

### A-2. 위젯 드래그앤드롭

```typescript
// app/(dashboard)/page.tsx
'use client';

import { useState, useCallback } from 'react';
import { Responsive, WidthProvider, type Layout } from 'react-grid-layout';
import 'react-grid-layout/css/styles.css';
import 'react-resizable/css/styles.css';

const ResponsiveGrid = WidthProvider(Responsive);

// 기본 위젯 레이아웃
const DEFAULT_LAYOUTS = {
  lg: [
    { i: 'kpi-tenants',    x: 0,  y: 0, w: 3,  h: 2, minW: 2, minH: 2 },
    { i: 'kpi-resources',  x: 3,  y: 0, w: 3,  h: 2, minW: 2, minH: 2 },
    { i: 'kpi-alerts',     x: 6,  y: 0, w: 3,  h: 2, minW: 2, minH: 2 },
    { i: 'kpi-cost',       x: 9,  y: 0, w: 3,  h: 2, minW: 2, minH: 2 },
    { i: 'chart-cost',     x: 0,  y: 2, w: 7,  h: 5, minW: 4, minH: 4 },
    { i: 'chart-severity', x: 7,  y: 2, w: 5,  h: 5, minW: 3, minH: 4 },
    { i: 'anomaly',        x: 0,  y: 7, w: 12, h: 3, minW: 6, minH: 2 },
    { i: 'activity',       x: 0,  y: 10,w: 6,  h: 5, minW: 4, minH: 4 },
    { i: 'region-map',     x: 6,  y: 10,w: 6,  h: 5, minW: 4, minH: 4 },
  ],
};

export default function DashboardPage() {
  const [isEditing, setIsEditing] = useState(false);
  const [layouts, setLayouts] = useState(DEFAULT_LAYOUTS);

  const handleLayoutChange = useCallback((_: Layout[], allLayouts: typeof DEFAULT_LAYOUTS) => {
    setLayouts(allLayouts);
    // 서버에 레이아웃 저장
    saveLayoutToServer(allLayouts);
  }, []);

  return (
    <div>
      {/* 페이지 헤더 */}
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-semibold text-[var(--text-primary)]">대시보드</h1>
          <p className="text-sm text-[var(--text-secondary)]">
            금일 {new Date().toLocaleDateString('ko-KR')}
          </p>
        </div>
        <div className="flex gap-2">
          <Button
            variant={isEditing ? 'default' : 'outline'}
            size="sm"
            onClick={() => setIsEditing(v => !v)}
          >
            {isEditing ? '저장' : '위젯 편집'}
          </Button>
          <Button variant="outline" size="icon">
            <RefreshCw size={16} />
          </Button>
        </div>
      </div>

      <ResponsiveGrid
        className={cn('layout', isEditing && 'ring-1 ring-dashed ring-[var(--border-focus)]')}
        layouts={layouts}
        breakpoints={{ lg: 1200, md: 996, sm: 768 }}
        cols={{ lg: 12, md: 10, sm: 6 }}
        rowHeight={60}
        isDraggable={isEditing}
        isResizable={isEditing}
        onLayoutChange={handleLayoutChange}
        draggableHandle=".drag-handle"
      >
        <div key="kpi-tenants">
          <KPICard
            title="총 테넌시"
            value={24}
            delta={{ value: 2, label: '이번달 신규' }}
            icon={<Users size={20} />}
            isDragging={isEditing}
          />
        </div>
        {/* ... 나머지 위젯들 */}
      </ResponsiveGrid>
    </div>
  );
}
```

### A-3. KPI 카드 컴포넌트

```typescript
// components/features/dashboard/KPICard.tsx
interface KPICardProps {
  title:    string;
  value:    number | string;
  delta?:   { value: number; label: string; positive?: boolean };
  icon:     React.ReactNode;
  status?:  'success' | 'warning' | 'error' | 'neutral';
  isDragging?: boolean;
}

export function KPICard({ title, value, delta, icon, status, isDragging }: KPICardProps) {
  return (
    <div
      className={cn(
        'h-full rounded-lg border bg-[var(--surface)] p-4 flex flex-col',
        'border-[var(--border)] shadow-sm',
        isDragging && 'cursor-grab active:cursor-grabbing'
      )}
    >
      {/* 드래그 핸들 — 편집 모드에서만 표시 */}
      {isDragging && (
        <div className="drag-handle absolute top-2 right-2 opacity-40 cursor-grab">
          <GripHorizontal size={16} />
        </div>
      )}

      <div className="flex items-center justify-between mb-3">
        <span className="text-sm font-medium text-[var(--text-secondary)]">{title}</span>
        <div className={cn('p-1.5 rounded-md', statusBgMap[status ?? 'neutral'])}>
          {icon}
        </div>
      </div>

      <div className="flex-1 flex items-end justify-between">
        <span className="text-3xl font-bold text-[var(--text-primary)]">
          {typeof value === 'number' ? value.toLocaleString('ko-KR') : value}
        </span>
        {delta && (
          <span className={cn(
            'flex items-center gap-1 text-xs font-medium',
            (delta.positive ?? delta.value > 0) ? 'text-status-success' : 'text-status-error'
          )}>
            {delta.value > 0 ? <TrendingUp size={12} /> : <TrendingDown size={12} />}
            {delta.label}
          </span>
        )}
      </div>
    </div>
  );
}
```

---

## B. 테넌시 온보딩 위저드 (/tenants/new)

### B-1. 전체 와이어프레임

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         새 테넌시 온보딩                                    │
│                                                                             │
│  ●─────────────────●─────────────────●─────────────────●─────────────────● │
│  1 Credential     2 권한 검증        3 구조 탐색        4 모니터링          5 담당자│
│  입력             (자동 체크)         & 태깅             기본값              배정    │
│                                                                             │
│  ────────────────────────────────────────────────────────────────────      │
│                                                                             │
│  STEP 1: OCI Credential 입력 (예상 시간: 3분)                              │
│                                                                             │
│  접근 방식 선택:                                                            │
│  ┌───────────────────────────────┐  ┌───────────────────────────────┐      │
│  │ ○ Cross-Tenancy Principal     │  │ ○ API Key 방식                │      │
│  │   [권장]                      │  │   (수동 구성)                  │      │
│  │   MSP Dynamic Group 정책     │  │   IAM User + API Key 파일     │      │
│  │   고객사에서 허용               │  │   고객사에서 User 생성         │      │
│  └───────────────────────────────┘  └───────────────────────────────┘      │
│                                                                             │
│  테넌시 기본 정보                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ 고객사 이름 *                          테넌시 OCID *                  │   │
│  │ [Acme Corporation              ]  [ocid1.tenancy.oc1..xxxxxxx   ]  │   │
│  │                                                                     │   │
│  │ 홈 리전 *                              SLA 티어 *                    │   │
│  │ [ap-seoul-1 (한국 서울) ▾        ]  [Premium ▾                    ]  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  [Cross-Tenancy 선택 시] MSP 구성 가이드                                   │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ 고객사 OCI 콘솔에서 아래 정책을 추가해주세요:                          │   │
│  │                                                                     │   │
│  │ Define tenancy msp as ocid1.tenancy.oc1..msp-tenancy-ocid          │   │
│  │ Admit dynamic-group MSPOperators of tenancy msp to manage ...      │   │
│  │                                                [복사 📋]            │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  [이전]                                         [다음: 권한 검증 →]        │
│                                                                             │
│  ─────────────────────────────────────────────────────────────────────     │
│  ⏱ 예상 완료: 약 12분 남음   [저장하고 나중에 계속]   [도움말 ?]             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### B-2. 각 스텝별 상세

```
STEP 2: 권한 검증 (자동 체크)
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│  OCI 연결을 확인하고 있습니다... (약 30~60초)                                │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                                                                     │   │
│  │  ✅ 테넌시 기본 연결           완료 (1.2s)                           │   │
│  │  ✅ IAM 정책 확인              완료 (2.1s)                           │   │
│  │  ⟳ Compute 권한 확인          확인 중...                            │   │
│  │  ○ Network 권한 확인           대기 중                               │   │
│  │  ○ Storage 권한 확인           대기 중                               │   │
│  │  ○ Monitoring 권한 확인        대기 중                               │   │
│  │                                                                     │   │
│  │  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  40%                        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  [경고 발생 시]                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ ⚠️  Database 권한 없음                                               │   │
│  │    'manage autonomous-database-family' 정책이 없습니다.              │   │
│  │    Database 기능이 제한될 수 있습니다.         [무시하고 계속] [해결]  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

STEP 3: Compartment 구조 탐색 & 태깅
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│  발견된 Compartment 구조                          [전체 펼치기] [전체 접기] │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ [✓] ▼ Acme-Root (12개 리소스)                                       │   │
│  │      [✓] ▼ Production (847개 리소스)       🏷 [prod] [서울]          │   │
│  │           [✓]   Web-Tier (234개)                                    │   │
│  │           [✓]   App-Tier (198개)                                    │   │
│  │           [✓]   DB-Tier (45개)                                     │   │
│  │      [✓] ▼ Staging (123개 리소스)          🏷 [staging]             │   │
│  │      [✓] ▼ Dev (67개 리소스)               🏷 [dev]                 │   │
│  │      [✓]   Network (23개 리소스)           🏷 [network] [공통]      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  모니터링 범위: [선택된 Compartment만 ▾]                                    │
│                                                                             │
│  ☑ Production 및 하위 전체 포함                                            │
│  ☑ Staging 포함                                                            │
│  ☐ Dev 포함 (비용 절약을 위해 제외 권장)                                    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

STEP 4: 모니터링 기본값 설정
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│  기본 알람 임계값 (나중에 개별 조정 가능)                                    │
│                                                                             │
│  CPU 사용률 경고         [80]  %  이상    지속  [5]  분                     │
│  CPU 사용률 위험         [95]  %  이상    지속  [3]  분                     │
│  메모리 사용률 경고      [80]  %  이상    지속  [5]  분                     │
│  메모리 사용률 위험      [95]  %  이상    지속  [3]  분                     │
│                                                                             │
│  알람 수신 채널                                                             │
│  ☑ 이메일    [ops@acme.com                              ] [+ 추가]         │
│  ☑ Slack     [#oci-alerts                               ] [연결 테스트]    │
│  ☐ SMS                                                                     │
│  ☐ PagerDuty                                                               │
│                                                                             │
│  Maintenance Window (알람 무음 구간)                                        │
│  매주  [일요일 ▾]  [00:00] ~ [06:00]  [+ 추가]                            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

STEP 5: 담당자 & SLA 배정
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│  주 담당 엔지니어                          백업 담당자                       │
│  [홍길동 (hong@msp.co.kr) ▾          ]  [김영수 (kim@msp.co.kr) ▾     ]   │
│                                                                             │
│  SLA 설정 (Premium 티어 기본값)                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ P1 대응 시간  [30]  분   │  가용성 목표  [99.9]  %                    │   │
│  │ P2 대응 시간  [2 ]  시간 │  RTO 목표     [4  ]  시간                  │   │
│  │ P3 대응 시간  [8 ]  시간 │  RPO 목표     [1  ]  시간                  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  온보딩 요약                                                                │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   │
│  고객사: Acme Corporation                                                   │
│  테넌시: ocid1.tenancy.oc1..xxx (ap-seoul-1)                               │
│  리소스: 1,060개 (Production + Staging 범위)                                │
│  담당자: 홍길동 / 김영수                                                     │
│  SLA:   Premium (P1 30분, 가용성 99.9%)                                    │
│                                                                             │
│  [이전]                           [온보딩 완료 및 동기화 시작 ✓]            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### B-3. Step Wizard 컴포넌트

```typescript
// components/features/tenants/OnboardingWizard/index.tsx
'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { type WizardStep, wizardSteps } from './steps';
import { StepIndicator } from './StepIndicator';
import { Step1Credentials } from './Step1Credentials';
import { Step2Verification } from './Step2Verification';
import { Step3Structure } from './Step3Structure';
import { Step4Monitoring } from './Step4Monitoring';
import { Step5Assignment } from './Step5Assignment';

export type OnboardingData = {
  // Step 1
  accessMethod:  'cross-tenancy' | 'api-key';
  displayName:   string;
  tenancyOcid:   string;
  homeRegion:    string;
  slaTier:       'BASIC' | 'STANDARD' | 'PREMIUM' | 'ENTERPRISE';
  // Step 3
  compartments:  string[];
  // Step 4
  cpuThreshold:  number;
  memThreshold:  number;
  alertChannels: string[];
  // Step 5
  primaryEngineerId:  string;
  backupEngineerId:   string;
  slaConfig:          SLAConfig;
};

const STEPS = [
  { id: 1, label: 'Credential', description: '연결 정보 입력' },
  { id: 2, label: '권한 검증',  description: '자동 확인' },
  { id: 3, label: '구조 탐색',  description: 'Compartment 설정' },
  { id: 4, label: '모니터링',   description: '기본값 설정' },
  { id: 5, label: '담당자',     description: 'SLA 배정' },
] as const;

export function OnboardingWizard() {
  const router = useRouter();
  const [currentStep, setCurrentStep] = useState(1);
  const [data, setData] = useState<Partial<OnboardingData>>({});

  // URL에 스텝 동기화 (새로고침 복원)
  useEffect(() => {
    const url = new URL(window.location.href);
    url.searchParams.set('step', String(currentStep));
    window.history.replaceState({}, '', url.toString());
  }, [currentStep]);

  const handleNext = (stepData: Partial<OnboardingData>) => {
    setData(prev => ({ ...prev, ...stepData }));
    setCurrentStep(s => Math.min(s + 1, 5));
  };

  const handleBack = () => setCurrentStep(s => Math.max(s - 1, 1));

  const handleComplete = async (finalData: Partial<OnboardingData>) => {
    const merged = { ...data, ...finalData } as OnboardingData;
    // API 호출 → 완료 후 테넌시 상세 페이지로 이동
    const tenant = await createTenant(merged);
    router.push(`/tenants/${tenant.id}`);
  };

  return (
    <div className="max-w-3xl mx-auto">
      {/* 스텝 표시기 */}
      <StepIndicator steps={STEPS} currentStep={currentStep} />

      {/* 스텝 콘텐츠 */}
      <div className="mt-8">
        {currentStep === 1 && <Step1Credentials onNext={handleNext} initialData={data} />}
        {currentStep === 2 && <Step2Verification tenancyData={data} onNext={handleNext} onBack={handleBack} />}
        {currentStep === 3 && <Step3Structure tenancyData={data} onNext={handleNext} onBack={handleBack} />}
        {currentStep === 4 && <Step4Monitoring onNext={handleNext} onBack={handleBack} />}
        {currentStep === 5 && <Step5Assignment allData={data} onComplete={handleComplete} onBack={handleBack} />}
      </div>

      {/* 하단 고정 푸터 */}
      <div className="mt-8 flex items-center justify-between text-sm text-[var(--text-tertiary)] border-t border-[var(--border)] pt-4">
        <span>⏱ 예상 완료: {estimateRemaining(currentStep)}분 남음</span>
        <div className="flex gap-3">
          <Button variant="ghost" size="sm" onClick={saveDraft}>
            저장하고 나중에 계속
          </Button>
          <Button variant="ghost" size="sm">
            도움말 ?
          </Button>
        </div>
      </div>
    </div>
  );
}
```

---

## C. 고객사 목록/상세 (/customers)

### C-1. 목록 화면 와이어프레임

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 고객사 관리                                                [+ 새 테넌시 추가] │
│ ─────────────────────────────────────────────────────────────────────────── │
│                                                                             │
│ [🔍 검색: 회사명, OCID...]  [상태 ▾]  [SLA 티어 ▾]  [리전 ▾]  [정렬 ▾]    │
│                                                                             │
│ 전체 24개  ·  이상 3개  ·  오늘 신규 1개                    [내보내기 ↓]    │
│                                                                             │
│ ┌──────────────────────────────────────────────────────────────────────┐   │
│ │ ☐  고객사                  상태   리소스   알람    비용      담당자     │   │
│ ├──────────────────────────────────────────────────────────────────────┤   │
│ │ ☐  🔴 Acme Corporation    ●이상  1,060    🔴2 🟠3  ₩4.2M   홍길동   [→]│
│ │    OCID: ocid1.tenancy... ap-seoul-1       🟡8          +127%↑      │   │
│ ├──────────────────────────────────────────────────────────────────────┤   │
│ │ ☐  🟢 Beta Inc            ●정상   847     🟠5      ₩2.8M   김영수   [→]│
│ │    OCID: ocid1.tenancy... ap-seoul-1                     +12%↑      │   │
│ ├──────────────────────────────────────────────────────────────────────┤   │
│ │ ☐  🟡 Gamma Co            ●경고   312     🟡11     ₩3.1M   이민준   [→]│
│ │    OCID: ocid1.tenancy... ap-chuncheon-1                 -3%↓       │   │
│ ├──────────────────────────────────────────────────────────────────────┤   │
│ │ ☐  🟢 Delta LLC           ●정상   198     -        ₩0.9M   박지수   [→]│
│ │    OCID: ocid1.tenancy... ap-seoul-1                     +5%↑       │   │
│ ├──────────────────────────────────────────────────────────────────────┤   │
│ │  [+20개 더 보기] 또는 [스크롤하여 자동 로드]                          │   │
│ └──────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│ [일괄 선택 시] ────────────────────────────────────────────────────────── │
│  ☑  3개 선택됨    [보고서 생성] [일괄 동기화] [담당자 변경] [비활성화]       │
└─────────────────────────────────────────────────────────────────────────────┘
```

### C-2. 상세 Side Sheet

```
┌───────────────────────────────────────────────────────────────────┬─────────────────────────┐
│  (배경 — 목록 컨텍스트 유지, 어둡게 처리)                          │ Acme Corporation      [X] │
│                                                                   │ ─────────────────────── │
│                                                                   │ ●이상  ocid1.tenancy... │
│                                                                   │ ap-seoul-1  Premium SLA │
│                                                                   │                         │
│                                                                   │ [개요][리소스][모니터링] │
│                                                                   │ [비용][설정]             │
│                                                                   │                         │
│                                                                   │ ── 개요 탭 ──           │
│                                                                   │                         │
│                                                                   │ KPI 요약                │
│                                                                   │ ┌───────┐ ┌───────────┐ │
│                                                                   │ │ 리소스 │ │  활성 알람  │ │
│                                                                   │ │ 1,060 │ │   🔴 2    │ │
│                                                                   │ └───────┘ └───────────┘ │
│                                                                   │ ┌───────┐ ┌───────────┐ │
│                                                                   │ │ 이달비용│ │ 가용성    │ │
│                                                                   │ │ ₩4.2M │ │ 99.98%   │ │
│                                                                   │ └───────┘ └───────────┘ │
│                                                                   │                         │
│                                                                   │ CPU 트렌드 (7일)        │
│                                                                   │ ~~~^~~~___~~^~~          │
│                                                                   │                         │
│                                                                   │ 최근 Incident (2건)     │
│                                                                   │ 🔴 DB 연결 실패  2시간전 │
│                                                                   │ 🟠 CPU 과부하  3일전    │
│                                                                   │                         │
│                                                                   │ 담당 엔지니어           │
│                                                                   │ 👤 홍길동               │
│                                                                   │ 📧 hong@msp.co.kr       │
│                                                                   │                         │
│                                                                   │ [전체 상세 보기 →]      │
│                                                                   │ [OCI 콘솔 열기 ↗]       │
└───────────────────────────────────────────────────────────────────┴─────────────────────────┘
```

---

## D. Compute 리소스 관리 (/compute/instances)

### D-1. 와이어프레임

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Compute › 인스턴스                                                          │
│                                                                             │
│ [🔍 인스턴스명, OCID, IP...]  [테넌시 ▾: Acme]  [리전 ▾]  [상태 ▾]  [Shape ▾] │
│                                                                             │
│ 전체 847개  ·  실행 중 724  ·  중지됨 98  ·  오류 25          [열 설정 ⚙]  │
│                                                                             │
│ ┌──────────────────────────────────────────────────────────────────────┐   │
│ │ ☐  인스턴스명     상태  테넌시     Shape         CPU%   MEM%  IP           │
│ ├──────────────────────────────────────────────────────────────────────┤   │
│ │ ☐  web-prod-01  ●실행 Acme     VM.Std.E4.4   ████▌ 87%  ████▌ 91%  10.0.1.10  [···]│
│ │                                                       ⚠ 높음         │   │
│ ├──────────────────────────────────────────────────────────────────────┤   │
│ │ ☐  web-prod-02  ●실행 Acme     VM.Std.E4.4   ██▌   45%  ███   62%  10.0.1.11  [···]│
│ ├──────────────────────────────────────────────────────────────────────┤   │
│ │ ☐  app-prod-01  ●실행 Acme     VM.Std.E4.8   █████ 92%  ████  78%  10.0.2.10  [···]│
│ │                                                       🔴 위험        │   │
│ ├──────────────────────────────────────────────────────────────────────┤   │
│ │ ☐  db-prod-01   ●실행 Acme     BM.HPC2.36    ██    32%  ████▌ 89%  10.0.3.10  [···]│
│ ├──────────────────────────────────────────────────────────────────────┤   │
│ │ ☐  stage-app-01 ●중지 Acme     VM.Std.E4.4   ──    -    ──    -    10.0.1.20  [···]│
│ ├──────────────────────────────────────────────────────────────────────┤   │
│ │ ☐  old-server   🔴오류 Beta     VM.Std.E4.2   !     -    !     -    10.0.1.50  [···]│
│ │                                                                      │   │
│ │  [가상화 스크롤 — 수천 행 성능 보장]                                  │   │
│ └──────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│ [일괄 액션 Fixed Bar — 체크 시 나타남]                                      │
│ ☑ 3개 선택   [▶ 시작]  [■ 중지]  [↺ 재시작]  [··· 더보기▾]     [선택 해제] │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### D-2. 인라인 메트릭 바 + Fixed Action Bar

```typescript
// components/features/compute/InstanceTable.tsx
'use client';

import { useVirtualizer } from '@tanstack/react-virtual';
import { useReactTable, getCoreRowModel, type ColumnDef } from '@tanstack/react-table';
import { type Instance } from '@/types/resources';
import { MetricBar } from '@/components/shared/MetricBar';
import { StatusBadge } from '@/components/shared/StatusBadge';

const columns: ColumnDef<Instance>[] = [
  {
    id:     'select',
    header: ({ table }) => (
      <Checkbox
        checked={table.getIsAllRowsSelected()}
        onCheckedChange={table.getToggleAllRowsSelectedHandler()}
        aria-label="전체 선택"
      />
    ),
    cell: ({ row }) => (
      <Checkbox
        checked={row.getIsSelected()}
        onCheckedChange={row.getToggleSelectedHandler()}
        onClick={e => e.stopPropagation()}
        aria-label={`${row.original.displayName} 선택`}
      />
    ),
    size: 40,
  },
  {
    accessorKey: 'displayName',
    header:      '인스턴스명',
    cell:        ({ row }) => (
      <button
        className="text-left font-medium text-[var(--brand-accent)] hover:underline"
        onClick={() => openSideSheet(row.original.id)}
      >
        {row.original.displayName}
      </button>
    ),
  },
  {
    accessorKey: 'lifecycleState',
    header:      '상태',
    cell:        ({ getValue }) => <StatusBadge status={getValue<string>()} />,
    size:        90,
  },
  {
    id:   'cpu',
    header: 'CPU%',
    cell: ({ row }) => (
      <div className="flex items-center gap-2">
        <MetricBar value={row.original.cpuUtilization} size="sm" />
        <span className="text-xs w-8 text-right">{row.original.cpuUtilization}%</span>
        {row.original.cpuUtilization > 90 && (
          <AlertTriangle size={12} className="text-status-error" />
        )}
      </div>
    ),
    size: 140,
  },
  {
    id:   'mem',
    header: 'MEM%',
    cell: ({ row }) => (
      <div className="flex items-center gap-2">
        <MetricBar value={row.original.memUtilization} size="sm" />
        <span className="text-xs w-8 text-right">{row.original.memUtilization}%</span>
      </div>
    ),
    size: 140,
  },
  // ... 나머지 열
];

export function InstanceTable({ instances }: { instances: Instance[] }) {
  const parentRef = useRef<HTMLDivElement>(null);

  const table = useReactTable({
    data:           instances,
    columns,
    getCoreRowModel: getCoreRowModel(),
    enableRowSelection: true,
  });

  const { rows } = table.getRowModel();
  const rowVirtualizer = useVirtualizer({
    count:        rows.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => 52,   // 행 높이 추정
    overscan:     20,
  });

  const selectedRows = table.getSelectedRowModel().rows;

  return (
    <div className="relative">
      {/* 가상화 테이블 */}
      <div ref={parentRef} className="overflow-auto h-[calc(100vh-280px)]">
        <table className="w-full border-collapse">
          <thead className="sticky top-0 z-10 bg-[var(--surface)]">
            {table.getHeaderGroups().map(headerGroup => (
              <tr key={headerGroup.id}>
                {headerGroup.headers.map(header => (
                  <th
                    key={header.id}
                    className="border-b border-[var(--border)] px-4 py-3 text-left
                               text-xs font-medium text-[var(--text-secondary)] uppercase"
                    style={{ width: header.getSize() }}
                  >
                    {flexRender(header.column.columnDef.header, header.getContext())}
                  </th>
                ))}
              </tr>
            ))}
          </thead>
          <tbody
            style={{ height: `${rowVirtualizer.getTotalSize()}px`, position: 'relative' }}
          >
            {rowVirtualizer.getVirtualItems().map(virtualRow => {
              const row = rows[virtualRow.index];
              return (
                <tr
                  key={row.id}
                  data-index={virtualRow.index}
                  ref={rowVirtualizer.measureElement}
                  className={cn(
                    'border-b border-[var(--border)] hover:bg-[var(--surface-raised)]',
                    'cursor-pointer transition-colors',
                    row.getIsSelected() && 'bg-[var(--status-info-bg)]'
                  )}
                  style={{ position: 'absolute', top: virtualRow.start, width: '100%' }}
                  onClick={() => openSideSheet(row.original.id)}
                >
                  {row.getVisibleCells().map(cell => (
                    <td key={cell.id} className="px-4 py-3">
                      {flexRender(cell.column.columnDef.cell, cell.getContext())}
                    </td>
                  ))}
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {/* Fixed Action Bar — 선택 시 표시 */}
      <FixedActionBar
        selectedRows={selectedRows}
        onStart={handleBulkStart}
        onStop={handleBulkStop}
        onRestart={handleBulkRestart}
        onClear={() => table.resetRowSelection()}
      />
    </div>
  );
}

// Fixed Action Bar
function FixedActionBar({ selectedRows, onStart, onStop, onRestart, onClear }) {
  if (selectedRows.length === 0) return null;

  return (
    <div
      className={cn(
        'fixed bottom-0 left-0 right-0 z-50',
        'flex items-center gap-3 border-t border-[var(--border)]',
        'bg-[var(--surface)] px-6 py-3 shadow-xl',
        'animate-in slide-in-from-bottom duration-200'
      )}
      role="toolbar"
      aria-label="일괄 작업"
    >
      <span className="text-sm font-medium">
        {selectedRows.length}개 선택됨
      </span>
      <div className="flex gap-2">
        <AsyncJobButton variant="outline" size="sm" onClick={onStart} icon={<Play size={14} />}>
          시작
        </AsyncJobButton>
        <AsyncJobButton variant="warning" size="sm" onClick={onStop} icon={<Square size={14} />}>
          중지
        </AsyncJobButton>
        <AsyncJobButton variant="outline" size="sm" onClick={onRestart} icon={<RotateCcw size={14} />}>
          재시작
        </AsyncJobButton>
      </div>
      <Button variant="ghost" size="sm" onClick={onClear} className="ml-auto">
        선택 해제
      </Button>
    </div>
  );
}
```

---

## E. 모니터링 대시보드 (/monitoring)

### E-1. 와이어프레임

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 모니터링                     [테넌시: 전체 ▾]  [리전: 전체 ▾]  [기간: 1h ▾] │
│ ─────────────────────────────────────────────────────────────────────────── │
│                                                                             │
│  ┌─────────────────────────────┐  ┌───────────────────────────────────────┐│
│  │ 알람 요약                    │  │ CPU 사용률 — 상위 10개 인스턴스 (1h)   ││
│  │                             │  │                                       ││
│  │  🔴 P1 Critical    3 건     │  │  100%│    /╲         ╱╲              ││
│  │  🟠 P2 High        8 건     │  │   80%│   /  ╲  ____╱  ╲___          ││
│  │  🟡 P3 Medium     21 건     │  │   60%│  /    ╲╱                      ││
│  │  🔵 P4 Low        45 건     │  │   40%│──────────────────────         ││
│  │                             │  │   20%│                               ││
│  │  [무음 처리] [일괄 확인]     │  │    0%└───────────────────────────── ││
│  │                             │  │      12:00  12:15  12:30  12:45  13:00││
│  │ ── 활성 알람 목록 ──         │  │                                       ││
│  │                             │  │  [시계열 범위 드래그하여 확대]          ││
│  │ 🔴 Acme/CPU 위험  2분전     │  └───────────────────────────────────────┘│
│  │    web-prod-01   CPU: 97%  [확인]                                       │
│  │                             │  ┌───────────────────────────────────────┐│
│  │ 🔴 Acme/DB 오류   5분전     │  │ 메모리 사용률 (1h)                     ││
│  │    db-prod-01  연결 실패   [확인]  ...동일한 차트 패턴...              ││
│  │                             │  └───────────────────────────────────────┘│
│  │ 🟠 Beta/MEM 높음 12분전     │                                           │
│  │    app-server  MEM: 88%   [확인]  ┌───────────────────────────────────┐ │
│  │                             │  │ 네트워크 I/O (1h)                     │ │
│  │ [전체 77건 보기→]           │  │  ...                                  │ │
│  └─────────────────────────────┘  └───────────────────────────────────────┘│
│                                                                             │
│  알람 규칙 목록                                                [+ 새 규칙]  │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ 규칙명          대상        조건            활성화   마지막 발동       │   │
│  │ CPU-Critical    전체 VM     CPU > 95% 3분   ●켜짐  10분전   [편집]  │   │
│  │ MEM-Warning     Acme Prod  MEM > 80% 5분   ●켜짐  1시간전  [편집]  │   │
│  │ DB-Connection   DB 인스턴스 연결실패   즉시   ●켜짐  5분전   [편집]  │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### E-2. ECharts 시계열 컴포넌트

```typescript
// components/shared/MetricChart/index.tsx
'use client';

import { useEffect, useRef } from 'react';
import * as echarts from 'echarts/core';
import { LineChart } from 'echarts/charts';
import {
  GridComponent, TooltipComponent, LegendComponent,
  DataZoomComponent, MarkLineComponent,
} from 'echarts/components';
import { CanvasRenderer } from 'echarts/renderers';

echarts.use([
  LineChart, GridComponent, TooltipComponent,
  LegendComponent, DataZoomComponent, MarkLineComponent, CanvasRenderer,
]);

interface MetricSeries {
  name:  string;
  data:  [number, number][];  // [timestamp_ms, value]
  color?: string;
}

interface MetricChartProps {
  title?:      string;
  series:      MetricSeries[];
  unit?:       string;       // '%', 'MB/s', 'req/s'
  thresholds?: { value: number; label: string; color: string }[];
  height?:     number;
  timeRange?:  '1h' | '6h' | '24h' | '7d' | '30d';
  onZoom?:     (start: number, end: number) => void;
  className?:  string;
}

export function MetricChart({
  title, series, unit = '%', thresholds, height = 240, onZoom, className,
}: MetricChartProps) {
  const chartRef  = useRef<HTMLDivElement>(null);
  const chartInst = useRef<echarts.ECharts | null>(null);
  const { theme } = useTheme();

  // 초기화
  useEffect(() => {
    if (!chartRef.current) return;
    chartInst.current = echarts.init(chartRef.current, theme === 'dark' ? 'dark' : undefined);

    const handleResize = () => chartInst.current?.resize();
    window.addEventListener('resize', handleResize);
    return () => {
      window.removeEventListener('resize', handleResize);
      chartInst.current?.dispose();
    };
  }, [theme]);

  // 데이터 업데이트
  useEffect(() => {
    if (!chartInst.current) return;

    const isDark = theme === 'dark';

    const option: echarts.EChartsOption = {
      backgroundColor: 'transparent',
      animation: false,        // 성능 최적화
      grid: { top: 30, right: 20, bottom: 60, left: 55, containLabel: false },

      tooltip: {
        trigger:  'axis',
        axisPointer: { type: 'cross', label: { backgroundColor: '#6a7985' } },
        formatter: (params: any[]) =>
          params.map(p =>
            `<div style="display:flex;align-items:center;gap:8px">
              <span style="background:${p.color};width:10px;height:10px;border-radius:50%;display:inline-block"></span>
              <span>${p.seriesName}: <b>${p.value[1].toFixed(1)}${unit}</b>
            </div>`
          ).join(''),
      },

      xAxis: {
        type:       'time',
        axisLabel:  {
          color:      isDark ? '#94A3B8' : '#64748B',
          fontSize:   11,
          formatter:  (val: number) => new Date(val).toLocaleTimeString('ko-KR', { hour: '2-digit', minute: '2-digit' }),
        },
        axisLine:   { lineStyle: { color: isDark ? '#1F2937' : '#E2E8F0' } },
        splitLine:  { show: false },
      },

      yAxis: {
        type:      'value',
        min:       0,
        max:       unit === '%' ? 100 : undefined,
        axisLabel: { color: isDark ? '#94A3B8' : '#64748B', fontSize: 11, formatter: `{value}${unit}` },
        splitLine: { lineStyle: { color: isDark ? '#1F2937' : '#F1F5F9', type: 'dashed' } },
      },

      // 임계값 마크 라인
      series: series.map(s => ({
        name:      s.name,
        type:      'line',
        data:      s.data,
        smooth:    0.3,
        lineStyle: { width: 1.5, color: s.color },
        symbol:    'none',
        areaStyle: { color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
          { offset: 0, color: s.color + '33' },
          { offset: 1, color: s.color + '00' },
        ])},
        markLine: thresholds ? {
          silent: true,
          data: thresholds.map(t => ({
            yAxis: t.value,
            label: { formatter: t.label, position: 'end' },
            lineStyle: { color: t.color, type: 'dashed', width: 1 },
          })),
        } : undefined,
      })),

      // 범위 선택 (DataZoom)
      dataZoom: [
        { type: 'inside', start: 0, end: 100 },
        {
          type:       'slider',
          height:     20,
          bottom:     10,
          borderColor: isDark ? '#1F2937' : '#E2E8F0',
          fillerColor: isDark ? '#1E3A5F' : '#DBEAFE',
          handleStyle: { color: '#3B82F6' },
          moveHandleStyle: { color: '#3B82F6' },
          textStyle:   { color: isDark ? '#94A3B8' : '#64748B', fontSize: 10 },
        },
      ],

      legend: {
        top:       0,
        right:     0,
        textStyle: { color: isDark ? '#94A3B8' : '#64748B', fontSize: 11 },
        icon:      'circle',
        itemWidth: 8,
      },
    };

    chartInst.current.setOption(option, { notMerge: true });

    if (onZoom) {
      chartInst.current.on('datazoom', (e: any) => {
        onZoom(e.start, e.end);
      });
    }
  }, [series, thresholds, theme, unit, onZoom]);

  return (
    <div className={cn('rounded-lg border border-[var(--border)] bg-[var(--surface)] p-4', className)}>
      {title && <h3 className="text-sm font-medium text-[var(--text-secondary)] mb-3">{title}</h3>}
      <div ref={chartRef} style={{ height }} />
    </div>
  );
}
```

---

## F. Incident 관리 (/incidents)

### F-1. 목록 와이어프레임

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Incident 관리                                              [+ Incident 생성]│
│ ─────────────────────────────────────────────────────────────────────────── │
│                                                                             │
│  [🔍 검색]  [상태 ▾: 오픈]  [심각도 ▾]  [담당자 ▾]  [기간 ▾]              │
│                                                                             │
│  오픈 12건  ·  조치중 3건  ·  오늘 종료 5건                                 │
│                                                                             │
│ ┌──────────────────────────────────────────────────────────────────────┐   │
│ │ ID       제목                    심각도  상태   담당자  경과시간  SLA  │   │
│ ├──────────────────────────────────────────────────────────────────────┤   │
│ │ INC-089  Acme DB 연결 실패       🔴 P1  조치중  홍길동  0h 32m  ⚠SLA│   │
│ │          ∟ 알람 2건 연결됨   Acme Corp · ap-seoul-1                  │   │
│ ├──────────────────────────────────────────────────────────────────────┤   │
│ │ INC-088  Beta Compute CPU 과부하 🟠 P2  배정대기 -     1h 15m       │   │
│ │          ∟ 알람 5건 연결됨   Beta Inc · ap-seoul-1                   │   │
│ ├──────────────────────────────────────────────────────────────────────┤   │
│ │ INC-087  Gamma 네트워크 지연     🟡 P3  오픈    이민준  3h 42m       │   │
│ │                                Gamma Co · ap-chuncheon-1            │   │
│ ├──────────────────────────────────────────────────────────────────────┤   │
│ │ INC-086  ✅ Delta Storage 경보  🔵 P4  해결됨  박지수  어제          │   │
│ └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### F-2. Incident 상세 — 타임라인 시각화

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ ← 목록  /  INC-089: Acme DB 연결 실패                                      │
│                                                                             │
│  🔴 P1 Critical  ·  조치 중  ·  Acme Corp  ·  경과: 0h 32m               │
│                                                                             │
│  [담당자: 홍길동 ▾]  [심각도 ▾]  [상태: 조치중 ▾]  [RCA 작성] [종료]      │
│                                                                             │
│  ┌─────────────────────────────────────┐  ┌─────────────────────────────┐ │
│  │ 타임라인                             │  │ 연결된 알람 (2건)            │ │
│  │                                     │  │                             │ │
│  │ 13:15  🔴 P1 알람 발생              │  │ 🔴 DB 연결 실패 (Acme)      │ │
│  │         DB 연결 실패 감지           │  │    발생: 13:15  지속: 32분   │ │
│  │         [시스템 자동]               │  │                             │ │
│  │              │                      │  │ 🔴 CPU 급상승 (Acme DB)     │ │
│  │ 13:16  📧 Incident 자동 생성       │  │    발생: 13:16  지속: 31분   │ │
│  │              │                      │  └─────────────────────────────┘ │
│  │ 13:18  👤 홍길동 배정됨            │                                   │
│  │         [시스템: On-call 배정]     │  ┌─────────────────────────────┐ │
│  │              │                      │  │ 관련 리소스                  │ │
│  │ 13:22  💬 홍길동 조치 기록         │  │                             │ │
│  │         "DB 재시작 시도 중"         │  │ 💾 db-prod-01               │ │
│  │              │                      │  │    ocid1.dbsystem.oc1...    │ │
│  │ 13:28  ↺ 재시작 작업 시작          │  │    상태: 🔴 오류            │ │
│  │         [Job #4521 — 진행 60%]     │  │                             │ │
│  │         ━━━━━━━━━━━━━━━━━━━  60%  │  │ 💻 db-app-01                │ │
│  │              │                      │  │    ocid1.instance.oc1...    │ │
│  │ 13:47  [현재]                       │  │    상태: 🟢 실행 중         │ │
│  │         ⟳ 작업 완료 대기           │  └─────────────────────────────┘ │
│  │                                     │                                   │
│  │ 조치 기록 추가:                     │  ┌─────────────────────────────┐ │
│  │ ┌─────────────────────────────┐    │  │ 에스컬레이션                 │ │
│  │ │ 조치 내용을 입력하세요...    │    │  │                             │ │
│  │ └─────────────────────────────┘    │  │ P1 SLA 만료: 14분 후        │ │
│  │ [내부 메모] [공개 업데이트] [등록] │  │ ⚠ SLA 위반 위험             │ │
│  │                                     │  │                             │ │
│  └─────────────────────────────────────┘  │ [상위 에스컬레이션]         │ │
│                                            └─────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## G. 비용 분석 (/billing)

### G-1. 와이어프레임

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 비용 분석                    [기간: 2026년 3월 ▾]  [테넌시: 전체 ▾]         │
│ ─────────────────────────────────────────────────────────────────────────── │
│                                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ 이달 총 비용  │  │ 전월 대비     │  │ 예산 대비     │  │ 월말 예상    │  │
│  │              │  │              │  │              │  │              │  │
│  │  ₩13,100만  │  │  +₩900만     │  │  ████░░  78%│  │  ₩15,600만  │  │
│  │              │  │   +7.4% ↑   │  │  예산: ₩1.6억│  │  예산 초과 예상│  │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘  │
│                                                                             │
│  ┌──────────────────────────────────┐  ┌───────────────────────────────┐  │
│  │ 고객사별 비용 분포 (Donut)        │  │ 서비스별 비용 (Bar)            │  │
│  │                                  │  │                               │  │
│  │     ┌─────────────────────┐      │  │ Compute  ████████████ ₩6.8M  │  │
│  │     │  ●Acme  32.1%       │      │  │ Database ████████     ₩4.1M  │  │
│  │     │  ●Beta  21.4%       │  ○   │  │ Network  ████         ₩2.1M  │  │
│  │     │  ●Gamma 23.7%       │  ○   │  │ Storage  ██           ₩0.9M  │  │
│  │     │  ●기타  22.8%       │      │  │ 기타     █            ₩0.2M  │  │
│  │     └─────────────────────┘      │  │                               │  │
│  └──────────────────────────────────┘  └───────────────────────────────┘  │
│                                                                             │
│  월별 비용 추이 (12개월, Stacked Bar)                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │   1.5억│                                              ████          │   │
│  │       │                              ████  ████  ████████          │   │
│  │   1.0억│         ████  ████  ████  ████████████████████████         │   │
│  │       │ ████  ████████████████████████████████████████████         │   │
│  │   0.5억│ ████████████████████████████████████████████████          │   │
│  │       └─────────────────────────────────────────────────────────   │   │
│  │        4월   5월   6월   7월   8월   9월   10월  11월  12월  1월  2월  3월│   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  상세 내역 테이블                                        [Excel 다운로드 ↓] │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ 고객사    서비스    리소스         이달 비용   전월비용   증감        │   │
│  │ Acme     Compute  web-prod-01  ₩380,000   ₩310,000  +22.6%↑      │   │
│  │ Acme     Database db-prod-01   ₩1,200,000 ₩1,100,000 +9.1%↑       │   │
│  │ ...                                                                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## H. Command Palette ([Cmd+K])

### H-1. 와이어프레임

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ (배경 오버레이 — backdrop-blur)                                             │
│                                                                             │
│            ┌─────────────────────────────────────────────┐                 │
│            │ 🔍 [검색어 입력...                        ] │                 │
│            │ ─────────────────────────────────────────── │                 │
│            │                                             │                 │
│            │  최근 방문                                  │                 │
│            │  🏢 Acme Corporation         테넌시   ↵    │                 │
│            │  💻 web-prod-01              인스턴스  ↵    │                 │
│            │  🎫 INC-089 DB 연결 실패     Incident  ↵    │                 │
│            │                                             │                 │
│            │  빠른 작업                                  │                 │
│            │  + 새 테넌시 온보딩                   ↵    │                 │
│            │  + 새 알람 규칙                       ↵    │                 │
│            │  📋 감사 로그 보기                    ↵    │                 │
│            │                                             │                 │
│            │ ─── [검색 결과: "acme cpu"] ──────────────  │                 │
│            │                                             │                 │
│            │  🏢 Acme Corporation         테넌시   ↵    │                 │
│            │     ap-seoul-1 · Premium SLA               │                 │
│            │                                             │                 │
│            │  💻 인스턴스: CPU > 90% (Acme)    모니터링 ↵│                 │
│            │     app-prod-01, web-prod-01               │                 │
│            │                                             │                 │
│            │  📡 알람: CPU-Critical (Acme)   알람규칙  ↵ │                 │
│            │     3분 전 발동 · P1                        │                 │
│            │                                             │                 │
│            │  ─────────────────────────────────────────  │                 │
│            │  ↑↓ 이동   ↵ 선택   Esc 닫기   Tab 카테고리 │                 │
│            └─────────────────────────────────────────────┘                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### H-2. Command Palette 구현

```typescript
// components/shared/CommandPalette/index.tsx
'use client';

import { useState, useEffect, useCallback, useRef } from 'react';
import { useRouter } from 'next/navigation';
import { Command } from 'cmdk';
import { Dialog, DialogContent } from '@/components/ui/dialog';
import { useUIStore } from '@/stores/ui.store';
import { usePaletteSearch } from './usePaletteSearch';

export function CommandPalette() {
  const { commandPaletteOpen, setCommandPaletteOpen } = useUIStore();
  const [query, setQuery] = useState('');
  const router = useRouter();

  // 전역 단축키 등록
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
        e.preventDefault();
        setCommandPaletteOpen(true);
      }
    };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [setCommandPaletteOpen]);

  const { results, isLoading } = usePaletteSearch(query);

  const handleSelect = useCallback((href: string) => {
    setCommandPaletteOpen(false);
    setQuery('');
    router.push(href);
  }, [router, setCommandPaletteOpen]);

  return (
    <Dialog open={commandPaletteOpen} onOpenChange={setCommandPaletteOpen}>
      <DialogContent
        className="p-0 max-w-xl overflow-hidden shadow-xl"
        aria-label="Command Palette"
      >
        <Command shouldFilter={false} loop>
          {/* 검색 입력 */}
          <div className="flex items-center border-b border-[var(--border)] px-3">
            <Search size={16} className="text-[var(--text-tertiary)] mr-2 shrink-0" />
            <Command.Input
              value={query}
              onValueChange={setQuery}
              placeholder="검색어 입력... (리소스, 테넌시, 작업)"
              className="h-12 w-full bg-transparent text-sm outline-none placeholder:text-[var(--text-tertiary)]"
            />
            {isLoading && <Loader2 size={16} className="animate-spin text-[var(--text-tertiary)]" />}
          </div>

          <Command.List className="max-h-96 overflow-y-auto py-2">
            <Command.Empty className="py-8 text-center text-sm text-[var(--text-tertiary)]">
              "{query}"에 대한 결과가 없습니다.
            </Command.Empty>

            {/* 최근 방문 (query 없을 때) */}
            {!query && (
              <Command.Group heading="최근 방문" className="px-2">
                {results.recent.map(item => (
                  <PaletteItem key={item.id} item={item} onSelect={handleSelect} />
                ))}
              </Command.Group>
            )}

            {/* 빠른 작업 */}
            {!query && (
              <Command.Group heading="빠른 작업" className="px-2">
                {QUICK_ACTIONS.map(action => (
                  <PaletteItem key={action.id} item={action} onSelect={handleSelect} />
                ))}
              </Command.Group>
            )}

            {/* 검색 결과 */}
            {query && results.tenants.length > 0 && (
              <Command.Group heading="테넌시" className="px-2">
                {results.tenants.map(item => (
                  <PaletteItem key={item.id} item={item} onSelect={handleSelect} />
                ))}
              </Command.Group>
            )}

            {query && results.resources.length > 0 && (
              <Command.Group heading="리소스" className="px-2">
                {results.resources.map(item => (
                  <PaletteItem key={item.id} item={item} onSelect={handleSelect} />
                ))}
              </Command.Group>
            )}

            {query && results.incidents.length > 0 && (
              <Command.Group heading="Incident" className="px-2">
                {results.incidents.map(item => (
                  <PaletteItem key={item.id} item={item} onSelect={handleSelect} />
                ))}
              </Command.Group>
            )}

            {query && results.alarms.length > 0 && (
              <Command.Group heading="알람" className="px-2">
                {results.alarms.map(item => (
                  <PaletteItem key={item.id} item={item} onSelect={handleSelect} />
                ))}
              </Command.Group>
            )}
          </Command.List>

          {/* 하단 힌트 */}
          <div className="border-t border-[var(--border)] px-3 py-2 flex items-center gap-4 text-2xs text-[var(--text-tertiary)]">
            <span><kbd className="border border-[var(--border)] rounded px-1">↑↓</kbd> 이동</span>
            <span><kbd className="border border-[var(--border)] rounded px-1">↵</kbd> 선택</span>
            <span><kbd className="border border-[var(--border)] rounded px-1">Esc</kbd> 닫기</span>
          </div>
        </Command>
      </DialogContent>
    </Dialog>
  );
}

function PaletteItem({ item, onSelect }: { item: PaletteResultItem; onSelect: (href: string) => void }) {
  const Icon = item.icon;
  return (
    <Command.Item
      value={item.id}
      onSelect={() => onSelect(item.href)}
      className={cn(
        'flex items-center gap-3 rounded-md px-2 py-2 cursor-pointer',
        'aria-selected:bg-[var(--surface-raised)] text-sm',
        'transition-colors'
      )}
    >
      <div className="flex h-8 w-8 items-center justify-center rounded-md bg-[var(--surface-raised)] shrink-0">
        <Icon size={14} className="text-[var(--text-secondary)]" />
      </div>
      <div className="flex-1 min-w-0">
        <div className="font-medium truncate">{item.label}</div>
        {item.description && (
          <div className="text-xs text-[var(--text-tertiary)] truncate">{item.description}</div>
        )}
      </div>
      <kbd className="text-2xs text-[var(--text-tertiary)] border border-[var(--border)] rounded px-1.5 py-0.5 shrink-0">
        ↵
      </kbd>
    </Command.Item>
  );
}
```
