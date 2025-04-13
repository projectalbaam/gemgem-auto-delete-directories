#!/bin/bash

# 설정 변수
LOG_FILE="./cleanup.log"  # 기본값은 현재 디렉터리에 로그 저장
TARGET_DIRS=10      # 유지할 목표 디렉터리 수
DRY_RUN=false       # 테스트 모드 (실제 삭제 안 함)

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
log() {
    local level="$1"
    local message="$2"
    local color="$NC"
    
    case "$level" in
        "INFO") color="$BLUE" ;;
        "SUCCESS") color="$GREEN" ;;
        "WARNING") color="$YELLOW" ;;
        "ERROR") color="$RED" ;;
    esac
    
    # 파일에 로그 저장 (색상 없이)
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [$level] $message" >> "$LOG_FILE"
    
    # 터미널에 로그 출력 (색상 포함)
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - ${color}[$level]${NC} $message"
}

# 사용법 출력 함수
usage() {
    echo "사용법: $0 [옵션] 디렉터리1 [디렉터리2 ...]"
    echo "옵션:"
    echo "  -t, --target NUM      유지할 목표 디렉터리 수 (기본값: $TARGET_DIRS)"
    echo "  -l, --log FILE        로그 파일 경로 (기본값: $LOG_FILE)"
    echo "  -d, --dry-run         테스트 모드 (실제 삭제 없이 계획만 표시)"
    echo "  -h, --help            이 도움말 메시지 표시"
    echo ""
    echo "예시:"
    echo "  $0 /path/to/dir1 /path/to/dir2"
    echo "  $0 -t 15 /path/to/dir1"
    echo "  $0 --log /tmp/cleanup.log /path/to/dir1"
    echo "  $0 --dry-run /path/to/dir1"
    exit 1
}

# 인자 파싱
DIRECTORIES=()
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--target)
            TARGET_DIRS="$2"
            shift 2
            ;;
        -l|--log)
            LOG_FILE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        -*)
            echo "알 수 없는 옵션: $1"
            usage
            ;;
        *)
            DIRECTORIES+=("$1")
            shift
            ;;
    esac
done

# 처리할 디렉터리가 없으면 사용법 표시
if [ ${#DIRECTORIES[@]} -eq 0 ]; then
    echo "오류: 처리할 디렉터리를 최소 하나 이상 지정해야 합니다."
    usage
fi

# 로그 디렉터리 확인 및 생성
LOG_DIR=$(dirname "$LOG_FILE")
if [ ! -d "$LOG_DIR" ] && [ "$LOG_DIR" != "." ]; then
    mkdir -p "$LOG_DIR" || {
        echo "오류: 로그 디렉터리를 생성할 수 없습니다: $LOG_DIR"
        # 실패 시 현재 디렉터리에 로그 저장
        LOG_FILE="./cleanup.log"
        echo "로그 파일 위치를 현재 디렉터리로 변경: $LOG_FILE"
    }
fi

# 테스트 모드 메시지
if [ "$DRY_RUN" = true ]; then
    log "INFO" "테스트 모드로 실행 중입니다 - 실제 삭제는 수행되지 않습니다"
fi

log "INFO" "스크립트 시작: 유지할 목표 디렉터리 수=$TARGET_DIRS"
log "INFO" "처리할 최상위 디렉터리 수: ${#DIRECTORIES[@]}"
for ((i=0; i<${#DIRECTORIES[@]}; i++)); do
    log "INFO" "   최상위 디렉터리 #$((i+1)): ${DIRECTORIES[$i]}"
done

# 요약 통계
total_all_dirs=0
total_numeric_dirs=0
total_deleted=0
total_skipped=0

# 각 디렉터리 처리
for dir in "${DIRECTORIES[@]}"; do
    log "INFO" "-----------------------------------------------"
    log "INFO" "최상위 디렉터리 처리 중: $dir"
    
    # 디렉터리가 존재하는지 확인
    if [ ! -d "$dir" ]; then
        log "ERROR" "디렉터리가 존재하지 않습니다: $dir"
        continue
    fi
    
    # 전체 하위 디렉터리 수 확인
    all_subdirs=$(find "$dir" -mindepth 1 -maxdepth 1 -type d | wc -l)
    all_subdirs=$(echo $all_subdirs | tr -d '[:space:]')  # 공백 제거
    total_all_dirs=$((total_all_dirs + all_subdirs))
    log "INFO" "전체 하위 디렉터리 수: $all_subdirs"
    
    # 숫자로만 구성된 디렉터리 찾기 (숫자 기준으로 정렬)
    numeric_dirs=()
    non_numeric_dirs=()
    
    # find 명령의 결과를 파일로 저장 (프로세스 치환 대신)
    find_temp=$(mktemp)
    find "$dir" -mindepth 1 -maxdepth 1 -type d | sort -V > "$find_temp"
    
    while IFS= read -r subdir; do
        basename=$(basename "$subdir")
        # 숫자로만 구성된 디렉터리 필터링
        if [[ $basename =~ ^[0-9]+$ ]]; then
            numeric_dirs+=("$subdir")
        else
            non_numeric_dirs+=("$subdir")
        fi
    done < "$find_temp"
    
    # 임시 파일 삭제
    rm -f "$find_temp"
    
    total_numeric_dirs=$((total_numeric_dirs + ${#numeric_dirs[@]}))
    
    log "INFO" "숫자 디렉터리 수: ${#numeric_dirs[@]} (숫자 아닌 디렉터리: ${#non_numeric_dirs[@]})"
    
    if [ ${#numeric_dirs[@]} -gt 0 ]; then
        # 숫자 디렉터리 목록을 한 줄로 표시
        dir_list=""
        
        # 첫 5개 디렉터리 추가
        for ((i=0; i<${#numeric_dirs[@]} && i<5; i++)); do
            basename=$(basename "${numeric_dirs[$i]}")
            if [ -z "$dir_list" ]; then
                dir_list="$basename"
            else
                dir_list="$dir_list, $basename"
            fi
        done
        
        # 중간 생략 표시
        if [ ${#numeric_dirs[@]} -gt 10 ]; then
            dir_list="$dir_list, ... "
            
            # 마지막 3개 디렉터리 추가
            for ((i=${#numeric_dirs[@]}-3; i<${#numeric_dirs[@]}; i++)); do
                if [ $i -ge 5 ]; then
                    basename=$(basename "${numeric_dirs[$i]}")
                    dir_list="$dir_list, $basename"
                fi
            done
        # 10개 이하면 나머지 모두 표시
        elif [ ${#numeric_dirs[@]} -gt 5 ]; then
            for ((i=5; i<${#numeric_dirs[@]}; i++)); do
                basename=$(basename "${numeric_dirs[$i]}")
                dir_list="$dir_list, $basename"
            done
        fi
        
        log "INFO" "숫자 디렉터리 목록 (오름차순): $dir_list"
    fi
    
    # 디렉터리 수가 목표치를 초과하는지 확인
    if [ "${#numeric_dirs[@]}" -gt "$TARGET_DIRS" ]; then
        # 삭제할 디렉터리 수 계산
        to_delete=$((${#numeric_dirs[@]} - TARGET_DIRS))
        
        log "WARNING" "삭제 필요: $to_delete 개 (총 ${#numeric_dirs[@]} 중 $TARGET_DIRS 개만 유지)"
        
        if [ $to_delete -gt 0 ]; then
            # 삭제 대상 목록을 한 줄로 표시
            delete_list=""
            for ((i=0; i<to_delete && i<${#numeric_dirs[@]}; i++)); do
                basename=$(basename "${numeric_dirs[$i]}")
                if [ -z "$delete_list" ]; then
                    delete_list="$basename"
                else
                    delete_list="$delete_list, $basename"
                fi
            done
            log "WARNING" "삭제 대상 디렉터리: $delete_list"
            
            # 테스트 모드일 경우 실제 삭제하지 않음
            if [ "$DRY_RUN" = true ]; then
                log "INFO" "테스트 모드: 위 $to_delete 개의 디렉터리는 실제로 삭제되지 않았습니다."
                total_skipped=$((total_skipped + to_delete))
            else
                # 실제 삭제 작업 수행
                log "INFO" "삭제 작업 시작..."
                deleted=0
                for ((i=0; i<to_delete && i<${#numeric_dirs[@]}; i++)); do
                    subdir="${numeric_dirs[$i]}"
                    basename=$(basename "$subdir")
                    
                    log "WARNING" "   삭제 중: $basename"
                    # 디렉터리 삭제 시도
                    if rm -rf "$subdir"; then
                        log "SUCCESS" "   삭제 완료: $basename"
                        deleted=$((deleted + 1))
                        total_deleted=$((total_deleted + 1))
                    else
                        log "ERROR" "   삭제 실패: $basename"
                    fi
                done
                
                log "SUCCESS" "삭제 작업 완료: $deleted 개 삭제됨 (남은 디렉터리: $((${#numeric_dirs[@]} - deleted)))"
            fi
        fi
    else
        log "SUCCESS" "디렉터리 수(${#numeric_dirs[@]})가 목표치($TARGET_DIRS) 이하입니다. 삭제 작업 없음."
    fi
done

log "INFO" "-----------------------------------------------"
log "INFO" "실행 요약:"
log "INFO" "처리된 최상위 디렉터리: ${#DIRECTORIES[@]}"
log "INFO" "발견된 전체 하위 디렉터리: $total_all_dirs"
log "INFO" "발견된 숫자 디렉터리: $total_numeric_dirs"

if [ "$DRY_RUN" = true ]; then
    log "INFO" "테스트 모드에서 삭제 대상 디렉터리: $total_skipped"
    log "INFO" "실제 삭제된 디렉터리: 0 (테스트 모드)"
else
    log "SUCCESS" "삭제된 디렉터리: $total_deleted"
fi

log "SUCCESS" "스크립트 실행 완료"