--!strict
--!optimize 2
local Bnum = {}
local ln10 = 2.302585092994046
local pow10 = {}
for i = -308, 308 do
	pow10[i] = math.pow(10, i)
end

function Bnum.new(man: number?, exp: number?): buffer
	local buff = buffer.create(12)
	if not man or not exp then
		return buff
	end
	buffer.writef64(buff, 0, man)
	buffer.writei32(buff, 8, exp)
	return buff
end

Bnum.zero = Bnum.new()
Bnum.one = Bnum.new(1, 0)
Bnum.inf = Bnum.new(1, math.huge)
Bnum.ninf = Bnum.new(-1, math.huge)
Bnum.nan = Bnum.new(0/0, 0/0)

function Bnum.read(val: any): (number, number)
	if type(val) == "buffer" then
		return buffer.readf64(val, 0), buffer.readi32(val, 8)
	end
	if type(val) == "number" then
		if val == 0 then
			return 0, 0
		end
		if val ~= val then
			return 0/0, 0
		end
		if val == math.huge then
			return 1, math.huge
		end
		if val == -math.huge then
			return -1, math.huge
		end
		local absn = math.abs(val)
		if absn >= 1e10 or absn <= 1e-10 then
			local e = math.floor(math.log10(absn))
			return val / pow10[e], e
		end
		return val, 0
	end
	if type(val) == "string" then
		local len = #val
		if len == 0 then
			return 0/0, 0
		end
		local i = 1
		local sign = 1
		local c = string.byte(val, i)
		if c == 45 then
			sign = -1; i += 1
		elseif c == 43 then
			i += 1
		end
		local mant = 0
		local mantDigits = 0
		local exp = 0
		local frac = false
		while i <= len do
			c = string.byte(val, i)
			if c >= 48 and c <= 57 then
				if mantDigits < 17 then
					mant = mant * 10 + (c - 48)
					mantDigits += 1
				else
					exp += 1
				end
				if frac then exp -= 1 end
			elseif c == 46 then
				if frac then break end
				frac = true
			elseif c == 101 or c == 69 then
				i += 1
				break
			else
				break
			end
			i += 1
		end
		if i <= len then
			local esign = 1
			c = string.byte(val, i)
			if c == 45 then esign = -1; i += 1
			elseif c == 43 then i += 1 end
			local e = 0
			while i <= len do
				c = string.byte(val, i)
				if c < 48 or c > 57 then break end
				e = e * 10 + (c - 48)
				i += 1
			end
			exp += e * esign
		end
		if mant == 0 then
			return 0, 0
		end
		local m = mant * pow10[-(mantDigits - 1)]
		return sign * m, exp + mantDigits - 1
	end
	error("Bnum.read: invalid type autocorrected to zero")
	return 0, 0
end

function Bnum.write(buff: buffer, man: number, exp: number): buffer
	buffer.writef64(buff, 0, man)
	buffer.writei32(buff, 8, exp)
	return buff
end

function Bnum.fromNumber(n: number): buffer
	local buf = buffer.create(12)
	if n == 0 then
		buffer.writef64(buf, 0, 0)
		buffer.writei32(buf, 8, 0)
		return buf
	end
	if n ~= n then
		buffer.writef64(buf, 0, -1)
		buffer.writei32(buf, 8, 1)
		return buf
	end
	local exp = math.floor(math.log10(n))
	local man = n/pow10[exp]
	buffer.writef64(buf, 0, man)
	buffer.writei32(buf, 8, exp)
	return buf
end

function Bnum.fromString(str: string): buffer
	local out = buffer.create(12)
	local len = #str
	if len == 0 then
		buffer.writef64(out, 0, 0/0)
		buffer.writei32(out, 8, 0)
		return out
	end
	local i = 1
	local sign = 1
	local c = string.byte(str, i)
	if c == 45 then
		sign = -1
		i += 1
	elseif c == 43 then
		i += 1
	end
	local mant = 0
	local mantDigits = 0
	local exp = 0
	local frac = false
	while i <= len do
		c = string.byte(str, i)
		if c >= 48 and c <= 57 then
			if mantDigits < 17 then
				mant = mant * 10 + (c - 48)
				mantDigits += 1
			else
				exp += 1
			end
			if frac then
				exp -= 1
			end
		elseif c == 46 then
			if frac then break end
			frac = true
		elseif c == 101 or c == 69 then
			i += 1
			break
		else
			break
		end
		i += 1
	end
	if i <= len then
		local esign = 1
		c = string.byte(str, i)
		if c == 45 then
			esign = -1
			i += 1
		elseif c == 43 then
			i += 1
		end
		local e = 0
		while i <= len do
			c = string.byte(str, i)
			if c < 48 or c > 57 then break end
			e = e * 10 + (c - 48)
			i += 1
		end
		exp += e * esign
	end
	if mant == 0 then
		buffer.writef64(out, 0, 0)
		buffer.writei32(out, 8, 0)
		return out
	end
	local m = mant * (pow10[-(mantDigits - 1)])
	buffer.writef64(out, 0, sign * m)
	buffer.writei32(out, 8, exp + mantDigits - 1)
	return out
end

function convert(val: any): buffer
	if type(val) == 'number' then
		local b = buffer.create(12)
		if val == 0 then
			buffer.writef64(b, 0, 0)
			buffer.writei32(b, 8, 0)
			return b
		end
		if val ~= val then
			buffer.writef64(b, 0, -1)
			buffer.writei32(b, 8, 1)
			return b
		end
		if val == math.huge then
			buffer.writef64(b, 0, 1)
			buffer.writei32(b, 8, math.huge)
			return b
		elseif val == -math.huge then
			buffer.writef64(b, 0, -1)
			buffer.writei32(b, 8, math.huge)
			return b
		end
		local man, exp = val, 0
		if man >= 10 then
			man, exp = man * 0.1, exp + 1
		elseif man < 1 and man > 0 then
			man, exp = man * 10, exp - 1
		elseif man > -1 and man < 0 then
			man, exp = man * 10, exp - 1
		else
			man, exp = man, exp
		end
		buffer.writef64(b, 0, man)
		buffer.writei32(b, 8, exp)
		return b
	elseif type(val) == 'string' then
		local out = buffer.create(12)
		local len = #val
		if len == 0 then
			buffer.writef64(out, 0, 0/0)
			buffer.writei32(out, 8, 0)
			return out
		end
		local i = 1
		local sign = 1
		local c = string.byte(val, i)
		if c == 45 then
			sign = -1
			i += 1
		elseif c == 43 then
			i += 1
		end
		local mant = 0
		local mantDigits = 0
		local exp = 0
		local frac = false
		while i <= len do
			c = string.byte(val, i)
			if c >= 48 and c <= 57 then
				if mantDigits < 17 then
					mant = mant * 10 + (c - 48)
					mantDigits += 1
				else
					exp += 1
				end
				if frac then
					exp -= 1
				end
			elseif c == 46 then
				if frac then break end
				frac = true
			elseif c == 101 or c == 69 then
				i += 1
				break
			else
				break
			end
			i += 1
		end
		if i <= len then
			local esign = 1
			c = string.byte(val, i)
			if c == 45 then
				esign = -1
				i += 1
			elseif c == 43 then
				i += 1
			end
			local e = 0
			while i <= len do
				c = string.byte(val, i)
				if c < 48 or c > 57 then break end
				e = e * 10 + (c - 48)
				i += 1
			end
			exp += e * esign
		end
		if mant == 0 then
			buffer.writef64(out, 0, 0)
			buffer.writei32(out, 8, 0)
			return out
		end
		buffer.writef64(out, 0, sign * mant * (pow10[-(mantDigits - 1)]))
		buffer.writei32(out, 8, exp + mantDigits - 1)
		return out
	end
	local out = buffer.create(12)
	warn(`Failed to convert to buffer corrected to {out}`)
	return out
end

function Bnum.toString(val: any): string
	local man, exp
	if type(val) == "buffer" then
		man = buffer.readf64(val, 0)
		exp = buffer.readi32(val, 8)
	elseif type(val) == "number" then
		return tostring(val)
	else
		error("Bnum.toString: invalid type")
	end
	if man ~= man or exp ~= exp then return "nan" end
	if exp == math.huge then
		return (man < 0 and "-inf" or "inf")
	end
	if man == 0 then return "0" end
	return tostring(man) .. "e" .. tostring(exp)
end

function Bnum.toNumber(buff: buffer): number
	local man, exp = Bnum.read(buff)
	return man * pow10[exp]
end

function Bnum.add(val1: any, val2: any): buffer
	local m1: number, e1: number
	local m2: number, e2: number
	if type(val1) == "buffer" then
		m1, e1 = buffer.readf64(val1, 0), buffer.readi32(val1, 8)
	elseif type(val1) == "number" then
		if val1 == 0 then m1, e1 = 0,0
		elseif val1 ~= val1 then m1, e1 = 0/0,0
		elseif val1 == math.huge then m1, e1 = 1, math.huge
		elseif val1 == -math.huge then m1, e1 = -1, math.huge
		else
			local absn = math.abs(val1)
			if absn >= 1e10 or absn <= 1e-10 then
				local e = math.floor(math.log10(absn))
				m1, e1 = val1 / pow10[e], e
			else
				m1, e1 = val1, 0
			end
		end
	elseif type(val1) == "string" then
		local len = #val1
		if len == 0 then m1, e1 = 0/0, 0 end
		local i = 1
		local sign = 1
		local c = string.byte(val1, i)
		if c == 45 then sign = -1; i += 1
		elseif c == 43 then i += 1 end
		local mant = 0
		local mantDigits = 0
		local exp = 0
		local frac = false
		local b = string.byte
		while i <= len do
			c = b(val1, i)
			if c >= 48 and c <= 57 then
				if mantDigits < 17 then
					mant = mant * 10 + (c - 48)
					mantDigits += 1
				else
					exp += 1
				end
				if frac then exp -= 1 end
			elseif c == 46 then
				if frac then break end
				frac = true
			elseif c == 69 or c == 101 then
				i += 1
				break
			else
				break
			end
			i += 1
		end
		if i <= len then
			local esign = 1
			c = b(val1, i)
			if c == 45 then esign = -1; i += 1
			elseif c == 43 then i += 1 end

			local e = 0
			while i <= len do
				c = b(val1, i)
				if c < 48 or c > 57 then break end
				e = e * 10 + (c - 48)
				i += 1
			end
			exp += e * esign
		end
		if mant == 0 then m1, e1= 0,0 end
		local m = mant * pow10[-(mantDigits-1)]
		m1, e1 = sign * m, exp + mantDigits - 1
	end
	if m1 == nil or e1 == nil then m1, e1 = 0,0 end
	if type(val2) == "buffer" then
		m2, e2 = buffer.readf64(val2, 0), buffer.readi32(val2, 8)
	elseif type(val2) == "number" then
		if val2 == 0 then m2, e2 = 0,0
		elseif val2 ~= val2 then m2, e2 = 0/0,0
		elseif val2 == math.huge then m2, e2 = 1, math.huge
		elseif val2 == -math.huge then m2, e2 = -1, math.huge
		else
			local absn = math.abs(val2)
			if absn >= 1e10 or absn <= 1e-10 then
				local e = math.floor(math.log10(absn))
				m2, e2 = val2 / pow10[e], e
			else
				m2, e2 = val2, 0
			end
		end
	elseif type(val2) == "string" then
		local len = #val2
		if len == 0 then m2, e2 = 0/0, 0 end
		local i = 1
		local sign = 1
		local c = string.byte(val2, i)
		if c == 45 then sign = -1; i += 1
		elseif c == 43 then i += 1 end
		local mant = 0
		local mantDigits = 0
		local exp = 0
		local frac = false
		local b = string.byte
		while i <= len do
			c = b(val2, i)
			if c >= 48 and c <= 57 then
				if mantDigits < 17 then
					mant = mant * 10 + (c - 48)
					mantDigits += 1
				else
					exp += 1
				end
				if frac then exp -= 1 end
			elseif c == 46 then
				if frac then break end
				frac = true
			elseif c == 69 or c == 101 then
				i += 1
				break
			else
				break
			end
			i += 1
		end
		if i <= len then
			local esign = 1
			c = b(val2, i)
			if c == 45 then esign = -1; i += 1
			elseif c == 43 then i += 1 end
			local e = 0
			while i <= len do
				c = b(val2, i)
				if c < 48 or c > 57 then break end
				e = e * 10 + (c - 48)
				i += 1
			end
			exp += e * esign
		end
		if mant == 0 then m2, e2 = 0,0 end
		local m = mant * pow10[-(mantDigits-1)]
		m2, e2 = sign * m, exp + mantDigits - 1
	end
	if m2 == nil or e2 == nil then m2, e2 = 0,0 end
	if m1 == 0 then return Bnum.new(m2,e2) end
	if m2 == 0 then return Bnum.new(m1,e1) end
	local de = e1 - e2
	if de >= 13 then return Bnum.new(m1,e1) end
	if de <= -13 then return Bnum.new(m2,e2) end
	if de > 0 then
		m2 *= pow10[-de]
		e2 = e1
	elseif de < 0 then
		m1 *= pow10[de]
		e1 = e2
	end
	local m = m1 + m2
	if m == 0 then return Bnum.zero end
	local am = math.abs(m)
	local e = math.floor(math.log10(m))
	m /= pow10[e]
	local out = buffer.create(12)
	buffer.writef64(out, 0, m)
	buffer.writei32(out, 8, e)
	return out
end

function Bnum.sub(val1: any, val2: any): buffer
	local m1: number, e1: number
	local m2: number, e2: number
	if type(val1) == "buffer" then
		m1, e1 = buffer.readf64(val1, 0), buffer.readi32(val1, 8)
	elseif type(val1) == "number" then
		if val1 == 0 then m1, e1 = 0,0
		elseif val1 ~= val1 then m1, e1 = 0/0,0
		elseif val1 == math.huge then m1, e1 = 1, math.huge
		elseif val1 == -math.huge then m1, e1 = -1, math.huge
		else
			local absn = math.abs(val1)
			if absn >= 1e10 or absn <= 1e-10 then
				local e = math.floor(math.log10(absn))
				m1, e1 = val1 / pow10[e], e
			else
				m1, e1 = val1, 0
			end
		end
	elseif type(val1) == "string" then
		local len = #val1
		if len == 0 then m1, e1 = 0/0, 0 end
		local i = 1
		local sign = 1
		local c = string.byte(val1, i)
		if c == 45 then sign = -1; i += 1
		elseif c == 43 then i += 1 end
		local mant = 0
		local mantDigits = 0
		local exp = 0
		local frac = false
		local b = string.byte
		while i <= len do
			c = b(val1, i)
			if c >= 48 and c <= 57 then
				if mantDigits < 17 then
					mant = mant * 10 + (c - 48)
					mantDigits += 1
				else
					exp += 1
				end
				if frac then exp -= 1 end
			elseif c == 46 then
				if frac then break end
				frac = true
			elseif c == 69 or c == 101 then
				i += 1
				break
			else
				break
			end
			i += 1
		end
		if i <= len then
			local esign = 1
			c = b(val1, i)
			if c == 45 then esign = -1; i += 1
			elseif c == 43 then i += 1 end
			local e = 0
			while i <= len do
				c = b(val1, i)
				if c < 48 or c > 57 then break end
				e = e * 10 + (c - 48)
				i += 1
			end
			exp += e * esign
		end
		if mant == 0 then m1, e1= 0,0 end
		local m = mant * pow10[-(mantDigits-1)]
		m1, e1 = sign * m, exp + mantDigits - 1
	end
	if m1 == nil or e1 == nil then m1, e1 = 0,0 end
	if type(val2) == "buffer" then
		m2, e2 = buffer.readf64(val2, 0), buffer.readi32(val2, 8)
	elseif type(val2) == "number" then
		if val2 == 0 then m2, e2 = 0,0
		elseif val2 ~= val2 then m2, e2 = 0/0,0
		elseif val2 == math.huge then m2, e2 = 1, math.huge
		elseif val2 == -math.huge then m2, e2 = -1, math.huge
		else
			local absn = math.abs(val2)
			if absn >= 1e10 or absn <= 1e-10 then
				local e = math.floor(math.log10(absn))
				m2, e2 = val2 / pow10[e], e
			else
				m2, e2 = val2, 0
			end
		end
	elseif type(val2) == "string" then
		local len = #val2
		if len == 0 then m2, e2 = 0/0, 0 end
		local i = 1
		local sign = 1
		local c = string.byte(val2, i)
		if c == 45 then sign = -1; i += 1
		elseif c == 43 then i += 1 end
		local mant = 0
		local mantDigits = 0
		local exp = 0
		local frac = false
		local b = string.byte
		while i <= len do
			c = b(val2, i)
			if c >= 48 and c <= 57 then
				if mantDigits < 17 then
					mant = mant * 10 + (c - 48)
					mantDigits += 1
				else
					exp += 1
				end
				if frac then exp -= 1 end
			elseif c == 46 then
				if frac then break end
				frac = true
			elseif c == 69 or c == 101 then
				i += 1
				break
			else
				break
			end
			i += 1
		end
		if i <= len then
			local esign = 1
			c = b(val2, i)
			if c == 45 then esign = -1; i += 1
			elseif c == 43 then i += 1 end
			local e = 0
			while i <= len do
				c = b(val2, i)
				if c < 48 or c > 57 then break end
				e = e * 10 + (c - 48)
				i += 1
			end
			exp += e * esign
		end
		if mant == 0 then m2, e2 = 0,0 end
		local m = mant * pow10[-(mantDigits-1)]
		m2, e2 = sign * m, exp + mantDigits - 1
	end
	if m2 == nil or e2 == nil then m2, e2 = 0,0 end
	local de = e1 - e2
	if de >= 13 then return Bnum.new(m1,e1) end
	if de <= -13 then return Bnum.new(m2,e2) end
	if de > 0 then
		m2 *= pow10[-de]
		e2 = e1
	elseif de < 0 then
		m1 *= pow10[de]
		e1 = e2
	end
	local m = m1 - m2
	local e = e1
	if m <= 0 then
		return Bnum.zero
	end
	local exp = math.floor(math.log10(m))
	local man = m/pow10[exp]
	local out = buffer.create(12)
	buffer.writef64(out, 0, man)
	buffer.writei32(out, 8, exp)
	return out
end

function Bnum.mul(val1: any, val2: any): buffer
	local m1: number, e1: number
	local m2: number, e2: number
	if type(val1) == "buffer" then
		m1, e1 = buffer.readf64(val1, 0), buffer.readi32(val1, 8)
	elseif type(val1) == "number" then
		if val1 == 0 then m1, e1 = 0,0
		elseif val1 ~= val1 then m1, e1 = 0/0,0
		elseif val1 == math.huge then m1, e1 = 1, math.huge
		elseif val1 == -math.huge then m1, e1 = -1, math.huge
		else
			local absn = math.abs(val1)
			if absn >= 1e10 or absn <= 1e-10 then
				local e = math.floor(math.log10(absn))
				m1, e1 = val1 / pow10[e], e
			else
				m1, e1 = val1, 0
			end
		end
	elseif type(val1) == "string" then
		local len = #val1
		local i, sign, mant, mantDigits, exp, frac = 1, 1, 0, 0, 0, false
		local b = string.byte
		if string.byte(val1, i) == 45 then sign = -1; i += 1
		elseif string.byte(val1, i) == 43 then i += 1 end
		while i <= len do
			local c = b(val1, i)
			if c >= 48 and c <= 57 then
				if mantDigits < 17 then mant = mant * 10 + (c-48); mantDigits += 1
				else exp += 1 end
				if frac then exp -= 1 end
			elseif c == 46 then
				if frac then break end
				frac = true
			elseif c == 69 or c == 101 then i += 1; break
			else break end
			i += 1
		end
		if i <= len then
			local esign = 1
			local c = b(val1, i)
			if c == 45 then esign = -1; i += 1
			elseif c == 43 then i += 1 end
			local e = 0
			while i <= len do
				c = b(val1, i)
				if c < 48 or c > 57 then break end
				e = e * 10 + (c-48)
				i += 1
			end
			exp += e * esign
		end
		if mant == 0 then m1, e1 = 0,0
		else
			local m = mant * pow10[-(mantDigits-1)]
			m1, e1 = sign * m, exp + mantDigits - 1
		end
	end
	if m1 == nil or e1 == nil then m1, e1 = 0,0 end
	if type(val2) == "buffer" then
		m2, e2 = buffer.readf64(val2, 0), buffer.readi32(val2, 8)
	elseif type(val2) == "number" then
		if val2 == 0 then m2, e2 = 0,0
		elseif val2 ~= val2 then m2, e2 = 0/0,0
		elseif val2 == math.huge then m2, e2 = 1, math.huge
		elseif val2 == -math.huge then m2, e2 = -1, math.huge
		else
			local absn = math.abs(val2)
			if absn >= 1e10 or absn <= 1e-10 then
				local e = math.floor(math.log10(absn))
				m2, e2 = val2 / pow10[e], e
			else
				m2, e2 = val2, 0
			end
		end
	elseif type(val2) == "string" then
		local len = #val2
		local i, sign, mant, mantDigits, exp, frac = 1, 1, 0, 0, 0, false
		local b = string.byte
		if string.byte(val2, i) == 45 then sign = -1; i += 1
		elseif string.byte(val2, i) == 43 then i += 1 end
		while i <= len do
			local c = b(val2, i)
			if c >= 48 and c <= 57 then
				if mantDigits < 17 then mant = mant*10 + (c-48); mantDigits += 1
				else exp += 1 end
				if frac then exp -= 1 end
			elseif c == 46 then
				if frac then break end
				frac = true
			elseif c == 69 or c == 101 then i += 1; break
			else break end
			i += 1
		end
		if i <= len then
			local esign = 1
			local c = b(val2, i)
			if c == 45 then esign = -1; i += 1
			elseif c == 43 then i += 1 end
			local e = 0
			while i <= len do
				c = b(val2, i)
				if c < 48 or c > 57 then break end
				e = e*10 + (c-48)
				i += 1
			end
			exp += e * esign
		end
		if mant == 0 then m2, e2 = 0,0
		else
			local m = mant * pow10[-(mantDigits-1)]
			m2, e2 = sign * m, exp + mantDigits - 1
		end
	end
	if m2 == nil or e2 == nil then m2, e2 = 0,0 end
	local m = m1 * m2
	local e = e1 + e2
	local am = math.abs(m)
	local exp = math.floor(math.log10(m))
	local man = m/pow10[exp]
	local out = buffer.create(12)
	buffer.writef64(out, 0, man)
	buffer.writei32(out, 8, exp)
	return out
end

function Bnum.recip(val1: any): buffer
	local m: number, e: number
	if type(val1) == "buffer" then
		m, e = buffer.readf64(val1, 0), buffer.readi32(val1, 8)
	elseif type(val1) == "number" then
		if val1 == 0 then m, e = 0,0
		elseif val1 ~= val1 then m, e = 0/0,0
		elseif val1 == math.huge then m, e = 1, math.huge
		elseif val1 == -math.huge then m, e = -1, math.huge
		else
			local absn = math.abs(val1)
			if absn >= 1e10 or absn <= 1e-10 then
				local expv = math.floor(math.log10(absn))
				m, e = val1 / pow10[expv], expv
			else
				m, e = val1, 0
			end
		end
	elseif type(val1) == "string" then
		local len = #val1
		local i, sign, mant, mantDigits, exp, frac = 1, 1, 0, 0, 0, false
		local b = string.byte
		if b(val1,i) == 45 then sign = -1; i += 1
		elseif b(val1,i) == 43 then i += 1 end
		while i <= len do
			local c = b(val1,i)
			if c >= 48 and c <= 57 then
				if mantDigits < 17 then mant = mant*10 + (c-48); mantDigits += 1
				else exp += 1 end
				if frac then exp -= 1 end
			elseif c == 46 then
				if frac then break end
				frac = true
			elseif c == 69 or c == 101 then i += 1; break
			else break end
			i += 1
		end
		if i <= len then
			local esign = 1
			local c = b(val1,i)
			if c == 45 then esign = -1; i += 1
			elseif c == 43 then i += 1 end
			local e2 = 0
			while i <= len do
				c = b(val1,i)
				if c < 48 or c > 57 then break end
				e2 = e2*10 + (c-48)
				i += 1
			end
			exp += e2 * esign
		end
		if mant == 0 then m, e = 0,0
		else
			local m2 = mant * pow10[-(mantDigits-1)]
			m, e = sign * m2, exp + mantDigits - 1
		end
	end
	if m == nil or e == nil then m, e = 0,0 end
	if m == 0 then error("Bnum.recip: division by zero") end
	local rMan = 1 / m
	local rExp = -e
	local absMan = math.abs(rMan)
	if absMan >= 10 or absMan < 1 then
		local delta = math.floor(math.log10(absMan))
		rMan = rMan / pow10[delta]
		rExp = rExp + delta
	end
	local out = buffer.create(12)
	buffer.writef64(out, 0, rMan)
	buffer.writei32(out, 8, rExp)
	return out
end

function Bnum.div(val1: any, val2: any): buffer
	local m1: number, e1: number
	local m2: number, e2: number
	if type(val1) == "buffer" then
		m1, e1 = buffer.readf64(val1, 0), buffer.readi32(val1, 8)
	elseif type(val1) == "number" then
		if val1 == 0 then m1, e1 = 0,0
		elseif val1 ~= val1 then m1, e1 = 0/0,0
		elseif val1 == math.huge then m1, e1 = 1, math.huge
		elseif val1 == -math.huge then m1, e1 = -1, math.huge
		else
			local absn = math.abs(val1)
			if absn >= 1e10 or absn <= 1e-10 then
				local e = math.floor(math.log10(absn))
				m1, e1 = val1 / pow10[e], e
			else
				m1, e1 = val1, 0
			end
		end
	elseif type(val1) == "string" then
		local len = #val1
		local i, sign, mant, mantDigits, exp, frac = 1, 1, 0, 0, 0, false
		local b = string.byte
		if string.byte(val1, i) == 45 then sign = -1; i += 1
		elseif string.byte(val1, i) == 43 then i += 1 end
		while i <= len do
			local c = b(val1, i)
			if c >= 48 and c <= 57 then
				if mantDigits < 17 then mant = mant * 10 + (c-48); mantDigits += 1
				else exp += 1 end
				if frac then exp -= 1 end
			elseif c == 46 then
				if frac then break end
				frac = true
			elseif c == 69 or c == 101 then i += 1; break
			else break end
			i += 1
		end
		if i <= len then
			local esign = 1
			local c = b(val1, i)
			if c == 45 then esign = -1; i += 1
			elseif c == 43 then i += 1 end
			local e = 0
			while i <= len do
				c = b(val1, i)
				if c < 48 or c > 57 then break end
				e = e*10 + (c-48)
				i += 1
			end
			exp += e * esign
		end
		if mant == 0 then m1, e1 = 0,0
		else
			local m = mant * pow10[-(mantDigits-1)]
			m1, e1 = sign * m, exp + mantDigits - 1
		end
	end
	if m1 == nil or e1 == nil then m1, e1 = 0,0 end
	if type(val2) == "buffer" then
		m2, e2 = buffer.readf64(val2, 0), buffer.readi32(val2, 8)
	elseif type(val2) == "number" then
		if val2 == 0 then m2, e2 = 0,0
		elseif val2 ~= val2 then m2, e2 = 0/0,0
		elseif val2 == math.huge then m2, e2 = 1, math.huge
		elseif val2 == -math.huge then m2, e2 = -1, math.huge
		else
			local absn = math.abs(val2)
			if absn >= 1e10 or absn <= 1e-10 then
				local e = math.floor(math.log10(absn))
				m2, e2 = val2 / pow10[e], e
			else
				m2, e2 = val2, 0
			end
		end
	elseif type(val2) == "string" then
		local len = #val2
		local i, sign, mant, mantDigits, exp, frac = 1, 1, 0, 0, 0, false
		local b = string.byte
		if string.byte(val2, i) == 45 then sign = -1; i += 1
		elseif string.byte(val2, i) == 43 then i += 1 end
		while i <= len do
			local c = b(val2, i)
			if c >= 48 and c <= 57 then
				if mantDigits < 17 then mant = mant*10 + (c-48); mantDigits += 1
				else exp += 1 end
				if frac then exp -= 1 end
			elseif c == 46 then
				if frac then break end
				frac = true
			elseif c == 69 or c == 101 then i += 1; break
			else break end
			i += 1
		end
		if i <= len then
			local esign = 1
			local c = b(val2, i)
			if c == 45 then esign = -1; i += 1
			elseif c == 43 then i += 1 end
			local e = 0
			while i <= len do
				c = b(val2, i)
				if c < 48 or c > 57 then break end
				e = e*10 + (c-48)
				i += 1
			end
			exp += e * esign
		end
		if mant == 0 then m2, e2 = 0,0
		else
			local m = mant * pow10[-(mantDigits-1)]
			m2, e2 = sign * m, exp + mantDigits - 1
		end
	end
	if m2 == nil or e2 == nil then m2, e2 = 0,0 end
	if m1 == 0 then return Bnum.zero end
	if m2 == 0 then error("Bnum.div: division by zero") end
	local m = m1 / m2
	local e = e1 - e2
	local am = math.abs(m)
	local exp = math.floor(math.log10(m))
	local man = m/pow10[exp]
	local out = buffer.create(12)
	buffer.writef64(out, 0, man)
	buffer.writei32(out, 8, exp)
	return out
end

function Bnum.pow(val1: any, val2: any): buffer
	local m1: number, e1: number
	local m2: number, e2: number
	if type(val1) == "buffer" then
		m1, e1 = buffer.readf64(val1, 0), buffer.readi32(val1, 8)
	elseif type(val1) == "number" then
		if val1 == 0 then m1, e1 = 0,0
		elseif val1 ~= val1 then m1, e1 = 0/0,0
		elseif val1 == math.huge then m1, e1 = 1, math.huge
		elseif val1 == -math.huge then m1, e1 = -1, math.huge
		else
			local absn = math.abs(val1)
			if absn >= 1e10 or absn <= 1e-10 then
				local e = math.floor(math.log10(absn))
				m1, e1 = val1 / pow10[e], e
			else
				m1, e1 = val1, 0
			end
		end
	elseif type(val1) == "string" then
		local len = #val1
		local i, sign, mant, mantDigits, exp, frac = 1, 1, 0, 0, 0, false
		local b = string.byte
		if string.byte(val1, i) == 45 then sign = -1; i += 1
		elseif string.byte(val1, i) == 43 then i += 1 end
		while i <= len do
			local c = b(val1, i)
			if c >= 48 and c <= 57 then
				if mantDigits < 17 then mant = mant * 10 + (c-48); mantDigits += 1
				else exp += 1 end
				if frac then exp -= 1 end
			elseif c == 46 then
				if frac then break end
				frac = true
			elseif c == 69 or c == 101 then i += 1; break
			else break end
			i += 1
		end
		if i <= len then
			local esign = 1
			local c = b(val1, i)
			if c == 45 then esign = -1; i += 1
			elseif c == 43 then i += 1 end
			local e = 0
			while i <= len do
				c = b(val1, i)
				if c < 48 or c > 57 then break end
				e = e*10 + (c-48)
				i += 1
			end
			exp += e * esign
		end
		if mant == 0 then m1, e1 = 0,0
		else
			local m = mant * pow10[-(mantDigits-1)]
			m1, e1 = sign * m, exp + mantDigits - 1
		end
	end
	if m1 == nil or e1 == nil then m1, e1 = 0,0 end
	if type(val2) == "buffer" then
		m2, e2 = buffer.readf64(val2, 0), buffer.readi32(val2, 8)
	elseif type(val2) == "number" then
		if val2 == 0 then m2, e2 = 0,0
		elseif val2 ~= val2 then m2, e2 = 0/0,0
		elseif val2 == math.huge then m2, e2 = 1, math.huge
		elseif val2 == -math.huge then m2, e2 = -1, math.huge
		else
			local absn = math.abs(val2)
			if absn >= 1e10 or absn <= 1e-10 then
				local e = math.floor(math.log10(absn))
				m2, e2 = val2 / pow10[e], e
			else
				m2, e2 = val2, 0
			end
		end
	elseif type(val2) == "string" then
		local len = #val2
		local i, sign, mant, mantDigits, exp, frac = 1, 1, 0, 0, 0, false
		local b = string.byte
		if string.byte(val2, i) == 45 then sign = -1; i += 1
		elseif string.byte(val2, i) == 43 then i += 1 end
		while i <= len do
			local c = b(val2, i)
			if c >= 48 and c <= 57 then
				if mantDigits < 17 then mant = mant*10 + (c-48); mantDigits += 1
				else exp += 1 end
				if frac then exp -= 1 end
			elseif c == 46 then
				if frac then break end
				frac = true
			elseif c == 69 or c == 101 then i += 1; break
			else break end
			i += 1
		end
		if i <= len then
			local esign = 1
			local c = b(val2, i)
			if c == 45 then esign = -1; i += 1
			elseif c == 43 then i += 1 end
			local e = 0
			while i <= len do
				c = b(val2, i)
				if c < 48 or c > 57 then break end
				e = e*10 + (c-48)
				i += 1
			end
			exp += e * esign
		end
		if mant == 0 then m2, e2 = 0,0
		else
			local m = mant * pow10[-(mantDigits-1)]
			m2, e2 = sign * m, exp + mantDigits - 1
		end
	end
	if m1 == 0 then return (m2 == 0 and Bnum.one or Bnum.zero) end
	if m1 == 1 and e1 == 0 then return Bnum.one end
	if m2 == 0 and e2 == 0 then return Bnum.one end
	if m1 < 0 then
		local n = m2 * pow10[e2]
		if n % 1 ~= 0 then return Bnum.nan end
		local res = Bnum.pow(Bnum.new(-m1, e1), val2)
		if n % 2 ~= 0 then
			buffer.writef64(res, 0, -buffer.readf64(res, 0))
		end
		return res
	end
	local fullExp = m2 * pow10[e2]
	local logBase = math.log10(m1) + e1
	local powVal = logBase * fullExp
	if powVal == math.huge then return Bnum.inf end
	if powVal == -math.huge then return Bnum.zero end
	local newE = math.floor(powVal)
	local newM = 10^(powVal - newE)
	local exp = math.floor(math.log10(newM))
	local man = newM/pow10[exp]
	local out = buffer.create(12)
	buffer.writef64(out, 0, man)
	buffer.writei32(out, 8, exp)
	return out
end

function Bnum.pow10(val: any): buffer
	local m: number, e: number
	if type(val) == "buffer" then
		m, e = buffer.readf64(val, 0), buffer.readi32(val, 8)
	elseif type(val) == "number" then
		if val == 0 then
			m, e = 0, 0
		elseif val ~= val then
			m, e = 0/0, 0
		elseif val == math.huge then
			m, e = 1, math.huge
		elseif val == -math.huge then
			m, e = -1, math.huge
		else
			local absn = math.abs(val)
			if absn >= 1e10 or absn <= 1e-10 then
				local ee = math.floor(math.log10(absn))
				m, e = val / pow10[ee], ee
			else
				m, e = val, 0
			end
		end
	elseif type(val) == "string" then
		local len = #val
		if len == 0 then
			m, e = 0/0, 0
		else
			local i = 1
			local sign = 1
			local c = string.byte(val, i)
			if c == 45 then sign = -1; i += 1
			elseif c == 43 then i += 1 end
			local mant = 0
			local mantDigits = 0
			local exp = 0
			local frac = false
			local b = string.byte
			while i <= len do
				c = b(val, i)
				if c >= 48 and c <= 57 then
					if mantDigits < 17 then
						mant = mant * 10 + (c - 48)
						mantDigits += 1
					else
						exp += 1
					end
					if frac then exp -= 1 end
				elseif c == 46 then
					if frac then break end
					frac = true
				elseif c == 69 or c == 101 then
					i += 1
					break
				else
					break
				end
				i += 1
			end
			if i <= len then
				local esign = 1
				c = b(val, i)
				if c == 45 then esign = -1; i += 1
				elseif c == 43 then i += 1 end
				local ee = 0
				while i <= len do
					c = b(val, i)
					if c < 48 or c > 57 then break end
					ee = ee * 10 + (c - 48)
					i += 1
				end
				exp += ee * esign
			end
			if mant == 0 then
				m, e = 0, 0
			else
				local mm = mant * pow10[-(mantDigits - 1)]
				m, e = sign * mm, exp + mantDigits - 1
			end
		end
	end
	if m == nil or e == nil then
		m, e = 0, 0
	end
	if m == 0 then
		return Bnum.one
	end
	local total = m * pow10[e]
	if total == math.huge then
		return Bnum.inf
	elseif total == -math.huge then
		return Bnum.zero
	end
	local newE = math.floor(total)
	local newM = pow10[total-newE]
	local exp = math.floor(math.log10(newM))
	local man = newM/pow10[exp]
	local out = buffer.create(12)
	buffer.writef64(out, 0, man)
	buffer.writei32(out, 8, exp)
	return out
end

function Bnum.ln(val: any): buffer
	local m: number, e: number
	if type(val) == "buffer" then
		m, e = buffer.readf64(val, 0), buffer.readi32(val, 8)
	elseif type(val) == "number" then
		if val == 0 then
			m, e = 0, 0
		elseif val ~= val then
			m, e = 0/0, 0
		elseif val == math.huge then
			m, e = 1, math.huge
		elseif val == -math.huge then
			m, e = -1, math.huge
		else
			local absn = math.abs(val)
			if absn >= 1e10 or absn <= 1e-10 then
				local ee = math.floor(math.log10(absn))
				m, e = val / pow10[ee], ee
			else
				m, e = val, 0
			end
		end
	elseif type(val) == "string" then
		local len = #val
		if len == 0 then
			m, e = 0/0, 0
		else
			local i = 1
			local sign = 1
			local c = string.byte(val, i)
			if c == 45 then sign = -1; i += 1
			elseif c == 43 then i += 1 end
			local mant = 0
			local mantDigits = 0
			local exp = 0
			local frac = false
			local b = string.byte
			while i <= len do
				c = b(val, i)
				if c >= 48 and c <= 57 then
					if mantDigits < 17 then
						mant = mant * 10 + (c - 48)
						mantDigits += 1
					else
						exp += 1
					end
					if frac then exp -= 1 end
				elseif c == 46 then
					if frac then break end
					frac = true
				elseif c == 69 or c == 101 then
					i += 1
					break
				else
					break
				end
				i += 1
			end
			if i <= len then
				local esign = 1
				c = b(val, i)
				if c == 45 then esign = -1; i += 1
				elseif c == 43 then i += 1 end
				local ee = 0
				while i <= len do
					c = b(val, i)
					if c < 48 or c > 57 then break end
					ee = ee * 10 + (c - 48)
					i += 1
				end
				exp += ee * esign
			end
			if mant == 0 then
				m, e = 0, 0
			else
				local mm = mant * pow10[-(mantDigits - 1)]
				m, e = sign * mm, exp + mantDigits - 1
			end
		end
	end
	local buf = buffer.create(12)
	if m == 0 then
		buffer.writef64(buf, 0, -math.huge)
		buffer.writei32(buf, 8, 0)
		return buf
	elseif m ~= m or e ~= e or m < 0 then
		buffer.writef64(buf, 0, 0/0)
		buffer.writei32(buf, 8, 0)
		return buf
	elseif e == math.huge then
		buffer.writef64(buf, 0, math.huge)
		buffer.writei32(buf, 8, 0)
		return buf
	end
	local result = math.log(m) + e * 2.302585092994046
	local exp = math.floor(math.log10(result))
	local man = result/pow10[exp]
	buffer.writef64(buf, 0, man)
	buffer.writei32(buf, 8, exp)
	return buf
end

function Bnum.log10(val: any): buffer
	local m: number, e: number
	if type(val) == "buffer" then
		m, e = buffer.readf64(val, 0), buffer.readi32(val, 8)
	elseif type(val) == "number" then
		if val == 0 then
			m, e = 0, 0
		elseif val ~= val then
			m, e = 0/0, 0
		elseif val == math.huge then
			m, e = 1, math.huge
		elseif val == -math.huge then
			m, e = -1, math.huge
		else
			local absn = math.abs(val)
			if absn >= 1e10 or absn <= 1e-10 then
				local ee = math.floor(math.log10(absn))
				m, e = val / pow10[ee], ee
			else
				m, e = val, 0
			end
		end
	elseif type(val) == "string" then
		local len = #val
		if len == 0 then
			m, e = 0/0, 0
		else
			local i = 1
			local sign = 1
			local c = string.byte(val, i)
			if c == 45 then sign = -1; i += 1
			elseif c == 43 then i += 1 end
			local mant = 0
			local mantDigits = 0
			local exp = 0
			local frac = false
			local b = string.byte
			while i <= len do
				c = b(val, i)
				if c >= 48 and c <= 57 then
					if mantDigits < 17 then
						mant = mant * 10 + (c - 48)
						mantDigits += 1
					else
						exp += 1
					end
					if frac then exp -= 1 end
				elseif c == 46 then
					if frac then break end
					frac = true
				elseif c == 69 or c == 101 then
					i += 1
					break
				else
					break
				end
				i += 1
			end
			if i <= len then
				local esign = 1
				c = b(val, i)
				if c == 45 then esign = -1; i += 1
				elseif c == 43 then i += 1 end
				local ee = 0
				while i <= len do
					c = b(val, i)
					if c < 48 or c > 57 then break end
					ee = ee * 10 + (c - 48)
					i += 1
				end
				exp += ee * esign
			end
			if mant == 0 then
				m, e = 0, 0
			else
				local mm = mant * pow10[-(mantDigits - 1)]
				m, e = sign * mm, exp + mantDigits - 1
			end
		end
	end
	local buf = buffer.create(12)
	if m == 0 then
		buffer.writef64(buf, 0, -math.huge)
		buffer.writei32(buf, 8, 0)
		return buf
	elseif m ~= m or m < 0 then
		buffer.writef64(buf, 0, 0/0)
		buffer.writei32(buf, 8, 0)
		return buf
	elseif e == math.huge then
		buffer.writef64(buf, 0, math.huge)
		buffer.writei32(buf, 8, 0)
		return buf
	end
	local result = math.log10(m) + e
	local exp = math.floor(math.log10(result))
	local man = result/pow10[exp]
	buffer.writef64(buf, 0, man)
	buffer.writei32(buf, 8, exp)
	return buf
end

function Bnum.log(val1: any, val2: any): buffer
	local out = buffer.create(12)
	local m1: number, e1: number = 0/0, 0
	local m2: number, e2: number = 0/0, 0
	if type(val1) == "buffer" then
		m1, e1 = buffer.readf64(val1, 0), buffer.readi32(val1, 8)
	elseif type(val1) == "number" then
		if val1 == 0 then
			m1, e1 = 0, 0
		elseif val1 ~= val1 then
			m1, e1 = 0/0, 0
		elseif val1 == math.huge then
			m1, e1 = 1, math.huge
		elseif val1 == -math.huge then
			m1, e1 = -1, math.huge
		else
			local a = math.abs(val1)
			if a >= 1e10 or a <= 1e-10 then
				local ee = math.floor(math.log10(a))
				m1, e1 = val1 / pow10[ee], ee
			else
				m1, e1 = val1, 0
			end
		end
	elseif type(val1) == "string" then
		local len = #val1
		if len == 0 then
			m1, e1 = 0/0, 0
		else
			local i, sign = 1, 1
			local mant, mantDigits, exp = 0, 0, 0
			local frac = false
			local b = string.byte
			local c = b(val1, i)
			if c == 45 then sign = -1; i += 1
			elseif c == 43 then i += 1 end
			while i <= len do
				c = b(val1, i)
				if c >= 48 and c <= 57 then
					if mantDigits < 17 then
						mant = mant * 10 + (c - 48)
						mantDigits += 1
					else
						exp += 1
					end
					if frac then exp -= 1 end
				elseif c == 46 then
					if frac then break end
					frac = true
				elseif c == 69 or c == 101 then
					i += 1
					break
				else
					break
				end
				i += 1
			end
			if i <= len then
				local esign, ee = 1, 0
				c = b(val1, i)
				if c == 45 then esign = -1; i += 1
				elseif c == 43 then i += 1 end
				while i <= len do
					c = b(val1, i)
					if c < 48 or c > 57 then break end
					ee = ee * 10 + (c - 48)
					i += 1
				end
				exp += ee * esign
			end
			if mant == 0 then
				m1, e1 = 0, 0
			else
				m1 = sign * mant * pow10[-(mantDigits - 1)]
				e1 = exp + mantDigits - 1
			end
		end
	end
	if m1 <= 0 or m1 ~= m1 then
		buffer.writef64(out, 0, 0/0)
		buffer.writei32(out, 8, 0)
		return out
	end
	if val2 == nil then
		local ln = math.log(m1) + e1 * 2.302585092994046
		buffer.writef64(out, 0, ln)
		buffer.writei32(out, 8, 0)
		return out
	end
	if type(val2) == "buffer" then
		m2, e2 = buffer.readf64(val2, 0), buffer.readi32(val2, 8)
	elseif type(val2) == "number" then
		if val2 == 0 then
			m2, e2 = 0, 0
		elseif val2 ~= val2 then
			m2, e2 = 0/0, 0
		elseif val2 == math.huge then
			m2, e2 = 1, math.huge
		elseif val2 == -math.huge then
			m2, e2 = -1, math.huge
		else
			local a = math.abs(val2)
			if a >= 1e10 or a <= 1e-10 then
				local ee = math.floor(math.log10(a))
				m2, e2 = val2 / pow10[ee], ee
			else
				m2, e2 = val2, 0
			end
		end
	elseif type(val2) == "string" then
		local len = #val2
		if len == 0 then
			m2, e2 = 0/0, 0
		else
			local i, sign = 1, 1
			local mant, mantDigits, exp = 0, 0, 0
			local frac = false
			local b = string.byte
			local c = b(val2, i)
			if c == 45 then sign = -1; i += 1
			elseif c == 43 then i += 1 end
			while i <= len do
				c = b(val2, i)
				if c >= 48 and c <= 57 then
					if mantDigits < 17 then
						mant = mant * 10 + (c - 48)
						mantDigits += 1
					else
						exp += 1
					end
					if frac then exp -= 1 end
				elseif c == 46 then
					if frac then break end
					frac = true
				elseif c == 69 or c == 101 then
					i += 1
					break
				else
					break
				end
				i += 1
			end
			if i <= len then
				local esign, ee = 1, 0
				c = b(val2, i)
				if c == 45 then esign = -1; i += 1
				elseif c == 43 then i += 1 end
				while i <= len do
					c = b(val2, i)
					if c < 48 or c > 57 then break end
					ee = ee * 10 + (c - 48)
					i += 1
				end
				exp += ee * esign
			end
			if mant == 0 then
				m2, e2 = 0, 0
			else
				m2 = sign * mant * pow10[-(mantDigits - 1)]
				e2 = exp + mantDigits - 1
			end
		end
	end
	if m2 <= 0 or m2 ~= m2 then
		buffer.writef64(out, 0, 0/0)
		buffer.writei32(out, 8, 0)
		return out
	end
	local ln1 = math.log(m1) + e1 * 2.302585092994046
	local ln2 = math.log(m2) + e2 * 2.302585092994046
	local result = ln1 / ln2
	local exp = math.floor(math.log10(result))
	local man = result / 10^exp
	buffer.writef64(out, 0, man)
	buffer.writei32(out, 8, exp)
	return out
end

function Bnum.random	(val1: any, val2: any): buffer
	local m1: number, e1: number
	local m2: number, e2: number
	if type(val1) == "buffer" then
		m1, e1 = buffer.readf64(val1, 0), buffer.readi32(val1, 8)
	elseif type(val1) == "number" then
		if val1 == 0 then m1, e1 = 0,0
		elseif val1 ~= val1 then m1, e1 = 0/0,0
		elseif val1 == math.huge then m1, e1 = 1, math.huge
		elseif val1 == -math.huge then m1, e1 = -1, math.huge
		else
			local absn = math.abs(val1)
			if absn >= 1e10 or absn <= 1e-10 then
				local e = math.floor(math.log10(absn))
				m1, e1 = val1 / pow10[e], e
			else
				m1, e1 = val1, 0
			end
		end
	elseif type(val1) == "string" then
		local len = #val1
		local i, sign, mant, mantDigits, exp, frac = 1, 1, 0, 0, 0, false
		local b = string.byte
		if string.byte(val1, i) == 45 then sign = -1; i += 1
		elseif string.byte(val1, i) == 43 then i += 1 end
		while i <= len do
			local c = b(val1, i)
			if c >= 48 and c <= 57 then
				if mantDigits < 17 then mant = mant * 10 + (c-48); mantDigits += 1
				else exp += 1 end
				if frac then exp -= 1 end
			elseif c == 46 then
				if frac then break end
				frac = true
			elseif c == 69 or c == 101 then i += 1; break
			else break end
			i += 1
		end
		if i <= len then
			local esign = 1
			local c = b(val1, i)
			if c == 45 then esign = -1; i += 1
			elseif c == 43 then i += 1 end
			local e = 0
			while i <= len do
				c = b(val1, i)
				if c < 48 or c > 57 then break end
				e = e*10 + (c-48)
				i += 1
			end
			exp += e * esign
		end
		if mant == 0 then m1, e1 = 0,0
		else
			local m = mant * pow10[-(mantDigits-1)]
			m1, e1 = sign * m, exp + mantDigits - 1
		end
	end
	if m1 == nil or e1 == nil then m1, e1 = 0,0 end
	if type(val2) == "buffer" then
		m2, e2 = buffer.readf64(val2, 0), buffer.readi32(val2, 8)
	elseif type(val2) == "number" then
		if val2 == 0 then m2, e2 = 0,0
		elseif val2 ~= val2 then m2, e2 = 0/0,0
		elseif val2 == math.huge then m2, e2 = 1, math.huge
		elseif val2 == -math.huge then m2, e2 = -1, math.huge
		else
			local absn = math.abs(val2)
			if absn >= 1e10 or absn <= 1e-10 then
				local e = math.floor(math.log10(absn))
				m2, e2 = val2 / pow10[e], e
			else
				m2, e2 = val2, 0
			end
		end
	elseif type(val2) == "string" then
		local len = #val2
		local i, sign, mant, mantDigits, exp, frac = 1, 1, 0, 0, 0, false
		local b = string.byte
		if string.byte(val2, i) == 45 then sign = -1; i += 1
		elseif string.byte(val2, i) == 43 then i += 1 end
		while i <= len do
			local c = b(val2, i)
			if c >= 48 and c <= 57 then
				if mantDigits < 17 then mant = mant*10 + (c-48); mantDigits += 1
				else exp += 1 end
				if frac then exp -= 1 end
			elseif c == 46 then
				if frac then break end
				frac = true
			elseif c == 69 or c == 101 then i += 1; break
			else break end
			i += 1
		end
		if i <= len then
			local esign = 1
			local c = b(val2, i)
			if c == 45 then esign = -1; i += 1
			elseif c == 43 then i += 1 end
			local e = 0
			while i <= len do
				c = b(val2, i)
				if c < 48 or c > 57 then break end
				e = e*10 + (c-48)
				i += 1
			end
			exp += e * esign
		end
		if mant == 0 then m2, e2 = 0,0
		else
			local m = mant * pow10[-(mantDigits-1)]
			m2, e2 = sign * m, exp + mantDigits - 1
		end
	end
	local minLog, maxLog = math.log10(math.abs(m1)) + e1, math.log10(math.abs(m2)) + e2
	if minLog > maxLog then
		minLog, maxLog = maxLog, minLog
	end
	local rLog = minLog + math.random() * (maxLog - minLog)
	local exp = math.floor(rLog)
	local man = 10^rLog-exp
	local buff = buffer.create(12)
	buffer.writef64(buff, 0, man)
	buffer.writei32(buff, 8, exp)
	return buff
end

function Bnum.me(val1: any, val2: any): boolean
	local m1: number, e1: number
	local m2: number, e2: number
	if type(val1) == "buffer" then
		m1, e1 = buffer.readf64(val1, 0), buffer.readi32(val1, 8)
	elseif type(val1) == "number" then
		if val1 == 0 then m1, e1 = 0,0
		elseif val1 ~= val1 then m1, e1 = 0/0,0
		elseif val1 == math.huge then m1, e1 = 1, math.huge
		elseif val1 == -math.huge then m1, e1 = -1, math.huge
		else
			local absn = math.abs(val1)
			if absn >= 1e10 or absn <= 1e-10 then
				local e = math.floor(math.log10(absn))
				m1, e1 = val1 / pow10[e], e
			else
				m1, e1 = val1, 0
			end
		end
	elseif type(val1) == "string" then
		local len = #val1
		local i, sign, mant, mantDigits, exp, frac = 1, 1, 0, 0, 0, false
		local b = string.byte
		if string.byte(val1, i) == 45 then sign = -1; i += 1
		elseif string.byte(val1, i) == 43 then i += 1 end
		while i <= len do
			local c = b(val1, i)
			if c >= 48 and c <= 57 then
				if mantDigits < 17 then mant = mant * 10 + (c-48); mantDigits += 1
				else exp += 1 end
				if frac then exp -= 1 end
			elseif c == 46 then
				if frac then break end
				frac = true
			elseif c == 69 or c == 101 then i += 1; break
			else break end
			i += 1
		end
		if i <= len then
			local esign = 1
			local c = b(val1, i)
			if c == 45 then esign = -1; i += 1
			elseif c == 43 then i += 1 end
			local e = 0
			while i <= len do
				c = b(val1, i)
				if c < 48 or c > 57 then break end
				e = e*10 + (c-48)
				i += 1
			end
			exp += e * esign
		end
		if mant == 0 then m1, e1 = 0,0
		else
			local m = mant * pow10[-(mantDigits-1)]
			m1, e1 = sign * m, exp + mantDigits - 1
		end
	end
	if m1 == nil or e1 == nil then m1, e1 = 0,0 end
	if type(val2) == "buffer" then
		m2, e2 = buffer.readf64(val2, 0), buffer.readi32(val2, 8)
	elseif type(val2) == "number" then
		if val2 == 0 then m2, e2 = 0,0
		elseif val2 ~= val2 then m2, e2 = 0/0,0
		elseif val2 == math.huge then m2, e2 = 1, math.huge
		elseif val2 == -math.huge then m2, e2 = -1, math.huge
		else
			local absn = math.abs(val2)
			if absn >= 1e10 or absn <= 1e-10 then
				local e = math.floor(math.log10(absn))
				m2, e2 = val2 / pow10[e], e
			else
				m2, e2 = val2, 0
			end
		end
	elseif type(val2) == "string" then
		local len = #val2
		local i, sign, mant, mantDigits, exp, frac = 1, 1, 0, 0, 0, false
		local b = string.byte
		if string.byte(val2, i) == 45 then sign = -1; i += 1
		elseif string.byte(val2, i) == 43 then i += 1 end
		while i <= len do
			local c = b(val2, i)
			if c >= 48 and c <= 57 then
				if mantDigits < 17 then mant = mant*10 + (c-48); mantDigits += 1
				else exp += 1 end
				if frac then exp -= 1 end
			elseif c == 46 then
				if frac then break end
				frac = true
			elseif c == 69 or c == 101 then i += 1; break
			else break end
			i += 1
		end
		if i <= len then
			local esign = 1
			local c = b(val2, i)
			if c == 45 then esign = -1; i += 1
			elseif c == 43 then i += 1 end
			local e = 0
			while i <= len do
				c = b(val2, i)
				if c < 48 or c > 57 then break end
				e = e*10 + (c-48)
				i += 1
			end
			exp += e * esign
		end
		if mant == 0 then m2, e2 = 0,0
		else
			local m = mant * pow10[-(mantDigits-1)]
			m2, e2 = sign * m, exp + mantDigits - 1
		end
	end
	if e1 ~= e2 then
		return e1 > e2
	end
	return m1 > m2
end

function Bnum.eq(val1: any, val2: any): boolean
	local m1: number, e1: number
	local m2: number, e2: number
	if type(val1) == "buffer" then
		m1, e1 = buffer.readf64(val1, 0), buffer.readi32(val1, 8)
	elseif type(val1) == "number" then
		if val1 == 0 then m1, e1 = 0,0
		elseif val1 ~= val1 then m1, e1 = 0/0,0
		elseif val1 == math.huge then m1, e1 = 1, math.huge
		elseif val1 == -math.huge then m1, e1 = -1, math.huge
		else
			local absn = math.abs(val1)
			if absn >= 1e10 or absn <= 1e-10 then
				local e = math.floor(math.log10(absn))
				m1, e1 = val1 / pow10[e], e
			else
				m1, e1 = val1, 0
			end
		end
	elseif type(val1) == "string" then
		local len = #val1
		local i, sign, mant, mantDigits, exp, frac = 1, 1, 0, 0, 0, false
		local b = string.byte
		if string.byte(val1, i) == 45 then sign = -1; i += 1
		elseif string.byte(val1, i) == 43 then i += 1 end
		while i <= len do
			local c = b(val1, i)
			if c >= 48 and c <= 57 then
				if mantDigits < 17 then mant = mant * 10 + (c-48); mantDigits += 1
				else exp += 1 end
				if frac then exp -= 1 end
			elseif c == 46 then
				if frac then break end
				frac = true
			elseif c == 69 or c == 101 then i += 1; break
			else break end
			i += 1
		end
		if i <= len then
			local esign = 1
			local c = b(val1, i)
			if c == 45 then esign = -1; i += 1
			elseif c == 43 then i += 1 end
			local e = 0
			while i <= len do
				c = b(val1, i)
				if c < 48 or c > 57 then break end
				e = e*10 + (c-48)
				i += 1
			end
			exp += e * esign
		end
		if mant == 0 then m1, e1 = 0,0
		else
			local m = mant * pow10[-(mantDigits-1)]
			m1, e1 = sign * m, exp + mantDigits - 1
		end
	end
	if m1 == nil or e1 == nil then m1, e1 = 0,0 end
	if type(val2) == "buffer" then
		m2, e2 = buffer.readf64(val2, 0), buffer.readi32(val2, 8)
	elseif type(val2) == "number" then
		if val2 == 0 then m2, e2 = 0,0
		elseif val2 ~= val2 then m2, e2 = 0/0,0
		elseif val2 == math.huge then m2, e2 = 1, math.huge
		elseif val2 == -math.huge then m2, e2 = -1, math.huge
		else
			local absn = math.abs(val2)
			if absn >= 1e10 or absn <= 1e-10 then
				local e = math.floor(math.log10(absn))
				m2, e2 = val2 / pow10[e], e
			else
				m2, e2 = val2, 0
			end
		end
	elseif type(val2) == "string" then
		local len = #val2
		local i, sign, mant, mantDigits, exp, frac = 1, 1, 0, 0, 0, false
		local b = string.byte
		if string.byte(val2, i) == 45 then sign = -1; i += 1
		elseif string.byte(val2, i) == 43 then i += 1 end
		while i <= len do
			local c = b(val2, i)
			if c >= 48 and c <= 57 then
				if mantDigits < 17 then mant = mant*10 + (c-48); mantDigits += 1
				else exp += 1 end
				if frac then exp -= 1 end
			elseif c == 46 then
				if frac then break end
				frac = true
			elseif c == 69 or c == 101 then i += 1; break
			else break end
			i += 1
		end
		if i <= len then
			local esign = 1
			local c = b(val2, i)
			if c == 45 then esign = -1; i += 1
			elseif c == 43 then i += 1 end
			local e = 0
			while i <= len do
				c = b(val2, i)
				if c < 48 or c > 57 then break end
				e = e*10 + (c-48)
				i += 1
			end
			exp += e * esign
		end
		if mant == 0 then m2, e2 = 0,0
		else
			local m = mant * pow10[-(mantDigits-1)]
			m2, e2 = sign * m, exp + mantDigits - 1
		end
	end
	if e1 ~= e2 then
		return e1 == e2
	end
	return m1 == m2
end

function Bnum.le(val1: any, val2: any): boolean
	local m1: number, e1: number
	local m2: number, e2: number
	if type(val1) == "buffer" then
		m1, e1 = buffer.readf64(val1, 0), buffer.readi32(val1, 8)
	elseif type(val1) == "number" then
		if val1 == 0 then m1, e1 = 0,0
		elseif val1 ~= val1 then m1, e1 = 0/0,0
		elseif val1 == math.huge then m1, e1 = 1, math.huge
		elseif val1 == -math.huge then m1, e1 = -1, math.huge
		else
			local absn = math.abs(val1)
			if absn >= 1e10 or absn <= 1e-10 then
				local e = math.floor(math.log10(absn))
				m1, e1 = val1 / pow10[e], e
			else
				m1, e1 = val1, 0
			end
		end
	elseif type(val1) == "string" then
		local len = #val1
		local i, sign, mant, mantDigits, exp, frac = 1, 1, 0, 0, 0, false
		local b = string.byte
		if string.byte(val1, i) == 45 then sign = -1; i += 1
		elseif string.byte(val1, i) == 43 then i += 1 end
		while i <= len do
			local c = b(val1, i)
			if c >= 48 and c <= 57 then
				if mantDigits < 17 then mant = mant * 10 + (c-48); mantDigits += 1
				else exp += 1 end
				if frac then exp -= 1 end
			elseif c == 46 then
				if frac then break end
				frac = true
			elseif c == 69 or c == 101 then i += 1; break
			else break end
			i += 1
		end
		if i <= len then
			local esign = 1
			local c = b(val1, i)
			if c == 45 then esign = -1; i += 1
			elseif c == 43 then i += 1 end
			local e = 0
			while i <= len do
				c = b(val1, i)
				if c < 48 or c > 57 then break end
				e = e*10 + (c-48)
				i += 1
			end
			exp += e * esign
		end
		if mant == 0 then m1, e1 = 0,0
		else
			local m = mant * pow10[-(mantDigits-1)]
			m1, e1 = sign * m, exp + mantDigits - 1
		end
	end
	if m1 == nil or e1 == nil then m1, e1 = 0,0 end
	if type(val2) == "buffer" then
		m2, e2 = buffer.readf64(val2, 0), buffer.readi32(val2, 8)
	elseif type(val2) == "number" then
		if val2 == 0 then m2, e2 = 0,0
		elseif val2 ~= val2 then m2, e2 = 0/0,0
		elseif val2 == math.huge then m2, e2 = 1, math.huge
		elseif val2 == -math.huge then m2, e2 = -1, math.huge
		else
			local absn = math.abs(val2)
			if absn >= 1e10 or absn <= 1e-10 then
				local e = math.floor(math.log10(absn))
				m2, e2 = val2 / pow10[e], e
			else
				m2, e2 = val2, 0
			end
		end
	elseif type(val2) == "string" then
		local len = #val2
		local i, sign, mant, mantDigits, exp, frac = 1, 1, 0, 0, 0, false
		local b = string.byte
		if string.byte(val2, i) == 45 then sign = -1; i += 1
		elseif string.byte(val2, i) == 43 then i += 1 end
		while i <= len do
			local c = b(val2, i)
			if c >= 48 and c <= 57 then
				if mantDigits < 17 then mant = mant*10 + (c-48); mantDigits += 1
				else exp += 1 end
				if frac then exp -= 1 end
			elseif c == 46 then
				if frac then break end
				frac = true
			elseif c == 69 or c == 101 then i += 1; break
			else break end
			i += 1
		end
		if i <= len then
			local esign = 1
			local c = b(val2, i)
			if c == 45 then esign = -1; i += 1
			elseif c == 43 then i += 1 end
			local e = 0
			while i <= len do
				c = b(val2, i)
				if c < 48 or c > 57 then break end
				e = e*10 + (c-48)
				i += 1
			end
			exp += e * esign
		end
		if mant == 0 then m2, e2 = 0,0
		else
			local m = mant * pow10[-(mantDigits-1)]
			m2, e2 = sign * m, exp + mantDigits - 1
		end
	end
	if e1 ~= e2 then
		return e1 < e2
	end
	return m1 < m2
end

function Bnum.meeq(val1: any, val2: any): boolean
	local m1: number, e1: number
	local m2: number, e2: number
	if type(val1) == "buffer" then
		m1, e1 = buffer.readf64(val1, 0), buffer.readi32(val1, 8)
	elseif type(val1) == "number" then
		if val1 == 0 then m1, e1 = 0,0
		elseif val1 ~= val1 then m1, e1 = 0/0,0
		elseif val1 == math.huge then m1, e1 = 1, math.huge
		elseif val1 == -math.huge then m1, e1 = -1, math.huge
		else
			local absn = math.abs(val1)
			if absn >= 1e10 or absn <= 1e-10 then
				local e = math.floor(math.log10(absn))
				m1, e1 = val1 / pow10[e], e
			else
				m1, e1 = val1, 0
			end
		end
	elseif type(val1) == "string" then
		local len = #val1
		local i, sign, mant, mantDigits, exp, frac = 1, 1, 0, 0, 0, false
		local b = string.byte
		if string.byte(val1, i) == 45 then sign = -1; i += 1
		elseif string.byte(val1, i) == 43 then i += 1 end
		while i <= len do
			local c = b(val1, i)
			if c >= 48 and c <= 57 then
				if mantDigits < 17 then mant = mant * 10 + (c-48); mantDigits += 1
				else exp += 1 end
				if frac then exp -= 1 end
			elseif c == 46 then
				if frac then break end
				frac = true
			elseif c == 69 or c == 101 then i += 1; break
			else break end
			i += 1
		end
		if i <= len then
			local esign = 1
			local c = b(val1, i)
			if c == 45 then esign = -1; i += 1
			elseif c == 43 then i += 1 end
			local e = 0
			while i <= len do
				c = b(val1, i)
				if c < 48 or c > 57 then break end
				e = e*10 + (c-48)
				i += 1
			end
			exp += e * esign
		end
		if mant == 0 then m1, e1 = 0,0
		else
			local m = mant * pow10[-(mantDigits-1)]
			m1, e1 = sign * m, exp + mantDigits - 1
		end
	end
	if m1 == nil or e1 == nil then m1, e1 = 0,0 end
	if type(val2) == "buffer" then
		m2, e2 = buffer.readf64(val2, 0), buffer.readi32(val2, 8)
	elseif type(val2) == "number" then
		if val2 == 0 then m2, e2 = 0,0
		elseif val2 ~= val2 then m2, e2 = 0/0,0
		elseif val2 == math.huge then m2, e2 = 1, math.huge
		elseif val2 == -math.huge then m2, e2 = -1, math.huge
		else
			local absn = math.abs(val2)
			if absn >= 1e10 or absn <= 1e-10 then
				local e = math.floor(math.log10(absn))
				m2, e2 = val2 / pow10[e], e
			else
				m2, e2 = val2, 0
			end
		end
	elseif type(val2) == "string" then
		local len = #val2
		local i, sign, mant, mantDigits, exp, frac = 1, 1, 0, 0, 0, false
		local b = string.byte
		if string.byte(val2, i) == 45 then sign = -1; i += 1
		elseif string.byte(val2, i) == 43 then i += 1 end
		while i <= len do
			local c = b(val2, i)
			if c >= 48 and c <= 57 then
				if mantDigits < 17 then mant = mant*10 + (c-48); mantDigits += 1
				else exp += 1 end
				if frac then exp -= 1 end
			elseif c == 46 then
				if frac then break end
				frac = true
			elseif c == 69 or c == 101 then i += 1; break
			else break end
			i += 1
		end
		if i <= len then
			local esign = 1
			local c = b(val2, i)
			if c == 45 then esign = -1; i += 1
			elseif c == 43 then i += 1 end
			local e = 0
			while i <= len do
				c = b(val2, i)
				if c < 48 or c > 57 then break end
				e = e*10 + (c-48)
				i += 1
			end
			exp += e * esign
		end
		if mant == 0 then m2, e2 = 0,0
		else
			local m = mant * pow10[-(mantDigits-1)]
			m2, e2 = sign * m, exp + mantDigits - 1
		end
	end
	if e1 ~= e2 then
		return e1 > e2
	end
	return m1 >= m2
end

function Bnum.leeq(val1: any, val2: any): boolean
	local m1: number, e1: number
	local m2: number, e2: number
	if type(val1) == "buffer" then
		m1, e1 = buffer.readf64(val1, 0), buffer.readi32(val1, 8)
	elseif type(val1) == "number" then
		if val1 == 0 then m1, e1 = 0,0
		elseif val1 ~= val1 then m1, e1 = 0/0,0
		elseif val1 == math.huge then m1, e1 = 1, math.huge
		elseif val1 == -math.huge then m1, e1 = -1, math.huge
		else
			local absn = math.abs(val1)
			if absn >= 1e10 or absn <= 1e-10 then
				local e = math.floor(math.log10(absn))
				m1, e1 = val1 / pow10[e], e
			else
				m1, e1 = val1, 0
			end
		end
	elseif type(val1) == "string" then
		local len = #val1
		local i, sign, mant, mantDigits, exp, frac = 1, 1, 0, 0, 0, false
		local b = string.byte
		if string.byte(val1, i) == 45 then sign = -1; i += 1
		elseif string.byte(val1, i) == 43 then i += 1 end
		while i <= len do
			local c = b(val1, i)
			if c >= 48 and c <= 57 then
				if mantDigits < 17 then mant = mant * 10 + (c-48); mantDigits += 1
				else exp += 1 end
				if frac then exp -= 1 end
			elseif c == 46 then
				if frac then break end
				frac = true
			elseif c == 69 or c == 101 then i += 1; break
			else break end
			i += 1
		end
		if i <= len then
			local esign = 1
			local c = b(val1, i)
			if c == 45 then esign = -1; i += 1
			elseif c == 43 then i += 1 end
			local e = 0
			while i <= len do
				c = b(val1, i)
				if c < 48 or c > 57 then break end
				e = e*10 + (c-48)
				i += 1
			end
			exp += e * esign
		end
		if mant == 0 then m1, e1 = 0,0
		else
			local m = mant * pow10[-(mantDigits-1)]
			m1, e1 = sign * m, exp + mantDigits - 1
		end
	end
	if m1 == nil or e1 == nil then m1, e1 = 0,0 end
	if type(val2) == "buffer" then
		m2, e2 = buffer.readf64(val2, 0), buffer.readi32(val2, 8)
	elseif type(val2) == "number" then
		if val2 == 0 then m2, e2 = 0,0
		elseif val2 ~= val2 then m2, e2 = 0/0,0
		elseif val2 == math.huge then m2, e2 = 1, math.huge
		elseif val2 == -math.huge then m2, e2 = -1, math.huge
		else
			local absn = math.abs(val2)
			if absn >= 1e10 or absn <= 1e-10 then
				local e = math.floor(math.log10(absn))
				m2, e2 = val2 / pow10[e], e
			else
				m2, e2 = val2, 0
			end
		end
	elseif type(val2) == "string" then
		local len = #val2
		local i, sign, mant, mantDigits, exp, frac = 1, 1, 0, 0, 0, false
		local b = string.byte
		if string.byte(val2, i) == 45 then sign = -1; i += 1
		elseif string.byte(val2, i) == 43 then i += 1 end
		while i <= len do
			local c = b(val2, i)
			if c >= 48 and c <= 57 then
				if mantDigits < 17 then mant = mant*10 + (c-48); mantDigits += 1
				else exp += 1 end
				if frac then exp -= 1 end
			elseif c == 46 then
				if frac then break end
				frac = true
			elseif c == 69 or c == 101 then i += 1; break
			else break end
			i += 1
		end
		if i <= len then
			local esign = 1
			local c = b(val2, i)
			if c == 45 then esign = -1; i += 1
			elseif c == 43 then i += 1 end
			local e = 0
			while i <= len do
				c = b(val2, i)
				if c < 48 or c > 57 then break end
				e = e*10 + (c-48)
				i += 1
			end
			exp += e * esign
		end
		if mant == 0 then m2, e2 = 0,0
		else
			local m = mant * pow10[-(mantDigits-1)]
			m2, e2 = sign * m, exp + mantDigits - 1
		end
	end
	if e1 ~= e2 then
		return e1 < e2
	end
	return m1 <= m2
end

function Bnum.abs(val: any): buffer
	local m: number, e: number
	if type(val) == "buffer" then
		m, e = buffer.readf64(val, 0), buffer.readi32(val, 8)
	elseif type(val) == "number" then
		if val == 0 then
			m, e = 0, 0
		elseif val ~= val then
			m, e = 0/0, 0
		elseif val == math.huge then
			m, e = 1, math.huge
		elseif val == -math.huge then
			m, e = -1, math.huge
		else
			local absn = math.abs(val)
			if absn >= 1e10 or absn <= 1e-10 then
				local ee = math.floor(math.log10(absn))
				m, e = val / pow10[ee], ee
			else
				m, e = val, 0
			end
		end
	elseif type(val) == "string" then
		local len = #val
		if len == 0 then
			m, e = 0/0, 0
		else
			local i = 1
			local sign = 1
			local c = string.byte(val, i)
			if c == 45 then sign = -1; i += 1
			elseif c == 43 then i += 1 end
			local mant = 0
			local mantDigits = 0
			local exp = 0
			local frac = false
			local b = string.byte
			while i <= len do
				c = b(val, i)
				if c >= 48 and c <= 57 then
					if mantDigits < 17 then
						mant = mant * 10 + (c - 48)
						mantDigits += 1
					else
						exp += 1
					end
					if frac then exp -= 1 end
				elseif c == 46 then
					if frac then break end
					frac = true
				elseif c == 69 or c == 101 then
					i += 1
					break
				else
					break
				end
				i += 1
			end
			if i <= len then
				local esign = 1
				c = b(val, i)
				if c == 45 then esign = -1; i += 1
				elseif c == 43 then i += 1 end
				local ee = 0
				while i <= len do
					c = b(val, i)
					if c < 48 or c > 57 then break end
					ee = ee * 10 + (c - 48)
					i += 1
				end
				exp += ee * esign
			end
			if mant == 0 then
				m, e = 0, 0
			else
				local mm = mant * pow10[-(mantDigits - 1)]
				m, e = sign * mm, exp + mantDigits - 1
			end
		end
	end
	local out: buffer = buffer.create(12)
	if m < 0 then
		m =-m
	end
	buffer.writef64(out, 0, m)
	buffer.writei32(out, 8, e)
	return out
end

function Bnum.round(val: any, digits: number?): buffer
	digits = digits or 0
	local m: number, e: number
	if type(val) == "buffer" then
		m, e = buffer.readf64(val, 0), buffer.readi32(val, 8)
	elseif type(val) == "number" then
		if val == 0 then
			m, e = 0, 0
		elseif val ~= val then
			m, e = 0/0, 0
		elseif val == math.huge then
			m, e = 1, math.huge
		elseif val == -math.huge then
			m, e = -1, math.huge
		else
			local absn = math.abs(val)
			if absn >= 1e10 or absn <= 1e-10 then
				local ee = math.floor(math.log10(absn))
				m, e = val / pow10[ee], ee
			else
				m, e = val, 0
			end
		end
	elseif type(val) == "string" then
		local len = #val
		if len == 0 then
			m, e = 0/0, 0
		else
			local i = 1
			local sign = 1
			local c = string.byte(val, i)
			if c == 45 then sign = -1; i += 1
			elseif c == 43 then i += 1 end
			local mant = 0
			local mantDigits = 0
			local exp = 0
			local frac = false
			local b = string.byte
			while i <= len do
				c = b(val, i)
				if c >= 48 and c <= 57 then
					if mantDigits < 17 then
						mant = mant * 10 + (c - 48)
						mantDigits += 1
					else
						exp += 1
					end
					if frac then exp -= 1 end
				elseif c == 46 then
					if frac then break end
					frac = true
				elseif c == 69 or c == 101 then
					i += 1
					break
				else
					break
				end
				i += 1
			end
			if i <= len then
				local esign = 1
				c = b(val, i)
				if c == 45 then esign = -1; i += 1
				elseif c == 43 then i += 1 end
				local ee = 0
				while i <= len do
					c = b(val, i)
					if c < 48 or c > 57 then break end
					ee = ee * 10 + (c - 48)
					i += 1
				end
				exp += ee * esign
			end
			if mant == 0 then
				m, e = 0, 0
			else
				local mm = mant * pow10[-(mantDigits - 1)]
				m, e = sign * mm, exp + mantDigits - 1
			end
		end
	end
	local out = buffer.create(12)
	if m == 0 then
		buffer.writef64(out, 0, 0)
		buffer.writei32(out, 8, 0)
		return out
	end
	if digits > 0 then
		local scale = pow10[digits]
		m = math.floor(m*scale + 0.05)/scale
		if m >= 10 then
			m *= 0.1
			e += 1
		elseif m > 0 and m < 1 then
			m *= 10
			e -= 1
		end
	end
	buffer.writef64(out, 0, m)
	buffer.writei32(out, 8, e)
	return out
end

function Bnum.ceil(val: any, digits: number?): buffer
	digits = digits or 0
	local m: number, e: number
	if type(val) == "buffer" then
		m, e = buffer.readf64(val, 0), buffer.readi32(val, 8)
	elseif type(val) == "number" then
		if val == 0 then
			m, e = 0, 0
		elseif val ~= val then
			m, e = 0/0, 0
		elseif val == math.huge then
			m, e = 1, math.huge
		elseif val == -math.huge then
			m, e = -1, math.huge
		else
			local absn = math.abs(val)
			if absn >= 1e10 or absn <= 1e-10 then
				local ee = math.floor(math.log10(absn))
				m, e = val / pow10[ee], ee
			else
				m, e = val, 0
			end
		end
	elseif type(val) == "string" then
		local len = #val
		if len == 0 then
			m, e = 0/0, 0
		else
			local i = 1
			local sign = 1
			local c = string.byte(val, i)
			if c == 45 then sign = -1; i += 1
			elseif c == 43 then i += 1 end
			local mant = 0
			local mantDigits = 0
			local exp = 0
			local frac = false
			local b = string.byte
			while i <= len do
				c = b(val, i)
				if c >= 48 and c <= 57 then
					if mantDigits < 17 then
						mant = mant * 10 + (c - 48)
						mantDigits += 1
					else
						exp += 1
					end
					if frac then exp -= 1 end
				elseif c == 46 then
					if frac then break end
					frac = true
				elseif c == 69 or c == 101 then
					i += 1
					break
				else
					break
				end
				i += 1
			end
			if i <= len then
				local esign = 1
				c = b(val, i)
				if c == 45 then esign = -1; i += 1
				elseif c == 43 then i += 1 end
				local ee = 0
				while i <= len do
					c = b(val, i)
					if c < 48 or c > 57 then break end
					ee = ee * 10 + (c - 48)
					i += 1
				end
				exp += ee * esign
			end
			if mant == 0 then
				m, e = 0, 0
			else
				local mm = mant * pow10[-(mantDigits - 1)]
				m, e = sign * mm, exp + mantDigits - 1
			end
		end
	end
	local out = buffer.create(12)
	if m == 0 then
		buffer.writef64(out, 0, 0)
		buffer.writei32(out, 8, 0)
		return out
	end
	if digits > 0 then
		local scale = pow10[digits]
		m = math.ceil(m*scale)/scale
		if m >= 10 then
			m *= 0.1
			e += 1
		elseif m > 0 and m < 1 then
			m *= 10
			e -= 1
		end
	end
	buffer.writef64(out, 0, m)
	buffer.writei32(out, 8, e)
	return out
end

function Bnum.clamp(val: any, min: any, max: any): buffer
	local out = buffer.create(12)
	local mV: number, eV: number
	if type(val) == "buffer" then
		mV, eV = buffer.readf64(val, 0), buffer.readi32(val, 8)
	elseif type(val) == "number" then
		if val == 0 then mV, eV = 0, 0
		elseif val ~= val then mV, eV = 0/0, 0
		elseif val == math.huge then mV, eV = 1, math.huge
		elseif val == -math.huge then mV, eV = -1, math.huge
		else
			local a = math.abs(val)
			if a >= 1e10 or a <= 1e-10 then
				local ee = math.floor(math.log10(a))
				mV, eV = val / pow10[ee], ee
			else
				mV, eV = val, 0
			end
		end
	elseif type(val) == "string" then
		local len = #val
		if len == 0 then
			mV, eV = 0/0, 0
		else
			local i, sign = 1, 1
			local b = string.byte
			local c = b(val, i)
			if c == 45 then sign = -1; i += 1
			elseif c == 43 then i += 1 end
			local mant, mantDigits, exp = 0, 0, 0
			local frac = false
			while i <= len do
				c = b(val, i)
				if c >= 48 and c <= 57 then
					if mantDigits < 17 then
						mant = mant * 10 + (c - 48)
						mantDigits += 1
					else
						exp += 1
					end
					if frac then exp -= 1 end
				elseif c == 46 then
					if frac then break end
					frac = true
				elseif c == 69 or c == 101 then
					i += 1
					break
				else
					break
				end
				i += 1
			end
			if i <= len then
				local esign, ee = 1, 0
				c = b(val, i)
				if c == 45 then esign = -1; i += 1
				elseif c == 43 then i += 1 end
				while i <= len do
					c = b(val, i)
					if c < 48 or c > 57 then break end
					ee = ee * 10 + (c - 48)
					i += 1
				end
				exp += ee * esign
			end
			if mant == 0 then
				mV, eV = 0, 0
			else
				mV = sign * mant * pow10[-(mantDigits - 1)]
				eV = exp + mantDigits - 1
			end
		end
	end
	local mMin: number, eMin: number
	if type(min) == "buffer" then
		mMin, eMin = buffer.readf64(min, 0), buffer.readi32(min, 8)
	elseif type(min) == "number" then
		if min == 0 then mMin, eMin = 0, 0
		elseif min ~= min then mMin, eMin = 0/0, 0
		elseif min == math.huge then mMin, eMin = 1, math.huge
		elseif min == -math.huge then mMin, eMin = -1, math.huge
		else
			local a = math.abs(min)
			if a >= 1e10 or a <= 1e-10 then
				local ee = math.floor(math.log10(a))
				mMin, eMin = min / pow10[ee], ee
			else
				mMin, eMin = min, 0
			end
		end
	elseif type(min) == "string" then
		local len = #min
		if len == 0 then
			mMin, eMin = 0/0, 0
		else
			local i, sign = 1, 1
			local b = string.byte
			local c = b(min, i)
			if c == 45 then sign = -1; i += 1
			elseif c == 43 then i += 1 end
			local mant, mantDigits, exp = 0, 0, 0
			local frac = false
			while i <= len do
				c = b(min, i)
				if c >= 48 and c <= 57 then
					if mantDigits < 17 then
						mant = mant * 10 + (c - 48)
						mantDigits += 1
					else
						exp += 1
					end
					if frac then exp -= 1 end
				elseif c == 46 then
					if frac then break end
					frac = true
				elseif c == 69 or c == 101 then
					i += 1
					break
				else
					break
				end
				i += 1
			end
			if i <= len then
				local esign, ee = 1, 0
				c = b(min, i)
				if c == 45 then esign = -1; i += 1
				elseif c == 43 then i += 1 end
				while i <= len do
					c = b(min, i)
					if c < 48 or c > 57 then break end
					ee = ee * 10 + (c - 48)
					i += 1
				end
				exp += ee * esign
			end
			if mant == 0 then
				mMin, eMin = 0, 0
			else
				mMin = sign * mant * pow10[-(mantDigits - 1)]
				eMin = exp + mantDigits - 1
			end
		end
	end
	local mMax: number, eMax: number
	if type(max) == "buffer" then
		mMax, eMax = buffer.readf64(max, 0), buffer.readi32(max, 8)
	elseif type(max) == "number" then
		if max == 0 then mMax, eMax = 0, 0
		elseif max ~= max then mMax, eMax = 0/0, 0
		elseif max == math.huge then mMax, eMax = 1, math.huge
		elseif max == -math.huge then mMax, eMax = -1, math.huge
		else
			local a = math.abs(max)
			if a >= 1e10 or a <= 1e-10 then
				local ee = math.floor(math.log10(a))
				mMax, eMax = max / pow10[ee], ee
			else
				mMax, eMax = max, 0
			end
		end
	elseif type(max) == "string" then
		local len = #max
		if len == 0 then
			mMax, eMax = 0/0, 0
		else
			local i, sign = 1, 1
			local b = string.byte
			local c = b(max, i)
			if c == 45 then sign = -1; i += 1
			elseif c == 43 then i += 1 end
			local mant, mantDigits, exp = 0, 0, 0
			local frac = false
			while i <= len do
				c = b(max, i)
				if c >= 48 and c <= 57 then
					if mantDigits < 17 then
						mant = mant * 10 + (c - 48)
						mantDigits += 1
					else
						exp += 1
					end
					if frac then exp -= 1 end
				elseif c == 46 then
					if frac then break end
					frac = true
				elseif c == 69 or c == 101 then
					i += 1
					break
				else
					break
				end
				i += 1
			end
			if i <= len then
				local esign, ee = 1, 0
				c = b(max, i)
				if c == 45 then esign = -1; i += 1
				elseif c == 43 then i += 1 end
				while i <= len do
					c = b(max, i)
					if c < 48 or c > 57 then break end
					ee = ee * 10 + (c - 48)
					i += 1
				end
				exp += ee * esign
			end
			if mant == 0 then
				mMax, eMax = 0, 0
			else
				mMax = sign * mant * pow10[-(mantDigits - 1)]
				eMax = exp + mantDigits - 1
			end
		end
	end
	if eV < eMin or (eV == eMin and mV < mMin) then
		buffer.writef64(out, 0, mMin)
		buffer.writei32(out, 8, eMin)
		return out
	end
	if eV > eMax or (eV == eMax and mV > mMax) then
		buffer.writef64(out, 0, mMax)
		buffer.writei32(out, 8, eMax)
		return out
	end
	buffer.writef64(out, 0, mV)
	buffer.writei32(out, 8, eV)
	return out
end

function Bnum.sqrt(val: any): buffer
	local m: number, e: number
	if type(val) == "buffer" then
		m, e = buffer.readf64(val, 0), buffer.readi32(val, 8)
	elseif type(val) == "number" then
		if val == 0 then
			m, e = 0, 0
		elseif val ~= val then
			m, e = 0/0, 0
		elseif val == math.huge then
			m, e = 1, math.huge
		elseif val == -math.huge then
			m, e = -1, math.huge
		else
			local absn = math.abs(val)
			if absn >= 1e10 or absn <= 1e-10 then
				local ee = math.floor(math.log10(absn))
				m, e = val / pow10[ee], ee
			else
				m, e = val, 0
			end
		end
	elseif type(val) == "string" then
		local len = #val
		if len == 0 then
			m, e = 0/0, 0
		else
			local i = 1
			local sign = 1
			local c = string.byte(val, i)
			if c == 45 then sign = -1; i += 1
			elseif c == 43 then i += 1 end
			local mant = 0
			local mantDigits = 0
			local exp = 0
			local frac = false
			local b = string.byte
			while i <= len do
				c = b(val, i)
				if c >= 48 and c <= 57 then
					if mantDigits < 17 then
						mant = mant * 10 + (c - 48)
						mantDigits += 1
					else
						exp += 1
					end
					if frac then exp -= 1 end
				elseif c == 46 then
					if frac then break end
					frac = true
				elseif c == 69 or c == 101 then
					i += 1
					break
				else
					break
				end
				i += 1
			end
			if i <= len then
				local esign = 1
				c = b(val, i)
				if c == 45 then esign = -1; i += 1
				elseif c == 43 then i += 1 end
				local ee = 0
				while i <= len do
					c = b(val, i)
					if c < 48 or c > 57 then break end
					ee = ee * 10 + (c - 48)
					i += 1
				end
				exp += ee * esign
			end
			if mant == 0 then
				m, e = 0, 0
			else
				local mm = mant * pow10[-(mantDigits - 1)]
				m, e = sign * mm, exp + mantDigits - 1
			end
		end
	end
	if m < 0 then
		local out = buffer.create(12)
		buffer.writef64(out, 0, 0/0)
		buffer.writei32(out, 8, 0)
		return out
	end
	if e % 2 ~= 0 then
		m = m * 10
		e = e - 1
	end
	local newMan = math.sqrt(m)
	local newExp = e / 2
	local exp = math.floor(math.log10(newMan))
	local man = newMan/pow10[exp]
	local out = buffer.create(12)
	buffer.writef64(out, 0, man)
	buffer.writei32(out, 8, exp)
	return out
end

function Bnum.cbrt(val: any): buffer
	local m: number, e: number
	if type(val) == "buffer" then
		m, e = buffer.readf64(val, 0), buffer.readi32(val, 8)
	elseif type(val) == "number" then
		if val == 0 then
			m, e = 0, 0
		elseif val ~= val then
			m, e = 0/0, 0
		elseif val == math.huge then
			m, e = 1, math.huge
		elseif val == -math.huge then
			m, e = -1, math.huge
		else
			local absn = math.abs(val)
			if absn >= 1e10 or absn <= 1e-10 then
				local ee = math.floor(math.log10(absn))
				m, e = val / pow10[ee], ee
			else
				m, e = val, 0
			end
		end
	elseif type(val) == "string" then
		local len = #val
		if len == 0 then
			m, e = 0/0, 0
		else
			local i = 1
			local sign = 1
			local c = string.byte(val, i)
			if c == 45 then sign = -1; i += 1
			elseif c == 43 then i += 1 end
			local mant = 0
			local mantDigits = 0
			local exp = 0
			local frac = false
			local b = string.byte
			while i <= len do
				c = b(val, i)
				if c >= 48 and c <= 57 then
					if mantDigits < 17 then
						mant = mant * 10 + (c - 48)
						mantDigits += 1
					else
						exp += 1
					end
					if frac then exp -= 1 end
				elseif c == 46 then
					if frac then break end
					frac = true
				elseif c == 69 or c == 101 then
					i += 1
					break
				else
					break
				end
				i += 1
			end
			if i <= len then
				local esign = 1
				c = b(val, i)
				if c == 45 then esign = -1; i += 1
				elseif c == 43 then i += 1 end
				local ee = 0
				while i <= len do
					c = b(val, i)
					if c < 48 or c > 57 then break end
					ee = ee * 10 + (c - 48)
					i += 1
				end
				exp += ee * esign
			end
			if mant == 0 then
				m, e = 0, 0
			else
				local mm = mant * pow10[-(mantDigits - 1)]
				m, e = sign * mm, exp + mantDigits - 1
			end
		end
	end
	local sign = m < 0 and -1 or 1
	m = math.abs(m)
	local newMan = sign * m^(1/3)
	local newExp = e / 3
	local exp = math.floor(math.log10(newMan))
	local man = newMan/pow10[exp]
	local out = buffer.create(12)
	buffer.writef64(out, 0, man)
	buffer.writei32(out, 8, exp)
	return out
end

function Bnum.root(val: any, n: any): buffer
	local out = buffer.create(12)
	local m1: number, e1: number = 0/0, 0
	local m2: number, e2: number = 0/0, 0
	if type(val) == "buffer" then
		m1, e1 = buffer.readf64(val, 0), buffer.readi32(val, 8)
	elseif type(val) == "number" then
		if val == 0 then
			m1, e1 = 0, 0
		elseif val ~= val then
			m1, e1 = 0/0, 0
		elseif val == math.huge then
			m1, e1 = 1, math.huge
		elseif val == -math.huge then
			m1, e1 = -1, math.huge
		else
			local a = math.abs(val)
			if a >= 1e10 or a <= 1e-10 then
				local ee = math.floor(math.log10(a))
				m1, e1 = val / pow10[ee], ee
			else
				m1, e1 = val, 0
			end
		end
	elseif type(val) == "string" then
		local len = #val
		if len == 0 then
			m1, e1 = 0/0, 0
		else
			local i, sign = 1, 1
			local mant, mantDigits, exp = 0, 0, 0
			local frac = false
			local b = string.byte
			local c = b(val, i)
			if c == 45 then sign = -1; i += 1
			elseif c == 43 then i += 1 end
			while i <= len do
				c = b(val, i)
				if c >= 48 and c <= 57 then
					if mantDigits < 17 then
						mant = mant * 10 + (c - 48)
						mantDigits += 1
					else
						exp += 1
					end
					if frac then exp -= 1 end
				elseif c == 46 then
					if frac then break end
					frac = true
				elseif c == 69 or c == 101 then
					i += 1
					break
				else
					break
				end
				i += 1
			end
			if i <= len then
				local esign, ee = 1, 0
				c = b(val, i)
				if c == 45 then esign = -1; i += 1
				elseif c == 43 then i += 1 end
				while i <= len do
					c = b(val, i)
					if c < 48 or c > 57 then break end
					ee = ee * 10 + (c - 48)
					i += 1
				end
				exp += ee * esign
			end
			if mant == 0 then
				m1, e1 = 0, 0
			else
				m1 = sign * mant * pow10[-(mantDigits - 1)]
				e1 = exp + mantDigits - 1
			end
		end
	end
	if type(n) == "buffer" then
		m2, e2 = buffer.readf64(n, 0), buffer.readi32(n, 8)
	elseif type(n) == "number" then
		if n == 0 then
			m2, e2 = 0, 0
		elseif n ~= n then
			m2, e2 = 0/0, 0
		elseif n == math.huge then
			m2, e2 = 1, math.huge
		elseif n == -math.huge then
			m2, e2 = -1, math.huge
		else
			local a = math.abs(n)
			if a >= 1e10 or a <= 1e-10 then
				local ee = math.floor(math.log10(a))
				m2, e2 = n / pow10[ee], ee
			else
				m2, e2 = n, 0
			end
		end
	elseif type(n) == "string" then
		local len = #n
		if len == 0 then
			m2, e2 = 0/0, 0
		else
			local i, sign = 1, 1
			local mant, mantDigits, exp = 0, 0, 0
			local frac = false
			local b = string.byte

			local c = b(n, i)
			if c == 45 then sign = -1; i += 1
			elseif c == 43 then i += 1 end
			while i <= len do
				c = b(n, i)
				if c >= 48 and c <= 57 then
					if mantDigits < 17 then
						mant = mant * 10 + (c - 48)
						mantDigits += 1
					else
						exp += 1
					end
					if frac then exp -= 1 end
				elseif c == 46 then
					if frac then break end
					frac = true
				elseif c == 69 or c == 101 then
					i += 1
					break
				else
					break
				end
				i += 1
			end
			if i <= len then
				local esign, ee = 1, 0
				c = b(n, i)
				if c == 45 then esign = -1; i += 1
				elseif c == 43 then i += 1 end
				while i <= len do
					c = b(n, i)
					if c < 48 or c > 57 then break end
					ee = ee * 10 + (c - 48)
					i += 1
				end
				exp += ee * esign
			end
			if mant == 0 then
				m2, e2 = 0, 0
			else
				m2 = sign * mant * pow10[-(mantDigits - 1)]
				e2 = exp + mantDigits - 1
			end
		end
	end
	if m1 < 0 or m1 ~= m1 or m2 ~= m2 then
		buffer.writef64(out, 0, 0/0)
		buffer.writei32(out, 8, 0)
		return out
	end
	if m2 == 0 then
		buffer.writef64(out, 0, math.huge)
		buffer.writei32(out, 8, 0)
		return out
	end
	local logv = math.log10(m1) + e1
	local invN = 1 / (m2 * pow10[e2])
	local newLog = logv * invN
	local ne = math.floor(newLog)
	local nm = 10^(newLog-ne)

	local exp = math.floor(math.log10(nm))
	local man = nm/pow10[exp]
	buffer.writef64(out, 0, man)
	buffer.writei32(out, 8, exp)
	return out
end

function Bnum.floor(val: any): buffer
	local out = buffer.create(12)
	local m: number, e: number
	if type(val) == "buffer" then
		m, e = buffer.readf64(val, 0), buffer.readi32(val, 8)
	elseif type(val) == "number" then
		if val == 0 then
			buffer.writef64(out, 0, 0)
			buffer.writei32(out, 8, 0)
			return out
		elseif val ~= val then
			buffer.writef64(out, 0, 0/0)
			buffer.writei32(out, 8, 0)
			return out
		elseif val == math.huge then
			buffer.writef64(out, 0, 1)
			buffer.writei32(out, 8, math.huge)
			return out
		elseif val == -math.huge then
			buffer.writef64(out, 0, -1)
			buffer.writei32(out, 8, math.huge)
			return out
		else
			local a = math.abs(val)
			if a >= 1e10 or a <= 1e-10 then
				local ee = math.floor(math.log10(a))
				m, e = val / pow10[ee], ee
			else
				m, e = val, 0
			end
		end
	elseif type(val) == "string" then
		local len = #val
		if len == 0 then
			m, e = 0/0, 0
		else
			local i, sign = 1, 1
			local b = string.byte
			local c = b(val, i)
			if c == 45 then sign = -1; i += 1
			elseif c == 43 then i += 1 end
			local mant, mantDigits, exp = 0, 0, 0
			local frac = false
			while i <= len do
				c = b(val, i)
				if c >= 48 and c <= 57 then
					if mantDigits < 17 then
						mant = mant * 10 + (c - 48)
						mantDigits += 1
					else
						exp += 1
					end
					if frac then exp -= 1 end
				elseif c == 46 then
					if frac then break end
					frac = true
				elseif c == 69 or c == 101 then
					i += 1
					break
				else
					break
				end
				i += 1
			end
			if i <= len then
				local esign, ee = 1, 0
				c = b(val, i)
				if c == 45 then esign = -1; i += 1
				elseif c == 43 then i += 1 end
				while i <= len do
					c = b(val, i)
					if c < 48 or c > 57 then break end
					ee = ee * 10 + (c - 48)
					i += 1
				end
				exp += ee * esign
			end
			if mant == 0 then
				m, e = 0, 0
			else
				m = sign * mant * pow10[-(mantDigits - 1)]
				e = exp + mantDigits - 1
			end
		end
	end
	if m == 0 then
		buffer.writef64(out, 0, 0)
		buffer.writei32(out, 8, 0)
		return out
	end
	if e < 0 then
		buffer.writef64(out, 0, m >= 0 and 0 or -1)
		buffer.writei32(out, 8, 0)
		return out
	end
	if e < 16 then
		local scaled = m * pow10[e]
		if m < 0 then
			scaled = math.ceil(scaled)
		else
			scaled = math.floor(scaled)
		end
		if scaled == 0 then
			buffer.writef64(out, 0, 0)
			buffer.writei32(out, 8, 0)
			return out
		end
		local ne = math.floor(math.log10(math.abs(scaled)))
		local nm = scaled / pow10[ne]
		buffer.writef64(out, 0, nm)
		buffer.writei32(out, 8, ne)
		return out
	end
	if m < 0 and m % 1 ~= 0 then
		m -= 1
	end
	buffer.writef64(out, 0, m)
	buffer.writei32(out, 8, e)
	return out
end

function Bnum.min<T...>(...: T...): buffer
	local args: any = {...}
	if #args == 0 then
		error("Bnum.min: expected at least one argument")
	end
	local out = buffer.create(12)
	local bestMan: number, bestExp: number
	for i = 1, #args do
		local val: any = args[i]
		local m: number, e: number
		if type(val) == "buffer" then
			m, e = buffer.readf64(val, 0), buffer.readi32(val, 8)
		elseif type(val) == "number" then
			if val == 0 then
				m, e = 0, 0
			elseif val ~= val then
				m, e = 0/0, 0
			elseif val == math.huge then
				m, e = 1, math.huge
			elseif val == -math.huge then
				m, e = -1, math.huge
			else
				local a = math.abs(val)
				if a >= 1e10 or a <= 1e-10 then
					local ee = math.floor(math.log10(a))
					m, e = val / pow10[ee], ee
				else
					m, e = val, 0
				end
			end
		elseif type(val) == "string" then
			local len = #val
			if len == 0 then
				m, e = 0/0, 0
			else
				local i2, sign = 1, 1
				local b = string.byte
				local c = b(val, i2)
				if c == 45 then sign = -1; i2 += 1
				elseif c == 43 then i2 += 1 end
				local mant, mantDigits, exp = 0, 0, 0
				local frac = false
				while i2 <= len do
					c = b(val, i2)
					if c >= 48 and c <= 57 then
						if mantDigits < 17 then
							mant = mant * 10 + (c - 48)
							mantDigits += 1
						else
							exp += 1
						end
						if frac then exp -= 1 end
					elseif c == 46 then
						if frac then break end
						frac = true
					elseif c == 69 or c == 101 then
						i2 += 1
						break
					else
						break
					end
					i2 += 1
				end
				if i2 <= len then
					local esign, ee = 1, 0
					c = b(val, i2)
					if c == 45 then esign = -1; i2 += 1
					elseif c == 43 then i2 += 1 end
					while i2 <= len do
						c = b(val, i2)
						if c < 48 or c > 57 then break end
						ee = ee * 10 + (c - 48)
						i2 += 1
					end
					exp += ee * esign
				end
				if mant == 0 then
					m, e = 0, 0
				else
					m = sign * mant * pow10[-(mantDigits - 1)]
					e = exp + mantDigits - 1
				end
			end
		else
			error("Bnum.min: invalid argument type")
		end
		if i == 1 then
			bestMan, bestExp = m, e
		else
			if e < bestExp or (e == bestExp and m < bestMan) then
				bestMan, bestExp = m, e
			end
		end
	end
	buffer.writef64(out, 0, bestMan)
	buffer.writei32(out, 8, bestExp)
	return out
end

function Bnum.max<T...>(...: T...): buffer
	local args: any = {...}
	if #args == 0 then
		error("Bnum.max: expected at least one argument")
	end
	local out = buffer.create(12)
	local bestMan: number, bestExp: number
	for i = 1, #args do
		local val = args[i]
		local m, e
		if type(val) == "buffer" then
			m, e = buffer.readf64(val, 0), buffer.readi32(val, 8)
		elseif type(val) == "number" then
			if val == 0 then
				m, e = 0, 0
			elseif val ~= val then
				m, e = 0/0, 0
			elseif val == math.huge then
				m, e = 1, math.huge
			elseif val == -math.huge then
				m, e = -1, math.huge
			else
				local a = math.abs(val)
				if a >= 1e10 or a <= 1e-10 then
					local ee = math.floor(math.log10(a))
					m, e = val / pow10[ee], ee
				else
					m, e = val, 0
				end
			end
		elseif type(val) == "string" then
			local len = #val
			if len == 0 then
				m, e = 0/0, 0
			else
				local i2, sign = 1, 1
				local b = string.byte
				local c = b(val, i2)
				if c == 45 then sign = -1; i2 += 1
				elseif c == 43 then i2 += 1 end
				local mant, mantDigits, exp = 0, 0, 0
				local frac = false
				while i2 <= len do
					c = b(val, i2)
					if c >= 48 and c <= 57 then
						if mantDigits < 17 then
							mant = mant * 10 + (c - 48)
							mantDigits += 1
						else
							exp += 1
						end
						if frac then exp -= 1 end
					elseif c == 46 then
						if frac then break end
						frac = true
					elseif c == 69 or c == 101 then
						i2 += 1
						break
					else
						break
					end
					i2 += 1
				end
				if i2 <= len then
					local esign, ee = 1, 0
					c = b(val, i2)
					if c == 45 then esign = -1; i2 += 1
					elseif c == 43 then i2 += 1 end
					while i2 <= len do
						c = b(val, i2)
						if c < 48 or c > 57 then break end
						ee = ee * 10 + (c - 48)
						i2 += 1
					end
					exp += ee * esign
				end
				if mant == 0 then
					m, e = 0, 0
				else
					m = sign * mant * pow10[-(mantDigits - 1)]
					e = exp + mantDigits - 1
				end
			end
		else
			error("Bnum.max: invalid argument type")
		end
		if i == 1 then
			bestMan, bestExp = m, e
		else
			if e > bestExp or (e == bestExp and m > bestMan) then
				bestMan, bestExp = m, e
			end
		end
	end
	buffer.writef64(out, 0, bestMan)
	buffer.writei32(out, 8, bestExp)
	return out
end

function Bnum.mod(val1: any, val2: any): buffer
	local m1: number, e1: number, m2: number, e2: number
	local out = buffer.create(12)
	if type(val1) == "buffer" then
		m1, e1 = buffer.readf64(val1, 0), buffer.readi32(val1, 8)
	elseif type(val1) == "number" then
		if val1 == 0 then m1, e1 = 0, 0
		elseif val1 ~= val1 then m1, e1 = 0/0, 0
		elseif val1 == math.huge then m1, e1 = 1, math.huge
		elseif val1 == -math.huge then m1, e1 = -1, math.huge
		else
			local absn = math.abs(val1)
			if absn >= 1e10 or absn <= 1e-10 then
				local ee = math.floor(math.log10(absn))
				m1, e1 = val1 / pow10[ee], ee
			else
				m1, e1 = val1, 0
			end
		end
	elseif type(val1) == "string" then
		local len = #val1
		if len == 0 then m1, e1 = 0/0, 0 end
		local i = 1
		local sign = 1
		local c = string.byte(val1, i)
		if c == 45 then sign = -1; i += 1
		elseif c == 43 then i += 1 end
		local mant, mantDigits, exp = 0, 0, 0
		local frac = false
		local b = string.byte
		while i <= len do
			c = b(val1, i)
			if c >= 48 and c <= 57 then
				if mantDigits < 17 then
					mant = mant * 10 + (c - 48)
					mantDigits += 1
				else
					exp += 1
				end
				if frac then exp -= 1 end
			elseif c == 46 then
				if frac then break end
				frac = true
			elseif c == 69 or c == 101 then
				i += 1
				break
			else
				break
			end
			i += 1
		end
		if i <= len then
			local esign, ee = 1, 0
			c = b(val1, i)
			if c == 45 then esign = -1; i += 1
			elseif c == 43 then i += 1 end
			while i <= len do
				c = b(val1, i)
				if c < 48 or c > 57 then break end
				ee = ee * 10 + (c - 48)
				i += 1
			end
			exp += ee * esign
		end
		if mant == 0 then m1, e1 = 0, 0
		else
			m1, e1 = sign * mant * pow10[-(mantDigits-1)], exp + mantDigits - 1
		end
	end
	if type(val2) == "buffer" then
		m2, e2 = buffer.readf64(val2, 0), buffer.readi32(val2, 8)
	elseif type(val2) == "number" then
		if val2 == 0 then error("Bnum.mod: division by zero")
		elseif val2 ~= val2 then m2, e2 = 0/0, 0
		elseif val2 == math.huge then m2, e2 = 1, math.huge
		elseif val2 == -math.huge then m2, e2 = -1, math.huge
		else
			local absn = math.abs(val2)
			if absn >= 1e10 or absn <= 1e-10 then
				local ee = math.floor(math.log10(absn))
				m2, e2 = val2 / pow10[ee], ee
			else
				m2, e2 = val2, 0
			end
		end
	elseif type(val2) == "string" then
		local len = #val2
		if len == 0 then m2, e2 = 0/0, 0 end
		local i = 1
		local sign = 1
		local c = string.byte(val2, i)
		if c == 45 then sign = -1; i += 1
		elseif c == 43 then i += 1 end
		local mant, mantDigits, exp = 0, 0, 0
		local frac = false
		local b = string.byte
		while i <= len do
			c = b(val2, i)
			if c >= 48 and c <= 57 then
				if mantDigits < 17 then
					mant = mant * 10 + (c - 48)
					mantDigits += 1
				else
					exp += 1
				end
				if frac then exp -= 1 end
			elseif c == 46 then
				if frac then break end
				frac = true
			elseif c == 69 or c == 101 then
				i += 1
				break
			else
				break
			end
			i += 1
		end
		if i <= len then
			local esign, ee = 1, 0
			c = b(val2, i)
			if c == 45 then esign = -1; i += 1
			elseif c == 43 then i += 1 end
			while i <= len do
				c = b(val2, i)
				if c < 48 or c > 57 then break end
				ee = ee * 10 + (c - 48)
				i += 1
			end
			exp += ee * esign
		end
		if mant == 0 then m2, e2 = 0, 0
		else
			m2, e2 = sign * mant * pow10[-(mantDigits-1)], exp + mantDigits - 1
		end
	end
	local de = e1 - e2
	if de >= 13 then
		buffer.writef64(out, 0, m1)
		buffer.writei32(out, 8, e1)
		return out
	end
	if de <= -13 then
		buffer.writef64(out, 0, m1)
		buffer.writei32(out, 8, e1)
		return out
	end
	if de > 0 then
		m2 *= pow10[-de]
		e2 = e1
	elseif de < 0 then
		m1 *= pow10[de]
		e1 = e2
	end
	local rem = m1 - math.floor(m1 / m2) * m2
	local remE = e1
	if rem == 0 then
		buffer.writef64(out, 0, 0)
		buffer.writei32(out, 8, 0)
	else
		while rem >= 10 do rem *= 0.1; remE += 1 end
		while rem > 0 and rem < 1 do rem *= 10; remE -= 1 end
		buffer.writef64(out, 0, rem)
		buffer.writei32(out, 8, remE)
	end
	return out
end

function Bnum.modf(val: any): (buffer, buffer)
	local m: number, e: number
	local intBuf = buffer.create(12)
	local fracBuf = buffer.create(12)
	if type(val) == "buffer" then
		m, e = buffer.readf64(val, 0), buffer.readi32(val, 8)
	elseif type(val) == "number" then
		if val == 0 then
			buffer.writef64(intBuf, 0, 0)
			buffer.writei32(intBuf, 8, 0)
			buffer.writef64(fracBuf, 0, 0)
			buffer.writei32(fracBuf, 8, 0)
			return intBuf, fracBuf
		end
		local absn = math.abs(val)
		if absn >= 1e10 or absn <= 1e-10 then
			e = math.floor(math.log10(absn))
			m = val / pow10[e]
		else
			m, e = val, 0
		end
	elseif type(val) == "string" then
		local len = #val
		if len == 0 then
			m, e = 0/0, 0
		else
			local i = 1
			local sign = 1
			local c = string.byte(val, i)
			if c == 45 then sign = -1; i += 1
			elseif c == 43 then i += 1 end
			local mant, mantDigits, exp = 0, 0, 0
			local frac = false
			local b = string.byte
			while i <= len do
				c = b(val, i)
				if c >= 48 and c <= 57 then
					if mantDigits < 17 then
						mant = mant * 10 + (c - 48)
						mantDigits += 1
					else
						exp += 1
					end
					if frac then exp -= 1 end
				elseif c == 46 then
					if frac then break end
					frac = true
				elseif c == 69 or c == 101 then
					i += 1
					break
				else
					break
				end
				i += 1
			end
			if i <= len then
				local esign, ee = 1, 0
				c = b(val, i)
				if c == 45 then esign = -1; i += 1
				elseif c == 43 then i += 1 end
				while i <= len do
					c = b(val, i)
					if c < 48 or c > 57 then break end
					ee = ee * 10 + (c - 48)
					i += 1
				end
				exp += ee * esign
			end
			if mant == 0 then
				m, e = 0, 0
			else
				m, e = sign * mant * pow10[-(mantDigits-1)], exp + mantDigits - 1
			end
		end
	end
	if m == 0 then
		buffer.writef64(intBuf, 0, 0)
		buffer.writei32(intBuf, 8, 0)
		buffer.writef64(fracBuf, 0, 0)
		buffer.writei32(fracBuf, 8, 0)
		return intBuf, fracBuf
	end
	local intM, intE, fracM, fracE
	if e < 0 then
		intM, intE = 0, 0
		fracM, fracE = m, e
	else
		intM = m * pow10[e]
		local intFloor = (intM >= 0) and math.floor(intM) or math.ceil(intM)
		intE = math.floor(math.log10(math.abs(intFloor)))
		intM = intFloor / pow10[intE]
		fracM = m * pow10[e] - intFloor
		if fracM == 0 then
			fracE, fracM = 0, 0
		else
			fracE = math.floor(math.log10(math.abs(fracM)))
			fracM = fracM / pow10[fracE]
		end
	end
	buffer.writef64(intBuf, 0, intM)
	buffer.writei32(intBuf, 8, intE)
	buffer.writef64(fracBuf, 0, fracM)
	buffer.writei32(fracBuf, 8, fracE)
	return intBuf, fracBuf
end

function Bnum.fmod(n1: any, n2: any): buffer
	local m1: number, e1: number, m2: number, e2: number
	local out = buffer.create(12)
	if type(n1) == "buffer" then
		m1, e1 = buffer.readf64(n1, 0), buffer.readi32(n1, 8)
	elseif type(n1) == "number" then
		if n1 == 0 then m1, e1 = 0, 0
		else
			local absn = math.abs(n1)
			if absn >= 1e10 or absn <= 1e-10 then
				e1 = math.floor(math.log10(absn))
				m1 = n1 / pow10[e1]
			else
				m1, e1 = n1, 0
			end
		end
	elseif type(n1) == "string" then
		local len = #n1
		if len == 0 then m1, e1 = 0/0, 0
		else
			local i = 1
			local sign = 1
			local c = string.byte(n1, i)
			if c == 45 then sign = -1; i += 1
			elseif c == 43 then i += 1 end
			local mant, mantDigits, exp = 0, 0, 0
			local frac = false
			local b = string.byte
			while i <= len do
				c = b(n1, i)
				if c >= 48 and c <= 57 then
					if mantDigits < 17 then mant = mant * 10 + (c - 48); mantDigits += 1
					else exp += 1 end
					if frac then exp -= 1 end
				elseif c == 46 then
					if frac then break end
					frac = true
				elseif c == 69 or c == 101 then
					i += 1
					break
				else
					break
				end
				i += 1
			end
			if i <= len then
				local esign, ee = 1, 0
				c = b(n1, i)
				if c == 45 then esign = -1; i += 1
				elseif c == 43 then i += 1 end
				while i <= len do
					c = b(n1, i)
					if c < 48 or c > 57 then break end
					ee = ee * 10 + (c - 48)
					i += 1
				end
				exp += ee * esign
			end
			if mant == 0 then m1, e1 = 0, 0
			else m1, e1 = sign * mant * pow10[-(mantDigits-1)], exp + mantDigits - 1
			end
		end
	end
	if type(n2) == "buffer" then
		m2, e2 = buffer.readf64(n2, 0), buffer.readi32(n2, 8)
	elseif type(n2) == "number" then
		if n2 == 0 then error("Bnum.fmod: division by zero") end
		local absn = math.abs(n2)
		if absn >= 1e10 or absn <= 1e-10 then
			e2 = math.floor(math.log10(absn))
			m2 = n2 / pow10[e2]
		else
			m2, e2 = n2, 0
		end
	elseif type(n2) == "string" then
		local len = #n2
		if len == 0 then m2, e2 = 0/0, 0
		else
			local i = 1
			local sign = 1
			local c = string.byte(n2, i)
			if c == 45 then sign = -1; i += 1
			elseif c == 43 then i += 1 end
			local mant, mantDigits, exp = 0, 0, 0
			local frac = false
			local b = string.byte
			while i <= len do
				c = b(n2, i)
				if c >= 48 and c <= 57 then
					if mantDigits < 17 then mant = mant * 10 + (c - 48); mantDigits += 1
					else exp += 1 end
					if frac then exp -= 1 end
				elseif c == 46 then
					if frac then break end
					frac = true
				elseif c == 69 or c == 101 then
					i += 1
					break
				else
					break
				end
				i += 1
			end
			if i <= len then
				local esign, ee = 1, 0
				c = b(n2, i)
				if c == 45 then esign = -1; i += 1
				elseif c == 43 then i += 1 end
				while i <= len do
					c = b(n2, i)
					if c < 48 or c > 57 then break end
					ee = ee * 10 + (c - 48)
					i += 1
				end
				exp += ee * esign
			end
			if mant == 0 then m2, e2 = 0, 0
			else m2, e2 = sign * mant * pow10[-(mantDigits-1)], exp + mantDigits - 1
			end
		end
	end
	if e1 < e2 or (e1 == e2 and m1 < m2) then
		buffer.writef64(out, 0, m1)
		buffer.writei32(out, 8, e1)
		return out
	end
	local de = e1 - e2
	if de > 0 then
		m2 = m2 * pow10[de]
		e2 = e1
	elseif de < 0 then
		m1 = m1 * pow10[-de]
		e1 = e2
	end
	local q = math.floor(m1 / m2)
	local r = m1 - m2 * q
	if r == 0 then
		buffer.writef64(out, 0, 0)
		buffer.writei32(out, 8, 0)
	else
		local ae = math.floor(math.log10(math.abs(r)))
		if r >= 10 or r < 1 then
			r = r / pow10[ae]
			e1 = e1 + ae
		end
		buffer.writef64(out, 0, r)
		buffer.writei32(out, 8, e1)
	end
	return out
end

function Bnum.slog(val: any): buffer
	local m: number, e: number
	if type(val) == "buffer" then
		m, e = buffer.readf64(val, 0), buffer.readi32(val, 8)
	elseif type(val) == "number" then
		if val == 0 then
			local out = buffer.create(12)
			buffer.writef64(out, 0, -math.huge)
			buffer.writei32(out, 8, 0)
			return out
		end
		local absn = math.abs(val)
		if absn >= 1e10 or absn <= 1e-10 then
			e = math.floor(math.log10(absn))
			m = val / pow10[e]
		else
			m, e = val, 0
		end
	elseif type(val) == "string" then
		local len = #val
		if len == 0 then m, e = 0/0, 0
		else
			local i = 1
			local sign = 1
			local c = string.byte(val, i)
			if c == 45 then sign = -1; i += 1
			elseif c == 43 then i += 1 end
			local mant, mantDigits, exp = 0, 0, 0
			local frac = false
			local b = string.byte
			while i <= len do
				c = b(val, i)
				if c >= 48 and c <= 57 then
					if mantDigits < 17 then mant = mant * 10 + (c - 48); mantDigits += 1
					else exp += 1 end
					if frac then exp -= 1 end
				elseif c == 46 then
					if frac then break end
					frac = true
				elseif c == 69 or c == 101 then
					i += 1
					break
				else
					break
				end
				i += 1
			end
			if i <= len then
				local esign, ee = 1, 0
				c = b(val, i)
				if c == 45 then esign = -1; i += 1
				elseif c == 43 then i += 1 end
				while i <= len do
					c = b(val, i)
					if c < 48 or c > 57 then break end
					ee = ee * 10 + (c - 48)
					i += 1
				end
				exp += ee * esign
			end
			if mant == 0 then m, e = 0, 0
			else m, e = sign * mant * pow10[-(mantDigits-1)], exp + mantDigits - 1
			end
		end
	end
	if m <= 0 then
		local out = buffer.create(12)
		buffer.writef64(out, 0, 0/0)
		buffer.writei32(out, 8, 0)
		return out
	end
	local count = 0
	local total = m * pow10[e]
	while total >= 10 do
		total = math.log10(total)
		count += 1
	end
	local newM = total
	local newE = count
	local exp = math.floor(math.log10(newM))
	local man = newM/pow10[exp]
	local out = buffer.create(12)
	buffer.writef64(out, 0, man)
	buffer.writei32(out, 8, exp)
	return out
end

local scale = 1e6
local zero = 4e18

function Bnum.lbencode(val: any): buffer
	local m: number, e: number
	local out = buffer.create(12)
	if type(val) == "buffer" then
		m, e = buffer.readf64(val, 0), buffer.readi32(val, 8)
	elseif type(val) == "number" then
		if val == 0 then
			buffer.writef64(out, 0, 0)
			buffer.writei32(out, 8, 0)
			return out
		end
		local absn = math.abs(val)
		if absn >= 1e10 or absn <= 1e-10 then
			e = math.floor(math.log10(absn))
			m = val / pow10[e]
		else
			m, e = val, 0
		end
	elseif type(val) == "string" then
		local len = #val
		if len == 0 then m, e = 0/0, 0
		else
			local i = 1
			local sign = 1
			local c = string.byte(val, i)
			if c == 45 then sign = -1; i += 1
			elseif c == 43 then i += 1 end
			local mant, mantDigits, exp = 0, 0, 0
			local frac = false
			local b = string.byte
			while i <= len do
				c = b(val, i)
				if c >= 48 and c <= 57 then
					if mantDigits < 17 then mant = mant * 10 + (c - 48); mantDigits += 1
					else exp += 1 end
					if frac then exp -= 1 end
				elseif c == 46 then
					if frac then break end
					frac = true
				elseif c == 69 or c == 101 then
					i += 1
					break
				else
					break
				end
				i += 1
			end
			if i <= len then
				local esign, ee = 1, 0
				c = b(val, i)
				if c == 45 then esign = -1; i += 1
				elseif c == 43 then i += 1 end
				while i <= len do
					c = b(val, i)
					if c < 48 or c > 57 then break end
					ee = ee * 10 + (c - 48)
					i += 1
				end
				exp += ee * esign
			end
			if mant == 0 then m, e = 0, 0
			else m, e = sign * mant * pow10[-(mantDigits-1)], exp + mantDigits - 1
			end
		end
	else
		error("Bnum.lbencode: invalid type")
	end
	buffer.writef64(out, 0, m)
	buffer.writei32(out, 8, e)
	return out
end

function Bnum.lbdecode(encodedBuf: buffer): buffer
	local out = buffer.create(12)
	local man = buffer.readf64(encodedBuf, 0)
	local exp = buffer.readi32(encodedBuf, 8)
	if man == 0 and exp == 0 then
		buffer.writef64(out, 0, 0)
		buffer.writei32(out, 8, 0)
		return out
	end
	if man ~= 0 then
		local absMan = math.abs(man)
		if absMan >= 10 then
			local delta = math.floor(math.log10(absMan))
			man = man / pow10[delta]
			exp = exp + delta
		elseif absMan < 1 then
			local delta = math.floor(math.log10(absMan))
			man = man / pow10[delta]
			exp = exp + delta
		end
	end
	buffer.writef64(out, 0, man)
	buffer.writei32(out, 8, exp)
	return out
end

function Bnum.encodeData(val: any, oldData: any): buffer
	local newBuff = Bnum.lbencode(val)
	if not oldData then return newBuff end
	local manNew, expNew = buffer.readf64(newBuff, 0), buffer.readi32(newBuff, 8)
	local manOld, expOld = buffer.readf64(oldData, 0), buffer.readi32(oldData, 8)
	local useOld
	if expOld > expNew then
		useOld = true
	elseif expOld < expNew then
		useOld = false
	else
		useOld = manOld >= manNew
	end
	local out = buffer.create(12)
	if useOld then
		buffer.writef64(out, 0, manOld)
		buffer.writei32(out, 8, expOld)
	else
		buffer.writef64(out, 0, manNew)
		buffer.writei32(out, 8, expNew)
	end
	return out
end

function Bnum.Comma(val: any, digits: number?): string
	digits = digits or 2
	if type(val) ~= "number" then
		val = Bnum.toNumber(val)
	end
	local factor = pow10[digits]
	val = math.floor(val * factor + 0.001) / factor
	local intPart, fracPart = tostring(val):match("^(%-?%d+)%.?(%d*)$")
	intPart = intPart:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	intPart = intPart:gsub("^,", "")
	if fracPart ~= "" then
		fracPart = fracPart:: string .. string.rep("0", digits:: number - #fracPart:: number)
		return intPart .. "." .. fracPart:: string
	else
		return intPart
	end
end

local first = {'', 'k', 'm', 'b'}
local firstset = {"", "U","D","T","Qd","Qn","Sx","Sp","Oc","No"}
local second = {"", "De","Vt","Tg","qg","Qg","sg","Sg","Og","Ng"}
local third = {"", "Ce", "Du","Tr","Qa","Qi","Se","Si","Ot","Ni"}

function Bnum.format(val: any, digits: number?): string
	digits = digits or 2
	local m: number, e: number
	if type(val) == "buffer" then
		m, e = buffer.readf64(val, 0), buffer.readi32(val, 8)
	elseif type(val) == "number" then
		if val == 0 then return "0" end
		local absn = math.abs(val)
		if absn >= 1e10 or absn <= 1e-10 then
			e = math.floor(math.log10(absn))
			m = val / pow10[e]
		else
			m, e = val, 0
		end
	elseif type(val) == "string" then
		local len = #val
		if len == 0 then m, e = 0/0, 0
		else
			local i = 1
			local sign = 1
			local c = string.byte(val, i)
			if c == 45 then sign = -1; i += 1
			elseif c == 43 then i += 1 end
			local mant, mantDigits, exp = 0, 0, 0
			local frac = false
			local b = string.byte
			while i <= len do
				c = b(val, i)
				if c >= 48 and c <= 57 then
					if mantDigits < 17 then mant = mant * 10 + (c - 48); mantDigits += 1
					else exp += 1 end
					if frac then exp -= 1 end
				elseif c == 46 then
					if frac then break end
					frac = true
				elseif c == 69 or c == 101 then
					i += 1
					break
				else
					break
				end
				i += 1
			end
			if i <= len then
				local esign, ee = 1, 0
				c = b(val, i)
				if c == 45 then esign = -1; i += 1
				elseif c == 43 then i += 1 end
				while i <= len do
					c = b(val, i)
					if c < 48 or c > 57 then break end
					ee = ee * 10 + (c - 48)
					i += 1
				end
				exp += ee * esign
			end
			if mant == 0 then m, e = 0, 0
			else m, e = sign * mant * pow10[-(mantDigits-1)], exp + mantDigits - 1
			end
		end
	else
		error("Bnum.format: invalid type")
	end
	if m ~= m then return "NaN" end
	if e == math.huge then return m >= 0 and "Inf" or "-Inf" end
	if m == 0 then return "0" end
	if e < 3000 then
		if e <= -3 then
			local index = math.floor(-e / 3)
			m = math.floor(m * pow10[digits] + 0.5) / pow10[digits]
			if index <= 3 then
				return "1/" .. m .. (first[index + 1] or "")
			else
				local a = index % 10
				local b = (index // 10) % 10
				local c = (index // 100) % 10
				return "1/" .. m .. firstset[a + 1] .. second[b + 1] .. third[c + 1]
			end
		end
		if e < 3 then
			local num = m * pow10[e]
			local factor = pow10[digits]
			num = math.floor(num * factor + 0.5) / factor
			return tostring(num)
		end
		local index = math.floor(e / 3)
		local rem = e % 3
		local scaled = m * pow10[rem]
		scaled = math.floor(scaled * pow10[digits] + 0.5) / pow10[digits]
		if index <= 3 then
			return scaled .. (first[index + 1] or "")
		else
			local a = index % 10
			local b = (index // 10) % 10
			local c = (index // 100) % 10
			return scaled .. firstset[a + 1] .. second[b + 1] .. third[c + 1]
		end
	end
	local eMan: number, eExp: number = e, 0
	if eMan >= 1e10 then
		eExp = math.floor(math.log10(eMan))
		eMan = eMan / pow10[eExp]
	end
	local expStr
	if eExp < 3 then
		expStr = string.format("%.":: string .. digits:: number .. "f":: string, eMan:: number * pow10[eExp]:: number):: any
	else
		local index = math.floor(eExp / 3)
		local rem = eExp % 3
		local scaled = eMan * pow10[rem]
		scaled = math.floor(scaled * pow10[digits] + 0.5) / pow10[digits]
		if index <= 3 then
			expStr = scaled .. (first[index + 1] or "")
		else
			local a = index % 10
			local b = (index // 10) % 10
			local c = (index // 100) % 10
			expStr = scaled .. firstset[a + 1] .. second[b + 1] .. third[c + 1]
		end
	end
	return "E" .. expStr
end

return table.freeze(Bnum)
