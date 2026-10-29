import { resolveAgentChatLocale, type AgentChatLocale } from "./i18n";
const keys = ["group", "main", "members", "conversation", "tools", "terminal", "hide", "unassigned", "observed", "unknown", "unavailable", "missing", "loading", "readOnly", "truncated", "collapsed", "expanded"] as const;
type Key = typeof keys[number];
const copy: Record<AgentChatLocale, string[]> = {
 en: ["Agent workspace", "Main agent", "Members", "Conversation", "Tool activity", "Original terminal", "Hide group", "Unassigned", "Observed run", "Unknown", "Not provided by this session", "Session binding is missing. Reopen from its terminal.", "Loading…", "Read-only record. Reply in the main conversation.", "Showing recent history only.", "Show members", "Hide members"],
 ko: ["에이전트 작업 화면", "메인 에이전트", "멤버", "대화", "도구 실행", "원본 터미널", "그룹 숨기기", "미지정", "관찰된 실행", "알 수 없음", "이 세션에서 제공하지 않습니다", "세션 연결이 없습니다. 해당 터미널에서 다시 여세요.", "불러오는 중…", "읽기 전용 기록입니다. 메인 대화에서 답하세요.", "최근 기록만 표시합니다.", "멤버 보기", "멤버 숨기기"],
 ja: ["エージェント作業画面", "メインエージェント", "メンバー", "会話", "ツール実行", "元のターミナル", "グループを隠す", "未割り当て", "観測された実行", "不明", "このセッションでは利用できません", "セッションの接続がありません。ターミナルから開き直してください。", "読み込み中…", "読み取り専用の記録です。メインの会話で返信してください。", "最近の履歴のみ表示しています。", "メンバーを表示", "メンバーを隠す"],
 de: ["Agentenarbeitsbereich", "Hauptagent", "Mitglieder", "Unterhaltung", "Werkzeugaktivität", "Ursprüngliches Terminal", "Gruppe ausblenden", "Nicht zugeordnet", "Beobachteter Lauf", "Unbekannt", "Von dieser Sitzung nicht bereitgestellt", "Sitzungsbindung fehlt. Vom Terminal erneut öffnen.", "Wird geladen…", "Schreibgeschütztes Protokoll. In der Hauptunterhaltung antworten.", "Nur der jüngste Verlauf wird angezeigt.", "Mitglieder anzeigen", "Mitglieder ausblenden"],
 fr: ["Espace des agents", "Agent principal", "Membres", "Conversation", "Activité des outils", "Terminal d’origine", "Masquer le groupe", "Non affecté", "Exécution observée", "Inconnu", "Non fourni par cette session", "La liaison de session est absente. Rouvrez depuis le terminal.", "Chargement…", "Journal en lecture seule. Répondez dans la conversation principale.", "Seul l’historique récent est affiché.", "Afficher les membres", "Masquer les membres"],
 es: ["Espacio de agentes", "Agente principal", "Miembros", "Conversación", "Actividad de herramientas", "Terminal original", "Ocultar grupo", "Sin asignar", "Ejecución observada", "Desconocido", "Esta sesión no lo proporciona", "Falta el vínculo de sesión. Vuelva a abrir desde el terminal.", "Cargando…", "Registro de solo lectura. Responda en la conversación principal.", "Solo se muestra el historial reciente.", "Mostrar miembros", "Ocultar miembros"],
 ar: ["مساحة الوكلاء", "الوكيل الرئيسي", "الأعضاء", "المحادثة", "نشاط الأدوات", "الطرفية الأصلية", "إخفاء المجموعة", "غير معيّن", "تشغيل مرصود", "غير معروف", "غير متاح في هذه الجلسة", "ارتباط الجلسة مفقود. أعد الفتح من الطرفية.", "جارٍ التحميل…", "سجل للقراءة فقط. أجب في المحادثة الرئيسية.", "يتم عرض السجل الحديث فقط.", "عرض الأعضاء", "إخفاء الأعضاء"],
 "zh-CN": ["智能体工作区", "主智能体", "成员", "对话", "工具活动", "原始终端", "隐藏分组", "未分配", "观察到的运行", "未知", "此会话未提供", "会话连接已失效，请从终端重新打开。", "加载中…", "只读记录。请在主对话中回复。", "仅显示最近记录。", "显示成员", "隐藏成员"],
 "zh-TW": ["代理工作區", "主代理", "成員", "對話", "工具活動", "原始終端", "隱藏群組", "未指派", "觀察到的執行", "未知", "此工作階段未提供", "工作階段連線已失效，請從終端機重新開啟。", "載入中…", "唯讀記錄。請在主對話中回覆。", "僅顯示最近記錄。", "顯示成員", "隱藏成員"],
 it: ["Area degli agenti", "Agente principale", "Membri", "Conversazione", "Attività degli strumenti", "Terminale originale", "Nascondi gruppo", "Non assegnato", "Esecuzione osservata", "Sconosciuto", "Non fornito da questa sessione", "Collegamento della sessione mancante. Riapri dal terminale.", "Caricamento…", "Registro di sola lettura. Rispondi nella conversazione principale.", "Viene mostrata solo la cronologia recente.", "Mostra membri", "Nascondi membri"],
 da: ["Agentarbejdsområde", "Hovedagent", "Medlemmer", "Samtale", "Værktøjsaktivitet", "Oprindelig terminal", "Skjul gruppe", "Ikke tildelt", "Observeret kørsel", "Ukendt", "Ikke tilgængelig i denne session", "Sessionstilknytning mangler. Åbn igen fra terminalen.", "Indlæser…", "Skrivebeskyttet log. Svar i hovedsamtalen.", "Kun den seneste historik vises.", "Vis medlemmer", "Skjul medlemmer"],
 pl: ["Obszar agentów", "Główny agent", "Członkowie", "Rozmowa", "Aktywność narzędzi", "Oryginalny terminal", "Ukryj grupę", "Nieprzypisany", "Zaobserwowane uruchomienie", "Nieznany", "Ta sesja tego nie udostępnia", "Brak powiązania sesji. Otwórz ponownie z terminala.", "Ładowanie…", "Dziennik tylko do odczytu. Odpowiedz w głównej rozmowie.", "Wyświetlana jest tylko ostatnia historia.", "Pokaż członków", "Ukryj członków"],
 ru: ["Рабочая область агентов", "Главный агент", "Участники", "Разговор", "Действия инструментов", "Исходный терминал", "Скрыть группу", "Не назначен", "Наблюдаемый запуск", "Неизвестно", "Не предоставляется этой сессией", "Привязка сессии отсутствует. Откройте снова из терминала.", "Загрузка…", "Журнал только для чтения. Ответьте в основном разговоре.", "Показана только недавняя история.", "Показать участников", "Скрыть участников"],
 bs: ["Radni prostor agenata", "Glavni agent", "Članovi", "Razgovor", "Aktivnost alata", "Izvorni terminal", "Sakrij grupu", "Nedodijeljeno", "Posmatrano izvršavanje", "Nepoznato", "Nije dostupno u ovoj sesiji", "Veza sesije nedostaje. Ponovo otvorite iz terminala.", "Učitavanje…", "Zapis samo za čitanje. Odgovorite u glavnom razgovoru.", "Prikazana je samo nedavna historija.", "Prikaži članove", "Sakrij članove"],
 no: ["Agentarbeidsområde", "Hovedagent", "Medlemmer", "Samtale", "Verktøyaktivitet", "Opprinnelig terminal", "Skjul gruppe", "Ikke tildelt", "Observert kjøring", "Ukjent", "Ikke tilgjengelig i denne økten", "Økttilknytning mangler. Åpne på nytt fra terminalen.", "Laster…", "Skrivebeskyttet logg. Svar i hovedsamtalen.", "Bare nyere historikk vises.", "Vis medlemmer", "Skjul medlemmer"],
 "pt-BR": ["Espaço dos agentes", "Agente principal", "Membros", "Conversa", "Atividade de ferramentas", "Terminal original", "Ocultar grupo", "Não atribuído", "Execução observada", "Desconhecido", "Não fornecido por esta sessão", "Vínculo da sessão ausente. Reabra pelo terminal.", "Carregando…", "Registro somente leitura. Responda na conversa principal.", "Apenas o histórico recente é exibido.", "Mostrar membros", "Ocultar membros"],
 th: ["พื้นที่ทำงานเอเจนต์", "เอเจนต์หลัก", "สมาชิก", "การสนทนา", "กิจกรรมเครื่องมือ", "เทอร์มินัลเดิม", "ซ่อนกลุ่ม", "ยังไม่กำหนด", "การทำงานที่สังเกตได้", "ไม่ทราบ", "เซสชันนี้ไม่ได้ให้ข้อมูล", "ไม่พบการเชื่อมโยงเซสชัน โปรดเปิดใหม่จากเทอร์มินัล", "กำลังโหลด…", "บันทึกแบบอ่านอย่างเดียว โปรดตอบในการสนทนาหลัก", "แสดงเฉพาะประวัติล่าสุด", "แสดงสมาชิก", "ซ่อนสมาชิก"],
 tr: ["Ajan çalışma alanı", "Ana ajan", "Üyeler", "Konuşma", "Araç etkinliği", "Asıl terminal", "Grubu gizle", "Atanmamış", "Gözlemlenen çalışma", "Bilinmiyor", "Bu oturum tarafından sağlanmıyor", "Oturum bağlantısı eksik. Terminalden yeniden açın.", "Yükleniyor…", "Salt okunur kayıt. Ana konuşmada yanıtlayın.", "Yalnızca yakın geçmiş gösteriliyor.", "Üyeleri göster", "Üyeleri gizle"],
 km: ["កន្លែងធ្វើការភ្នាក់ងារ", "ភ្នាក់ងារមេ", "សមាជិក", "ការសន្ទនា", "សកម្មភាពឧបករណ៍", "ស្ថានីយដើម", "លាក់ក្រុម", "មិនបានកំណត់", "ការដំណើរការដែលបានសង្កេត", "មិនស្គាល់", "សម័យនេះមិនផ្ដល់ទេ", "បាត់ការភ្ជាប់សម័យ។ បើកឡើងវិញពីស្ថានីយ។", "កំពុងផ្ទុក…", "កំណត់ត្រាសម្រាប់អានប៉ុណ្ណោះ។ ឆ្លើយក្នុងការសន្ទនាមេ។", "បង្ហាញតែប្រវត្តិថ្មីៗ។", "បង្ហាញសមាជិក", "លាក់សមាជិក"],
 uk: ["Робоча область агентів", "Головний агент", "Учасники", "Розмова", "Дії інструментів", "Початковий термінал", "Приховати групу", "Не призначено", "Спостережений запуск", "Невідомо", "Не надається цією сесією", "Прив’язка сесії відсутня. Відкрийте знову з термінала.", "Завантаження…", "Журнал лише для читання. Відповідайте в основній розмові.", "Показано лише недавню історію.", "Показати учасників", "Приховати учасників"],
};
export function agentWorkspaceText(key: Key, languages = typeof navigator === "undefined" ? ["en"] : navigator.languages ?? ["en"]): string {
  return copy[resolveAgentChatLocale(languages)][keys.indexOf(key)];
}

const states: Record<AgentChatLocale, string[]> = {
 en: ["Working", "Idle", "Needs input", "Ended", "No child records yet"],
 ko: ["작업 중", "대기 중", "입력 필요", "종료됨", "하위 기록이 아직 없습니다"],
 ja: ["作業中", "待機中", "入力が必要", "終了", "子の記録はまだありません"],
 de: ["In Arbeit", "Bereit", "Eingabe nötig", "Beendet", "Noch keine untergeordneten Aufzeichnungen"],
 fr: ["En cours", "En attente", "Saisie requise", "Terminé", "Aucun enregistrement enfant pour le moment"],
 es: ["Trabajando", "Inactivo", "Requiere entrada", "Finalizado", "Aún no hay registros secundarios"],
 ar: ["يعمل", "خامل", "يتطلب إدخالاً", "انتهى", "لا توجد سجلات فرعية بعد"],
 "zh-CN": ["工作中", "空闲", "需要输入", "已结束", "暂无子记录"],
 "zh-TW": ["工作中", "閒置", "需要輸入", "已結束", "尚無子記錄"],
 it: ["In corso", "Inattivo", "Input richiesto", "Terminato", "Nessun registro secondario ancora"],
 da: ["Arbejder", "Inaktiv", "Kræver input", "Afsluttet", "Ingen underordnede poster endnu"],
 pl: ["Pracuje", "Bezczynny", "Wymaga danych", "Zakończony", "Brak jeszcze rekordów podrzędnych"],
 ru: ["Работает", "Ожидание", "Требуется ввод", "Завершён", "Дочерних записей пока нет"],
 bs: ["Radi", "Neaktivan", "Potreban unos", "Završeno", "Još nema podređenih zapisa"],
 no: ["Arbeider", "Inaktiv", "Trenger inndata", "Avsluttet", "Ingen underordnede oppføringer ennå"],
 "pt-BR": ["Trabalhando", "Inativo", "Requer entrada", "Encerrado", "Ainda não há registros secundários"],
 th: ["กำลังทำงาน", "ว่าง", "ต้องการข้อมูล", "สิ้นสุดแล้ว", "ยังไม่มีบันทึกย่อย"],
 tr: ["Çalışıyor", "Boşta", "Girdi gerekiyor", "Sona erdi", "Henüz alt kayıt yok"],
 km: ["កំពុងធ្វើការ", "ទំនេរ", "ត្រូវការបញ្ចូល", "បានបញ្ចប់", "មិនទាន់មានកំណត់ត្រាកូនទេ"],
 uk: ["Працює", "Очікування", "Потрібне введення", "Завершено", "Дочірніх записів поки немає"],
};
export function agentWorkspaceState(state: "working" | "idle" | "needsInput" | "ended" | "empty" | "unknown", languages = typeof navigator === "undefined" ? ["en"] : navigator.languages ?? ["en"]): string {
  if (state === "unknown") return agentWorkspaceText("unknown", languages);
  return states[resolveAgentChatLocale(languages)][["working", "idle", "needsInput", "ended", "empty"].indexOf(state)];
}
