using HTTP, JSON3, Dates
using TOML

const AUKABU_URL = "http://localhost:18080/kabusapi"

function get_token(password)
    json_data = JSON3.write(Dict(:APIPassword => password))
    response = HTTP.post("$AUKABU_URL/token", headers(), json_data)
    content = JSON3.read(String(response.body))
    content.Token
end

headers() = ["Content-Type" => "application/json"]
headers(token) = ["Content-Type" => "application/json", "X-API-KEY" => token]

unregister_all(token) = HTTP.put("$AUKABU_URL/unregister/all", headers(token))

function get_orders(token)
    query = Dict("product" => "2", "details" => false, "cashmargin" => "2")
    response = HTTP.get("$AUKABU_URL/orders", headers(token); query)
    JSON3.read(String(response.body))
end

function cancel_orders(token, tradepassword)
    orders = get_orders(token)
    responses = JSON3.Object[]
    for order in orders
        order.State in [1, 3] || continue
        json_data = JSON3.write(Dict(
            :OrderId => order.ID,
            :Password => tradepassword,
        ))
        response = HTTP.put("$AUKABU_URL/cancelorder", headers(token), json_data)
        push!(responses, JSON3.read(String(response.body)))
    end
    responses
end

function get_positions(token)
    response = HTTP.get("$AUKABU_URL/positions", headers(token); query=Dict("product" => "2"))
    JSON3.read(String(response.body))
end

function get_wallet(token)
    response = HTTP.get("$AUKABU_URL/wallet/margin", headers(token))
    JSON3.read(String(response.body))
end

function get_wallet(token, symbol)
    response = HTTP.get("$AUKABU_URL/wallet/margin/$symbol@1", headers(token))
    JSON3.read(String(response.body))
end

function get_symbolinfo(token, symbol)
    response = HTTP.get("$AUKABU_URL/symbol/$symbol@1", headers(token); query=Dict("addinfo" => "true"))
    JSON3.read(String(response.body))
end
function get_board(token, symbol)
    response = HTTP.get("$AUKABU_URL/board/$symbol@1", headers(token))
    JSON3.read(String(response.body))
end
function get_regulations(token, symbol)
    response = HTTP.get("$AUKABU_URL/regulations/$symbol@1", headers(token))
    JSON3.read(String(response.body))
end

function create_json(; kwargs...)
    kwargs = filter(x -> !isnothing(x[2]), kwargs)
    JSON3.write(Dict(kwargs))::String
end

function create_orderbody(; Password="", Symbol="", Side="2", Qty=0, Price=0,
    Exchange=1, SecurityType=1, CashMargin=2, MarginTradeType=3,
    DelivType=0, AccountType=4, FrontOrderType=20, ExpireDay=0, ClosePositionOrder=nothing)
    create_json(;
        Password, Symbol, Side, Qty, Price, Exchange, SecurityType, CashMargin,
        MarginTradeType, DelivType, AccountType, FrontOrderType, ExpireDay, ClosePositionOrder)
end

function send_order(token, symbol, value, side, Password)
    unregister_all(token)
    symbolinfo = get_symbolinfo(token, symbol)
    can_margintrade(symbolinfo, side) || return :FailMarginTrade
    board = get_board(token, symbol)
    orderupper = rationalize(3symbolinfo.UpperLimit + symbolinfo.LowerLimit) // 4
    orderlower = rationalize(symbolinfo.UpperLimit + 3symbolinfo.LowerLimit) // 4
    price = rationalize(board.CalcPrice + ifelse(side == :buy, orderupper, orderlower)) // 2
    fprice = floor_price(price, symbolinfo.PriceRangeGroup)
    wallet = get_wallet(token, symbol)
    # 証拠金口座の実質的な価値を計算
    marginvalue = wallet.MarginAccountWallet * 100 / (100 + wallet.ConsignmentDepositRate)
    # 注文金額と証拠金口座の価値を比較し、丸め関数を決定
    if marginvalue > value
        Qty = round(Int, value / board.CalcPrice / symbolinfo.TradingUnit) * symbolinfo.TradingUnit
    else
        Qty = floor(Int, marginvalue / fprice / symbolinfo.TradingUnit) * symbolinfo.TradingUnit
    end
    Qty == 0 && return :FailWallet
    Side = ifelse(side == :buy, "2", "1")
    body = create_orderbody(; Password, Symbol=symbol, Side, Qty, Price=fprice)
    response = HTTP.post("$AUKABU_URL/sendorder", headers(token), body)
    content = JSON3.read(String(response.body))
    if content.Result == 0
        return :Success
    else
        return :FailOrder
    end
end

function can_margintrade(symbolinfo, side)
    if side == :buy
        return symbolinfo.KCMarginBuy::Bool
    else
        return symbolinfo.KCMarginSell::Bool
    end
end
read_pricerange() = TOML.parsefile(joinpath(@__DIR__, "PriceRange.toml"))
function floor_price(price, group)
    priceranges = read_pricerange()
    grouprange = convert(Dict{String,Int}, priceranges[group])
    pricepairs = sort([parse(Float64, k) => rationalize(v) for (k, v) in grouprange], by=x -> x[1])
    for (max_price, unit) in pricepairs
        price ≤ max_price && return floor(price // unit) * unit
    end
end

function close_positions(token, Password)
    positions = get_positions(token)
    responses = JSON3.Object[]
    for position in positions
        Qty = position.LeavesQty - position.HoldQty
        Qty == 0 && continue
        Side = ifelse(position.Side == "1", "2", "1")
        MarginTradeType = position.MarginTradeType
        body = create_orderbody(;
            Password, Symbol=position.Symbol, Side, Qty, CashMargin=3, MarginTradeType, DelivType=2, 
            ClosePositionOrder=0, FrontOrderType=16)
        response = HTTP.post("$AUKABU_URL/sendorder", headers(token), body)
        push!(responses, JSON3.read(String(response.body)))
        sleep(1)
    end
    responses
end