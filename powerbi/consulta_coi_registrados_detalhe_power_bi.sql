USE mdb;
SET NOCOUNT ON;

--------------------------------------------------------------------------------
-- VERSAO POWER BI de queries/consulta_coi_registrados_detalhe.sql
--
-- A regra e a da consulta de /queries, que e a fonte de verdade. Este arquivo
-- e o texto dela sem alteracao, exceto pelas adaptacoes abaixo, marcadas no
-- corpo com [POWER BI]. Se esta versao e a fonte divergirem, vale a fonte.
--
-- Adaptacoes:
--   - periodo automatico: os @PBI_QuantidadeMeses meses de calendario COMPLETOS
--     anteriores ao mes corrente, no lugar das datas digitadas;
--   - saida: a fonte ja devolve um unico result set, que sai sem alteracao.
--
-- Power BI: conector SQL Server, banco mdb, modo Importacao, este arquivo
-- inteiro no campo Instrucao SQL, Adicionar colunas de relacao desmarcado.
-- Somente leitura. Batch unico, sem GO.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- [POWER BI] PERIODO AUTOMATICO
--
-- A fonte recebe o periodo digitado, em meses de calendario com fim EXCLUSIVO.
-- Aqui ele e calculado a cada atualizacao, na mesma forma:
--
--     fim    (exclusivo) = dia 1 do mes corrente, 00:00:00, horario do Brasil
--     inicio (inclusivo) = @PBI_QuantidadeMeses meses antes do fim
--
-- Entram so meses COMPLETOS: o mes em andamento fica de fora. Para mudar a
-- cobertura, altere apenas @PBI_QuantidadeMeses.
--------------------------------------------------------------------------------
DECLARE @PBI_QuantidadeMeses int = 6;

DECLARE @PBI_HojeBR date =
    CONVERT(date, DATEADD(HOUR, -3, SYSUTCDATETIME()));
DECLARE @PBI_FimBR datetime2(0) =
    CONVERT(datetime2(0), DATEFROMPARTS(YEAR(@PBI_HojeBR), MONTH(@PBI_HojeBR), 1));
DECLARE @PBI_InicioBR datetime2(0) =
    DATEADD(MONTH, -@PBI_QuantidadeMeses, @PBI_FimBR);


/*
================================================================================
COI - REGISTRADOS - detalhe, uma linha por SDM (auditoria)
================================================================================

Prova de auditoria da base de Registrados: lista NOMINALMENTE os chamados que
compoem o total do indicador, com quem registrou e POR QUE cada um entrou.

Saida: UM unico result set, UMA linha por SDM.
    SDM, DataHoraRegistro, DataRegistro, HoraRegistro, TipoCodigo, Tipo,
    RegistradorUUID, RegistradorUserID, RegistradorNome,
    GrupoAtualUUID, EvidenciaCOI, AliasEvidencia, DataPrimeiraEntradaCOI

QUEM REGISTROU
    A fonte tecnica e call_req.log_agent. ca_contact entra apenas por LEFT JOIN,
    SO PARA EXIBIR nome e userid. Chamado cujo registrador nao resolve NAO e
    descartado: sai com o UUID preenchido e o nome marcado como nao resolvido -
    perder linha para nao mostrar nulo falsearia o total.

AS COLUNAS DE AUDITORIA NAO SAO CRITERIO

    log_agent, grupo atual e data de entrada no COI viajam junto com a base
    canonica APENAS para exibicao e conferencia. Nenhuma delas aparece em
    predicado ou na classificacao: a populacao e exatamente a mesma das
    consultas de indicador, sem um chamado a mais nem a menos.

HORIZONTE
    Nao ha mais parametro de horizonte. DataRegistroCOI e um INSTANTE fixo do
    chamado, entao o mes dele nao muda porque a janela consultada cresceu - a
    imutabilidade que @HorizonteMensal produzia por parametro agora e estrutural.
    Auditoria e indicador batem por construcao, em qualquer tamanho de janela.

REGRA DE "REGISTRADO PELO COI" - canonica, baseada no sistema fonte

    type IN ('I','R')
    E  PRIMEIRA ENTRADA NA FILA DO COI, em toda a vida do chamado, caindo
       dentro da janela consultada
    -> uma linha por SDM, sem filtro de analista, categoria, motivo ou status.

    O eixo NAO e call_req.open_date: e a DataRegistroCOI reconstruida. Um SDM
    conta UMA vez, na primeira entrada; reentrada nao conta de novo.

    A evidencia PRINCIPAL e a cadeia real de mudancas de grupo em act_log. O
    '%GROUP=' do INIT e apenas AUXILIAR - ha chamados cujo INIT declara uma fila
    que a primeira mudanca de grupo contradiz, e nesses a cadeia vence. Quando
    nao existe NENHUM evento de grupo, aplica-se o fallback de estado autorizado
    pela gestao do COI: a fila em que o chamado permaneceu.

    O detalhamento, os aliases historicos, a janela de transicao de contrato e o
    motivo de cada decisao estao no bloco delimitado por INICIO/FIM REGRA
    CANONICA DE REGISTRADOS COI, IDENTICO byte a byte nas SETE consultas de
    Registrados e conferivel por SHA256.

O RSP HISTORICO NAO E O ALVO

    Os relatorios antigos do fornecedor vieram de OUTRA ferramenta/base, o
    proprio fornecedor confirmou inconsistencias, e a aba DADOS guarda apenas
    valores digitados - sem pivot, conexao ou formula que revele a regra. Eles
    valem como referencia externa de reconciliacao; a definicao tecnica do
    indicador e esta consulta, sobre o sistema fonte atual.

    Nenhum filtro aqui existe para aproximar numero de relatorio antigo.

LIMITE CONHECIDO - historico nao e imutavel

    Uma execucao de hoje pode divergir de um relatorio emitido meses atras se
    chamados foram corrigidos ou incluidos depois com open_date retroativo. O
    horizonte de elegibilidade impede que MOVIMENTACAO posterior mude um periodo
    fechado, mas nao reconstroi um snapshot antigo. Se for exigido que meses
    fechados nunca mudem, o caminho e snapshot mensal persistido no fechamento -
    decisao de projeto, nao implementada aqui.

Somente leitura. Batch unico. Nao existe GO neste arquivo.
================================================================================
*/

--------------------------------------------------------------------------------
-- [0] PARAMETROS
--
-- Datas em horario do Brasil. Intervalo SEMIABERTO: >= inicio e < fim.
-- Nao usar 23:59:59 como fim: o chamado do ultimo segundo do dia ficaria de fora.
--
-- open_date e close_date em dbo.call_req sao epoch UTC em segundos (int).
-- Brasil = UTC-3 fixo (sem horario de verao desde 2019), mesma conversao ja
-- validada em decision/ e protect4/.
--------------------------------------------------------------------------------
DECLARE @HorasBrasilParaUTC int = 3;
DECLARE @Epoch datetime2(0) = '1970-01-01 00:00:00';

-- [POWER BI] Periodo automatico, calculado no inicio do arquivo.
DECLARE @InicioBR datetime2(0) = @PBI_InicioBR;   -- inclusivo
DECLARE @FimBR    datetime2(0) = @PBI_FimBR;      -- EXCLUSIVO

DECLARE @InicioEpoch int = DATEDIFF(SECOND, @Epoch, DATEADD(HOUR, @HorasBrasilParaUTC, @InicioBR));
DECLARE @FimEpoch    int = DATEDIFF(SECOND, @Epoch, DATEADD(HOUR, @HorasBrasilParaUTC, @FimBR));


--------------------------------------------------------------------------------
-- INICIO REGRA CANONICA DE REGISTRADOS COI
--
-- Bloco IDENTICO, byte a byte, nas SETE consultas de Registrados:
--     INDICADORES
--       consulta_coi_registrados_mensal.sql
--       consulta_coi_registrados_encerrados_diario.sql
--       consulta_coi_registrados_por_hora.sql
--     AUDITORIA
--       consulta_coi_registrados_detalhe.sql
--       consulta_coi_registrados_por_registrador.sql
--       consulta_coi_registrados_por_evidencia.sql
--       consulta_coi_registrados_validacao.sql
--
-- Conferir com SHA256 do trecho entre os marcadores. Nao basta parecerem iguais.
--
-- A REGRA
--
--   Um SDM e Registrado pelo COI quando ENTRA NO COI PELA PRIMEIRA VEZ NA VIDA
--   do chamado. Cada SDM produz UMA data:
--
--       DataRegistroCOI
--
--   e os indicadores mensal, diario e por hora sao agrupados por ela - NAO por
--   call_req.open_date. Um SDM conta UMA vez. Reentrada nao gera novo registro.
--
-- O QUE MUDOU: O INIT DEIXOU DE SER A EVIDENCIA PRINCIPAL
--
--   A versao anterior consultava primeiro o '%GROUP=' do evento INIT e, se ele
--   fosse alias do COI, fixava DataRegistroCOI = open_date sem olhar a cadeia.
--   Isso foi REFUTADO por dados: existem chamados cujo INIT declara '10-COI' e
--   cuja primeira mudanca real de grupo prova que eles estavam em OUTRA fila.
--
--       1686505  INIT='10-COI'  aberto 18/03 22:08:45
--                1o evento: GESTAO DE SUPORTE REMOTO -> COI  em 22:09:37
--
--   O chamado nao foi aberto no COI as 22:08:45. Ele ENTROU no COI as 22:09:37.
--   O INIT carrega o grupo PEDIDO no template da automacao, que pode nao ser o
--   grupo em que o chamado efetivamente nasceu.
--
--   Por isso a hierarquia se inverteu. O INIT continua no resultado, como
--   evidencia AUXILIAR e auditavel (colunas GrupoInit e
--   InitConsistenteComReconstrucao), mas NAO decide mais a data.
--
-- HIERARQUIA DE EVIDENCIA - determinista, uma evidencia por SDM
--   (AUTOMACAO_TASK_SCHEDULER entra como ULTIMO ramo; ver PRECEDENCIA)
--
--   1. CADEIA REAL DE MUDANCAS DE GRUPO - evidencia principal
--
--      ABERTO_NO_COI_CADEIA
--          a ORIGEM do primeiro evento real de grupo pertence ao universo
--          logico COI -> DataRegistroCOI = open_date
--          Nao havendo mudanca de grupo anterior, o chamado ja estava no COI
--          antes da primeira transferencia observada.
--
--      TRANSFERIDO_PARA_COI
--          a origem do primeiro evento e legivel e NAO e COI: o chamado nasceu
--          fora -> DataRegistroCOI = primeiro evento cujo DESTINO e COI
--
--      JA_ESTAVA_NO_COI_HISTORICO
--          a origem do primeiro evento e 'CONTRATO 7/2023 - COI', o chamado foi
--          aberto ANTES da transicao, o %GROUP= do INIT nao aponta fila nao-COI
--          e nao ha ancora de grupo ilegivel antes do primeiro evento legivel
--          -> DataRegistroCOI = open_date
--
--          Esse nome e o rotulo POSTERIOR da fila que, antes da transicao, se
--          chamava 'COI'. O act_log grava o nome vigente NO INSTANTE DO EVENTO,
--          entao um chamado de 2023 que so se move em 2026 tem o evento gravado
--          com o nome novo da fila velha. Ler isso como "entrou no COI agora"
--          apaga a entrada historica e joga o SDM para outro mes.
--
--          Caso 1419597: aberto em 2023-05-29, primeiro evento em jun/2026 com
--          origem 'CONTRATO 7/2023 - COI' e destino 'COI'. A primeira entrada e
--          2023, nao junho de 2026.
--
--          AS DUAS TRAVAS, e por que existem. A origem so prova que o SDM estava
--          naquela fila IMEDIATAMENTE ANTES da transferencia - nao que estava la
--          desde a abertura. Entre a abertura e o primeiro evento observavel
--          pode ter havido movimentacao que o log nao mostra. Entao:
--
--            1. se o %GROUP= do INIT nomeia uma fila NAO-COI, ele e evidencia
--               direta e contemporanea de que o chamado nasceu fora. Datar em
--               open_date afirmaria um nascimento que o proprio registro de
--               abertura nega -> CONTRADICAO_INIT_x_CADEIA, ressalva.
--
--               A compatibilidade aqui e TEMPORAL, nao apenas nominal. Para
--               abertura anterior a transicao, so 'COI' e '10-COI' sao INIT
--               compativeis - e '10-COI' entra porque tem evento operacional
--               real desde 13/02/2026. 'CONTRATO 7/2023 - COI' NAO e: esse nome
--               so passa a existir NA transicao, e o INIT e escrito na criacao.
--               Encontra-lo num chamado aberto antes e anomalia a auditar, nao
--               evidencia de pertencimento
--               -> INIT_CONTRATO_INCOMPATIVEL_COM_DATA_ABERTURA, ressalva.
--
--               Note que #AliasInit NAO serve de trava aqui, embora sirva a
--               auditoria geral do rotulo: ela inclui o nome do contrato, e
--               usa-la deixaria passar exatamente o caso anomalo.
--            2. se existe ancora de grupo ILEGIVEL antes do primeiro evento
--               legivel, esse evento pode nao ser o primeiro da vida, e a
--               origem dele nao descreve a abertura
--               -> SEM_RECONSTRUCAO_EVENTO_ILEGIVEL, ressalva.
--
--          Isto NAO devolve o INIT ao topo da hierarquia. Ele nao escolhe data
--          em ramo nenhum; aqui ele so IMPEDE uma inferencia que o contradiz.
--
--      ENTRADA_DEMONSTRAVEL_DESTINO
--          a origem do primeiro evento nao prova a primeira entrada, mas existe
--          evento com DESTINO COI -> DataRegistroCOI = esse evento
--
--          A origem pode falhar de duas maneiras, e as duas caem aqui:
--            ilegivel no TEXTO      "'' -> COI" (caso 1686579)
--            ilegivel no SIGNIFICADO origem 'CONTRATO 7/2023 - COI' em chamado
--                                    aberto DENTRO da janela de renomeacao, em
--                                    que nao se sabe sob que nome aquele UUID
--                                    operava
--
--          Nos dois casos a ENTRADA e demonstravel naquele instante, e so a
--          antecipacao para open_date e que fica impedida - antecipar seria
--          afirmar um nascimento que o log nao mostra.
--
--   2. FALLBACK DE ESTADO - autorizado pelo gerente, SO sem cadeia utilizavel
--
--      ABERTO_NO_COI_INFERIDO_GRUPO_ATUAL
--          nenhum evento de grupo em toda a vida, e group_id atual = COI novo
--          -> DataRegistroCOI = open_date
--          "sem log de mudanca, considerar a fila em que o chamado permaneceu"
--
--      ABERTO_NO_COI_INFERIDO_GRUPO_ATUAL_HISTORICO
--          nenhum evento de grupo, group_id atual = COI antigo, e o chamado foi
--          aberto ANTES da transicao -> DataRegistroCOI = open_date
--          Reconstrucao historica: quando ele nasceu, aquele UUID se chamava
--          'COI' e era a fila do COI.
--
--   3. FORA DO INDICADOR, mas VISIVEL em #RegRessalvas
--
--      SEM_RECONSTRUCAO_EVENTO_ILEGIVEL
--          existe evento com ancora de grupo, mas NENHUM legivel. Nao se pode
--          reconstruir a cadeia - e nao se pode cair no fallback, porque houve
--          movimentacao. Contar aqui seria afirmar permanencia onde houve
--          movimento que nao sabemos ler.
--
--      CONTRADICAO_INIT_x_CADEIA
--          a origem historica sugere pertencimento ao COI, mas o %GROUP= do
--          INIT nomeia explicitamente uma fila nao-COI. As duas evidencias se
--          contradizem e a entrada correta nao e demonstravel. Vai para
--          auditoria em vez de receber open_date inventado.
--
--      INIT_CONTRATO_INCOMPATIVEL_COM_DATA_ABERTURA
--          o chamado abriu ANTES da transicao mas o %GROUP= do INIT ja traz
--          'CONTRATO 7/2023 - COI', nome que a fila so recebeu DEPOIS. O
--          registro de abertura nao pode conhecer um nome futuro: ou a linha
--          INIT nao descreve a criacao, ou a data de abertura nao e a que
--          parece. Qualquer das duas invalida a inferencia historica.
--
--      AMBIGUO_JANELA_TRANSICAO
--          abertura DENTRO da janela de renomeacao E nenhuma entrada
--          demonstravel em fila COI. Duas formas:
--            sem cadeia, group_id atual = COI antigo - o UUID antigo sozinho
--              nao data a abertura ali;
--            com cadeia cuja origem e 'CONTRATO 7/2023 - COI' mas sem nenhum
--              evento com destino COI.
--
--          A ressalva EXIGE ausencia de entrada demonstravel. Ela existe para o
--          caso "nao sei SE entrou", nao para "nao sei QUANDO entrou". Havendo
--          evento com destino em fila COI, o SDM entra pelo ramo
--          ENTRADA_DEMONSTRAVEL_DESTINO, datado nesse evento.
--
--      NAO_ENTRA
--          cadeia existe e nunca toca o COI, ou estado atual nao e COI.
--          Descartado antes de #RegBase.
--
--   A ordem importa: a cadeia real e consultada PRIMEIRO e vence sempre. O
--   fallback so e alcancado quando nao existe NENHUM evento de grupo.
--
-- UNIVERSO LOGICO COI NOS EVENTOS REAIS
--
--   Aceitos:      COI      e  10-COI
--   NAO aceito:   CONTRATO 7/2023 - COI
--
--   '10-COI' entra porque a serie temporal provou que sua atuacao operacional
--   real ficou restrita ao periodo de transicao:
--
--       como destino: 2026-02-13 16:45:06  ate  2026-03-18 19:29:11
--       como origem : 2026-02-27 16:40:06  ate  2026-03-18 20:35:51
--
--   Nenhum evento real com '10-COI' depois disso. Ele foi, temporariamente, o
--   nome da fila do COI - e nesse intervalo transferir para '10-COI' era
--   transferir para o COI.
--
--   'CONTRATO 7/2023 - COI' e ASSIMETRICO, e essa e a correcao mais importante
--   desta regra. Ele vale conforme a POSICAO que ocupa no evento:
--
--     como DESTINO, depois da transicao        NAO cria entrada
--         'OUTRA FILA' -> 'CONTRATO 7/2023 - COI' e movimentacao para a fila do
--         contrato ENCERRADO. Nao e entrada no COI corrente. Por isso o nome
--         NAO esta em #AliasCOI, que so decide destino.
--
--     como ORIGEM, em chamado aberto ANTES da transicao   PROVA pertencimento
--         'CONTRATO 7/2023 - COI' -> 'COI' diz que, imediatamente antes dessa
--         transferencia, o SDM ja estava na fila que naquela epoca se chamava
--         'COI'. Ele ja era do universo logico COI. A primeira entrada e a
--         abertura, nao essa transferencia.
--
--   A assimetria existe porque um evento POSTERIOR a renomeacao registra a
--   origem pelo nome vigente NAQUELE momento. Logo, o primeiro evento historico
--   disponivel pode mostrar o nome NOVO de uma fila na qual o chamado ja estava
--   ANTES da renomeacao.
--
--   Nenhuma linha antiga do act_log e alterada: as linhas gravadas antes da
--   troca continuam com o nome antigo. O que muda e o nome usado pelas linhas
--   gravadas DEPOIS. Ler origem e destino com o mesmo criterio confunde as duas
--   coisas.
--
--   RESTRICAO: a leitura da origem exige abertura ANTES da transicao. Um chamado
--   aberto DEPOIS dela cujo primeiro evento parte de 'CONTRATO 7/2023 - COI'
--   nasceu mesmo na fila do contrato encerrado - ali o nome nao e rotulo
--   retroativo, e a fila de verdade. Esse cai nos ramos normais de entrada por
--   destino. Aberto DENTRO da janela: ressalva.
--
--   O nome 'COI' vale nos DOIS lados da troca. Ele mudou de UUID, mas nao de
--   significado de negocio: dos dois lados ele designa a fila do COI. Como o
--   indicador mede primeira entrada no universo logico COI, e nao pertencimento
--   a um UUID, a troca de identidade do nome nao altera o indicador.
--
-- JANELA DE TRANSICAO
--
--       (2026-03-18 20:35:51 , 2026-03-18 21:48:58]
--
--   Extremos medidos: ultima aparicao operacional de '10-COI' e primeira de
--   'CONTRATO 7/2023 - COI'. Como max(10-COI) < min(CONTRATO), nao ha
--   intercalamento entre os dois nomes.
--
--   A janela impede INFERENCIA, nunca apaga EVIDENCIA. Dentro dela nao se sabe
--   sob que nome o UUID antigo operava, entao nao se pode inferir pertencimento
--   a partir da origem nem do estado atual - mas um evento com destino em fila
--   COI continua provando a entrada, e com instante conhecido.
--
--   Por isso ela so exclui quando NAO ha entrada demonstravel. Confundir as
--   duas coisas faria a regra responder "nao sei se entrou" quando o log diz
--   "entrou as 21:48:58, so nao sei se ja estava antes".
--
-- REENTRADAS - uma contagem por SDM
--
--   DataRegistroCOI e a PRIMEIRA entrada da vida. A busca varre a vida inteira
--   do chamado, sem recorte de janela; so depois a janela filtra. Se o SDM
--   entrou no COI em janeiro, saiu e voltou em fevereiro, ele e de janeiro e
--   nao reaparece em fevereiro.
--
--   Movimentos COI -> 10-COI e 10-COI -> COI sao movimentacao INTERNA do
--   universo logico e nao geram entrada nova: ambos os nomes estao em
--   #AliasCOI, entao a origem do primeiro evento ja e COI e o SDM fica com
--   open_date pelo ramo ABERTO_NO_COI_CADEIA.
--
-- CANDIDATOS - por EVENTO, nunca por idade do chamado
--
--   Para uma DataRegistroCOI cair dentro da janela, so existem dois caminhos:
--
--     A) o chamado ABRIU dentro da janela (nasceu no COI, entrou nela, ou caiu
--        no fallback de estado - todos dao DataRegistroCOI = open_date);
--     B) houve ENTRADA no COI dentro da janela, qualquer que seja a idade.
--
--   Entao o universo e A UNIAO B. Um chamado aberto ha dois anos em outro
--   nucleo, transferido ao COI ontem, entra por B - sem horizonte de abertura.
--
--   Isto NAO e otimizacao: e a diferenca entre "primeira entrada da vida" e
--   "primeira entrada entre os chamados que resolvemos carregar". Um recorte
--   por open_date nao pode ser validado por contador nenhum, porque o que ele
--   exclui fica de fora ANTES de existir para ser contado.
--
-- IDENTIDADE HISTORICA - por texto, nunca por UUID atual
--
--   O act_log grava o grupo por NOME textual historico. Resolver esse nome
--   contra o cadastro ATUAL reescreve o passado com o presente. Por isso os
--   eventos sao decididos por tabela EXPLICITA de aliases, e nao por JOIN em
--   ca_contact nem por LIKE '%COI%'. O UUID so aparece no fallback, que e
--   justamente o ramo em que nao ha texto historico para ler.
--
-- CONTAS TECNICAS: ONDE ENTRAM E ONDE NAO ENTRAM
--
--   ServiceDesk, usr_automacoes e sesuc_auto sao compartilhadas com outros
--   nucleos. Um NOME DE CONTA, sozinho, continua nao provando pertencimento ao
--   COI, e continua nao existindo ramo que conte um chamado so porque ele foi
--   aberto por conta tecnica.
--
--   O que mudou: a modalidade Task Scheduler / SESUC, informada oficialmente
--   pela gestao, e definida por uma TRINCA - interface CMD, %FROM_USERID=
--   servicedesk e %GROUP= dentro de uma lista fechada de filas. A conta e
--   apenas UM dos tres termos, e nenhum dos tres basta sozinho.
--
--   Para Zabbix, log_agent = usr_automacoes participa APENAS da coluna
--   informativa TipoAutomacaoCOI. Nao decide pertencimento nem data: os
--   chamados do Zabbix ja entram pela cadeia real, porque nascem no COI.
--
-- AUTOMACOES OFICIAIS - tres modalidades informadas pela gestao
--
--   A regra deixou de depender EXCLUSIVAMENTE de passagem pela fila COI. O
--   motivo e factual: o Task Scheduler registra direto na fila do NSTI ou do
--   fornecedor, e esses chamados nunca produzem evento de grupo com origem ou
--   destino no COI. Antes, eles nao existiam para o indicador.
--
--   1. TASK SCHEDULER / SESUC     -> DECIDE pertencimento
--
--      Criterio oficial, os tres termos ao mesmo tempo:
--          primeiro log 'Criado via interface CMD'
--          %FROM_USERID= servicedesk
--          %GROUP= em #GrupoTaskSched (lista oficial fechada, [R1c])
--
--      Evidencia propria: AUTOMACAO_TASK_SCHEDULER, com
--      DataRegistroCOI = open_date. O rotulo NAO afirma entrada na fila COI -
--      afirma registro por automacao oficial do COI em fila de destino. Por
--      isso e rotulo separado, e nao reuso de ABERTO_NO_COI_*.
--
--   2. ZABBIX MONITOR             -> so CLASSIFICA
--
--      log_agent = usr_automacoes e type = 'I'. Os exemplos oficiais ja entram
--      pela cadeia (ABERTO_NO_COI_CADEIA): o Zabbix abre no COI e o COI
--      transfere adiante. Nada aqui cria linha nova nem altera data.
--
--      O campo 'Relatado por' da tela corresponde a log_agent.
--      call_req.customer varia entre contas de infraestrutura e NAO e criterio.
--
--   3. ROBO COI / COPILOT STUDIO  -> so CLASSIFICA
--
--      Os exemplos oficiais ja entram pela cadeia ou pelo grupo atual. A
--      assinatura usada aqui e EVIDENCIA TECNICA OBSERVADA, e nao criterio de
--      negocio declarado pela gestao: interface CMD, DUAS ocorrencias de
--      %FROM_USERID= e presenca de %TYPE=, quase sempre com %GROUP=COI.
--
--      %FROM_USERID= gravado NAO e vazio: contem a matricula do solicitante,
--      ou uma conta tecnica. O modelo em branco mostrado pela gestao e marcador
--      de template, nao o valor armazenado.
--
--      Por ser correlacao observada, ela alimenta SOMENTE a coluna informativa
--      TipoAutomacaoCOI. Nenhum chamado entra, sai ou muda de data por causa
--      dela.
--
--   TipoAutomacaoCOI explica a ORIGEM do registro. EvidenciaRegistroCOI explica
--   POR QUE e QUANDO o chamado entrou no indicador. Sao independentes.
--
-- PRECEDENCIA ENTRE CADEIA, AUTOMACAO, FALLBACK E HISTORICO
--
--   1. cadeia real de eventos de grupo    ABERTO_NO_COI_CADEIA,
--                                         JA_ESTAVA_NO_COI_HISTORICO,
--                                         TRANSFERIDO_PARA_COI,
--                                         ENTRADA_DEMONSTRAVEL_DESTINO
--   2. travas e ressalvas de historico e da janela de transicao
--   3. fallback de estado por grupo atual ABERTO_NO_COI_INFERIDO_GRUPO_ATUAL,
--                                         ABERTO_NO_COI_INFERIDO_GRUPO_ATUAL_HISTORICO
--   4. automacao Task Scheduler           AUTOMACAO_TASK_SCHEDULER
--
--   A automacao e o ULTIMO recurso, deliberadamente. Assim nenhum chamado que
--   ja contava por cadeia, historico ou grupo atual muda de evidencia ou de
--   data: os ramos anteriores disparam primeiro. A automacao so alcanca quem
--   antes terminava em NAO_ENTRA.
--
--   Consequencia aceita: se a cadeia esta ilegivel (ancora de grupo sem nenhum
--   evento legivel), o chamado permanece na ressalva
--   SEM_RECONSTRUCAO_EVENTO_ILEGIVEL mesmo sendo elegivel por automacao.
--   Preferiu-se nao deixar a automacao apagar uma ressalva existente. Quantos
--   casos sao, a consulta de validacao mede - nao se supoe.
--------------------------------------------------------------------------------

-- [R0] Identidade da fila COI e janela de transicao.
--      Nomes proprios (@COI_UUID_*) para nao colidir com @COI_Antigo/@COI_Novo
--      que alguns arquivos ja declaram para o lado de Encerrados.
DECLARE @COI_UUID_Antigo varbinary(16) = 0xDA7095D797E3FE498A62B79CB7EAED15;  -- hoje 'CONTRATO 7/2023 - COI'
DECLARE @COI_UUID_Novo   varbinary(16) = 0x3C11B3A9EBCE5D498E2F7D7FF385F967;  -- hoje 'COI'

DECLARE @TransIniBR datetime2(0) = '2026-03-18 20:35:51';  -- ultimo evento real '10-COI'
DECLARE @TransFimBR datetime2(0) = '2026-03-18 21:48:58';  -- 1o evento real 'CONTRATO 7/2023 - COI'
-- Conta tecnica do Zabbix, resolvida por userid e nunca por UUID fixo. Serve
-- exclusivamente a coluna informativa TipoAutomacaoCOI. Se a conta nao existir,
-- fica NULL e a classificacao apenas nao marca Zabbix - nenhum chamado entra
-- ou sai por causa disso.
DECLARE @UUID_UsrAutomacoes varbinary(16) = (
    SELECT TOP (1) k.contact_uuid FROM dbo.ca_contact AS k
    WHERE k.userid COLLATE Latin1_General_CI_AI = N'usr_automacoes');

DECLARE @TransIniEpoch int = DATEDIFF(SECOND, @Epoch, DATEADD(HOUR, @HorasBrasilParaUTC, @TransIniBR));
DECLARE @TransFimEpoch int = DATEDIFF(SECOND, @Epoch, DATEADD(HOUR, @HorasBrasilParaUTC, @TransFimBR));

-- [R1] Universo logico COI nos EVENTOS REAIS de grupo. Tabela explicita.
--      'CONTRATO 7/2023 - COI' NAO esta aqui: ver o bloco de documentacao.
IF OBJECT_ID('tempdb..#AliasCOI') IS NOT NULL DROP TABLE #AliasCOI;
CREATE TABLE #AliasCOI (nome_norm nvarchar(200) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);
INSERT INTO #AliasCOI (nome_norm) VALUES (N'COI'), (N'10-COI');

-- [R1b] Nomes considerados COI APENAS para auditar o %GROUP= do INIT. Inclui o
--       nome do contrato antigo porque aqui o objetivo e medir consistencia do
--       rotulo, nao decidir pertencimento. Esta tabela NAO entra em nenhuma
--       decisao de DataRegistroCOI.
IF OBJECT_ID('tempdb..#AliasInit') IS NOT NULL DROP TABLE #AliasInit;
CREATE TABLE #AliasInit (nome_norm nvarchar(200) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);
INSERT INTO #AliasInit (nome_norm) VALUES (N'COI'), (N'10-COI'), (N'CONTRATO 7/2023 - COI');

-- [R1c] Filas oficiais do Task Scheduler / SESUC, exatamente como a gestao
--       informou. A lista e FECHADA: %GROUP= fora dela NAO entra pela
--       automacao, ainda que o chamado seja 'Criado via interface CMD' por
--       servicedesk.
--
--       Os nomes estao SEM ACENTO de proposito. Todo o bloco e ASCII e a
--       comparacao usa Latin1_General_CI_AI, accent-insensitive: 'NSTI
--       SEGURANCA' casa com o nome gravado com cedilha e 'NSTI APLICACAO' casa
--       com o gravado com til. Os valores tambem chegam em caixa alta, porque
--       #RegInitTag ja aplica UPPER.
--
--       '10-COI' e o nome historico do COI e NAO esta na lista oficial. Isso e
--       proposital: chamados assim entram - quando entram - pela cadeia real,
--       e nao pela automacao.
IF OBJECT_ID('tempdb..#GrupoTaskSched') IS NOT NULL DROP TABLE #GrupoTaskSched;
CREATE TABLE #GrupoTaskSched (nome_norm nvarchar(200) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);
INSERT INTO #GrupoTaskSched (nome_norm) VALUES
    (N'FORNECEDORES - A2B'),
    (N'FORNECEDORES - AMM'),
    (N'FORNECEDORES - BULL'),
    (N'FORNECEDORES BULL - 41/2022 - G1 - FA1/FA2'),
    (N'FORNECEDORES BULL - 41/2022 - G2 - FB1'),
    (N'FORNECEDORES BULL - 45/2020 - G1 - FA3/FA4/FA5'),
    (N'FORNECEDORES BULL - 45/2020 - G2 - FB2'),
    (N'FORNECEDORES BULL - 45/2020 - G3 - FA-NAS-1 / FB3'),
    (N'FORNECEDORES - DECISION'),
    (N'NSTI REDE'),
    (N'NSTI SEGURANCA'),
    (N'NSTI APLICACAO'),
    (N'NSTI AD-WORKPLACE'),
    (N'NSTI BD'),
    (N'NSTI BI-ANALYTICS'),
    (N'NSTI SO'),
    (N'NSTI GCM'),
    (N'NSTI PLAN-DOC'),
    (N'COI');

-- [R2a] CONJUNTO A - chamados I/R abertos DENTRO da janela.
--       open_date e type crus: sargaveis.
IF OBJECT_ID('tempdb..#CandA') IS NOT NULL DROP TABLE #CandA;

SELECT r.id, r.persid
INTO #CandA
FROM dbo.call_req AS r
WHERE r.[type] IN ('I', 'R')
  AND r.open_date >= @InicioEpoch
  AND r.open_date <  @FimEpoch
OPTION (RECOMPILE);

CREATE UNIQUE CLUSTERED INDEX IX_CandA ON #CandA(id);

-- [R2b] CONJUNTO B - chamados que RECEBERAM entrada no COI dentro da janela,
--       com QUALQUER idade de abertura.
--
--       Aqui o act_log e filtrado por system_time, e nao por call_req_id. Se
--       nao houver indice temporal em act_log, este passo e uma varredura da
--       tabela, e o custo esta assumido. A alternativa seria recortar por data
--       de abertura - e era exatamente isso que tornava a regra falsa.
--
--       O LIKE '%COI%' e PRE-FILTRO, nao criterio: 'COI' e '10-COI' contem essa
--       substring, entao ele nao pode perder linha. Serve so para nao levar a
--       tempdb o texto de toda transferencia da janela. Quem decide e a ancora
--       de grupo e o par de aspas, logo abaixo.
IF OBJECT_ID('tempdb..#EvJanela') IS NOT NULL DROP TABLE #EvJanela;

SELECT
    al.call_req_id,
    (CONVERT(nvarchar(max), ISNULL(al.description, N'')) + N' ' +
     CONVERT(nvarchar(max), ISNULL(al.action_desc,  N'')))
        COLLATE Latin1_General_CI_AI AS texto
INTO #EvJanela
FROM dbo.act_log AS al
WHERE al.[type] = 'TR'
  AND al.system_time >= @InicioEpoch
  AND al.system_time <  @FimEpoch
  AND (al.description COLLATE Latin1_General_CI_AI LIKE N'%COI%'
    OR al.action_desc COLLATE Latin1_General_CI_AI LIKE N'%COI%')
OPTION (RECOMPILE);

CREATE CLUSTERED INDEX IX_EvJanela ON #EvJanela(call_req_id);

-- Dos eventos da janela, so os que sao mesmo mudanca de GRUPO com destino COI.
-- "Transferir Responsavel de 'A' para 'B'" grava o mesmo tipo 'TR' e NAO casa
-- com nenhuma das cinco ancoras: troca de analista nao e troca de fila.
IF OBJECT_ID('tempdb..#CandB') IS NOT NULL DROP TABLE #CandB;

SELECT DISTINCT r.id, r.persid
INTO #CandB
FROM #EvJanela AS a
JOIN dbo.call_req AS r
    ON a.call_req_id = r.persid
CROSS APPLY (SELECT p1 = CHARINDEX(N'Grupo de',             a.texto),
                    p2 = CHARINDEX(N'Grupo alterado de',    a.texto),
                    p3 = CHARINDEX(N'Grupo transferido de', a.texto),
                    p4 = CHARINDEX(N'Group from',           a.texto),
                    p5 = CHARINDEX(N'Group changed from',   a.texto)) AS pos
CROSS APPLY (SELECT posicao = CASE
        WHEN pos.p1 > 0 THEN pos.p1 + LEN(N'Grupo de')
        WHEN pos.p2 > 0 THEN pos.p2 + LEN(N'Grupo alterado de')
        WHEN pos.p3 > 0 THEN pos.p3 + LEN(N'Grupo transferido de')
        WHEN pos.p4 > 0 THEN pos.p4 + LEN(N'Group from')
        WHEN pos.p5 > 0 THEN pos.p5 + LEN(N'Group changed from')
        ELSE 0 END) AS anc
CROSS APPLY (SELECT resto = CONVERT(nvarchar(400),
                 SUBSTRING(a.texto, CASE WHEN anc.posicao > 0 THEN anc.posicao ELSE 1 END, 400))) AS g
CROSS APPLY (SELECT q1 = CHARINDEX(N'''', g.resto)) AS c1
CROSS APPLY (SELECT q2 = CASE WHEN c1.q1 > 0 THEN CHARINDEX(N'''', g.resto, c1.q1 + 1) ELSE 0 END) AS c2
CROSS APPLY (SELECT sp = CASE
        WHEN c2.q2 > 0 AND CHARINDEX(N' para ', g.resto, c2.q2) > 0 THEN CHARINDEX(N' para ', g.resto, c2.q2)
        WHEN c2.q2 > 0 THEN CHARINDEX(N' to ', g.resto, c2.q2)
        ELSE 0 END) AS sep
CROSS APPLY (SELECT q3 = CASE WHEN sep.sp > 0 THEN CHARINDEX(N'''', g.resto, sep.sp) ELSE 0 END) AS c3
CROSS APPLY (SELECT q4 = CASE WHEN c3.q3 > 0 THEN CHARINDEX(N'''', g.resto, c3.q3 + 1) ELSE 0 END) AS c4
CROSS APPLY (SELECT nome = CASE WHEN c4.q4 > c3.q3
                                THEN SUBSTRING(g.resto, c3.q3 + 1, c4.q4 - c3.q3 - 1) ELSE N'' END) AS des
CROSS APPLY (SELECT destino_norm = CONVERT(nvarchar(200), LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(
        UPPER(LTRIM(RTRIM(des.nome))), N' ', N'<>'), N'><', N''), N'<>', N' '))))) AS d
WHERE r.[type] IN ('I', 'R')
  AND anc.posicao > 0 AND c3.q3 > 0 AND c4.q4 > c3.q3
  AND EXISTS (SELECT 1 FROM #AliasCOI AS x
              WHERE x.nome_norm COLLATE Latin1_General_CI_AI
                  = d.destino_norm COLLATE Latin1_General_CI_AI);

CREATE UNIQUE CLUSTERED INDEX IX_CandB ON #CandB(id);

-- [R2] CANDIDATOS = A UNIAO B. Uma linha por SDM, sem recorte de idade.
IF OBJECT_ID('tempdb..#RegCand') IS NOT NULL DROP TABLE #RegCand;

SELECT
    r.id, r.persid, r.ref_num, r.[type] AS tipo, r.group_id, r.open_date,
    -- log_agent viaja junto SO PARA AUDITORIA: e a coluna de "quem abriu o
    -- chamado". Ela NAO aparece em nenhum predicado nem na classificacao, e NAO
    -- e o ator que transferiu o chamado para o COI.
    r.log_agent,
    DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, r.open_date, @Epoch)) AS abertura_br
INTO #RegCand
FROM dbo.call_req AS r
WHERE EXISTS (SELECT 1 FROM #CandA AS a WHERE a.id = r.id)
   OR EXISTS (SELECT 1 FROM #CandB AS b WHERE b.id = r.id)
OPTION (RECOMPILE);

CREATE UNIQUE CLUSTERED INDEX IX_RegCand_id ON #RegCand(id);
CREATE INDEX IX_RegCand_persid ON #RegCand(persid);

-- [R3] VIDA INTEIRA dos candidatos em dbo.act_log. Traz 'TR' (movimentacao) e
--      'INIT' (criacao). O INIT hoje e auxiliar, mas continua sendo lido no
--      mesmo passe - separar as leituras custaria um segundo passe sobre a
--      tabela para produzir uma coluna de auditoria.
--
--      Esta e a SEGUNDA leitura de act_log do bloco, e ela e necessaria. A
--      primeira ([R2b]) foi por FAIXA DE TEMPO e serviu so para descobrir QUEM
--      sao os candidatos; esta e por call_req_id e traz a VIDA INTEIRA deles.
--
--      call_req_id fica CRU no ON - sem funcao, CAST ou COLLATE - preservando o
--      seek em act_log_x0. Qualquer coercao ali inutiliza o indice sobre uma
--      tabela de ~21 GB.
IF OBJECT_ID('tempdb..#RegAtos') IS NOT NULL DROP TABLE #RegAtos;

SELECT
    c.id, al.system_time,
    CONVERT(varchar(30), al.[type]) COLLATE DATABASE_DEFAULT AS tipo_ato,
    (CONVERT(nvarchar(max), ISNULL(al.description, N'')) + N' ' +
     CONVERT(nvarchar(max), ISNULL(al.action_desc,  N'')))
        COLLATE Latin1_General_CI_AI AS texto
INTO #RegAtos
FROM #RegCand AS c
JOIN dbo.act_log AS al
    ON al.call_req_id = c.persid
   AND al.[type] IN ('TR', 'INIT')
   AND al.system_time IS NOT NULL
OPTION (RECOMPILE);

CREATE CLUSTERED INDEX IX_RegAtos ON #RegAtos(id, system_time);

-- [R4] AUXILIAR - %GROUP= do INIT.
--      Continua sendo extraido, mas nao decide mais DataRegistroCOI. Serve as
--      colunas GrupoInit e InitConsistenteComReconstrucao, que existem para
--      medir quanto o rotulo da abertura concorda com a cadeia reconstruida.
--
--      O valor comeca logo depois do '=' e termina no proximo '%'; sem outro
--      '%', vai ate o fim do texto. A busca e pelo literal '%GROUP=', entao
--      '%CATEGORY=COI...' nunca e lido como grupo e '%SUBGROUP=' tambem nao
--      casa. DATALENGTH/2 em vez de LEN porque LEN descarta espacos a direita e
--      erraria o comprimento no caso sem '%' final.
IF OBJECT_ID('tempdb..#RegInitTag') IS NOT NULL DROP TABLE #RegInitTag;

SELECT
    a.id, a.system_time,
    CONVERT(nvarchar(200), LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(
        UPPER(REPLACE(REPLACE(REPLACE(v.bruto, CHAR(13), N' '), CHAR(10), N' '), CHAR(9), N' ')),
        N' ', N'<>'), N'><', N''), N'<>', N' '))))
        COLLATE DATABASE_DEFAULT AS grupo_init
INTO #RegInitTag
FROM #RegAtos AS a
CROSS APPLY (SELECT p = CHARINDEX(N'%GROUP=', a.texto)) AS t
CROSS APPLY (SELECT ini = t.p + 7) AS s
CROSS APPLY (SELECT fim = CASE WHEN t.p > 0 THEN CHARINDEX(N'%', a.texto, s.ini) ELSE 0 END) AS e
CROSS APPLY (SELECT tam = CASE WHEN t.p = 0 THEN 0
                               WHEN e.fim > s.ini THEN e.fim - s.ini
                               ELSE (DATALENGTH(a.texto) / 2) - s.ini + 1 END) AS n
CROSS APPLY (SELECT bruto = CASE WHEN n.tam > 0
                                 THEN LTRIM(RTRIM(SUBSTRING(a.texto, s.ini, n.tam)))
                                 ELSE N'' END) AS v
WHERE a.tipo_ato = 'INIT'
  AND t.p > 0 AND n.tam > 0 AND LEN(LTRIM(RTRIM(v.bruto))) > 0;

CREATE CLUSTERED INDEX IX_RegInitTag ON #RegInitTag(id, system_time);

-- [R4b] AUXILIAR - assinatura de automacao no evento INIT.
--
--       Le o MESMO texto de [R3] - description + action_desc concatenados, sem
--       truncamento - e produz quatro medidas por evento INIT:
--
--           via_cmd      o log comeca por 'Criado via interface CMD'
--           n_from       quantas vezes '%FROM_USERID=' aparece
--           n_type       quantas vezes '%TYPE=' aparece
--           from_userid  o VALOR de '%FROM_USERID=', normalizado
--
--       POR QUE O CORTE E DIFERENTE DO DE [R4]
--
--       [R4] corta o valor no proximo '%'. Isso funciona para %GROUP= porque
--       %AFFECTED_RC= sempre vem depois dele. Nao funciona para
--       %FROM_USERID=, que costuma ser a ULTIMA tag do INIT: sem um '%'
--       seguinte, o valor absorveria todo o texto restante e 'servicedesk'
--       viraria 'servicedesk Criar solicitacao/incidente/...'.
--
--       Por isso aqui o valor termina no PRIMEIRO de { '%', CR, LF }. Quando
--       nao ha nenhum dos tres, vai ate o fim do texto, e DATALENGTH/2 mede
--       esse fim - LEN descartaria espacos a direita e erraria o comprimento.
--
--       A normalizacao final e a mesma de [R4]: CHAR(13), CHAR(10) e CHAR(9)
--       viram espaco ANTES de qualquer comparacao, espacos repetidos colapsam
--       e o resultado vai para caixa alta. RTRIM sozinho nao removeria a quebra
--       de linha que o valor carrega.
--
--       n_from e n_type contam ocorrencias por diferenca de comprimento: o
--       texto sem a tag e mais curto exatamente (ocorrencias x tamanho da tag).
--       '%FROM_USERID=' tem 13 caracteres e '%TYPE=' tem 6.
IF OBJECT_ID('tempdb..#RegAutoTag') IS NOT NULL DROP TABLE #RegAutoTag;

SELECT
    a.id, a.system_time,
    CONVERT(bit, CASE WHEN CHARINDEX(N'Criado via interface CMD', a.texto) > 0
                      THEN 1 ELSE 0 END) AS via_cmd,
    CONVERT(int, ((DATALENGTH(a.texto) / 2)
                  - (DATALENGTH(REPLACE(a.texto, N'%FROM_USERID=', N'')) / 2)) / 13) AS n_from,
    CONVERT(int, ((DATALENGTH(a.texto) / 2)
                  - (DATALENGTH(REPLACE(a.texto, N'%TYPE=', N'')) / 2)) / 6) AS n_type,
    CONVERT(nvarchar(200), LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(
        UPPER(REPLACE(REPLACE(REPLACE(v.bruto, CHAR(13), N' '), CHAR(10), N' '), CHAR(9), N' ')),
        N' ', N'<>'), N'><', N''), N'<>', N' '))))
        COLLATE DATABASE_DEFAULT AS from_userid
INTO #RegAutoTag
FROM #RegAtos AS a
CROSS APPLY (SELECT p = CHARINDEX(N'%FROM_USERID=', a.texto)) AS t
CROSS APPLY (SELECT ini = t.p + 13) AS s
CROSS APPLY (SELECT fim = CASE WHEN t.p = 0 THEN 0 ELSE z.menor END
             FROM (SELECT menor = MIN(w.p)
                   FROM (VALUES (NULLIF(CHARINDEX(N'%',     a.texto, t.p + 13), 0)),
                                (NULLIF(CHARINDEX(CHAR(13), a.texto, t.p + 13), 0)),
                                (NULLIF(CHARINDEX(CHAR(10), a.texto, t.p + 13), 0))
                        ) AS w(p)) AS z) AS e
CROSS APPLY (SELECT tam = CASE WHEN t.p = 0 THEN 0
                               WHEN e.fim > s.ini THEN e.fim - s.ini
                               ELSE (DATALENGTH(a.texto) / 2) - s.ini + 1 END) AS n
CROSS APPLY (SELECT bruto = CASE WHEN n.tam > 0
                                 THEN LTRIM(RTRIM(SUBSTRING(a.texto, s.ini, n.tam)))
                                 ELSE N'' END) AS v
WHERE a.tipo_ato = 'INIT';

CREATE CLUSTERED INDEX IX_RegAutoTag ON #RegAutoTag(id, system_time);

-- [R5] Ancora de GRUPO nos eventos 'TR'. Troca de grupo e troca de responsavel
--      gravam o MESMO tipo 'TR': sem a ancora, "Transferir Responsavel de 'A'
--      para 'B'" entraria como se fosse movimentacao de fila. Nenhuma das cinco
--      ancoras abaixo casa com esse texto, e e por isso que sao literais e nao
--      um padrao generico.
--
--      #RegRaw guarda TODA linha com ancora, inclusive as que o par de aspas
--      nao conseguir ler. Essa contagem e o que separa "nao houve mudanca de
--      grupo" de "houve mudanca que nao sabemos ler" - distincao que decide se
--      o fallback de estado pode ou nao ser aplicado.
IF OBJECT_ID('tempdb..#RegRaw') IS NOT NULL DROP TABLE #RegRaw;

SELECT
    a.id, a.system_time,
    CONVERT(nvarchar(400), SUBSTRING(a.texto, anc.posicao, 400))
        COLLATE DATABASE_DEFAULT AS resto
INTO #RegRaw
FROM #RegAtos AS a
CROSS APPLY (SELECT p1 = CHARINDEX(N'Grupo de',             a.texto),
                    p2 = CHARINDEX(N'Grupo alterado de',    a.texto),
                    p3 = CHARINDEX(N'Grupo transferido de', a.texto),
                    p4 = CHARINDEX(N'Group from',           a.texto),
                    p5 = CHARINDEX(N'Group changed from',   a.texto)) AS pos
CROSS APPLY (SELECT posicao = CASE
        WHEN pos.p1 > 0 THEN pos.p1 + LEN(N'Grupo de')
        WHEN pos.p2 > 0 THEN pos.p2 + LEN(N'Grupo alterado de')
        WHEN pos.p3 > 0 THEN pos.p3 + LEN(N'Grupo transferido de')
        WHEN pos.p4 > 0 THEN pos.p4 + LEN(N'Group from')
        WHEN pos.p5 > 0 THEN pos.p5 + LEN(N'Group changed from')
        ELSE 0 END) AS anc
WHERE a.tipo_ato = 'TR'
  AND anc.posicao > 0;

CREATE CLUSTERED INDEX IX_RegRaw ON #RegRaw(id, system_time);

-- [R6] Origem e destino pelo par de aspas, com o nome normalizado ao lado.
--      Normalizacao LEVE de proposito: UPPER, trim e espacos colapsados, com a
--      PONTUACAO preservada. '10-COI' e 'CONTRATO 7/2023 - COI' se distinguem
--      justamente por ela. O acento e resolvido na comparacao, por collation.
--
--      ATENCAO: origem VAZIA nao e descartada aqui, e isso e deliberado. O
--      evento "Grupo de '' para 'COI'" prova a ENTRADA mesmo sem provar de onde
--      o chamado veio. Descartar a linha faria o SDM parecer sem cadeia e o
--      empurraria para o fallback - conclusao mais forte que a evidencia.
IF OBJECT_ID('tempdb..#RegEv') IS NOT NULL DROP TABLE #RegEv;

SELECT
    g.id, g.system_time AS evento,
    CONVERT(nvarchar(200), LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(
        UPPER(LTRIM(RTRIM(ori.nome))), N' ', N'<>'), N'><', N''), N'<>', N' '))))
        COLLATE DATABASE_DEFAULT AS origem_norm,
    CONVERT(nvarchar(200), LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(
        UPPER(LTRIM(RTRIM(des.nome))), N' ', N'<>'), N'><', N''), N'<>', N' '))))
        COLLATE DATABASE_DEFAULT AS destino_norm
INTO #RegEv
FROM #RegRaw AS g
CROSS APPLY (SELECT q1 = CHARINDEX(N'''', g.resto)) AS c1
CROSS APPLY (SELECT q2 = CASE WHEN c1.q1 > 0 THEN CHARINDEX(N'''', g.resto, c1.q1 + 1) ELSE 0 END) AS c2
CROSS APPLY (SELECT nome = CASE WHEN c2.q2 > c1.q1
                                THEN SUBSTRING(g.resto, c1.q1 + 1, c2.q2 - c1.q1 - 1) ELSE N'' END) AS ori
CROSS APPLY (SELECT posicao = CASE
        WHEN c2.q2 > 0 AND CHARINDEX(N' para ', g.resto, c2.q2) > 0 THEN CHARINDEX(N' para ', g.resto, c2.q2)
        WHEN c2.q2 > 0 THEN CHARINDEX(N' to ', g.resto, c2.q2)
        ELSE 0 END) AS sep
CROSS APPLY (SELECT q3 = CASE WHEN sep.posicao > 0 THEN CHARINDEX(N'''', g.resto, sep.posicao) ELSE 0 END) AS c3
CROSS APPLY (SELECT q4 = CASE WHEN c3.q3 > 0 THEN CHARINDEX(N'''', g.resto, c3.q3 + 1) ELSE 0 END) AS c4
CROSS APPLY (SELECT nome = CASE WHEN c4.q4 > c3.q3
                                THEN SUBSTRING(g.resto, c3.q3 + 1, c4.q4 - c3.q3 - 1) ELSE N'' END) AS des
WHERE c1.q1 > 0 AND c2.q2 > c1.q1 AND sep.posicao > 0 AND c3.q3 > 0 AND c4.q4 > c3.q3;

CREATE CLUSTERED INDEX IX_RegEv ON #RegEv(id, evento);

-- [R7] UMA linha por SDM com a DataRegistroCOI e a evidencia.
--
--      Todos os APPLY sao TOP (1) ou agregacao escalar: nao ha caminho por onde
--      um SDM se multiplique, e nao ha DISTINCT no final escondendo join que
--      multiplicou. A deduplicacao acontece na modelagem, nao no fim.
--
--      A janela ainda NAO foi aplicada aqui. Isso e proposital: a primeira
--      entrada tem de ser apurada sobre a vida inteira antes de qualquer
--      recorte, senao "primeira entrada" viraria "primeira entrada da janela".
IF OBJECT_ID('tempdb..#RegBase') IS NOT NULL DROP TABLE #RegBase;

SELECT
    c.id, c.ref_num AS SDM, c.tipo, c.open_date, c.abertura_br,
    c.log_agent, c.group_id AS grupo_atual,
    CONVERT(nvarchar(200), ISNULL(gn.nome, N'')) COLLATE DATABASE_DEFAULT AS grupo_atual_nome,
    CONVERT(nvarchar(200), ISNULL(ig.grupo_init, N'')) COLLATE DATABASE_DEFAULT AS grupo_init,
    CONVERT(nvarchar(200), ISNULL(pri.origem_norm,  N'')) COLLATE DATABASE_DEFAULT AS grupo_hist_inicial,
    CONVERT(nvarchar(200), ISNULL(pri.destino_norm, N'')) COLLATE DATABASE_DEFAULT AS grupo_hist_destino,
    pri.evento   AS primeiro_evento_grupo,
    ev.n         AS qtd_evento_grupo,
    anc.n        AS qtd_ancora_grupo,
    -- ancoras ilegiveis antes do 1o evento legivel. Hoje TRAVA apenas o ramo
    -- historico; nos demais viaja como auditoria, para que o efeito de
    -- estende-la a eles seja MEDIDO antes de ser decidido.
    ilg.n        AS qtd_ancora_antes_do_1o,
    ent.entrada  AS primeiro_destino_coi,
    CONVERT(varchar(46), k.evidencia) COLLATE DATABASE_DEFAULT AS evidencia_coi,
    CONVERT(nvarchar(200), k.alias_evid) COLLATE DATABASE_DEFAULT AS alias_evidencia,
    k.data_registro,
    ic.init_consistente,
    CONVERT(nvarchar(40), tp.tipo_automacao) COLLATE DATABASE_DEFAULT AS tipo_automacao
INTO #RegBase
FROM #RegCand AS c
-- nome do grupo ATUAL: coluna de auditoria. Nao entra em nenhuma decisao de
-- evidencia - quem decide o fallback e o UUID, nao o nome de hoje.
OUTER APPLY (SELECT TOP (1) nome = LTRIM(RTRIM(CONCAT(ISNULL(g2.first_name, N''), N' ',
                                                      ISNULL(g2.last_name,  N''))))
             FROM dbo.ca_contact AS g2
             WHERE g2.contact_uuid = c.group_id) AS gn
-- %GROUP= do INIT: AUXILIAR. O primeiro, se houver mais de um evento INIT.
OUTER APPLY (SELECT TOP (1) t.grupo_init
             FROM #RegInitTag AS t
             WHERE t.id = c.id
             ORDER BY t.system_time, t.grupo_init) AS ig
-- assinatura de automacao do PRIMEIRO evento INIT. Mesmo criterio de desempate
-- de 'ig': o INIT mais antigo. Um chamado com varios INIT usa o da criacao.
OUTER APPLY (SELECT TOP (1) u.via_cmd, u.n_from, u.n_type, u.from_userid
             FROM #RegAutoTag AS u
             WHERE u.id = c.id
             ORDER BY u.system_time, u.from_userid) AS au
-- PRIMEIRO evento real de grupo da vida. Origem vazia NAO e filtrada: e o caso
-- em que a entrada se prova pelo destino.
OUTER APPLY (SELECT TOP (1) e.evento, e.origem_norm, e.destino_norm
             FROM #RegEv AS e
             WHERE e.id = c.id
             ORDER BY e.evento, e.origem_norm, e.destino_norm) AS pri
OUTER APPLY (SELECT n = COUNT(*) FROM #RegEv  AS e WHERE e.id = c.id) AS ev
OUTER APPLY (SELECT n = COUNT(*) FROM #RegRaw AS w WHERE w.id = c.id) AS anc
-- ancoras de grupo ANTERIORES ao primeiro evento legivel. Como 'pri' e o mais
-- antigo evento LEGIVEL, toda ancora estritamente anterior a ele e, por
-- definicao, ilegivel - nao precisa de anti-join para descobrir isso.
-- Sem evento legivel algum, conta todas, e o numero coincide com anc.n.
OUTER APPLY (SELECT n = COUNT(*) FROM #RegRaw AS w2
             WHERE w2.id = c.id
               AND w2.system_time < ISNULL(pri.evento, 2147483647)) AS ilg
-- PRIMEIRA entrada da VIDA no universo logico COI, pelo destino. Sem recorte de
-- janela: e isto que faz a reentrada nao contar duas vezes.
OUTER APPLY (SELECT entrada = MIN(e.evento)
             FROM #RegEv AS e
             WHERE e.id = c.id
               AND EXISTS (SELECT 1 FROM #AliasCOI AS a
                           WHERE a.nome_norm COLLATE Latin1_General_CI_AI
                               = e.destino_norm COLLATE Latin1_General_CI_AI)) AS ent
CROSS APPLY (SELECT
        pri_origem_coi = CASE WHEN EXISTS (
            SELECT 1 FROM #AliasCOI AS a
            WHERE a.nome_norm COLLATE Latin1_General_CI_AI
                = pri.origem_norm COLLATE Latin1_General_CI_AI) THEN 1 ELSE 0 END,
        pri_origem_legivel = CASE WHEN NULLIF(pri.origem_norm, N'') IS NOT NULL
                                  THEN 1 ELSE 0 END,
        -- origem = nome POSTERIOR da fila que antes da transicao era o COI
        pri_origem_contrato = CASE WHEN pri.origem_norm COLLATE Latin1_General_CI_AI
                                        = N'CONTRATO 7/2023 - COI' THEN 1 ELSE 0 END,
        atual_novo   = CASE WHEN c.group_id = @COI_UUID_Novo   THEN 1 ELSE 0 END,
        atual_antigo = CASE WHEN c.group_id = @COI_UUID_Antigo THEN 1 ELSE 0 END,
        antes_transicao = CASE WHEN c.open_date <= @TransIniEpoch THEN 1 ELSE 0 END,
        na_janela_transicao = CASE WHEN c.open_date >  @TransIniEpoch
                                    AND c.open_date <= @TransFimEpoch
                                   THEN 1 ELSE 0 END,
        -- o %GROUP= do INIT. Calculado AQUI, antes da hierarquia, porque agora
        -- ele participa como TRAVA - nao como decisor de data.
        init_eh_coi = CASE WHEN EXISTS (
            SELECT 1 FROM #AliasInit AS a
            WHERE a.nome_norm COLLATE Latin1_General_CI_AI
                = ig.grupo_init COLLATE Latin1_General_CI_AI) THEN 1 ELSE 0 END,
        -- INIT existe, e legivel (#RegInitTag so guarda valor nao vazio) e
        -- nomeia fila que nao pertence ao universo COI
        init_contradiz = CASE
            WHEN ig.grupo_init IS NULL THEN 0
            WHEN EXISTS (SELECT 1 FROM #AliasInit AS a
                         WHERE a.nome_norm COLLATE Latin1_General_CI_AI
                             = ig.grupo_init COLLATE Latin1_General_CI_AI) THEN 0
            ELSE 1 END,
        -- o INIT traz o nome que a fila so recebeu NA transicao. Num chamado
        -- aberto antes dela, isso e anomalia - nao compatibilidade.
        init_contrato = CASE WHEN ig.grupo_init COLLATE Latin1_General_CI_AI
                                  = N'CONTRATO 7/2023 - COI' THEN 1 ELSE 0 END,
        -- AUTOMACAO 1 - Task Scheduler / SESUC. UNICA que decide pertencimento.
        -- Os tres termos oficiais precisam valer ao mesmo tempo; nenhum deles
        -- sozinho classifica coisa alguma.
        auto_task_sched = CASE
            WHEN au.via_cmd = 1
             AND au.from_userid COLLATE Latin1_General_CI_AI = N'SERVICEDESK'
             AND EXISTS (SELECT 1 FROM #GrupoTaskSched AS gt
                         WHERE gt.nome_norm COLLATE Latin1_General_CI_AI
                             = ig.grupo_init COLLATE Latin1_General_CI_AI)
            THEN 1 ELSE 0 END,
        -- AUTOMACAO 2 - Zabbix. SO CLASSIFICA. Nao aparece em nenhum ramo da
        -- hierarquia de evidencia nem em data_registro.
        auto_zabbix = CASE
            WHEN @UUID_UsrAutomacoes IS NOT NULL
             AND c.log_agent = @UUID_UsrAutomacoes
             AND c.tipo = 'I'
            THEN 1 ELSE 0 END,
        -- AUTOMACAO 3 - Robo COI / Copilot Studio. SO CLASSIFICA. Assinatura
        -- tecnica OBSERVADA, nao criterio declarado: CMD + %FROM_USERID=
        -- duplicado + %TYPE= presente.
        auto_robo = CASE
            WHEN au.via_cmd = 1 AND au.n_from = 2 AND au.n_type >= 1
            THEN 1 ELSE 0 END) AS f
-- A hierarquia. A cadeia real e consultada PRIMEIRO e vence sempre; o fallback
-- de estado so e alcancado quando nao existe NENHUM evento de grupo.
CROSS APPLY (SELECT
        evidencia = CASE
            WHEN ev.n > 0 AND f.pri_origem_coi = 1
                 THEN 'ABERTO_NO_COI_CADEIA'
            -- TRAVA 1a: INIT anterior a transicao nao pode trazer o nome que a
            -- fila so recebeu depois. Vem ANTES da 1b porque #AliasInit aceita
            -- esse nome e, sozinha, deixaria o caso anomalo passar.
            WHEN ev.n > 0 AND f.pri_origem_contrato = 1 AND f.antes_transicao = 1
                         AND f.init_contrato = 1
                 THEN 'INIT_CONTRATO_INCOMPATIVEL_COM_DATA_ABERTURA'
            -- TRAVA 1b: o registro de abertura nomeia fila nao-COI. A origem
            -- historica nao pode sobrepor evidencia contemporanea da abertura.
            WHEN ev.n > 0 AND f.pri_origem_contrato = 1 AND f.antes_transicao = 1
                         AND f.init_contradiz = 1
                 THEN 'CONTRADICAO_INIT_x_CADEIA'
            -- TRAVA 2: ha ancora ilegivel antes do 1o evento legivel, entao ele
            -- pode nao ser o primeiro da vida e sua origem nao descreve a abertura
            WHEN ev.n > 0 AND f.pri_origem_contrato = 1 AND f.antes_transicao = 1
                         AND ilg.n > 0
                 THEN 'SEM_RECONSTRUCAO_EVENTO_ILEGIVEL'
            -- origem e o rotulo posterior da fila antiga: ja era COI na abertura
            WHEN ev.n > 0 AND f.pri_origem_contrato = 1 AND f.antes_transicao = 1
                 THEN 'JA_ESTAVA_NO_COI_HISTORICO'
            -- origem 'CONTRATO' dentro da janela: o nome nao prova de onde o
            -- chamado veio, mas se ha evento com destino em fila COI a entrada
            -- esta provada e datada. A ambiguidade impede antecipar para
            -- open_date, nao apaga a entrada.
            WHEN ev.n > 0 AND f.pri_origem_contrato = 1 AND f.na_janela_transicao = 1
                         AND ent.entrada IS NOT NULL
                 THEN 'ENTRADA_DEMONSTRAVEL_DESTINO'
            -- sem entrada demonstravel: ai sim nao se sabe SE entrou
            WHEN ev.n > 0 AND f.pri_origem_contrato = 1 AND f.na_janela_transicao = 1
                 THEN 'AMBIGUO_JANELA_TRANSICAO'
            WHEN ev.n > 0 AND f.pri_origem_legivel = 1 AND ent.entrada IS NOT NULL
                 THEN 'TRANSFERIDO_PARA_COI'
            WHEN ev.n > 0 AND ent.entrada IS NOT NULL
                 THEN 'ENTRADA_DEMONSTRAVEL_DESTINO'
            -- AUTOMACAO como ULTIMO recurso do ramo com cadeia: o chamado tem
            -- eventos de grupo, nenhum deles toca o COI, e antes disso ele
            -- terminava em NAO_ENTRA. Nenhum ramo acima muda de resultado.
            WHEN ev.n > 0 AND f.auto_task_sched = 1
                 THEN 'AUTOMACAO_TASK_SCHEDULER'
            WHEN ev.n > 0
                 THEN 'NAO_ENTRA'
            WHEN anc.n > 0
                 THEN 'SEM_RECONSTRUCAO_EVENTO_ILEGIVEL'
            WHEN f.atual_novo = 1
                 THEN 'ABERTO_NO_COI_INFERIDO_GRUPO_ATUAL'
            WHEN f.atual_antigo = 1 AND f.antes_transicao = 1
                 THEN 'ABERTO_NO_COI_INFERIDO_GRUPO_ATUAL_HISTORICO'
            WHEN f.atual_antigo = 1 AND f.na_janela_transicao = 1
                 THEN 'AMBIGUO_JANELA_TRANSICAO'
            -- AUTOMACAO como ULTIMO recurso do ramo sem cadeia: e o caso dos
            -- chamados que nascem direto na fila do NSTI ou do fornecedor e
            -- nunca produzem evento de grupo.
            WHEN f.auto_task_sched = 1
                 THEN 'AUTOMACAO_TASK_SCHEDULER'
            ELSE 'NAO_ENTRA' END,
        alias_evid = CASE
            WHEN ev.n > 0 AND f.pri_origem_coi = 1       THEN pri.origem_norm
            WHEN ev.n > 0 AND f.pri_origem_contrato = 1 AND f.antes_transicao = 1
                         AND f.init_contrato = 1         THEN ig.grupo_init
            WHEN ev.n > 0 AND f.pri_origem_contrato = 1 AND f.antes_transicao = 1
                         AND f.init_contradiz = 1        THEN ig.grupo_init
            WHEN ev.n > 0 AND f.pri_origem_contrato = 1 AND f.antes_transicao = 1
                         AND ilg.n > 0                   THEN N'(ancora ilegivel antes do 1o evento)'
            WHEN ev.n > 0 AND f.pri_origem_contrato = 1 AND f.antes_transicao = 1
                                                         THEN pri.origem_norm
            WHEN ev.n > 0 AND f.pri_origem_contrato = 1 AND f.na_janela_transicao = 1
                         AND ent.entrada IS NOT NULL     THEN N'(destino COI na 1a entrada)'
            WHEN ev.n > 0 AND f.pri_origem_contrato = 1 AND f.na_janela_transicao = 1
                                                         THEN pri.origem_norm
            WHEN ev.n > 0 AND ent.entrada IS NOT NULL    THEN N'(destino COI na 1a entrada)'
            WHEN ev.n > 0 AND f.auto_task_sched = 1      THEN ig.grupo_init
            WHEN ev.n > 0                                THEN NULL
            WHEN anc.n > 0                               THEN N'(evento de grupo ilegivel)'
            WHEN f.atual_novo = 1                        THEN N'COI'
            WHEN f.atual_antigo = 1 AND f.antes_transicao = 1
                                                         THEN N'CONTRATO 7/2023 - COI'
            WHEN f.atual_antigo = 1 AND f.na_janela_transicao = 1
                                                         THEN N'CONTRATO 7/2023 - COI'
            -- a fila em que a automacao registrou. NAO e alias do COI: e o
            -- destino oficial do agendamento, e a coluna diz exatamente isso.
            WHEN f.auto_task_sched = 1                   THEN ig.grupo_init
            ELSE NULL END,
        data_registro = CASE
            WHEN ev.n > 0 AND f.pri_origem_coi = 1       THEN c.open_date
            -- as duas ressalvas recebem data so para poderem ser filtradas por
            -- periodo em #RegRessalvas. Elas nao entram em #Registrados.
            WHEN ev.n > 0 AND f.pri_origem_contrato = 1 AND f.antes_transicao = 1
                         AND f.init_contrato = 1         THEN c.open_date
            WHEN ev.n > 0 AND f.pri_origem_contrato = 1 AND f.antes_transicao = 1
                         AND f.init_contradiz = 1        THEN c.open_date
            WHEN ev.n > 0 AND f.pri_origem_contrato = 1 AND f.antes_transicao = 1
                         AND ilg.n > 0                   THEN c.open_date
            WHEN ev.n > 0 AND f.pri_origem_contrato = 1 AND f.antes_transicao = 1
                                                         THEN c.open_date
            -- dentro da janela COM entrada demonstravel: data e a ENTRADA,
            -- nunca open_date - a abertura nao e demonstravel como 1a entrada
            WHEN ev.n > 0 AND f.pri_origem_contrato = 1 AND f.na_janela_transicao = 1
                         AND ent.entrada IS NOT NULL     THEN ent.entrada
            -- ressalva de janela recebe data so para poder ser filtrada por periodo
            WHEN ev.n > 0 AND f.pri_origem_contrato = 1 AND f.na_janela_transicao = 1
                                                         THEN c.open_date
            WHEN ev.n > 0 AND ent.entrada IS NOT NULL    THEN ent.entrada
            WHEN ev.n > 0 AND f.auto_task_sched = 1      THEN c.open_date
            WHEN ev.n > 0                                THEN NULL
            -- as duas linhas abaixo recebem data SO para poderem ser filtradas
            -- por periodo em #RegRessalvas. Elas nao entram em #Registrados.
            WHEN anc.n > 0                               THEN c.open_date
            WHEN f.atual_novo = 1                        THEN c.open_date
            WHEN f.atual_antigo = 1 AND f.antes_transicao = 1
                                                         THEN c.open_date
            WHEN f.atual_antigo = 1 AND f.na_janela_transicao = 1
                                                         THEN c.open_date
            -- pertencimento exclusivamente por automacao: a data e a ABERTURA.
            -- Nao ha entrada em fila COI para datar, e inventar uma seria pior
            -- do que usar o unico instante demonstravel do registro.
            WHEN f.auto_task_sched = 1                   THEN c.open_date
            ELSE NULL END) AS k
-- auditoria do rotulo: o %GROUP= da abertura concorda com o que a cadeia mostra?
-- f.init_eh_coi ja foi calculado acima, porque a hierarquia precisa dele.
CROSS APPLY (SELECT init_consistente = CASE
        WHEN ig.grupo_init IS NULL THEN NULL
        -- por construcao alias_evidencia = grupo_init neste ramo: o rotulo da
        -- abertura e exatamente a fila que a regra afirma. Nao ha o que
        -- contradizer, com %GROUP=COI ou com qualquer outra fila da lista.
        WHEN k.evidencia = 'AUTOMACAO_TASK_SCHEDULER' THEN CONVERT(bit, 1)
        WHEN f.init_eh_coi = 1 AND k.evidencia IN (
                 'ABERTO_NO_COI_CADEIA',
                 'JA_ESTAVA_NO_COI_HISTORICO',
                 'ABERTO_NO_COI_INFERIDO_GRUPO_ATUAL',
                 'ABERTO_NO_COI_INFERIDO_GRUPO_ATUAL_HISTORICO') THEN CONVERT(bit, 1)
        WHEN f.init_eh_coi = 0 AND k.evidencia NOT IN (
                 'ABERTO_NO_COI_CADEIA',
                 'JA_ESTAVA_NO_COI_HISTORICO',
                 'ABERTO_NO_COI_INFERIDO_GRUPO_ATUAL',
                 'ABERTO_NO_COI_INFERIDO_GRUPO_ATUAL_HISTORICO') THEN CONVERT(bit, 1)
        ELSE CONVERT(bit, 0) END) AS ic
-- MODALIDADE DE AUTOMACAO - coluna INFORMATIVA.
--
--   Nao participa de nenhuma decisao de pertencimento nem de data. Serve para
--   explicar a ORIGEM do registro ao lado de evidencia_coi, que explica por que
--   e quando o chamado entrou.
--
--   As tres assinaturas sao disjuntas nos dados observados - servicedesk contra
--   matricula, %FROM_USERID= unico contra duplicado, CMD contra ausencia de
--   CMD. A ordem do CASE existe so para tornar o resultado determinista caso
--   alguma delas passe a se sobrepor no futuro; a consulta de validacao mede se
--   isso aconteceu, em vez de confiar na ordem.
--
--   'Criado via interface CMD' por servicedesk com %GROUP= FORA da lista
--   oficial fica deliberadamente NAO classificado. A modalidade oficial e a
--   trinca inteira, e a validacao conta esses casos para que a lacuna seja
--   visivel e nao silenciosa.
CROSS APPLY (SELECT tipo_automacao = CASE
        WHEN f.auto_task_sched = 1 THEN N'Task Scheduler / SESUC'
        WHEN f.auto_zabbix     = 1 THEN N'Zabbix Monitor'
        WHEN f.auto_robo       = 1 THEN N'Robo COI'
        ELSE NULL END) AS tp
WHERE k.evidencia <> 'NAO_ENTRA';

CREATE UNIQUE CLUSTERED INDEX IX_RegBase ON #RegBase(id);

-- [R8] A janela e aplicada AGORA, sobre DataRegistroCOI - e nao sobre
--      open_date. E aqui que o eixo temporal do indicador muda de fato.
--
--      As duas categorias de ressalva saem do indicador e vao para
--      #RegRessalvas. Elas nao sao descartadas em silencio: a consulta de
--      validacao as lista, para que a consequencia seja medida e nao suposta.
IF OBJECT_ID('tempdb..#Registrados') IS NOT NULL DROP TABLE #Registrados;

SELECT
    b.id, b.SDM, b.tipo, b.abertura_br, b.log_agent,
    b.grupo_atual, b.grupo_atual_nome,
    b.grupo_init, b.grupo_hist_inicial, b.grupo_hist_destino,
    b.qtd_evento_grupo, b.qtd_ancora_grupo, b.qtd_ancora_antes_do_1o,
    b.init_consistente, b.tipo_automacao,
    b.evidencia_coi, b.alias_evidencia, b.data_registro,
    DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, b.data_registro, @Epoch)) AS registro_br,
    CASE WHEN b.primeiro_evento_grupo IS NULL THEN NULL
         ELSE DATEADD(HOUR, -@HorasBrasilParaUTC,
                      DATEADD(SECOND, b.primeiro_evento_grupo, @Epoch)) END AS primeiro_evento_grupo_br,
    CASE WHEN b.primeiro_destino_coi IS NULL THEN NULL
         ELSE DATEADD(HOUR, -@HorasBrasilParaUTC,
                      DATEADD(SECOND, b.primeiro_destino_coi, @Epoch)) END AS primeira_transf_coi_br,
    CONVERT(bit, CASE WHEN b.open_date < @InicioEpoch THEN 1 ELSE 0 END) AS aberto_antes_periodo,
    CONVERT(bit, CASE WHEN b.data_registro < b.open_date THEN 1 ELSE 0 END) AS anomalia_data
INTO #Registrados
FROM #RegBase AS b
WHERE b.data_registro >= @InicioEpoch
  AND b.data_registro <  @FimEpoch
  AND b.evidencia_coi NOT IN ('AMBIGUO_JANELA_TRANSICAO',
                              'SEM_RECONSTRUCAO_EVENTO_ILEGIVEL',
                              'CONTRADICAO_INIT_x_CADEIA',
                              'INIT_CONTRATO_INCOMPATIVEL_COM_DATA_ABERTURA');

-- Indice NAO unico de proposito: se algum dia a regra passar a duplicar SDM, o
-- erro deve aparecer numa conferencia COUNT(*) x COUNT(DISTINCT SDM), e nao
-- como falha bruta de criacao de indice que esconde o diagnostico.
CREATE CLUSTERED INDEX IX_Registrados ON #Registrados(id);

-- [R9] RESSALVAS - candidatos do periodo que a regra NAO conta, e por que.
--      Existe para que "ficou de fora" seja um numero conferivel, com os SDMs
--      nominais, e nao uma nota de rodape.
IF OBJECT_ID('tempdb..#RegRessalvas') IS NOT NULL DROP TABLE #RegRessalvas;

SELECT
    b.id, b.SDM, b.tipo, b.abertura_br, b.grupo_atual, b.grupo_atual_nome,
    b.grupo_init, b.grupo_hist_inicial, b.grupo_hist_destino,
    b.qtd_evento_grupo, b.qtd_ancora_grupo, b.qtd_ancora_antes_do_1o,
    b.evidencia_coi, b.alias_evidencia, b.tipo_automacao,
    DATEADD(HOUR, -@HorasBrasilParaUTC, DATEADD(SECOND, b.data_registro, @Epoch)) AS referencia_br
INTO #RegRessalvas
FROM #RegBase AS b
WHERE b.data_registro >= @InicioEpoch
  AND b.data_registro <  @FimEpoch
  AND b.evidencia_coi IN ('AMBIGUO_JANELA_TRANSICAO',
                          'SEM_RECONSTRUCAO_EVENTO_ILEGIVEL',
                          'CONTRADICAO_INIT_x_CADEIA',
                          'INIT_CONTRATO_INCOMPATIVEL_COM_DATA_ABERTURA');

CREATE CLUSTERED INDEX IX_RegRessalvas ON #RegRessalvas(id);

--------------------------------------------------------------------------------
-- FIM REGRA CANONICA DE REGISTRADOS COI
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- RESULTADO - uma linha por SDM
--
-- ca_contact e LEFT JOIN e nao pode multiplicar linha: contact_uuid e a chave
-- da tabela. COUNT(*) = COUNT(DISTINCT SDM) continua garantido pela modelagem
-- do bloco canonico, nao por DISTINCT aqui.
--
-- ESTE SELECT E SO PROJECAO. Ele nao filtra, nao agrupa e nao recalcula nada:
-- le #Registrados como o bloco canonico entregou. Nenhuma coluna aqui pode
-- alterar populacao, DataRegistroCOI ou evidencia.
--
-- AS DUAS COLUNAS DE EVIDENCIA, e por que sao duas
--
--   FormaRegistroCOI      texto de negocio, para ler e filtrar no Excel/Power BI
--   EvidenciaRegistroCOI  o rotulo tecnico da hierarquia, sem traducao
--   TipoAutomacaoCOI      a MODALIDADE de automacao que originou o registro
--
--   As duas primeiras respondem POR QUE e QUANDO o chamado entrou no indicador.
--   TipoAutomacaoCOI responde outra coisa: DE ONDE ele veio. Um chamado do
--   Zabbix entra por ABERTO_NO_COI_CADEIA e um do Robo COI tambem - a evidencia
--   nao os distingue, e a modalidade sim. Por isso sao colunas separadas e nao
--   uma so.
--
--   O nome EvidenciaRegistroCOI e PRESERVADO de proposito. Renomea-lo para algo
--   mais curto quebraria consumidores que leem a saida por nome de coluna -
--   Power Query, planilha com cabecalho fixo - sem ganho nenhum.
--
--   A amigavel NAO substitui a tecnica. Duas evidencias tecnicas distintas -
--   ABERTO_NO_COI_INFERIDO_GRUPO_ATUAL e ..._HISTORICO - compartilham o mesmo
--   texto de negocio "Aberto no COI - inferido", porque para quem audita o
--   fallback a distincao entre UUID novo e antigo nao muda a pergunta. Quem
--   precisa separar os dois usa EvidenciaRegistroCOI. Traduzir sem manter a tecnica
--   destruiria essa informacao.
--
--   O ELSE do CASE devolve 'Outro - <rotulo tecnico>' em vez de NULL. Se a
--   hierarquia ganhar um ramo e alguem esquecer de mapea-lo aqui, ele aparece
--   nomeado no resultado - nao some numa celula vazia.
--
-- AS COLUNAS DE AUDITORIA DA RECONSTRUCAO
--
--   PrimeiraOrigemGrupo / PrimeiroDestinoGrupo / DataPrimeiroEventoGrupo e
--   QtdEventosGrupo descrevem a CADEIA, que e a evidencia principal. GrupoInit e
--   InitConsistenteComReconstrucao descrevem o rotulo da abertura, que e
--   auxiliar. Quando os dois discordam, quem vale e a cadeia - e a coluna
--   InitConsistenteComReconstrucao existe justamente para tornar essa
--   discordancia contavel, em vez de invisivel.
--------------------------------------------------------------------------------
SELECT
    -- IDENTIFICACAO E EIXO
    r.SDM,
    r.abertura_br                                   AS DataAbertura,
    r.registro_br                                   AS DataRegistroCOI,

    -- COMO O CHAMADO ENTROU NO INDICADOR
    CONVERT(nvarchar(60), CASE r.evidencia_coi
        WHEN 'ABERTO_NO_COI_CADEIA'
             THEN N'Aberto no COI'
        WHEN 'TRANSFERIDO_PARA_COI'
             THEN N'Transferido para o COI'
        WHEN 'JA_ESTAVA_NO_COI_HISTORICO'
             THEN N'Já estava no COI histórico'
        WHEN 'ENTRADA_DEMONSTRAVEL_DESTINO'
             THEN N'Entrada identificada pelo destino'
        WHEN 'ABERTO_NO_COI_INFERIDO_GRUPO_ATUAL'
             THEN N'Aberto no COI - inferido'
        WHEN 'ABERTO_NO_COI_INFERIDO_GRUPO_ATUAL_HISTORICO'
             THEN N'Aberto no COI - inferido'
        WHEN 'AUTOMACAO_TASK_SCHEDULER'
             THEN N'Registrado por automação do COI'
        ELSE N'Outro - ' + CONVERT(nvarchar(46), r.evidencia_coi)
        END)                                        AS FormaRegistroCOI,
    r.evidencia_coi                                 AS EvidenciaRegistroCOI,
    -- ORIGEM do registro, independente de FormaRegistroCOI/EvidenciaRegistroCOI.
    -- NULL = nenhuma das tres modalidades oficiais reconhecida.
    ISNULL(r.tipo_automacao, N'Não automatizado')   AS TipoAutomacaoCOI,

    -- ROTULO DA ABERTURA E CADEIA, lado a lado com as duas acima
    ISNULL(NULLIF(r.grupo_init, N''), N'(sem %GROUP= no INIT)')         AS GrupoInit,
    ISNULL(NULLIF(r.grupo_hist_inicial, N''), N'(origem não legível)')  AS PrimeiraOrigemGrupo,
    ISNULL(NULLIF(r.grupo_hist_destino, N''), N'(sem evento de grupo)') AS PrimeiroDestinoGrupo,

    -- RECORTES DE TEMPO DERIVADOS DO EIXO
    CONVERT(date, r.registro_br)                    AS DataRegistro,
    DATEPART(HOUR, r.registro_br)                   AS HoraRegistro,

    -- TIPO
    r.tipo                                          AS TipoCodigo,
    CASE r.tipo WHEN 'I' THEN N'Incidente'
                WHEN 'R' THEN N'Solicitação'
                ELSE N'N/A' END                     AS Tipo,

    -- CATEGORIA E RESUMO do registro principal do chamado (call_req), so
    -- informativos: mesma definicao das consultas do Power BI dos outros
    -- nucleos. call_req.id e a chave; prob_ctg.persid e a chave da categoria.
    ISNULL(cat.sym, N'N/A')                         AS Categoria,
    LTRIM(RTRIM(ISNULL(cr.summary, N'')))           AS Resumo,

    -- QUEM ABRIU - auditoria. Nao e o ator que trouxe o chamado para o COI.
    r.log_agent                                     AS RegistradorUUID,
    ISNULL(NULLIF(LTRIM(RTRIM(reg.userid)), N''), N'(não resolvido)') AS RegistradorUserID,
    CASE
        WHEN r.log_agent IS NULL THEN N'(sem registrador no chamado)'
        WHEN reg.contact_uuid IS NULL THEN N'(UUID sem contato em ca_contact)'
        WHEN (ISNULL(reg.first_name, N'') <> N'' OR ISNULL(reg.last_name, N'') <> N'')
            THEN LTRIM(RTRIM(CONCAT(ISNULL(reg.first_name, N''), N' ', ISNULL(reg.last_name, N''))))
        WHEN ISNULL(reg.userid, N'') <> N'' THEN reg.userid
        ELSE N'(contato sem nome)'
    END                                             AS RegistradorNome,

    -- DETALHE DA EVIDENCIA E DA CADEIA
    ISNULL(r.alias_evidencia, N'-')                 AS AliasEvidencia,
    r.primeiro_evento_grupo_br                      AS DataPrimeiroEventoGrupo,
    r.qtd_evento_grupo                              AS QtdEventosGrupo,
    r.qtd_ancora_grupo                              AS QtdAncorasGrupo,
    r.qtd_ancora_antes_do_1o                        AS QtdAncorasAntesDo1oLegivel,
    r.primeira_transf_coi_br                        AS DataPrimeiraEntradaNoCOI,

    -- ESTADO ATUAL - so referencia; decide apenas no ramo de fallback
    r.grupo_atual                                   AS UUIDGrupoAtual,
    ISNULL(NULLIF(r.grupo_atual_nome, N''), N'(não resolvido)')      AS GrupoAtual,

    CASE WHEN r.init_consistente IS NULL THEN N'(sem %GROUP= no INIT)'
         WHEN r.init_consistente = 1     THEN N'sim'
         ELSE N'NAO - cadeia contradiz o INIT' END  AS InitConsistenteComReconstrucao,

    CASE WHEN r.aberto_antes_periodo = 1 THEN N'sim' ELSE N'nao' END AS AbertoAntesDoPeriodo,
    CASE WHEN r.anomalia_data = 1
         THEN N'ANOMALIA: registro anterior a abertura' ELSE N'' END AS Anomalia
FROM #Registrados AS r
LEFT JOIN dbo.ca_contact AS reg
    ON reg.contact_uuid = r.log_agent
LEFT JOIN dbo.call_req AS cr
    ON cr.id = r.id
LEFT JOIN dbo.prob_ctg AS cat
    ON cat.persid = cr.category
ORDER BY
    r.registro_br,
    r.SDM;
