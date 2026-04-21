#!/usr/bin/env bash
# =============================================================================
#  deploy.sh  —  배포 패키지 생성
#  실행: bash scripts_v2/deploy.sh [버전메모]
#  출력: scripts_v2/build/YYYYMMDD_HHMMSS/   (압축 포함)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_ROOT="${SCRIPT_DIR}/build"
TS=$(date '+%Y%m%d_%H%M%S')
DATE_LABEL=$(date '+%Y-%m-%d %H:%M:%S')
MEMO="${1:-}"                              # 선택: bash deploy.sh "v1.0 초기배포"

BUILD_DIR="${BUILD_ROOT}/${TS}"
ARCHIVE="${BUILD_ROOT}/kidi_oda_scripts_${TS}.tar.gz"

# ── 배너 ─────────────────────────────────────────────────────────────────────
echo "================================================================"
echo "  KIDI ODA 배포 패키지 생성"
echo "  시각  : ${DATE_LABEL}"
echo "  출력  : ${BUILD_DIR}"
echo "  아카이브: ${ARCHIVE}"
[ -n "${MEMO}" ] && echo "  메모  : ${MEMO}"
echo "================================================================"

# ── build 디렉토리 생성 ───────────────────────────────────────────────────
mkdir -p "${BUILD_DIR}"

# ── 파일 복사 (build/ 자체 제외) ─────────────────────────────────────────
rsync -a \
  --exclude='build/' \
  --exclude='.gitkeep' \
  --exclude='*.pyc' \
  --exclude='__pycache__/' \
  --exclude='baseline/data/*.txt' \
  --exclude='cp_19.28/data/*.txt' \
  --exclude='cp_19.30/data/*.txt' \
  "${SCRIPT_DIR}/" "${BUILD_DIR}/"

# ── RELEASE 파일 생성 ────────────────────────────────────────────────────
cat > "${BUILD_DIR}/RELEASE.txt" <<RELEOF
=== KIDI ODA 배포 패키지 ===
생성일시 : ${DATE_LABEL}
패키지명  : kidi_oda_scripts_${TS}.tar.gz
메모      : ${MEMO:-없음}

=== 포함 파일 ===
RELEOF
find "${BUILD_DIR}" -type f | sed "s|${BUILD_DIR}/||" | sort >> "${BUILD_DIR}/RELEASE.txt"

# ── tar.gz 압축 ──────────────────────────────────────────────────────────
tar -czf "${ARCHIVE}" -C "${BUILD_ROOT}" "${TS}/"

# ── 결과 요약 ────────────────────────────────────────────────────────────
FILE_COUNT=$(find "${BUILD_DIR}" -type f | wc -l | tr -d ' ')
ARCHIVE_SIZE=$(du -sh "${ARCHIVE}" | cut -f1)

echo ""
echo "================================================================"
echo "  완료: ${DATE_LABEL}"
echo ""
echo "  디렉토리 : ${BUILD_DIR}"
echo "  아카이브 : ${ARCHIVE}  (${ARCHIVE_SIZE})"
echo "  파일 수  : ${FILE_COUNT}개"
echo ""
echo "  배포 목록:"
find "${BUILD_DIR}" -type f | sed "s|${BUILD_DIR}/||" | sort | sed 's/^/    /'
echo "================================================================"

# ── 이전 build 보존 현황 ─────────────────────────────────────────────────
echo ""
echo "  [build/ 전체 패키지 목록]"
ls -lth "${BUILD_ROOT}"/*.tar.gz 2>/dev/null | awk '{print "  "$NF"  ("$5")"}' || echo "  (없음)"
echo "================================================================"
