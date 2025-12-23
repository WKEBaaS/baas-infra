-- migrate:up

CREATE TYPE api.log_level AS ENUM ('INFO', 'WARN', 'ERROR', 'FATAL');

CREATE TABLE api.logs
(
    id            uuid        DEFAULT uuidv7(),
    -- 基礎資訊
    user_id       uuid,
    action        VARCHAR(255),

    -- 錯誤分級與來源
    level         api.log_level NOT NULL,
    function_name VARCHAR(100),
    error_code    TEXT,  -- SQLSTATE (例如 P0001, 23505)

    -- 目標物件
    target_id     uuid,
    target_type   VARCHAR(100),

    -- 詳細內容與環境
    details       jsonb, -- 錯誤訊息 stack, 參數 payload
    request_info  jsonb, -- PostgREST 特有的 Header, IP, User-Agent

    timestamp     timestamptz DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_api_logs PRIMARY KEY (id)
);

-- 建議加上索引以利查詢
CREATE INDEX idx_api_logs_timestamp ON api.logs (timestamp DESC);
CREATE INDEX idx_api_logs_level ON api.logs (level);
CREATE INDEX idx_api_logs_target ON api.logs (target_id, target_type);

-- migrate:down
