# UI/UX 설계서 — Part 1: 디자인 시스템

> OCI MSP 관리 플랫폼 | 작성일: 2026-03-21 | 상태: 확정

---

## 1. 디자인 철학: "Professional Clarity"

| 원칙 | 설명 |
|------|------|
| Context Awareness | 현재 테넌시/리소스 위치를 항상 Breadcrumb으로 명시 |
| Density with Clarity | 기본 뷰(핵심 지표) / 전문가 모드(전체 데이터) 단계적 공개 |
| Trust & Safety | 파괴적 작업의 위험도별 시각적 분리, Preview before action |
| Speed First | 빈번 작업 3클릭 이내, Skeleton UI 즉시 피드백, 키보드 퍼스트 |

---

## 2. 컬러 팔레트

### 2-1. CSS 변수 (globals.css)

```css
/* ===== Light Mode ===== */
:root {
  /* Background */
  --background:        #F8FAFC;   /* slate-50  — 페이지 배경 */
  --surface:           #FFFFFF;   /* white     — 카드/패널 */
  --surface-raised:    #F1F5F9;   /* slate-100 — hover, 구분 영역 */
  --surface-overlay:   #E2E8F0;   /* slate-200 — 모달 배경 */

  /* Text */
  --text-primary:      #0F172A;   /* slate-900 */
  --text-secondary:    #475569;   /* slate-600 */
  --text-tertiary:     #94A3B8;   /* slate-400 */
  --text-disabled:     #CBD5E1;   /* slate-300 */
  --text-inverse:      #F8FAFC;   /* slate-50  */

  /* Brand */
  --brand-primary:     #C74634;   /* OCI Red   — Oracle 브랜드 */
  --brand-secondary:   #1E40AF;   /* blue-800  — 보조 강조 */
  --brand-accent:      #0EA5E9;   /* sky-500   — 인터랙티브 */

  /* Border */
  --border:            #E2E8F0;   /* slate-200 */
  --border-strong:     #CBD5E1;   /* slate-300 */
  --border-focus:      #0EA5E9;   /* sky-500   — focus ring */

  /* Status */
  --status-success:    #10B981;   /* emerald-500 */
  --status-warning:    #F59E0B;   /* amber-500   */
  --status-error:      #EF4444;   /* red-500     */
  --status-info:       #3B82F6;   /* blue-500    */
  --status-neutral:    #6B7280;   /* gray-500    */

  /* Status Background (subtle) */
  --status-success-bg: #ECFDF5;
  --status-warning-bg: #FFFBEB;
  --status-error-bg:   #FEF2F2;
  --status-info-bg:    #EFF6FF;

  /* Severity — Incident/Alert */
  --severity-p1:       #EF4444;   /* Critical — red-500   */
  --severity-p2:       #F97316;   /* High     — orange-500 */
  --severity-p3:       #F59E0B;   /* Medium   — amber-500  */
  --severity-p4:       #3B82F6;   /* Low      — blue-500   */

  /* Shadow */
  --shadow-sm:  0 1px 2px 0 rgba(0,0,0,0.05);
  --shadow-md:  0 4px 6px -1px rgba(0,0,0,0.1);
  --shadow-lg:  0 10px 15px -3px rgba(0,0,0,0.1);
  --shadow-xl:  0 20px 25px -5px rgba(0,0,0,0.1);

  /* Radius */
  --radius-sm:  4px;
  --radius-md:  8px;
  --radius-lg:  12px;
  --radius-xl:  16px;
  --radius-full: 9999px;

  /* Transition */
  --transition-fast:   150ms ease;
  --transition-normal: 200ms ease;
  --transition-slow:   300ms ease;
}

/* ===== Dark Mode ===== */
.dark {
  /* Background — 딥 네이비 테마 (OCI 브랜드 연계) */
  --background:        #0A0E1A;   /* 최상위 배경 */
  --surface:           #111827;   /* gray-900   — 카드/패널 */
  --surface-raised:    #1F2937;   /* gray-800   — hover */
  --surface-overlay:   #374151;   /* gray-700   — 모달 */

  /* Text */
  --text-primary:      #F1F5F9;   /* slate-100 */
  --text-secondary:    #94A3B8;   /* slate-400 */
  --text-tertiary:     #64748B;   /* slate-500 */
  --text-disabled:     #374151;   /* gray-700  */
  --text-inverse:      #0F172A;   /* slate-900 */

  /* Brand — 다크에서는 조금 밝게 */
  --brand-primary:     #E05A48;
  --brand-secondary:   #3B82F6;
  --brand-accent:      #38BDF8;

  /* Border */
  --border:            #1F2937;   /* gray-800 */
  --border-strong:     #374151;   /* gray-700 */
  --border-focus:      #38BDF8;

  /* Status (배경만 어둡게) */
  --status-success-bg: #022C22;
  --status-warning-bg: #1C1A00;
  --status-error-bg:   #1F0A0A;
  --status-info-bg:    #0C1A33;

  /* Shadow */
  --shadow-sm:  0 1px 2px 0 rgba(0,0,0,0.4);
  --shadow-md:  0 4px 6px -1px rgba(0,0,0,0.5);
  --shadow-lg:  0 10px 15px -3px rgba(0,0,0,0.5);
  --shadow-xl:  0 20px 25px -5px rgba(0,0,0,0.6);
}
```

### 2-2. Tailwind 커스텀 설정 (tailwind.config.ts)

```typescript
import type { Config } from 'tailwindcss';

const config: Config = {
  darkMode: ['class'],
  content: ['./src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        background: 'var(--background)',
        surface: 'var(--surface)',
        'surface-raised': 'var(--surface-raised)',
        border: 'var(--border)',
        'border-strong': 'var(--border-strong)',
        brand: {
          primary:   'var(--brand-primary)',
          secondary: 'var(--brand-secondary)',
          accent:    'var(--brand-accent)',
        },
        status: {
          success: 'var(--status-success)',
          warning: 'var(--status-warning)',
          error:   'var(--status-error)',
          info:    'var(--status-info)',
        },
        severity: {
          p1: 'var(--severity-p1)',
          p2: 'var(--severity-p2)',
          p3: 'var(--severity-p3)',
          p4: 'var(--severity-p4)',
        },
      },
      fontFamily: {
        sans:  ['Inter', 'system-ui', 'sans-serif'],
        mono:  ['JetBrains Mono', 'Fira Code', 'monospace'],
      },
      fontSize: {
        '2xs': ['10px', { lineHeight: '14px' }],
        xs:    ['12px', { lineHeight: '16px' }],
        sm:    ['13px', { lineHeight: '20px' }],
        base:  ['14px', { lineHeight: '22px' }],
        md:    ['15px', { lineHeight: '24px' }],
        lg:    ['16px', { lineHeight: '24px' }],
        xl:    ['18px', { lineHeight: '28px' }],
        '2xl': ['20px', { lineHeight: '28px' }],
        '3xl': ['24px', { lineHeight: '32px' }],
        '4xl': ['30px', { lineHeight: '36px' }],
      },
      spacing: {
        '0.5': '2px',
        '1':   '4px',
        '1.5': '6px',
        '2':   '8px',
        '2.5': '10px',
        '3':   '12px',
        '4':   '16px',
        '5':   '20px',
        '6':   '24px',
        '8':   '32px',
        '10':  '40px',
        '12':  '48px',
        '16':  '64px',
        '20':  '80px',
      },
      boxShadow: {
        sm:  'var(--shadow-sm)',
        md:  'var(--shadow-md)',
        lg:  'var(--shadow-lg)',
        xl:  'var(--shadow-xl)',
      },
    },
  },
  plugins: [require('tailwindcss-animate')],
};

export default config;
```

---

## 3. 타이포그래피

### 3-1. 폰트 계층

| 레벨 | 용도 | 크기 | 굵기 | 행간 |
|------|------|------|------|------|
| Display | 페이지 제목 (거의 미사용) | 30px | 700 | 36px |
| H1 | 페이지 헤더 | 24px | 600 | 32px |
| H2 | 섹션 제목 | 20px | 600 | 28px |
| H3 | 카드 제목 | 16px | 600 | 24px |
| H4 | 서브 섹션 | 14px | 600 | 22px |
| Body-LG | 주요 본문 | 15px | 400 | 24px |
| Body | 기본 본문 | 14px | 400 | 22px |
| Body-SM | 보조 텍스트 | 13px | 400 | 20px |
| Caption | 레이블, 힌트 | 12px | 400 | 16px |
| Overline | 카테고리 레이블 | 11px | 500 | 16px (자간 0.05em) |
| Mono | OCID, IP, 코드 | 13px | 400 | 20px |

### 3-2. 타이포그래피 컴포넌트

```typescript
// components/ui/typography.tsx
import { cn } from '@/lib/utils';
import { cva, type VariantProps } from 'class-variance-authority';

const textVariants = cva('', {
  variants: {
    variant: {
      h1:       'text-3xl font-semibold text-[var(--text-primary)] tracking-tight',
      h2:       'text-2xl font-semibold text-[var(--text-primary)]',
      h3:       'text-lg  font-semibold text-[var(--text-primary)]',
      h4:       'text-base font-semibold text-[var(--text-primary)]',
      body:     'text-base font-normal text-[var(--text-primary)]',
      bodyMd:   'text-md   font-normal text-[var(--text-primary)]',
      bodySm:   'text-sm   font-normal text-[var(--text-secondary)]',
      caption:  'text-xs   font-normal text-[var(--text-tertiary)]',
      overline: 'text-2xs  font-medium text-[var(--text-tertiary)] uppercase tracking-widest',
      mono:     'font-mono text-sm text-[var(--text-primary)]',
    },
  },
  defaultVariants: { variant: 'body' },
});

interface TextProps extends VariantProps<typeof textVariants> {
  as?: keyof JSX.IntrinsicElements;
  className?: string;
  children: React.ReactNode;
}

export function Text({ as: Tag = 'p', variant, className, children }: TextProps) {
  return <Tag className={cn(textVariants({ variant }), className)}>{children}</Tag>;
}
```

---

## 4. 컴포넌트 라이브러리 (shadcn/ui 기반)

### 4-1. 설치 컴포넌트 목록

```bash
# 기본 레이아웃
npx shadcn@latest add separator scroll-area resizable

# 폼 요소
npx shadcn@latest add button input textarea select
npx shadcn@latest add checkbox radio-group switch
npx shadcn@latest add form label

# 오버레이
npx shadcn@latest add dialog alert-dialog sheet
npx shadcn@latest add popover tooltip hover-card dropdown-menu context-menu

# 네비게이션
npx shadcn@latest add command navigation-menu tabs
npx shadcn@latest add breadcrumb pagination

# 데이터 표시
npx shadcn@latest add table badge avatar card
npx shadcn@latest add progress skeleton

# 피드백
npx shadcn@latest add alert toast  # Sonner로 대체
npx shadcn@latest add sonner

# 유틸리티
npx shadcn@latest add calendar date-picker
npx shadcn@latest add collapsible accordion
```

### 4-2. 커스텀 컴포넌트 계층

```
components/
├── ui/                     # shadcn/ui 기반 (수정 최소화)
│   ├── button.tsx
│   ├── input.tsx
│   ├── ...
│
├── shared/                 # 공통 비즈니스 컴포넌트
│   ├── ResourceTable/      # TanStack Table + Virtual
│   ├── StatusBadge/        # 리소스/알람 상태
│   ├── MetricChart/        # ECharts 래퍼
│   ├── SideSheet/          # 드릴다운 슬라이드 패널
│   ├── ConfirmDialog/      # 위험 작업 확인
│   ├── AsyncJobButton/     # 비동기 작업 버튼
│   ├── CommandPalette/     # 전역 검색
│   ├── EmptyState/         # 빈 상태
│   ├── ErrorBoundary/      # 에러 경계
│   └── LoadingSkeleton/    # 로딩 스켈레톤
│
├── layout/                 # 레이아웃 구조
│   ├── Sidebar/
│   ├── TopBar/
│   ├── Breadcrumb/
│   └── JobCenter/          # 우하단 비동기 작업 패널
│
├── features/               # 기능별 컴포넌트
│   ├── dashboard/
│   ├── tenants/
│   ├── compute/
│   ├── monitoring/
│   ├── incidents/
│   └── billing/
```

### 4-3. 버튼 변형 체계

```typescript
// components/ui/button.tsx 확장
const buttonVariants = cva(
  'inline-flex items-center justify-center gap-2 rounded-md text-sm font-medium ' +
  'transition-colors focus-visible:outline-none focus-visible:ring-2 ' +
  'focus-visible:ring-[var(--border-focus)] disabled:opacity-50 disabled:pointer-events-none',
  {
    variants: {
      variant: {
        // Primary — 주요 액션
        default:      'bg-[var(--brand-accent)] text-white hover:bg-sky-600',
        // Secondary — 보조 액션
        secondary:    'bg-[var(--surface-raised)] text-[var(--text-primary)] hover:bg-[var(--border-strong)]',
        // Outline — 테두리 버튼
        outline:      'border border-[var(--border)] bg-transparent hover:bg-[var(--surface-raised)]',
        // Ghost — 배경 없음
        ghost:        'hover:bg-[var(--surface-raised)] text-[var(--text-secondary)]',
        // Destructive — 삭제 등 위험 작업
        destructive:  'bg-[var(--status-error)] text-white hover:bg-red-600',
        // Warning — 주의 필요 작업 (중지/재시작)
        warning:      'bg-[var(--status-warning)] text-white hover:bg-amber-600',
        // Brand — OCI 브랜드 (랜딩, 온보딩)
        brand:        'bg-[var(--brand-primary)] text-white hover:bg-red-700',
        // Link
        link:         'text-[var(--brand-accent)] underline-offset-4 hover:underline p-0 h-auto',
      },
      size: {
        xs:   'h-6  px-2 text-xs rounded',
        sm:   'h-8  px-3 text-sm',
        md:   'h-9  px-4 text-sm',   /* default */
        lg:   'h-10 px-6 text-base',
        icon: 'h-9  w-9',
        'icon-sm': 'h-7 w-7',
      },
    },
    defaultVariants: { variant: 'default', size: 'md' },
  }
);
```

---

## 5. 간격(Spacing) 시스템

### 5-1. 기본 8px 그리드

```
t-shirt  |  px  | 사용 예
---------|------|-------------------------------
2xs      |  2   | 아이콘 내부 여백, 배지 상하 패딩
xs       |  4   | 인라인 요소 간격, 아이콘-텍스트
sm       |  8   | 버튼 내부, 입력 필드 내부
md       | 12   | 카드 내부 섹션 간격
lg       | 16   | 카드 패딩, 폼 그룹 간격
xl       | 20   | 카드 간격, 섹션 간격
2xl      | 24   | 페이지 패딩 (모바일)
3xl      | 32   | 페이지 패딩 (데스크톱)
4xl      | 40   | 주요 섹션 구분
5xl      | 48   | 페이지 헤더 하단 간격
```

### 5-2. 컴포넌트별 간격 기준

```typescript
// 카드
const cardSpacing = {
  padding: 'p-4 md:p-6',           // 16px / 24px
  gap:     'space-y-4',             // 16px 내부 섹션
  headerGap: 'mb-4',               // 16px 헤더-콘텐츠
};

// 테이블
const tableSpacing = {
  cellPaddingY: 'py-3',            // 12px (밀도: comfortable)
  cellPaddingX: 'px-4',            // 16px
  compactY:     'py-2',            // 8px  (밀도: compact)
  comfortableY: 'py-4',            // 16px (밀도: spacious)
};

// 폼
const formSpacing = {
  fieldGap:   'space-y-4',         // 16px 필드 간격
  sectionGap: 'space-y-6',         // 24px 섹션 간격
  labelGap:   'mb-1.5',            // 6px  레이블-입력
};

// 페이지
const pageSpacing = {
  horizontal: 'px-4 md:px-6 lg:px-8',
  vertical:   'py-6',
  headerGap:  'mb-6',
};
```

---

## 6. 아이콘 시스템 (Lucide React)

### 6-1. 아이콘 크기 기준

```typescript
// 일관된 크기 사용
const iconSizes = {
  xs:  12,  // 배지 내 아이콘
  sm:  14,  // 캡션/소형 버튼
  md:  16,  // 기본 버튼, 테이블 셀 (default)
  lg:  20,  // 네비게이션 메뉴
  xl:  24,  // 페이지 헤더
  '2xl': 32, // Empty State 일러스트 대체
  '3xl': 48, // 온보딩 스텝 아이콘
};
```

### 6-2. 도메인별 아이콘 매핑

```typescript
// lib/icons.ts
import {
  // 리소스 타입
  Server,          // Compute Instance
  Network,         // VCN / Network
  Database,        // Database
  HardDrive,       // Block Storage
  Package,         // Object Storage
  Globe,           // Region / 리전

  // 상태
  CheckCircle2,    // Running / Success
  XCircle,         // Error / Terminated
  AlertCircle,     // Warning
  Clock,           // Provisioning / Pending
  Pause,           // Stopped
  Loader2,         // Loading (spin)
  MinusCircle,     // Unknown

  // 심각도
  Siren,           // P1 Critical
  AlertTriangle,   // P2 High
  Info,            // P3 Medium / P4 Low

  // 액션
  Play,            // 시작
  Square,          // 중지
  RotateCcw,       // 재시작
  Trash2,          // 삭제
  Pencil,          // 편집
  Eye,             // 조회/상세
  Plus,            // 추가
  Download,        // 내보내기
  RefreshCw,       // 새로고침
  Copy,            // 복사
  ExternalLink,    // 외부 링크

  // 네비게이션
  LayoutDashboard, // 대시보드
  Users,           // 고객사/테넌트
  Cpu,             // Compute
  Activity,        // 모니터링
  Ticket,          // Incident
  Receipt,         // 비용
  Settings,        // 설정
  ChevronRight,    // 드릴다운 화살표
  ChevronDown,
  X,               // 닫기

  // 기타
  Search,          // 검색
  Bell,            // 알림
  Moon,            // 다크 모드
  Sun,             // 라이트 모드
  Star,            // 즐겨찾기
  Shield,          // 보안/MFA
  Key,             // API 키
  Terminal,        // 콘솔/CLI
  FileText,        // 보고서
  Zap,             // 자동화/빠른 작업
} from 'lucide-react';

export const ResourceIcon: Record<string, React.ComponentType> = {
  'compute.instance':    Server,
  'network.vcn':         Network,
  'database.autonomous': Database,
  'storage.block':       HardDrive,
  'storage.object':      Package,
};

export const SeverityIcon: Record<string, React.ComponentType> = {
  P1: Siren,
  P2: AlertTriangle,
  P3: AlertCircle,
  P4: Info,
};

export const StatusIcon: Record<string, React.ComponentType> = {
  RUNNING:      CheckCircle2,
  STOPPED:      Pause,
  TERMINATED:   XCircle,
  PROVISIONING: Loader2,
  ERROR:        XCircle,
  UNKNOWN:      MinusCircle,
};
```

### 6-3. 아이콘 컴포넌트 패턴

```typescript
// components/shared/StatusIcon.tsx
import { cn } from '@/lib/utils';
import { StatusIcon } from '@/lib/icons';

interface StatusIconProps {
  status: string;
  size?: number;
  className?: string;
}

const statusColorMap: Record<string, string> = {
  RUNNING:      'text-status-success',
  STOPPED:      'text-status-neutral',
  TERMINATED:   'text-status-error',
  PROVISIONING: 'text-status-info animate-spin',
  ERROR:        'text-status-error',
  UNKNOWN:      'text-status-neutral',
};

export function ResourceStatusIcon({ status, size = 16, className }: StatusIconProps) {
  const Icon = StatusIcon[status] ?? StatusIcon.UNKNOWN;
  return (
    <Icon
      size={size}
      className={cn(statusColorMap[status], className)}
      aria-label={`상태: ${status}`}
    />
  );
}
```

---

## 7. 모션 / 애니메이션 시스템

```typescript
// lib/animations.ts — Tailwind 기반 애니메이션 클래스

export const animations = {
  // 페이지 전환
  pageEnter:   'animate-in fade-in-0 slide-in-from-bottom-2 duration-300',
  pageExit:    'animate-out fade-out-0 slide-out-to-bottom-2 duration-200',

  // Side Sheet
  sheetEnter:  'animate-in slide-in-from-right duration-300 ease-out',
  sheetExit:   'animate-out slide-out-to-right duration-200 ease-in',

  // 모달
  modalEnter:  'animate-in fade-in-0 zoom-in-95 duration-200',
  modalExit:   'animate-out fade-out-0 zoom-out-95 duration-150',

  // Toast
  toastEnter:  'animate-in slide-in-from-bottom-4 duration-300',
  toastExit:   'animate-out slide-out-to-bottom-4 duration-200',

  // 스켈레톤
  skeleton:    'animate-pulse bg-gradient-to-r from-surface-raised via-border to-surface-raised',

  // 스피너
  spin:        'animate-spin',
};
```

---

## 8. 반응형 Breakpoint

```typescript
// lib/breakpoints.ts
export const breakpoints = {
  sm:  640,   // 모바일 가로
  md:  768,   // 태블릿
  lg:  1024,  // 노트북
  xl:  1280,  // 데스크톱
  '2xl': 1536, // 와이드
} as const;

// Tailwind 기준 레이아웃 전략
// sm:  모바일 — 알람 확인 + Incident 상태 업데이트만 지원
// md:  태블릿 — 주요 조회 기능 지원 (읽기 전용)
// lg+: 데스크톱 — 전체 기능 지원
```

---

## 9. 테마 전환 구현

```typescript
// components/ThemeProvider.tsx
'use client';

import { ThemeProvider as NextThemesProvider } from 'next-themes';
import type { ThemeProviderProps } from 'next-themes/dist/types';

export function ThemeProvider({ children, ...props }: ThemeProviderProps) {
  return (
    <NextThemesProvider
      attribute="class"
      defaultTheme="dark"        // MSP는 기본 다크 모드
      enableSystem={false}       // OS 설정 비연동 (전문가 환경)
      disableTransitionOnChange  // 깜빡임 방지
      {...props}
    >
      {children}
    </NextThemesProvider>
  );
}

// hooks/useTheme.ts
import { useTheme } from 'next-themes';
import { useCallback } from 'react';

export function useAppTheme() {
  const { theme, setTheme } = useTheme();

  const toggleTheme = useCallback(() => {
    setTheme(theme === 'dark' ? 'light' : 'dark');
  }, [theme, setTheme]);

  return { theme, toggleTheme, isDark: theme === 'dark' };
}
```
