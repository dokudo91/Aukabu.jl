using ArgParse
using DataFrames, CSV

function create_settings()
    s = ArgParseSettings()::ArgParseSettings
    @add_arg_table! s begin
        "order"
        action = :command
        help = "注文を発注する"
        "close"
        action = :command
        help = "全てのポジションを閉じる"
    end
    @add_arg_table! s["order"] begin
        "--read", "-r"
        default = "order.csv"
        help = "注文CSVパス"
        "--login", "-l"
        default = "loginpass"
        help = "ログインパスワード"
        "--trade", "-t"
        default = "tradepass"
        help = "トレードパスワード"
    end
    @add_arg_table! s["close"] begin
        "--login", "-l"
        default = "loginpass"
        help = "ログインパスワード"
        "--trade", "-t"
        default = "tradepass"
        help = "トレードパスワード"
    end
    s
end

function run_cmd()
    s = create_settings()
    args = parse_args(s; as_symbols=true)::Dict{Symbol,Any}
    command = args[:_COMMAND_]::Symbol
    cargs = args[command]::Dict{Symbol,Any}
    if command == :order
        run_order(cargs)
    elseif command == :order
        run_close(cargs)
    end
end

"""
```
s = create_settings()
args = parse_args(["order"], s; as_symbols=true)
command = args[:_COMMAND_]
cargs = args[command]
run_order(cargs)
```
"""
function run_order(cargs)
    csvpath = cargs[:read]::String
    loginpassword = cargs[:login]::String
    Password = cargs[:trade]::String
    orderdf = CSV.File(csvpath) |> DataFrame
    token = get_token(loginpassword)
    failcount = 0
    for row in eachrow(orderdf)
        ret = send_order(token, row.symbol |> string, row.value, row.side |> Symbol, Password)
        if ret == :FailWallet
            failcount == 3 && break
            failcount += 1
        end
    end
end

function run_close(cargs)
    loginpassword = cargs[:login]::String
    Password = cargs[:trade]::String
    token = get_token(loginpassword)
    close_positions(token, Password)
end

isinteractive() || run_cmd()
