# UI/UX 설계서 — Part 4: 공통 컴포넌트 설계

> OCI MSP 관리 플랫폼 | 작성일: 2026-03-21

---

## 1. ResourceTable — 가상화 테이블

### 1-1. Props 인터페이스

```typescript
// components/shared/ResourceTable/types.ts
import { type ColumnDef, type RowSelectionState, type SortingState } from '@tanstack/react-table';

export interface ResourceTableProps<TData> {
  /** 테이블 데이터 */
  data:         TData[];
  /** 열 정의 (TanStack Table ColumnDef) */
  columns:      ColumnDef<TData>[];

  /** 가상화 설정 */
  rowHeight?:   number;      // 기본 52px
  overscan?:    number;      // 기본 20행
  /** 컨테이너 높이 (CSS 값) */
  containerHeight?: string;  // 기본 'calc(100vh - 280px)'

  /** 행 선택 */
  enableSelection?:  boolean;
  onSelectionChange?: (selected: TData[]) => void;

  /** 정렬 */
  enableSorting?:  boolean;
  defaultSorting?: SortingState;
  onSortingChange?: (sorting: SortingState) => void;

  /** 서버 사이드 페이지네이션 (선택적) */
  pageCount?:      number;
  pageIndex?:      number;
  pageSize?:       number;
  onPageChange?:   (page: number) => void;

  /** 행 이벤트 */
  onRowClick?:     (row: TData) => void;
  /** 행에 추가 CSS 클래스 */
  getRowClassName?: (row: TData) => string | undefined;

  /** 상태 */
  isLoading?:      boolean;
  isFetching?:     boolean;  // 백그라운드 갱신 표시
  emptyState?:     React.ReactNode;

  /** 열 가시성 토글 */
  enableColumnVisibility?: boolean;
  /** 테이블 밀도 */
  density?: 'compact' | 'comfortable' | 'spacious';

  className?:  string;
  'aria-label'?: string;
}
```

### 1-2. 전체 구현

```typescript
// components/shared/ResourceTable/index.tsx
'use client';

import { useRef, useState, useCallback } from 'react';
import {
  useReactTable,
  getCoreRowModel,
  getSortedRowModel,
  flexRender,
  type ColumnDef,
  type SortingState,
  type RowSelectionState,
} from '@tanstack/react-table';
import { useVirtualizer } from '@tanstack/react-virtual';
import { cn } from '@/lib/utils';
import { LoadingRows } from './LoadingRows';
import { TableColumnToggle } from './TableColumnToggle';
import { ChevronUp, ChevronDown, ChevronsUpDown } from 'lucide-react';

const DENSITY_MAP = {
  compact:     'py-1.5 px-3',
  comfortable: 'py-3 px-4',   // default
  spacious:    'py-4 px-4',
};

export function ResourceTable<TData>({
  data,
  columns,
  rowHeight = 52,
  overscan = 20,
  containerHeight = 'calc(100vh - 280px)',
  enableSelection = false,
  onSelectionChange,
  enableSorting = true,
  defaultSorting = [],
  onSortingChange,
  onRowClick,
  getRowClassName,
  isLoading = false,
  isFetching = false,
  emptyState,
  enableColumnVisibility = false,
  density = 'comfortable',
  className,
  'aria-label': ariaLabel,
}: ResourceTableProps<TData>) {
  const parentRef = useRef<HTMLDivElement>(null);
  const [sorting, setSorting]           = useState<SortingState>(defaultSorting);
  const [rowSelection, setRowSelection] = useState<RowSelectionState>({});
  const [columnVisibility, setColumnVisibility] = useState({});

  const table = useReactTable({
    data,
    columns,
    state: { sorting, rowSelection, columnVisibility },
    enableRowSelection:  enableSelection,
    onRowSelectionChange: (updater) => {
      setRowSelection(updater);
      if (onSelectionChange) {
        const next = typeof updater === 'function' ? updater(rowSelection) : updater;
        const selected = data.filter((_, i) => next[i]);
        onSelectionChange(selected);
      }
    },
    onSortingChange: (updater) => {
      setSorting(updater);
      onSortingChange?.(typeof updater === 'function' ? updater(sorting) : updater);
    },
    onColumnVisibilityChange: setColumnVisibility,
    getCoreRowModel:    getCoreRowModel(),
    getSortedRowModel:  getSortedRowModel(),
    manualPagination:   true,
  });

  const { rows } = table.getRowModel();

  const rowVirtualizer = useVirtualizer({
    count:           rows.length,
    getScrollElement: () => parentRef.current,
    estimateSize:    () => rowHeight,
    overscan,
  });

  const virtualItems = rowVirtualizer.getVirtualItems();

  return (
    <div className={cn('relative flex flex-col', className)}>
      {/* 열 가시성 토글 */}
      {enableColumnVisibility && (
        <div className="flex justify-end mb-2">
          <TableColumnToggle table={table} />
        </div>
      )}

      {/* 배경 갱신 표시 */}
      {isFetching && !isLoading && (
        <div className="absolute top-0 left-0 right-0 h-0.5 z-50">
          <div className="h-full bg-[var(--brand-accent)] animate-pulse" />
        </div>
      )}

      {/* 스크롤 컨테이너 */}
      <div
        ref={parentRef}
        className="overflow-auto rounded-lg border border-[var(--border)]"
        style={{ height: containerHeight }}
        role="region"
        aria-label={ariaLabel}
      >
        <table
          className="w-full border-collapse"
          role="grid"
          aria-rowcount={data.length}
        >
          {/* 헤더 — sticky */}
          <thead className="sticky top-0 z-10">
            {table.getHeaderGroups().map(headerGroup => (
              <tr key={headerGroup.id} className="bg-[var(--surface)]">
                {headerGroup.headers.map(header => (
                  <th
                    key={header.id}
                    className={cn(
                      'border-b border-[var(--border)] text-left text-xs font-medium',
                      'text-[var(--text-secondary)] uppercase tracking-wide',
                      'select-none whitespace-nowrap',
                      DENSITY_MAP[density],
                      header.column.getCanSort() && 'cursor-pointer hover:text-[var(--text-primary)]'
                    )}
                    style={{ width: header.getSize() }}
                    onClick={header.column.getToggleSortingHandler()}
                    aria-sort={
                      header.column.getIsSorted() === 'asc'  ? 'ascending'  :
                      header.column.getIsSorted() === 'desc' ? 'descending' : 'none'
                    }
                  >
                    <span className="flex items-center gap-1">
                      {flexRender(header.column.columnDef.header, header.getContext())}
                      {header.column.getCanSort() && (
                        <span className="text-[var(--text-tertiary)]">
                          {header.column.getIsSorted() === 'asc'  ? <ChevronUp size={12} /> :
                           header.column.getIsSorted() === 'desc' ? <ChevronDown size={12} /> :
                           <ChevronsUpDown size={12} />}
                        </span>
                      )}
                    </span>
                  </th>
                ))}
              </tr>
            ))}
          </thead>

          {/* 바디 — 가상화 */}
          <tbody
            style={{
              height:   `${rowVirtualizer.getTotalSize()}px`,
              position: 'relative',
            }}
          >
            {/* 로딩 스켈레톤 */}
            {isLoading ? (
              <LoadingRows columnCount={columns.length} rowCount={8} density={density} />
            ) : rows.length === 0 ? (
              <tr>
                <td colSpan={columns.length} className="py-16 text-center">
                  {emptyState ?? (
                    <div className="text-sm text-[var(--text-tertiary)]">데이터가 없습니다.</div>
                  )}
                </td>
              </tr>
            ) : (
              virtualItems.map(virtualRow => {
                const row = rows[virtualRow.index];
                return (
                  <tr
                    key={row.id}
                    data-index={virtualRow.index}
                    ref={rowVirtualizer.measureElement}
                    className={cn(
                      'border-b border-[var(--border)] transition-colors',
                      'hover:bg-[var(--surface-raised)]',
                      row.getIsSelected() && 'bg-[var(--status-info-bg)]',
                      onRowClick && 'cursor-pointer',
                      getRowClassName?.(row.original)
                    )}
                    style={{
                      position:  'absolute',
                      top:       virtualRow.start,
                      width:     '100%',
                      display:   'table-row',  // tr은 absolute 대신 transform 사용
                      transform: `translateY(${virtualRow.start}px)`,
                    }}
                    onClick={() => onRowClick?.(row.original)}
                    aria-selected={row.getIsSelected()}
                    role="row"
                  >
                    {row.getVisibleCells().map(cell => (
                      <td
                        key={cell.id}
                        className={cn('text-sm text-[var(--text-primary)]', DENSITY_MAP[density])}
                      >
                        {flexRender(cell.column.columnDef.cell, cell.getContext())}
                      </td>
                    ))}
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>

      {/* 행 수 표시 */}
      <div className="mt-2 text-xs text-[var(--text-tertiary)] px-1">
        총 {data.length.toLocaleString('ko-KR')}개
        {Object.keys(rowSelection).length > 0 && (
          <span className="ml-2 text-[var(--brand-accent)]">
            {Object.keys(rowSelection).length}개 선택됨
          </span>
        )}
      </div>
    </div>
  );
}
```

---

## 2. StatusBadge — 리소스/알람 상태

### 2-1. Props 인터페이스

```typescript
// components/shared/StatusBadge/types.ts
export type ResourceStatus =
  | 'RUNNING' | 'STOPPED' | 'STOPPING' | 'STARTING'
  | 'TERMINATED' | 'TERMINATING'
  | 'PROVISIONING' | 'UPDATING'
  | 'ERROR' | 'FAILED'
  | 'UNKNOWN';

export type AlarmStatus = 'ACTIVE' | 'ACKNOWLEDGED' | 'RESOLVED' | 'SILENCED';

export type SeverityLevel = 'P1' | 'P2' | 'P3' | 'P4';

export type IncidentStatus = 'OPEN' | 'ASSIGNED' | 'IN_PROGRESS' | 'RESOLVED' | 'CLOSED';

export type TenantStatus = 'HEALTHY' | 'DEGRADED' | 'CRITICAL' | 'ONBOARDING' | 'INACTIVE';

export type StatusBadgeStatus =
  | ResourceStatus | AlarmStatus | SeverityLevel | IncidentStatus | TenantStatus;

export interface StatusBadgeProps {
  status:    StatusBadgeStatus;
  /** 점(dot)만 표시, 텍스트 없음 */
  dotOnly?:  boolean;
  /** 크기 */
  size?:     'xs' | 'sm' | 'md';
  /** 커스텀 레이블 (기본: 상태명 한국어 변환) */
  label?:    string;
  /** 아이콘 표시 */
  showIcon?: boolean;
  className?: string;
}
```

### 2-2. 구현

```typescript
// components/shared/StatusBadge/index.tsx
import { cn } from '@/lib/utils';
import { CheckCircle2, XCircle, Pause, Loader2, AlertCircle, MinusCircle } from 'lucide-react';

type StatusConfig = {
  label:     string;
  color:     string;   // dot 색상
  bg:        string;   // 배지 배경
  text:      string;   // 텍스트 색상
  icon?:     React.ComponentType<{ size?: number; className?: string }>;
  animate?:  boolean;  // 아이콘 애니메이션
};

const STATUS_CONFIG: Record<string, StatusConfig> = {
  // Resource
  RUNNING:      { label: '실행 중',     color: 'bg-status-success', bg: 'bg-[var(--status-success-bg)]', text: 'text-status-success', icon: CheckCircle2 },
  STOPPED:      { label: '중지됨',      color: 'bg-status-neutral', bg: 'bg-[var(--surface-raised)]',    text: 'text-[var(--text-secondary)]', icon: Pause },
  STOPPING:     { label: '중지 중',     color: 'bg-status-warning', bg: 'bg-[var(--status-warning-bg)]', text: 'text-status-warning', icon: Loader2, animate: true },
  STARTING:     { label: '시작 중',     color: 'bg-status-info',    bg: 'bg-[var(--status-info-bg)]',    text: 'text-status-info',    icon: Loader2, animate: true },
  PROVISIONING: { label: '프로비저닝',  color: 'bg-status-info',    bg: 'bg-[var(--status-info-bg)]',    text: 'text-status-info',    icon: Loader2, animate: true },
  TERMINATED:   { label: '종료됨',      color: 'bg-status-neutral', bg: 'bg-[var(--surface-raised)]',    text: 'text-[var(--text-tertiary)]', icon: XCircle },
  ERROR:        { label: '오류',        color: 'bg-status-error',   bg: 'bg-[var(--status-error-bg)]',   text: 'text-status-error',   icon: XCircle },
  FAILED:       { label: '실패',        color: 'bg-status-error',   bg: 'bg-[var(--status-error-bg)]',   text: 'text-status-error',   icon: XCircle },
  UNKNOWN:      { label: '알 수 없음',  color: 'bg-status-neutral', bg: 'bg-[var(--surface-raised)]',    text: 'text-[var(--text-tertiary)]', icon: MinusCircle },

  // Alarm
  ACTIVE:       { label: '활성',        color: 'bg-status-error',   bg: 'bg-[var(--status-error-bg)]',   text: 'text-status-error' },
  ACKNOWLEDGED: { label: '확인됨',      color: 'bg-status-warning', bg: 'bg-[var(--status-warning-bg)]', text: 'text-status-warning' },
  RESOLVED:     { label: '해결됨',      color: 'bg-status-success', bg: 'bg-[var(--status-success-bg)]', text: 'text-status-success' },
  SILENCED:     { label: '무음',        color: 'bg-status-neutral', bg: 'bg-[var(--surface-raised)]',    text: 'text-[var(--text-tertiary)]' },

  // Severity
  P1:           { label: 'P1 Critical', color: 'bg-severity-p1',   bg: 'bg-[var(--status-error-bg)]',   text: 'text-severity-p1' },
  P2:           { label: 'P2 High',     color: 'bg-severity-p2',   bg: 'bg-orange-50 dark:bg-orange-950', text: 'text-severity-p2' },
  P3:           { label: 'P3 Medium',   color: 'bg-severity-p3',   bg: 'bg-[var(--status-warning-bg)]', text: 'text-severity-p3' },
  P4:           { label: 'P4 Low',      color: 'bg-severity-p4',   bg: 'bg-[var(--status-info-bg)]',    text: 'text-severity-p4' },

  // Incident
  OPEN:         { label: '오픈',        color: 'bg-status-error',   bg: 'bg-[var(--status-error-bg)]',   text: 'text-status-error' },
  ASSIGNED:     { label: '배정됨',      color: 'bg-status-warning', bg: 'bg-[var(--status-warning-bg)]', text: 'text-status-warning' },
  IN_PROGRESS:  { label: '조치 중',     color: 'bg-status-info',    bg: 'bg-[var(--status-info-bg)]',    text: 'text-status-info', icon: Loader2, animate: true },
  CLOSED:       { label: '종료됨',      color: 'bg-status-neutral', bg: 'bg-[var(--surface-raised)]',    text: 'text-[var(--text-tertiary)]' },

  // Tenant
  HEALTHY:      { label: '정상',        color: 'bg-status-success', bg: 'bg-[var(--status-success-bg)]', text: 'text-status-success' },
  DEGRADED:     { label: '저하됨',      color: 'bg-status-warning', bg: 'bg-[var(--status-warning-bg)]', text: 'text-status-warning' },
  CRITICAL:     { label: '위험',        color: 'bg-status-error',   bg: 'bg-[var(--status-error-bg)]',   text: 'text-status-error' },
  ONBOARDING:   { label: '온보딩 중',   color: 'bg-status-info',    bg: 'bg-[var(--status-info-bg)]',    text: 'text-status-info', icon: Loader2, animate: true },
  INACTIVE:     { label: '비활성',      color: 'bg-status-neutral', bg: 'bg-[var(--surface-raised)]',    text: 'text-[var(--text-tertiary)]' },
};

const SIZE_MAP = {
  xs: 'text-2xs px-1 py-0.5 gap-1',
  sm: 'text-xs  px-1.5 py-0.5 gap-1',
  md: 'text-xs  px-2 py-1 gap-1.5',   // default
};

const DOT_SIZE_MAP = {
  xs: 'h-1.5 w-1.5',
  sm: 'h-1.5 w-1.5',
  md: 'h-2 w-2',
};

export function StatusBadge({
  status, dotOnly = false, size = 'md', label, showIcon = false, className,
}: StatusBadgeProps) {
  const config = STATUS_CONFIG[status] ?? STATUS_CONFIG.UNKNOWN;
  const displayLabel = label ?? config.label;
  const Icon = config.icon;

  if (dotOnly) {
    return (
      <span
        className={cn('inline-block rounded-full', config.color, DOT_SIZE_MAP[size], className)}
        aria-label={displayLabel}
        title={displayLabel}
      />
    );
  }

  return (
    <span
      className={cn(
        'inline-flex items-center rounded-full font-medium',
        config.bg, config.text,
        SIZE_MAP[size],
        className
      )}
      aria-label={`상태: ${displayLabel}`}
    >
      {/* 점 또는 아이콘 */}
      {showIcon && Icon ? (
        <Icon size={size === 'md' ? 12 : 10} className={cn(config.animate && 'animate-spin')} />
      ) : (
        <span className={cn('inline-block rounded-full', config.color, DOT_SIZE_MAP[size])} />
      )}
      {displayLabel}
    </span>
  );
}

// 사용 예:
// <StatusBadge status="RUNNING" />                      → ● 실행 중
// <StatusBadge status="P1" size="sm" />                 → ● P1 Critical
// <StatusBadge status="PROVISIONING" showIcon />         → ⟳ 프로비저닝
// <StatusBadge status="RUNNING" dotOnly />              → ● (점만)
```

---

## 3. SideSheet — 드릴다운 슬라이드 패널

### 3-1. Props 인터페이스

```typescript
// components/shared/SideSheet/types.ts
export interface SideSheetProps {
  /** 패널 열림/닫힘 */
  open:          boolean;
  onClose:       () => void;

  /** 제목 영역 */
  title:         string;
  subtitle?:     string;
  /** 헤더 추가 콘텐츠 (배지, 상태 등) */
  headerSlot?:   React.ReactNode;
  /** 헤더 액션 버튼 */
  headerActions?: React.ReactNode;

  /** 탭 구성 (없으면 탭 없는 단순 패널) */
  tabs?: {
    id:      string;
    label:   string;
    content: React.ReactNode;
  }[];
  defaultTab?:   string;

  /** 단순 콘텐츠 (탭 없을 때) */
  children?:     React.ReactNode;

  /** 패널 너비 */
  width?:        'sm' | 'md' | 'lg' | 'xl';  // sm=320, md=480(default), lg=640, xl=800

  /** "전체 페이지로 보기" 링크 */
  fullPageHref?: string;

  /** 레벨 (1→2→3 드릴다운) */
  level?:        1 | 2 | 3;

  /** 오버레이 클릭 시 닫기 */
  closeOnOverlay?: boolean;  // default: true

  className?:    string;
}
```

### 3-2. 구현

```typescript
// components/shared/SideSheet/index.tsx
'use client';

import { useEffect, useRef, useState } from 'react';
import { cn } from '@/lib/utils';
import { X, ExternalLink, Maximize2 } from 'lucide-react';
import Link from 'next/link';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';

const WIDTH_MAP = {
  sm:  'w-80',    // 320px
  md:  'w-[480px]',
  lg:  'w-[640px]',
  xl:  'w-[800px]',
};

// z-index: Level 1=50, Level 2=60, Level 3=70
const LEVEL_Z = { 1: 'z-50', 2: 'z-60', 3: 'z-70' };

export function SideSheet({
  open, onClose,
  title, subtitle, headerSlot, headerActions,
  tabs, defaultTab,
  children,
  width = 'md',
  fullPageHref,
  level = 1,
  closeOnOverlay = true,
  className,
}: SideSheetProps) {
  const panelRef = useRef<HTMLDivElement>(null);
  const [activeTab, setActiveTab] = useState(defaultTab ?? tabs?.[0]?.id);

  // Esc 키 닫기
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && open) onClose();
    };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [open, onClose]);

  // Focus trap
  useEffect(() => {
    if (open) {
      panelRef.current?.focus();
    }
  }, [open]);

  // 스크롤 잠금
  useEffect(() => {
    if (open && level === 1) {
      document.body.style.overflow = 'hidden';
    }
    return () => {
      if (level === 1) document.body.style.overflow = '';
    };
  }, [open, level]);

  return (
    <>
      {/* 오버레이 */}
      {open && (
        <div
          className={cn(
            'fixed inset-0 bg-black/30 backdrop-blur-sm transition-opacity',
            LEVEL_Z[level],
            'opacity-100'
          )}
          onClick={closeOnOverlay ? onClose : undefined}
          aria-hidden="true"
        />
      )}

      {/* 패널 */}
      <div
        ref={panelRef}
        role="dialog"
        aria-label={title}
        aria-modal="true"
        tabIndex={-1}
        className={cn(
          'fixed right-0 top-0 h-full flex flex-col',
          'bg-[var(--surface)] border-l border-[var(--border)] shadow-xl',
          'transition-transform duration-300 ease-out',
          WIDTH_MAP[width],
          LEVEL_Z[level],
          open ? 'translate-x-0' : 'translate-x-full',
          className
        )}
      >
        {/* 헤더 */}
        <div className="flex-shrink-0 border-b border-[var(--border)] px-4 py-4">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2 flex-wrap">
                <h2 className="text-base font-semibold text-[var(--text-primary)] truncate">
                  {title}
                </h2>
                {headerSlot}
              </div>
              {subtitle && (
                <p className="mt-0.5 text-xs text-[var(--text-tertiary)] font-mono truncate">
                  {subtitle}
                </p>
              )}
            </div>

            <div className="flex items-center gap-1 shrink-0">
              {headerActions}
              {fullPageHref && (
                <Link
                  href={fullPageHref}
                  className="p-1.5 rounded-md hover:bg-[var(--surface-raised)] text-[var(--text-tertiary)]"
                  title="전체 페이지로 보기"
                  aria-label="전체 페이지로 보기"
                >
                  <Maximize2 size={14} />
                </Link>
              )}
              <button
                onClick={onClose}
                className="p-1.5 rounded-md hover:bg-[var(--surface-raised)] text-[var(--text-tertiary)]"
                aria-label="닫기"
              >
                <X size={16} />
              </button>
            </div>
          </div>
        </div>

        {/* 콘텐츠 */}
        <div className="flex-1 overflow-y-auto">
          {tabs ? (
            <Tabs value={activeTab} onValueChange={setActiveTab} className="h-full flex flex-col">
              {/* 탭 목록 */}
              <TabsList className="h-10 w-full justify-start rounded-none border-b border-[var(--border)] bg-transparent px-4 gap-0">
                {tabs.map(tab => (
                  <TabsTrigger
                    key={tab.id}
                    value={tab.id}
                    className={cn(
                      'rounded-none border-b-2 border-transparent px-3 py-2',
                      'text-sm font-medium text-[var(--text-secondary)]',
                      'data-[state=active]:border-[var(--brand-accent)]',
                      'data-[state=active]:text-[var(--text-primary)]',
                      'data-[state=active]:shadow-none',
                    )}
                  >
                    {tab.label}
                  </TabsTrigger>
                ))}
              </TabsList>

              {/* 탭 콘텐츠 */}
              {tabs.map(tab => (
                <TabsContent
                  key={tab.id}
                  value={tab.id}
                  className="flex-1 overflow-y-auto p-4 mt-0"
                >
                  {tab.content}
                </TabsContent>
              ))}
            </Tabs>
          ) : (
            <div className="p-4">{children}</div>
          )}
        </div>
      </div>
    </>
  );
}

// 사용 예:
// <SideSheet
//   open={isOpen}
//   onClose={() => setOpen(false)}
//   title="Acme Corporation"
//   subtitle="ocid1.tenancy.oc1..xxxxxxx"
//   headerSlot={<StatusBadge status="HEALTHY" size="sm" />}
//   headerActions={<Button variant="outline" size="sm">OCI 콘솔 ↗</Button>}
//   fullPageHref={`/tenants/${tenantId}`}
//   tabs={[
//     { id: 'overview', label: '개요', content: <TenantOverview /> },
//     { id: 'resources', label: '리소스', content: <TenantResources /> },
//   ]}
// />
```

---

## 4. ConfirmDialog — 위험 작업 확인

### 4-1. Props 인터페이스

```typescript
// components/shared/ConfirmDialog/types.ts
export type RiskLevel = 'LOW' | 'MED' | 'HIGH' | 'CRITICAL';

export interface ConfirmDialogProps {
  open:      boolean;
  onClose:   () => void;
  onConfirm: () => void | Promise<void>;

  /** 다이얼로그 제목 */
  title:       string;
  /** 설명 (영향도 등) */
  description: string;

  /** 위험도 — UX 패턴이 달라짐 */
  riskLevel: RiskLevel;

  /**
   * HIGH/CRITICAL: 이 텍스트를 입력해야 확인 버튼 활성화
   * (리소스 이름 또는 "삭제" 등)
   */
  confirmText?:    string;
  confirmPlaceholder?: string;

  /**
   * CRITICAL: 추가 2차 승인자 선택 (이중 승인)
   */
  requireSecondApprover?: boolean;
  approvers?: { id: string; name: string; email: string }[];

  /** 영향도 목록 */
  impacts?: string[];

  /** 확인 버튼 텍스트 */
  actionLabel?: string;
  /** 취소 버튼 텍스트 */
  cancelLabel?: string;

  /** 확인 처리 중 */
  isLoading?: boolean;
}
```

### 4-2. 구현

```typescript
// components/shared/ConfirmDialog/index.tsx
'use client';

import { useState } from 'react';
import {
  AlertDialog, AlertDialogContent, AlertDialogHeader,
  AlertDialogTitle, AlertDialogDescription, AlertDialogFooter,
} from '@/components/ui/alert-dialog';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { AlertTriangle, Siren, Info, AlertCircle } from 'lucide-react';

const RISK_CONFIG = {
  LOW: {
    icon:        Info,
    iconColor:   'text-status-info',
    iconBg:      'bg-[var(--status-info-bg)]',
    confirmVariant: 'default' as const,
    border:      'border-[var(--border)]',
  },
  MED: {
    icon:        AlertCircle,
    iconColor:   'text-status-warning',
    iconBg:      'bg-[var(--status-warning-bg)]',
    confirmVariant: 'warning' as const,
    border:      'border-[var(--status-warning)]',
  },
  HIGH: {
    icon:        AlertTriangle,
    iconColor:   'text-status-error',
    iconBg:      'bg-[var(--status-error-bg)]',
    confirmVariant: 'destructive' as const,
    border:      'border-[var(--status-error)]',
  },
  CRITICAL: {
    icon:        Siren,
    iconColor:   'text-status-error',
    iconBg:      'bg-[var(--status-error-bg)]',
    confirmVariant: 'destructive' as const,
    border:      'border-[var(--status-error)]',
  },
};

export function ConfirmDialog({
  open, onClose, onConfirm,
  title, description,
  riskLevel,
  confirmText, confirmPlaceholder,
  requireSecondApprover, approvers,
  impacts,
  actionLabel = '확인',
  cancelLabel = '취소',
  isLoading,
}: ConfirmDialogProps) {
  const [typedText, setTypedText]           = useState('');
  const [secondApprover, setSecondApprover] = useState('');
  const config = RISK_CONFIG[riskLevel];
  const Icon   = config.icon;

  // 확인 버튼 활성화 조건
  const isConfirmEnabled =
    (!confirmText || typedText === confirmText) &&
    (!requireSecondApprover || !!secondApprover) &&
    !isLoading;

  const handleConfirm = async () => {
    if (!isConfirmEnabled) return;
    await onConfirm();
    setTypedText('');
    setSecondApprover('');
  };

  return (
    <AlertDialog open={open} onOpenChange={open => !open && onClose()}>
      <AlertDialogContent
        className={cn('border-2', config.border, 'max-w-md')}
        aria-describedby="confirm-description"
      >
        <AlertDialogHeader>
          {/* 아이콘 + 제목 */}
          <div className="flex items-start gap-3">
            <div className={cn('p-2 rounded-lg shrink-0', config.iconBg)}>
              <Icon size={20} className={config.iconColor} />
            </div>
            <div>
              <AlertDialogTitle className="text-base font-semibold">
                {title}
              </AlertDialogTitle>
              <AlertDialogDescription id="confirm-description" className="mt-1 text-sm">
                {description}
              </AlertDialogDescription>
            </div>
          </div>
        </AlertDialogHeader>

        {/* 영향도 목록 (HIGH/CRITICAL) */}
        {impacts && impacts.length > 0 && (
          <div className="rounded-md bg-[var(--status-error-bg)] border border-[var(--status-error)] p-3">
            <p className="text-xs font-medium text-status-error mb-2">영향 범위:</p>
            <ul className="space-y-1">
              {impacts.map((impact, i) => (
                <li key={i} className="flex items-center gap-2 text-xs text-status-error">
                  <span className="text-status-error">•</span> {impact}
                </li>
              ))}
            </ul>
          </div>
        )}

        {/* 타이핑 확인 (HIGH/CRITICAL) */}
        {confirmText && (
          <div className="space-y-2">
            <p className="text-sm text-[var(--text-secondary)]">
              계속하려면{' '}
              <code className="bg-[var(--surface-raised)] px-1.5 py-0.5 rounded font-mono text-status-error">
                {confirmText}
              </code>
              을(를) 입력하세요.
            </p>
            <Input
              value={typedText}
              onChange={e => setTypedText(e.target.value)}
              placeholder={confirmPlaceholder ?? confirmText}
              className={cn(
                typedText && typedText !== confirmText
                  ? 'border-status-error focus-visible:ring-status-error'
                  : ''
              )}
              autoComplete="off"
              spellCheck={false}
              aria-label={`"${confirmText}" 입력`}
            />
          </div>
        )}

        {/* 2차 승인자 (CRITICAL) */}
        {requireSecondApprover && approvers && (
          <div className="space-y-2">
            <p className="text-sm font-medium text-[var(--text-primary)]">2차 승인자 선택 (필수)</p>
            <select
              value={secondApprover}
              onChange={e => setSecondApprover(e.target.value)}
              className="w-full h-9 rounded-md border border-[var(--border)] bg-[var(--surface)] px-3 text-sm"
              aria-label="2차 승인자 선택"
            >
              <option value="">승인자를 선택하세요...</option>
              {approvers.map(a => (
                <option key={a.id} value={a.id}>{a.name} ({a.email})</option>
              ))}
            </select>
          </div>
        )}

        <AlertDialogFooter className="flex gap-2">
          <Button
            variant="outline"
            onClick={onClose}
            disabled={isLoading}
          >
            {cancelLabel}
          </Button>
          <Button
            variant={config.confirmVariant}
            onClick={handleConfirm}
            disabled={!isConfirmEnabled}
            className={cn(isLoading && 'opacity-70 pointer-events-none')}
          >
            {isLoading ? (
              <><Loader2 size={14} className="animate-spin mr-2" /> 처리 중...</>
            ) : actionLabel}
          </Button>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}

// 사용 예:
// LOW — 인스턴스 중지
// <ConfirmDialog
//   riskLevel="LOW"
//   title="인스턴스를 중지하시겠습니까?"
//   description="web-prod-01을 중지합니다. 언제든지 다시 시작할 수 있습니다."
//   actionLabel="중지"
//   onConfirm={handleStop}
// />

// HIGH — 인스턴스 삭제
// <ConfirmDialog
//   riskLevel="HIGH"
//   title="인스턴스를 삭제하시겠습니까?"
//   description="이 작업은 되돌릴 수 없습니다."
//   confirmText="web-prod-01"
//   impacts={['Boot Volume 데이터 영구 삭제', '연결된 Secondary VNIC 분리']}
//   actionLabel="삭제"
//   onConfirm={handleDelete}
// />
```

---

## 5. AsyncJobButton — 비동기 작업 버튼

### 5-1. Props 인터페이스

```typescript
// components/shared/AsyncJobButton/types.ts
export interface AsyncJobButtonProps {
  /** 버튼 클릭 시 실행할 async 함수 — Job ID를 반환 */
  onTrigger:  () => Promise<{ jobId: string }>;

  /** 진행률 폴링 함수 (0~100, -1=실패) */
  onPoll?:    (jobId: string) => Promise<number>;

  /** 완료 콜백 */
  onComplete?: (jobId: string) => void;
  /** 실패 콜백 */
  onError?:    (jobId: string, error: string) => void;

  /** 버튼 표시 */
  children:    React.ReactNode;
  icon?:       React.ReactNode;

  /** 위험도 — ConfirmDialog 연동 */
  riskLevel?:  'LOW' | 'MED' | 'HIGH';
  confirmProps?: Partial<ConfirmDialogProps>;

  /** 실행 중 버튼 비활성화 */
  disableWhileRunning?: boolean;

  // 버튼 기본 props
  variant?:   string;
  size?:      string;
  disabled?:  boolean;
  className?: string;
}

export type JobButtonState = 'idle' | 'confirming' | 'running' | 'success' | 'error';
```

### 5-2. 구현

```typescript
// components/shared/AsyncJobButton/index.tsx
'use client';

import { useState, useCallback } from 'react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import { Loader2, CheckCircle2, XCircle } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useJobStore } from '@/stores/ui.store';

export function AsyncJobButton({
  onTrigger, onPoll, onComplete, onError,
  children, icon,
  riskLevel, confirmProps,
  disableWhileRunning = true,
  variant, size, disabled, className,
}: AsyncJobButtonProps) {
  const [state, setState] = useState<JobButtonState>('idle');
  const [progress, setProgress] = useState(0);
  const [confirmOpen, setConfirmOpen] = useState(false);
  const { addJob, updateJob } = useJobStore();

  const executeJob = useCallback(async () => {
    setState('running');
    setProgress(0);

    try {
      // 작업 트리거
      const { jobId } = await onTrigger();

      // 작업 센터에 등록
      addJob({ id: jobId, label: String(children), status: 'running', progress: 0 });

      // 진행률 폴링
      if (onPoll) {
        const pollInterval = setInterval(async () => {
          const p = await onPoll(jobId);
          if (p === -1) {
            clearInterval(pollInterval);
            setState('error');
            updateJob(jobId, { status: 'error', progress: 0 });
            toast.error(`작업 실패`, {
              description: `${String(children)} 작업이 실패했습니다.`,
              action: {
                label: '재시도',
                onClick: () => { setState('idle'); executeJob(); },
              },
            });
            onError?.(jobId, '작업 실패');
          } else if (p >= 100) {
            clearInterval(pollInterval);
            setState('success');
            setProgress(100);
            updateJob(jobId, { status: 'success', progress: 100 });
            toast.success(`${String(children)} 완료`);
            onComplete?.(jobId);
            // 2초 후 idle 복귀
            setTimeout(() => setState('idle'), 2000);
          } else {
            setProgress(p);
            updateJob(jobId, { progress: p });
          }
        }, 2000);
      } else {
        // 폴링 없으면 즉시 완료
        setState('success');
        updateJob(jobId, { status: 'success', progress: 100 });
        toast.success(`${String(children)} 완료`);
        onComplete?.(jobId);
        setTimeout(() => setState('idle'), 2000);
      }
    } catch (err) {
      setState('error');
      toast.error(`작업 실패`, {
        description: err instanceof Error ? err.message : '알 수 없는 오류',
        action: { label: '재시도', onClick: () => { setState('idle'); } },
      });
      onError?.('', err instanceof Error ? err.message : '알 수 없는 오류');
      setTimeout(() => setState('idle'), 3000);
    }
  }, [onTrigger, onPoll, onComplete, onError, children, addJob, updateJob]);

  const handleClick = () => {
    if (riskLevel && riskLevel !== 'LOW') {
      setConfirmOpen(true);
    } else if (riskLevel === 'LOW') {
      // LOW는 바로 실행 (or 단순 확인)
      setConfirmOpen(true);
    } else {
      executeJob();
    }
  };

  const isRunning = state === 'running';
  const isDisabled = disabled || (disableWhileRunning && isRunning);

  return (
    <>
      <Button
        variant={variant as any}
        size={size as any}
        disabled={isDisabled}
        onClick={handleClick}
        className={cn('relative overflow-hidden', className)}
        aria-label={isRunning ? `${String(children)} 진행 중 (${progress}%)` : undefined}
      >
        {/* 진행률 바 (배경) */}
        {isRunning && (
          <span
            className="absolute inset-0 bg-white/20 transition-all duration-300"
            style={{ width: `${progress}%` }}
            aria-hidden="true"
          />
        )}

        {/* 아이콘/스피너 */}
        <span className="relative flex items-center gap-2">
          {state === 'idle'    && icon}
          {state === 'running' && <Loader2 size={14} className="animate-spin" />}
          {state === 'success' && <CheckCircle2 size={14} />}
          {state === 'error'   && <XCircle size={14} />}
          {children}
          {isRunning && ` ${progress}%`}
        </span>
      </Button>

      {/* 위험 확인 다이얼로그 */}
      {riskLevel && (
        <ConfirmDialog
          open={confirmOpen}
          onClose={() => setConfirmOpen(false)}
          onConfirm={async () => {
            setConfirmOpen(false);
            await executeJob();
          }}
          riskLevel={riskLevel}
          title={`${String(children)} 확인`}
          description={`이 작업을 실행하시겠습니까?`}
          actionLabel={String(children)}
          {...confirmProps}
        />
      )}
    </>
  );
}

// 사용 예:
// <AsyncJobButton
//   onTrigger={() => stopInstance(instanceId)}
//   onPoll={jobId => pollJobProgress(jobId)}
//   onComplete={() => invalidateQueries(['instances'])}
//   riskLevel="LOW"
//   confirmProps={{ title: '인스턴스 중지', description: 'web-prod-01을 중지합니다.' }}
//   variant="warning"
//   icon={<Square size={14} />}
// >
//   중지
// </AsyncJobButton>
```

---

## 6. MetricBar — 인라인 진행률 바

```typescript
// components/shared/MetricBar/index.tsx
interface MetricBarProps {
  value:     number;    // 0~100
  size?:     'xs' | 'sm' | 'md';
  showValue?: boolean;
  className?: string;
}

const COLOR_MAP = (v: number) =>
  v >= 90 ? 'bg-status-error' :
  v >= 75 ? 'bg-status-warning' :
  'bg-status-success';

export function MetricBar({ value, size = 'sm', showValue = false, className }: MetricBarProps) {
  const height = { xs: 'h-1', sm: 'h-1.5', md: 'h-2' }[size];

  return (
    <div
      className={cn('flex items-center gap-2', className)}
      role="meter"
      aria-valuenow={value}
      aria-valuemin={0}
      aria-valuemax={100}
      aria-label={`${value}%`}
    >
      <div className={cn('flex-1 rounded-full bg-[var(--surface-overlay)]', height)}>
        <div
          className={cn('h-full rounded-full transition-all duration-300', COLOR_MAP(value))}
          style={{ width: `${Math.min(value, 100)}%` }}
        />
      </div>
      {showValue && (
        <span className="text-xs font-medium w-8 text-right">{value}%</span>
      )}
    </div>
  );
}
```
