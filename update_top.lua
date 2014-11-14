ngx.req.read_body()
local args, err = ngx.req.get_post_args()
if not args then
	ngx.say("failed to get post args: ", err)
	ngx.exit(500)
end

--redis
local optype = args["type"]
local id = args["id"]
local score = args["score"]
if ( (optype == nil) or (id == nil) or (score == nil) ) then
	ngx.say("post args error!")
	ngx.exit(500)
end

ngx.say("<<" .. optype .. "<<" .. id .. "<<" .. score)

local res = ngx.location.capture(
	"/zincrby", { args = { optype = optype, id = id, score = score} }
)

