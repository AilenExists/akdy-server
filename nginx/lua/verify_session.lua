-- verify_session.lua
-- OpenResty access_by_lua 단계에서 실행.
-- 쿠키의 세션ID를 추출 → Redis에서 session:{id} 조회 → 검증 후
-- ngx.var.auth_user_id / auth_user_role 에 값을 세팅한다.
-- (nginx 설정에서 이 변수를 proxy_set_header로 백엔드에 주입)

local redis = require "resty.redis"
local cjson = require "cjson.safe"

-- ── 설정 ────────────────────────────────────────────
local REDIS_HOST   = "redis"        -- compose 서비스명
local REDIS_PORT   = 6379
local REDIS_TIMEOUT = 1000          -- ms (connect/read/send)
local SESSION_COOKIE = "SID"        -- 쿠키 이름 (Ktor가 발급할 이름과 일치시킬 것)
local SESSION_PREFIX = "session:"   -- Redis 키 접두사
local SESSION_TTL_RENEW = 1800      -- 슬라이딩 만료(초). 0이면 갱신 안 함

-- ── 공통: JSON 에러 응답 후 종료 ────────────────────
local function deny(status, code, message)
    ngx.status = status
    ngx.header["Content-Type"] = "application/json"
    ngx.say(cjson.encode({ error = code, message = message }))
    return ngx.exit(status)
end

-- ── 1. 쿠키에서 세션 ID 추출 ────────────────────────
-- ngx.var.cookie_<name> 으로 특정 쿠키에 바로 접근 가능
local session_id = ngx.var["cookie_" .. SESSION_COOKIE]
if not session_id or session_id == "" then
    return deny(ngx.HTTP_UNAUTHORIZED, "NO_SESSION", "세션 쿠키가 없습니다")
end

-- 세션 ID 형식 방어 (예상 밖 문자 차단 — 인젝션/오남용 방지)
if not string.match(session_id, "^[%w%-_]+$") then
    return deny(ngx.HTTP_UNAUTHORIZED, "INVALID_SESSION", "세션 형식이 올바르지 않습니다")
end

-- ── 2. Redis 연결 ───────────────────────────────────
local red = redis:new()
red:set_timeouts(REDIS_TIMEOUT, REDIS_TIMEOUT, REDIS_TIMEOUT)

local ok, err = red:connect(REDIS_HOST, REDIS_PORT)
if not ok then
    ngx.log(ngx.ERR, "redis connect failed: ", err)
    -- 인증 실패가 아니라 인프라 장애이므로 503
    return deny(ngx.HTTP_SERVICE_UNAVAILABLE, "AUTH_BACKEND_DOWN", "인증 저장소에 연결할 수 없습니다")
end

-- ── 3. 세션 조회 ────────────────────────────────────
local key = SESSION_PREFIX .. session_id
local data, err = red:get(key)

if err then
    ngx.log(ngx.ERR, "redis get failed: ", err)
    return deny(ngx.HTTP_SERVICE_UNAVAILABLE, "AUTH_BACKEND_ERROR", "세션 조회 중 오류가 발생했습니다")
end

-- ngx.null = Redis nil (키 없음 = 만료됐거나 위조된 세션)
if data == ngx.null then
    -- 연결은 풀에 반납해도 안전
    red:set_keepalive(10000, 100)
    return deny(ngx.HTTP_UNAUTHORIZED, "SESSION_EXPIRED", "세션이 만료되었거나 존재하지 않습니다")
end

-- ── 4. 세션 JSON 파싱 ───────────────────────────────
local session = cjson.decode(data)
if not session or not session.userId then
    ngx.log(ngx.ERR, "session decode failed for key: ", key)
    red:set_keepalive(10000, 100)
    return deny(ngx.HTTP_UNAUTHORIZED, "INVALID_SESSION", "세션 데이터가 손상되었습니다")
end

-- ── 5. 슬라이딩 만료(선택): 접근 시 TTL 갱신 ────────
if SESSION_TTL_RENEW > 0 then
    -- expire 실패는 치명적이지 않으므로 에러 무시
    red:expire(key, SESSION_TTL_RENEW)
end

-- ── 6. 연결 반납 (close 대신 keepalive로 풀 재사용) ──
red:set_keepalive(10000, 100)

-- ── 7. 경로 기반 인가 (admin 보호) ──────────────────
local role = session.role or "USER"
local uri = ngx.var.uri   -- 예: /api/admin/products

if string.match(uri, "^/api/admin") and role ~= "ADMIN" then
    return deny(ngx.HTTP_FORBIDDEN, "FORBIDDEN", "관리자 권한이 필요합니다")
end

-- ── 8. 검증된 값을 nginx 변수에 세팅 → 백엔드 주입 ──
-- nginx 설정에서 set $auth_user_id ''; 로 변수를 미리 선언해 둬야 함
ngx.var.auth_user_id   = tostring(session.userId)
ngx.var.auth_user_role = role

-- 여기서 함수가 끝나면 access 단계 통과 → proxy_pass 진행