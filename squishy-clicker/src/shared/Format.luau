--!strict
-- Turns big numbers into short readable ones: 1500 -> "1.5K", 2000000 -> "2M".

local Format = {}

local suffixes = { "", "K", "M", "B", "T", "Qa", "Qi" }

function Format.abbreviate(n: number): string
	local i = 1
	while n >= 1000 and i < #suffixes do
		n /= 1000
		i += 1
	end
	if i == 1 then
		return tostring(math.floor(n))
	end
	-- one decimal place, but drop a trailing ".0"
	local text = string.format("%.1f", n)
	text = text:gsub("%.0$", "")
	return text .. suffixes[i]
end

return Format
