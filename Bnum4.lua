--!strict
--!optimize 2
local Bnum = {}
local ln10 = 2.302585092994046

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

function Bnum.read(buff: buffer): (number, number)
	return buffer.readf64(buff, 0), buffer.readi32(buff, 8)
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
	local man, exp
	if n >= 1e10 or n <= -1e10 or (n > 0 and n < 1e-10) or (n < 0 and n > -1e-10) then
		exp = math.floor(math.log10(math.abs(n)))
		man = n / (10 ^ exp)
	else
		man = n
		exp = 0
	end
	buffer.writef64(buf, 0, man)
	buffer.writei32(buf, 8, exp)
	return buf
end

function Bnum.toNumber(buff: buffer): number
	local man, exp = Bnum.read(buff)
	return man * 10^exp
end

function Bnum.add(a: any, b: any): buffer
	local m1, e1, m2, e2
	if type(a) == "buffer" then
		m1 = buffer.readf64(a, 0)
		e1 = buffer.readi32(a, 8)
	else
		if a == 0 then
			m1, e1 = 0, 0
		else
			local abs = math.abs(a)
			if abs >= 1e10 or abs <= 1e-10 then
				e1 = math.floor(math.log10(abs))
				m1 = a / (10 ^ e1)
			else
				m1, e1 = a, 0
			end
		end
	end
	if type(b) == "buffer" then
		m2 = buffer.readf64(b, 0)
		e2 = buffer.readi32(b, 8)
	else
		if b == 0 then
			m2, e2 = 0, 0
		else
			local abs = math.abs(b)
			if abs >= 1e10 or abs <= 1e-10 then
				e2 = math.floor(math.log10(abs))
				m2 = b / (10 ^ e2)
			else
				m2, e2 = b, 0
			end
		end
	end
	if m1 == 0 then return Bnum.new(m2, e2) end
	if m2 == 0 then return Bnum.new(m1, e1) end
	local de = e1 - e2
	if de >= 13 then return Bnum.new(m1, e1) end
	if de <= -13 then return Bnum.new(m2, e2) end
	if de > 0 then
		m2 *= 10 ^ (-de)
		e2 = e1
	elseif de < 0 then
		m1 *= 10 ^ de
		e1 = e2
	end
	local m = m1 + m2
	if m == 0 then return Bnum.zero end
	local e = e1
	local am = math.abs(m)
	if am >= 10 then
		m *= 0.1
		e += 1
	elseif am < 1 then
		m *= 10
		e -= 1
	end
	local out = buffer.create(12)
	buffer.writef64(out, 0, m)
	buffer.writei32(out, 8, e)
	return out
end

function Bnum.sub(n1: any, n2: any): buffer
	local man1, exp1, man2, exp2
	if type(n1) == "buffer" then
		man1 = buffer.readf64(n1, 0)
		exp1 = buffer.readi32(n1, 8)
	elseif type(n1) == "number" then
		if n1 == 0 then
			man1, exp1 = 0, 0
		else
			local a = math.abs(n1)
			if a >= 1e10 or a <= 1e-10 then
				exp1 = math.floor(math.log10(a))
				man1 = n1 * 10 ^ -exp1
			else
				man1, exp1 = n1, 0
			end
		end
	else
		error("Bnum.sub: invalid n1")
	end
	if type(n2) == "buffer" then
		man2 = buffer.readf64(n2, 0)
		exp2 = buffer.readi32(n2, 8)
	elseif type(n2) == "number" then
		if n2 == 0 then
			man2, exp2 = 0, 0
		else
			local a = math.abs(n2)
			if a >= 1e10 or a <= 1e-10 then
				exp2 = math.floor(math.log10(a))
				man2 = n2 * 10 ^ -exp2
			else
				man2, exp2 = n2, 0
			end
		end
	else
		error("Bnum.sub: invalid n2")
	end
	local out = buffer.create(12)
	if man2 == 0 then
		buffer.writef64(out, 0, man1)
		buffer.writei32(out, 8, exp1)
		return out
	elseif man1 == 0 then
		buffer.writef64(out, 0, -man2)
		buffer.writei32(out, 8, exp2)
		return out
	end
	if exp1 >= exp2 + 16 then
		buffer.writef64(out, 0, man1)
		buffer.writei32(out, 8, exp1)
		return out
	elseif exp2 >= exp1 + 16 then
		buffer.writef64(out, 0, -man2)
		buffer.writei32(out, 8, exp2)
		return out
	end
	if exp1 > exp2 then
		man2 *= 10 ^ (exp2 - exp1)
		exp2 = exp1
	elseif exp2 > exp1 then
		man1 *= 10 ^ (exp1 - exp2)
		exp1 = exp2
	end
	local diff = man1 - man2
	local exp = exp1
	if diff < 0 then
		buffer.writef64(out, 0, 0)
		buffer.writei32(out, 8, 0)
		return out
	end
	if diff == 0 then
		buffer.writef64(out, 0, 0)
		buffer.writei32(out, 8, 0)
		return out
	end
	local a = math.abs(diff)
	if a >= 10 then
		diff *= 0.1
		exp += 1
	elseif a < 1 then
		diff *= 10
		exp -= 1
	end
	buffer.writef64(out, 0, diff)
	buffer.writei32(out, 8, exp)
	return out
end

function Bnum.mul(n1: any, n2: any): buffer
	local man1, exp1, man2, exp2
	if type(n1) == "buffer" then
		man1 = buffer.readf64(n1, 0)
		exp1 = buffer.readi32(n1, 8)
	elseif type(n1) == "number" then
		if n1 == 0 then
			man1, exp1 = 0, 0
		else
			local sign = math.sign(n1)
			local absn = math.abs(n1)
			if absn >= 1e10 or absn <= 1e-10 then
				exp1 = math.floor(math.log10(absn))
				man1 = sign * absn / (10^exp1)
			else
				man1 = n1
				exp1 = 0
			end
		end
	else
		error("Bnum.mul: invalid type n1")
	end
	if type(n2) == "buffer" then
		man2 = buffer.readf64(n2, 0)
		exp2 = buffer.readi32(n2, 8)
	elseif type(n2) == "number" then
		if n2 == 0 then
			man2, exp2 = 0, 0
		else
			local sign = math.sign(n2)
			local absn = math.abs(n2)
			if absn >= 1e10 or absn <= 1e-10 then
				exp2 = math.floor(math.log10(absn))
				man2 = sign * absn / (10^exp2)
			else
				man2 = n2
				exp2 = 0
			end
		end
	else
		error("Bnum.mul: invalid type n2")
	end
	local out = buffer.create(12)
	if man1 == 0 or man2 == 0 then
		buffer.writef64(out, 0, 0)
		buffer.writei32(out, 8, 0)
		return out
	end
	local man = man1 * man2
	local exp = exp1 + exp2
	local absMan = math.abs(man)
	if absMan >= 10 or absMan < 1 then
		local delta = math.floor(math.log10(absMan))
		man = man / (10^delta)
		exp = exp + delta
	end
	buffer.writef64(out, 0, man)
	buffer.writei32(out, 8, exp)
	return out
end

function Bnum.recip(n: any): buffer
	local man, exp
	if type(n) == "buffer" then
		man = buffer.readf64(n, 0)
		exp = buffer.readi32(n, 8)
	elseif type(n) == "number" then
		if n == 0 then
			error("Bnum.recip: division by zero")
		end
		local a = math.abs(n)
		if a >= 1e10 or a <= 1e-10 then
			exp = math.floor(math.log10(a))
			man = n * 10 ^ -exp
		else
			man, exp = n, 0
		end
	else
		error("Bnum.recip: invalid type")
	end
	if man == 0 then
		error("Bnum.recip: division by zero")
	end
	local out = buffer.create(12)
	local rMan = 1 / man
	local rExp = -exp
	if math.abs(rMan) < 1 then
		rMan *= 10
		rExp -= 1
	end
	buffer.writef64(out, 0, rMan)
	buffer.writei32(out, 8, rExp)
	return out
end

function Bnum.div(n1: any, n2: any): buffer
	local man1, exp1, man2, exp2
	if type(n1) == "buffer" then
		man1 = buffer.readf64(n1, 0)
		exp1 = buffer.readi32(n1, 8)
	elseif type(n1) == "number" then
		if n1 == 0 then
			man1, exp1 = 0, 0
		else
			local a = math.abs(n1)
			if a >= 1e10 or a <= 1e-10 then
				exp1 = math.floor(math.log10(a))
				man1 = n1 * 10 ^ -exp1
			else
				man1, exp1 = n1, 0
			end
		end
	else
		error("Bnum.div: invalid type n1")
	end
	if type(n2) == "buffer" then
		man2 = buffer.readf64(n2, 0)
		exp2 = buffer.readi32(n2, 8)
	elseif type(n2) == "number" then
		if n2 == 0 then
			error("Bnum.div: division by zero")
		end
		local a = math.abs(n2)
		if a >= 1e10 or a <= 1e-10 then
			exp2 = math.floor(math.log10(a))
			man2 = n2 * 10 ^ -exp2
		else
			man2, exp2 = n2, 0
		end
	else
		error("Bnum.div: invalid type n2")
	end
	if man2 == 0 then
		error("Bnum.div: division by zero")
	end
	local out = buffer.create(12)
	local man = man1 / man2
	local exp = exp1 - exp2
	local a = man
	if a < 0 then a = -a end
	if a >= 10 then
		man *= 0.1
		exp += 1
	elseif a < 1 and a ~= 0 then
		man *= 10
		exp -= 1
	end
	buffer.writef64(out, 0, man)
	buffer.writei32(out, 8, exp)
	return out
end

function Bnum.pow(val1: any, val2: any): buffer
	local man1, exp1
	if type(val1) == "buffer" then
		man1 = buffer.readf64(val1, 0)
		exp1 = buffer.readi32(val1, 8)
	else
		local a = math.abs(val1)
		exp1 = (a >= 1e10 or a <= 1e-10) and math.floor(math.log10(a)) or 0
		man1 = val1 / (10^exp1)
	end
	local man2, exp2
	if type(val2) == "buffer" then
		man2 = buffer.readf64(val2, 0)
		exp2 = buffer.readi32(val2, 8)
	else
		local a = math.abs(val2)
		exp2 = (a >= 1e10 or a <= 1e-10) and math.floor(math.log10(a)) or 0
		man2 = val2 / (10^exp2)
	end
	if man1 == 0 then return (man2 == 0 and Bnum.one or Bnum.zero) end
	if man1 == 1 and exp1 == 0 then return Bnum.one end
	if man2 == 0 and exp2 == 0 then return Bnum.one end
	if man1 < 0 then
		local n = man2 * (10^exp2)
		if n % 1 ~= 0 then return Bnum.nan end 
		local res = Bnum.pow(Bnum.new(-man1, exp1), val2)
		if n % 2 ~= 0 then
			buffer.writef64(res, 0, -buffer.readf64(res, 0))
		end
		return res
	end
	local logVal1 = math.log10(man1) + exp1
	local powVal = logVal1 * man2 * (10^exp2)
	if powVal == math.huge then return Bnum.inf end
	if powVal == -math.huge then return Bnum.zero end
	local newE = math.floor(powVal)
	local newM = 10^(powVal - newE)
	if newM >= 10 then
		newM = newM * 0.1
		newE = newE + 1
	end
	local buf = buffer.create(12)
	buffer.writef64(buf, 0, newM)
	buffer.writei32(buf, 8, newE)
	return buf
end

function Bnum.pow10(val: any): buffer
	local man, exp
	if type(val) == "buffer" then
		man = buffer.readf64(val, 0)
		exp = buffer.readi32(val, 8)
	elseif type(val) == "number" then
		if val == 0 then
			local out = buffer.create(12)
			buffer.writef64(out, 0, 1)
			buffer.writei32(out, 8, 0)
			return out
		end
		local absn = math.abs(val)
		exp = (absn >= 1e10 or absn <= 1e-10) and math.floor(math.log10(absn)) or 0
		man = val / (10^exp)
	else
		error("Bnum.pow10: invalid type")
	end
	local total = man * (10^exp)
	local newE = math.floor(total)
	local newM = 10^(total - newE)
	if newM >= 10 then
		newM *= 0.1
		newE += 1
	elseif newM > 0 and newM < 1 then
		newM *= 10
		newE -= 1
	end
	local out = buffer.create(12)
	buffer.writef64(out, 0, newM)
	buffer.writei32(out, 8, newE)
	return out
end

function Bnum.ln(val: any): buffer
	local man, exp
	if type(val) == "buffer" then
		man = buffer.readf64(val, 0)
		exp = buffer.readi32(val, 8)
	elseif type(val) == "number" then
		if val == 0 then
			man, exp = 0, 0
		else
			local a = math.abs(val)
			exp = (a >= 1e10 or a <= 1e-10) and math.floor(math.log10(a)) or 0
			man = val / (10^exp)
		end
	else
		error("Bnum.ln: invalid type")
	end
	local buf = buffer.create(12)
	if man == 0 then
		buffer.writef64(buf, 0, -math.huge)
		buffer.writei32(buf, 8, 0)
		return buf
	elseif man ~= man or exp ~= exp or man < 0 then
		buffer.writef64(buf, 0, 0/0)
		buffer.writei32(buf, 8, 0)
		return buf
	elseif exp == math.huge then
		buffer.writef64(buf, 0, math.huge)
		buffer.writei32(buf, 8, 0)
		return buf
	end
	local result = math.log(man) + exp * 2.302585092994046
	buffer.writef64(buf, 0, result)
	buffer.writei32(buf, 8, 0)
	return buf
end

function Bnum.log10(val: any): buffer
	local man, exp
	if type(val) == "buffer" then
		man = buffer.readf64(val, 0)
		exp = buffer.readi32(val, 8)
	elseif type(val) == "number" then
		if val == 0 then
			man, exp = 0, 0
		else
			local a = math.abs(val)
			exp = (a >= 1e10 or a <= 1e-10) and math.floor(math.log10(a)) or 0
			man = val / (10^exp)
		end
	else
		error("Bnum.log10: invalid type")
	end
	local buf = buffer.create(12)
	if man == 0 then
		buffer.writef64(buf, 0, -math.huge)
		buffer.writei32(buf, 8, 0)
		return buf
	elseif man ~= man or man < 0 then
		buffer.writef64(buf, 0, 0/0)
		buffer.writei32(buf, 8, 0)
		return buf
	elseif exp == math.huge then
		buffer.writef64(buf, 0, math.huge)
		buffer.writei32(buf, 8, 0)
		return buf
	end
	local result = math.log10(man) + exp
	buffer.writef64(buf, 0, result)
	buffer.writei32(buf, 8, 0)
	return buf
end

function Bnum.log(n1: any, n2: any): buffer
	local man1, exp1, man2, exp2
	if type(n1) == "buffer" then
		man1 = buffer.readf64(n1, 0)
		exp1 = buffer.readi32(n1, 8)
	else
		local a = math.abs(n1)
		exp1 = (a >= 1e10 or a <= 1e-10) and math.floor(math.log10(a)) or 0
		man1 = n1 / (10^exp1)
	end
	local buf = buffer.create(12)
	if man1 <= 0 or man1 ~= man1 then
		buffer.writef64(buf, 0, 0/0)
		buffer.writei32(buf, 8, 0)
		return buf
	end
	if not n2 then
		local result = math.log(man1) + exp1 * 2.302585092994046
		buffer.writef64(buf, 0, result)
		buffer.writei32(buf, 8, 0)
		return buf
	end
	if type(n2) == "buffer" then
		man2 = buffer.readf64(n2, 0)
		exp2 = buffer.readi32(n2, 8)
	else
		local a = math.abs(n2)
		exp2 = (a >= 1e10 or a <= 1e-10) and math.floor(math.log10(a)) or 0
		man2 = n2 / (10^exp2)
	end
	if man2 <= 0 or man2 ~= man2 then
		buffer.writef64(buf, 0, 0/0)
		buffer.writei32(buf, 8, 0)
		return buf
	end
	local result = (math.log(man1) + exp1 * 2.302585092994046) / (math.log(man2) + exp2 * 2.302585092994046)
	buffer.writef64(buf, 0, result)
	buffer.writei32(buf, 8, 0)
	return buf
end

function Bnum.random(min: any, max: any): buffer
	if not min or not max then
		local buff = buffer.create(12)
		buffer.writef64(buff, 0, math.random())
		buffer.writei32(buff, 8, 0)
		return buff
	end
	local minMan, minExp
	if type(min) == "buffer" then
		minMan = buffer.readf64(min, 0)
		minExp = buffer.readi32(max, 8)
	else
		local absn = math.abs(min)
		minExp = (absn >= 1e10 or absn <= 1e-10) and math.floor(math.log10(absn)) or 0
		minMan = min / (10 ^ minExp)
	end
	local maxMan, maxExp
	if type(max) == "buffer" then
		maxMan = buffer.readf64(max, 0)
		maxExp = buffer.readi32(max, 8)
	else
		local absn = math.abs(max)
		maxExp = (absn >= 1e10 or absn <= 1e-10) and math.floor(math.log10(absn)) or 0
		maxMan = max / (10 ^ maxExp)
	end
	local minLog, maxLog = math.log10(math.abs(minMan)) + minExp, math.log10(math.abs(maxMan)) + maxExp
	if minLog > maxLog then
		minLog, maxLog = maxLog, minLog
	end
	local rLog = minLog + math.random() * (maxLog - minLog)
	local exp = math.floor(rLog)
	local man = 10^(rLog-exp)
	local buff = buffer.create(12)
	buffer.writef64(buff, 0, man)
	buffer.writei32(buff, 8, exp)
	return buff
end

function Bnum.me(a: any, b: any): boolean
	local m1, e1
	if type(a) == "buffer" then
		m1 = buffer.readf64(a, 0)
		e1 = buffer.readi32(a, 8)
	else
		local absn = math.abs(a)
		e1 = (absn >= 1e10 or absn <= 1e-10) and math.floor(math.log10(absn)) or 0
		m1 = a / (10 ^ e1)
	end
	local m2, e2
	if type(b) == "buffer" then
		m2 = buffer.readf64(b, 0)
		e2 = buffer.readi32(b, 8)
	else
		local absn = math.abs(b)
		e2 = (absn >= 1e10 or absn <= 1e-10) and math.floor(math.log10(absn)) or 0
		m2 = b / (10 ^ e2)
	end
	if e1 ~= e2 then
		return e1 > e2
	end
	return m1 > m2
end

function Bnum.eq(a: any, b: any): boolean
	local m1, e1
	if type(a) == "buffer" then
		m1 = buffer.readf64(a, 0)
		e1 = buffer.readi32(a, 8)
	else
		local absn = math.abs(a)
		e1 = (absn >= 1e10 or absn <= 1e-10) and math.floor(math.log10(absn)) or 0
		m1 = a / (10 ^ e1)
	end
	local m2, e2
	if type(b) == "buffer" then
		m2 = buffer.readf64(b, 0)
		e2 = buffer.readi32(b, 8)
	else
		local absn = math.abs(b)
		e2 = (absn >= 1e10 or absn <= 1e-10) and math.floor(math.log10(absn)) or 0
		m2 = b / (10 ^ e2)
	end
	return m1 == m2 and e1 == e2
end

function Bnum.le(a: any, b: any): boolean
	local m1, e1
	if type(a) == "buffer" then
		m1 = buffer.readf64(a, 0)
		e1 = buffer.readi32(a, 8)
	else
		local absn = math.abs(a)
		e1 = (absn >= 1e10 or absn <= 1e-10) and math.floor(math.log10(absn)) or 0
		m1 = a / (10 ^ e1)
	end
	local m2, e2
	if type(b) == "buffer" then
		m2 = buffer.readf64(b, 0)
		e2 = buffer.readi32(b, 8)
	else
		local absn = math.abs(b)
		e2 = (absn >= 1e10 or absn <= 1e-10) and math.floor(math.log10(absn)) or 0
		m2 = b / (10 ^ e2)
	end
	if e1 ~= e2 then
		return e1 < e2
	end
	return m1 < m2
end

function Bnum.meeq(a: any, b: any): boolean
	local m1, e1
	if type(a) == "buffer" then
		m1 = buffer.readf64(a, 0)
		e1 = buffer.readi32(a, 8)
	else
		local absn = math.abs(a)
		e1 = (absn >= 1e10 or absn <= 1e-10) and math.floor(math.log10(absn)) or 0
		m1 = a / (10 ^ e1)
	end
	local m2, e2
	if type(b) == "buffer" then
		m2 = buffer.readf64(b, 0)
		e2 = buffer.readi32(b, 8)
	else
		local absn = math.abs(b)
		e2 = (absn >= 1e10 or absn <= 1e-10) and math.floor(math.log10(absn)) or 0
		m2 = b / (10 ^ e2)
	end
	if e1 ~= e2 then
		return e1 > e2
	end
	return m1 >= m2
end

function Bnum.leeq(a: any, b: any): boolean
	local m1, e1
	if type(a) == "buffer" then
		m1 = buffer.readf64(a, 0)
		e1 = buffer.readi32(a, 8)
	else
		local absn = math.abs(a)
		e1 = (absn >= 1e10 or absn <= 1e-10) and math.floor(math.log10(absn)) or 0
		m1 = a / (10 ^ e1)
	end
	local m2, e2
	if type(b) == "buffer" then
		m2 = buffer.readf64(b, 0)
		e2 = buffer.readi32(b, 8)
	else
		local absn = math.abs(b)
		e2 = (absn >= 1e10 or absn <= 1e-10) and math.floor(math.log10(absn)) or 0
		m2 = b / (10 ^ e2)
	end
	if e1 ~= e2 then
		return e1 < e2
	end
	return m1 <= m2
end

function Bnum.abs(val: any): buffer
	local man, exp
	local out: buffer
	if type(val) == 'buffer' then
		man = buffer.readf64(val, 0)
		exp = buffer.readi32(val, 8)
		out = val
	elseif type(val) == "number" then
		if val == 0 then
			out = buffer.create(12)
			buffer.writef64(out, 0, 0)
			buffer.writei32(out, 8, 0)
			return out
		end
		local absn = math.abs(val)
		if absn >= 1e10 or absn <= 1e-10 then
			exp = math.floor(math.log10(absn))
			man = val / (10^exp)
		else
			man = val
			exp = 0
		end
		out = buffer.create(12)
	else
		error("Bnum.abs: invalid type")
	end
	if man < 0 then
		man =-man
	end
	buffer.writef64(out, 0, man)
	buffer.writei32(out, 8, exp)
	return out
end

function Bnum.round(val: any, digits: number?): buffer
	digits = digits or 0
	local man, exp, out: buffer
	if type(val) == 'buffer' then
		man, exp = buffer.readf64(val, 0), buffer.readi32(val, 8)
	elseif type(val) == 'number' then
		if val == 0 then
			out = buffer.create(12)
			buffer.writef64(out, 0, 0)
			buffer.writei32(out, 8, 0)
			return out
		end
		local abs = math.abs(val)
		if abs >= 1e10 or abs <= 1e-10 then
			exp = math.floor(math.log10(abs))
			man = val/(10^exp)
		else
			man = val
			exp = 0
		end
		out = buffer.create(12)
	else
		error('Bnum.round: invalid type')
	end
	out = buffer.create(12)
	if man == 0 then
		buffer.writef64(out, 0, 0)
		buffer.writei32(out, 8, 0)
		return out
	end
	if digits > 0 then
		local scale = 10^digits
		man = math.floor(man*scale + 0.05)/scale
		if man >= 10 then
			man *= 0.1
			exp += 1
		elseif man > 0 and man < 1 then
			man *= 10
			exp -= 1
		end
	end
	buffer.writef64(out, 0, man)
	buffer.writei32(out, 8, exp)
	return out
end

function Bnum.ceil(val: any, digits: number?): buffer
	digits = digits or 0
	local man, exp, out: buffer
	if type(val) == 'buffer' then
		man, exp = buffer.readf64(val, 0), buffer.readi32(val, 8)
	elseif type(val) == 'number' then
		if val == 0 then
			out = buffer.create(12)
			buffer.writef64(out, 0, 0)
			buffer.writei32(out, 8, 0)
			return out
		end
		local abs = math.abs(val)
		if abs >= 1e10 or abs <= 1e-10 then
			exp = math.floor(math.log10(abs))
			man = val/(10^exp)
		else
			man = val
			exp = 0
		end
		out = buffer.create(12)
	else
		error('Bnum.round: invalid type')
	end
	out = buffer.create(12)
	if man == 0 then
		buffer.writef64(out, 0, 0)
		buffer.writei32(out, 8, 0)
		return out
	end
	if digits > 0 then
		local scale = 10^digits
		man = math.ceil(man*scale)/scale
		if man >= 10 then
			man *= 0.1
			exp += 1
		elseif man > 0 and man < 1 then
			man *= 10
			exp -= 1
		end
	end
	buffer.writef64(out, 0, man)
	buffer.writei32(out, 8, exp)
	return out
end

function Bnum.clamp(val: any, min: any, max: any): buffer
	local out = buffer.create(12)
	local manV, expV
	if type(val) == "buffer" then
		manV = buffer.readf64(val, 0)
		expV = buffer.readi32(val, 8)
	elseif type(val) == "number" then
		if val == 0 then
			manV, expV = 0, 0
		else
			local absV = math.abs(val)
			if absV >= 1e10 or absV <= 1e-10 then
				expV = math.floor(math.log10(absV))
				manV = val / (10^expV)
			else
				manV, expV = val, 0
			end
		end
	else
		error("Bnum.clamp: invalid val type")
	end
	local manMin, expMin
	if type(min) == "buffer" then
		manMin = buffer.readf64(min, 0)
		expMin = buffer.readi32(min, 8)
	elseif type(min) == "number" then
		if min == 0 then
			manMin, expMin = 0, 0
		else
			local absMin = math.abs(min)
			if absMin >= 1e10 or absMin <= 1e-10 then
				expMin = math.floor(math.log10(absMin))
				manMin = min / (10^expMin)
			else
				manMin, expMin = min, 0
			end
		end
	else
		error("Bnum.clamp: invalid min type")
	end
	local manMax, expMax
	if type(max) == "buffer" then
		manMax = buffer.readf64(max, 0)
		expMax = buffer.readi32(max, 8)
	elseif type(max) == "number" then
		if max == 0 then
			manMax, expMax = 0, 0
		else
			local absMax = math.abs(max)
			if absMax >= 1e10 or absMax <= 1e-10 then
				expMax = math.floor(math.log10(absMax))
				manMax = max / (10^expMax)
			else
				manMax, expMax = max, 0
			end
		end
	else
		error("Bnum.clamp: invalid max type")
	end
	if expV < expMin or (expV == expMin and manV < manMax) then
		buffer.writef64(out, 0, manMin)
		buffer.writei32(out, 8, expMin)
		return out
	end
	if expV > expMax or (expV == expMax and manV > manMax) then
		buffer.writef64(out, 0, manMax)
		buffer.writei32(out, 8, expMax)
		return out
	end
	buffer.writef64(out, 0, manV)
	buffer.writei32(out, 8, expV)
	return out
end

function Bnum.sqrt(val: any): buffer
	local man, exp
	if type(val) == "buffer" then
		man = buffer.readf64(val, 0)
		exp = buffer.readi32(val, 8)
	elseif type(val) == "number" then
		if val == 0 then
			local out = buffer.create(12)
			buffer.writef64(out, 0, 0)
			buffer.writei32(out, 8, 0)
			return out
		end
		local absn = math.abs(val)
		exp = (absn >= 1e10 or absn <= 1e-10) and math.floor(math.log10(absn)) or 0
		man = val / (10^exp)
	else
		error("Bnum.sqrt: invalid type")
	end
	if man < 0 then
		local out = buffer.create(12)
		buffer.writef64(out, 0, 0/0)
		buffer.writei32(out, 8, 0)
		return out
	end
	if exp % 2 ~= 0 then
		man = man * 10
		exp = exp - 1
	end
	local newMan = math.sqrt(man)
	local newExp = exp / 2
	if newMan >= 10 then
		newMan *= 0.1
		newExp += 1
	elseif newMan > 0 and newMan < 1 then
		newMan *= 10
		newExp -= 1
	end
	local out = buffer.create(12)
	buffer.writef64(out, 0, newMan)
	buffer.writei32(out, 8, newExp)
	return out
end

function Bnum.cbrt(val: any): buffer
	local man, exp
	if type(val) == "buffer" then
		man = buffer.readf64(val, 0)
		exp = buffer.readi32(val, 8)
	elseif type(val) == "number" then
		if val == 0 then
			local out = buffer.create(12)
			buffer.writef64(out, 0, 0)
			buffer.writei32(out, 8, 0)
			return out
		end
		local absn = math.abs(val)
		exp = (absn >= 1e10 or absn <= 1e-10) and math.floor(math.log10(absn)) or 0
		man = val / (10^exp)
	else
		error("Bnum.cbrt: invalid type")
	end
	local sign = man < 0 and -1 or 1
	man = math.abs(man)
	local newMan = sign * man^(1/3)
	local newExp = exp / 3
	if newMan >= 10 then
		newMan *= 0.1
		newExp += 1
	elseif newMan > 0 and newMan < 1 then
		newMan *= 10
		newExp -= 1
	end
	local out = buffer.create(12)
	buffer.writef64(out, 0, newMan)
	buffer.writei32(out, 8, newExp)
	return out
end

function Bnum.root(val: any, n: number): buffer
	if n == 0 then error("root: n cannot be 0") end
	local man, exp
	if type(val) == "buffer" then
		man = buffer.readf64(val, 0)
		exp = buffer.readi32(val, 8)
	elseif type(val) == "number" then
		if val == 0 then
			local out = buffer.create(12)
			buffer.writef64(out, 0, 0)
			buffer.writei32(out, 8, 0)
			return out
		end
		local absn = math.abs(val)
		exp = (absn >= 1e10 or absn <= 1e-10) and math.floor(math.log10(absn)) or 0
		man = val / (10^exp)
	else
		error("root: invalid type")
	end
	if man < 0 and n % 2 == 0 then
		local out = buffer.create(12)
		buffer.writef64(out, 0, 0/0)
		buffer.writei32(out, 8, 0)
		return out
	end
	local sign = man < 0 and -1 or 1
	man = math.abs(man)
	local newMan = sign * man^(1/n)
	local newExp = exp / n
	if newMan >= 10 then
		newMan *= 0.1
		newExp += 1
	elseif newMan > 0 and newMan < 1 then
		newMan *= 10
		newExp -= 1
	end
	local out = buffer.create(12)
	buffer.writef64(out, 0, newMan)
	buffer.writei32(out, 8, newExp)
	return out
end

function Bnum.floor(val: any): buffer
	local man, exp
	local out = buffer.create(12)
	if type(val) == "buffer" then
		man = buffer.readf64(val, 0)
		exp = buffer.readi32(val, 8)
	elseif type(val) == "number" then
		if val == 0 then
			buffer.writef64(out, 0, 0)
			buffer.writei32(out, 8, 0)
			return out
		end
		local absn = math.abs(val)
		exp = (absn >= 1e10 or absn <= 1e-10) and math.floor(math.log10(absn)) or 0
		man = val / (10^exp)
	else
		error("Bnum.floor: invalid type")
	end
	if man == 0 then
		buffer.writef64(out, 0, 0)
		buffer.writei32(out, 8, 0)
		return out
	end
	if exp < 0 then
		buffer.writef64(out, 0, man >= 0 and 0 or -1)
		buffer.writei32(out, 8, 0)
		return out
	end
	if exp < 16 then
		local scaled = man * (10^exp)
		if man < 0 then scaled = math.ceil(scaled) else scaled = math.floor(scaled) end
		local newE = math.floor(math.log10(math.abs(scaled)))
		local newM = scaled / (10^newE)
		buffer.writef64(out, 0, newM)
		buffer.writei32(out, 8, newE)
		return out
	end
	if man < 0 then
		local flooredMan = man
		if man % 1 ~= 0 then flooredMan = man - 1 end
		buffer.writef64(out, 0, flooredMan)
	else
		buffer.writef64(out, 0, man)
	end
	buffer.writei32(out, 8, exp)
	return out
end

function Bnum.min<T...>(...: T...): buffer
	local args = {...}
	if #args == 0 then
		error("Bnum.min: expected at least one argument")
	end
	local out = buffer.create(12)
	local bestMan: any, bestExp: any
	for i = 1, #args do
		local man, exp
		local val: any = args[i]
		if type(val) == "buffer" then
			man = buffer.readf64(val, 0)
			exp = buffer.readi32(val, 8)
		elseif type(val) == "number" then
			if val == 0 then
				man, exp = 0, 0
			else
				local absn = math.abs(val)
				exp = (absn >= 1e10 or absn <= 1e-10) and math.floor(math.log10(absn)) or 0
				man = val / (10^exp)
			end
		else
			error("Bnum.min: invalid argument type")
		end
		if i == 1 then
			bestMan, bestExp = man, exp
		else
			if exp > bestExp then
				bestMan, bestExp = bestMan, bestExp
			elseif exp < bestExp then
				bestMan, bestExp = man, exp
			else
				if man < bestMan then
					bestMan, bestExp = man, exp
				end
			end
		end
	end
	buffer.writef64(out, 0, bestMan)
	buffer.writei32(out, 8, bestExp)
	return out
end

function Bnum.max<T...>(...: T...): buffer
	local args = {...}
	if #args == 0 then
		error("Bnum.max: expected at least one argument")
	end
	local out = buffer.create(12)
	local bestMan: any, bestExp: any
	for i = 1, #args do
		local man, exp
		local val: any = args[i]
		if type(val) == "buffer" then
			man = buffer.readf64(val, 0)
			exp = buffer.readi32(val, 8)
		elseif type(val) == "number" then
			if val == 0 then
				man, exp = 0, 0
			else
				local absn = math.abs(val)
				exp = (absn >= 1e10 or absn <= 1e-10) and math.floor(math.log10(absn)) or 0
				man = val / (10^exp)
			end
		else
			error("Bnum.max: invalid argument type")
		end
		if i == 1 then
			bestMan, bestExp = man, exp
		else
			if exp > bestExp then
				bestMan, bestExp = man, exp
			elseif exp == bestExp and man > bestMan then
				bestMan, bestExp = man, exp
			end
		end
	end
	buffer.writef64(out, 0, bestMan)
	buffer.writei32(out, 8, bestExp)
	return out
end

function Bnum.mod(n1: any, n2: any): buffer
	local man1, exp1, man2, exp2
	local out = buffer.create(12)
	if type(n1) == "buffer" then
		man1 = buffer.readf64(n1, 0)
		exp1 = buffer.readi32(n1, 8)
	elseif type(n1) == "number" then
		if n1 == 0 then
			man1, exp1 = 0, 0
		else
			local absn = math.abs(n1)
			exp1 = (absn >= 1e10 or absn <= 1e-10) and math.floor(math.log10(absn)) or 0
			man1 = n1 / (10^exp1)
		end
	else
		error("Bnum.mod: invalid n1 type")
	end
	if type(n2) == "buffer" then
		man2 = buffer.readf64(n2, 0)
		exp2 = buffer.readi32(n2, 8)
	elseif type(n2) == "number" then
		if n2 == 0 then
			error("Bnum.mod: division by zero")
		else
			local absn = math.abs(n2)
			exp2 = (absn >= 1e10 or absn <= 1e-10) and math.floor(math.log10(absn)) or 0
			man2 = n2 / (10^exp2)
		end
	else
		error("Bnum.mod: invalid n2 type")
	end
	if exp1 < exp2 or (exp1 == exp2 and man1 < man2) then
		buffer.writef64(out, 0, man1)
		buffer.writei32(out, 8, exp1)
		return out
	end
	local deltaExp = exp1 - exp2
	local scaledMan2 = man2 * (10^deltaExp)
	local quotient = math.floor(man1 / scaledMan2)
	local remainder = man1 - scaledMan2 * quotient
	if remainder > 0 and remainder < 1 then
		remainder = remainder * 10
		deltaExp = deltaExp - 1
	end
	if remainder == 0 then
		buffer.writef64(out, 0, 0)
		buffer.writei32(out, 8, 0)
	else
		buffer.writef64(out, 0, remainder)
		buffer.writei32(out, 8, exp2 + deltaExp)
	end
	return out
end

function Bnum.modf(val: any): (buffer, buffer)
	local man, exp
	local intBuf = buffer.create(12)
	local fracBuf = buffer.create(12)
	if type(val) == "buffer" then
		man = buffer.readf64(val, 0)
		exp = buffer.readi32(val, 8)
	elseif type(val) == "number" then
		if val == 0 then
			buffer.writef64(intBuf, 0, 0)
			buffer.writei32(intBuf, 8, 0)
			buffer.writef64(fracBuf, 0, 0)
			buffer.writei32(fracBuf, 8, 0)
			return intBuf, fracBuf
		end
		local absn = math.abs(val)
		exp = (absn >= 1e10 or absn <= 1e-10) and math.floor(math.log10(absn)) or 0
		man = val / (10^exp)
	else
		error("Bnum.modf: invalid type")
	end
	if exp < 0 then
		buffer.writef64(intBuf, 0, 0)
		buffer.writei32(intBuf, 8, 0)
		buffer.writef64(fracBuf, 0, man)
		buffer.writei32(fracBuf, 8, exp)
		return intBuf, fracBuf
	end
	local intExp = exp
	local intMan = man
	if exp > 0 then
		intMan = man * (10^exp)
		local intFloor = math.floor(intMan)
		intExp = math.floor(math.log10(intFloor))
		intMan = intFloor / (10^intExp)
	end
	local fracMan = man * (10^exp) - math.floor(man * (10^exp))
	local fracExp = 0
	if fracMan ~= 0 then
		fracExp = math.floor(math.log10(math.abs(fracMan)))
		fracMan = fracMan / (10^fracExp)
	end
	buffer.writef64(intBuf, 0, intMan)
	buffer.writei32(intBuf, 8, intExp)
	buffer.writef64(fracBuf, 0, fracMan)
	buffer.writei32(fracBuf, 8, fracExp)
	return intBuf, fracBuf
end

function Bnum.fmod(n1: any, n2: any): buffer
	local man1, exp1, man2, exp2
	local out = buffer.create(12)
	if type(n1) == "buffer" then
		man1 = buffer.readf64(n1, 0)
		exp1 = buffer.readi32(n1, 8)
	elseif type(n1) == "number" then
		if n1 == 0 then
			buffer.writef64(out, 0, 0)
			buffer.writei32(out, 8, 0)
			return out
		end
		local absn = math.abs(n1)
		exp1 = (absn >= 1e10 or absn <= 1e-10) and math.floor(math.log10(absn)) or 0
		man1 = n1 / (10^exp1)
	else
		error("Bnum.fmod: invalid n1")
	end
	if type(n2) == "buffer" then
		man2 = buffer.readf64(n2, 0)
		exp2 = buffer.readi32(n2, 8)
	elseif type(n2) == "number" then
		if n2 == 0 then
			error("Bnum.fmod: division by zero")
		end
		local absn = math.abs(n2)
		exp2 = (absn >= 1e10 or absn <= 1e-10) and math.floor(math.log10(absn)) or 0
		man2 = n2 / (10^exp2)
	else
		error("Bnum.fmod: invalid n2")
	end
	if exp1 < exp2 or (exp1 == exp2 and man1 < man2) then
		buffer.writef64(out, 0, man1)
		buffer.writei32(out, 8, exp1)
		return out
	end
	if exp1 > exp2 then
		man2 = man2 * (10^(exp2 - exp1))
		exp2 = exp1
	end
	local quotient = math.floor(man1 / man2)
	local rem = man1 - quotient * man2
	local exp = exp1
	if rem ~= 0 then
		local absRem = math.abs(rem)
		if absRem >= 10 or absRem < 1 then
			local delta = math.floor(math.log10(absRem))
			rem = rem / (10^delta)
			exp = exp + delta
		end
	end
	buffer.writef64(out, 0, rem)
	buffer.writei32(out, 8, exp)
	return out
end

function Bnum.slog(val: any): buffer
	local man, exp
	if type(val) == "buffer" then
		man = buffer.readf64(val, 0)
		exp = buffer.readi32(val, 8)
	elseif type(val) == "number" then
		if val == 0 then
			local out = buffer.create(12)
			buffer.writef64(out, 0, -math.huge)
			buffer.writei32(out, 8, 0)
			return out
		end
		local absn = math.abs(val)
		exp = (absn >= 1e10 or absn <= 1e-10) and math.floor(math.log10(absn)) or 0
		man = val / (10^exp)
	else
		error("slog: invalid type")
	end
	if man <= 0 then
		local out = buffer.create(12)
		buffer.writef64(out, 0, 0/0)
		buffer.writei32(out, 8, 0)
		return out
	end
	local count = 0
	if exp > 10 then
		local newExp = math.log10(man) + exp
		man = newExp / 10
		exp = 1
		count = count + 1
	end
	local result = math.log10(man) + exp
	local out = buffer.create(12)
	buffer.writef64(out, 0, result)
	buffer.writei32(out, 8, count)
	return out
end

local scale = 1e6
local zero = 4e18

function Bnum.lbencode(val: any): buffer
	local out = buffer.create(12)
	local man, exp
	if type(val) == "buffer" then
		man = buffer.readf64(val, 0)
		exp = buffer.readi32(val, 8)
	elseif type(val) == "number" then
		if val == 0 then
			buffer.writef64(out, 0, 0)
			buffer.writei32(out, 8, 0)
			return out
		end
		local sign = math.sign(val)
		local absVal = math.abs(val)
		if absVal >= 10 or absVal <= 0.1 then
			exp = math.floor(math.log10(absVal))
			man = absVal / (10^exp) * sign
		else
			man = val
			exp = 0
		end
	else
		error("Bnum.lbencode: invalid type")
	end
	buffer.writef64(out, 0, man)
	buffer.writei32(out, 8, exp)
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
			man = man / (10^delta)
			exp = exp + delta
		elseif absMan < 1 then
			local delta = math.floor(math.log10(absMan))
			man = man / (10^delta)
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
	local factor = 10^digits
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

function suffixPart(x: number): string
	local a = x % 10
	local b = (x // 10) % 10
	local c = (x // 100) % 10
	return	firstset[a + 1] ..second[b + 1] ..third[c + 1]
end

function Bnum.short(val: any, digits: number?): string
	digits = digits or 2
	local man, exp
	if type(val) == "number" then
		man, exp = val, 0
	elseif type(val) == "buffer" then
		man = buffer.readf64(val, 0)
		exp = buffer.readi32(val, 8)
	else
		error("Bnum.short: invalid type")
	end
	if man ~= man then return "NaN" end
	if exp == math.huge then return man >= 0 and "Inf" or "-Inf" end
	if man == 0 then return "0" end
	if exp <= -3 then
		local index = math.floor(-exp / 3)
		man = math.floor(man * 100 + 0.1) / 100
		if index <= 3 then
			return "1/" .. man .. (first[index + 1] or "")
		else
			local a = index % 10
			local b = (index // 10) % 10
			local c = (index // 100) % 10
			return "1/" .. man .. firstset[a + 1] .. second[b + 1] .. third[c + 1]
		end
	end
	if exp < 3 then
		local num = man * (10 ^ exp)
		local factor = 10^digits
		num = math.floor(num * factor + 0.1) / factor
		return tostring(num)
	end
	local index = math.floor(exp / 3)
	local rem = exp % 3
	local scaled = man * (10 ^ rem)
	scaled = math.floor(scaled * (10 ^ digits) + 0.1) / (10 ^ digits)
	if index <= 3 then
		return scaled .. (first[index + 1] or "")
	else
		local a = index % 10
		local b = (index // 10) % 10
		local c = (index // 100) % 10
		return scaled .. firstset[a + 1] .. second[b + 1] .. third[c + 1]
	end
end

function Bnum.shortE(val: any, digits: number?): string
	digits = digits or 2
	local man, exp
	if type(val) == "buffer" then
		man = buffer.readf64(val, 0)
		exp = buffer.readi32(val, 8)
	elseif type(val) == "number" then
		local absn = math.abs(val)
		if absn >= 1e10 or absn <= 1e-10 then
			exp = math.floor(math.log10(absn))
			man = val / (10^exp)
		else
			man = val
			exp = 0
		end
	else
		error("Bnum.shortE: invalid type")
	end
	if man ~= man then return "NaN" end
	if exp == math.huge then return man >= 0 and "Inf" or "-Inf" end
	if man == 0 then return "0" end
	if exp < 3000 then
		digits = digits or 2
		local man, exp
		if type(val) == "number" then
			man, exp = val, 0
		elseif type(val) == "buffer" then
			man = buffer.readf64(val, 0)
			exp = buffer.readi32(val, 8)
		else
			error("Bnum.short: invalid type")
		end
		if man ~= man then return "NaN" end
		if exp == math.huge then return man >= 0 and "Inf" or "-Inf" end
		if man == 0 then return "0" end
		if exp <= -3 then
			local index = math.floor(-exp / 3)
			man = math.floor(man * 100 + 0.1) / 100
			if index <= 3 then
				return "1/" .. man .. (first[index + 1] or "")
			else
				local a = index % 10
				local b = (index // 10) % 10
				local c = (index // 100) % 10
				return "1/" .. man .. firstset[a + 1] .. second[b + 1] .. third[c + 1]
			end
		end
		if exp < 3 then
			local num = man * (10 ^ exp)
			local factor = 10^digits
			num = math.floor(num * factor + 0.1) / factor
			return tostring(num)
		end
		local index = math.floor(exp / 3)
		local rem = exp % 3
		local scaled = man * (10 ^ rem)
		scaled = math.floor(scaled * (10 ^ digits) + 0.1) / (10 ^ digits)
		if index <= 3 then
			return scaled .. (first[index + 1] or "")
		else
			local a = index % 10
			local b = (index // 10) % 10
			local c = (index // 100) % 10
			return scaled .. firstset[a + 1] .. second[b + 1] .. third[c + 1]
		end
	end
	local eMan, eExp = exp, 0
	if eMan >= 1e10 then
		eExp = math.floor(math.log10(eMan))
		eMan = eMan / (10^eExp)
	end
	local expStr
	if eExp < 3 then
		expStr = string.format("%.2f", eMan * 10^eExp)
	else
		local index = math.floor(eExp / 3)
		local rem = eExp % 3
		local scaled = eMan * (10 ^ rem)
		scaled = math.floor(scaled * 10^digits + 0.1) / (10^digits)
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

return Bnum
