# UI/UX 설계서 — Part 6: 상태 관리 설계

> OCI MSP 관리 플랫폼 | 작성일: 2026-03-21

---

## 1. TanStack Query 설계

### 1-1. 쿼리 키 팩토리

```typescript
// lib/query/keys.ts

/**
 * 쿼리 키 설계 원칙:
 * 1. 계층 구조로 세분화 (invalidate 범위 제어)
 * 2. 필터/파라미터는 마지막에 객체로
 * 3. 불변 ref equality를 위해 팩토리 패턴 사용
 */

export const queryKeys = {
  // ─── 인증 ───────────────────────────────────────────────
  auth: {
    all:  ['auth'] as const,
    me:   () => ['auth', 'me'] as const,
  },

  // ─── 테넌시 ─────────────────────────────────────────────
  tenants: {
    all:    ['tenants'] as const,
    lists:  () => ['tenants', 'list'] as const,
    list:   (filters?: TenantFilters) => ['tenants', 'list', filters] as const,
    detail: (id: string) => ['tenants', 'detail', id] as const,
    stats:  (id: string) => ['tenants', 'detail', id, 'stats'] as const,
    // 온보딩 임시 저장
    draft:  () => ['tenants', 'draft'] as const,
  },

  // ─── Compute ─────────────────────────────────────────────
  compute: {
    all:       ['compute'] as const,
    instances: (filters?: InstanceFilters) => ['compute', 'instances', filters] as const,
    instance:  (id: string) => ['compute', 'instance', id] as const,
    metrics:   (id: string, range: TimeRange) => ['compute', 'instance', id, 'metrics', range] as const,
    images:    (filters?: ImageFilters) => ['compute', 'images', filters] as const,
  },

  // ─── Network ─────────────────────────────────────────────
  network: {
    vcns:     (filters?: NetworkFilters) => ['network', 'vcns', filters] as const,
    vcn:      (id: string) => ['network', 'vcn', id] as const,
    subnets:  (vcnId?: string) => ['network', 'subnets', vcnId] as const,
  },

  // ─── 모니터링 ────────────────────────────────────────────
  monitoring: {
    all:        ['monitoring'] as const,
    alarms:     (filters?: AlarmFilters) => ['monitoring', 'alarms', filters] as const,
    alarm:      (id: string) => ['monitoring', 'alarm', id] as const,
    alarmRules: (filters?: AlarmRuleFilters) => ['monitoring', 'alarm-rules', filters] as const,
    metrics:    (tenantId: string, query: MetricQuery) => ['monitoring', 'metrics', tenantId, query] as const,
    summary:    () => ['monitoring', 'summary'] as const,
  },

  // ─── Incident ────────────────────────────────────────────
  incidents: {
    all:      ['incidents'] as const,
    list:     (filters?: IncidentFilters) => ['incidents', 'list', filters] as const,
    detail:   (id: string) => ['incidents', 'detail', id] as const,
    timeline: (id: string) => ['incidents', 'detail', id, 'timeline'] as const,
    stats:    () => ['incidents', 'stats'] as const,
  },

  // ─── 비용 ───────────────────────────────────────────────
  billing: {
    all:       ['billing'] as const,
    summary:   (period: string) => ['billing', 'summary', period] as const,
    byTenant:  (tenantId: string, period: string) => ['billing', 'tenant', tenantId, period] as const,
    trend:     (months: number) => ['billing', 'trend', months] as const,
    detail:    (filters: BillingFilters) => ['billing', 'detail', filters] as const,
  },

  // ─── 작업 ───────────────────────────────────────────────
  jobs: {
    all:    ['jobs'] as const,
    list:   () => ['jobs', 'list'] as const,
    detail: (id: string) => ['jobs', 'detail', id] as const,
  },

  // ─── 설정 ───────────────────────────────────────────────
  settings: {
    users:   () => ['settings', 'users'] as const,
    roles:   () => ['settings', 'roles'] as const,
    apiKeys: () => ['settings', 'api-keys'] as const,
  },
} as const;

// invalidate 헬퍼
export const invalidateHelpers = {
  // 인스턴스 변경 시 (시작/중지/재시작)
  afterInstanceAction: (qc: QueryClient, tenantId?: string) => {
    qc.invalidateQueries({ queryKey: queryKeys.compute.all });
    qc.invalidateQueries({ queryKey: queryKeys.monitoring.all });
    if (tenantId) {
      qc.invalidateQueries({ queryKey: queryKeys.tenants.stats(tenantId) });
    }
  },

  // 알람 상태 변경 시
  afterAlarmAction: (qc: QueryClient) => {
    qc.invalidateQueries({ queryKey: queryKeys.monitoring.alarms() });
    qc.invalidateQueries({ queryKey: queryKeys.monitoring.summary() });
    qc.invalidateQueries({ queryKey: queryKeys.incidents.stats() });
  },

  // Incident 변경 시
  afterIncidentAction: (qc: QueryClient, incidentId: string) => {
    qc.invalidateQueries({ queryKey: queryKeys.incidents.list() });
    qc.invalidateQueries({ queryKey: queryKeys.incidents.detail(incidentId) });
    qc.invalidateQueries({ queryKey: queryKeys.incidents.stats() });
  },
};
```

### 1-2. QueryClient 설정

```typescript
// lib/query/client.ts
import { QueryClient } from '@tanstack/react-query';

export function createQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: {
        // 전역 기본 캐시 설정
        staleTime:       30_000,     // 30초 — 데이터 신선도 기준
        gcTime:          5 * 60_000, // 5분 — 메모리 보존
        retry:           2,
        retryDelay:      (attempt) => Math.min(1000 * 2 ** attempt, 30_000),
        refetchOnWindowFocus: false, // 탭 포커스 시 자동 갱신 끔 (MSP 환경)
        refetchOnMount:  true,

        // 네트워크 오류 시 조용히 처리 (toast는 각 컴포넌트에서)
        throwOnError:    false,
      },
      mutations: {
        retry: false,   // mutation은 자동 재시도 안 함
      },
    },
  });
}

// 데이터 타입별 캐시 정책
export const CACHE_POLICIES = {
  // 실시간성 높은 데이터 — stale 즉시 (WebSocket 업데이트)
  realtime: { staleTime: 0, gcTime: 30_000 },

  // 중간 — 30초 (대부분의 리소스 목록)
  medium:   { staleTime: 30_000, gcTime: 5 * 60_000 },

  // 느린 변경 — 5분 (테넌시 목록, 사용자 설정)
  slow:     { staleTime: 5 * 60_000, gcTime: 30 * 60_000 },

  // 정적 — 1시간 (리전 목록, Shape 목록)
  static:   { staleTime: 60 * 60_000, gcTime: 24 * 60 * 60_000 },
} as const;
```

### 1-3. Optimistic Update 패턴

```typescript
// 패턴 1: Incident 담당자 즉시 배정
export function useAssignIncident() {
  const qc = useQueryClient();

  return useMutation({
    mutationFn: ({ incidentId, assigneeId }: AssignPayload) =>
      apiClient.patch(`/incidents/${incidentId}/assign`, { assigneeId }),

    onMutate: async ({ incidentId, assigneeId }) => {
      // 진행 중인 refetch 취소
      await qc.cancelQueries({ queryKey: queryKeys.incidents.list() });
      await qc.cancelQueries({ queryKey: queryKeys.incidents.detail(incidentId) });

      // 현재 데이터 스냅샷
      const prevList   = qc.getQueryData(queryKeys.incidents.list());
      const prevDetail = qc.getQueryData(queryKeys.incidents.detail(incidentId));

      // Optimistic Update
      const patchFn = (incident: Incident) =>
        incident.id === incidentId ? { ...incident, assigneeId, status: 'ASSIGNED' as const } : incident;

      qc.setQueryData(queryKeys.incidents.list(), (old: Incident[] | undefined) => old?.map(patchFn));
      qc.setQueryData(queryKeys.incidents.detail(incidentId), (old: Incident | undefined) =>
        old ? patchFn(old) : undefined
      );

      return { prevList, prevDetail };
    },

    onSuccess: (_, { incidentId }) => {
      toast.success('담당자가 배정되었습니다.');
      // 타임라인 갱신
      qc.invalidateQueries({ queryKey: queryKeys.incidents.timeline(incidentId) });
    },

    onError: (err, { incidentId }, context) => {
      // 롤백
      qc.setQueryData(queryKeys.incidents.list(), context?.prevList);
      qc.setQueryData(queryKeys.incidents.detail(incidentId), context?.prevDetail);
      toast.error('담당자 배정 실패', { description: err instanceof Error ? err.message : '서버 오류' });
    },

    onSettled: (_, __, { incidentId }) => {
      // 최종 서버 데이터로 동기화
      qc.invalidateQueries({ queryKey: queryKeys.incidents.list() });
      qc.invalidateQueries({ queryKey: queryKeys.incidents.detail(incidentId) });
    },
  });
}
```

---

## 2. Zustand Store 구조

### 2-1. Auth Store

```typescript
// stores/auth.store.ts
import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import { immer } from 'zustand/middleware/immer';

interface User {
  id:       string;
  name:     string;
  email:    string;
  role:     'SUPER_ADMIN' | 'TENANT_ADMIN' | 'OPERATOR' | 'VIEWER';
  avatar?:  string;
}

interface AuthState {
  user:         User | null;
  isLoading:    boolean;
  permissions:  Set<string>;  // 'compute:write', 'incidents:delete' 등

  // 액션
  setUser:    (user: User | null) => void;
  logout:     () => void;
  hasPermission: (permission: string) => boolean;
}

export const useAuthStore = create<AuthState>()(
  persist(
    immer((set, get) => ({
      user:        null,
      isLoading:   false,
      permissions: new Set(),

      setUser: (user) => set(state => {
        state.user = user;
        // 역할 기반 권한 계산
        state.permissions = user ? computePermissions(user.role) : new Set();
      }),

      logout: () => set(state => {
        state.user        = null;
        state.permissions = new Set();
      }),

      hasPermission: (permission) => get().permissions.has(permission),
    })),
    {
      name:    'auth-store',
      storage: createJSONStorage(() => sessionStorage),  // 탭 닫으면 초기화
      partialize: (state) => ({ user: state.user }),     // permissions는 메모리만
    }
  )
);

function computePermissions(role: User['role']): Set<string> {
  const base = ['resources:read', 'monitoring:read', 'incidents:read', 'billing:read'];

  const rolePerms: Record<User['role'], string[]> = {
    VIEWER:       base,
    OPERATOR:     [...base, 'resources:write', 'incidents:write', 'monitoring:write'],
    TENANT_ADMIN: [...base, 'resources:write', 'incidents:write', 'incidents:delete',
                   'monitoring:write', 'tenants:write', 'settings:read'],
    SUPER_ADMIN:  [...base, 'resources:write', 'resources:delete', 'incidents:write',
                   'incidents:delete', 'monitoring:write', 'tenants:write', 'tenants:delete',
                   'settings:write', 'users:write'],
  };

  return new Set(rolePerms[role]);
}
```

### 2-2. Tenant Store

```typescript
// stores/tenant.store.ts
import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import { immer } from 'zustand/middleware/immer';

interface TenantSummary {
  id:          string;
  displayName: string;
  status:      string;
  homeRegion:  string;
  isFavorite:  boolean;
}

interface TenantState {
  // 현재 선택된 테넌시 (필터 컨텍스트)
  selectedTenantId: string | null;  // null = 전체

  // 즐겨찾기 (사이드바 상단 고정)
  favoriteTenantIds: string[];

  // 최근 방문 테넌시
  recentTenantIds: string[];

  // 액션
  selectTenant:       (id: string | null) => void;
  toggleFavorite:     (id: string) => void;
  addRecentTenant:    (id: string) => void;
}

export const useTenantStore = create<TenantState>()(
  persist(
    immer((set) => ({
      selectedTenantId:  null,
      favoriteTenantIds: [],
      recentTenantIds:   [],

      selectTenant: (id) => set(state => {
        state.selectedTenantId = id;
        // 최근 방문 업데이트
        if (id) {
          state.recentTenantIds = [
            id,
            ...state.recentTenantIds.filter(r => r !== id),
          ].slice(0, 5);
        }
      }),

      toggleFavorite: (id) => set(state => {
        const idx = state.favoriteTenantIds.indexOf(id);
        if (idx === -1) {
          // 최대 5개 즐겨찾기
          if (state.favoriteTenantIds.length < 5) {
            state.favoriteTenantIds.push(id);
          }
        } else {
          state.favoriteTenantIds.splice(idx, 1);
        }
      }),

      addRecentTenant: (id) => set(state => {
        state.recentTenantIds = [
          id,
          ...state.recentTenantIds.filter(r => r !== id),
        ].slice(0, 5);
      }),
    })),
    {
      name:    'tenant-store',
      storage: createJSONStorage(() => localStorage),
    }
  )
);
```

### 2-3. Notification Store

```typescript
// stores/notification.store.ts
import { create } from 'zustand';
import { immer } from 'zustand/middleware/immer';

interface Notification {
  id:         string;
  type:       'alarm' | 'incident' | 'job' | 'system';
  title:      string;
  message:    string;
  severity?:  'P1' | 'P2' | 'P3' | 'P4';
  href?:      string;
  read:       boolean;
  createdAt:  string;
}

interface NotificationState {
  notifications:   Notification[];
  unreadCount:     number;

  // 액션
  addNotification:    (notification: Omit<Notification, 'read'>) => void;
  markRead:           (id: string) => void;
  markAllRead:        () => void;
  removeNotification: (id: string) => void;
  clearAll:           () => void;
}

export const useNotificationStore = create<NotificationState>()(
  immer((set) => ({
    notifications: [],
    unreadCount:   0,

    addNotification: (notification) => set(state => {
      const newNotif: Notification = { ...notification, read: false };
      state.notifications.unshift(newNotif);
      state.notifications = state.notifications.slice(0, 100); // 최대 100개
      state.unreadCount++;
    }),

    markRead: (id) => set(state => {
      const notif = state.notifications.find(n => n.id === id);
      if (notif && !notif.read) {
        notif.read = true;
        state.unreadCount = Math.max(0, state.unreadCount - 1);
      }
    }),

    markAllRead: () => set(state => {
      state.notifications.forEach(n => n.read = true);
      state.unreadCount = 0;
    }),

    removeNotification: (id) => set(state => {
      const idx = state.notifications.findIndex(n => n.id === id);
      if (idx !== -1) {
        if (!state.notifications[idx].read) state.unreadCount--;
        state.notifications.splice(idx, 1);
      }
    }),

    clearAll: () => set(state => {
      state.notifications = [];
      state.unreadCount   = 0;
    }),
  }))
);
```

### 2-4. UI Store

```typescript
// stores/ui.store.ts
import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import { immer } from 'zustand/middleware/immer';

type SidebarState = 'expanded' | 'collapsed' | 'mini';

interface Job {
  id:       string;
  label:    string;
  status:   'running' | 'success' | 'error';
  progress: number;
  retry?:   () => void;
}

interface UIState {
  // 사이드바
  sidebarState: SidebarState;
  setSidebarState: (state: SidebarState) => void;
  toggleSidebar:   () => void;

  // Command Palette
  commandPaletteOpen: boolean;
  setCommandPaletteOpen: (open: boolean) => void;

  // Side Sheet (드릴다운)
  sideSheetStack: string[];   // 리소스 ID 스택 (Level 1→2→3)
  pushSideSheet:  (id: string) => void;
  popSideSheet:   () => void;
  clearSideSheet: () => void;

  // 비동기 작업 센터
  jobs:       Job[];
  addJob:     (job: Omit<Job, 'retry'> & { retry?: () => void }) => void;
  updateJob:  (id: string, patch: Partial<Job>) => void;
  removeJob:  (id: string) => void;

  // 테이블 밀도
  tableDensity: 'compact' | 'comfortable' | 'spacious';
  setTableDensity: (density: UIState['tableDensity']) => void;
}

export const useUIStore = create<UIState>()(
  persist(
    immer((set, get) => ({
      sidebarState: 'expanded',
      setSidebarState: (state) => set(s => { s.sidebarState = state; }),
      toggleSidebar: () => set(s => {
        const next: Record<SidebarState, SidebarState> = {
          expanded:  'collapsed',
          collapsed: 'expanded',
          mini:      'expanded',
        };
        s.sidebarState = next[s.sidebarState];
      }),

      commandPaletteOpen: false,
      setCommandPaletteOpen: (open) => set(s => { s.commandPaletteOpen = open; }),

      sideSheetStack: [],
      pushSideSheet:  (id) => set(s => { s.sideSheetStack.push(id); }),
      popSideSheet:   () => set(s => { s.sideSheetStack.pop(); }),
      clearSideSheet: () => set(s => { s.sideSheetStack = []; }),

      jobs: [],
      addJob: (job) => set(s => { s.jobs.unshift(job as Job); }),
      updateJob: (id, patch) => set(s => {
        const job = s.jobs.find(j => j.id === id);
        if (job) Object.assign(job, patch);
      }),
      removeJob: (id) => set(s => {
        s.jobs = s.jobs.filter(j => j.id !== id);
      }),

      tableDensity: 'comfortable',
      setTableDensity: (density) => set(s => { s.tableDensity = density; }),
    })),
    {
      name:    'ui-store',
      storage: createJSONStorage(() => localStorage),
      // 영구 저장할 UI 상태만
      partialize: (state) => ({
        sidebarState: state.sidebarState,
        tableDensity: state.tableDensity,
      }),
    }
  )
);

// 편의 훅 (jobs 관련)
export const useJobStore = () => {
  const { jobs, addJob, updateJob, removeJob } = useUIStore();
  return { jobs, addJob, updateJob, removeJob };
};
```

---

## 3. WebSocket 상태와 React Query 연동

### 3-1. WebSocket Provider

```typescript
// components/WebSocketProvider.tsx
'use client';

import { createContext, useContext, useEffect, useRef, useCallback } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { useAuthStore } from '@/stores/auth.store';
import { useNotificationStore } from '@/stores/notification.store';
import { useJobStore } from '@/stores/ui.store';
import { queryKeys } from '@/lib/query/keys';
import { toast } from 'sonner';

type WSMessage =
  | { type: 'alarm.created';   payload: Alarm }
  | { type: 'alarm.resolved';  payload: { alarmId: string } }
  | { type: 'incident.created';payload: Incident }
  | { type: 'incident.updated';payload: Partial<Incident> & { id: string } }
  | { type: 'job.progress';    payload: { jobId: string; progress: number; status: string } }
  | { type: 'resource.updated';payload: { resourceId: string; type: string; state: string } }
  | { type: 'cost.anomaly';    payload: { tenantId: string; message: string } };

interface WSContextType {
  subscribe:   (channel: string) => void;
  unsubscribe: (channel: string) => void;
  isConnected: boolean;
}

const WSContext = createContext<WSContextType | null>(null);

export function WebSocketProvider({ children }: { children: React.ReactNode }) {
  const qc         = useQueryClient();
  const ws         = useRef<WebSocket | null>(null);
  const reconnectT = useRef<ReturnType<typeof setTimeout>>();
  const channels   = useRef<Set<string>>(new Set());

  const { addNotification } = useNotificationStore();
  const { updateJob }       = useJobStore();
  const { user }            = useAuthStore();

  const handleMessage = useCallback((event: MessageEvent) => {
    let msg: WSMessage;
    try {
      msg = JSON.parse(event.data);
    } catch {
      return;
    }

    switch (msg.type) {
      // ── 알람 ─────────────────────────────────────────────
      case 'alarm.created': {
        const alarm = msg.payload;

        // 알림 추가
        addNotification({
          id:       alarm.id,
          type:     'alarm',
          title:    `${alarm.severity} 알람 발생`,
          message:  alarm.displayName,
          severity: alarm.severity,
          href:     `/monitoring?alarm=${alarm.id}`,
          createdAt: new Date().toISOString(),
        });

        // P1/P2는 강조 토스트
        if (alarm.severity === 'P1' || alarm.severity === 'P2') {
          toast.error(`${alarm.severity} 알람: ${alarm.displayName}`, {
            duration:    Infinity,      // 수동으로 닫아야 함
            position:    'top-center',
            action: { label: '확인하기', onClick: () => {} },
          });
        }

        // 쿼리 무효화
        qc.invalidateQueries({ queryKey: queryKeys.monitoring.alarms() });
        qc.invalidateQueries({ queryKey: queryKeys.monitoring.summary() });
        break;
      }

      case 'alarm.resolved': {
        qc.invalidateQueries({ queryKey: queryKeys.monitoring.alarms() });
        qc.invalidateQueries({ queryKey: queryKeys.monitoring.summary() });
        break;
      }

      // ── Incident ──────────────────────────────────────────
      case 'incident.created': {
        const incident = msg.payload;
        addNotification({
          id:       incident.id,
          type:     'incident',
          title:    `Incident 생성: ${incident.title}`,
          message:  `${incident.severity} · ${incident.tenantName}`,
          severity: incident.severity,
          href:     `/incidents/${incident.id}`,
          createdAt: new Date().toISOString(),
        });
        qc.invalidateQueries({ queryKey: queryKeys.incidents.all });
        break;
      }

      case 'incident.updated': {
        const { id, ...patch } = msg.payload;
        // Incident 상세 캐시 업데이트 (refetch 없이)
        qc.setQueryData(queryKeys.incidents.detail(id), (old: Incident | undefined) =>
          old ? { ...old, ...patch } : undefined
        );
        // 목록은 invalidate
        qc.invalidateQueries({ queryKey: queryKeys.incidents.list() });
        break;
      }

      // ── 작업 진행률 ───────────────────────────────────────
      case 'job.progress': {
        const { jobId, progress, status } = msg.payload;

        updateJob(jobId, {
          progress,
          status: status as 'running' | 'success' | 'error',
        });

        if (status === 'SUCCESS') {
          // 관련 쿼리 자동 갱신
          qc.invalidateQueries({ queryKey: queryKeys.compute.all });
          toast.success('작업 완료');
        } else if (status === 'FAILED') {
          toast.error('작업 실패');
        }
        break;
      }

      // ── 리소스 상태 변경 ──────────────────────────────────
      case 'resource.updated': {
        const { resourceId, type, state } = msg.payload;

        if (type.startsWith('compute')) {
          // Compute 인스턴스 상태 즉시 업데이트 (refetch 없이)
          qc.setQueryData(queryKeys.compute.instances(), (old: Instance[] | undefined) =>
            old?.map(i => i.id === resourceId ? { ...i, lifecycleState: state } : i)
          );
        }
        break;
      }

      // ── 비용 이상 ─────────────────────────────────────────
      case 'cost.anomaly': {
        const { tenantId, message } = msg.payload;
        addNotification({
          id:       `cost-${tenantId}-${Date.now()}`,
          type:     'system',
          title:    '비용 이상 감지',
          message,
          href:     `/billing?tenant=${tenantId}`,
          createdAt: new Date().toISOString(),
        });
        toast.warning(`비용 이상 감지: ${message}`, {
          action: { label: '비용 분석', onClick: () => {} },
        });
        break;
      }
    }
  }, [qc, addNotification, updateJob]);

  const connect = useCallback(() => {
    if (!user) return;

    const wsUrl = `${process.env.NEXT_PUBLIC_WS_URL}/ws?token=${getAccessToken()}`;
    ws.current = new WebSocket(wsUrl);

    ws.current.onopen = () => {
      console.log('[WebSocket] Connected');
      // 구독 복원
      channels.current.forEach(ch => {
        ws.current?.send(JSON.stringify({ type: 'subscribe', channel: ch }));
      });
    };

    ws.current.onmessage = handleMessage;

    ws.current.onclose = () => {
      console.log('[WebSocket] Disconnected. Reconnecting in 3s...');
      reconnectT.current = setTimeout(connect, 3000);
    };

    ws.current.onerror = () => {
      ws.current?.close();
    };
  }, [user, handleMessage]);

  useEffect(() => {
    connect();
    return () => {
      clearTimeout(reconnectT.current);
      ws.current?.close();
    };
  }, [connect]);

  const subscribe = useCallback((channel: string) => {
    channels.current.add(channel);
    if (ws.current?.readyState === WebSocket.OPEN) {
      ws.current.send(JSON.stringify({ type: 'subscribe', channel }));
    }
  }, []);

  const unsubscribe = useCallback((channel: string) => {
    channels.current.delete(channel);
    if (ws.current?.readyState === WebSocket.OPEN) {
      ws.current.send(JSON.stringify({ type: 'unsubscribe', channel }));
    }
  }, []);

  return (
    <WSContext.Provider value={{
      subscribe,
      unsubscribe,
      isConnected: ws.current?.readyState === WebSocket.OPEN,
    }}>
      {children}
    </WSContext.Provider>
  );
}

// 사용 훅
export function useWebSocket() {
  const ctx = useContext(WSContext);
  if (!ctx) throw new Error('useWebSocket must be used inside WebSocketProvider');
  return ctx;
}

// 특정 테넌시 채널 구독
export function useTenantWebSocket(tenantId: string) {
  const { subscribe, unsubscribe } = useWebSocket();

  useEffect(() => {
    subscribe(`tenant:${tenantId}`);
    return () => unsubscribe(`tenant:${tenantId}`);
  }, [tenantId, subscribe, unsubscribe]);
}
```

### 3-2. 모니터링 메트릭 실시간 폴링 훅

```typescript
// hooks/useMetrics.ts
import { useQuery } from '@tanstack/react-query';
import { queryKeys, CACHE_POLICIES } from '@/lib/query';
import { apiClient } from '@/lib/api/client';

interface UseMetricsOptions {
  tenantId:   string;
  resourceId?: string;
  namespace:  string;
  metricName: string;
  timeRange:  '1h' | '6h' | '24h' | '7d';
  resolution?: string;  // 'PT1M', 'PT5M', 'PT1H'
}

export function useMetrics({
  tenantId, resourceId, namespace, metricName, timeRange, resolution,
}: UseMetricsOptions) {
  return useQuery({
    queryKey: queryKeys.monitoring.metrics(tenantId, { resourceId, namespace, metricName, timeRange }),
    queryFn:  async () => {
      const res = await apiClient.get<MetricDataPoint[]>('/monitoring/metrics', {
        params: { tenantId, resourceId, namespace, metricName, timeRange, resolution },
      });
      return res.data;
    },
    // 모니터링 데이터는 30초마다 자동 갱신
    refetchInterval: 30_000,
    ...CACHE_POLICIES.realtime,
  });
}
```
