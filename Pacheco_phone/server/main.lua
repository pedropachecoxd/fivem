local ESX = exports['es_extended']:getSharedObject()
local activeCalls = {}
local VehicleNames = {}

-- ==========================================
-- AUXILIARES
-- ==========================================
local function GenerateUniquePhoneNumber()
    local found = false; local number = ""
    while not found do
        number = string.format("+351 95%d %03d %03d", math.random(0,9), math.random(0,999), math.random(0,999))
        local result = MySQL.Sync.fetchScalar('SELECT phone_number FROM users WHERE phone_number = @number', {['@number']=number})
        if not result then found = true end
    end
    return number
end

local function GenerateUniqueIBAN()
    local found = false; local iban = ""
    while not found do
        iban = string.format("RP-%06d", math.random(100000,999999))
        local result = MySQL.Sync.fetchScalar('SELECT iban FROM users WHERE iban = @iban', {['@iban']=iban})
        if not result then found = true end
    end
    return iban
end

MySQL.ready(function()
    MySQL.Async.fetchAll('SELECT name, model FROM vehicles', {}, function(result)
        if result then
            for i=1,#result do
                local modelStr = result[i].model; local nameStr = result[i].name
                if modelStr and nameStr then
                    local hash = joaat(modelStr)
                    VehicleNames[hash] = nameStr; VehicleNames[modelStr] = nameStr; VehicleNames[string.lower(modelStr)] = nameStr
                end
            end
        end
    end)
end)

-- ==========================================
-- INIT E DADOS DO JOGADOR
-- ==========================================
ESX.RegisterUsableItem('phone', function(source)
    TriggerClientEvent('pacheco_phone:abrirTelefone', source)
end)

ESX.RegisterServerCallback('pacheco_phone:verificarItem', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    local item = xPlayer.getInventoryItem('phone')
    if item and item.count > 0 then cb(true) else cb(false) end
end)

ESX.RegisterServerCallback('pacheco_phone:getUserInfo', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        MySQL.Async.fetchAll('SELECT firstname, lastname, phone_number FROM users WHERE identifier = @identifier', {['@identifier']=xPlayer.identifier}, function(result)
            if result[1] then
                local nomeCompleto = (result[1].firstname or "Cidadão") .. " " .. (result[1].lastname or "")
                local numero = result[1].phone_number
                if numero == nil or numero == "" then
                    numero = GenerateUniquePhoneNumber()
                    MySQL.Async.execute('UPDATE users SET phone_number = @number WHERE identifier = @identifier', {['@number']=numero, ['@identifier']=xPlayer.identifier})
                end
                cb({nome=nomeCompleto, numero=numero, job=xPlayer.job.name})
            else cb({nome="Erro", numero="Erro", job="unemployed"}) end
        end)
    else cb({nome="Desconhecido", numero="Desconhecido", job="unemployed"}) end
end)

RegisterNetEvent('esx:playerLoaded')
AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    local identifier = xPlayer.getIdentifier()
    MySQL.Async.fetchScalar('SELECT phone_number FROM users WHERE identifier = @identifier', {['@identifier']=identifier}, function(number)
        if number == nil or number == "" then
            local newNumber = GenerateUniquePhoneNumber()
            MySQL.Async.execute('UPDATE users SET phone_number = @number WHERE identifier = @identifier', {['@number']=newNumber, ['@identifier']=identifier})
        end
    end)
end)

-- ==========================================
-- BANCO
-- ==========================================
ESX.RegisterServerCallback('pacheco_phone:getBankInfo', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        MySQL.Async.fetchScalar('SELECT iban FROM users WHERE identifier = @identifier', {['@identifier']=xPlayer.identifier}, function(iban)
            if not iban or iban == "" then
                iban = GenerateUniqueIBAN()
                MySQL.Async.execute('UPDATE users SET iban = @iban WHERE identifier = @identifier', {['@iban']=iban, ['@identifier']=xPlayer.identifier})
            end
            cb({saldo=xPlayer.getAccount('bank').money, iban=iban})
        end)
    else cb({saldo=0, iban="ERRO"}) end
end)

ESX.RegisterServerCallback('pacheco_phone:transferirDinheiro', function(source, cb, targetIban, amount)
    local xPlayer = ESX.GetPlayerFromId(source)
    local val = tonumber(amount)
    if not xPlayer then return cb(false, "Erro interno.") end
    if not val or val <= 0 then return cb(false, "Valor inválido.") end
    targetIban = string.upper(targetIban)
    MySQL.Async.fetchAll('SELECT identifier, iban FROM users WHERE iban = @iban', {['@iban']=targetIban}, function(result)
        if result[1] then
            local targetIdentifier = result[1].identifier
            if targetIdentifier == xPlayer.identifier then return cb(false, "Não podes enviar para ti próprio.") end
            if xPlayer.getAccount('bank').money >= val then
                xPlayer.removeAccountMoney('bank', val)
                local targetPlayer = ESX.GetPlayerFromIdentifier(targetIdentifier)
                if targetPlayer then
                    targetPlayer.addAccountMoney('bank', val)
                    TriggerClientEvent('esx:showNotification', targetPlayer.source, "~g~Transferência Recebida:~s~ "..val.."€ via IBAN.")
                else
                    MySQL.Async.fetchAll('SELECT accounts FROM users WHERE identifier = @identifier', {['@identifier']=targetIdentifier}, function(accResult)
                        if accResult[1] then
                            local accounts = json.decode(accResult[1].accounts)
                            if accounts and accounts.bank then
                                accounts.bank = accounts.bank + val
                                MySQL.Async.execute('UPDATE users SET accounts = @accounts WHERE identifier = @identifier', {['@accounts']=json.encode(accounts), ['@identifier']=targetIdentifier})
                            end
                        end
                    end)
                end
                MySQL.Async.execute('INSERT INTO pacheco_bank_transactions (identifier, type, amount) VALUES (@id, @type, @amount)', {['@id']=xPlayer.identifier, ['@type']='transferencia_enviada', ['@amount']=val})
                MySQL.Async.execute('INSERT INTO pacheco_bank_transactions (identifier, type, amount) VALUES (@id, @type, @amount)', {['@id']=targetIdentifier, ['@type']='transferencia_recebida', ['@amount']=val})
                cb(true, "Transferência enviada com sucesso!")
            else cb(false, "Saldo insuficiente.") end
        else cb(false, "IBAN não encontrado.") end
    end)
end)

ESX.RegisterServerCallback('pacheco_phone:getTransacoes', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then MySQL.Async.fetchAll('SELECT type, amount FROM pacheco_bank_transactions WHERE identifier = @identifier ORDER BY date DESC LIMIT 20', {['@identifier']=xPlayer.identifier}, function(result) cb(result) end) else cb({}) end
end)

ESX.RegisterServerCallback('pacheco_phone:getCreditos', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then MySQL.Async.fetchAll('SELECT amount, remaining_amount, daily_installment, status FROM pacheco_bank_loans WHERE identifier = @identifier ORDER BY id DESC', {['@identifier']=xPlayer.identifier}, function(result) cb(result) end) else cb({}) end
end)

-- ==========================================
-- GARAGEM
-- ==========================================
ESX.RegisterServerCallback('pacheco_phone:getGaragem', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return cb({}) end
    MySQL.Async.fetchAll("SELECT plate, vehicle, stored, garage, apreendido FROM owned_vehicles WHERE owner = @identifier", {['@identifier']=xPlayer.identifier}, function(results)
        local veiculos = {}
        if results then
            for i=1,#results do
                local row = results[i]; local vData = json.decode(row.vehicle)
                if vData then
                    local status = "Desconhecido"
                    if row.apreendido == 1 then status = "Apreendido" elseif row.stored == 0 then status = "Na Rua" else status = row.garage or "Garagem" end
                    local finalName = nil
                    if vData.model and VehicleNames[vData.model] then finalName = VehicleNames[vData.model] end
                    table.insert(veiculos, {plate=row.plate, name=finalName or vData.model or "Desconhecido", status=status, fuel=math.floor(vData.fuelLevel or 100), engine=math.floor((vData.engineHealth or 1000)/10), body=math.floor((vData.bodyHealth or 1000)/10)})
                end
            end
        end
        cb(veiculos)
    end)
end)

-- ==========================================
-- CONTACTOS & CHAMADAS
-- ==========================================
ESX.RegisterServerCallback('pacheco_phone:getContacts', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then MySQL.Async.fetchAll('SELECT id, name, number FROM pacheco_contacts WHERE identifier = @id ORDER BY name ASC', {['@id']=xPlayer.identifier}, function(results) cb(results) end) else cb({}) end
end)

ESX.RegisterServerCallback('pacheco_phone:addContact', function(source, cb, name, number)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then MySQL.Async.execute('INSERT INTO pacheco_contacts (identifier, name, number) VALUES (@id, @name, @number)', {['@id']=xPlayer.identifier, ['@name']=name, ['@number']=number}, function(rowsChanged) cb(rowsChanged > 0) end) else cb(false) end
end)

ESX.RegisterServerCallback('pacheco_phone:deleteContact', function(source, cb, contactId)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then MySQL.Async.execute('DELETE FROM pacheco_contacts WHERE id = @id AND identifier = @identifier', {['@id']=contactId, ['@identifier']=xPlayer.identifier}, function(rowsChanged) cb(rowsChanged > 0) end) else cb(false) end
end)

RegisterServerEvent('pacheco_phone:startCall')
AddEventHandler('pacheco_phone:startCall', function(targetNumber)
    local source = source; local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end
    MySQL.Async.fetchScalar('SELECT phone_number FROM users WHERE identifier = @id', {['@id']=xPlayer.identifier}, function(myNumber)
        if myNumber == targetNumber then TriggerClientEvent('pacheco_phone:callFailed', source, "Número Ocupado"); return end
        MySQL.Async.fetchAll('SELECT identifier FROM users WHERE phone_number = @num', {['@num']=targetNumber}, function(result)
            if result[1] then
                local targetPlayer = ESX.GetPlayerFromIdentifier(result[1].identifier)
                if targetPlayer then
                    if activeCalls[targetPlayer.source] then
                        TriggerClientEvent('pacheco_phone:callFailed', source, "O número está ocupado.")
                    else
                        activeCalls[source] = targetPlayer.source; activeCalls[targetPlayer.source] = source
                        TriggerClientEvent('pacheco_phone:incomingCall', targetPlayer.source, myNumber, source)
                    end
                else TriggerClientEvent('pacheco_phone:callFailed', source, "O telemóvel está desligado.") end
            else TriggerClientEvent('pacheco_phone:callFailed', source, "Número não existe.") end
        end)
    end)
end)

RegisterServerEvent('pacheco_phone:acceptCall')
AddEventHandler('pacheco_phone:acceptCall', function(callerSource)
    local receiverSource = source
    if activeCalls[receiverSource] == callerSource then
        local callChannel = math.random(10000,99999)
        TriggerClientEvent('pacheco_phone:callAccepted', callerSource, callChannel)
        TriggerClientEvent('pacheco_phone:callAccepted', receiverSource, callChannel)
    end
end)

RegisterServerEvent('pacheco_phone:rejectCall')
AddEventHandler('pacheco_phone:rejectCall', function(callerSource)
    local receiverSource = source
    if activeCalls[receiverSource] == callerSource then
        activeCalls[receiverSource] = nil; activeCalls[callerSource] = nil
        TriggerClientEvent('pacheco_phone:callFailed', callerSource, "Chamada Rejeitada.")
    end
end)

RegisterServerEvent('pacheco_phone:endCall')
AddEventHandler('pacheco_phone:endCall', function()
    local source = source; local target = activeCalls[source]
    if target then activeCalls[target] = nil; TriggerClientEvent('pacheco_phone:callEnded', target) end
    activeCalls[source] = nil; TriggerClientEvent('pacheco_phone:callEnded', source)
end)

AddEventHandler('playerDropped', function()
    local source = source; local target = activeCalls[source]
    if target then activeCalls[target] = nil; TriggerClientEvent('pacheco_phone:callEnded', target) end
    activeCalls[source] = nil
end)

-- ==========================================
-- DISPATCH
-- ==========================================
local pendingDispatches = {}; local dispatchCounter = 0

RegisterServerEvent('pacheco_phone:callService')
AddEventHandler('pacheco_phone:callService', function(number, reason, coords)
    local _source = source; local xPlayer = ESX.GetPlayerFromId(_source)
    if not xPlayer then return end
    local jobNeeded = ""; local serviceName = ""
    if number == "112" then jobNeeded = "police"; serviceName = "Polícia"
    elseif number == "111" then jobNeeded = "ambulance"; serviceName = "INEM"
    elseif number == "113" then jobNeeded = "mechanic"; serviceName = "Mecânico" end
    dispatchCounter = dispatchCounter + 1
    local callId = dispatchCounter
    pendingDispatches[callId] = {caller=_source, coords=coords, job=jobNeeded, accepted=false, name=serviceName}
    local xPlayers = ESX.GetPlayers(); local sentToSomeone = false
    for i=1,#xPlayers do
        local targetPlayer = ESX.GetPlayerFromId(xPlayers[i])
        if targetPlayer and targetPlayer.job.name == jobNeeded then
            sentToSomeone = true
            TriggerClientEvent('pacheco_phone:serviceAlert', targetPlayer.source, callId, coords, serviceName, reason)
        end
    end
    if not sentToSomeone then
        TriggerClientEvent('pacheco_phone:callFailed', _source, "Não há unidades ativas.")
        pendingDispatches[callId] = nil; return
    end
    SetTimeout(15000, function()
        if pendingDispatches[callId] and not pendingDispatches[callId].accepted then
            TriggerClientEvent('pacheco_phone:callFailed', pendingDispatches[callId].caller, "Ninguém atendeu o pedido.")
            pendingDispatches[callId] = nil
        end
    end)
end)

RegisterCommand('aceitar', function(source, args, rawCommand)
    local xPlayer = ESX.GetPlayerFromId(source); local callId = tonumber(args[1])
    if not callId or not pendingDispatches[callId] then TriggerClientEvent('esx:showNotification', source, "~r~Pedido inativo."); return end
    local dispatch = pendingDispatches[callId]
    if dispatch.accepted then TriggerClientEvent('esx:showNotification', source, "~r~Já foi aceite."); return end
    if xPlayer.job.name ~= dispatch.job then TriggerClientEvent('esx:showNotification', source, "~r~Sem permissão."); return end
    dispatch.accepted = true
    TriggerClientEvent('pacheco_phone:acceptDispatch', source, dispatch.coords)
    if ESX.GetPlayerFromId(dispatch.caller) then
        TriggerClientEvent('pacheco_phone:callEnded', dispatch.caller)
        TriggerClientEvent('esx:showNotification', dispatch.caller, "~g~Central:~s~ Uma unidade está a caminho!")
    end
    pendingDispatches[callId] = nil
end, false)

-- ==========================================
-- SMS
-- ==========================================
ESX.RegisterServerCallback('pacheco_phone:getMessages', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return cb({}, nil) end
    MySQL.Async.fetchScalar('SELECT phone_number FROM users WHERE identifier = @id', {['@id']=xPlayer.identifier}, function(myNumber)
        if myNumber then
            MySQL.Async.fetchAll('SELECT * FROM pacheco_messages WHERE sender = @num OR receiver = @num ORDER BY timestamp ASC', {['@num']=myNumber}, function(msgs) cb(msgs, myNumber) end)
        else cb({}, nil) end
    end)
end)

RegisterServerEvent('pacheco_phone:sendMessage')
AddEventHandler('pacheco_phone:sendMessage', function(targetNumber, message)
    local _source = source; local xPlayer = ESX.GetPlayerFromId(_source)
    if not xPlayer then return end
    MySQL.Async.fetchScalar('SELECT phone_number FROM users WHERE identifier = @id', {['@id']=xPlayer.identifier}, function(myNumber)
        if not myNumber then return end
        MySQL.Async.execute('INSERT INTO pacheco_messages (sender, receiver, message) VALUES (@sender, @receiver, @msg)', {['@sender']=myNumber, ['@receiver']=targetNumber, ['@msg']=message}, function()
            if myNumber ~= targetNumber then
                MySQL.Async.fetchAll('SELECT identifier FROM users WHERE phone_number = @num', {['@num']=targetNumber}, function(res)
                    if res[1] then
                        local targetPlayer = ESX.GetPlayerFromIdentifier(res[1].identifier)
                        if targetPlayer then TriggerClientEvent('pacheco_phone:receiveSMS', targetPlayer.source, myNumber, message) end
                    end
                end)
            end
            TriggerClientEvent('pacheco_phone:smsSent', _source)
        end)
    end)
end)

-- ==========================================
-- TWITTER
-- ==========================================
ESX.RegisterServerCallback('pacheco_phone:twitterLogin', function(source, cb, username, password)
    MySQL.Async.fetchAll('SELECT id, username, avatar FROM pacheco_twitter_accounts WHERE username = @user AND password = @pass', {['@user']=username, ['@pass']=password}, function(result)
        if result[1] then cb(true, result[1]) else cb(false, "Credenciais inválidas.") end
    end)
end)

ESX.RegisterServerCallback('pacheco_phone:twitterRegister', function(source, cb, username, password)
    local xPlayer = ESX.GetPlayerFromId(source)
    MySQL.Async.fetchAll('SELECT id FROM pacheco_twitter_accounts WHERE username = @user', {['@user']=username}, function(result)
        if result[1] then cb(false, "Username já em uso.")
        else MySQL.Async.execute('INSERT INTO pacheco_twitter_accounts (identifier, username, password) VALUES (@id, @user, @pass)', {['@id']=xPlayer.identifier, ['@user']=username, ['@pass']=password}, function() cb(true, "Conta criada!") end) end
    end)
end)

ESX.RegisterServerCallback('pacheco_phone:getTwitterTopics', function(source, cb)
    MySQL.Async.fetchAll('SELECT topic, MAX(time) as last_update FROM pacheco_tweets GROUP BY topic ORDER BY last_update DESC LIMIT 30', {}, function(topics) cb(topics) end)
end)

ESX.RegisterServerCallback('pacheco_phone:getTweets', function(source, cb, topicName)
    MySQL.Async.fetchAll('SELECT username, avatar, content, time FROM pacheco_tweets WHERE topic = @topic ORDER BY time DESC LIMIT 50', {['@topic']=topicName}, function(tweets) cb(tweets) end)
end)

RegisterServerEvent('pacheco_phone:postTweet')
AddEventHandler('pacheco_phone:postTweet', function(username, avatar, content, topic)
    MySQL.Async.execute('INSERT INTO pacheco_tweets (username, avatar, content, topic) VALUES (@user, @avatar, @content, @topic)', {['@user']=username, ['@avatar']=avatar, ['@content']=content, ['@topic']=topic}, function() TriggerClientEvent('pacheco_phone:newTweet', -1, topic) end)
end)

ESX.RegisterServerCallback('pacheco_phone:changeTwitterAvatar', function(source, cb, username, avatarUrl)
    MySQL.Async.execute('UPDATE pacheco_twitter_accounts SET avatar = @avatar WHERE username = @user', {['@avatar']=avatarUrl, ['@user']=username}, function(rowsChanged) cb(rowsChanged > 0) end)
end)

-- ==========================================
-- BLACKMARKET + DARK WEB LISTAGENS
-- ==========================================
ESX.RegisterServerCallback('pacheco_phone:getBMTopics', function(source, cb)
    MySQL.Async.fetchAll('SELECT topic, MAX(time) as last_update FROM pacheco_blackmarket GROUP BY topic ORDER BY last_update DESC LIMIT 30', {}, function(topics) cb(topics) end)
end)

ESX.RegisterServerCallback('pacheco_phone:getBlackmarket', function(source, cb, topicName)
    MySQL.Async.fetchAll('SELECT message, time FROM pacheco_blackmarket WHERE topic = @topic ORDER BY time ASC LIMIT 100', {['@topic']=topicName}, function(msgs) cb(msgs) end)
end)

RegisterServerEvent('pacheco_phone:postBlackmarket')
AddEventHandler('pacheco_phone:postBlackmarket', function(msg, topic)
    MySQL.Async.execute('INSERT INTO pacheco_blackmarket (message, topic) VALUES (@msg, @topic)', {['@msg']=msg, ['@topic']=topic}, function() TriggerClientEvent('pacheco_phone:newBlackmarketMsg', -1, topic) end)
end)

ESX.RegisterServerCallback('pacheco_phone:getDWListings', function(source, cb, topic)
    MySQL.Async.fetchAll('SELECT id, type, title, message, price, contact, timestamp FROM pacheco_darkweb_listings WHERE topic = @topic ORDER BY timestamp DESC LIMIT 50', {['@topic']=topic}, function(result) cb(result or {}) end)
end)

ESX.RegisterServerCallback('pacheco_phone:postDWListing', function(source, cb, topic, title, message, price, listingType)
    -- Rastreamento aleatório (5% de chance de alertar admins)
    local tracked = math.random(1,100) <= 5
    if tracked then
        local xPlayer = ESX.GetPlayerFromId(source)
        print("[DarkWeb] RASTREADO: Jogador " .. (xPlayer and xPlayer.identifier or "unknown") .. " postou no topic: " .. tostring(topic))
    end
    MySQL.Async.execute('INSERT INTO pacheco_darkweb_listings (topic, type, title, message, price, contact) VALUES (@topic, @type, @title, @msg, @price, @contact)', {
        ['@topic']=topic, ['@type']=listingType or 'message', ['@title']=title or '', ['@msg']=message, ['@price']=tonumber(price) or 0, ['@contact']='Anónimo'
    }, function(rowsChanged) cb(rowsChanged > 0, rowsChanged > 0 and "Publicado." or "Erro.") end)
end)

-- ==========================================
-- ZIPZAP
-- ==========================================
ESX.RegisterServerCallback('pacheco_phone:getZZMessages', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return cb({}, nil) end
    MySQL.Async.fetchScalar('SELECT phone_number FROM users WHERE identifier = @id', {['@id']=xPlayer.identifier}, function(myNumber)
        if myNumber then
            MySQL.Async.fetchAll('SELECT * FROM pacheco_zipzap_messages WHERE sender = @num OR receiver = @num ORDER BY timestamp ASC', {['@num']=myNumber}, function(msgs) cb(msgs, myNumber) end)
        else cb({}, nil) end
    end)
end)

RegisterServerEvent('pacheco_phone:sendZZMessage')
AddEventHandler('pacheco_phone:sendZZMessage', function(targetNumber, message)
    local _source = source; local xPlayer = ESX.GetPlayerFromId(_source)
    if not xPlayer then return end
    MySQL.Async.fetchScalar('SELECT phone_number FROM users WHERE identifier = @id', {['@id']=xPlayer.identifier}, function(myNumber)
        if not myNumber then return end
        MySQL.Async.execute('INSERT INTO pacheco_zipzap_messages (sender, receiver, message) VALUES (@s, @r, @m)', {['@s']=myNumber, ['@r']=targetNumber, ['@m']=message}, function()
            MySQL.Async.fetchAll('SELECT identifier FROM users WHERE phone_number = @num', {['@num']=targetNumber}, function(res)
                if res[1] then
                    local tp = ESX.GetPlayerFromIdentifier(res[1].identifier)
                    if tp then TriggerClientEvent('pacheco_phone:receiveZZ', tp.source, myNumber, message) end
                end
            end)
        end)
    end)
end)

RegisterServerEvent('pacheco_phone:zzShareLocation')
AddEventHandler('pacheco_phone:zzShareLocation', function(targetNumber, x, y, z)
    local _source = source; local xPlayer = ESX.GetPlayerFromId(_source)
    if not xPlayer then return end
    MySQL.Async.fetchScalar('SELECT phone_number FROM users WHERE identifier = @id', {['@id']=xPlayer.identifier}, function(myNumber)
        if not myNumber then return end
        local locationMsg = string.format("[LOCALIZAÇÃO] X:%.1f Y:%.1f Z:%.1f", x, y, z)
        MySQL.Async.execute('INSERT INTO pacheco_zipzap_messages (sender, receiver, message) VALUES (@s, @r, @m)', {['@s']=myNumber, ['@r']=targetNumber, ['@m']=locationMsg}, function()
            MySQL.Async.fetchAll('SELECT identifier FROM users WHERE phone_number = @num', {['@num']=targetNumber}, function(res)
                if res[1] then
                    local tp = ESX.GetPlayerFromIdentifier(res[1].identifier)
                    if tp then TriggerClientEvent('pacheco_phone:receiveZZ', tp.source, myNumber, locationMsg) end
                end
            end)
        end)
    end)
end)

ESX.RegisterServerCallback('pacheco_phone:getZZGroups', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return cb({}) end
    MySQL.Async.fetchScalar('SELECT phone_number FROM users WHERE identifier = @id', {['@id']=xPlayer.identifier}, function(myNumber)
        if not myNumber then return cb({}) end
        -- Grupos onde o jogador é membro + grupos do seu job
        MySQL.Async.fetchAll([[
            SELECT g.id, g.name, g.type, g.job FROM pacheco_zipzap_groups g
            LEFT JOIN pacheco_zipzap_group_members m ON g.id = m.group_id
            WHERE m.phone_number = @num OR (g.type = 'job' AND g.job = @job)
            GROUP BY g.id
        ]], {['@num']=myNumber, ['@job']=xPlayer.job.name}, function(result) cb(result or {}) end)
    end)
end)

ESX.RegisterServerCallback('pacheco_phone:createZZGroup', function(source, cb, name, members)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return cb(false, nil) end
    MySQL.Async.fetchScalar('SELECT phone_number FROM users WHERE identifier = @id', {['@id']=xPlayer.identifier}, function(myNumber)
        if not myNumber then return cb(false, nil) end
        MySQL.Async.execute('INSERT INTO pacheco_zipzap_groups (name, type, created_by) VALUES (@name, @type, @creator)', {
            ['@name']=name, ['@type']='custom', ['@creator']=myNumber
        }, function(rowsChanged, insertId)
            if insertId then
                -- Adicionar criador
                MySQL.Async.execute('INSERT INTO pacheco_zipzap_group_members (group_id, phone_number) VALUES (@gid, @num)', {['@gid']=insertId, ['@num']=myNumber})
                -- Adicionar membros convidados
                if members then
                    for _, memberNum in ipairs(members) do
                        MySQL.Async.execute('INSERT INTO pacheco_zipzap_group_members (group_id, phone_number) VALUES (@gid, @num)', {['@gid']=insertId, ['@num']=memberNum})
                    end
                end
                cb(true, insertId)
            else cb(false, nil) end
        end)
    end)
end)

ESX.RegisterServerCallback('pacheco_phone:getZZGroupMessages', function(source, cb, groupId)
    MySQL.Async.fetchAll('SELECT sender, message, timestamp FROM pacheco_zipzap_group_messages WHERE group_id = @gid ORDER BY timestamp ASC LIMIT 100', {['@gid']=groupId}, function(result) cb(result or {}) end)
end)

RegisterServerEvent('pacheco_phone:sendZZGroupMessage')
AddEventHandler('pacheco_phone:sendZZGroupMessage', function(groupId, message)
    local _source = source; local xPlayer = ESX.GetPlayerFromId(_source)
    if not xPlayer then return end
    MySQL.Async.fetchScalar('SELECT phone_number FROM users WHERE identifier = @id', {['@id']=xPlayer.identifier}, function(myNumber)
        if not myNumber then return end
        MySQL.Async.execute('INSERT INTO pacheco_zipzap_group_messages (group_id, sender, message) VALUES (@gid, @sender, @msg)', {['@gid']=groupId, ['@sender']=myNumber, ['@msg']=message}, function()
            -- Buscar nome do grupo e notificar todos os membros
            MySQL.Async.fetchAll('SELECT g.name, m.phone_number FROM pacheco_zipzap_groups g JOIN pacheco_zipzap_group_members m ON g.id = m.group_id WHERE g.id = @gid', {['@gid']=groupId}, function(members)
                if members then
                    local groupName = members[1] and members[1].name or "Grupo"
                    for _, member in ipairs(members) do
                        if member.phone_number ~= myNumber then
                            MySQL.Async.fetchAll('SELECT identifier FROM users WHERE phone_number = @num', {['@num']=member.phone_number}, function(res)
                                if res[1] then
                                    local tp = ESX.GetPlayerFromIdentifier(res[1].identifier)
                                    if tp then TriggerClientEvent('pacheco_phone:receiveZZGroup', tp.source, groupId, groupName, myNumber, message) end
                                end
                            end)
                        end
                    end
                end
            end)
        end)
    end)
end)

-- ==========================================
-- FOTOGRAM
-- ==========================================
ESX.RegisterServerCallback('pacheco_phone:fotogramLogin', function(source, cb, username, password)
    local xPlayer = ESX.GetPlayerFromId(source)
    MySQL.Async.fetchAll('SELECT id, username, avatar, bio, followers FROM pacheco_fotogram_accounts WHERE username = @user AND identifier = @id', {['@user']=username, ['@id']=xPlayer.identifier}, function(result)
        if result[1] then cb(true, result[1]) else cb(false, "Credenciais inválidas.") end
    end)
end)

ESX.RegisterServerCallback('pacheco_phone:fotogramRegister', function(source, cb, username, password)
    local xPlayer = ESX.GetPlayerFromId(source)
    MySQL.Async.fetchAll('SELECT id FROM pacheco_fotogram_accounts WHERE username = @user', {['@user']=username}, function(result)
        if result[1] then cb(false, "Username já em uso.")
        else
            MySQL.Async.execute('INSERT INTO pacheco_fotogram_accounts (identifier, username, avatar) VALUES (@id, @user, @avatar)', {
                ['@id']=xPlayer.identifier, ['@user']=username, ['@avatar']='https://www.w3schools.com/howto/img_avatar.png'
            }, function() cb(true, "Conta criada!") end)
        end
    end)
end)

ESX.RegisterServerCallback('pacheco_phone:getFotogramFeed', function(source, cb)
    MySQL.Async.fetchAll('SELECT p.id, p.username, p.avatar, p.image_url, p.caption, p.likes, p.timestamp FROM pacheco_fotogram_posts p ORDER BY p.timestamp DESC LIMIT 30', {}, function(result) cb(result or {}) end)
end)

ESX.RegisterServerCallback('pacheco_phone:postFotogram', function(source, cb, username, avatar, imageUrl, caption)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return cb(false, "Erro interno.") end
    if not imageUrl or imageUrl == "" then return cb(false, "Imagem inválida.") end
    MySQL.Async.execute('INSERT INTO pacheco_fotogram_posts (identifier, username, avatar, image_url, caption) VALUES (@id, @user, @avatar, @img, @caption)', {
        ['@id']=xPlayer.identifier, ['@user']=username, ['@avatar']=avatar, ['@img']=imageUrl, ['@caption']=caption
    }, function(rowsChanged)
        if rowsChanged > 0 then TriggerClientEvent('pacheco_phone:newFotogramPost', -1); cb(true, "Publicado!") else cb(false, "Erro ao publicar.") end
    end)
end)

RegisterServerEvent('pacheco_phone:likeFotogram')
AddEventHandler('pacheco_phone:likeFotogram', function(postId)
    MySQL.Async.execute('UPDATE pacheco_fotogram_posts SET likes = likes + 1 WHERE id = @id', {['@id']=postId})
end)

ESX.RegisterServerCallback('pacheco_phone:getFotogramComments', function(source, cb, postId)
    MySQL.Async.fetchAll('SELECT username, comment, timestamp FROM pacheco_fotogram_comments WHERE post_id = @id ORDER BY timestamp ASC LIMIT 50', {['@id']=postId}, function(result) cb(result or {}) end)
end)

RegisterServerEvent('pacheco_phone:postFotogramComment')
AddEventHandler('pacheco_phone:postFotogramComment', function(postId, username, comment)
    MySQL.Async.execute('INSERT INTO pacheco_fotogram_comments (post_id, username, comment) VALUES (@id, @user, @comment)', {['@id']=postId, ['@user']=username, ['@comment']=comment})
end)

ESX.RegisterServerCallback('pacheco_phone:getMyFotogramProfile', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return cb(nil) end
    MySQL.Async.fetchAll('SELECT username, avatar, bio, followers FROM pacheco_fotogram_accounts WHERE identifier = @id', {['@id']=xPlayer.identifier}, function(result) cb(result[1] or nil) end)
end)

-- ==========================================
-- PÁGINAS AMARELAS
-- ==========================================
ESX.RegisterServerCallback('pacheco_phone:getPaginasAmarelas', function(source, cb, category)
    local query = 'SELECT id, job, business_name, description, phone, category, location FROM pacheco_paginas_amarelas'
    local params = {}
    if category and category ~= "" and category ~= "all" then
        query = query .. ' WHERE category = @cat'
        params['@cat'] = category
    end
    query = query .. ' ORDER BY business_name ASC'
    MySQL.Async.fetchAll(query, params, function(result) cb(result or {}) end)
end)

ESX.RegisterServerCallback('pacheco_phone:registarEmpresa', function(source, cb, businessName, description, phone, category, location)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return cb(false, "Erro interno.") end
    if xPlayer.job.name == "unemployed" then return cb(false, "Precisas de estar empregado para registar uma empresa.") end
    -- Verificar se já tem registo
    MySQL.Async.fetchAll('SELECT id FROM pacheco_paginas_amarelas WHERE identifier = @id', {['@id']=xPlayer.identifier}, function(existing)
        if existing[1] then
            -- Atualizar existente
            MySQL.Async.execute('UPDATE pacheco_paginas_amarelas SET business_name=@name, description=@desc, phone=@phone, category=@cat, location=@loc WHERE identifier=@id', {
                ['@name']=businessName, ['@desc']=description, ['@phone']=phone, ['@cat']=category, ['@loc']=location, ['@id']=xPlayer.identifier
            }, function() cb(true, "Empresa atualizada!") end)
        else
            MySQL.Async.execute('INSERT INTO pacheco_paginas_amarelas (identifier, job, business_name, description, phone, category, location) VALUES (@id, @job, @name, @desc, @phone, @cat, @loc)', {
                ['@id']=xPlayer.identifier, ['@job']=xPlayer.job.name, ['@name']=businessName, ['@desc']=description, ['@phone']=phone, ['@cat']=category, ['@loc']=location
            }, function(rowsChanged) cb(rowsChanged > 0, rowsChanged > 0 and "Empresa registada!" or "Erro.") end)
        end
    end)
end)

ESX.RegisterServerCallback('pacheco_phone:getMinhaEmpresa', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return cb(nil) end
    MySQL.Async.fetchAll('SELECT * FROM pacheco_paginas_amarelas WHERE identifier = @id', {['@id']=xPlayer.identifier}, function(result) cb(result[1] or nil) end)
end)

ESX.RegisterServerCallback('pacheco_phone:atualizarEmpresa', function(source, cb, businessName, description, phone, category, location)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return cb(false, "Erro.") end
    MySQL.Async.execute('UPDATE pacheco_paginas_amarelas SET business_name=@name, description=@desc, phone=@phone, category=@cat, location=@loc WHERE identifier=@id', {
        ['@name']=businessName, ['@desc']=description, ['@phone']=phone, ['@cat']=category, ['@loc']=location, ['@id']=xPlayer.identifier
    }, function(rowsChanged) cb(rowsChanged > 0, rowsChanged > 0 and "Atualizado!" or "Sem registo para atualizar.") end)
end)

ESX.RegisterServerCallback('pacheco_phone:getNearbyPlayerNames', function(source, cb, serverIds)
    local players = {}
    for i=1,#serverIds do
        local target = ESX.GetPlayerFromId(serverIds[i])
        if target then table.insert(players, {id=target.source, name=target.getName()}) end
    end
    cb(players)
end)

-- ==========================================
-- E-FATURAS
-- ==========================================
ESX.RegisterServerCallback('pacheco_phone:getInvoices', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return cb({}) end
    MySQL.Async.fetchAll('SELECT id, sender, target_type, label, amount FROM billing WHERE identifier = @identifier', {['@identifier']=xPlayer.identifier}, function(result) cb(result) end)
end)

ESX.RegisterServerCallback('pacheco_phone:getPredefinedInvoices', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return cb({}) end
    MySQL.Async.fetchAll('SELECT id, label, amount FROM pacheco_predefined_invoices WHERE job = @job', {['@job']=xPlayer.job.name}, function(result) cb(result) end)
end)

ESX.RegisterServerCallback('pacheco_phone:sendInvoice', function(source, cb, targetId, label, amount, type)
    local xPlayer = ESX.GetPlayerFromId(source); local targetPlayer = ESX.GetPlayerFromId(targetId)
    if not xPlayer or not targetPlayer then return cb(false, "Cidadão não encontrado.") end
    local targetType = (type == "society") and "society" or "player"
    local senderIdentifier = (type == "society") and ("society_"..xPlayer.job.name) or xPlayer.identifier
    MySQL.Async.execute('INSERT INTO billing (identifier, sender, target_type, target, label, amount) VALUES (@identifier, @sender, @target_type, @target, @label, @amount)', {
        ['@identifier']=targetPlayer.identifier, ['@sender']=xPlayer.identifier, ['@target_type']=targetType, ['@target']=senderIdentifier, ['@label']=label, ['@amount']=amount
    }, function(rowsChanged)
        if rowsChanged > 0 then TriggerClientEvent('esx:showNotification', targetPlayer.source, "~b~Nova Fatura:~s~ "..label.." - "..amount.."€"); cb(true, "Fatura emitida!") else cb(false, "Erro.") end
    end)
end)

ESX.RegisterServerCallback('pacheco_phone:payInvoice', function(source, cb, invoiceId)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return cb(false, "Erro interno") end
    MySQL.Async.fetchAll('SELECT sender, target_type, target, label, amount FROM billing WHERE id = @id', {['@id']=invoiceId}, function(result)
        if result[1] then
            local invoice = result[1]
            if xPlayer.getAccount('bank').money >= invoice.amount then
                xPlayer.removeAccountMoney('bank', invoice.amount)
                if invoice.target_type == 'society' then
                    TriggerEvent('esx_addonaccount:getSharedAccount', invoice.target, function(account) if account then account.addMoney(invoice.amount) end end)
                else
                    local tp = ESX.GetPlayerFromIdentifier(invoice.target)
                    if tp then tp.addAccountMoney('bank', invoice.amount) end
                end
                MySQL.Async.execute('DELETE FROM billing WHERE id = @id', {['@id']=invoiceId})
                local payerName = xPlayer.getName()
                local employee = ESX.GetPlayerFromIdentifier(invoice.sender)
                if employee then
                    TriggerClientEvent('ox_lib:notify', employee.source, {type='success', title='💰 Fatura Liquidada', description="**"..payerName.."** pagou: **"..invoice.label.."** ("..invoice.amount.."€)", duration=8000})
                end
                cb(true, "Fatura paga com sucesso!")
            else cb(false, "Saldo insuficiente.") end
        else cb(false, "Fatura não encontrada.") end
    end)
end)