$(document).ready(function() {
    let isDragging = false, startY = 0, appAberta = null;
    let currentTwitterAccount = null, currentTwitterTopic = null, currentBMTopic = null;
    let listaContactosCache = [], smsAbertoNum = null, myPhoneNumber = null, myJob = "unemployed";
    let activeCallSource = null, callTimer = null, callSeconds = 0, pendingDispatchNumber = null;
    let unreadSmsCount = 0, unreadZZCount = 0;
    let currentZZChat = null, currentZZGroupId = null, zzMyNumber = null;
    let fotogramAccount = null;
    let currentCommentPostId = null;
    let modoCamara = "tras";

    // ==========================================
    // INIT & PREFERÊNCIAS
    // ==========================================
    function aplicarWallpaper(url) { if (url) $(".ecra, #lockscreen").css("background-image", "url('" + url + "')"); }
    aplicarWallpaper(localStorage.getItem('pacheco_wallpaper') || 'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?q=80&w=1000');
    $("#perfil-img").attr("src", localStorage.getItem('pacheco_avatar') || 'https://www.w3schools.com/howto/img_avatar.png');

    function mostrarNotificacao(tipo, msg) {
        let id = "notif-" + Math.floor(Math.random() * 9999);
        let cor = tipo === 'success' ? 'notify-success' : tipo === 'warning' ? 'notify-warning' : 'notify-error';
        $("#phone-notifications").append(`<div class="phone-notify ${cor}" id="${id}">${msg}</div>`);
        setTimeout(() => { $("#" + id).fadeOut(300, function() { $(this).remove(); }); }, 3500);
    }
    function atualizarData() { const op = { weekday: 'long', day: 'numeric', month: 'short' }; $(".lock-date").text(new Date().toLocaleDateString('pt-PT', op)); }
    function updateSmsBadge() { if (unreadSmsCount > 0) { $("#sms-badge").text(unreadSmsCount).show(); } else { $("#sms-badge").hide(); } }
    function updateZZBadge() { if (unreadZZCount > 0) { $("#zz-badge").text(unreadZZCount).show(); } else { $("#zz-badge").hide(); } }

    // ==========================================
    // SISTEMA DE VOLTAR
    // ==========================================
    $(document).on('click', '.btn-voltar', function() {
        let destino = $(this).data("target");
        if (destino === "home") { $(".system-app, .app-screen").hide(); $("#home-screen").fadeIn(150); appAberta = "home"; }
        else if (destino === "definicoes") { $(".system-app").hide(); $("#app-definicoes").fadeIn(150); appAberta = "definicoes"; }
        else if (destino === "contactos-fechar") { $("#modal-novo-contacto").hide(); }
        else if (destino === "sms-fechar") { $("#modal-nova-sms").hide(); }
        else if (destino === "zz-fechar") { $("#modal-nova-zz").hide(); }
        else if (destino === "pa-list") { $(".system-app").hide(); $("#app-paginasamarelas").show(); appAberta = "paginasamarelas"; carregarPaginasAmarelas(); }
        else if (destino === "fotogram-feed") { $("#fotogram-compose-view, #fotogram-comments-view, #fotogram-profile-view").hide(); $("#fotogram-feed-view").show(); }
    });

    // ==========================================
    // MENSAGENS LUA → NUI
    // ==========================================
// ==========================================
// ==========================================
    window.addEventListener('message', function(e) {
        let d = e.data;
        if (d.action === "abrir") { atualizarData(); $("#telemovel").fadeIn(200); $("#lockscreen").removeClass('unlocked'); appAberta = "locked"; }
        else if (d.action === "fechar") { $("#telemovel").fadeOut(200); }
        else if (d.action === "updateTime") { $("#horas-lock, #horas-header").text(d.time); }
        else if (d.action === "incomingCall") { activeCallSource = d.source; $("#call-name").text(d.number); $("#call-status").text("A Receber..."); $("#btn-accept-call").show(); $("#call-screen").fadeIn(200); }
        else if (d.action === "callAccepted") { $("#call-status").text("00:00"); $("#btn-accept-call").hide(); callSeconds = 0; clearInterval(callTimer); callTimer = setInterval(() => { callSeconds++; let m = Math.floor(callSeconds/60).toString().padStart(2,'0'); let s = (callSeconds%60).toString().padStart(2,'0'); $("#call-status").text(`${m}:${s}`); }, 1000); }
        else if (d.action === "callFailed") { $("#call-status").text(d.reason); setTimeout(() => { $("#call-screen").fadeOut(200); clearInterval(callTimer); activeCallSource = null; }, 2000); }
        else if (d.action === "callEnded") { $("#call-status").text("Terminada"); clearInterval(callTimer); setTimeout(() => { $("#call-screen").fadeOut(200); activeCallSource = null; }, 1500); }
        else if (d.action === "receiveSMS") {
            if (appAberta === "sms" && smsAbertoNum === d.sender && $("#sms-chat-view").is(":visible")) { window.abrirChatSMS(smsAbertoNum); }
            else { unreadSmsCount++; updateSmsBadge(); mostrarNotificacao('success', '💬 SMS de ' + d.sender); }
        }
        else if (d.action === "smsSent") { if (appAberta === "sms" && smsAbertoNum && $("#sms-chat-view").is(":visible")) { window.abrirChatSMS(smsAbertoNum); } }
        else if (d.action === "receiveZZ") {
            if (appAberta === "zipzap" && currentZZChat === d.sender && $("#zz-chat-view").is(":visible")) { carregarChatZZ(d.sender); }
            else { unreadZZCount++; updateZZBadge(); mostrarNotificacao('success', '⚡ ZipZap de ' + d.sender); }
        }
        else if (d.action === "receiveZZGroup") {
            if (appAberta === "zipzap" && currentZZGroupId == d.groupId) { carregarZZGroupMessages(d.groupId); }
            else { unreadZZCount++; updateZZBadge(); mostrarNotificacao('success', `⚡ [${d.groupName}] ${d.sender}`); }
        }
        else if (d.action === "newTweet" && appAberta === "twitter" && currentTwitterTopic === d.topic) { carregarFeedTwitter(d.topic); }
        else if (d.action === "newBlackmarketMsg" && appAberta === "blackmarket" && currentBMTopic === d.topic) { window.abrirTopicoBM(d.topic); }
        else if (d.action === "newFotogramPost" && appAberta === "fotogram") { carregarFeedFotogram(); }
        
        // CORREÇÃO AQUI: Ativa a câmara, centraliza o tlm e ESCONDE o formulário do Fotogram atrás
        else if (d.action === "mostrarCamara") { 
            $("#overlay-camara").fadeIn(200); 
            $("#telemovel").addClass("camara-ativa");
            
            // Torna invisível o conteúdo antigo (textos, botões antigos, inputs) para não tapar o jogo
            $("#telemovel .tela, #telemovel .app-container, #telemovel .nova-publicacao").css("visibility", "hidden");
            // Garante que o painel da câmara novo fica 100% visível
            $("#overlay-camara").css("visibility", "visible").find("*").css("visibility", "visible");
        }
        
        // CORREÇÃO AQUI: Fecha a câmara e devolve a visibilidade ao ecrã do Fotogram
        else if (d.action === "esconderCamara") { 
            $("#overlay-camara").fadeOut(200); 
            $("#telemovel").removeClass("camara-ativa");
            
            // Devolve a visibilidade ao Fotogram para o jogador publicar a foto
            $("#telemovel .tela, #telemovel .app-container, #telemovel .nova-publicacao").css("visibility", "visible");
        }
    });

    // ==========================================
    // LOCKSCREEN & HOME
    // ==========================================
    $('#lockscreen').on('mousedown', function(e) { isDragging = true; startY = e.pageY; });
    $(document).on('mousemove', function(e) {
        if (isDragging && startY - e.pageY > 60) {
            $('#lockscreen').addClass('unlocked'); isDragging = false; $("#home-screen").fadeIn(200); appAberta = "home";
            $.post('https://pacheco_phone/getContacts', JSON.stringify({}), function(c) { listaContactosCache = c || []; });
        }
    });
    $(document).on('mouseup', function() { isDragging = false; });
    // Evento para o botão de rodar a câmara
    $(document).on('click', '#btn-fg-rodar-camara', function(e) {
        e.preventDefault();
        
        // Alterna entre 'tras' e 'selfie'
        modoCamara = (modoCamara === "tras") ? "selfie" : "tras";
        
        // Avisa o Client Lua para reposicionar a câmara do jogo
        $.post('https://Pacheco_phone/mudarModoCamara', JSON.stringify({ modo: modoCamara }));
    });

    $("#btn-home").click(function() {
        if (appAberta === "locked") return;
        if (["wallpapers","avatar","sobre","twitter-avatar"].includes(appAberta)) { $(".system-app").hide(); $("#app-definicoes").show(); appAberta = "definicoes"; }
        else if (appAberta !== "home" && appAberta !== null) { $(".system-app, .app-screen").hide(); $("#home-screen").show(); appAberta = "home"; }
        else { $.post('https://pacheco_phone/fechar', JSON.stringify({})); }
    });
    document.onkeyup = function(data) { if (data.which == 27 && $("#call-screen").is(":hidden") && $("#modal-dispatch-reason").is(":hidden")) { $.post('https://pacheco_phone/fechar', JSON.stringify({})); } };

    // ==========================================
    // NAVEGAÇÃO APPS
    // ==========================================
    $(document).on('click', '.app', function() {
        if (appAberta === "locked") return;
        let app = $(this).data("app");
        $(".app-screen, .system-app").hide(); appAberta = app; $("#app-" + app).fadeIn(150);

        if (app === "twitter") { if (currentTwitterAccount) { $("#twitter-auth-view").hide(); $("#twitter-topics-view").show(); carregarTopicosTwitter(); } else { $("#twitter-topics-view").hide(); $("#twitter-auth-view").show(); } }
        else if (app === "blackmarket") { $("#bm-chat-view").hide(); $("#bm-topics-view").show(); carregarTopicosBM(); }
        else if (app === "definicoes") { $.post('https://pacheco_phone/getUserData', JSON.stringify({}), function(data) { $("#def-nome").text(data ? data.nome : "Erro"); $("#def-numero").text(data ? data.numero : "Erro"); }); }
        else if (app === "garagem") { carregarGaragem(); }
        else if (app === "sms") { unreadSmsCount = 0; updateSmsBadge(); carregarConversasSMS(); }
        else if (app === "contactos") { carregarContactos(); }
        else if (app === "banco") { $.post('https://pacheco_phone/getBankInfo', JSON.stringify({}), function(info) { if(info) { $("#banco-saldo").text(info.saldo + "€"); $("#banco-iban").text(info.iban); } }); }
        else if (app === "telefone") { $("#dial-number").val(""); }
        else if (app === "efaturas") { carregarEfaturas(); }
        else if (app === "zipzap") { unreadZZCount = 0; updateZZBadge(); carregarZZConversas(); }
        else if (app === "fotogram") { if(fotogramAccount) { $("#fotogram-auth-view").hide(); $("#fotogram-feed-view").show(); carregarFeedFotogram(); } else { $("#fotogram-feed-view").hide(); $("#fotogram-auth-view").show(); } }
        else if (app === "paginasamarelas") { carregarPaginasAmarelas(); }
    });

    // ==========================================
    // GARAGEM
    // ==========================================
    function carregarGaragem() {
        $.post('https://pacheco_phone/getGaragemData', JSON.stringify({}), function(v) {
            $("#lista-garagem").empty();
            if(!v || v.length === 0) { $("#lista-garagem").append("<p style='text-align:center;color:var(--text-muted);margin-top:30px;'>Sem veículos registados.</p>"); return; }
            v.forEach(x => {
                let isApreendido = (x.status === "Apreendido");
                let isRua = (x.status === "Na Rua");
                let badgeClass = isApreendido ? "bg-red" : isRua ? "bg-amber" : "bg-blue";
                $("#lista-garagem").append(`
                    <div class="car-card-modern">
                        <div class="car-header-m"><h4>${x.name}</h4><span class="status-badge ${badgeClass}">${x.status}</span></div>
                        <span class="car-plate-modern">${x.plate}</span>
                        <div class="car-stats-m">
                            <span><i class="fas fa-gas-pump" style="color:var(--danger);"></i> ${x.fuel}%</span>
                            <span><i class="fas fa-wrench" style="color:var(--text-muted);"></i> ${x.engine}%</span>
                            <span><i class="fas fa-shield-alt" style="color:#f43f5e;"></i> ${x.body}%</span>
                        </div>
                    </div>
                `);
            });
        });
    }

    // ==========================================
    // E-FATURAS
    // ==========================================
    function carregarEfaturas() {
        $.post('https://pacheco_phone/getUserData', JSON.stringify({}), function(data) { myJob = data ? data.job : "unemployed"; });
        carregarFaturasPendentes();
        $(".ef-nav-btn").removeClass("active"); $(".ef-nav-btn[data-tab='pendentes']").addClass("active");
        $(".ef-tab-content").hide(); $("#tab-pendentes").show();
    }

    $(".ef-nav-btn").click(function() {
        $(".ef-nav-btn").removeClass("active"); $(this).addClass("active");
        $(".ef-tab-content").hide();
        let tab = $(this).data("tab");
        $("#tab-" + tab).fadeIn(150);
        if (tab === "pendentes") carregarFaturasPendentes();
        else if (tab === "emitir") atualizarPessoasProximas();
        else if (tab === "empresa") carregarFaturasEmpresa();
    });

    function carregarFaturasPendentes() {
        $.post('https://pacheco_phone/getInvoices', JSON.stringify({}), function(faturas) {
            $("#lista-faturas-pendentes").empty();
            if(!faturas || faturas.length === 0) { $("#lista-faturas-pendentes").append("<p style='text-align:center;color:var(--text-muted);margin-top:20px;'>Sem faturas pendentes.</p>"); return; }
            faturas.forEach(f => {
                let remetente = f.target_type === 'society' ? f.target : 'Cidadão';
                $("#lista-faturas-pendentes").append(`
                    <div class="car-card-modern" style="margin:10px 15px;">
                        <div class="car-header-m"><h4>${f.label}</h4><span class="status-badge bg-red">${f.amount}€</span></div>
                        <p style="font-size:12px;color:var(--text-muted);margin:0 0 10px;">De: ${remetente}</p>
                        <button class="btn-solid btn-pay-invoice" data-id="${f.id}">Pagar</button>
                    </div>
                `);
            });
        });
    }

    $(document).on('click', '.btn-pay-invoice', function() {
        let id = $(this).data("id"); let btn = $(this); btn.prop('disabled',true).text("A Pagar...");
        $.post('https://pacheco_phone/payInvoice', JSON.stringify({invoiceId: id}), function(res) {
            if(res.success) { mostrarNotificacao('success','Fatura Paga!'); carregarFaturasPendentes(); }
            else { mostrarNotificacao('error', res.message); btn.prop('disabled',false).text("Pagar"); }
        });
    });

    function atualizarPessoasProximas() {
        $("#ef-alvo").empty().append('<option value="">A procurar...</option>');
        $.post('https://pacheco_phone/getNearbyPlayers', JSON.stringify({}), function(players) {
            $("#ef-alvo").empty();
            if(!players || players.length === 0) { $("#ef-alvo").append('<option value="">Ninguém por perto</option>'); return; }
            players.forEach(p => { $("#ef-alvo").append(`<option value="${p.id}">ID:${p.id} - ${p.name}</option>`); });
        });
    }

    $("#btn-refresh-nearby").click(function() { atualizarPessoasProximas(); });
    $("#btn-enviar-fatura").click(function() {
        let targetId = $("#ef-alvo").val(), label = $("#ef-descricao").val().trim(), amount = $("#ef-valor").val(), type = $("#ef-tipo").val();
        if(!targetId || !label || !amount || amount <= 0) { mostrarNotificacao('error','Preenche todos os campos!'); return; }
        $.post('https://pacheco_phone/sendInvoice', JSON.stringify({targetId, label, amount, type}), function(res) {
            if(res.success) { mostrarNotificacao('success','Fatura Emitida!'); $("#ef-descricao, #ef-valor").val(""); }
            else mostrarNotificacao('error', res.message);
        });
    });

    function carregarFaturasEmpresa() {
        $.post('https://pacheco_phone/getPredefinedInvoices', JSON.stringify({}), function(faturas) {
            $("#lista-faturas-empresa").empty();
            if(!faturas || faturas.length === 0) { $("#lista-faturas-empresa").append("<p style='text-align:center;color:var(--text-muted);margin-top:20px;'>Sem faturas predefinidas.</p>"); return; }
            faturas.forEach(f => {
                $("#lista-faturas-empresa").append(`
                    <div class="car-card-modern" style="margin:10px 15px;">
                        <div class="car-header-m"><h4>${f.label}</h4><span class="status-badge bg-blue">${f.amount}€</span></div>
                        <button class="btn-outline btn-predef-invoice" data-label="${f.label}" data-amount="${f.amount}" style="margin-top:10px;">Usar</button>
                    </div>
                `);
            });
        });
    }

    $(document).on('click', '.btn-predef-invoice', function() {
        let l = $(this).data("label"), a = $(this).data("amount");
        $(".ef-nav-btn").removeClass("active"); $(".ef-nav-btn[data-tab='emitir']").addClass("active");
        $(".ef-tab-content").hide(); $("#tab-emitir").fadeIn(150);
        $("#ef-descricao").val(l); $("#ef-valor").val(a); $("#ef-tipo").val("society");
        atualizarPessoasProximas();
    });

    // ==========================================
    // DEFINIÇÕES
    // ==========================================
    $("#btn-wallpapers").click(function() { $(".system-app").hide(); $("#app-wallpapers").fadeIn(150); appAberta = "wallpapers"; });
    $(document).on('click', '.wall-item', function() { let url = $(this).data("url"); if(url) { localStorage.setItem('pacheco_wallpaper', url); aplicarWallpaper(url); mostrarNotificacao('success','Wallpaper atualizado!'); $(".system-app").hide(); $("#app-definicoes").show(); appAberta = "definicoes"; } });
    $("#btn-mudar-avatar").click(function() { $(".system-app").hide(); $("#app-avatar").fadeIn(150); appAberta = "avatar"; });
    $(document).on('click', '.avatar-item', function() { let url = $(this).data("url"); localStorage.setItem('pacheco_avatar', url); $("#perfil-img").attr("src", url); $(".system-app").hide(); $("#app-definicoes").fadeIn(150); appAberta = "definicoes"; mostrarNotificacao('success','Avatar atualizado!'); });
    $("#btn-sobre").click(function() { $.post('https://pacheco_phone/getPhoneVersion', JSON.stringify({}), function(data) { $("#phone-version").text(data.version || "3.0.0"); $(".system-app").hide(); $("#app-sobre").fadeIn(150); appAberta = "sobre"; }); });

    // ==========================================
    // TELEFONE
    // ==========================================
    window.tentarLigar = function(num, name) {
        if (num === "112" || num === "111" || num === "113") { pendingDispatchNumber = num; $("#dispatch-reason-input").val(""); $("#modal-dispatch-reason").fadeIn(150); }
        else { $("#call-name").text(name || num); $("#call-status").text("A Ligar..."); $("#btn-accept-call").hide(); $("#call-screen").fadeIn(200); $.post('https://pacheco_phone/startCall', JSON.stringify({number: num})); }
    }
    $(".dial-key").click(function() { let val = $(this).data("num"); let current = $("#dial-number").val(); if(val === "del") { $("#dial-number").val(current.slice(0,-1)); } else { $("#dial-number").val(current + val); } });
    $("#btn-iniciar-chamada").click(function() { let num = $("#dial-number").val().trim(); if(num.length < 3) return; window.tentarLigar(num, num); });
    $("#btn-send-dispatch").click(function() { let reason = $("#dispatch-reason-input").val().trim(); if(!reason) { mostrarNotificacao("error","Indica um motivo."); return; } $("#modal-dispatch-reason").hide(); let sName = pendingDispatchNumber === "112" ? "Polícia" : (pendingDispatchNumber === "111" ? "INEM" : "Mecânicos"); $("#call-name").text(sName); $("#call-status").text("A contactar central..."); $("#btn-accept-call").hide(); $("#call-screen").fadeIn(200); $.post('https://pacheco_phone/startDispatch', JSON.stringify({number: pendingDispatchNumber, reason: reason})); pendingDispatchNumber = null; });
    $("#btn-cancel-dispatch").click(function() { $("#modal-dispatch-reason").hide(); pendingDispatchNumber = null; });
    $("#btn-accept-call").click(function() { if(activeCallSource) $.post('https://pacheco_phone/acceptCall', JSON.stringify({targetSource: activeCallSource})); });
    $("#btn-end-call").click(function() { if(activeCallSource) $.post('https://pacheco_phone/rejectCall', JSON.stringify({targetSource: activeCallSource})); else $.post('https://pacheco_phone/endCall', JSON.stringify({})); });

    // ==========================================
    // CONTACTOS
    // ==========================================
    function carregarContactos() {
        $.post('https://pacheco_phone/getContacts', JSON.stringify({}), function(contacts) {
            listaContactosCache = contacts || [];
            $("#lista-contactos").empty();
            let defaults = [{name:'Polícia',number:'112'},{name:'INEM',number:'111'},{name:'Mecânicos',number:'113'}];
            defaults.forEach(d => { $("#lista-contactos").append(`<div class="contact-item" style="border-left:4px solid var(--accent);"><div class="contact-info"><h4>${d.name}</h4><p>${d.number}</p></div><div class="contact-actions"><button class="contact-btn btn-call-small" onclick="window.tentarLigar('${d.number}','${d.name}')"><i class="fas fa-phone"></i></button></div></div>`); });
            if(listaContactosCache.length > 0) {
                listaContactosCache.forEach(c => { $("#lista-contactos").append(`<div class="contact-item"><div class="contact-info"><h4>${c.name}</h4><p>${c.number}</p></div><div class="contact-actions"><button class="contact-btn btn-call-small" onclick="event.stopPropagation();window.tentarLigar('${c.number}','${c.name}')"><i class="fas fa-phone"></i></button><button class="contact-btn btn-sms-small" onclick="event.stopPropagation();window.mandarSmsContacto('${c.number}')"><i class="fas fa-comment"></i></button><button class="contact-btn" style="background:var(--success);" onclick="event.stopPropagation();window.mandarZZContacto('${c.number}')"><i class="fas fa-bolt"></i></button><button class="contact-btn btn-del-small" onclick="event.stopPropagation();window.apagarContacto(${c.id})"><i class="fas fa-trash"></i></button></div></div>`); });
            }
        });
    }
    window.apagarContacto = function(id) { $.post('https://pacheco_phone/deleteContact', JSON.stringify({id}), function() { carregarContactos(); mostrarNotificacao('success','Apagado!'); }); }
    $("#btn-add-contact").click(function() { $("#modal-novo-contacto").show(); });
    $("#btn-cancelar-contacto").click(function() { $("#modal-novo-contacto").hide(); });
    $("#btn-guardar-contacto").click(function() { let n = $("#novo-cont-nome").val().trim(); let num = $("#novo-cont-numero").val().trim(); if(!n||!num) { mostrarNotificacao('error','Preenche todos os campos!'); return; } $.post('https://pacheco_phone/addContact', JSON.stringify({name:n,number:num}), function(data) { if(data.success) { $("#novo-cont-nome,#novo-cont-numero").val(""); mostrarNotificacao('success','Guardado.'); $("#modal-novo-contacto").hide(); carregarContactos(); } }); });

    // ==========================================
    // SMS
    // ==========================================
    window.mandarSmsContacto = function(num) { $(".system-app").hide(); $("#app-sms").show(); appAberta = "sms"; window.abrirChatSMS(num); }
    function carregarConversasSMS() {
        $.post('https://pacheco_phone/getMessages', JSON.stringify({}), function(data) {
            if(!data) return; myPhoneNumber = data.myNumber; $("#lista-conversas").empty();
            let conversas = {};
            (data.messages || []).forEach(m => { let otherNum = (m.sender === myPhoneNumber) ? m.receiver : m.sender; if(!conversas[otherNum]) conversas[otherNum] = []; conversas[otherNum].push(m); });
            for(const [num, arrayMsgs] of Object.entries(conversas)) {
                let last = arrayMsgs[arrayMsgs.length-1];
                let timeStr = new Date(last.timestamp).toLocaleTimeString('pt-PT',{hour:'2-digit',minute:'2-digit'});
                let c = listaContactosCache.find(x => x.number === num);
                let nome = c ? c.name : num;
                $("#lista-conversas").prepend(`<div class="conversa-item" onclick="window.abrirChatSMS('${num}')"><div class="conv-top"><h4>${nome}</h4><span>${timeStr}</span></div><p class="conv-msg">${last.message}</p></div>`);
            }
        });
    }
    window.abrirChatSMS = function(num) {
        smsAbertoNum = num; let c = listaContactosCache.find(x => x.number === num);
        $("#chat-nome-contacto").text(c ? c.name : num); $("#sms-list-view").hide(); $("#sms-chat-view").show();
        $.post('https://pacheco_phone/getMessages', JSON.stringify({}), function(data) {
            let box = $("#chat-messages"); box.empty();
            if(data && data.messages) { data.messages.forEach(m => { if(m.sender === num || m.receiver === num) { let balaoClass = (m.sender === myPhoneNumber) ? "enviada" : "recebida"; box.append(`<div class="balao ${balaoClass}">${m.message}</div>`); } }); }
            box.scrollTop(box[0].scrollHeight);
        });
    }
    $("#btn-enviar-sms").off('click').on('click', function() { let txt = $("#sms-input-texto").val().trim(); if(!txt) return; $.post('https://pacheco_phone/sendMessage', JSON.stringify({number:smsAbertoNum,message:txt})); $("#sms-input-texto").val(""); let box = $("#chat-messages"); box.append(`<div class="balao enviada">${txt}</div>`); box.scrollTop(box[0].scrollHeight); });
    $("#sms-input-texto").off('keypress').on('keypress', function(e) { if(e.which==13) $("#btn-enviar-sms").click(); });
    $("#btn-voltar-sms").click(function() { $("#sms-chat-view").hide(); $("#sms-list-view").show(); carregarConversasSMS(); });
    $("#btn-new-sms").click(function() { $("#modal-nova-sms").show(); $.post('https://pacheco_phone/getContacts', JSON.stringify({}), function(contacts) { let d = $("#nova-sms-contacto"); d.empty().append('<option value="">Selecionar...</option>'); if(contacts) contacts.forEach(c => { d.append(`<option value="${c.number}">${c.name}</option>`); }); }); });
    $("#btn-iniciar-conversa").click(function() { let finalNum = $("#nova-sms-contacto").val() || $("#nova-sms-numero").val().trim(); if(finalNum) { $("#modal-nova-sms").hide(); window.abrirChatSMS(finalNum); } });

    // ==========================================
    // ZIPZAP
    // ==========================================
    window.mandarZZContacto = function(num) { $(".system-app").hide(); $("#app-zipzap").show(); appAberta = "zipzap"; window.abrirChatZZ(num); }

    function carregarZZConversas() {
        $.post('https://pacheco_phone/getZZMessages', JSON.stringify({}), function(data) {
            if(!data) return; zzMyNumber = data.myNumber; $("#zz-conversas-list").empty();
            let conversas = {};
            (data.messages || []).forEach(m => { let otherNum = (m.sender === zzMyNumber) ? m.receiver : m.sender; if(!conversas[otherNum]) conversas[otherNum] = []; conversas[otherNum].push(m); });
            for(const [num, arrayMsgs] of Object.entries(conversas)) {
                let last = arrayMsgs[arrayMsgs.length-1];
                let timeStr = new Date(last.timestamp).toLocaleTimeString('pt-PT',{hour:'2-digit',minute:'2-digit'});
                let c = listaContactosCache.find(x => x.number === num);
                let nome = c ? c.name : num;
                $("#zz-conversas-list").prepend(`<div class="conversa-item zz-conversa" onclick="window.abrirChatZZ('${num}')"><div class="conv-top"><h4>⚡ ${nome}</h4><span>${timeStr}</span></div><p class="conv-msg">${last.message}</p></div>`);
            }
        });
        carregarZZGrupos();
    }

    function carregarZZGrupos() {
        $.post('https://pacheco_phone/getZZGroups', JSON.stringify({}), function(groups) {
            $("#zz-grupos-list").empty();
            if(!groups || groups.length === 0) return;
            groups.forEach(g => {
                let icon = g.type === 'job' ? '🏢' : '👥';
                $("#zz-grupos-list").append(`<div class="conversa-item" onclick="window.abrirGrupoZZ(${g.id},'${g.name}')"><div class="conv-top"><h4>${icon} ${g.name}</h4><span>${g.type === 'job' ? g.job : 'Grupo'}</span></div></div>`);
            });
        });
    }

    window.abrirChatZZ = function(num) {
        currentZZChat = num; currentZZGroupId = null;
        let c = listaContactosCache.find(x => x.number === num);
        $("#zz-chat-titulo").text(c ? c.name : num);
        $("#zz-list-view").hide(); $("#zz-chat-view").show();
        carregarChatZZ(num);
    }

    function carregarChatZZ(num) {
        $.post('https://pacheco_phone/getZZMessages', JSON.stringify({}), function(data) {
            let box = $("#zz-chat-messages"); box.empty();
            if(data && data.messages) {
                data.messages.forEach(m => {
                    if(m.sender === num || m.receiver === num) {
                        let balaoClass = (m.sender === zzMyNumber) ? "enviada" : "recebida";
                        let icon = m.message.startsWith('[LOCALIZAÇÃO]') ? '📍 ' : '';
                        box.append(`<div class="balao ${balaoClass}">${icon}${m.message}</div>`);
                    }
                });
            }
            box.scrollTop(box[0].scrollHeight);
        });
    }

    window.abrirGrupoZZ = function(groupId, groupName) {
        currentZZGroupId = groupId; currentZZChat = null;
        $("#zz-chat-titulo").text("👥 " + groupName);
        $("#zz-list-view").hide(); $("#zz-chat-view").show();
        carregarZZGroupMessages(groupId);
    }

    function carregarZZGroupMessages(groupId) {
        $.post('https://pacheco_phone/getZZGroupMessages', JSON.stringify({groupId}), function(msgs) {
            let box = $("#zz-chat-messages"); box.empty();
            if(msgs) msgs.forEach(m => {
                let balaoClass = (m.sender === zzMyNumber) ? "enviada" : "recebida";
                box.append(`<div class="balao ${balaoClass}">${balaoClass === 'recebida' ? `<small style="color:var(--accent);font-size:10px;">${m.sender}</small><br>` : ''}${m.message}</div>`);
            });
            box.scrollTop(box[0].scrollHeight);
        });
    }

    $("#btn-enviar-zz").off('click').on('click', function() {
        let txt = $("#zz-input-texto").val().trim(); if(!txt) return;
        if(currentZZGroupId) { $.post('https://pacheco_phone/sendZZGroupMessage', JSON.stringify({groupId:currentZZGroupId, message:txt})); }
        else { $.post('https://pacheco_phone/sendZZMessage', JSON.stringify({number:currentZZChat, message:txt})); }
        $("#zz-input-texto").val("");
        let box = $("#zz-chat-messages"); box.append(`<div class="balao enviada">${txt}</div>`); box.scrollTop(box[0].scrollHeight);
    });
    $("#zz-input-texto").off('keypress').on('keypress', function(e) { if(e.which==13) $("#btn-enviar-zz").click(); });

    $("#btn-zz-share-location").click(function() {
        if(!currentZZChat) { mostrarNotificacao('error','Só em chat privado.'); return; }
        $.post('https://pacheco_phone/shareLocationZZ', JSON.stringify({number:currentZZChat}), function() { mostrarNotificacao('success','Localização partilhada!'); });
    });

    $("#btn-voltar-zz").click(function() { $("#zz-chat-view").hide(); $("#zz-list-view").show(); currentZZChat = null; currentZZGroupId = null; });

    $("#btn-new-zz").click(function() {
        $("#modal-nova-zz").show();
        $.post('https://pacheco_phone/getContacts', JSON.stringify({}), function(contacts) {
            let d = $("#nova-zz-contacto"); d.empty().append('<option value="">Selecionar...</option>');
            if(contacts) contacts.forEach(c => { d.append(`<option value="${c.number}">${c.name}</option>`); });
        });
    });
    $("#btn-cancelar-zz").click(function() { $("#modal-nova-zz").hide(); });
    $("#btn-iniciar-zz").click(function() { let finalNum = $("#nova-zz-contacto").val() || $("#nova-zz-numero").val().trim(); if(finalNum) { $("#modal-nova-zz").hide(); window.abrirChatZZ(finalNum); } });

    // Criar grupo ZipZap
    $("#btn-criar-grupo-zz").click(function() { $("#modal-criar-grupo-zz").show(); carregarProximosZZ(); });
    $("#btn-cancelar-grupo-zz").click(function() { $("#modal-criar-grupo-zz").hide(); });

    function carregarProximosZZ() {
        $.post('https://pacheco_phone/getNearbyPlayersZZ', JSON.stringify({}), function(players) {
            let container = $("#zz-grupo-membros"); container.empty();
            if(!players || players.length === 0) { container.append('<p style="color:var(--text-muted);font-size:13px;">Ninguém por perto.</p>'); return; }
            players.forEach(p => { container.append(`<label style="display:flex;align-items:center;gap:8px;margin-bottom:8px;cursor:pointer;"><input type="checkbox" class="zz-membro-check" value="${p.id}" style="width:16px;height:16px;"> ${p.name}</label>`); });
        });
    }

    $("#btn-confirmar-grupo-zz").click(function() {
        let nome = $("#zz-grupo-nome").val().trim();
        if(!nome) { mostrarNotificacao('error','Dá um nome ao grupo!'); return; }
        let membros = [];
        $(".zz-membro-check:checked").each(function() { membros.push($(this).val()); });
        $.post('https://pacheco_phone/createZZGroup', JSON.stringify({name:nome, members:membros}), function(res) {
            if(res.success) { mostrarNotificacao('success','Grupo criado!'); $("#modal-criar-grupo-zz").hide(); $("#zz-grupo-nome").val(""); carregarZZGrupos(); }
            else mostrarNotificacao('error','Erro ao criar grupo.');
        });
    });

    // ==========================================
    // FOTOGRAM
    // ==========================================
    $("#btn-fotogram-login").click(function() {
        let u = $("#fg-login-user").val().trim(), p = $("#fg-login-pass").val().trim();
        if(!u||!p) return;
        $.post('https://pacheco_phone/fotogramLogin', JSON.stringify({username:u, password:p}), function(d) {
            if(d.success) { fotogramAccount = d.data; $("#fotogram-auth-view").hide(); $("#fotogram-feed-view").show(); carregarFeedFotogram(); }
            else mostrarNotificacao('error', d.message || 'Credenciais inválidas.');
        });
    });

    $("#btn-fotogram-register").click(function() {
        let u = $("#fg-reg-user").val().trim(), p = $("#fg-reg-pass").val().trim();
        if(!u||!p) return;
        $.post('https://pacheco_phone/fotogramRegister', JSON.stringify({username:u, password:p}), function(d) {
            if(d.success) { mostrarNotificacao('success','Conta criada! Faz login.'); $("#fg-reg-user,#fg-reg-pass").val(""); $("#fotogram-reg-form").hide(); $("#fotogram-login-form").show(); }
            else mostrarNotificacao('error', d.message);
        });
    });

    function carregarFeedFotogram() {
        $.post('https://pacheco_phone/getFotogramFeed', JSON.stringify({}), function(posts) {
            $("#fotogram-feed-list").empty();
            if(!posts || posts.length === 0) { $("#fotogram-feed-list").append("<p style='text-align:center;color:#8899a6;margin-top:40px;'>Sem publicações ainda.</p>"); return; }
            posts.forEach(p => {
                let timeStr = new Date(p.timestamp).toLocaleString('pt-PT',{day:'2-digit',month:'short',hour:'2-digit',minute:'2-digit'});
                $("#fotogram-feed-list").append(`
                    <div class="fotogram-post" data-id="${p.id}">
                        <div class="fg-post-header">
                            <img src="${p.avatar}" class="fg-avatar">
                            <div><h4 class="fg-username">@${p.username}</h4><span class="fg-time">${timeStr}</span></div>
                        </div>
                        <img src="${p.image_url}" class="fg-post-image" onerror="this.style.display='none'">
                        <div class="fg-post-actions">
                            <button class="fg-action-btn btn-fg-like" data-id="${p.id}"><i class="fas fa-heart"></i> ${p.likes}</button>
                            <button class="fg-action-btn btn-fg-comment" data-id="${p.id}"><i class="fas fa-comment"></i> Comentar</button>
                        </div>
                        ${p.caption ? `<p class="fg-caption"><strong>@${p.username}</strong> ${p.caption}</p>` : ''}
                    </div>
                `);
            });
        });
    }

    $(document).on('click', '.btn-fg-like', function() {
        let id = $(this).data("id"); let btn = $(this);
        $.post('https://pacheco_phone/likeFotogram', JSON.stringify({postId:id}), function() {
            let currentLikes = parseInt(btn.text().trim().split(' ')[1]) || 0;
            btn.html(`<i class="fas fa-heart" style="color:#f43f5e;"></i> ${currentLikes+1}`);
        });
    });

    $(document).on('click', '.btn-fg-comment', function() {
        currentCommentPostId = $(this).data("id");
        $("#fotogram-feed-view").hide(); $("#fotogram-comments-view").show();
        $.post('https://pacheco_phone/getFotogramComments', JSON.stringify({postId:currentCommentPostId}), function(comments) {
            $("#fg-comments-list").empty();
            if(!comments || comments.length === 0) { $("#fg-comments-list").append("<p style='color:#8899a6;text-align:center;margin-top:20px;'>Sem comentários.</p>"); return; }
            comments.forEach(c => { $("#fg-comments-list").append(`<div class="fg-comment"><strong style="color:var(--accent);">@${c.username}</strong> ${c.comment}</div>`); });
        });
    });

    $("#btn-enviar-fg-comment").click(function() {
        let txt = $("#fg-comment-input").val().trim();
        if(!txt || !fotogramAccount) return;
        $.post('https://pacheco_phone/postFotogramComment', JSON.stringify({postId:currentCommentPostId, username:fotogramAccount.username, comment:txt}));
        $("#fg-comments-list").append(`<div class="fg-comment"><strong style="color:var(--accent);">@${fotogramAccount.username}</strong> ${txt}</div>`);
        $("#fg-comment-input").val("");
    });

    $("#btn-fg-novo-post").click(function() { $("#fotogram-feed-view").hide(); $("#fotogram-compose-view").show(); $("#fg-compose-url, #fg-compose-caption").val(""); });
    $("#btn-fg-cancel-compose").click(function() { $("#fotogram-compose-view").hide(); $("#fotogram-feed-view").show(); });

    // Câmara do jogo
    $("#btn-fg-abrir-camara").click(function() {
        $.post('https://pacheco_phone/tirarFoto', JSON.stringify({}), function() {});
    });

    // Clique no botão de tirar foto (Círculo Branco)
    $(document).on('click', '#btn-fg-capturar', function(e) {
        e.preventDefault();
        
        // Faz o pedido ao Client Lua para tirar o print
        $.post('https://Pacheco_phone/capturarFoto', JSON.stringify({}), function(data) {
            if (data && data.url) {
                // Injeta o link da foto na tua aba do Fotogram (ajusta os IDs se necessário)
                // Geralmente guarda-se num input ou mostra-se numa tag <img>
                $("#fotogram-url-input").val(data.url); 
                $("#fotogram-preview-img").attr("src", data.url).show();
                
                // Se o teu HTML tiver um input de texto para a imagem, podes usar:
                // $("input[placeholder='https://fivem.net/logo.png']").val(data.url);
            }
        });
    });

    // Clique no botão de fechar (O 'X')
    $(document).on('click', '#btn-fg-cancelar-camara', function(e) {
        e.preventDefault();
        // Fecha a câmara no GTA
        $.post('https://Pacheco_phone/cancelarFoto', JSON.stringify({}));
    });

    $("#btn-fg-publicar").click(function() {
        let imageUrl = $("#fg-compose-url").val().trim();
        let caption = $("#fg-compose-caption").val().trim();
        if(!imageUrl) { mostrarNotificacao('error','Adiciona uma imagem!'); return; }
        if(!fotogramAccount) { mostrarNotificacao('error','Não estás autenticado.'); return; }
        $.post('https://pacheco_phone/postFotogram', JSON.stringify({username:fotogramAccount.username, avatar:fotogramAccount.avatar, imageUrl, caption}), function(res) {
            if(res.success) { mostrarNotificacao('success','Publicado!'); $("#fotogram-compose-view").hide(); $("#fotogram-feed-view").show(); carregarFeedFotogram(); }
            else mostrarNotificacao('error', res.message);
        });
    });

    // ==========================================
    // PÁGINAS AMARELAS
    // ==========================================
    function carregarPaginasAmarelas(category) {
        let cat = category || "all";
        $.post('https://pacheco_phone/getPaginasAmarelas', JSON.stringify({category:cat}), function(empresas) {
            $("#pa-lista").empty();
            if(!empresas || empresas.length === 0) { $("#pa-lista").append("<p style='text-align:center;color:var(--text-muted);margin-top:30px;'>Sem empresas nesta categoria.</p>"); return; }
            empresas.forEach(e => {
                $("#pa-lista").append(`
                    <div class="car-card-modern" style="margin:10px 15px;">
                        <div class="car-header-m">
                            <h4>${e.business_name}</h4>
                            <span class="status-badge bg-blue">${e.category || e.job}</span>
                        </div>
                        ${e.description ? `<p style="font-size:13px;color:var(--text-muted);margin:5px 0;">${e.description}</p>` : ''}
                        <div style="display:flex;gap:10px;margin-top:10px;flex-wrap:wrap;">
                            ${e.phone ? `<button class="btn-outline" style="flex:1;padding:8px;" onclick="window.tentarLigar('${e.phone}','${e.business_name}')"><i class="fas fa-phone"></i> ${e.phone}</button>` : ''}
                            ${e.location ? `<span style="flex:1;text-align:center;padding:8px;background:var(--bg-card);border-radius:8px;font-size:12px;color:var(--text-muted);"><i class="fas fa-map-marker-alt"></i> ${e.location}</span>` : ''}
                        </div>
                    </div>
                `);
            });
        });
    }

    // Filtros categoria
    $(document).on('click', '.pa-cat-btn', function() {
        $(".pa-cat-btn").removeClass("active"); $(this).addClass("active");
        carregarPaginasAmarelas($(this).data("cat"));
    });

    // Tab registar/gerir empresa
    $(document).on('click', '.pa-nav-btn', function() {
        $(".pa-nav-btn").removeClass("active"); $(this).addClass("active");
        $(".pa-tab").hide();
        let tab = $(this).data("tab");
        $("#pa-tab-" + tab).fadeIn(150);
        if(tab === "minha") { carregarMinhaEmpresa(); }
    });

    function carregarMinhaEmpresa() {
        $.post('https://pacheco_phone/getMinhaEmpresa', JSON.stringify({}), function(empresa) {
            if(empresa) {
                $("#pa-empresa-nome").val(empresa.business_name || "");
                $("#pa-empresa-desc").val(empresa.description || "");
                $("#pa-empresa-tel").val(empresa.phone || "");
                $("#pa-empresa-cat").val(empresa.category || "");
                $("#pa-empresa-loc").val(empresa.location || "");
                $("#btn-registar-empresa").text("Atualizar Empresa");
            } else { $("#btn-registar-empresa").text("Registar Empresa"); }
        });
    }

    $("#btn-registar-empresa").click(function() {
        let nome = $("#pa-empresa-nome").val().trim();
        let desc = $("#pa-empresa-desc").val().trim();
        let tel = $("#pa-empresa-tel").val().trim();
        let cat = $("#pa-empresa-cat").val().trim();
        let loc = $("#pa-empresa-loc").val().trim();
        if(!nome) { mostrarNotificacao('error','Nome da empresa obrigatório!'); return; }
        $.post('https://pacheco_phone/registarEmpresa', JSON.stringify({businessName:nome, description:desc, phone:tel, category:cat, location:loc}), function(res) {
            if(res.success) mostrarNotificacao('success', res.message);
            else mostrarNotificacao('error', res.message);
        });
    });

    // ==========================================
    // TWITTER
    // ==========================================
    $("#btn-tw-login").click(function() { let u = $("#tw-login-user").val().trim(), p = $("#tw-login-pass").val().trim(); if(!u.startsWith('@')) u = '@'+u; $.post('https://pacheco_phone/twitterLogin', JSON.stringify({username:u,password:p}), function(d) { if(d.success) { currentTwitterAccount = d.data; $("#tw-header-avatar").attr("src",d.data.avatar); $("#twitter-auth-view").hide(); $("#twitter-topics-view").show(); carregarTopicosTwitter(); } else mostrarNotificacao("error","Credenciais inválidas!"); }); });
    $("#btn-tw-register").click(function() { let u = $("#tw-reg-user").val().trim(), p = $("#tw-reg-pass").val().trim(); if(!u.startsWith('@')) u = '@'+u; $.post('https://pacheco_phone/twitterRegister', JSON.stringify({username:u,password:p}), function(d) { if(d.success) { mostrarNotificacao("success","Conta Criada!"); $("#twitter-reg-form").hide(); $("#twitter-login-form").show(); } else mostrarNotificacao("error","Erro ao registar!"); }); });
    function carregarTopicosTwitter() { $.post('https://pacheco_phone/getTwitterTopics', JSON.stringify({}), function(topics) { $("#twitter-topics-list").empty(); if(topics) topics.forEach(t => { $("#twitter-topics-list").append(`<div class="topic-item" onclick="window.abrirTopicoTwitter('${t.topic}')"><h4>#${t.topic}</h4><span><i class="fas fa-chevron-right" style="color:var(--text-muted);"></i></span></div>`); }); }); }
    $("#btn-tw-open-topic").click(function() { let txt = $("#tw-topic-input").val().trim().replace('#',''); if(txt) { $("#tw-topic-input").val(""); window.abrirTopicoTwitter(txt); } });
    window.abrirTopicoTwitter = function(name) { currentTwitterTopic = name; $("#tw-current-topic-name").text("#"+name); $("#twitter-topics-view").hide(); $("#twitter-feed-view").show(); carregarFeedTwitter(name); };
    function carregarFeedTwitter(name) { $.post('https://pacheco_phone/getTweets', JSON.stringify({topic:name}), function(tweets) { $("#twitter-lista").empty(); if(tweets) tweets.forEach(t => { $("#twitter-lista").append(`<div class="tweet-card"><img src="${t.avatar}" class="tweet-avatar"><div class="tweet-content"><h4 class="tweet-author">${t.username}</h4><p class="tweet-text">${t.content}</p></div></div>`); }); }); }
    $("#btn-tw-voltar-topics").click(function() { $("#twitter-feed-view").hide(); $("#twitter-topics-view").show(); currentTwitterTopic = null; });
    $("#btn-show-compose").click(function() { $("#twitter-feed-view").hide(); $("#twitter-compose-view").show(); });
    $("#btn-cancel-compose").click(function() { $("#twitter-compose-view").hide(); $("#twitter-feed-view").show(); });
    $("#btn-enviar-tweet").click(function() { let txt = $("#tw-compose-text").val().trim(); if(!txt) return; $.post('https://pacheco_phone/postTweet', JSON.stringify({username:currentTwitterAccount.username,avatar:currentTwitterAccount.avatar,content:txt,topic:currentTwitterTopic})); $("#tw-compose-text").val(""); $("#twitter-compose-view").hide(); $("#twitter-feed-view").show(); });
    $("#tw-header-avatar").click(function() { $("#twitter-topics-view").hide(); $("#app-twitter-avatar").show(); appAberta = "twitter-avatar"; });
    $("#btn-tw-avatar-voltar").click(function() { $("#app-twitter-avatar").hide(); $("#twitter-topics-view").show(); appAberta = "twitter"; });
    $(".tw-avatar-item").click(function() { let url = $(this).data("url"); $.post('https://pacheco_phone/changeTwitterAvatar', JSON.stringify({username:currentTwitterAccount.username,avatar:url}), function(d) { if(d.success) { currentTwitterAccount.avatar = url; $("#tw-header-avatar").attr("src",url); $("#app-twitter-avatar").hide(); $("#twitter-topics-view").show(); appAberta="twitter"; mostrarNotificacao('success','Avatar Atualizado'); } }); });

    // ==========================================
    // DARK WEB (melhorado com listagens)
    // ==========================================
    function carregarTopicosBM() { $.post('https://pacheco_phone/getBMTopics', JSON.stringify({}), function(topics) { $("#bm-topics-list").empty(); if(topics) topics.forEach(t => { $("#bm-topics-list").append(`<div class="topic-item" style="border-color:var(--border);" onclick="window.abrirTopicoBM('${t.topic}')"><h4 style="color:var(--danger);font-family:monospace;">> SESSION: ${t.topic}</h4></div>`); }); }); }
    $("#btn-bm-open-topic").click(function() { let txt = $("#bm-topic-input").val().trim(); if(txt) { $("#bm-topic-input").val(""); window.abrirTopicoBM(txt); } });
    window.abrirTopicoBM = function(name) {
        currentBMTopic = name; $("#bm-current-topic-name").text(name.toUpperCase());
        $("#bm-topics-view").hide(); $("#bm-chat-view").show();
        carregarDWListings(name);
    };

    function carregarDWListings(topic) {
        $.post('https://pacheco_phone/getDWListings', JSON.stringify({topic}), function(listings) {
            let box = $("#bm-messages"); box.empty();
            if(!listings || listings.length === 0) { box.append(`<div class="bm-msg"><span>SISTEMA:</span> Sem publicações nesta sala.</div>`); return; }
            listings.forEach(l => {
                let priceStr = l.price > 0 ? `<span style="color:#10b981;font-weight:bold;"> | 💰 ${l.price}€</span>` : '';
                let typeBadge = l.type === 'venda' ? '<span style="color:var(--danger);">[VENDA]</span>' : l.type === 'contrato' ? '<span style="color:#f59e0b;">[CONTRATO]</span>' : '<span style="color:#8899a6;">[MSG]</span>';
                box.append(`<div class="bm-msg">${typeBadge}${priceStr}<br><span style="color:#ccc;">${l.title ? '<strong>'+l.title+'</strong><br>' : ''}${l.message}</span></div>`);
            });
            box.scrollTop(box[0].scrollHeight);
        });
    }

    $("#btn-dw-nova-listagem").click(function() { $("#modal-dw-listagem").show(); });
    $("#btn-dw-cancel-listagem").click(function() { $("#modal-dw-listagem").hide(); });
    $("#btn-dw-publicar-listagem").click(function() {
        let title = $("#dw-listing-title").val().trim();
        let msg = $("#dw-listing-msg").val().trim();
        let price = $("#dw-listing-price").val() || 0;
        let type = $("#dw-listing-type").val();
        if(!msg) { mostrarNotificacao('error','Escreve uma mensagem.'); return; }
        $.post('https://pacheco_phone/postDWListing', JSON.stringify({topic:currentBMTopic, title, message:msg, price, type}), function(res) {
            if(res.success) { mostrarNotificacao('success','Publicado.'); $("#modal-dw-listagem").hide(); $("#dw-listing-title,#dw-listing-msg,#dw-listing-price").val(""); carregarDWListings(currentBMTopic); }
            else mostrarNotificacao('error', res.message);
        });
    });

    // Chat rápido DW (mantém o original)
    $("#btn-enviar-bm").click(function() { let txt = $("#bm-input-texto").val().trim(); if(!txt) return; $.post('https://pacheco_phone/postBlackmarket', JSON.stringify({message:txt,topic:currentBMTopic})); $("#bm-input-texto").val(""); });
    $("#bm-input-texto").keypress(function(e) { if(e.which==13) $("#btn-enviar-bm").click(); });
    $("#btn-bm-voltar-topics").click(function() { $("#bm-chat-view").hide(); $("#bm-topics-view").show(); currentBMTopic = null; });

    // ==========================================
    // BANCO
    // ==========================================
    $(".btn-banco-action").click(function() {
        let t = $(this).data("target"); $("#banco-home-content").hide(); $("#btn-banco-voltar-home").hide();
        if(t === "historico") { $.post('https://pacheco_phone/getTransacoes', JSON.stringify({}), function(trans) { $("#lista-historico").empty(); if(trans) trans.forEach(x => { let isPos = (x.type==='deposito'||x.type==='transferencia_recebida'); $("#lista-historico").append(`<div class="setting-item"><span style="font-size:12px;color:var(--text-muted);">${x.type}</span><span style="color:${isPos?'var(--success)':'var(--danger)'};font-weight:bold;">${isPos?'+':'-'}${x.amount}€</span></div>`); }); $("#banco-historico-content").show(); }); }
        else { $.post('https://pacheco_phone/getCreditos', JSON.stringify({}), function(cred) { $("#lista-creditos").empty(); if(cred) cred.forEach(c => { $("#lista-creditos").append(`<div class="setting-item"><span style="font-size:12px;">Dívida: ${c.amount}€</span><span style="color:var(--danger);font-weight:bold;">${c.remaining_amount}€</span></div>`); }); $("#banco-creditos-content").show(); }); }
        $("#btn-banco-voltar").show();
    });
    $("#btn-banco-voltar").click(function() { $("#banco-historico-content,#banco-creditos-content").hide(); $("#banco-home-content").show(); $(this).hide(); $("#btn-banco-voltar-home").show(); });
    $("#btn-transferir").click(function() { let iban = $("#trans-iban").val().trim(); let val = $("#trans-valor").val(); if(!iban||!val) return; let btn = $(this); btn.prop('disabled',true); $.post('https://pacheco_phone/fazerTransferencia', JSON.stringify({iban,amount:val}), function(data) { btn.prop('disabled',false); if(data.success) { mostrarNotificacao('success',data.message); $("#trans-iban,#trans-valor").val(""); $.post('https://pacheco_phone/getBankInfo', JSON.stringify({}), function(d) { if(d) $("#banco-saldo").text(d.saldo+"€"); }); } else mostrarNotificacao('error',data.message); }); });
});
