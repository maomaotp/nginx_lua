ngx.req.read_body()
local args, err = ngx.req.get_post_args()
if not args then
	ngx.say("failed to get post args: ", err)
	ngx.exit(500)
end

--redis
local type = args["type"]
local id = args["id"]
local score = args["score"]
if ( (type == nil) or (id == nil) or (score == nil) ) then
	ngx.say("post args error!")
	ngx.exit(500)
end

ngx.say("<<" .. type .. "<<" .. id .. "<<" .. score)

local res = ngx.location.capture(
	"/zincrby ", { args = { type = type, id = id, score = score} }
)

