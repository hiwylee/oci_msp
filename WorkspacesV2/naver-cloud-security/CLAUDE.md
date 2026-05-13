# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

OCI(Oracle Cloud Infrastructure) 클라우드 보안 컨설팅 문서 저장소입니다.
고객이 OCI 보안 기능을 이해하고 직접 설정할 수 있도록 **OCI 콘솔** 기반 절차와 **OCI CLI** 명령을 함께 제공합니다.

대상 고객 환경:
- DB: Oracle DB 미사용 → **MySQL, PostgreSQL, OpenSearch** 사용 중
- 접속: SSL VPN 없음 → **OCI Bastion Service** 단독 사용
- 주요 관심사: WAF, DB 접근통제, 암호화키 관리, CVE 취약점 점검, Run Command, Cloud Guard

## 문서 구조

| 파일 | 주제 |
|------|------|
| [docs/01_waf.md](docs/01_waf.md) | WAF (Web Application Firewall) 설정 |
| [docs/02_db_access_control.md](docs/02_db_access_control.md) | DB 접근통제 (MySQL / PostgreSQL / OpenSearch) |
| [docs/03_key_management.md](docs/03_key_management.md) | 암호화 키 관리 (OCI Vault / KMS) |
| [docs/04_cve_scanning.md](docs/04_cve_scanning.md) | CVE 취약점 점검 (OS Agent / Vulnerability Scanning) |
| [docs/05_bastion.md](docs/05_bastion.md) | OCI Bastion Service (SSL VPN 대체 접속) |
| [docs/06_cloud_guard.md](docs/06_cloud_guard.md) | Cloud Guard (보안 위협 탐지 및 OS 보안) |
| [docs/07_run_command.md](docs/07_run_command.md) | OCI Run Command (Compute 원격 명령 실행) |
| [docs/00_security_overview.md](docs/00_security_overview.md) | 보안 리소스 설정 빠른 참조 |
| [docs/08_integrated_security_guide.md](docs/08_integrated_security_guide.md) | 서비스별 지원 범위 + 통합 보안 설정 가이드 |

## OCI CLI 사용 규칙

- **프로필**: 모든 OCI CLI 명령은 반드시 `--profile YWDCLOUD` 옵션을 사용한다.
  ```bash
  oci <service> <command> --profile YWDCLOUD [기타 옵션]
  ```
- 문서 내 CLI 예시 코드에도 `--profile YWDCLOUD`를 포함하여 작성한다.

## 문서 작성 규칙

- **콘솔 절차**: 메뉴 경로를 `Identity & Security > Bastion` 형식으로 명시
- **CLI 명령**: `oci` CLI 예시를 항상 콘솔 절차 아래에 병기
- **고객 질문 매핑**: 각 문서 상단에 대응하는 실제 고객 질문을 `> 고객 질문:` 인용구로 기재
- 한국어로 작성, 기술 용어(서비스명·파라미터명)는 영문 원어 유지
