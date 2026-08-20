rockspec_format = "3.0"
package = "helicopter.nvim"
version = "dev-1"
source = {
	url = "git+ssh://git@github.com/GurnoorBola/helicopter.nvim.git",
}
description = {
	summary = "Helicopter go brrr",
	detailed = "Helicopter go brrr",
	homepage = "*** please enter a project homepage ***",
	license = "*** please specify a license ***",
}
dependencies = {
	"luasocket >= 3.0",
}
build = {
	type = "builtin",
	modules = {
		["helicopter.ask"] = "lua/helicopter/ask.lua",
		["helicopter.config"] = "lua/helicopter/config.lua",
		["helicopter.init"] = "lua/helicopter/init.lua",
		["helicopter.utils"] = "lua/helicopter/utils.lua",
	},
}
