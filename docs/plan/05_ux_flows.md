# UI/UX 설계서 — Part 5: UX 흐름 설계

> OCI MSP 관리 플랫폼 | 작성일: 2026-03-21

---

## 1. 새 테넌시 온보딩 (목표: 15분 이내)

### 1-1. 전체 흐름 다이어그램

```
[사이드바] "고객사" 클릭
    │
    ▼
/tenants 목록 페이지
    │
    │ [+ 새 테넌시 추가] 클릭
    ▼
/tenants/new (Step 1)
    │
    │ ┌─────────────────────────────────────────────────────┐
    │ │ STEP 1: Credential 입력 (예상: 3분)                 │
    │ │                                                     │
    │ │  접근 방식 선택 (Cross-Tenancy / API Key)           │
    │ │  고객사명 + 테넌시 OCID + 홈 리전 + SLA 티어        │
    │ │  [Cross-Tenancy] 정책 가이드 & 복사                 │
    │ │                                                     │
    │ │  검증: 실시간 OCID 형식 확인                        │
    │ │  URL: ?step=1                                       │
    │ └─────────────────────────────────────────────────────┘
    │
    │ [다음] → 폼 검증 → 임시 저장
    ▼
STEP 2: 권한 검증 (자동, 예상: 2분)
    │
    │  OCI API 연결 테스트 (WebSocket 실시간 표시)
    │  - 기본 연결 ✅
    │  - IAM 정책 ✅
    │  - Compute 권한 ✅
    │  - Network 권한 ✅
    │  - DB 권한 ⚠ (선택적)
    │
    │  [경고 있을 때] → 무시/해결 선택 가능
    │  [연결 실패 시] → 에러 + 원인 + 해결 링크
    ▼
STEP 3: Compartment 탐색 (자동, 예상: 1분)
    │
    │  OCI API → Compartment 트리 자동 탐색
    │  체크박스 선택 (모니터링 범위)
    │  태깅 자동 추천
    ▼
STEP 4: 모니터링 기본값 (예상: 5분)
    │
    │  임계값 설정 (SLA 티어 기본값 자동 적용)
    │  알람 채널 설정 + 연결 테스트
    │  Maintenance Window 설정
    ▼
STEP 5: 담당자 & SLA (예상: 2분)
    │
    │  주/백업 엔지니어 선택
    │  SLA 설정 검토
    │  온보딩 요약 확인
    │
    │ [온보딩 완료 및 동기화 시작] 클릭
    ▼
백그라운드 동기화 시작 (Celery Task)
    │
    │  Toast: "동기화 시작됨. 완료 시 알림을 드립니다."
    │  작업 센터: 진행률 표시
    ▼
/tenants/[newId] 리디렉션
    │
    │  성공 배너 + 동기화 진행률 표시
    │  이후 WebSocket으로 실시간 업데이트
    ▼
동기화 완료
    │
    │  Toast: "✅ Acme Corporation 동기화 완료 (1,060개 리소스)"
    │  페이지 자동 갱신
```

### 1-2. 타이밍 분석

| 단계 | 사용자 대기 | 시스템 처리 | 비고 |
|------|------------|------------|------|
| Step 1 | 3분 | 즉시 | 폼 입력 |
| Step 2 | 30~60초 | OCI API 호출 | 자동 진행 |
| Step 3 | 10~30초 | OCI API 탐색 | 자동 진행 |
| Step 4 | 5분 | 즉시 | 폼 입력 |
| Step 5 | 2분 | 즉시 | 검토 + 클릭 |
| **합계** | **~11분** | | |
| 백그라운드 동기화 | 0분 (대기 불필요) | 5~30분 | 백그라운드 진행 |

**목표 15분 달성**: 사용자 직접 대기는 ~11분, 동기화는 백그라운드.

### 1-3. 에러 복구 플로우

```
Step 2 권한 검증 실패
    │
    ├── OCI API 연결 실패
    │   → 에러 메시지 + 원인 표시
    │   → [OCID 재확인] [정책 가이드 열기] [재시도]
    │
    ├── IAM 정책 없음
    │   → 필요 정책 자동 생성 스크립트 표시 + 복사
    │   → [정책 추가 후 재시도]
    │
    └── DB 권한 없음 (비필수)
        → [경고] + [무시하고 계속] 옵션
        → DB 기능 제한 안내
```

---

## 2. 인스턴스 중지 (3클릭 이내, WebSocket 진행률)

### 2-1. 클릭 경로

```
클릭 1: /compute/instances 목록에서 인스턴스 행의 [···] 메뉴 클릭
           또는 Side Sheet에서 [■ 중지] 버튼 클릭

클릭 2: ConfirmDialog "중지" 버튼 클릭 (LOW 위험도 — 단순 확인)

클릭 3: (완료, 사용자 추가 클릭 불필요)
        → AsyncJobButton이 자동으로 진행률 추적

총 클릭: 2~3회
```

### 2-2. 상세 흐름

```
① 사용자: 테이블 행 [···] 클릭
   → 드롭다운: [▶ 시작] [■ 중지] [↺ 재시작] [상세 보기]

② 사용자: [■ 중지] 선택
   → ConfirmDialog 오픈 (LOW 위험도)
   → "web-prod-01을 중지합니다. 언제든지 다시 시작할 수 있습니다."
   → [취소] [중지]

③ 사용자: [중지] 클릭
   → API POST /api/v1/compute/instances/{id}/stop
   → 응답: { jobId: "job-4521", workRequestId: "ocid1.workrequest..." }

④ 시스템: WebSocket → 실시간 진행률
   → 테이블 행: 상태가 STOPPING으로 변경 + 스피너
   → AsyncJobButton: "중지 중... 30%"
   → 작업 센터: "web-prod-01 중지 중 ████░░░░ 30%"

⑤ OCI Work Request 완료
   → WebSocket: { jobId: "job-4521", progress: 100, status: "SUCCESS" }
   → 테이블 행: 상태 → STOPPED
   → Toast: "✅ web-prod-01 중지 완료"
   → TanStack Query: invalidate(['instances'])

실패 시:
   → 테이블 행: 상태 → ERROR
   → Toast: "❌ 중지 실패 [오류 보기] [재시도]"
   → 작업 센터: "web-prod-01 중지 실패 — OCI WorkRequest Error"
```

### 2-3. 구현 코드

```typescript
// hooks/useInstanceActions.ts
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { apiClient } from '@/lib/api/client';
import { queryKeys } from '@/lib/query/keys';
import { toast } from 'sonner';

export function useStopInstance() {
  const qc = useQueryClient();

  return useMutation({
    mutationFn: async (instanceId: string) => {
      const res = await apiClient.post<{ jobId: string }>(
        `/compute/instances/${instanceId}/stop`
      );
      return res.data;
    },

    // Optimistic Update: 즉시 STOPPING으로 변경
    onMutate: async (instanceId) => {
      await qc.cancelQueries({ queryKey: queryKeys.compute.instances() });

      const prev = qc.getQueryData(queryKeys.compute.instances());
      qc.setQueryData(queryKeys.compute.instances(), (old: Instance[] | undefined) =>
        old?.map(i => i.id === instanceId ? { ...i, lifecycleState: 'STOPPING' } : i)
      );

      return { prev };
    },

    onSuccess: ({ jobId }, instanceId) => {
      // WebSocket으로 진행률 추적 (useWebSocket hook에서 처리)
      toast.info('중지 작업이 시작되었습니다.', {
        description: `Job #${jobId}`,
        duration: 3000,
      });
    },

    onError: (err, instanceId, context) => {
      // Optimistic Update 롤백
      if (context?.prev) {
        qc.setQueryData(queryKeys.compute.instances(), context.prev);
      }
      toast.error('중지 작업 시작 실패', {
        description: err instanceof Error ? err.message : '서버 오류',
        action: {
          label: '재시도',
          onClick: () => { /* 재시도 */ },
        },
      });
    },
  });
}
```

---

## 3. 알람 → Incident 생성 → 담당자 배정 흐름

### 3-1. 자동 흐름 (시스템)

```
OCI Monitoring → Celery Beat 폴링 (30초)
    │
    │  임계값 초과 감지
    ▼
Alert 레코드 생성 (DB)
    │
    │  이미 알람 규칙과 매칭
    ▼
자동 그루핑 체크
    │
    ├── [유사 알람 존재] → 기존 Incident에 연결
    └── [신규] → Incident 자동 생성
            │
            ├── P1/P2: On-call 엔지니어 자동 배정
            │          (테넌시 담당자 → 없으면 매니저 에스컬레이션)
            └── P3/P4: 배정 대기 상태로 생성
    │
    ▼
WebSocket 브로드캐스트
    │
    │  → 사이드바 알림 벨 카운터 +1
    │  → Toast 알림 (P1: 화면 중앙, P2: 우하단, P3: 우하단)
    │  → 알람 요약 패널 실시간 업데이트
    ▼
알림 채널 발송 (비동기)
    │
    ├── 이메일: ops@company.com
    ├── Slack:  #oci-alerts 채널
    └── SMS:   담당자 핸드폰 (P1만)
```

### 3-2. 담당자 수동 배정 흐름

```
/incidents 목록
    │
    │  배정 대기 상태 Incident 확인
    ▼
Incident 행 클릭 → Side Sheet or 상세 페이지
    │
    │  [담당자: 미배정 ▾] 클릭
    ▼
드롭다운: 엔지니어 목록
    │  ○ 홍길동 (현재 담당: 3건)
    │  ○ 김영수 (현재 담당: 1건) ← 추천 (가장 여유 있음)
    │  ○ 이민준 (현재 담당: 5건)
    │
    │ 선택 클릭 → 즉시 배정 (Optimistic Update)
    ▼
시스템:
    - DB: Incident.assigneeId 업데이트
    - Audit Log: 배정 이력 기록
    - 담당자 알림 (Slack/이메일)
    - 타임라인에 "홍길동 배정됨" 이벤트 추가
    │
    ▼
UI:
    - 담당자 셀: 즉시 변경 (Optimistic)
    - Toast: "홍길동에게 INC-089 배정됨"
```

### 3-3. 알람 → Incident 자동 생성 설정

```typescript
// app/(dashboard)/monitoring/alarms/new/page.tsx 의 Step 2 (조건 설정 UI)

// 알람 규칙 생성 위저드 — Incident 자동 생성 설정
const alarmRuleSchema = z.object({
  name:            z.string().min(1),
  metricNamespace: z.string(),
  metricName:      z.string(),
  condition:       z.object({
    operator:  z.enum(['GT', 'GTE', 'LT', 'LTE', 'EQ']),
    threshold:  z.number(),
    duration:   z.number(),  // 분
  }),
  severity:        z.enum(['P1', 'P2', 'P3', 'P4']),

  // Incident 자동 생성 설정
  autoCreateIncident: z.boolean(),
  incidentTitle:      z.string().optional(),  // 미입력 시 알람명 사용
  autoAssign:         z.boolean(),            // 테넌시 담당자 자동 배정

  // 알림 채널
  notificationChannels: z.array(z.string()),

  // Maintenance Window
  maintenanceWindows: z.array(z.object({
    dayOfWeek: z.number(),   // 0=일, 6=토
    startTime: z.string(),   // 'HH:mm'
    endTime:   z.string(),
  })),

  // 알람 피로도 방지
  repeatInterval: z.number(),  // 재알람 최소 간격 (분)
  groupBy:        z.array(z.string()),  // 그루핑 키
});
```

---

## 4. 비동기 작업 실패 시 재시도

### 4-1. 실패 감지 및 UI 표시

```
작업 실행 중 (예: 인스턴스 시작)
    │
    │  WebSocket: { jobId: "job-4521", status: "FAILED", error: "...", progress: 45 }
    ▼
UI 업데이트:
    ├── 테이블 행: ERROR 상태 배지
    ├── AsyncJobButton: 상태 → 'error', 아이콘 → XCircle
    ├── 작업 센터 패널: "❌ web-prod-01 시작 실패"
    └── Toast (영구 표시, 자동 닫힘 없음):
        ┌──────────────────────────────────────────────────┐
        │ ❌ 인스턴스 시작 실패                             │
        │    web-prod-01 · OCI WorkRequest 시간 초과        │
        │                          [오류 보기] [재시도]     │
        └──────────────────────────────────────────────────┘
```

### 4-2. 재시도 흐름

```
[재시도] 버튼 클릭
    │
    ├── LOW 위험도 (시작/재시작): 바로 재시도
    └── MED 이상: 실패 원인 + 재시도 확인 다이얼로그
            │
            │  "이전 작업이 실패했습니다.
            │   오류: OCI Rate Limit 초과
            │   재시도하시겠습니까?"
            │
            │  [취소] [재시도]
            ▼
API POST /api/v1/jobs/{jobId}/retry
    │
    │  새 jobId 반환
    ▼
새 작업으로 진행 (동일 흐름)
```

### 4-3. 재시도 정책 (프론트엔드)

```typescript
// hooks/useJobRetry.ts
export function useJobRetry() {
  const retryJob = useCallback(async (
    jobId:   string,
    retryFn: () => Promise<{ jobId: string }>,
    options?: { maxRetries?: number; backoffMs?: number }
  ) => {
    const { maxRetries = 3, backoffMs = 1000 } = options ?? {};
    let attempt = 0;

    while (attempt < maxRetries) {
      try {
        return await retryFn();
      } catch (err) {
        attempt++;
        if (attempt >= maxRetries) throw err;

        // 지수 백오프
        const delay = backoffMs * Math.pow(2, attempt - 1);
        await new Promise(r => setTimeout(r, delay));
      }
    }
  }, []);

  return { retryJob };
}
```

### 4-4. 작업 센터 (Job Center) UI

```
┌──────────────────────────────────────────────────────┐
│ 작업 센터                               [_] [X]      │
├──────────────────────────────────────────────────────┤
│ 진행 중 (2)                                          │
│ ┌────────────────────────────────────────────────┐   │
│ │ ⟳ web-prod-01 중지          ████████░░ 80%    │   │
│ │   Acme Corp · 0:02 경과                        │   │
│ └────────────────────────────────────────────────┘   │
│ ┌────────────────────────────────────────────────┐   │
│ │ ⟳ Compartment 동기화        ████░░░░░░ 40%    │   │
│ │   Beta Inc · 0:45 경과                         │   │
│ └────────────────────────────────────────────────┘   │
│ ─────────────────────────────────────────────────    │
│ 완료 (3)                                             │
│ ✅ app-prod-02 재시작       완료 · 3분 전            │
│ ✅ 온보딩: Gamma Co         완료 · 15분 전           │
│ ❌ db-prod-01 스냅샷        실패 · 1시간 전 [재시도] │
└──────────────────────────────────────────────────────┘
  우하단 고정, 최소화 시 → [작업 센터 ↕ 2진행중] 뱃지
```

```typescript
// components/layout/JobCenter/index.tsx
'use client';

import { useState } from 'react';
import { useJobStore } from '@/stores/ui.store';
import { Loader2, CheckCircle2, XCircle, ChevronDown, ChevronUp } from 'lucide-react';
import { cn } from '@/lib/utils';

export function JobCenter() {
  const [isExpanded, setIsExpanded] = useState(false);
  const { jobs } = useJobStore();

  const runningJobs = jobs.filter(j => j.status === 'running');
  const doneJobs    = jobs.filter(j => j.status !== 'running').slice(0, 10);

  if (jobs.length === 0) return null;

  return (
    <div
      className={cn(
        'fixed bottom-4 right-4 z-40 w-80',
        'rounded-xl border border-[var(--border)] bg-[var(--surface)] shadow-xl',
        'transition-all duration-300'
      )}
      role="region"
      aria-label="비동기 작업 센터"
      aria-live="polite"
    >
      {/* 헤더 */}
      <button
        className="flex w-full items-center justify-between px-4 py-3
                   hover:bg-[var(--surface-raised)] rounded-xl transition-colors"
        onClick={() => setIsExpanded(v => !v)}
        aria-expanded={isExpanded}
      >
        <div className="flex items-center gap-2">
          {runningJobs.length > 0 && (
            <Loader2 size={14} className="animate-spin text-[var(--brand-accent)]" />
          )}
          <span className="text-sm font-medium">작업 센터</span>
          {runningJobs.length > 0 && (
            <span className="rounded-full bg-[var(--brand-accent)] px-1.5 py-0.5 text-2xs font-bold text-white">
              {runningJobs.length}
            </span>
          )}
        </div>
        {isExpanded ? <ChevronDown size={14} /> : <ChevronUp size={14} />}
      </button>

      {/* 작업 목록 */}
      {isExpanded && (
        <div className="max-h-80 overflow-y-auto px-3 pb-3 space-y-2">
          {runningJobs.length > 0 && (
            <div>
              <p className="text-2xs font-medium text-[var(--text-tertiary)] uppercase mb-1.5 px-1">
                진행 중 ({runningJobs.length})
              </p>
              {runningJobs.map(job => (
                <div key={job.id} className="rounded-lg bg-[var(--surface-raised)] px-3 py-2">
                  <div className="flex items-center justify-between mb-1.5">
                    <span className="text-xs font-medium truncate">{job.label}</span>
                    <span className="text-2xs text-[var(--text-tertiary)]">{job.progress}%</span>
                  </div>
                  <div className="h-1 rounded-full bg-[var(--border)]">
                    <div
                      className="h-full rounded-full bg-[var(--brand-accent)] transition-all"
                      style={{ width: `${job.progress}%` }}
                    />
                  </div>
                </div>
              ))}
            </div>
          )}

          {doneJobs.length > 0 && (
            <div>
              <p className="text-2xs font-medium text-[var(--text-tertiary)] uppercase mb-1.5 px-1">
                완료
              </p>
              {doneJobs.map(job => (
                <div key={job.id} className="flex items-center justify-between px-1 py-1">
                  <div className="flex items-center gap-2 min-w-0">
                    {job.status === 'success'
                      ? <CheckCircle2 size={12} className="text-status-success shrink-0" />
                      : <XCircle     size={12} className="text-status-error shrink-0" />
                    }
                    <span className="text-xs truncate">{job.label}</span>
                  </div>
                  {job.status === 'error' && (
                    <button
                      className="text-2xs text-[var(--brand-accent)] hover:underline shrink-0"
                      onClick={() => job.retry?.()}
                    >
                      재시도
                    </button>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
```
