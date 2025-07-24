#!/usr/bin/env julia

if isempty(ARGS)
    println("Usage: smart_quotes.jl file1.md [file2.md ...]")
    exit(1)
end

isalnum(c::Char) = isletter(c) || isnumeric(c)

function smart_quotes(text::String)
    result = IOBuffer()

    is_open_double = true
    is_open_single = true
    in_code_block = false
    in_math_block = false

    for line in eachline(IOBuffer(text))
        # Toggle code block state
        if contains(line, "```")
            in_code_block = !in_code_block
            println(result, line)
            continue
        end

        # Toggle math block state
        if contains(line, "\$\$")
            in_math_block = !in_math_block
            println(result, line)
            continue
        end

        if in_code_block || in_math_block
            println(result, line)
            continue
        end

        # Process inline within line
        buf = IOBuffer()
        in_inline_code = false
        in_inline_math = false

        i = firstindex(line)
        n = lastindex(line)
        while i <= n
            c = line[i]
            i1 = i < n ? nextind(line, i) : i + 1
            i2 = i1 < n ? nextind(line, i1) : i1 + 1
            if c == '`'
                print(buf, c)
                in_inline_code = !in_inline_code
                i = i1
            elseif c == '$'
                print(buf, c)
                in_inline_math = !in_inline_math
                i = i1
            elseif in_inline_code || in_inline_math
                print(buf, c)
                i = i1
            elseif c == '"'
                print(buf, is_open_double ? '“' : '”')
                is_open_double = !is_open_double
                i = i1
            elseif c == '\''
                print(buf, is_open_single ? '‘' : '’')
                is_open_single = !is_open_single
                i = i1
            elseif i2 <= n &&
                isalnum(line[i]) && line[i1] == '\'' && isalnum(line[i2])
                # Contractions: don’t
                print(buf, line[i], '’', line[i2])
                i = nextind(line, i2)
            else
                print(buf, c)
                i = i1
            end
        end
        println(result, String(take!(buf)))
    end

    return String(take!(result))
end

for path in ARGS
    text = read(path, String)
    text = smart_quotes(text)
    write(path, text)
end
