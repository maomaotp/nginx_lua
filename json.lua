local cjson = require "cjson"
local redis = require "resty.redis"

REDIS_SERVER_IP = "127.0.0.1"
REDIS_SERVER_PORT = 6379
REDIS_TIMEOUT = 1000


function init_redis()
	red = redis:new()
    red:set_timeout(REDIS_TIMEOUT) -- 1 sec

    local ok, err = red:connect(REDIS_SERVER_IP, REDIS_SERVER_PORT)
    if not ok then
        ngx.say("failed to connect: ", err)
        return 20001
    end

	return 0
end

function query_all()
	local res,err = red:mget("inland", "hotel", "other", "foreign")
	ngx.say(cjson.encode(res))

--	if not res then
--		ngx.say("redis res: ", err)
--	end
--	ngx.say(res)
end

function main()
	init_redis()
	ngx.req.read_body()
--	local args, err = ngx.req.get_post_args()
--	for key, val in pairs(args) do
--		ngx.say(key .. ":" .. args[key])
--	end
	local data = ngx.req.get_body_data()
	--if not data then ngx.say("post data is nil") end

--	local test = '{"age":"23","testArray":{"array":[8,9,11,14,25]},"Himi":"himigame.com"}'
--	local value = cjson.decode(test)
--	if not value then ngx.say("json parse err") return end
--	ngx.say(value.age)

	query_all()
end

main()
