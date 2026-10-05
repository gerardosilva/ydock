import Foundation

/// Lightweight in-code localization (no .lproj needed, so it works with plain `swift build`).
/// Add a language: add it to `supported`, `languageNames`, and a column in every `table` row.
enum Localizer {
    static let supported = ["en", "es", "fr", "de", "pt", "it", "ja", "zh"]
    static let languageNames: [(code: String, name: String)] = [
        ("en", "English"), ("es", "Español"), ("fr", "Français"), ("de", "Deutsch"),
        ("pt", "Português"), ("it", "Italiano"), ("ja", "日本語"), ("zh", "中文"),
    ]

    /// Resolved language code currently in use ("en", "es", …).
    static var current = "en"

    /// "system" follows the macOS preferred languages; falls back to English.
    static func update(preference: String) {
        if supported.contains(preference) { current = preference; return }
        for l in Locale.preferredLanguages {
            let code = String(l.prefix(2))
            if supported.contains(code) { current = code; return }
        }
        current = "en"
    }

    static var locale: Locale { Locale(identifier: current == "zh" ? "zh-Hans" : current) }

    // key: [en, es, fr, de, pt, it, ja, zh]
    private static let table: [String: [String]] = [
        "menu.position":   ["Position", "Posición", "Position", "Position", "Posição", "Posizione", "位置", "位置"],
        "pos.bottom":      ["Bottom", "Abajo", "Bas", "Unten", "Embaixo", "In basso", "下", "底部"],
        "pos.above":       ["Above the system Dock", "Arriba del Dock de Apple", "Au-dessus du Dock Apple",
                            "Über dem Apple-Dock", "Acima do Dock da Apple", "Sopra il Dock di Apple",
                            "システムDockの上", "系统程序坞上方"],
        "pos.top":         ["Top", "Arriba", "Haut", "Oben", "Em cima", "In alto", "上", "顶部"],
        "pos.left":        ["Left", "Izquierda", "Gauche", "Links", "Esquerda", "Sinistra", "左", "左侧"],
        "pos.right":       ["Right", "Derecha", "Droite", "Rechts", "Direita", "Destra", "右", "右侧"],
        "menu.appearance": ["Appearance", "Apariencia", "Apparence", "Erscheinungsbild", "Aparência", "Aspetto", "外観", "外观"],
        "app.dark":        ["Dark", "Oscuro", "Sombre", "Dunkel", "Escuro", "Scuro", "ダーク", "深色"],
        "app.light":       ["Light", "Claro", "Clair", "Hell", "Claro", "Chiaro", "ライト", "浅色"],
        "app.tinted":      ["Tinted", "Teñido", "Teinté", "Getönt", "Colorido", "Colorato", "色付き", "着色"],
        "menu.tint":       ["Tint color…", "Color del tinte…", "Couleur de teinte…", "Tönungsfarbe …",
                            "Cor do tom…", "Colore della tinta…", "色合いの色…", "着色颜色…"],
        "menu.autohide":   ["Auto-hide", "Ocultar automáticamente", "Masquer automatiquement", "Automatisch ausblenden",
                            "Ocultar automaticamente", "Nascondi automaticamente", "自動的に隠す", "自动隐藏"],
        "menu.login":      ["Open at login", "Abrir al iniciar sesión", "Ouvrir à l’ouverture de session",
                            "Beim Anmelden öffnen", "Abrir ao iniciar sessão", "Apri al login", "ログイン時に開く", "登录时打开"],
        "menu.language":   ["Language", "Idioma", "Langue", "Sprache", "Idioma", "Lingua", "言語", "语言"],
        "lang.system":     ["System", "Sistema", "Système", "System", "Sistema", "Sistema", "システム", "系统"],
        "menu.addwidget":  ["Add widget", "Agregar widget", "Ajouter un widget", "Widget hinzufügen",
                            "Adicionar widget", "Aggiungi widget", "ウィジェットを追加", "添加小组件"],
        "menu.adddivider": ["Add separator", "Agregar separador", "Ajouter un séparateur", "Trennlinie hinzufügen",
                            "Adicionar separador", "Aggiungi separatore", "区切りを追加", "添加分隔线"],
        "menu.openconfig": ["Open configuration", "Abrir configuración", "Ouvrir la configuration", "Konfiguration öffnen",
                            "Abrir configuração", "Apri configurazione", "設定を開く", "打开配置"],
        "menu.reload":     ["Reload configuration", "Recargar configuración", "Recharger la configuration",
                            "Konfiguration neu laden", "Recarregar configuração", "Ricarica configurazione",
                            "設定を再読み込み", "重新载入配置"],
        "menu.quit":       ["Quit yDock", "Salir de yDock", "Quitter yDock", "yDock beenden",
                            "Sair do yDock", "Esci da yDock", "yDockを終了", "退出 yDock"],
        "item.reveal":     ["Show in Finder", "Mostrar en Finder", "Afficher dans le Finder", "Im Finder anzeigen",
                            "Mostrar no Finder", "Mostra nel Finder", "Finderで表示", "在访达中显示"],
        "item.remove":     ["Remove from dock", "Quitar del dock", "Retirer du dock", "Aus dem Dock entfernen",
                            "Remover do dock", "Rimuovi dal dock", "Dockから削除", "从程序坞移除"],
        "widget.clock":    ["Clock", "Reloj", "Horloge", "Uhr", "Relógio", "Orologio", "時計", "时钟"],
        "widget.battery":  ["Battery", "Batería", "Batterie", "Batterie", "Bateria", "Batteria", "バッテリー", "电池"],
        "widget.cpu":      ["CPU", "CPU", "CPU", "CPU", "CPU", "CPU", "CPU", "CPU"],
        "widget.memory":   ["Memory", "Memoria", "Mémoire", "Speicher", "Memória", "Memoria", "メモリ", "内存"],
        "widget.weather":  ["Weather", "Clima", "Météo", "Wetter", "Clima", "Meteo", "天気", "天气"],
        "widget.calendar": ["Calendar", "Calendario", "Calendrier", "Kalender", "Calendário", "Calendario", "カレンダー", "日历"],
        "widget.countdown": ["Countdown", "Cuenta regresiva", "Compte à rebours", "Countdown", "Contagem regressiva", "Conto alla rovescia", "カウントダウン", "倒计时"],
        "widget.network": ["Network", "Red", "Réseau", "Netzwerk", "Rede", "Rete", "ネットワーク", "网络"],
        "widget.dropdown": ["Dropdown", "Menú desplegable", "Menu déroulant", "Dropdown", "Menu suspenso", "Menu a tendina", "ドロップダウン", "下拉菜单"],
        "widget.stickynote": ["Sticky note", "Nota adhesiva", "Note adhésive", "Haftnotiz", "Nota adesiva", "Nota adesiva", "付箋", "便笺"],
        "widget.activity": ["System activity", "Actividad del sistema", "Activité système", "Systemaktivität", "Atividade do sistema", "Attività di sistema", "システムアクティビティ", "系统活动"],
        "widget.nowplaying": ["Now playing", "Reproduciendo", "Lecture en cours", "Aktuelle Wiedergabe", "Reproduzindo", "In riproduzione", "再生中", "正在播放"],
        "widget.airdrop": ["AirDrop", "AirDrop", "AirDrop", "AirDrop", "AirDrop", "AirDrop", "AirDrop", "AirDrop"],
        "widget.shortcut": ["Shortcut", "Atajo", "Raccourci", "Kurzbefehl", "Atalho", "Comando rapido", "ショートカット", "快捷指令"],
        "menu.addshortcut": ["Add shortcut", "Agregar atajo", "Ajouter un raccourci", "Kurzbefehl hinzufügen", "Adicionar atalho", "Aggiungi comando rapido", "ショートカットを追加", "添加快捷指令"],
        "menu.dropdownadd": ["Add to dropdown…", "Agregar al menú…", "Ajouter au menu…", "Zum Dropdown hinzufügen …", "Adicionar ao menu…", "Aggiungi al menu…", "ドロップダウンに追加…", "添加到下拉菜单…"],
        "sticky.placeholder": ["Click to write…", "Haz clic para escribir…", "Cliquez pour écrire…", "Zum Schreiben klicken…", "Clique para escrever…", "Fai clic per scrivere…", "クリックして入力…", "点击输入…"],
        "np.nothing": ["Nothing playing", "Nada en reproducción", "Aucune lecture", "Keine Wiedergabe", "Nada tocando", "Nessuna riproduzione", "再生なし", "未在播放"],
        "cal.noevents": ["No events", "Sin eventos", "Aucun événement", "Keine Termine", "Sem eventos", "Nessun evento", "予定なし", "无日程"],
        "cal.noaccess": ["No access", "Sin acceso", "Pas d’accès", "Kein Zugriff", "Sem acesso", "Nessun accesso", "アクセスなし", "无权限"],
        "airdrop.drop": ["Drop files", "Suelta archivos", "Déposez des fichiers", "Dateien ablegen", "Solte arquivos", "Rilascia file", "ファイルをドロップ", "拖放文件"],
        "cd.days": ["days", "días", "jours", "Tage", "dias", "giorni", "日", "天"],
        "widget.worldclock": ["World clock", "Reloj mundial", "Horloge mondiale", "Weltzeituhr", "Relógio mundial", "Orologio mondiale", "ワールドクロック", "世界时钟"],
        "widget.reminders": ["Reminders", "Recordatorios", "Rappels", "Erinnerungen", "Lembretes", "Promemoria", "リマインダー", "提醒事项"],
        "widget.stock": ["Stocks", "Bolsa", "Bourse", "Aktien", "Ações", "Azioni", "株価", "股票"],
        "widget.stopwatch": ["Stopwatch", "Cronómetro", "Chronomètre", "Stoppuhr", "Cronômetro", "Cronometro", "ストップウォッチ", "秒表"],
        "widget.focustimer": ["Focus timer", "Temporizador de enfoque", "Minuteur de concentration", "Fokus-Timer", "Temporizador de foco", "Timer di concentrazione", "集中タイマー", "专注计时器"],
        "widget.timeprogress": ["Time progress", "Progreso del tiempo", "Progression du temps", "Zeitfortschritt", "Progresso do tempo", "Avanzamento del tempo", "時間の進捗", "时间进度"],
        "detail.memused": ["Memory used", "Memoria usada", "Mémoire utilisée", "Genutzter Speicher", "Memória usada", "Memoria usata", "使用中のメモリ", "已用内存"],
        "battery.charging": ["Charging", "Cargando", "En charge", "Lädt", "Carregando", "In carica", "充電中", "正在充电"],
        "battery.onbattery": ["On battery", "Con batería", "Sur batterie", "Batteriebetrieb", "Na bateria", "A batteria", "バッテリー駆動", "使用电池"],
        "battery.remaining": ["Time remaining", "Tiempo restante", "Temps restant", "Verbleibende Zeit", "Tempo restante", "Tempo rimanente", "残り時間", "剩余时间"],
        "weather.feels": ["Feels like", "Sensación térmica", "Ressenti", "Gefühlt", "Sensação térmica", "Percepita", "体感温度", "体感温度"],
        "weather.humidity": ["Humidity", "Humedad", "Humidité", "Luftfeuchtigkeit", "Umidade", "Umidità", "湿度", "湿度"],
        "weather.wind": ["Wind", "Viento", "Vent", "Wind", "Vento", "Vento", "風", "风"],
        "weather.range": ["High / Low", "Máx / Mín", "Max / Min", "Hoch / Tief", "Máx / Mín", "Max / Min", "最高 / 最低", "最高 / 最低"],
        "cal.open": ["Open Calendar", "Abrir Calendario", "Ouvrir Calendrier", "Kalender öffnen", "Abrir Calendário", "Apri Calendario", "カレンダーを開く", "打开日历"],
        "cd.target": ["Date", "Fecha", "Date", "Datum", "Data", "Data", "日付", "日期"],
        "rem.empty": ["No reminders", "Sin recordatorios", "Aucun rappel", "Keine Erinnerungen", "Sem lembretes", "Nessun promemoria", "リマインダーなし", "无提醒事项"],
        "net.down": ["Download", "Descarga", "Téléchargement", "Download", "Download", "Download", "ダウンロード", "下载"],
        "net.up": ["Upload", "Subida", "Envoi", "Upload", "Upload", "Upload", "アップロード", "上传"],
        "settings.position": ["Dock position", "Posición del dock", "Position du Dock", "Dock-Position", "Posição do dock", "Posizione del Dock", "Dockの位置", "程序坞位置"],
        "menu.settings": ["Dock settings…", "Ajustes del dock…", "Réglages du Dock…", "Dock-Einstellungen …", "Ajustes do dock…", "Impostazioni del Dock…", "Dock設定…", "程序坞设置…"],
        "menu.widgetsettings": ["Widget settings…", "Ajustes del widget…", "Réglages du widget…", "Widget-Einstellungen …", "Ajustes do widget…", "Impostazioni widget…", "ウィジェット設定…", "小组件设置…"],
        "menu.profiles": ["Profiles", "Perfiles", "Profils", "Profile", "Perfis", "Profili", "プロファイル", "配置"],
        "profile.new": ["New profile…", "Nuevo perfil…", "Nouveau profil…", "Neues Profil …", "Novo perfil…", "Nuovo profilo…", "新規プロファイル…", "新建配置…"],
        "profile.rename": ["Rename…", "Renombrar…", "Renommer…", "Umbenennen …", "Renomear…", "Rinomina…", "名前を変更…", "重命名…"],
        "profile.delete": ["Delete profile", "Eliminar perfil", "Supprimer le profil", "Profil löschen", "Excluir perfil", "Elimina profilo", "プロファイルを削除", "删除配置"],
        "profile.name": ["Profile name", "Nombre del perfil", "Nom du profil", "Profilname", "Nome do perfil", "Nome del profilo", "プロファイル名", "配置名称"],
        "common.ok": ["OK", "Aceptar", "OK", "OK", "OK", "OK", "OK", "好"],
        "common.cancel": ["Cancel", "Cancelar", "Annuler", "Abbrechen", "Cancelar", "Annulla", "キャンセル", "取消"],
        "gallery.title": ["Add Widget", "Agregar widget", "Ajouter un widget", "Widget hinzufügen", "Adicionar widget", "Aggiungi widget", "ウィジェットを追加", "添加小组件"],
        "gallery.search": ["Search widgets", "Buscar widgets", "Rechercher des widgets", "Widgets suchen", "Buscar widgets", "Cerca widget", "ウィジェットを検索", "搜索小组件"],
        "cat.all": ["All Widgets", "Todos los widgets", "Tous les widgets", "Alle Widgets", "Todos os widgets", "Tutti i widget", "すべてのウィジェット", "全部小组件"],
        "cat.clocks": ["Clocks", "Relojes", "Horloges", "Uhren", "Relógios", "Orologi", "時計", "时钟"],
        "cat.calendar": ["Calendar", "Calendario", "Calendrier", "Kalender", "Calendário", "Calendario", "カレンダー", "日历"],
        "cat.reminders": ["Reminders", "Recordatorios", "Rappels", "Erinnerungen", "Lembretes", "Promemoria", "リマインダー", "提醒事项"],
        "cat.notes": ["Sticky Notes", "Notas adhesivas", "Notes adhésives", "Haftnotizen", "Notas adesivas", "Note adesive", "付箋", "便笺"],
        "cat.media": ["Media", "Multimedia", "Médias", "Medien", "Mídia", "Media", "メディア", "媒体"],
        "cat.system": ["System", "Sistema", "Système", "System", "Sistema", "Sistema", "システム", "系统"],
        "cat.weather": ["Weather", "Clima", "Météo", "Wetter", "Clima", "Meteo", "天気", "天气"],
        "cat.stocks": ["Stocks", "Bolsa", "Bourse", "Aktien", "Ações", "Azioni", "株価", "股票"],
        "cat.tools": ["Tools", "Herramientas", "Outils", "Werkzeuge", "Ferramentas", "Strumenti", "ツール", "工具"],
        "sw.start": ["Start", "Iniciar", "Démarrer", "Start", "Iniciar", "Avvia", "開始", "开始"],
        "sw.pause": ["Pause", "Pausar", "Pause", "Pause", "Pausar", "Pausa", "一時停止", "暂停"],
        "sw.reset": ["Reset", "Reiniciar", "Réinitialiser", "Zurücksetzen", "Reiniciar", "Azzera", "リセット", "重置"],
        "focus.work": ["Focus", "Enfoque", "Concentration", "Fokus", "Foco", "Concentrazione", "集中", "专注"],
        "focus.break": ["Break", "Descanso", "Pause", "Pause", "Pausa", "Pausa", "休憩", "休息"],
        "gallery.added": ["Added", "Agregado", "Ajouté", "Hinzugefügt", "Adicionado", "Aggiunto", "追加しました", "已添加"],
        "settings.size": ["Size","Tamaño","Taille","Größe","Tamanho","Dimensione","サイズ","大小"],
        "widget.alarm": ["Alarm", "Alarma", "Alarme", "Wecker", "Alarme", "Sveglia", "アラーム", "闹钟"],
        "alarm.set": ["Set a time", "Configura una hora", "Définir une heure", "Zeit festlegen", "Definir horário", "Imposta un orario", "時刻を設定", "设置时间"],
        "alarm.enabled": ["Alarm on", "Alarma activada", "Alarme activée", "Wecker an", "Alarme ativado", "Sveglia attiva", "アラームオン", "闹钟已开启"],
        "alarm.repeat": ["Repeat", "Repetir", "Répéter", "Wiederholen", "Repetir", "Ripeti", "繰り返し", "重复"],
        "alarm.daily": ["Every day", "Todos los días", "Tous les jours", "Täglich", "Todos os dias", "Ogni giorno", "毎日", "每天"],
        "alarm.weekdays": ["Weekdays", "Entre semana", "Jours ouvrés", "Werktage", "Dias úteis", "Giorni feriali", "平日", "工作日"],
        "alarm.once": ["Once", "Una vez", "Une fois", "Einmal", "Uma vez", "Una volta", "1回のみ", "仅一次"],
        "alarm.sound": ["Sound", "Sonido", "Son", "Ton", "Som", "Suono", "サウンド", "声音"],
        "alarm.label": ["Label", "Etiqueta", "Libellé", "Bezeichnung", "Rótulo", "Etichetta", "ラベル", "标签"],
        "alarm.snooze": ["Snooze 5 min", "Posponer 5 min", "Répéter dans 5 min", "5 Min. Schlummern", "Adiar 5 min", "Posticipa 5 min", "5分後に再通知", "贪睡5分钟"],
        "alarm.stop": ["Stop", "Detener", "Arrêter", "Stopp", "Parar", "Stop", "停止", "停止"],
        "settings.spacing": ["Spacing", "Espaciado", "Espacement", "Abstand", "Espaçamento", "Spaziatura", "間隔", "间距"],
        "settings.corner": ["Corner radius", "Radio de esquinas", "Rayon des coins", "Eckenradius", "Raio dos cantos", "Raggio degli angoli", "角の丸み", "圆角"],
        "settings.behavior": ["Behavior", "Comportamiento", "Comportement", "Verhalten", "Comportamento", "Comportamento", "動作", "行为"],
        "settings.hoverzoom": ["Zoom on hover", "Zoom al pasar el mouse", "Zoom au survol", "Zoom beim Darüberfahren", "Zoom ao passar o mouse", "Zoom al passaggio", "ホバー時に拡大", "悬停放大"],
        "settings.indicators": ["Running indicators", "Indicadores de apps abiertas", "Indicateurs d’apps ouvertes", "Aktiv-Anzeigen", "Indicadores de apps abertos", "Indicatori app aperte", "起動中インジケータ", "运行指示点"],
        "settings.handle": ["Resize handle", "Asa de tamaño", "Poignée de taille", "Größenregler", "Alça de tamanho", "Maniglia di ridimensionamento", "サイズ変更ハンドル", "调整大小手柄"],
        "settings.profilepill": ["Profile switcher", "Selector de perfil", "Sélecteur de profil", "Profilumschalter", "Seletor de perfil", "Selettore profilo", "プロファイル切替", "配置切换器"],
        "settings.general": ["General", "General", "Général", "Allgemein", "Geral", "Generale", "一般", "通用"],
        "widget.notes": ["Notes", "Notas", "Notes", "Notizen", "Notas", "Note", "メモ", "备忘录"],
        "widget.photos": ["Photos", "Fotos", "Photos", "Fotos", "Fotos", "Foto", "写真", "照片"],
        "widget.batteries": ["Batteries", "Baterías", "Batteries", "Batterien", "Baterias", "Batterie", "バッテリー", "电池"],
        "widget.divider": ["Separator", "Separador", "Séparateur", "Trennlinie", "Separador", "Separatore", "区切り", "分隔线"],
        "cat.photos": ["Photos", "Fotos", "Photos", "Fotos", "Fotos", "Foto", "写真", "照片"],
        "notes.open": ["Open Notes", "Abrir Notas", "Ouvrir Notes", "Notizen öffnen", "Abrir Notas", "Apri Note", "メモを開く", "打开备忘录"],
        "batteries.none": ["No devices", "Sin dispositivos", "Aucun appareil", "Keine Geräte", "Sem dispositivos", "Nessun dispositivo", "デバイスなし", "无设备"],
        "handle.hint": ["Drag to resize · double-click to reset", "Arrastra para cambiar el tamaño · doble clic para restablecer", "Glisser pour redimensionner · double-clic pour réinitialiser", "Ziehen zum Ändern der Größe · Doppelklick zum Zurücksetzen", "Arraste para redimensionar · clique duas vezes para redefinir", "Trascina per ridimensionare · doppio clic per ripristinare", "ドラッグでサイズ変更 · ダブルクリックでリセット", "拖动调整大小 · 双击重置"],
        "widget.monthcalendar": ["Month calendar", "Calendario mensual", "Calendrier mensuel", "Monatskalender", "Calendário mensal", "Calendario mensile", "月間カレンダー", "月历"],
        "widget.script":   ["Script", "Script", "Script", "Skript", "Script", "Script", "スクリプト", "脚本"],
    ]

    static func string(_ key: String) -> String {
        guard let row = table[key] else { return key }
        let i = supported.firstIndex(of: current) ?? 0
        return i < row.count ? row[i] : row[0]
    }
}

func L(_ key: String) -> String { Localizer.string(key) }
