# UI/UX 설계서 — Part 2: 전체 페이지 구조 및 라우팅

> OCI MSP 관리 플랫폼 | 작성일: 2026-03-21

---

## 1. Next.js App Router 파일 구조

```
apps/web/
├── src/
│   ├── app/
│   │   ├── layout.tsx                    # Root Layout (ThemeProvider, QueryProvider, FontConfig)
│   │   ├── globals.css                   # CSS 변수, 기본 스타일
│   │   │
│   │   ├── (auth)/                       # 인증 라우트 그룹 (레이아웃 없음)
│   │   │   ├── layout.tsx                # Auth Layout (중앙 정렬, 배경)
│   │   │   ├── login/
│   │   │   │   └── page.tsx              # /login
│   │   │   ├── mfa/
│   │   │   │   └── page.tsx              # /mfa (MFA 인증)
│   │   │   └── sso/
│   │   │       └── callback/
│   │   │           └── route.ts          # /sso/callback (SSO 처리)
│   │   │
│   │   ├── (dashboard)/                  # 대시보드 라우트 그룹
│   │   │   ├── layout.tsx                # Dashboard Layout (Sidebar + TopBar)
│   │   │   │
│   │   │   ├── page.tsx                  # / → 통합 대시보드
│   │   │   │
│   │   │   ├── tenants/
│   │   │   │   ├── page.tsx              # /tenants → 고객사 목록
│   │   │   │   ├── new/
│   │   │   │   │   └── page.tsx          # /tenants/new → 온보딩 위저드
│   │   │   │   └── [tenantId]/
│   │   │   │       ├── page.tsx          # /tenants/[id] → 고객사 상세
│   │   │   │       ├── resources/
│   │   │   │       │   └── page.tsx      # /tenants/[id]/resources
│   │   │   │       ├── monitoring/
│   │   │   │       │   └── page.tsx      # /tenants/[id]/monitoring
│   │   │   │       ├── billing/
│   │   │   │       │   └── page.tsx      # /tenants/[id]/billing
│   │   │   │       └── settings/
│   │   │   │           └── page.tsx      # /tenants/[id]/settings
│   │   │   │
│   │   │   ├── compute/
│   │   │   │   ├── layout.tsx            # Compute 하위 레이아웃 (서브 탭)
│   │   │   │   ├── instances/
│   │   │   │   │   ├── page.tsx          # /compute/instances
│   │   │   │   │   └── [instanceId]/
│   │   │   │   │       └── page.tsx      # /compute/instances/[id] → 상세 전체 페이지
│   │   │   │   ├── images/
│   │   │   │   │   └── page.tsx          # /compute/images
│   │   │   │   └── boot-volumes/
│   │   │   │       └── page.tsx          # /compute/boot-volumes
│   │   │   │
│   │   │   ├── network/
│   │   │   │   ├── vcns/
│   │   │   │   │   └── page.tsx          # /network/vcns
│   │   │   │   ├── subnets/
│   │   │   │   │   └── page.tsx          # /network/subnets
│   │   │   │   └── security-groups/
│   │   │   │       └── page.tsx          # /network/security-groups
│   │   │   │
│   │   │   ├── storage/
│   │   │   │   ├── block-volumes/
│   │   │   │   │   └── page.tsx          # /storage/block-volumes
│   │   │   │   └── object-storage/
│   │   │   │       └── page.tsx          # /storage/object-storage
│   │   │   │
│   │   │   ├── database/
│   │   │   │   ├── autonomous/
│   │   │   │   │   └── page.tsx          # /database/autonomous
│   │   │   │   └── db-systems/
│   │   │   │       └── page.tsx          # /database/db-systems
│   │   │   │
│   │   │   ├── monitoring/
│   │   │   │   ├── page.tsx              # /monitoring → 모니터링 대시보드
│   │   │   │   ├── alarms/
│   │   │   │   │   └── page.tsx          # /monitoring/alarms → 알람 규칙 목록
│   │   │   │   └── alarms/new/
│   │   │   │       └── page.tsx          # /monitoring/alarms/new → 규칙 생성 위저드
│   │   │   │
│   │   │   ├── incidents/
│   │   │   │   ├── page.tsx              # /incidents → Incident 목록
│   │   │   │   └── [incidentId]/
│   │   │   │       └── page.tsx          # /incidents/[id] → Incident 상세
│   │   │   │
│   │   │   ├── billing/
│   │   │   │   ├── page.tsx              # /billing → 비용 분석 대시보드
│   │   │   │   └── [tenantId]/
│   │   │   │       └── page.tsx          # /billing/[id] → 테넌시별 비용
│   │   │   │
│   │   │   ├── audit/
│   │   │   │   └── page.tsx              # /audit → 감사 로그
│   │   │   │
│   │   │   └── settings/
│   │   │       ├── page.tsx              # /settings → 설정 (리디렉션)
│   │   │       ├── users/
│   │   │       │   └── page.tsx          # /settings/users
│   │   │       ├── roles/
│   │   │       │   └── page.tsx          # /settings/roles
│   │   │       ├── notifications/
│   │   │       │   └── page.tsx          # /settings/notifications
│   │   │       └── api-keys/
│   │   │           └── page.tsx          # /settings/api-keys
│   │   │
│   │   └── api/                          # API Routes (BFF 최소화)
│   │       └── auth/
│   │           └── [...nextauth]/
│   │               └── route.ts
│   │
│   ├── components/
│   │   ├── ui/                           # shadcn/ui
│   │   ├── shared/                       # 공통 비즈니스 컴포넌트
│   │   ├── layout/                       # 레이아웃
│   │   └── features/                    # 기능별
│   │
│   ├── hooks/
│   │   ├── useOCIResources.ts
│   │   ├── useWebSocket.ts
│   │   ├── useCommandPalette.ts
│   │   ├── useKeyboardShortcuts.ts
│   │   └── useVirtualTable.ts
│   │
│   ├── stores/
│   │   ├── auth.store.ts
│   │   ├── tenant.store.ts
│   │   ├── notification.store.ts
│   │   └── ui.store.ts
│   │
│   ├── lib/
│   │   ├── api/                          # API 클라이언트
│   │   │   ├── client.ts                 # axios 인스턴스
│   │   │   ├── auth.api.ts
│   │   │   ├── tenants.api.ts
│   │   │   ├── compute.api.ts
│   │   │   ├── monitoring.api.ts
│   │   │   ├── incidents.api.ts
│   │   │   └── billing.api.ts
│   │   ├── query/
│   │   │   ├── keys.ts                   # 쿼리 키 팩토리
│   │   │   └── client.ts                 # QueryClient 설정
│   │   ├── utils.ts                      # cn, formatters
│   │   ├── icons.ts
│   │   └── constants.ts
│   │
│   ├── types/
│   │   ├── api.ts                        # API 응답 타입
│   │   ├── resources.ts
│   │   └── ui.ts
│   │
│   └── middleware.ts                     # Protected Route 처리
│
├── public/
├── tailwind.config.ts
├── next.config.ts
└── package.json
```

---

## 2. 레이아웃 계층

### 2-1. Root Layout

```typescript
// app/layout.tsx
import { Inter, JetBrains_Mono } from 'next/font/google';
import { ThemeProvider } from '@/components/ThemeProvider';
import { QueryProvider } from '@/components/QueryProvider';
import { Toaster } from '@/components/ui/sonner';
import { CommandPalette } from '@/components/shared/CommandPalette';
import './globals.css';

const inter = Inter({
  subsets: ['latin'],
  variable: '--font-sans',
  display: 'swap',
});

const jetbrainsMono = JetBrains_Mono({
  subsets: ['latin'],
  variable: '--font-mono',
  display: 'swap',
});

export const metadata = {
  title: {
    template: '%s | OCI MSP',
    default:  'OCI MSP 관리 플랫폼',
  },
  description: 'OCI 멀티 테넌시 통합 관리 플랫폼',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ko" suppressHydrationWarning>
      <body className={`${inter.variable} ${jetbrainsMono.variable} font-sans antialiased`}>
        <ThemeProvider>
          <QueryProvider>
            {children}
            <Toaster position="bottom-right" richColors />
            <CommandPalette />    {/* 전역 — [Cmd+K] */}
          </QueryProvider>
        </ThemeProvider>
      </body>
    </html>
  );
}
```

### 2-2. Dashboard Layout

```typescript
// app/(dashboard)/layout.tsx
import { Sidebar } from '@/components/layout/Sidebar';
import { TopBar } from '@/components/layout/TopBar';
import { JobCenter } from '@/components/layout/JobCenter';
import { WebSocketProvider } from '@/components/WebSocketProvider';

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  return (
    <WebSocketProvider>
      <div className="flex h-screen overflow-hidden bg-background">
        {/* 좌측 사이드바 240px → 72px → 56px */}
        <Sidebar />

        {/* 메인 영역 */}
        <div className="flex flex-1 flex-col overflow-hidden">
          {/* 상단 TopBar — 56px 고정 */}
          <TopBar />

          {/* 페이지 콘텐츠 */}
          <main
            className="flex-1 overflow-y-auto px-4 py-6 md:px-6 lg:px-8"
            id="main-content"
            tabIndex={-1}    // skip to main content 대상
          >
            {children}
          </main>
        </div>

        {/* 우하단 비동기 작업 센터 */}
        <JobCenter />
      </div>
    </WebSocketProvider>
  );
}
```

### 2-3. Auth Layout

```typescript
// app/(auth)/layout.tsx
export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen flex items-center justify-center bg-background">
      {/* 배경 패턴 (미묘한 그리드) */}
      <div
        className="absolute inset-0 opacity-[0.02]"
        style={{
          backgroundImage: `radial-gradient(circle at 1px 1px, var(--text-primary) 1px, transparent 0)`,
          backgroundSize:  '32px 32px',
        }}
      />
      <div className="relative z-10 w-full max-w-md">
        {children}
      </div>
    </div>
  );
}
```

---

## 3. URL 구조 설계

### 3-1. URL 설계 원칙

```
원칙 1. 리소스 중심 계층 구조
  /[리소스타입]/[리소스ID]/[서브리소스]

원칙 2. 필터/검색은 Query String
  /compute/instances?tenant=t1&region=ap-seoul-1&status=RUNNING

원칙 3. Side Sheet는 URL에 반영 (딥링크 지원)
  /compute/instances?detail=ocid1.instance.xxx
  → instances 목록 + Side Sheet 자동 오픈

원칙 4. 탭 상태는 Hash 또는 Query
  /tenants/t1#monitoring
  /tenants/t1?tab=monitoring
```

### 3-2. 주요 URL 패턴

| URL | 화면 | 비고 |
|-----|------|------|
| `/` | 통합 대시보드 | 루트 |
| `/tenants` | 고객사 목록 | |
| `/tenants/new` | 온보딩 위저드 | 5단계 |
| `/tenants/new?step=2` | 온보딩 2단계 | 새로고침 복원 |
| `/tenants/:id` | 고객사 상세 | |
| `/tenants/:id?tab=monitoring` | 고객사 모니터링 탭 | |
| `/compute/instances` | Compute 목록 | |
| `/compute/instances?tenant=:id&region=:region` | 필터링된 목록 | |
| `/compute/instances?detail=:ocid` | Side Sheet 열림 | 딥링크 |
| `/compute/instances/:ocid` | Compute 상세 전체 페이지 | Level 3 |
| `/monitoring` | 모니터링 대시보드 | |
| `/monitoring/alarms/new` | 알람 규칙 위저드 | |
| `/incidents` | Incident 목록 | |
| `/incidents/:id` | Incident 상세 + 타임라인 | |
| `/billing` | 비용 분석 | |
| `/billing?tenant=:id&period=2026-02` | 필터링된 비용 | |
| `/audit` | 감사 로그 | |
| `/settings/users` | 사용자 관리 | |

---

## 4. Protected Route 처리

### 4-1. Middleware (Edge Runtime)

```typescript
// middleware.ts
import { NextResponse, type NextRequest } from 'next/server';
import { verifyJWT } from '@/lib/jwt-edge';

const PUBLIC_PATHS = ['/login', '/mfa', '/sso', '/api/auth'];
const ADMIN_ONLY   = ['/settings/roles', '/settings/users'];

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // Public 경로 통과
  if (PUBLIC_PATHS.some(p => pathname.startsWith(p))) {
    return NextResponse.next();
  }

  // Access Token 검증
  const token = request.cookies.get('access_token')?.value;
  if (!token) {
    const loginUrl = new URL('/login', request.url);
    loginUrl.searchParams.set('from', pathname);  // 로그인 후 원래 위치로
    return NextResponse.redirect(loginUrl);
  }

  try {
    const payload = await verifyJWT(token);

    // 관리자 전용 경로 RBAC 확인
    if (ADMIN_ONLY.some(p => pathname.startsWith(p))) {
      if (!['SUPER_ADMIN', 'TENANT_ADMIN'].includes(payload.role)) {
        return NextResponse.redirect(new URL('/', request.url));
      }
    }

    // 테넌트 컨텍스트를 헤더로 전달 (서버 컴포넌트에서 사용)
    const response = NextResponse.next();
    response.headers.set('x-user-id',   payload.sub);
    response.headers.set('x-user-role', payload.role);
    response.headers.set('x-tenant-id', payload.tenantId ?? '');
    return response;

  } catch {
    // Token 만료 → Refresh 시도 → 실패 시 로그인
    const refreshToken = request.cookies.get('refresh_token')?.value;
    if (refreshToken) {
      // BFF refresh 엔드포인트 호출
      const refreshUrl = new URL('/api/auth/refresh', request.url);
      return NextResponse.redirect(refreshUrl);
    }
    return NextResponse.redirect(new URL('/login', request.url));
  }
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico).*)'],
};
```

### 4-2. 클라이언트 RBAC 가드

```typescript
// components/shared/PermissionGuard.tsx
'use client';

import { useAuthStore } from '@/stores/auth.store';
import { type Role } from '@/types/api';

interface PermissionGuardProps {
  roles:    Role[];          // 허용 역할 목록
  children: React.ReactNode;
  fallback?: React.ReactNode; // 권한 없을 때 대체 UI
}

export function PermissionGuard({ roles, children, fallback = null }: PermissionGuardProps) {
  const { user } = useAuthStore();

  if (!user || !roles.includes(user.role)) {
    return <>{fallback}</>;
  }

  return <>{children}</>;
}

// 사용 예:
// <PermissionGuard roles={['SUPER_ADMIN', 'TENANT_ADMIN']}>
//   <DeleteButton />
// </PermissionGuard>
```

### 4-3. 토큰 자동 갱신 (axios 인터셉터)

```typescript
// lib/api/client.ts
import axios, { AxiosError } from 'axios';
import { useAuthStore } from '@/stores/auth.store';

export const apiClient = axios.create({
  baseURL:         process.env.NEXT_PUBLIC_API_URL,
  timeout:         30_000,
  withCredentials: true,        // HttpOnly Cookie 자동 전송
});

// 요청 인터셉터 — 테넌트 컨텍스트 주입
apiClient.interceptors.request.use((config) => {
  const { selectedTenantId } = useTenantStore.getState();
  if (selectedTenantId) {
    config.headers['X-Tenant-ID'] = selectedTenantId;
  }
  return config;
});

// 응답 인터셉터 — 401 처리
let isRefreshing = false;
let waitQueue: Array<() => void> = [];

apiClient.interceptors.response.use(
  (res) => res,
  async (error: AxiosError) => {
    if (error.response?.status !== 401 || error.config?.url?.includes('/auth/refresh')) {
      return Promise.reject(error);
    }

    if (isRefreshing) {
      return new Promise((resolve) => {
        waitQueue.push(() => resolve(apiClient(error.config!)));
      });
    }

    isRefreshing = true;
    try {
      await apiClient.post('/auth/refresh');
      waitQueue.forEach(fn => fn());
      waitQueue = [];
      return apiClient(error.config!);
    } catch {
      useAuthStore.getState().logout();
      window.location.href = '/login';
      return Promise.reject(error);
    } finally {
      isRefreshing = false;
    }
  }
);
```

---

## 5. 레이아웃 와이어프레임

```
┌─────────────────────────────────────────────────────────────────────┐
│ Root Layout                                                         │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ Dashboard Layout                                             │   │
│  │  ┌──────────┐  ┌──────────────────────────────────────────┐ │   │
│  │  │          │  │ TopBar (h-14)                            │ │   │
│  │  │ Sidebar  │  │ [Logo] [Breadcrumb] [Search] [Bell] [Me] │ │   │
│  │  │ (w-60)   │  ├──────────────────────────────────────────┤ │   │
│  │  │          │  │ <main> — 스크롤 가능                      │ │   │
│  │  │ [Logo]   │  │                                          │ │   │
│  │  │          │  │   Page Content (page.tsx)                │ │   │
│  │  │ [메뉴]   │  │                                          │ │   │
│  │  │          │  │                                          │ │   │
│  │  │ [즐겨찾기] │  │                                          │ │   │
│  │  │          │  │                                          │ │   │
│  │  │ [설정]   │  └──────────────────────────────────────────┘ │   │
│  │  │ [프로필] │                                                │   │
│  │  └──────────┘                          ┌──────────────────┐ │   │
│  │                                         │ Job Center (우하단)│ │   │
│  │                                         └──────────────────┘ │   │
│  └─────────────────────────────────────────────────────────────┘   │
│  ┌─────────────┐  [Toaster]  [CommandPalette]                      │
│  │ Auth Layout │             (전역 오버레이)                          │
│  └─────────────┘                                                    │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 6. 사이드바 상세 설계

### 6-1. 3단계 사이드바 상태

```
[Expanded — 240px]           [Collapsed — 72px]     [Mini — 56px]
┌──────────────────────┐     ┌──────────┐            ┌────────┐
│ ⬡ OCI MSP        [<]│     │ ⬡    [>]│            │ ⬡     │
├──────────────────────┤     ├──────────┤            ├────────┤
│                      │     │          │            │        │
│ 전체 테넌시       [▾]│     │ [🏢]    │            │ [🏠]  │
│ ○ Acme Corp          │     │ [🏠]    │            │ [🏢]  │
│ ○ Beta Inc      [★] │     │ [💻]    │            │ [💻]  │
│ ○ Gamma Co           │     │ [📡]    │            │ [📡]  │
│                      │     │          │            │ [🎫]  │
│ ──────────────       │     │ ──────── │            │ [💰]  │
│                      │     │          │            │        │
│ [🏠] 대시보드        │     │ [🎫]    │            │ ──     │
│ [🏢] 고객사          │     │ [💰]    │            │ [⚙]  │
│ [💻] Compute         │     │          │            └────────┘
│   └ 인스턴스         │     │ ──────── │
│   └ 이미지           │     │          │
│ [🌐] Network         │     │ [⚙]    │
│ [💾] Storage         │     │ [👤]    │
│ [🗄] Database        │     └──────────┘
│ [📡] 모니터링        │
│ [🎫] Incidents       │
│ [💰] 비용 분석       │
│ [📋] 감사 로그       │
│ ──────────────       │
│ [⚙] 설정            │
│ [👤] 홍길동          │
│      Operator        │
└──────────────────────┘
```

### 6-2. 사이드바 컴포넌트

```typescript
// components/layout/Sidebar/index.tsx
'use client';

import { cn } from '@/lib/utils';
import { useUIStore } from '@/stores/ui.store';
import { useTenantStore } from '@/stores/tenant.store';
import { SidebarNav } from './SidebarNav';
import { TenantSwitcher } from './TenantSwitcher';
import { SidebarFooter } from './SidebarFooter';

const SIDEBAR_WIDTHS = {
  expanded:  'w-60',   // 240px
  collapsed: 'w-[72px]',
  mini:      'w-14',   // 56px
} as const;

export function Sidebar() {
  const { sidebarState } = useUIStore();

  return (
    <aside
      className={cn(
        'relative flex h-full flex-col border-r border-[var(--border)]',
        'bg-[var(--surface)] transition-all duration-300 ease-in-out',
        SIDEBAR_WIDTHS[sidebarState],
        'shrink-0'
      )}
      role="navigation"
      aria-label="메인 네비게이션"
    >
      {/* 로고 + 토글 */}
      <div className="flex h-14 items-center justify-between px-3 border-b border-[var(--border)]">
        {sidebarState === 'expanded' && (
          <span className="font-semibold text-lg text-[var(--brand-primary)]">OCI MSP</span>
        )}
        <SidebarToggleButton />
      </div>

      {/* 테넌트 스위처 */}
      <div className="px-2 py-3">
        <TenantSwitcher compact={sidebarState !== 'expanded'} />
      </div>

      {/* 네비게이션 메뉴 — 스크롤 가능 */}
      <div className="flex-1 overflow-y-auto py-2">
        <SidebarNav compact={sidebarState !== 'expanded'} />
      </div>

      {/* 하단 프로필/설정 */}
      <SidebarFooter compact={sidebarState !== 'expanded'} />
    </aside>
  );
}
```

---

## 7. TopBar 설계

```typescript
// components/layout/TopBar/index.tsx

/*
┌──────────────────────────────────────────────────────────────────────┐
│ [< Back] Compute / 인스턴스           [🔍 검색...] [🔔2] [🌙] [Me▾] │
└──────────────────────────────────────────────────────────────────────┘
*/

export function TopBar() {
  return (
    <header
      className="sticky top-0 z-40 flex h-14 items-center gap-4 border-b
                 border-[var(--border)] bg-[var(--surface)] px-4 md:px-6"
    >
      {/* 브레드크럼 */}
      <Breadcrumb className="flex-1" />

      {/* 검색 트리거 → Command Palette 오픈 */}
      <button
        onClick={() => useUIStore.getState().openCommandPalette()}
        className="hidden md:flex items-center gap-2 h-8 w-64 rounded-md border
                   border-[var(--border)] bg-[var(--surface-raised)] px-3 text-sm
                   text-[var(--text-tertiary)] hover:border-[var(--border-strong)]
                   transition-colors"
        aria-label="검색 열기 (Cmd+K)"
      >
        <Search size={14} />
        <span>검색...</span>
        <kbd className="ml-auto text-2xs border border-[var(--border)] rounded px-1">
          ⌘K
        </kbd>
      </button>

      {/* 알림 벨 */}
      <NotificationBell />

      {/* 다크/라이트 토글 */}
      <ThemeToggleButton />

      {/* 사용자 메뉴 */}
      <UserMenu />
    </header>
  );
}
```
