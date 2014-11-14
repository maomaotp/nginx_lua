TURN_NUMBER = 20     --每页条数
local parser = require "redis.parser"

--ngx.req.read_body()
--local args, err = ngx.req.get_post_args()
--if not args then
--	ngx.say("failed to get post args: ", err)
--	ngx.exit(500)
--end
--
--local optype = args["optype"]
--local page = args["page"]
--
--if not page then
--	page = "1"
--end
--
--page = ( tonumber(page) - 1 ) * 20;
--local turn_num = tonumber(page) + TURN_NUMBER 
--
--ngx.say(">>>>>>" .. page .. ">>>>" .. turn_num)

local reqs = {
	--{"zrange", optype, page, turn_num},
	{"zrange", "order", 0, 20},
}

local raw_reqs = {}
for i, req in ipairs(reqs) do
	table.insert(raw_reqs, parser.build_query(req))
end

local res = ngx.location.capture(
	"/redisquery?" .. #reqs, { body = table.concat(raw_reqs, "") } )

if res.status ~= 200 or not res.body then
	ngx.log(ngx.ERR, "failed to query redis")
	ngx.exit(500)
end

local replies = parser.parse_replies(res.body, #reqs)
for i, reply in pairs(replies) do
	ngx.say(reply[1])
end



