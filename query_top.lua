TURN_NUMBER = 20     --每页条数
local parser = require "redis.parser"
local cjson = require "cjson"

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


local res = ngx.location.capture(
	"/zrange", { args = { query = "zrange order 0 -1\r\n"} }
	--"/zrange", { args = { query = "ping\t\n"} }
)
--local reqs = {"zrange", "order", 0, -1}
local replies = parser.parse_reply(res.body)
ngx.say(cjson.encode(res.body))
ngx.say(res.body)

--if res.status ~= 200 or not res.body then
--	ngx.log(ngx.ERR, "failed to query redis")
--	ngx.exit(500)
--end

--for i, reply in pairs(res.body) do
--	 ngx.say(reply[1])
--end



