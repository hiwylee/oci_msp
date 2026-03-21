# UI/UX 설계서 — Part 7: 접근성 및 반응형

> OCI MSP 관리 플랫폼 | 작성일: 2026-03-21

---

## 1. WCAG 2.1 AA 준수 체크리스트

### 1-1. 인식 가능성 (Perceivable)

| 번호 | 기준 | 구현 방법 | 상태 |
|------|------|----------|------|
| 1.1.1 | 비텍스트 콘텐츠 대체 텍스트 | 모든 아이콘에 `aria-label` 또는 `title` | 필수 |
| 1.3.1 | 정보 및 관계 | 시맨틱 HTML (`table`, `nav`, `main`, `aside`) | 필수 |
| 1.3.2 | 의미 있는 순서 | DOM 순서 = 시각적 순서 일치 | 필수 |
| 1.3.3 | 감각적 특성 | 색상 외 아이콘/텍스트로도 상태 구분 | 필수 |
| 1.4.1 | 색상 사용 | 상태 배지: 색상 + 점 + 텍스트 모두 제공 | 필수 |
| 1.4.3 | 명도 대비 (최소) | 4.5:1 이상 (shadcn/ui 기본 준수) | 필수 |
| 1.4.4 | 텍스트 크기 조정 | 200% 확대 시 레이아웃 유지 | 권장 |
| 1.4.10 | 재배치 (Reflow) | 320px 너비에서 가로 스크롤 없음 | 권장 |
| 1.4.11 | 비텍스트 명도 대비 | UI 컴포넌트 경계선 3:1 이상 | 필수 |

### 1-2. 운용 가능성 (Operable)

| 번호 | 기준 | 구현 방법 | 상태 |
|------|------|----------|------|
| 2.1.1 | 키보드 접근 | 모든 인터랙션 키보드 가능 | 필수 |
| 2.1.2 | 키보드 트랩 없음 | 모달/드래그 Esc로 탈출 가능 | 필수 |
| 2.4.1 | 블록 건너뛰기 | "메인 콘텐츠로 건너뛰기" 링크 | 필수 |
| 2.4.3 | 초점 순서 | 논리적 Tab 순서 유지 | 필수 |
| 2.4.4 | 링크 목적 | 맥락 없이도 링크 의미 전달 | 필수 |
| 2.4.7 | 포커스 가시성 | Focus ring 2px solid sky-500 | 필수 |
| 2.5.1 | 포인터 제스처 | 드래그앤드롭 키보드 대안 제공 | 권장 |

### 1-3. 이해 가능성 (Understandable)

| 번호 | 기준 | 구현 방법 | 상태 |
|------|------|----------|------|
| 3.1.1 | 페이지 언어 | `<html lang="ko">` | 필수 |
| 3.2.2 | 입력 시 변경 없음 | 폼 제출은 명시적 버튼 클릭 | 필수 |
| 3.3.1 | 오류 식별 | 오류 필드 빨간 테두리 + 오류 메시지 | 필수 |
| 3.3.2 | 레이블 또는 지시문 | 모든 입력 필드 `<label>` 연결 | 필수 |
| 3.3.3 | 오류 제안 | "OCID는 'ocid1.'로 시작해야 합니다." | 필수 |

### 1-4. 접근성 구현 코드

```typescript
// components/layout/SkipLink.tsx — Skip Navigation
export function SkipLink() {
  return (
    <a
      href="#main-content"
      className={cn(
        'sr-only focus:not-sr-only',
        'fixed left-2 top-2 z-[9999] rounded-md bg-[var(--surface)] px-4 py-2',
        'text-sm font-medium focus:outline-none focus:ring-2 focus:ring-[var(--border-focus)]'
      )}
    >
      메인 콘텐츠로 건너뛰기
    </a>
  );
}

// app/(dashboard)/layout.tsx
// → <SkipLink /> 최상단 추가
// → <main id="main-content" tabIndex={-1} ...>

// ─────────────────────────────────────────────────────────────

// 명도 대비 확인 (Light/Dark 양쪽 체크)
// Light: 텍스트 #0F172A on #F8FAFC → 19.1:1 ✅
// Light: 보조 텍스트 #475569 on #FFFFFF → 5.9:1 ✅
// Light: Disabled 텍스트 #CBD5E1 on #FFFFFF → 1.6:1 ⚠ (disabled는 예외 허용)
// Dark:  텍스트 #F1F5F9 on #111827 → 13.4:1 ✅
// Dark:  보조 텍스트 #94A3B8 on #111827 → 4.8:1 ✅

// ─────────────────────────────────────────────────────────────

// ARIA 라이브 리전 — 실시간 알람 공지
// components/layout/LiveRegion.tsx
export function LiveRegion() {
  const { notifications } = useNotificationStore();
  const lastNotif = notifications[0];

  return (
    <>
      {/* 알람 실시간 공지 (스크린 리더) */}
      <div
        role="status"
        aria-live="polite"
        aria-atomic="true"
        className="sr-only"
      >
        {lastNotif && !lastNotif.read && `새 알림: ${lastNotif.title}. ${lastNotif.message}`}
      </div>

      {/* P1 알람은 즉시 공지 */}
      <div
        role="alert"
        aria-live="assertive"
        aria-atomic="true"
        className="sr-only"
      >
        {lastNotif?.severity === 'P1' && !lastNotif.read &&
          `긴급: P1 알람 발생. ${lastNotif.message}`
        }
      </div>
    </>
  );
}
```

### 1-5. 포커스 관리

```typescript
// Focus Trap for Modal/SideSheet — Radix UI 내장
// → Dialog, AlertDialog, Sheet 컴포넌트는 Radix UI 기반으로 자동 처리

// Focus Restore — 모달/패널 닫을 때 트리거로 복귀
export function useFocusRestore(isOpen: boolean) {
  const triggerRef = useRef<HTMLElement | null>(null);

  useEffect(() => {
    if (isOpen) {
      triggerRef.current = document.activeElement as HTMLElement;
    } else {
      // 패널 닫힐 때 원래 트리거로 포커스 복귀
      triggerRef.current?.focus();
    }
  }, [isOpen]);
}

// 테이블 키보드 네비게이션
export function useTableKeyboardNav(
  parentRef: React.RefObject<HTMLDivElement>,
  onOpen: (index: number) => void
) {
  useEffect(() => {
    const el = parentRef.current;
    if (!el) return;

    const handler = (e: KeyboardEvent) => {
      const rows = el.querySelectorAll('tr[role="row"]');
      const current = document.activeElement?.closest('tr');
      const idx = Array.from(rows).indexOf(current as HTMLTableRowElement);

      if (e.key === 'ArrowDown' || e.key === 'j') {
        e.preventDefault();
        (rows[idx + 1] as HTMLElement)?.focus();
      } else if (e.key === 'ArrowUp' || e.key === 'k') {
        e.preventDefault();
        (rows[idx - 1] as HTMLElement)?.focus();
      } else if (e.key === 'Enter' && idx >= 0) {
        e.preventDefault();
        onOpen(idx);
      }
    };

    el.addEventListener('keydown', handler);
    return () => el.removeEventListener('keydown', handler);
  }, [parentRef, onOpen]);
}
```

---

## 2. 키보드 단축키 전체 목록

### 2-1. 전역 단축키

| 단축키 | 동작 | 컨텍스트 |
|--------|------|----------|
| `Cmd/Ctrl + K` | Command Palette 열기 | 전역 |
| `Cmd/Ctrl + B` | 사이드바 토글 | 전역 |
| `Esc` | 모달/패널/드롭다운 닫기 | 전역 |
| `?` | 단축키 도움말 표시 | 전역 |

### 2-2. 페이지 이동 단축키 (g → 키)

| 단축키 | 이동 위치 | 비고 |
|--------|----------|------|
| `g` then `d` | 대시보드 (`/`) | |
| `g` then `c` | 고객사 목록 (`/tenants`) | |
| `g` then `r` | Compute 인스턴스 (`/compute/instances`) | |
| `g` then `m` | 모니터링 (`/monitoring`) | |
| `g` then `i` | Incidents (`/incidents`) | |
| `g` then `b` | 비용 분석 (`/billing`) | |
| `g` then `s` | 설정 (`/settings`) | |
| `g` then `a` | 감사 로그 (`/audit`) | |

### 2-3. 테이블 단축키

| 단축키 | 동작 |
|--------|------|
| `j` / `↓` | 다음 행 선택 |
| `k` / `↑` | 이전 행 선택 |
| `Enter` | 선택 행 상세 열기 (Side Sheet) |
| `Space` | 선택 행 체크/체크 해제 |
| `Shift + j/k` | 범위 선택 |
| `Ctrl/Cmd + a` | 전체 선택 |
| `Esc` | 선택 해제 / Side Sheet 닫기 |
| `/` | 테이블 내 검색 포커스 |

### 2-4. Side Sheet 단축키

| 단축키 | 동작 |
|--------|------|
| `Esc` | 현재 레벨 닫기 |
| `Tab` | 탭 이동 |
| `Shift + Tab` | 이전 탭 |
| `]` | 다음 탭 |
| `[` | 이전 탭 |
| `o` | 전체 페이지로 열기 |

### 2-5. 폼 단축키

| 단축키 | 동작 |
|--------|------|
| `Ctrl + Enter` | 폼 제출 |
| `Esc` | 폼 취소 |
| `Tab` | 다음 필드 |
| `Shift + Tab` | 이전 필드 |

### 2-6. 단축키 훅 구현

```typescript
// hooks/useKeyboardShortcuts.ts
import { useEffect, useRef } from 'react';

type KeyCombo = {
  key:       string;
  meta?:     boolean;
  ctrl?:     boolean;
  shift?:    boolean;
  alt?:      boolean;
  sequence?: string;  // 'g d' 같은 시퀀스
};

type Shortcut = {
  combo:       KeyCombo | KeyCombo[];
  handler:     (e: KeyboardEvent) => void;
  description: string;
  disabled?:   boolean;
};

export function useKeyboardShortcuts(shortcuts: Shortcut[]) {
  const sequenceBuffer = useRef<string[]>([]);
  const sequenceTimer  = useRef<ReturnType<typeof setTimeout>>();

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      // 입력 필드에서는 단축키 비활성화 (일부 제외)
      const target = e.target as HTMLElement;
      const isInput = ['INPUT', 'TEXTAREA', 'SELECT'].includes(target.tagName) ||
                      target.contentEditable === 'true';
      if (isInput && !e.metaKey && !e.ctrlKey) return;

      for (const shortcut of shortcuts) {
        if (shortcut.disabled) continue;

        const combos = Array.isArray(shortcut.combo) ? shortcut.combo : [shortcut.combo];

        for (const combo of combos) {
          // 시퀀스 처리 (g d, g c 등)
          if (combo.sequence) {
            sequenceBuffer.current.push(e.key.toLowerCase());
            clearTimeout(sequenceTimer.current);
            sequenceTimer.current = setTimeout(() => {
              sequenceBuffer.current = [];
            }, 1000);

            const bufStr = sequenceBuffer.current.join(' ');
            if (bufStr.endsWith(combo.sequence)) {
              e.preventDefault();
              sequenceBuffer.current = [];
              shortcut.handler(e);
            }
            continue;
          }

          // 일반 단축키
          const metaMatch  = combo.meta  ? (e.metaKey || e.ctrlKey) : true;
          const ctrlMatch  = combo.ctrl  ? e.ctrlKey                  : true;
          const shiftMatch = combo.shift ? e.shiftKey                 : true;
          const altMatch   = combo.alt   ? e.altKey                   : true;
          const keyMatch   = e.key.toLowerCase() === combo.key.toLowerCase();

          if (metaMatch && ctrlMatch && shiftMatch && altMatch && keyMatch) {
            e.preventDefault();
            shortcut.handler(e);
            break;
          }
        }
      }
    };

    document.addEventListener('keydown', handler);
    return () => {
      document.removeEventListener('keydown', handler);
      clearTimeout(sequenceTimer.current);
    };
  }, [shortcuts]);
}

// 전역 단축키 등록
export function useGlobalShortcuts() {
  const router = useRouter();
  const { setCommandPaletteOpen, toggleSidebar } = useUIStore();

  useKeyboardShortcuts([
    {
      combo: { key: 'k', meta: true },
      handler: () => setCommandPaletteOpen(true),
      description: 'Command Palette 열기',
    },
    {
      combo: { key: 'b', meta: true },
      handler: () => toggleSidebar(),
      description: '사이드바 토글',
    },
    {
      combo: { key: '?', shift: true },
      handler: () => { /* 단축키 도움말 */ },
      description: '단축키 도움말',
    },
    // 페이지 이동 시퀀스
    { combo: { key: 'd', sequence: 'g d' }, handler: () => router.push('/'),                      description: '대시보드' },
    { combo: { key: 'c', sequence: 'g c' }, handler: () => router.push('/tenants'),               description: '고객사' },
    { combo: { key: 'r', sequence: 'g r' }, handler: () => router.push('/compute/instances'),     description: 'Compute' },
    { combo: { key: 'm', sequence: 'g m' }, handler: () => router.push('/monitoring'),             description: '모니터링' },
    { combo: { key: 'i', sequence: 'g i' }, handler: () => router.push('/incidents'),             description: 'Incidents' },
    { combo: { key: 'b', sequence: 'g b' }, handler: () => router.push('/billing'),               description: '비용 분석' },
    { combo: { key: 's', sequence: 'g s' }, handler: () => router.push('/settings'),              description: '설정' },
  ]);
}
```

---

## 3. 모바일 대응 범위

### 3-1. 반응형 전략

```
데스크톱 (lg: 1024px+)
  → 전체 기능 지원
  → 사이드바 + TopBar + 메인 콘텐츠
  → TanStack Virtual 테이블
  → 드래그앤드롭 위젯

태블릿 (md: 768px ~ 1023px)
  → 읽기 전용 주요 기능
  → 사이드바 자동 collapsed (72px)
  → 테이블 열 일부 숨김 (우선순위 낮은 열)
  → Side Sheet 너비 조정

모바일 (sm: < 768px)
  → MVP 최소 지원 범위:
    ① 활성 알람 목록 확인
    ② Incident 상태 확인 + 상태 업데이트
  → 하단 탭 네비게이션으로 전환
  → 사이드바 → 슬라이드 드로어
  → 테이블 → 카드 뷰 자동 전환
```

### 3-2. 모바일 레이아웃

```typescript
// components/layout/MobileLayout.tsx
'use client';

import { useEffect } from 'react';
import { useUIStore } from '@/stores/ui.store';

// 모바일 감지 + 자동 사이드바 축소
export function useMobileLayout() {
  const { setSidebarState } = useUIStore();

  useEffect(() => {
    const mq = window.matchMedia('(max-width: 768px)');

    const handleChange = (e: MediaQueryListEvent | MediaQueryList) => {
      if (e.matches) {
        setSidebarState('mini');
      }
    };

    handleChange(mq);
    mq.addEventListener('change', handleChange);
    return () => mq.removeEventListener('change', handleChange);
  }, [setSidebarState]);
}

// 모바일 하단 탭 바
export function MobileBottomNav() {
  return (
    <nav
      className="md:hidden fixed bottom-0 left-0 right-0 z-50 flex h-16
                 border-t border-[var(--border)] bg-[var(--surface)]"
      aria-label="모바일 네비게이션"
    >
      {MOBILE_NAV_ITEMS.map(item => (
        <Link
          key={item.href}
          href={item.href}
          className="flex flex-1 flex-col items-center justify-center gap-1
                     text-[var(--text-tertiary)] hover:text-[var(--text-primary)]"
        >
          <item.icon size={20} />
          <span className="text-2xs">{item.label}</span>
        </Link>
      ))}
    </nav>
  );
}

const MOBILE_NAV_ITEMS = [
  { href: '/',          label: '홈',      icon: LayoutDashboard },
  { href: '/monitoring',label: '알람',    icon: Activity },
  { href: '/incidents', label: 'Incident',icon: Ticket },
  { href: '/tenants',   label: '고객사',  icon: Users },
];
```

### 3-3. 반응형 테이블 (카드 뷰 전환)

```typescript
// components/features/compute/InstanceListView.tsx
import { useMediaQuery } from '@/hooks/useMediaQuery';

export function InstanceListView({ instances }: { instances: Instance[] }) {
  const isMobile = useMediaQuery('(max-width: 768px)');

  if (isMobile) {
    // 카드 뷰 (모바일)
    return (
      <div className="space-y-3">
        {instances.map(inst => (
          <div
            key={inst.id}
            className="rounded-lg border border-[var(--border)] bg-[var(--surface)] p-4"
            onClick={() => openSideSheet(inst.id)}
          >
            <div className="flex items-start justify-between">
              <div>
                <p className="font-medium">{inst.displayName}</p>
                <p className="text-xs text-[var(--text-tertiary)] font-mono">{inst.shape}</p>
              </div>
              <StatusBadge status={inst.lifecycleState} size="sm" />
            </div>
            <div className="mt-3 grid grid-cols-2 gap-2">
              <div>
                <p className="text-2xs text-[var(--text-tertiary)] mb-1">CPU</p>
                <MetricBar value={inst.cpuUtilization} showValue size="sm" />
              </div>
              <div>
                <p className="text-2xs text-[var(--text-tertiary)] mb-1">MEM</p>
                <MetricBar value={inst.memUtilization} showValue size="sm" />
              </div>
            </div>
          </div>
        ))}
      </div>
    );
  }

  // 데스크톱 테이블 뷰
  return <InstanceTable instances={instances} />;
}
```

### 3-4. 모바일 알람 화면

```
모바일 알람 확인 화면:
┌──────────────────────────────────────┐
│ [≡]  모니터링                  [🔔3] │
│ ────────────────────────────────── │
│                                    │
│ 활성 알람 (32건)                   │
│                                    │
│ ┌──────────────────────────────┐   │
│ │ 🔴 P1  Acme DB 연결 실패     │   │
│ │        2분 전 · 홍길동 담당  │   │
│ │        [확인]  [Incident →]  │   │
│ └──────────────────────────────┘   │
│ ┌──────────────────────────────┐   │
│ │ 🟠 P2  Beta CPU 과부하       │   │
│ │        12분 전 · 미배정      │   │
│ │        [확인]  [Incident →]  │   │
│ └──────────────────────────────┘   │
│                                    │
│ [더 보기↓]                         │
│                                    │
├────────────────────────────────────┤
│ [🏠]  [📡 알람]  [🎫]  [🏢]       │
└──────────────────────────────────────┘

모바일 Incident 상태 업데이트:
┌──────────────────────────────────────┐
│ ← INC-089                     [⋯]   │
│ ────────────────────────────────── │
│                                    │
│ Acme DB 연결 실패         🔴 P1   │
│ 담당: 홍길동  ·  0h 32m            │
│                                    │
│ 현재 상태: [조치 중 ▾]             │
│                                    │
│ 빠른 업데이트                      │
│ ┌──────────────────────────────┐   │
│ │ 조치 내용...                  │   │
│ └──────────────────────────────┘   │
│ [내부 메모] [공개 업데이트] [등록] │
│                                    │
│ ── 타임라인 ──                     │
│ 13:15 🔴 알람 발생                 │
│ 13:18 👤 홍길동 배정               │
│ 13:22 💬 조치 기록: DB 재시작      │
│                                    │
└──────────────────────────────────────┘
```
