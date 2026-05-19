-- ==========================================
-- PACHECO PHONE - CLIENT.LUA
-- ==========================================
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
local fotoCam         = nil
local cameraMode      = 'tras'
local camRotX         = 0.0   -- pitch (cima/baixo)
local camRotZ         = 0.0   -- yaw (esquerda/direita)

local MY_WEBHOOK_URL = 'https://discord.com/api/webhooks/1502425947977023488/LuEO9qOxYewCCF80tEMee-XwUggw_SiQX7d6vze4uEvgURUpi6rYLa6m6Ow6ZgBjx7bc'

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
end

local function LoadModel(model)
    RequestModel(model)
    local t = 0
    while not HasModelLoaded(model) do
        Citizen.Wait(10)
        t = t + 10
        if t > 5000 then dlog("TIMEOUT a carregar model: " .. tostring(model)); break end
    end
end

-- ==========================================
-- ABRIR / FECHAR TELEMÓVEL
-- ==========================================
function AbrirTelemovel()
    if telemovelAberto then return end
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
end

function FecharTelemovel()
    telemovelAberto = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "fechar" })

    local ped = PlayerPedId()
    ClearPedTasks(ped)

    if propTelemovel and DoesEntityExist(propTelemovel) then
        DeleteEntity(propTelemovel)
        propTelemovel = nil
    end

    if fotoCam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(fotoCam, false)
        fotoCam = nil
        isTakingPhoto = false
        SetNuiFocus(false, false)
        -- Re-abrir foco NUI para o telemovel se ainda aberto
        Citizen.Wait(100)
        if telemovelAberto then
            SetNuiFocus(true, true)
        end
        SendNUIMessage({ action = "esconderCamara" })
    end
end

-- ==========================================
-- LOOP DE CONTROLO DA CÂMARA (Mouse)
-- Enquanto isTakingPhoto=true, lê o rato e roda a câmara
-- ==========================================
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if isTakingPhoto and fotoCam then
            -- Desativar controlo do jogador para capturar o rato
            DisableAllControlActions(0)
            -- Ler movimento do rato
            local mouseX = GetDisabledControlNormal(0, 1) -- eixo horizontal (look left/right)
            local mouseY = GetDisabledControlNormal(0, 2) -- eixo vertical (look up/down)

            local sensitivity = 3.0

            -- Acumular rotação
            camRotZ = camRotZ - (mouseX * sensitivity)
            camRotX = camRotX + (mouseY * sensitivity)

            -- Limitar pitch
            if camRotX > 89.0  then camRotX = 89.0  end
            if camRotX < -89.0 then camRotX = -89.0 end

            -- Aplicar rotação à câmara
            if DoesEntityExist(fotoCam and 0 or 0) or true then
                -- SetCamRot: pitch (X), roll (Y=0), yaw (Z)
                SetCamRot(fotoCam, camRotX, 0.0, camRotZ, 2)
            end
        end
    end
end)

-- ==========================================
-- SISTEMA DE CÂMARA - FOTOGRAM
-- ==========================================
-- =========================================================================
-- VARIÁVEIS GLOBAIS DO FOTOGRAM (OBRIGATÓRIO FICAREM NO TOPO DO FICHEIRO)
-- =========================================================================
local isTakingPhoto = false
local fotoCam = nil
local camRotX = -5.0
local camRotZ = 0.0
local cameraMode = 'tras'

-- Configurações padrão (Altera o Webhook para o teu se necessário)
local MY_WEBHOOK_URL = "https://discord.com/api/webhooks/1502425947977023488/LuEO9qOxYewCCF80tEMee-XwUggw_SiQX7d6vze4uEvgURUpi6rYLa6m6Ow6ZgBjx7bc"
local DEBUG = false

-- =========================================================================
-- SISTEMA DE CÂMARA - FOTOGRAM (CORRIGIDO E UNIFICADO)
-- =========================================================================

-- PASSO 1: Abrir câmara — sem bloquear, sem delay
RegisterNUICallback('tirarFoto', function(data, cb)
    if isTakingPhoto then cb('already'); return end

    local ped     = PlayerPedId()
    local coords  = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    camRotX = -5.0
    camRotZ = heading
    cameraMode = 'tras'

    fotoCam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    if not fotoCam then cb('error'); return end

    -- Câmara traseira: atrás do boneco, a olhar para a frente
    local forward = GetEntityForwardVector(ped)
    SetCamCoord(fotoCam,
        coords.x - forward.x * 1.5,
        coords.y - forward.y * 1.5,
        coords.z + 0.7
    )
    SetCamRot(fotoCam, camRotX, 0.0, camRotZ, 2)
    SetCamFov(fotoCam, 55.0)
    RenderScriptCams(true, true, 300, true, true)
    isTakingPhoto = true

    -- Animação em thread separada, não bloqueia
    Citizen.CreateThread(function()
        RequestAnimDict("cellphone@selfie")
        local t = 0
        while not HasAnimDictLoaded("cellphone@selfie") and t < 3000 do
            Citizen.Wait(10); t = t + 10
        end
        if HasAnimDictLoaded("cellphone@selfie") then
            TaskPlayAnim(ped, "cellphone@selfie", "idle_a", 8.0, -8.0, -1, 50, 0, false, false, false)
        end
    end)

    -- NUI continua focada (não tirar foco — o rato é lido pelo loop abaixo)
    -- Mostrar overlay
    SendNUIMessage({ action = "mostrarCamara" })

    cb('ok')
end)

-- LOOP DE CONTROLO DA CÂMARA
-- Lê o rato através de GetDisabledControlNormal SEM bloquear o NUI
Citizen.CreateThread(function()
    while true do
        if isTakingPhoto and fotoCam then
            Citizen.Wait(0)

            -- Ler movimento do rato (funciona mesmo com NUI focada)
            local mouseX = GetDisabledControlNormal(0, 1)
            local mouseY = GetDisabledControlNormal(0, 2)

            local sensitivity = 2.5
            camRotZ = camRotZ - (mouseX * sensitivity)
            camRotX = camRotX + (mouseY * sensitivity)
            
            if camRotX >  89.0 then camRotX =  89.0 end
            if camRotX < -89.0 then camRotX = -89.0 end

            SetCamRot(fotoCam, camRotX, 0.0, camRotZ, 2)
        else
            Citizen.Wait(100)
        end
    end
end)

-- PASSO 2: Capturar foto
RegisterNUICallback('capturarFoto', function(data, cb)
    if not isTakingPhoto then cb({ url = "" }); return end

    local photoUrl = nil

    -- Screenshot
    local ok = pcall(function()
        exports['screenshot-basic']:requestScreenshotUpload(
            MY_WEBHOOK_URL,
            'files[]',
            function(resData)
                local success, response = pcall(json.decode, resData)
                if success and response and response.attachments and response.attachments[1] then
                    photoUrl = response.attachments[1].url
                else
                    photoUrl = "erro"
                end
            end
        )
    end)
    if not ok then photoUrl = "erro" end

    -- Flash visual
    DoScreenFadeOut(80)
    Citizen.Wait(120)
    DoScreenFadeIn(350)

    -- Aguardar URL (máx 5s)
    local waited = 0
    while not photoUrl and waited < 50 do
        Citizen.Wait(100); waited = waited + 1
    end

    if not photoUrl or photoUrl == "erro" then
        photoUrl = DEBUG and "https://fivem.net/logo.png" or ""
    end

    -- Destruir câmara
    if fotoCam then
        RenderScriptCams(false, true, 400, true, true)
        Citizen.Wait(400)
        DestroyCam(fotoCam, false)
        fotoCam = nil
    end

    ClearPedTasks(PlayerPedId())
    isTakingPhoto = false

    SendNUIMessage({ action = "esconderCamara", photoUrl = photoUrl })
    cb({ url = photoUrl })
end)

-- PASSO 3: Cancelar câmara
RegisterNUICallback('cancelarFoto', function(data, cb)
    if fotoCam then
        RenderScriptCams(false, true, 300, true, true)
        Citizen.Wait(300)
        DestroyCam(fotoCam, false)
        fotoCam = nil
    end
    ClearPedTasks(PlayerPedId())
    isTakingPhoto = false
    SendNUIMessage({ action = "esconderCamara" })
    cb('ok')
end)

-- PASSO 4: Mudar modo (selfie / trás)
RegisterNUICallback('mudarModoCamara', function(data, cb)
    cameraMode = data.modo or 'tras'

    if fotoCam then
        local ped     = PlayerPedId()
        local coords  = GetEntityCoords(ped)
        local forward = GetEntityForwardVector(ped)

        if cameraMode == 'selfie' then
            -- =========================================================
            -- CÂMARA SELFIE — CORRECTA
            -- A câmara fica À FRENTE do boneco, a apontar PARA TRÁS
            -- (como se fosse a câmara da frente do telemóvel real:
            --  vês a tua própria cara porque a câmara está à tua frente)
            -- =========================================================
            -- Posição: ligeiramente à frente e ao nível da cabeça
            SetCamCoord(fotoCam,
                coords.x + forward.x * 0.8,   -- à frente
                coords.y + forward.y * 0.8,
                coords.z + 0.65               -- ao nível dos olhos
            )
            -- Rotação: aponta para trás (180° do heading do ped)
            -- Assim a câmara "olha" para o boneco, como selfie real
            camRotZ = GetEntityHeading(ped) + 180.0
            camRotX = -5.0
        else
            -- =========================================================
            -- CÂMARA TRASEIRA — atrás do boneco, aponta para a frente
            -- =========================================================
            SetCamCoord(fotoCam,
                coords.x - forward.x * 1.5,
                coords.y - forward.y * 1.5,
                coords.z + 0.7
            )
            camRotZ = GetEntityHeading(ped)
            camRotX = -5.0
        end

        SetCamRot(fotoCam, camRotX, 0.0, camRotZ, 2)
    end

    cb('ok')
end)

-- ==========================================
-- EVENTOS E COMANDOS
-- ==========================================
RegisterNetEvent('pacheco_phone:abrirTelefone')
AddEventHandler('pacheco_phone:abrirTelefone', function()
    AbrirTelemovel()
end)

RegisterCommand('telefone', function()
    if not telemovelAberto then
        ESX.TriggerServerCallback('pacheco_phone:verificarItem', function(temPhone)
            if temPhone then
                AbrirTelemovel()
            else
                ESX.ShowNotification("~r~Não tens nenhum telemóvel no inventário!")
            end
        end)
    else
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
            SendNUIMessage({ action = "updateTime", time = string.format("%02d:%02d", hour, minute) })
        end
    end
end)

-- ==========================================
-- CALLBACKS NUI GERAIS
-- ==========================================
RegisterNUICallback('fechar', function(data, cb)
    FecharTelemovel()
    cb('ok')
end)

RegisterNUICallback('getUserData', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:getUserInfo', function(info)
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
    local playerPed = PlayerPedId()
    local players   = ESX.Game.GetPlayersInArea(GetEntityCoords(playerPed), 5.0)
    local serverIds = {}
    for i = 1, #players do
        if players[i] ~= PlayerId() then
            table.insert(serverIds, GetPlayerServerId(players[i]))
        end
    end
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
        cb(faturas)
    end)
end)

RegisterNUICallback('getPredefinedInvoices', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:getPredefinedInvoices', function(faturas) cb(faturas) end)
end)

RegisterNUICallback('sendInvoice', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:sendInvoice', function(success, msg)
        cb({ success = success, message = msg })
    end, data.targetId, data.label, data.amount, data.type)
end)

RegisterNUICallback('payInvoice', function(data, cb)
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
        cb(veiculos)
    end)
end)

-- ==========================================
-- CONTACTOS, CHAMADAS & DISPATCH
-- ==========================================
RegisterNUICallback('getContacts', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:getContacts', function(contacts)
        cb(contacts)
    end)
end)

RegisterNUICallback('addContact', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:addContact', function(success)
        cb({ success = success })
    end, data.name, data.number)
end)

RegisterNUICallback('deleteContact', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:deleteContact', function(success)
        cb({ success = success })
    end, data.id)
end)

RegisterNUICallback('startCall', function(data, cb)
    TriggerServerEvent('pacheco_phone:startCall', data.number)
    cb('ok')
end)

RegisterNUICallback('acceptCall', function(data, cb)
    TriggerServerEvent('pacheco_phone:acceptCall', data.targetSource)
    cb('ok')
end)

RegisterNUICallback('rejectCall', function(data, cb)
    TriggerServerEvent('pacheco_phone:rejectCall', data.targetSource)
    cb('ok')
end)

RegisterNUICallback('endCall', function(data, cb)
    TriggerServerEvent('pacheco_phone:endCall')
    cb('ok')
end)

RegisterNUICallback('startDispatch', function(data, cb)
    local playerCoords = GetEntityCoords(PlayerPedId())
    TriggerServerEvent('pacheco_phone:callService', data.number, data.reason, playerCoords)
    cb('ok')
end)

RegisterNetEvent('pacheco_phone:incomingCall')
AddEventHandler('pacheco_phone:incomingCall', function(number, source)
    SendNUIMessage({ action = "incomingCall", number = number, source = source })
end)

RegisterNetEvent('pacheco_phone:callAccepted')
AddEventHandler('pacheco_phone:callAccepted', function(channel)
    SendNUIMessage({ action = "callAccepted" })
    exports["pma-voice"]:setCallChannel(channel)
end)

RegisterNetEvent('pacheco_phone:callFailed')
AddEventHandler('pacheco_phone:callFailed', function(reason)
    SendNUIMessage({ action = "callFailed", reason = reason })
end)

RegisterNetEvent('pacheco_phone:callEnded')
AddEventHandler('pacheco_phone:callEnded', function()
    SendNUIMessage({ action = "callEnded" })
    exports["pma-voice"]:setCallChannel(0)
end)

-- ==========================================
-- SMS
-- ==========================================
RegisterNUICallback('getMessages', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:getMessages', function(msgs, myNumber)
        cb({ messages = msgs, myNumber = myNumber })
    end)
end)

RegisterNUICallback('sendMessage', function(data, cb)
    TriggerServerEvent('pacheco_phone:sendMessage', data.number, data.message)
    cb('ok')
end)

RegisterNetEvent('pacheco_phone:receiveSMS')
AddEventHandler('pacheco_phone:receiveSMS', function(sender, message)
    SendNUIMessage({ action = "receiveSMS", sender = sender, message = message })
    if not telemovelAberto then
        ESX.ShowNotification("~b~Nova Mensagem de ~s~" .. sender)
    end
end)

RegisterNetEvent('pacheco_phone:smsSent')
AddEventHandler('pacheco_phone:smsSent', function()
    SendNUIMessage({ action = "smsSent" })
end)

-- ==========================================
-- TWITTER
-- ==========================================
RegisterNUICallback('twitterLogin', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:twitterLogin', function(success, resultData)
        cb({ success = success, data = resultData })
    end, data.username, data.password)
end)

RegisterNUICallback('twitterRegister', function(data, cb)
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
    TriggerServerEvent('pacheco_phone:postBlackmarket', data.message, data.topic)
    cb('ok')
end)

RegisterNUICallback('getDWListings', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:getDWListings', function(listings) cb(listings) end, data.topic)
end)

RegisterNUICallback('postDWListing', function(data, cb)
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
        cb({ messages = msgs, myNumber = myNumber })
    end)
end)

RegisterNUICallback('sendZZMessage', function(data, cb)
    TriggerServerEvent('pacheco_phone:sendZZMessage', data.number, data.message)
    cb('ok')
end)

RegisterNUICallback('getZZGroups', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:getZZGroups', function(groups)
        cb(groups)
    end)
end)

RegisterNUICallback('createZZGroup', function(data, cb)
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
    TriggerServerEvent('pacheco_phone:zzShareLocation', data.number, coords.x, coords.y, coords.z)
    cb('ok')
end)

RegisterNetEvent('pacheco_phone:receiveZZ')
AddEventHandler('pacheco_phone:receiveZZ', function(sender, message)
    SendNUIMessage({ action = "receiveZZ", sender = sender, message = message })
    if not telemovelAberto then
        ESX.ShowNotification("~g~[ZipZap] ~s~Nova mensagem de " .. sender)
    end
end)

RegisterNetEvent('pacheco_phone:receiveZZGroup')
AddEventHandler('pacheco_phone:receiveZZGroup', function(groupId, groupName, sender, message)
    SendNUIMessage({ action = "receiveZZGroup", groupId = groupId, groupName = groupName, sender = sender, message = message })
    if not telemovelAberto then
        ESX.ShowNotification("~g~[ZipZap] ~s~" .. groupName .. ": " .. sender)
    end
end)

-- ==========================================
-- FOTOGRAM
-- ==========================================
RegisterNUICallback('fotogramLogin', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:fotogramLogin', function(success, resultData)
        cb({ success = success, data = resultData })
    end, data.username, data.password)
end)

RegisterNUICallback('fotogramRegister', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:fotogramRegister', function(success, msg)
        cb({ success = success, message = msg })
    end, data.username, data.password)
end)

RegisterNUICallback('getFotogramFeed', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:getFotogramFeed', function(posts)
        cb(posts)
    end)
end)

RegisterNUICallback('postFotogram', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:postFotogram', function(success, msg)
        cb({ success = success, message = msg })
    end, data.username, data.avatar, data.imageUrl, data.caption)
end)

RegisterNUICallback('likeFotogram', function(data, cb)
    TriggerServerEvent('pacheco_phone:likeFotogram', data.postId)
    cb('ok')
end)

RegisterNUICallback('getFotogramComments', function(data, cb)
    ESX.TriggerServerCallback('pacheco_phone:getFotogramComments', function(comments)
        cb(comments)
    end, data.postId)
end)

RegisterNUICallback('postFotogramComment', function(data, cb)
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
    ESX.TriggerServerCallback('pacheco_phone:getPaginasAmarelas', function(empresas)
        cb(empresas)
    end, data.category)
end)

RegisterNUICallback('registarEmpresa', function(data, cb)
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
    ESX.ShowNotification(string.format("~r~[%s]~s~ Pedido #%d: %s | /aceitar %d", serviceName, callId, reason, callId))
end)

RegisterNetEvent('pacheco_phone:acceptDispatch')
AddEventHandler('pacheco_phone:acceptDispatch', function(coords)
    SetNewWaypoint(coords.x, coords.y)
    ESX.ShowNotification("~g~Waypoint definido para o pedido.")
end)