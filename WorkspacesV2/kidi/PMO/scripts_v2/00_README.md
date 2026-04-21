# CLOB 대용량 데이터 임포트 가이드
## 환경: ODA / Oracle 23ai  |  덤프: 2023(3개) + 2024(10개)  |  CLOB 100GB+

---

## 수행 순서

```
Step 0  00_config.sh        설정값 입력  ← 반드시 먼저
Step 1  01_precheck.sql     사전 용량/환경 점검
Step 2  02_create_tablespace.sql  Tablespace 생성
Step 3  03_create_user.sql  사용자 + 권한 생성
Step 4  04_create_directory.sql   Oracle Directory 등록
Step 5  05_run_impdp.sh     impdp 실행 (2023 → 2024 순)
Step 6  06_verify.sql       로딩 결과 검증
Step 99 99_rollback.sql     문제 발생 시 정리
```

---

## 빠른 시작

```bash
# 1) 설정 파일 편집
vi 00_config.sh

# 2) 덤프 파일 목록 확인 후 00_config.sh의 DUMP_FILES_* 배열 수정
ls /test_26aipoc/testdbdata/

# 3) 사전 점검 (DBA 터미널)
sqlplus / as sysdba @01_precheck.sql

# 4) Tablespace + User + Directory 생성
sqlplus / as sysdba @02_create_tablespace.sql
sqlplus / as sysdba @03_create_user.sql
sqlplus / as sysdba @04_create_directory.sql

# 5) impdp 실행 (백그라운드 권장)
chmod +x 05_run_impdp.sh
nohup ./05_run_impdp.sh > /tmp/impdp_master.log 2>&1 &
tail -f /tmp/impdp_master.log

# 6) 결과 검증
sqlplus / as sysdba @06_verify.sql
```

---

## ODA CLOB 로딩 핵심 주의사항

| 항목 | 확인 내용 | 명령 |
|------|----------|------|
| Force Logging | ON이면 NOLOGGING 무효 → ADG 재동기화 필요 | `01_precheck.sql` |
| Undo TBS | 100GB+ CLOB → Undo 급증 가능 | `01_precheck.sql` |
| ASM 여유 공간 | LOB TBS 200G 이상 필요 | `01_precheck.sql` |
| PGA | impdp 병렬시 PGA 소비 증가 | `01_precheck.sql` |
| Archive Log | 로딩 중 아카이브 공간 급증 | `01_precheck.sql` |

---

## 파일 설명

| 파일 | 역할 |
|------|------|
| `00_config.sh` | 모든 변수 중앙 관리 (여기만 수정) |
| `01_precheck.sql` | Undo·Temp·ASM·ForceLog 사전 점검 |
| `02_create_tablespace.sql` | DATA/LOB 분리 Tablespace 생성 |
| `03_create_user.sql` | 스키마 사용자 생성 + 최소 권한 |
| `04_create_directory.sql` | 2023/2024 Oracle Directory 등록 |
| `05_run_impdp.sh` | impdp 최적 파라미터 자동 실행 |
| `06_verify.sql` | 행수·LOB크기·오류 여부 확인 |
| `99_rollback.sql` | User/TBS/Directory 전체 삭제 |
