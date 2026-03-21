# UI/UX 설계서 — Part 8: 빈 상태 / 에러 상태 설계

> OCI MSP 관리 플랫폼 | 작성일: 2026-03-21

---

## 1. 빈 상태 (Empty State)

### 1-1. 빈 상태 유형 분류

| 유형 | 설명 | 예시 | CTA |
|------|------|------|-----|
| First-time | 최초 진입, 데이터 없음 | 테넌시 0개 | 새 테넌시 추가 |
| Filter-empty | 필터 적용 후 결과 없음 | 검색어에 맞는 결과 없음 | 필터 초기화 |
| Permission-empty | 권한 부족 | VIEWER가 삭제 목록 조회 | 관리자 요청 |
| Not-found | 존재하지 않는 리소스 | 삭제된 Incident 접근 | 목록으로 돌아가기 |

### 1-2. Empty State 컴포넌트

```typescript
// components/shared/EmptyState/index.tsx
import { cn } from '@/lib/utils';

interface EmptyStateProps {
  /** 유형별 프리셋 */
  variant?:    'first-time' | 'no-results' | 'no-permission' | 'not-found';

  /** 커스텀 아이콘 (Lucide 또는 SVG) */
  icon?:        React.ReactNode;
  title:        string;
  description?: string;

  /** CTA 버튼 */
  action?:     {
    label:    string;
    onClick?: () => void;
    href?:    string;
    variant?: 'default' | 'outline';
    icon?:    React.ReactNode;
  };

  /** 보조 액션 (필터 초기화 등) */
  secondaryAction?: {
    label:    string;
    onClick?: () => void;
    href?:    string;
  };

  className?: string;
}

// 유형별 기본값
const VARIANT_DEFAULTS = {
  'first-time': {
    icon:        <ServerIcon />,
    title:       '아직 데이터가 없습니다',
    description: '시작하려면 아래 버튼을 클릭하세요.',
  },
  'no-results': {
    icon:        <SearchX size={40} />,
    title:       '검색 결과가 없습니다',
    description: '검색어나 필터 조건을 변경해 보세요.',
  },
  'no-permission': {
    icon:        <ShieldOff size={40} />,
    title:       '접근 권한이 없습니다',
    description: '이 기능을 사용하려면 관리자에게 권한을 요청하세요.',
  },
  'not-found': {
    icon:        <FileX size={40} />,
    title:       '리소스를 찾을 수 없습니다',
    description: '삭제되었거나 접근 권한이 없는 리소스입니다.',
  },
};

export function EmptyState({
  variant, icon, title, description,
  action, secondaryAction, className,
}: EmptyStateProps) {
  const defaults = variant ? VARIANT_DEFAULTS[variant] : {};
  const finalIcon        = icon        ?? defaults.icon;
  const finalTitle       = title       ?? defaults.title;
  const finalDescription = description ?? defaults.description;

  return (
    <div
      className={cn(
        'flex flex-col items-center justify-center py-16 px-8 text-center',
        className
      )}
      role="status"
      aria-label={finalTitle}
    >
      {/* 아이콘 */}
      {finalIcon && (
        <div className="mb-4 text-[var(--text-tertiary)] opacity-60">
          {finalIcon}
        </div>
      )}

      {/* 텍스트 */}
      <h3 className="text-base font-semibold text-[var(--text-primary)] mb-2">
        {finalTitle}
      </h3>
      {finalDescription && (
        <p className="text-sm text-[var(--text-secondary)] max-w-sm mb-6">
          {finalDescription}
        </p>
      )}

      {/* CTA */}
      {action && (
        <div className="flex flex-col sm:flex-row gap-3">
          {action.href ? (
            <Link href={action.href}>
              <Button variant={action.variant ?? 'default'}>
                {action.icon && <span>{action.icon}</span>}
                {action.label}
              </Button>
            </Link>
          ) : (
            <Button variant={action.variant ?? 'default'} onClick={action.onClick}>
              {action.icon && <span>{action.icon}</span>}
              {action.label}
            </Button>
          )}

          {secondaryAction && (
            <Button
              variant="ghost"
              onClick={secondaryAction.onClick}
            >
              {secondaryAction.label}
            </Button>
          )}
        </div>
      )}
    </div>
  );
}
```

### 1-3. 화면별 Empty State 예시

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 고객사 관리                                                 [+ 새 테넌시]   │
│                                                                             │
│                 ┌─────────────────────────────────────┐                    │
│                 │                                     │                    │
│                 │            🏢                       │                    │
│                 │   (흐린 건물 아이콘, 40px)           │                    │
│                 │                                     │                    │
│                 │   등록된 고객사가 없습니다           │                    │
│                 │                                     │                    │
│                 │   첫 번째 OCI 테넌시를 온보딩하여    │                    │
│                 │   시작하세요. 약 15분이 소요됩니다.  │                    │
│                 │                                     │                    │
│                 │       [+ 새 테넌시 온보딩]          │                    │
│                 │       [온보딩 가이드 보기 ↗]        │                    │
│                 │                                     │                    │
│                 └─────────────────────────────────────┘                    │
└─────────────────────────────────────────────────────────────────────────────┘

검색 결과 없음:
│                 ┌─────────────────────────────────────┐
│                 │            🔍✗                      │
│                 │                                     │
│                 │  "acme-xxxx" 검색 결과가 없습니다   │
│                 │                                     │
│                 │  검색어 또는 필터를 변경해 보세요.  │
│                 │                                     │
│                 │       [필터 초기화]                 │
│                 └─────────────────────────────────────┘

활성 Incident 없음 (긍정적):
│                 ┌─────────────────────────────────────┐
│                 │            ✅                       │
│                 │   (초록 체크 아이콘)                 │
│                 │                                     │
│                 │   활성 Incident가 없습니다!         │
│                 │   모든 시스템이 정상입니다.          │
│                 └─────────────────────────────────────┘
```

---

## 2. OCI 연결 실패 화면

### 2-1. 연결 상태 배너

```typescript
// components/shared/OCIConnectionBanner.tsx
interface OCIConnectionBannerProps {
  tenantId:    string;
  error?:      OCIConnectionError;
  onRetry:     () => void;
  onDismiss?:  () => void;
}

type OCIConnectionError =
  | { type: 'CREDENTIAL_EXPIRED'; message: string }
  | { type: 'RATE_LIMIT';         retryAfter: number }
  | { type: 'NETWORK_ERROR';      message: string }
  | { type: 'PERMISSION_DENIED';  missing: string[] };

export function OCIConnectionBanner({ tenantId, error, onRetry, onDismiss }: OCIConnectionBannerProps) {
  if (!error) return null;

  const configs = {
    CREDENTIAL_EXPIRED: {
      icon:        <ShieldAlert size={16} />,
      title:       'OCI Credential 만료',
      description: '이 테넌시의 API Key가 만료되었습니다. Credential을 갱신해주세요.',
      actionLabel: 'Credential 갱신',
      actionHref:  `/tenants/${tenantId}/settings?tab=credentials`,
      severity:    'error' as const,
    },
    RATE_LIMIT: {
      icon:        <Clock size={16} />,
      title:       'OCI API Rate Limit 초과',
      description: `${error.type === 'RATE_LIMIT' ? error.retryAfter : 0}초 후 자동으로 재시도합니다.`,
      actionLabel: '지금 재시도',
      severity:    'warning' as const,
    },
    NETWORK_ERROR: {
      icon:        <WifiOff size={16} />,
      title:       'OCI 네트워크 오류',
      description: 'OCI API에 연결할 수 없습니다. 네트워크 상태를 확인하세요.',
      actionLabel: '재시도',
      severity:    'error' as const,
    },
    PERMISSION_DENIED: {
      icon:        <ShieldOff size={16} />,
      title:       'OCI 권한 부족',
      description: `다음 권한이 없습니다: ${
        error.type === 'PERMISSION_DENIED' ? error.missing.join(', ') : ''
      }`,
      actionLabel: '권한 설정 가이드',
      severity:    'error' as const,
    },
  };

  const config = configs[error.type];
  const bgMap  = { error: 'bg-[var(--status-error-bg)]', warning: 'bg-[var(--status-warning-bg)]' };
  const borderMap = { error: 'border-[var(--status-error)]', warning: 'border-[var(--status-warning)]' };

  return (
    <div
      className={cn(
        'flex items-start gap-3 rounded-lg border px-4 py-3',
        bgMap[config.severity], borderMap[config.severity]
      )}
      role="alert"
    >
      <span className="text-status-error shrink-0 mt-0.5">{config.icon}</span>
      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium text-[var(--text-primary)]">{config.title}</p>
        <p className="text-xs text-[var(--text-secondary)] mt-0.5">{config.description}</p>
      </div>
      <div className="flex items-center gap-2 shrink-0">
        {config.actionHref ? (
          <Link href={config.actionHref} className="text-xs font-medium text-[var(--brand-accent)] hover:underline">
            {config.actionLabel}
          </Link>
        ) : (
          <Button variant="ghost" size="xs" onClick={onRetry}>
            {config.actionLabel}
          </Button>
        )}
        {onDismiss && (
          <Button variant="ghost" size="icon-sm" onClick={onDismiss} aria-label="닫기">
            <X size={12} />
          </Button>
        )}
      </div>
    </div>
  );
}
```

### 2-2. OCI 연결 실패 화면 (전체 페이지)

```
테넌시 상세 페이지에서 OCI 연결 불가 시:
┌─────────────────────────────────────────────────────────────────────────────┐
│ Acme Corporation                                                            │
│ ─────────────────────────────────────────────────────────────────────────── │
│                                                                             │
│ ┌─────────────────────────────────────────────────────────────────────┐   │
│ │ ⚠️  OCI 연결 실패                                                    │   │
│ │    Credential이 만료되었습니다. API Key를 갱신해주세요.              │   │
│ │                                            [Credential 갱신] [×]   │   │
│ └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│ ╔═══════════════════════════════════════════════════════════════════════╗  │
│ ║ 마지막 정상 데이터 (2시간 전 캐시)                               [?] ║  │
│ ╚═══════════════════════════════════════════════════════════════════════╝  │
│                                                                             │
│  [캐시된 데이터 표시 — 흐릿하게, "캐시됨" 워터마크]                       │
│  ┌──────────────────────────────────────────────────────────────────┐     │
│  │ (불투명도 60%, 배경에 "2h ago" 텍스트)                           │     │
│  │ 리소스 847개 | CPU 45% | MEM 62%                                 │     │
│  │ [실시간 아님]                                                     │     │
│  └──────────────────────────────────────────────────────────────────┘     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. API 오류 화면

### 3-1. Error Boundary

```typescript
// components/shared/ErrorBoundary/index.tsx
'use client';

import { Component, type ReactNode } from 'react';

interface ErrorBoundaryProps {
  children:   ReactNode;
  fallback?:  ReactNode;
  onError?:   (error: Error, errorInfo: React.ErrorInfo) => void;
}

interface ErrorBoundaryState {
  hasError: boolean;
  error?:   Error;
}

export class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false };
  }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    this.props.onError?.(error, errorInfo);
    // 에러 추적 (OpenTelemetry)
    console.error('[ErrorBoundary]', error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      return this.props.fallback ?? (
        <GlobalErrorFallback
          error={this.state.error}
          onReset={() => this.setState({ hasError: false })}
        />
      );
    }
    return this.props.children;
  }
}

// Next.js App Router error.tsx
// app/(dashboard)/error.tsx
'use client';

export default function DashboardError({
  error,
  reset,
}: {
  error:  Error & { digest?: string };
  reset:  () => void;
}) {
  useEffect(() => {
    // 에러 로깅
    console.error(error);
  }, [error]);

  const isNetworkError   = error.message.includes('fetch');
  const isPermissionError = error.message.includes('403');
  const isNotFound        = error.message.includes('404');

  return (
    <GlobalErrorFallback
      error={error}
      onReset={reset}
      type={
        isNetworkError    ? 'network'     :
        isPermissionError ? 'permission'  :
        isNotFound        ? 'not-found'   :
        'unknown'
      }
    />
  );
}
```

### 3-2. 오류 유형별 화면

```typescript
// components/shared/ErrorFallback/index.tsx
type ErrorType = 'network' | 'permission' | 'not-found' | 'rate-limit' | 'unknown';

interface GlobalErrorFallbackProps {
  error?:   Error;
  type?:    ErrorType;
  onReset?: () => void;
}

const ERROR_CONFIGS: Record<ErrorType, {
  icon:        React.ReactNode;
  title:       string;
  description: string;
  primaryAction: { label: string; action: 'reset' | 'back' | 'home' };
}> = {
  network: {
    icon:        <WifiOff size={40} />,
    title:       '연결 오류',
    description: '서버에 연결할 수 없습니다. 네트워크 상태를 확인하거나 잠시 후 다시 시도하세요.',
    primaryAction: { label: '다시 시도', action: 'reset' },
  },
  permission: {
    icon:        <ShieldOff size={40} />,
    title:       '접근 권한 없음',
    description: '이 페이지에 접근할 권한이 없습니다. 관리자에게 권한을 요청하세요.',
    primaryAction: { label: '대시보드로', action: 'home' },
  },
  'not-found': {
    icon:        <FileQuestion size={40} />,
    title:       '페이지를 찾을 수 없습니다',
    description: '요청하신 리소스가 존재하지 않거나 삭제되었습니다.',
    primaryAction: { label: '이전 페이지', action: 'back' },
  },
  'rate-limit': {
    icon:        <Hourglass size={40} />,
    title:       'API 요청 한도 초과',
    description: 'OCI API 요청 한도를 초과했습니다. 잠시 후 자동으로 재시도합니다.',
    primaryAction: { label: '다시 시도', action: 'reset' },
  },
  unknown: {
    icon:        <AlertTriangle size={40} />,
    title:       '오류가 발생했습니다',
    description: '예상치 못한 오류가 발생했습니다. 문제가 지속되면 지원팀에 문의하세요.',
    primaryAction: { label: '다시 시도', action: 'reset' },
  },
};

export function GlobalErrorFallback({ error, type = 'unknown', onReset }: GlobalErrorFallbackProps) {
  const router = useRouter();
  const config = ERROR_CONFIGS[type];

  const handlePrimaryAction = () => {
    switch (config.primaryAction.action) {
      case 'reset': onReset?.(); break;
      case 'back':  router.back(); break;
      case 'home':  router.push('/'); break;
    }
  };

  return (
    <div className="flex flex-col items-center justify-center min-h-[400px] py-16 px-8 text-center">
      <div className="text-[var(--text-tertiary)] opacity-50 mb-4">
        {config.icon}
      </div>

      <h2 className="text-xl font-semibold text-[var(--text-primary)] mb-2">
        {config.title}
      </h2>
      <p className="text-sm text-[var(--text-secondary)] max-w-md mb-6">
        {config.description}
      </p>

      <div className="flex gap-3">
        <Button onClick={handlePrimaryAction}>
          {config.primaryAction.label}
        </Button>
        <Button variant="outline" onClick={() => router.push('/')}>
          대시보드로
        </Button>
      </div>

      {/* 개발/디버그용 에러 상세 */}
      {process.env.NODE_ENV === 'development' && error && (
        <details className="mt-8 text-left max-w-lg">
          <summary className="text-xs text-[var(--text-tertiary)] cursor-pointer">
            오류 상세 (개발 모드)
          </summary>
          <pre className="mt-2 p-3 bg-[var(--surface-raised)] rounded text-xs font-mono overflow-auto">
            {error.message}
            {error.stack && '\n\n' + error.stack}
          </pre>
        </details>
      )}
    </div>
  );
}
```

---

## 4. 로딩 Skeleton UI

### 4-1. Skeleton 컴포넌트 패턴

```typescript
// components/shared/LoadingSkeleton/index.tsx
import { Skeleton } from '@/components/ui/skeleton';

// ─── KPI 카드 스켈레톤 ──────────────────────────────────────────
export function KPICardSkeleton() {
  return (
    <div className="h-full rounded-lg border border-[var(--border)] bg-[var(--surface)] p-4">
      <div className="flex items-center justify-between mb-3">
        <Skeleton className="h-4 w-24" />
        <Skeleton className="h-8 w-8 rounded-md" />
      </div>
      <Skeleton className="h-8 w-16 mb-1" />
      <Skeleton className="h-3 w-20" />
    </div>
  );
}

// ─── 테이블 행 스켈레톤 ────────────────────────────────────────
export function TableRowSkeleton({ columnCount, density }: { columnCount: number; density?: string }) {
  const heights = { compact: 'h-4', comfortable: 'h-4', spacious: 'h-5' };
  const paddings = { compact: 'py-2', comfortable: 'py-3', spacious: 'py-4' };

  return (
    <tr className={`border-b border-[var(--border)] ${paddings[density ?? 'comfortable']}`}>
      {Array.from({ length: columnCount }).map((_, i) => (
        <td key={i} className="px-4">
          <Skeleton
            className={cn(heights[density ?? 'comfortable'], i === 0 ? 'w-32' : i === columnCount - 1 ? 'w-16' : 'w-24')}
          />
        </td>
      ))}
    </tr>
  );
}

export function LoadingRows({ columnCount, rowCount = 8, density }: {
  columnCount: number;
  rowCount?:   number;
  density?:    string;
}) {
  return (
    <>
      {Array.from({ length: rowCount }).map((_, i) => (
        <TableRowSkeleton key={i} columnCount={columnCount} density={density} />
      ))}
    </>
  );
}

// ─── 차트 스켈레톤 ──────────────────────────────────────────────
export function ChartSkeleton({ height = 240 }: { height?: number }) {
  return (
    <div
      className="rounded-lg border border-[var(--border)] bg-[var(--surface)] p-4"
      style={{ height: height + 32 }}
    >
      <Skeleton className="h-4 w-32 mb-3" />
      <div className="flex items-end gap-2" style={{ height }}>
        {/* 가짜 바 차트 */}
        {[60, 40, 70, 55, 80, 45, 65, 50, 75, 58].map((h, i) => (
          <div key={i} className="flex-1 flex flex-col justify-end">
            <Skeleton
              className="w-full rounded-sm"
              style={{ height: `${h}%` }}
            />
          </div>
        ))}
      </div>
    </div>
  );
}

// ─── Side Sheet 스켈레톤 ───────────────────────────────────────
export function SideSheetSkeleton() {
  return (
    <div className="p-4 space-y-4">
      {/* 헤더 */}
      <div className="flex items-center gap-3">
        <Skeleton className="h-10 w-10 rounded-full" />
        <div className="space-y-1.5">
          <Skeleton className="h-4 w-32" />
          <Skeleton className="h-3 w-48" />
        </div>
      </div>

      {/* KPI 카드 2x2 */}
      <div className="grid grid-cols-2 gap-3">
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="rounded-lg border border-[var(--border)] p-3 space-y-2">
            <Skeleton className="h-3 w-16" />
            <Skeleton className="h-6 w-12" />
          </div>
        ))}
      </div>

      {/* 차트 */}
      <Skeleton className="h-3 w-24" />
      <Skeleton className="h-24 w-full rounded-lg" />

      {/* 목록 */}
      <Skeleton className="h-3 w-28" />
      {Array.from({ length: 3 }).map((_, i) => (
        <div key={i} className="flex items-center gap-3">
          <Skeleton className="h-5 w-5 rounded-full shrink-0" />
          <div className="flex-1 space-y-1">
            <Skeleton className="h-3 w-full" />
            <Skeleton className="h-3 w-24" />
          </div>
        </div>
      ))}
    </div>
  );
}

// ─── 페이지 헤더 스켈레톤 ─────────────────────────────────────
export function PageHeaderSkeleton() {
  return (
    <div className="flex items-center justify-between mb-6">
      <div className="space-y-2">
        <Skeleton className="h-6 w-32" />
        <Skeleton className="h-4 w-48" />
      </div>
      <Skeleton className="h-9 w-28 rounded-md" />
    </div>
  );
}
```

### 4-2. Suspense 활용

```typescript
// app/(dashboard)/tenants/page.tsx
import { Suspense } from 'react';
import { TenantList } from '@/components/features/tenants/TenantList';
import { TenantListSkeleton } from '@/components/features/tenants/TenantListSkeleton';

export default function TenantsPage() {
  return (
    <div>
      <PageHeader title="고객사 관리" action={<NewTenantButton />} />

      <Suspense fallback={<TenantListSkeleton />}>
        <TenantList />
      </Suspense>
    </div>
  );
}

// TanStack Query Suspense 모드
// components/features/tenants/TenantList.tsx
import { useSuspenseQuery } from '@tanstack/react-query';

export function TenantList() {
  // 로딩 중이면 자동으로 Suspense fallback 표시
  const { data: tenants } = useSuspenseQuery({
    queryKey: queryKeys.tenants.list(),
    queryFn:  fetchTenants,
  });

  if (tenants.length === 0) {
    return (
      <EmptyState
        variant="first-time"
        title="등록된 고객사가 없습니다"
        description="첫 번째 OCI 테넌시를 온보딩하여 시작하세요."
        action={{ label: '+ 새 테넌시 추가', href: '/tenants/new', icon: <Plus size={14} /> }}
      />
    );
  }

  return <ResourceTable data={tenants} columns={tenantColumns} />;
}
```

### 4-3. Streaming SSR with Skeleton

```typescript
// app/(dashboard)/page.tsx — 대시보드 스트리밍 렌더링
import { Suspense } from 'react';

export default function DashboardPage() {
  return (
    <div>
      {/* KPI 카드 — 즉시 렌더링 (가장 중요) */}
      <Suspense fallback={<KPICardsGridSkeleton />}>
        <KPICardsGrid />
      </Suspense>

      {/* 차트 — 약간 늦게 */}
      <Suspense fallback={<ChartsRowSkeleton />}>
        <ChartsRow />
      </Suspense>

      {/* 하단 위젯 — 마지막 */}
      <Suspense fallback={<BottomWidgetsSkeleton />}>
        <BottomWidgets />
      </Suspense>
    </div>
  );
}
```

---

## 5. 전체 로딩 상태 계층

```
우선순위    상태                    UI 패턴
─────────  ──────────────────────  ───────────────────────────
즉시(0ms)  페이지 전환             Skeleton (Suspense)
즉시(0ms)  Optimistic Update       즉시 반영 (Toast on error)
< 300ms    데이터 refetch          TopBar thin progress bar
< 1s       백그라운드 갱신          isFetching indicator (점멸)
> 1s       장기 비동기 작업        Job Center + WebSocket %
무한        OCI 연결 불가           Error Banner + Cached data
```

```typescript
// hooks/useLoadingIndicator.ts
// 300ms 이상 로딩 시에만 스피너 표시 (깜빡임 방지)
export function useDelayedLoading(isLoading: boolean, delay = 300) {
  const [showLoading, setShowLoading] = useState(false);

  useEffect(() => {
    if (!isLoading) {
      setShowLoading(false);
      return;
    }

    const timer = setTimeout(() => setShowLoading(true), delay);
    return () => clearTimeout(timer);
  }, [isLoading, delay]);

  return showLoading;
}
```
