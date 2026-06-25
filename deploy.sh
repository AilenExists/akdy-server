#!/bin/bash

# 스크립트 실행 중 에러가 발생하면 즉시 중단
set -e

# --- [설정 변수] 본인의 서버 정보에 맞게 수정하세요 ---
SERVER_USER="shaper"
SERVER_IP="122.153.79.24"
TARGET_DIR="/home/$SERVER_USER/AKDYMALL-PROJECT"
# --------------------------------------------------

echo "[ 배포 자동화 스크립트를 시작합니다. ]"
echo -e "\n"
echo "==================================================="
echo "1. 로컬 PC에서 빌드 수행"
echo "==================================================="
echo -e "\n"
echo "[ 백엔드 (Ktor 서비스 서버) 빌드 중... ]"
echo -e "\n"
cd backend
./gradlew buildFatJar
cd ..
echo -e "\n"
echo "[ 프론트엔드 (Next.js) 빌드 중... ]"
echo -e "\n"
cd frontend
npm run build
cd ..
echo -e "\n"
echo "[ 모든 빌드가 성공적으로 완료되었습니다. ]"
echo -e "\n"
echo "==================================================="
echo "2. 서버에 디렉토리 구조 생성 및 파일 전송 (rsync)"
echo "==================================================="
echo -e "\n"

# 원격 서버에 필요한 디렉토리 구조 미리 생성
ssh $SERVER_USER@$SERVER_IP "mkdir -p $TARGET_DIR/nginx $TARGET_DIR/backend/auth/build/libs $TARGET_DIR/backend/build/libs $TARGET_DIR/frontend/.next $TARGET_DIR/frontend/public"

# 루트 설정 파일 및 Nginx 전송
rsync -avz ./docker-compose.yml $SERVER_USER@$SERVER_IP:$TARGET_DIR/
rsync -avz ./nginx/nginx.conf $SERVER_USER@$SERVER_IP:$TARGET_DIR/nginx/

# 백엔드 서버 (Dockerfile 및 jar 파일)
rsync -avz ./backend/Dockerfile $SERVER_USER@$SERVER_IP:$TARGET_DIR/backend/
rsync -avz ./backend/build/libs/ $SERVER_USER@$SERVER_IP:$TARGET_DIR/backend/build/libs/

# 프론트엔드 서버 (Dockerfile 및 Next.js standalone 빌드 결과물)
rsync -avz ./frontend/Dockerfile $SERVER_USER@$SERVER_IP:$TARGET_DIR/frontend/
rsync -avz ./frontend/public/ $SERVER_USER@$SERVER_IP:$TARGET_DIR/frontend/public/
rsync -avz ./frontend/.next/static/ $SERVER_USER@$SERVER_IP:$TARGET_DIR/frontend/.next/static/
rsync -avz ./frontend/.next/standalone/ $SERVER_USER@$SERVER_IP:$TARGET_DIR/frontend/.next/standalone/

rsync -avz ./.secrets/.env $SERVER_USER@$SERVER_IP:$TARGET_DIR/.secrets/

echo -e "\n"
echo "[ 서버 파일 전송이 완료되었습니다. ]"
echo -e "\n"
echo "==================================================="
echo "3. 원격 서버에서 Docker 컨테이너 실행"
echo "==================================================="
echo -e "\n"

# 서버 내부로 이동하여 컨테이너 빌드 및 백그라운드 실행
ssh $SERVER_USER@$SERVER_IP "cd $TARGET_DIR && docker compose up -d --build"
echo -e "\n"
echo "[ 배포가 성공적으로 완료되었습니다. ]"