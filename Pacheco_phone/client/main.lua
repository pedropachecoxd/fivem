-- ==========================================
-- PACHECO PHONE - CLIENT.LUA
-- ==========================================
-- DEBUG: true = logs no console F8, false = silencioso
local DEBUG = true

local function dlog(msg)
    if DEBUG then
        print("^3[PachecoPhone-Client] ^7" .. tostring(msg))
    end
end

-- ==========================================
-- VARIÁVEIS GLOBAIS
-- ==========================================
local ESX = exports['es_extended']:getSharedObject()
local telemovelAberto = false
local propTelemovel   = nil
local isTakingPhoto   = false
local fotoCam         = nil  -- câmara persistente entre callbacks

-- ==========================================
-- UTILITÁRIOS
-- ==========================================
local function LoadAnimDict(dict)
    RequestAnimDict(dict)
    local t = 0
    while not HasAnimDictLoaded(dict) do
        Citizen.Wait(10)
        t = t + 10
        if t > 5000 then dlog("TIMEOUT a carregar animDict: " .. dict); break end
    end
    dlog("AnimDict carregado: " .. dict)
end

local function LoadModel(model)
    RequestModel(model)
    local t = 0
    while not HasModelLoaded(model) do
        Citizen.Wait(10)
        t = t + 10
        if t > 5000 then dlog("TIMEOUT a carregar model: " .. tostring(model)); break end
    end
    dlog("Model carregado: " .. tostring(model))
end

-- ==========================================
-- ABRIR / FECHAR TELEMÓVEL
-- ==========================================
function AbrirTelemovel()
    if telemovelAberto then
        dlog("Telemóvel já aberto, ignorando.")
        return
    end
    dlog("A abrir telemóvel...")
    telemovelAberto = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = "abrir" })

    local ped = PlayerPedId()
    LoadAnimDict("cellphone@")
    TaskPlayAnim(ped, "cellphone@", "cellphone_text_in", 4.0, -1, -1, 50, 0, false, false, false)

    local propHash = GetHashKey("prop_npc_phone_02")
    LoadModel(propHash)
    propTelemovel = CreateObject(propHash, 1.0, 1.0, 1.0, 1, 1, 0)
    AttachEntityToEntity(propTelemovel, ped, GetPedBoneIndex(ped, 28422),
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1, 1, 0, 0, 2, 1)
    dlog("Telemóvel aberto com sucesso.")
end

function FecharTelemovel()
    dlog("A fechar telemóvel...")
    telemovelAberto = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "fechar" })

    local ped = PlayerPedId()
    ClearPedTasks(ped)

    if propTelemovel and DoesEntityExist(propTelemovel) then
        DeleteEntity(propTelemovel)
        propTelemovel = nil
        dlog("Prop do telemóvel apagado.")
    end

    -- Se estava a tirar foto, limpar câmara também
    if fotoCam then
        dlog("A limpar câmara residual ao fechar telemóvel.")
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(fotoCam, false)
        fotoCam = nil
        isTakingPhoto = false
    end
end

-- ==========================================
-- SISTEMA DE CÂMARA - FOTOGRAM
-- ==========================================

-- PASSO 1: Jogador clica "Câmara" no NUI
RegisterNUICallback('tirarFoto', function(data, cb)
    dlog("=== tirarFoto chamado ===")

    if isTakingPhoto then
        dlog("Já está a tirar foto, ignorando.")
        cb('already')
        return
    end

    -- Fechar NUI para ver o jogo
    SetNuiFocus(false, false)
    dlog("NUI fechado - jogo visível")

    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    dlog(string.format("Posição do ped: X=%.1f Y=%.1f Z=%.1f H=%.1f", coords.x, coords.y, coords.z, heading))

    -- Criar câmara na perspetiva do jogador
    fotoCam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    if not fotoCam then
        dlog("ERRO: falhou a criar câmara!")
        SetNuiFocus(true, true)
        cb('error')
        return
    end

    SetCamCoord(fotoCam, coords.x, coords.y, coords.z + 0.5)
    SetCamRot(fotoCam, 0.0, 0.0, heading, 2)
    SetCamFov(fotoCam, 60.0)
    RenderScriptCams(true, false, 0, true, true)
    dlog("Câmara criada e ativa: " .. tostring(fotoCam))

    isTakingPhoto = true

    -- Animação selfie
    LoadAnimDict("cellphone@selfie")
    TaskPlayAnim(ped, "cellphone@selfie", "idle_a", 8.0, -8.0, -1, 50, 0, false, false, false)
    dlog("Animação selfie iniciada")

    -- Pequeno delay para o jogo renderizar, depois abrir NUI com overlay
    Citizen.SetTimeout(300, function()
        SetNuiFocus(true, true)
        SendNUIMessage({ action = "mostrarCamara" })
        dlog("NUI reaberto com overlay de câmara")
    end)

    cb('ok')
end)

-- PASSO 2: Jogador clica no botão de captura no overlay
RegisterNUICallback('capturarFoto', function(data, cb)
    dlog("=== capturarFoto chamado ===")

    if not isTakingPhoto then
        dlog("AVISO: capturarFoto chamado mas isTakingPhoto=false")
    end

    -- Efeito flash
    DoScreenFadeOut(100)
    Citizen.Wait(150)
    DoScreenFadeIn(400)
    dlog("Flash efetuado")

    local photoUrl = nil

    -- Tentar screenshot-basic
    if DEBUG then dlog("A tentar screenshot-basic...") end

    local screenshotOk = pcall(function()
        exports['screenshot-basic']:requestScreenshotUpload(
            'https://api.imgur.com/3/image',
            'imgur',
            { headers = { Authorization = 'Client-ID SEU_CLIENT_ID_IMGUR' } },
            function(rawData)
                dlog("screenshot-basic raw response: " .. tostring(rawData))
                if rawData then
                    local ok, decoded = pcall(json.decode, rawData)
                    if ok and decoded and decoded.data and decoded.data.link then
                        photoUrl = decoded.data.link
                        dlog("Screenshot URL obtida: " .. photoUrl)
                    else
                        dlog("ERRO ao parsear resposta imgur: " .. tostring(rawData))
                    end
                end
            end
        )
    end)

    if not screenshotOk then
        dlog("AVISO: screenshot-basic não disponível ou erro ao chamar")
    end

    -- Aguardar URL (máx 6 segundos)
    local waited = 0
    while not photoUrl and waited < 60 do
        Citizen.Wait(100)
        waited = waited + 1
    end

    if photoUrl then
        dlog("Screenshot capturado com sucesso após " .. (waited * 100) .. "ms")
    else
        dlog("AVISO: screenshot falhou/timeout - a usar URL de debug")
        if DEBUG then
            -- Em modo debug usa uma imagem de teste
            photoUrl = "https://fivem.net/logo.png"
        else
            photoUrl = ""
        end
    end

    -- Limpar câmara
    if fotoCam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(fotoCam, false)
        fotoCam = nil
        dlog("Câmara destruída após captura")
    else
        dlog("AVISO: fotoCam era nil ao capturar - câmara não foi limpa")
    end

    ClearPedTasks(PlayerPedId())
    isTakingPhoto = false

    SendNUIMessage({ action = "esconderCamara" })
    dlog("Overlay câmara escondido, URL enviada para NUI: " .. tostring(photoUrl))

    cb({ url = photoUrl })
end)

-- PASSO 3: Jogador cancela a câmara
RegisterNUICallback('cancelarFoto', function(data, cb)
    dlog("=== cancelarFoto chamado ===")

    if fotoCam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(fotoCam, false)
        fotoCam = nil
        dlog("Câmara destruída ao cancelar")
    else
        dlog("AVISO: cancelarFoto mas fotoCam já era nil")
    end

    ClearPedTasks(PlayerPedId())
    isTakingPhoto = false
    SendNUIMessage({ action = "esconderCamara" })

    cb('ok')
end)

-- ==========================================
-- EVENTOS E COMANDOS
-- ==========================================
RegisterNetEvent('pacheco_phone:abrirTelefone')
AddEventHandler('pacheco_phone:abrirTelefone', function()
    dlog("Evento abrirTelefone recebido")
    AbrirTelemovel()
end)

RegisterCommand('telefone', function()
    dlog("Comando /telefone executado")
    if not telemovelAberto then
        ESX.TriggerServerCallback('pacheco_phone:verificarItem', function(temPhone)
            dlog("verificarItem resultado: " .. tostring(temPhone))
            if temPhone then
                AbrirTelemovel()
            else
                ESX.ShowNotification("~r~Não tens nenhum telemóvel no inventário!")
            end
        end)
    else
        dlog("Telefone já aberto, a fechar...")
        FecharTelemovel()
    end
end)
RegisterKeyMapping('telefone', 'Abrir Telemóvel', 'keyboard', 'F1')

-- Atualizar relógio
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(2000)
        if telemovelAberto then
            local hour   = GetClockHours()
            local minute = GetClockMinutes()
            local timeString = string.format("%02d:%02d", hour, minute)
            SendNUIMessage({ action = "updateTime", time = timeString })
        end
    end
end)

-- ==========================================
-- CALLBACKS NUI GERAIS
-- ==========================================
RegisterNUICallback('fechar', function(data, cb)
    dlog("NUI callback: fechar")
    FecharTelemovel()
    cb('ok')
end)

RegisterNUICallback('getUserData', function(data, cb)
    dlog("NUI callback: getUserData")
    ESX.TriggerServerCallback('pacheco_phone:getUserInfo', function(info)
        dlog("getUserInfo resposta: " .. json.encode(info or {}))
        cb(info)
    end)
end)

RegisterNUICallback('getPhoneVersion', function(data, cb)
    cb({ version = "3.0.0 (Platinum)" })
end)

-- ==========================================
-- E-FATURAS
-- ==========================================
RegisterNUICallback('getNearbyPlayers', function(data, cb)
    dlog("getNearbyPlayers chamado")
    local playerPed = PlayerPedId()
    local players   = ESX.Game.GetPlayersInArea(GetEntityCoords(playerPed), 5.0)
    local serverIds = {}
    for i = 1, #players do
        if players[i] ~= PlayerId() then
            table.insert(serverIds, GetPlayerServerId(players[i]))
        end
    end
    dlog("Jogadores próximos encontrados: " .. #serverIds)
    if #serverIds > 0 then
        ESX.TriggerServerCallback('pacheco_phone:getNearbyPlayerNames', function(names)
            cb(names)
        end, serverIds)
    else
        cb({})
    end
end)

RegisterNUICallback('getInvoices', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:getInvoices', function(faturas)
        dlog("getInvoices: " .. #(faturas or {}) .. " faturas")
        cb(faturas)
    end)
end)

RegisterNUICallback('getPredefinedInvoices', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:getPredefinedInvoices', function(faturas) cb(faturas) end)
end)

RegisterNUICallback('sendInvoice', function(data, cb)
    dlog("sendInvoice: target=" .. tostring(data.targetId) .. " amount=" .. tostring(data.amount))
    ESX.TriggerServerCallback('pacheco_phone:sendInvoice', function(success, msg)
        cb({ success = success, message = msg })
    end, data.targetId, data.label, data.amount, data.type)
end)

RegisterNUICallback('payInvoice', function(data, cb)
    dlog("payInvoice: id=" .. tostring(data.invoiceId))
    ESX.TriggerServerCallback('pacheco_phone:payInvoice', function(success, msg)
        cb({ success = success, message = msg })
    end, data.invoiceId)
end)

-- ==========================================
-- BANCO & GARAGEM
-- ==========================================
RegisterNUICallback('getBankInfo', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:getBankInfo', function(info) cb(info) end)
end)

RegisterNUICallback('fazerTransferencia', function(data, cb)
    dlog("fazerTransferencia: iban=" .. tostring(data.iban) .. " amount=" .. tostring(data.amount))
    ESX.TriggerServerCallback('pacheco_phone:transferirDinheiro', function(success, msg)
        cb({ success = success, message = msg })
    end, data.iban, data.amount)
end)

RegisterNUICallback('getTransacoes', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:getTransacoes', function(trans) cb(trans) end)
end)

RegisterNUICallback('getCreditos', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:getCreditos', function(creditos) cb(creditos) end)
end)

RegisterNUICallback('getGaragemData', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:getGaragem', function(veiculos)
        dlog("getGaragem: " .. #(veiculos or {}) .. " veículos")
        cb(veiculos)
    end)
end)

-- ==========================================
-- CONTACTOS, CHAMADAS & DISPATCH
-- ==========================================
RegisterNUICallback('getContacts', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:getContacts', function(contacts)
        dlog("getContacts: " .. #(contacts or {}) .. " contactos")
        cb(contacts)
    end)
end)

RegisterNUICallback('addContact', function(data, cb)
    dlog("addContact: nome=" .. tostring(data.name) .. " num=" .. tostring(data.number))
    ESX.TriggerServerCallback('pacheco_phone:addContact', function(success)
        cb({ success = success })
    end, data.name, data.number)
end)

RegisterNUICallback('deleteContact', function(data, cb)
    dlog("deleteContact: id=" .. tostring(data.id))
    ESX.TriggerServerCallback('pacheco_phone:deleteContact', function(success)
        cb({ success = success })
    end, data.id)
end)

RegisterNUICallback('startCall', function(data, cb)
    dlog("startCall: number=" .. tostring(data.number))
    TriggerServerEvent('pacheco_phone:startCall', data.number)
    cb('ok')
end)

RegisterNUICallback('acceptCall', function(data, cb)
    dlog("acceptCall: targetSource=" .. tostring(data.targetSource))
    TriggerServerEvent('pacheco_phone:acceptCall', data.targetSource)
    cb('ok')
end)

RegisterNUICallback('rejectCall', function(data, cb)
    dlog("rejectCall: targetSource=" .. tostring(data.targetSource))
    TriggerServerEvent('pacheco_phone:rejectCall', data.targetSource)
    cb('ok')
end)

RegisterNUICallback('endCall', function(data, cb)
    dlog("endCall")
    TriggerServerEvent('pacheco_phone:endCall')
    cb('ok')
end)

RegisterNUICallback('startDispatch', function(data, cb)
    dlog("startDispatch: number=" .. tostring(data.number) .. " reason=" .. tostring(data.reason))
    local playerCoords = GetEntityCoords(PlayerPedId())
    TriggerServerEvent('pacheco_phone:callService', data.number, data.reason, playerCoords)
    cb('ok')
end)

RegisterNetEvent('pacheco_phone:incomingCall')
AddEventHandler('pacheco_phone:incomingCall', function(number, source)
    dlog("incomingCall: de=" .. tostring(number) .. " source=" .. tostring(source))
    SendNUIMessage({ action = "incomingCall", number = number, source = source })
end)

RegisterNetEvent('pacheco_phone:callAccepted')
AddEventHandler('pacheco_phone:callAccepted', function(channel)
    dlog("callAccepted: canal=" .. tostring(channel))
    SendNUIMessage({ action = "callAccepted" })
    exports["pma-voice"]:setCallChannel(channel)
end)

RegisterNetEvent('pacheco_phone:callFailed')
AddEventHandler('pacheco_phone:callFailed', function(reason)
    dlog("callFailed: " .. tostring(reason))
    SendNUIMessage({ action = "callFailed", reason = reason })
end)

RegisterNetEvent('pacheco_phone:callEnded')
AddEventHandler('pacheco_phone:callEnded', function()
    dlog("callEnded")
    SendNUIMessage({ action = "callEnded" })
    exports["pma-voice"]:setCallChannel(0)
end)

-- ==========================================
-- SMS
-- ==========================================
RegisterNUICallback('getMessages', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:getMessages', function(msgs, myNumber)
        dlog("getMessages: " .. #(msgs or {}) .. " msgs, myNumber=" .. tostring(myNumber))
        cb({ messages = msgs, myNumber = myNumber })
    end)
end)

RegisterNUICallback('sendMessage', function(data, cb)
    dlog("sendMessage: para=" .. tostring(data.number))
    TriggerServerEvent('pacheco_phone:sendMessage', data.number, data.message)
    cb('ok')
end)

RegisterNetEvent('pacheco_phone:receiveSMS')
AddEventHandler('pacheco_phone:receiveSMS', function(sender, message)
    dlog("receiveSMS: de=" .. tostring(sender))
    SendNUIMessage({ action = "receiveSMS", sender = sender, message = message })
    if not telemovelAberto then
        ESX.ShowNotification("~b~Nova Mensagem de ~s~" .. sender)
    end
end)

RegisterNetEvent('pacheco_phone:smsSent')
AddEventHandler('pacheco_phone:smsSent', function()
    dlog("smsSent")
    SendNUIMessage({ action = "smsSent" })
end)

-- ==========================================
-- TWITTER
-- ==========================================
RegisterNUICallback('twitterLogin', function(data, cb)
    dlog("twitterLogin: user=" .. tostring(data.username))
    ESX.TriggerServerCallback('pacheco_phone:twitterLogin', function(success, resultData)
        cb({ success = success, data = resultData })
    end, data.username, data.password)
end)

RegisterNUICallback('twitterRegister', function(data, cb)
    dlog("twitterRegister: user=" .. tostring(data.username))
    ESX.TriggerServerCallback('pacheco_phone:twitterRegister', function(success, msg)
        cb({ success = success, message = msg })
    end, data.username, data.password)
end)

RegisterNUICallback('getTwitterTopics', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:getTwitterTopics', function(topics) cb(topics) end)
end)

RegisterNUICallback('getTweets', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:getTweets', function(tweets) cb(tweets) end, data.topic)
end)

RegisterNUICallback('postTweet', function(data, cb)
    dlog("postTweet: topic=" .. tostring(data.topic))
    TriggerServerEvent('pacheco_phone:postTweet', data.username, data.avatar, data.content, data.topic)
    cb('ok')
end)

RegisterNUICallback('changeTwitterAvatar', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:changeTwitterAvatar', function(success)
        cb({ success = success })
    end, data.username, data.avatar)
end)

RegisterNetEvent('pacheco_phone:newTweet')
AddEventHandler('pacheco_phone:newTweet', function(topic)
    SendNUIMessage({ action = "newTweet", topic = topic })
end)

-- ==========================================
-- BLACKMARKET / DARK WEB
-- ==========================================
RegisterNUICallback('getBMTopics', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:getBMTopics', function(topics) cb(topics) end)
end)

RegisterNUICallback('getBlackmarket', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:getBlackmarket', function(msgs) cb(msgs) end, data.topic)
end)

RegisterNUICallback('postBlackmarket', function(data, cb)
    dlog("postBlackmarket: topic=" .. tostring(data.topic))
    TriggerServerEvent('pacheco_phone:postBlackmarket', data.message, data.topic)
    cb('ok')
end)

RegisterNUICallback('getDWListings', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:getDWListings', function(listings) cb(listings) end, data.topic)
end)

RegisterNUICallback('postDWListing', function(data, cb)
    dlog("postDWListing: topic=" .. tostring(data.topic) .. " type=" .. tostring(data.type))
    ESX.TriggerServerCallback('pacheco_phone:postDWListing', function(success, msg)
        cb({ success = success, message = msg })
    end, data.topic, data.title, data.message, data.price, data.type)
end)

RegisterNetEvent('pacheco_phone:newBlackmarketMsg')
AddEventHandler('pacheco_phone:newBlackmarketMsg', function(topic)
    SendNUIMessage({ action = "newBlackmarketMsg", topic = topic })
end)

-- ==========================================
-- ZIPZAP
-- ==========================================
RegisterNUICallback('getZZMessages', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:getZZMessages', function(msgs, myNumber)
        dlog("getZZMessages: " .. #(msgs or {}) .. " msgs")
        cb({ messages = msgs, myNumber = myNumber })
    end)
end)

RegisterNUICallback('sendZZMessage', function(data, cb)
    dlog("sendZZMessage: para=" .. tostring(data.number))
    TriggerServerEvent('pacheco_phone:sendZZMessage', data.number, data.message)
    cb('ok')
end)

RegisterNUICallback('getZZGroups', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:getZZGroups', function(groups)
        dlog("getZZGroups: " .. #(groups or {}) .. " grupos")
        cb(groups)
    end)
end)

RegisterNUICallback('createZZGroup', function(data, cb)
    dlog("createZZGroup: nome=" .. tostring(data.name))
    ESX.TriggerServerCallback('pacheco_phone:createZZGroup', function(success, groupId)
        cb({ success = success, groupId = groupId })
    end, data.name, data.members)
end)

RegisterNUICallback('getZZGroupMessages', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:getZZGroupMessages', function(msgs)
        cb(msgs)
    end, data.groupId)
end)

RegisterNUICallback('sendZZGroupMessage', function(data, cb)
    dlog("sendZZGroupMessage: groupId=" .. tostring(data.groupId))
    TriggerServerEvent('pacheco_phone:sendZZGroupMessage', data.groupId, data.message)
    cb('ok')
end)

RegisterNUICallback('getNearbyPlayersZZ', function(data, cb)
    local playerPed = PlayerPedId()
    local players   = ESX.Game.GetPlayersInArea(GetEntityCoords(playerPed), 30.0)
    local serverIds = {}
    for i = 1, #players do
        if players[i] ~= PlayerId() then
            table.insert(serverIds, GetPlayerServerId(players[i]))
        end
    end
    dlog("getNearbyPlayersZZ: " .. #serverIds .. " jogadores")
    if #serverIds > 0 then
        ESX.TriggerServerCallback('pacheco_phone:getNearbyPlayerNames', function(names)
            cb(names)
        end, serverIds)
    else
        cb({})
    end
end)

RegisterNUICallback('shareLocationZZ', function(data, cb)
    local coords  = GetEntityCoords(PlayerPedId())
    dlog("shareLocationZZ: para=" .. tostring(data.number))
    TriggerServerEvent('pacheco_phone:zzShareLocation', data.number, coords.x, coords.y, coords.z)
    cb('ok')
end)

RegisterNetEvent('pacheco_phone:receiveZZ')
AddEventHandler('pacheco_phone:receiveZZ', function(sender, message)
    dlog("receiveZZ: de=" .. tostring(sender))
    SendNUIMessage({ action = "receiveZZ", sender = sender, message = message })
    if not telemovelAberto then
        ESX.ShowNotification("~g~[ZipZap] ~s~Nova mensagem de " .. sender)
    end
end)

RegisterNetEvent('pacheco_phone:receiveZZGroup')
AddEventHandler('pacheco_phone:receiveZZGroup', function(groupId, groupName, sender, message)
    dlog("receiveZZGroup: grupo=" .. tostring(groupName) .. " de=" .. tostring(sender))
    SendNUIMessage({ action = "receiveZZGroup", groupId = groupId, groupName = groupName, sender = sender, message = message })
    if not telemovelAberto then
        ESX.ShowNotification("~g~[ZipZap] ~s~" .. groupName .. ": " .. sender)
    end
end)

-- ==========================================
-- FOTOGRAM
-- ==========================================
RegisterNUICallback('fotogramLogin', function(data, cb)
    dlog("fotogramLogin: user=" .. tostring(data.username))
    ESX.TriggerServerCallback('pacheco_phone:fotogramLogin', function(success, resultData)
        dlog("fotogramLogin resultado: " .. tostring(success))
        cb({ success = success, data = resultData })
    end, data.username, data.password)
end)

RegisterNUICallback('fotogramRegister', function(data, cb)
    dlog("fotogramRegister: user=" .. tostring(data.username))
    ESX.TriggerServerCallback('pacheco_phone:fotogramRegister', function(success, msg)
        cb({ success = success, message = msg })
    end, data.username, data.password)
end)

RegisterNUICallback('getFotogramFeed', function(data, cb)
    dlog("getFotogramFeed chamado")
    ESX.TriggerServerCallback('pacheco_phone:getFotogramFeed', function(posts)
        dlog("getFotogramFeed: " .. #(posts or {}) .. " posts")
        cb(posts)
    end)
end)

RegisterNUICallback('postFotogram', function(data, cb)
    dlog("postFotogram: user=" .. tostring(data.username) .. " url=" .. tostring(data.imageUrl))
    ESX.TriggerServerCallback('pacheco_phone:postFotogram', function(success, msg)
        dlog("postFotogram resultado: " .. tostring(success) .. " - " .. tostring(msg))
        cb({ success = success, message = msg })
    end, data.username, data.avatar, data.imageUrl, data.caption)
end)

RegisterNUICallback('likeFotogram', function(data, cb)
    dlog("likeFotogram: postId=" .. tostring(data.postId))
    TriggerServerEvent('pacheco_phone:likeFotogram', data.postId)
    cb('ok')
end)

RegisterNUICallback('getFotogramComments', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:getFotogramComments', function(comments)
        cb(comments)
    end, data.postId)
end)

RegisterNUICallback('postFotogramComment', function(data, cb)
    dlog("postFotogramComment: postId=" .. tostring(data.postId))
    TriggerServerEvent('pacheco_phone:postFotogramComment', data.postId, data.username, data.comment)
    cb('ok')
end)

RegisterNUICallback('getMyFotogramProfile', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:getMyFotogramProfile', function(profile) cb(profile) end)
end)

RegisterNetEvent('pacheco_phone:newFotogramPost')
AddEventHandler('pacheco_phone:newFotogramPost', function()
    SendNUIMessage({ action = "newFotogramPost" })
end)

-- ==========================================
-- PÁGINAS AMARELAS
-- ==========================================
RegisterNUICallback('getPaginasAmarelas', function(data, cb)
    dlog("getPaginasAmarelas: category=" .. tostring(data.category))
    ESX.TriggerServerCallback('pacheco_phone:getPaginasAmarelas', function(empresas)
        dlog("getPaginasAmarelas: " .. #(empresas or {}) .. " empresas")
        cb(empresas)
    end, data.category)
end)

RegisterNUICallback('registarEmpresa', function(data, cb)
    dlog("registarEmpresa: nome=" .. tostring(data.businessName))
    ESX.TriggerServerCallback('pacheco_phone:registarEmpresa', function(success, msg)
        cb({ success = success, message = msg })
    end, data.businessName, data.description, data.phone, data.category, data.location)
end)

RegisterNUICallback('getMinhaEmpresa', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:getMinhaEmpresa', function(empresa) cb(empresa) end)
end)

RegisterNUICallback('atualizarEmpresa', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:atualizarEmpresa', function(success, msg)
        cb({ success = success, message = msg })
    end, data.businessName, data.description, data.phone, data.category, data.location)
end)

-- ==========================================
-- DISPATCH (receber alerta)
-- ==========================================
RegisterNetEvent('pacheco_phone:serviceAlert')
AddEventHandler('pacheco_phone:serviceAlert', function(callId, coords, serviceName, reason)
    dlog("serviceAlert: callId=" .. tostring(callId) .. " servico=" .. tostring(serviceName) .. " motivo=" .. tostring(reason))
    ESX.ShowNotification(string.format("~r~[%s]~s~ Pedido #%d: %s | /aceitar %d", serviceName, callId, reason, callId))
end)

RegisterNetEvent('pacheco_phone:acceptDispatch')
AddEventHandler('pacheco_phone:acceptDispatch', function(coords)
    dlog("acceptDispatch: X=" .. tostring(coords.x) .. " Y=" .. tostring(coords.y))
    SetNewWaypoint(coords.x, coords.y)
    ESX.ShowNotification("~g~Waypoint definido para o pedido.")
end)